import {
  BadRequestException, ConflictException, Injectable, NotFoundException, OnModuleInit,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { randomUUID } from 'crypto';
import { existsSync, promises as fs } from 'fs';
import { join } from 'path';
import { QueryFailedError, Repository } from 'typeorm';
import {
  imageContentType, imageExtension, UploadedImage, uploadRoot,
} from '../../common/uploaded-image';
import { Room, RoomStatus } from './room.entity';
import { CreateRoomDto } from './dto/create-room.dto';
import { UpdateRoomDto } from './dto/update-room.dto';
import { QueryRoomsDto } from './dto/query-rooms.dto';

/** Postgres foreign_key_violation — a room still referenced by a booking. */
const PG_FOREIGN_KEY_VIOLATION = '23503';

/**
 * Uploaded room photos. Each is stored as `<roomId>-<uuid>.<ext>` and listed
 * in `image_urls` as its API path, beside any bundled `image/...` assets.
 * A fresh name per upload means a new photo never hits a stale cache entry.
 */
const ROOM_IMAGE_SUBDIR = 'rooms';
const ROOM_IMAGE_FILE = /^[0-9a-f-]{36}-[0-9a-f-]{36}\.(jpg|png|webp)$/;
/** Same cap as the imageUrls DTOs. */
const MAX_ROOM_IMAGES = 20;

function roomImageUrl(roomId: string, file: string): string {
  return `/api/rooms/${roomId}/images/${file}`;
}

@Injectable()
export class RoomsService implements OnModuleInit {
  private readonly imageDir = join(uploadRoot(), ROOM_IMAGE_SUBDIR);

  constructor(
    @InjectRepository(Room) private readonly repo: Repository<Room>,
  ) {}

  async onModuleInit(): Promise<void> {
    await fs.mkdir(this.imageDir, { recursive: true });
  }

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
    const before = room.imageUrls;
    Object.assign(room, dto);
    const saved = await this.repo.save(room);
    // A photo dropped from the list is gone for good; do not leave its file.
    if (dto.imageUrls) {
      await this.deleteUploadedFiles(id, before.filter((u) => !saved.imageUrls.includes(u)));
    }
    return saved;
  }

  /** `POST /api/staff/rooms/:id/images` — appends one uploaded photo. */
  async addImage(id: string, file: UploadedImage | undefined): Promise<Room> {
    const ext = imageExtension(file);
    const room = await this.getOrFail(id);
    if (room.imageUrls.length >= MAX_ROOM_IMAGES) {
      throw new BadRequestException(`ห้องหนึ่งมีรูปได้ไม่เกิน ${MAX_ROOM_IMAGES} รูป`);
    }
    const name = `${id}-${randomUUID()}.${ext}`;
    await fs.writeFile(join(this.imageDir, name), file!.buffer);
    room.imageUrls = [...room.imageUrls, roomImageUrl(id, name)];
    return this.repo.save(room);
  }

  /**
   * Absolute path + content type for `GET /api/rooms/:id/images/:file`.
   * Only names this service generates are accepted, so the file parameter can
   * never reach outside the room photo folder.
   */
  getImageFile(id: string, file: string): { path: string; contentType: string } {
    if (!ROOM_IMAGE_FILE.test(file) || !file.startsWith(`${id}-`)) {
      throw new NotFoundException('ไม่พบรูป');
    }
    const path = join(this.imageDir, file);
    if (!existsSync(path)) throw new NotFoundException('ไม่พบรูป');
    return { path, contentType: imageContentType(file) };
  }

  /** Removes the files behind this room's uploaded-photo URLs; others are ignored. */
  private async deleteUploadedFiles(id: string, urls: string[]): Promise<void> {
    const prefix = roomImageUrl(id, '');
    for (const url of urls) {
      if (!url.startsWith(prefix)) continue;
      const file = url.slice(prefix.length);
      if (ROOM_IMAGE_FILE.test(file)) {
        await fs.rm(join(this.imageDir, file), { force: true });
      }
    }
  }

  /**
   * Hard delete. The FK is ON DELETE RESTRICT, so a room with booking history
   * cannot vanish and orphan it — staff should set `maintenance` instead.
   */
  async remove(id: string): Promise<void> {
    const room = await this.getOrFail(id);
    try {
      await this.repo.remove(room);
      await this.deleteUploadedFiles(id, room.imageUrls);
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
