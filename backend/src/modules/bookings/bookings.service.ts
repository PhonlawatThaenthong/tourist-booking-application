import {
  BadRequestException, ConflictException, ForbiddenException, Injectable, NotFoundException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { InjectQueue } from '@nestjs/bullmq';
import { Queue } from 'bullmq';
import { DataSource, QueryFailedError, Repository } from 'typeorm';
import { Booking, BookingStatus, PaymentStatus } from './booking.entity';
import { Room, RoomStatus } from '../rooms/room.entity';
import { CreateBookingDto } from './dto/create-booking.dto';
import { UpdateBookingDto } from './dto/update-booking.dto';
import { BookingResponse, nightsBetween, toBookingResponse } from './booking.response';
import { UserRole } from '../users/user.entity';
import { PaymentsService } from '../payments/payments.service';
import {
  CustomerPaymentView, StaffPaymentView, toCustomerPaymentView, toStaffPaymentView,
  UploadedSlip,
} from '../payments/payment.response';
import { NotificationsService } from '../notifications/notifications.service';
import { BOOKING_EXPIRY_QUEUE, getBookingHoldMs } from '../../config/booking.config';

/** Postgres SQLSTATEs that both mean "someone else got this range first". */
const PG_EXCLUSION_VIOLATION = '23P01';
const PG_SERIALIZATION_FAILURE = '40001';

const RELATIONS = { room: true, customer: true } as const;

@Injectable()
export class BookingsService {
  constructor(
    @InjectRepository(Booking) private readonly repo: Repository<Booking>,
    private readonly dataSource: DataSource,
    private readonly payments: PaymentsService,
    private readonly notifications: NotificationsService,
    @InjectQueue(BOOKING_EXPIRY_QUEUE) private readonly expiryQueue: Queue,
  ) {}

  private readonly holdMs = getBookingHoldMs();

  /**
   * `POST /api/bookings`.
   *
   * SERIALIZABLE is the belt; `EXC_bookings_no_overlap` is the braces. The
   * constraint alone already makes a double booking physically impossible —
   * the isolation level is what keeps the read of the room row (price,
   * capacity, status) consistent with the write that depends on it.
   *
   * Both failure codes map to 409, because from the client's point of view
   * they are the same event: the range was taken. No retry loop here — a retry
   * would silently book a range the customer saw as free a moment ago, so the
   * app re-queries and lets the customer choose.
   */
  async create(customerId: string, dto: CreateBookingDto): Promise<BookingResponse> {
    this.assertRange(dto.checkIn, dto.checkOut);

    try {
      const id = await this.dataSource.transaction('SERIALIZABLE', async (manager) => {
        const room = await manager.getRepository(Room).findOne({ where: { id: dto.roomId } });
        if (!room) throw new NotFoundException('ไม่พบห้องพัก');
        if (room.status !== RoomStatus.AVAILABLE) {
          throw new ConflictException('ห้องนี้ปิดปรับปรุงอยู่');
        }
        if (dto.guests > room.capacity) {
          throw new BadRequestException(`ห้องนี้รองรับได้สูงสุด ${room.capacity} คน`);
        }

        const nights = nightsBetween(dto.checkIn, dto.checkOut);
        const booking = manager.getRepository(Booking).create({
          roomId: room.id,
          customerId,
          checkIn: dto.checkIn,
          checkOut: dto.checkOut,
          guests: dto.guests,
          // Priced from the row just read inside this transaction, never from
          // anything the client sent.
          totalPrice: Number((room.pricePerNight * nights).toFixed(2)),
          status: BookingStatus.PENDING,
          paymentStatus: PaymentStatus.UNPAID,
        });

        const saved = await manager.getRepository(Booking).save(booking);
        return saved.id;
      });

      await this.scheduleExpiry(id);
      return this.getOrFail(id);
    } catch (err) {
      throw this.translateConflict(err);
    }
  }

  /**
   * Best-effort hold timer: schedule a delayed job to release the slot if the
   * booking is never paid. Wrapped so a Redis outage never fails the booking —
   * the slot just won't auto-release in that case.
   */
  private async scheduleExpiry(bookingId: string): Promise<void> {
    try {
      await this.expiryQueue.add(
        'expire',
        { bookingId },
        {
          delay: this.holdMs,
          jobId: `expire:${bookingId}`,
          removeOnComplete: true,
          removeOnFail: true,
        },
      );
    } catch {
      // Redis unavailable — ignore; booking creation must still succeed.
    }
  }

  /**
   * Auto-cancel an abandoned booking. Runs from the delayed queue job. No-op
   * unless the booking is still pending/unpaid with no slip uploaded, so a paid,
   * cancelled, or awaiting-verification booking is never touched.
   */
  async expireIfUnpaid(bookingId: string): Promise<void> {
    const booking = await this.repo.findOne({ where: { id: bookingId } });
    if (!booking) return;
    if (booking.status !== BookingStatus.PENDING
      || booking.paymentStatus !== PaymentStatus.UNPAID) {
      return;
    }
    const payment = await this.payments.findForBooking(bookingId);
    if (payment && payment.slipPath) return; // slip uploaded — leave for staff
    booking.status = BookingStatus.CANCELLED;
    await this.repo.save(booking);
  }

  /** `GET /api/bookings/me` */
  async findForCustomer(customerId: string): Promise<BookingResponse[]> {
    const rows = await this.repo.find({
      where: { customerId },
      relations: RELATIONS,
      order: { checkIn: 'DESC' },
    });
    return rows.map(toBookingResponse);
  }

  /** `GET /api/staff/bookings` */
  async findAll(): Promise<BookingResponse[]> {
    const rows = await this.repo.find({ relations: RELATIONS, order: { checkIn: 'DESC' } });
    return rows.map(toBookingResponse);
  }

  async getOrFail(id: string): Promise<BookingResponse> {
    const booking = await this.repo.findOne({ where: { id }, relations: RELATIONS });
    if (!booking) throw new NotFoundException('ไม่พบการจอง');
    return toBookingResponse(booking);
  }

  /**
   * `POST /api/bookings/:id/pay` — the customer uploads a PromptPay transfer
   * slip. This does NOT mark the booking paid: it records the slip and moves
   * the payment to `awaiting_verification`. A staff member confirms it later
   * (`verifyPayment`), which is the only path that flips the booking to paid.
   */
  async submitSlip(
    id: string,
    actorId: string,
    actorRole: UserRole,
    file: UploadedSlip | undefined,
  ): Promise<CustomerPaymentView> {
    if (!file) throw new BadRequestException('กรุณาแนบไฟล์สลิป (field: slip)');

    const booking = await this.loadOwned(id, actorId, actorRole);
    if (booking.status === BookingStatus.CANCELLED) {
      throw new ConflictException('การจองนี้ถูกยกเลิกแล้ว');
    }
    if (booking.paymentStatus === PaymentStatus.PAID) {
      throw new ConflictException('การจองนี้ชำระเงินเรียบร้อยแล้ว');
    }

    const payment = await this.payments.submitSlip(booking.id, booking.totalPrice, file);
    return toCustomerPaymentView(payment);
  }

  /** `GET /api/bookings/:id/payment` — the customer polls their payment state. */
  async getPaymentForCustomer(
    id: string,
    actorId: string,
    actorRole: UserRole,
  ): Promise<CustomerPaymentView> {
    await this.loadOwned(id, actorId, actorRole);
    const payment = await this.payments.findForBooking(id);
    if (!payment) throw new NotFoundException('ยังไม่มีการชำระเงินสำหรับการจองนี้');
    return toCustomerPaymentView(payment);
  }

  /**
   * `PATCH /api/staff/payments/:id` with action=approve. Staff confirmed the
   * slip: mark the payment succeeded, flip the booking to paid/approved, and
   * queue the confirmation notification — the same side effects the old stub
   * `pay` endpoint used to do instantly, now gated behind a human check.
   */
  async verifyPayment(paymentId: string, adminId: string): Promise<StaffPaymentView> {
    const payment = await this.payments.getOrFail(paymentId);
    const booking = await this.repo.findOne({
      where: { id: payment.bookingId },
      relations: { customer: true },
    });
    if (!booking) throw new NotFoundException('ไม่พบการจอง');
    if (booking.status === BookingStatus.CANCELLED) {
      throw new ConflictException('การจองนี้ถูกยกเลิกแล้ว');
    }

    await this.payments.markVerified(paymentId, adminId);

    booking.paymentStatus = PaymentStatus.PAID;
    booking.status = BookingStatus.APPROVED;
    await this.repo.save(booking);

    await this.notifications.sendBookingConfirmation(booking, booking.customer.email);

    return toStaffPaymentView(await this.payments.getOrFail(paymentId));
  }

  /** `PATCH /api/staff/payments/:id` with action=reject. */
  async rejectPayment(
    paymentId: string,
    adminId: string,
    reason: string,
  ): Promise<StaffPaymentView> {
    if (!reason?.trim()) {
      throw new BadRequestException('กรุณาระบุเหตุผลที่ปฏิเสธสลิป');
    }
    await this.payments.markRejected(paymentId, adminId, reason.trim());
    return toStaffPaymentView(await this.payments.getOrFail(paymentId));
  }

  /** `PATCH /api/staff/bookings/:id` — status transition and/or reschedule. */
  async update(id: string, dto: UpdateBookingDto): Promise<BookingResponse> {
    if (dto.status === undefined && dto.checkIn === undefined && dto.checkOut === undefined) {
      throw new BadRequestException('ไม่มีข้อมูลที่จะแก้ไข');
    }
    if ((dto.checkIn === undefined) !== (dto.checkOut === undefined)) {
      throw new BadRequestException('การเลื่อนวันต้องระบุทั้ง checkIn และ checkOut');
    }

    try {
      await this.dataSource.transaction('SERIALIZABLE', async (manager) => {
        const bookings = manager.getRepository(Booking);
        const booking = await bookings.findOne({ where: { id }, relations: { room: true } });
        if (!booking) throw new NotFoundException('ไม่พบการจอง');

        if (dto.checkIn && dto.checkOut) {
          this.assertRange(dto.checkIn, dto.checkOut);
          booking.checkIn = dto.checkIn;
          booking.checkOut = dto.checkOut;
          // Re-priced from the stored nightly rate, as the repository contract
          // in booking_repository.dart states.
          booking.totalPrice = Number(
            (booking.room.pricePerNight * nightsBetween(dto.checkIn, dto.checkOut)).toFixed(2),
          );
        }
        if (dto.status) booking.status = dto.status;

        await bookings.save(booking);
      });
    } catch (err) {
      throw this.translateConflict(err);
    }

    return this.getOrFail(id);
  }

  /** A customer cancelling their own booking. */
  async cancel(id: string, actorId: string, actorRole: UserRole): Promise<BookingResponse> {
    const booking = await this.repo.findOne({ where: { id } });
    if (!booking) throw new NotFoundException('ไม่พบการจอง');
    if (actorRole === UserRole.CUSTOMER && booking.customerId !== actorId) {
      throw new ForbiddenException('ไม่มีสิทธิ์เข้าถึงการจองนี้');
    }

    const wasPaid = booking.paymentStatus === PaymentStatus.PAID;
    booking.status = BookingStatus.CANCELLED;
    if (wasPaid) {
      booking.paymentStatus = PaymentStatus.REFUNDED;
    }
    await this.repo.save(booking);
    if (wasPaid) {
      await this.payments.recordRefund(booking.id);
    }
    return this.getOrFail(id);
  }

  private async loadOwned(id: string, actorId: string, actorRole: UserRole): Promise<Booking> {
    const booking = await this.repo.findOne({ where: { id } });
    if (!booking) throw new NotFoundException('ไม่พบการจอง');
    if (actorRole === UserRole.CUSTOMER && booking.customerId !== actorId) {
      throw new ForbiddenException('ไม่มีสิทธิ์เข้าถึงการจองนี้');
    }
    return booking;
  }

  private assertRange(checkIn: string, checkOut: string): void {
    if (checkOut <= checkIn) {
      throw new BadRequestException('checkOut ต้องมาหลัง checkIn');
    }
  }

  /**
   * Turns the two "you lost the race" SQLSTATEs into a 409 the Flutter
   * `RepositoryException(statusCode: 409)` already knows how to display.
   */
  private translateConflict(err: unknown): unknown {
    if (err instanceof QueryFailedError) {
      const code = (err.driverError as { code?: string }).code;
      if (code === PG_EXCLUSION_VIOLATION || code === PG_SERIALIZATION_FAILURE) {
        return new ConflictException('ห้องนี้ถูกจองในช่วงวันที่เลือกแล้ว');
      }
    }
    return err;
  }
}
