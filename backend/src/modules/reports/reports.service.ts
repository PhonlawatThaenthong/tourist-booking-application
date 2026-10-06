import { BadRequestException, Injectable } from '@nestjs/common';
import { DataSource } from 'typeorm';
import { RoomType } from '../rooms/room.entity';
import { ReportRangeDto, RevenueGroupBy, RevenueQueryDto } from './dto/report-query.dto';

const MAX_RANGE_DAYS = 366;

export interface RevenuePoint {
  /** `YYYY-MM-DD` when grouped by day, `YYYY-MM` when grouped by month. */
  period: string;
  revenue: number;
}

export interface RevenueReport {
  from: string;
  to: string;
  groupBy: RevenueGroupBy;
  total: number;
  /** Paid bookings with at least one night inside the range. */
  paidBookings: number;
  /** One entry per period in the range, zero-filled so a chart has no gaps. */
  series: RevenuePoint[];
}

export interface OccupancyStat {
  rooms: number;
  availableNights: number;
  bookedNights: number;
  /** Percentage, 0–100, one decimal. */
  rate: number;
}

export interface OccupancyReport {
  from: string;
  to: string;
  days: number;
  overall: OccupancyStat;
  byType: Array<OccupancyStat & { type: RoomType }>;
}

/**
 * Both reports work in room-nights, the same unit the booking ranges and the
 * exclusion constraint use, so they always agree with availability.
 */
@Injectable()
export class ReportsService {
  constructor(private readonly ds: DataSource) {}

  /**
   * Revenue from paid bookings, recognised per night stayed: a booking's
   * `total_price` is nightly rate × nights, so each night carries an equal
   * share. A stay that crosses the range boundary or a month boundary is
   * split exactly instead of landing entirely on its check-in date.
   */
  async revenue(q: RevenueQueryDto): Promise<RevenueReport> {
    rangeDays(q);
    const groupBy = q.groupBy ?? 'day';

    const rows: Array<{ period: string; revenue: number }> = await this.ds.query(
      `
      WITH nights AS (
        SELECT n::date AS night,
               b.total_price / (b.check_out - b.check_in) AS nightly
        FROM bookings b
        CROSS JOIN LATERAL generate_series(
          GREATEST(b.check_in, $1::date)::timestamp,
          LEAST(b.check_out - 1, $2::date)::timestamp,
          interval '1 day'
        ) AS n
        WHERE b.payment_status = 'paid'
          AND b.check_in <= $2::date
          AND b.check_out > $1::date
      ),
      periods AS (
        SELECT DISTINCT date_trunc($3, d)::date AS period
        FROM generate_series($1::date::timestamp, $2::date::timestamp, interval '1 day') AS d
      )
      SELECT to_char(p.period, CASE WHEN $3 = 'month' THEN 'YYYY-MM' ELSE 'YYYY-MM-DD' END) AS period,
             ROUND(COALESCE(SUM(n.nightly), 0), 2)::float8 AS revenue
      FROM periods p
      LEFT JOIN nights n ON date_trunc($3, n.night)::date = p.period
      GROUP BY p.period
      ORDER BY p.period
      `,
      [q.from, q.to, groupBy],
    );

    const [{ count }] = await this.ds.query<Array<{ count: number }>>(
      `SELECT count(*)::int AS count FROM bookings
       WHERE payment_status = 'paid' AND check_in <= $2::date AND check_out > $1::date`,
      [q.from, q.to],
    );

    const total = rows.reduce((sum, r) => sum + r.revenue, 0);
    return {
      from: q.from,
      to: q.to,
      groupBy,
      total: Math.round(total * 100) / 100,
      paidBookings: count,
      series: rows,
    };
  }

  /**
   * Occupancy = booked room-nights / sellable room-nights × 100, overall and
   * per room type. A night counts as booked when any non-cancelled booking
   * holds it — the same rule that blocks it from being sold again.
   *
   * Rooms under maintenance are left out of both sides, so a closed room does
   * not drag the rate down. `status` is the room's current state, not
   * historical: a room closed today is excluded from past ranges too.
   */
  async occupancy(q: ReportRangeDto): Promise<OccupancyReport> {
    const days = rangeDays(q);

    const rows: Array<{ type: RoomType; rooms: number; booked_nights: number }> =
      await this.ds.query(
        `
        SELECT r.type,
               count(*)::int AS rooms,
               COALESCE(SUM(bn.nights), 0)::int AS booked_nights
        FROM rooms r
        LEFT JOIN LATERAL (
          SELECT SUM(LEAST(b.check_out, $2::date + 1) - GREATEST(b.check_in, $1::date)) AS nights
          FROM bookings b
          WHERE b.room_id = r.id
            AND b.status <> 'cancelled'
            AND b.check_in <= $2::date
            AND b.check_out > $1::date
        ) bn ON true
        WHERE r.status = 'available'
        GROUP BY r.type
        `,
        [q.from, q.to],
      );

    const byType = Object.values(RoomType).map((type) => {
      const row = rows.find((r) => r.type === type);
      return { type, ...stat(row?.rooms ?? 0, row?.booked_nights ?? 0, days) };
    });
    const overall = stat(
      byType.reduce((n, t) => n + t.rooms, 0),
      byType.reduce((n, t) => n + t.bookedNights, 0),
      days,
    );

    return { from: q.from, to: q.to, days, overall, byType };
  }
}

function stat(rooms: number, bookedNights: number, days: number): OccupancyStat {
  const availableNights = rooms * days;
  const rate = availableNights === 0 ? 0 : (bookedNights / availableNights) * 100;
  return { rooms, availableNights, bookedNights, rate: Math.round(rate * 10) / 10 };
}

/** Inclusive day count; also rejects reversed or oversized ranges. */
function rangeDays({ from, to }: ReportRangeDto): number {
  const days = (Date.parse(`${to}T00:00:00Z`) - Date.parse(`${from}T00:00:00Z`)) / 86_400_000 + 1;
  if (days < 1) {
    throw new BadRequestException('วันที่สิ้นสุด (to) ต้องไม่อยู่ก่อนวันที่เริ่มต้น (from)');
  }
  if (days > MAX_RANGE_DAYS) {
    throw new BadRequestException(`ช่วงวันที่ต้องไม่เกิน ${MAX_RANGE_DAYS} วัน`);
  }
  return days;
}
