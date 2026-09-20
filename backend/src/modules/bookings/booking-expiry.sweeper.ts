import { Injectable, Logger, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { DataSource } from 'typeorm';
import { getBookingHoldMs, getBookingSweepMs } from '../../config/booking.config';

/**
 * Safety-net timer that releases abandoned holds. Every `BOOKING_SWEEP_SECONDS`
 * it cancels any pending/unpaid booking older than the hold window that has no
 * slip uploaded — a single UPDATE, no Redis. This backs up the per-booking
 * BullMQ job so a slot is freed even if that job never fired.
 */
@Injectable()
export class BookingExpirySweeper implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(BookingExpirySweeper.name);
  private readonly holdSeconds = Math.round(getBookingHoldMs() / 1000);
  private readonly sweepMs = getBookingSweepMs();
  private timer?: ReturnType<typeof setInterval>;

  constructor(private readonly dataSource: DataSource) {}

  onModuleInit(): void {
    this.timer = setInterval(() => {
      this.sweep().catch((e) => this.logger.warn(`sweep failed: ${e}`));
    }, this.sweepMs);
    // Do not keep the process alive just for this timer.
    this.timer.unref?.();
  }

  onModuleDestroy(): void {
    if (this.timer) clearInterval(this.timer);
  }

  private async sweep(): Promise<void> {
    const result = await this.dataSource.query(
      `UPDATE bookings b
          SET status = 'cancelled', updated_at = now()
        WHERE b.status = 'pending'
          AND b.payment_status = 'unpaid'
          AND b.created_at < now() - make_interval(secs => $1)
          AND NOT EXISTS (
            SELECT 1 FROM payments p
             WHERE p.booking_id = b.id AND p.slip_path IS NOT NULL
          )`,
      [this.holdSeconds],
    );
    // node-postgres returns [rows, rowCount] via TypeORM for UPDATE ... (no RETURNING)
    const count = Array.isArray(result) ? result[1] : undefined;
    if (typeof count === 'number' && count > 0) {
      this.logger.log(`released ${count} expired booking hold(s)`);
    }
  }
}
