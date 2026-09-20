import { BadRequestException, ConflictException, Injectable, NotFoundException } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { QueryFailedError, Repository } from 'typeorm';
import { Room, RoomStatus } from './room.entity';
import { CreateRoomDto } from './dto/create-room.dto';
import { UpdateRoomDto } from './dto/update-room.dto';
import { QueryRoomsDto } from './dto/query-rooms.dto';

/** Postgres foreign_key_violation — a room still referenced by a booking. */
const PG_FOREIGN_KEY_VIOLATION = '23503';

@Injectable()
export class RoomsService {
  constructor(
    @InjectRepository(Room) private readonly repo: Repository<Room>,
  ) {}

  /**
   * `GET /api/rooms`. With a date range, returns only rooms that have no
   * live booking overlapping it — the same `[)` half-open semantics as the
   * exclusion constraint, so search and insert can never disagree.
   * No cache yet: that is Sprint 4.
   */
  async search(q: QueryRoomsDto): Promise<Room[]> {
    const { checkIn, checkOut } = this.normalizeRange(q.checkIn, q.checkOut);

    const qb = this.repo
      .createQueryBuilder('r')
      .where('r.status = :status', { status: RoomStatus.AVAILABLE });

    if (q.type) qb.andWhere('r.type = :type', { type: q.type });
    if (q.guests) qb.andWhere('r.capacity >= :guests', { guests: q.guests });

    if (checkIn && checkOut) {
      qb.andWhere(
        `NOT EXISTS (
           SELECT 1 FROM bookings b
           WHERE b.room_id = r.id
             AND b.status <> 'cancelled'
             AND daterange(b.check_in, b.check_out, '[)')
                 && daterange(CAST(:checkIn AS date), CAST(:checkOut AS date), '[)')
         )`,
        { checkIn, checkOut },
      );
    }

    return qb.orderBy('r.price_per_night', 'ASC').addOrderBy('r.name', 'ASC').getMany();
  }

  /**
   * Booked date-ranges (roomId + check-in/out only — no customer data) for all
   * non-cancelled bookings overlapping [from, to). With no window, returns every
   * live booking. Powers the customer-side availability views.
   */
  async bookedRanges(
    from?: string,
    to?: string,
  ): Promise<{ roomId: string; checkIn: string; checkOut: string }[]> {
    const iso = /^\d{4}-\d{2}-\d{2}$/;
    if ((from && !iso.test(from)) || (to && !iso.test(to))) {
      throw new BadRequestException('from/to ต้องเป็นวันที่รูปแบบ YYYY-MM-DD');
    }
    const windowed = Boolean(from && to);
    return this.repo.manager.query(
      `SELECT room_id AS "roomId",
              check_in::text  AS "checkIn",
              check_out::text AS "checkOut"
         FROM bookings
        WHERE status <> 'cancelled'
          AND (
            $1::boolean = false
            OR daterange(check_in, check_out, '[)')
               && daterange($2::date, $3::date, '[)')
          )
        ORDER BY room_id, check_in`,
      [windowed, from ?? null, to ?? null],
    );
  }

  async getOrFail(id: string): Promise<Room> {
    const room = await this.repo.findOne({ where: { id } });
    if (!room) throw new NotFoundException('ไม่พบห้องพัก');
    return room;
  }

  create(dto: CreateRoomDto): Promise<Room> {
    const room = this.repo.create({
      ...dto,
      description: dto.description ?? '',
      imageUrls: dto.imageUrls ?? [],
      amenities: dto.amenities ?? [],
      status: dto.status ?? RoomStatus.AVAILABLE,
    });
    return this.repo.save(room);
  }

  async update(id: string, dto: UpdateRoomDto): Promise<Room> {
    const room = await this.getOrFail(id);
    Object.assign(room, dto);
    return this.repo.save(room);
  }

  /**
   * Hard delete. The FK is ON DELETE RESTRICT, so a room with booking history
   * cannot vanish and orphan it — staff should set `maintenance` instead.
   */
  async remove(id: string): Promise<void> {
    const room = await this.getOrFail(id);
    try {
      await this.repo.remove(room);
    } catch (err) {
      if (err instanceof QueryFailedError
        && (err.driverError as { code?: string }).code === PG_FOREIGN_KEY_VIOLATION) {
        throw new ConflictException(
          'ลบไม่ได้: ห้องนี้มีประวัติการจองอยู่ ให้เปลี่ยนสถานะเป็น maintenance แทน',
        );
      }
      throw err;
    }
  }

  /** Both dates or neither; check-out must be strictly after check-in. */
  private normalizeRange(checkIn?: string, checkOut?: string) {
    if (!checkIn && !checkOut) return { checkIn: undefined, checkOut: undefined };
    if (!checkIn || !checkOut) {
      throw new BadRequestException('ต้องระบุทั้ง checkIn และ checkOut');
    }
    if (checkOut <= checkIn) {
      throw new BadRequestException('checkOut ต้องมาหลัง checkIn');
    }
    return { checkIn, checkOut };
  }
}
