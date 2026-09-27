import { Injectable, Logger } from '@nestjs/common';
import { InjectQueue } from '@nestjs/bullmq';
import { InjectRepository } from '@nestjs/typeorm';
import { Queue } from 'bullmq';
import { Repository } from 'typeorm';
import { Booking } from '../bookings/booking.entity';
import { NotificationChannel, NotificationLog, NotificationStatus } from './notification-log.entity';
import { withQueueTimeout } from '../../config/redis.config';

export const NOTIFICATIONS_QUEUE = 'notifications';
export const BOOKING_CONFIRMATION_JOB = 'booking-confirmation';

export interface BookingConfirmationJobData {
  notificationLogId: string;
}

/**
 * What a booking-confirmation email says, frozen when it is queued so the
 * `notifications_log` row records exactly what the guest was told.
 */
export interface BookingConfirmationPayload {
  bookingId: string;
  customerName: string;
  roomName: string;
  checkIn: string;
  checkOut: string;
  guests: number;
  totalPrice: number;
}

@Injectable()
export class NotificationsService {
  private readonly logger = new Logger(NotificationsService.name);

  constructor(
    @InjectRepository(NotificationLog) private readonly repo: Repository<NotificationLog>,
    @InjectQueue(NOTIFICATIONS_QUEUE) private readonly queue: Queue<BookingConfirmationJobData>,
  ) {}

  /**
   * Writes the `queued` row first, then hands only its id to the job — the
   * worker re-reads the row rather than carrying the payload through the
   * queue, so retries always see the latest `attempts`/`status`.
   */
  async sendBookingConfirmation(booking: Booking, recipient: string): Promise<void> {
    const payload: BookingConfirmationPayload = {
      bookingId: booking.id,
      customerName: booking.customer?.name ?? '',
      roomName: booking.room?.name ?? '',
      checkIn: booking.checkIn,
      checkOut: booking.checkOut,
      guests: booking.guests,
      totalPrice: Number(booking.totalPrice),
    };
    const log = await this.repo.save(this.repo.create({
      bookingId: booking.id,
      channel: NotificationChannel.EMAIL,
      recipient,
      payload: { ...payload },
      status: NotificationStatus.QUEUED,
    }));

    try {
      await withQueueTimeout(this.queue.add(
        BOOKING_CONFIRMATION_JOB,
        { notificationLogId: log.id },
        {
          attempts: 3,
          backoff: { type: 'exponential', delay: 2000 },
          // notifications_log is the audit trail, so Redis only keeps a few
          // failed jobs around for debugging.
          removeOnComplete: true,
          removeOnFail: 100,
        },
      ));
    } catch (err) {
      // Redis unavailable. The caller (payment verification) has already
      // committed, so never fail it over a notification — record why instead.
      this.logger.warn(`could not queue notification ${log.id}: ${err}`);
      log.status = NotificationStatus.FAILED;
      log.lastError = err instanceof Error ? err.message : String(err);
      await this.repo.save(log);
    }
  }
}
