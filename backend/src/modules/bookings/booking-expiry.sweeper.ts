import { Injectable, Logger, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { DataSource } from 'typeorm';
import { getBookingHoldMs, getBookingSweepMs } from '../../config/booking.config';

/**
 * Safety-net timer that releases abandoned holds. Every `BOOKING_SWEEP_SECONDS`
 * it cancels any pending/unpaid booking older than the hold window that has no
 * slip uploaded — a single UPDATE, no Redis. This backs up the per-booking
 * BullMQ job so a slot is freed even if that job never fired (Redis was down
 * when the booking was created, or the app restarted).
 */
@Injectable()
export class BookingExpirySweeper implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(BookingExpirySweeper.name);
  private readonly sweepMs = getBookingSweepMs();
  private timer?: ReturnType<typeof setInterval>;

  constructor(private readonly dataSource: DataSource) {}

  onModuleInit(): void {
    const holdSeconds = Math.round(getBookingHoldMs() / 1000);
    this.logger.log(
      `active — releasing unpaid holds older than ${holdSeconds}s, every ${this.sweepMs / 1000}s`,
    );
    // Run once now so a stuck hold from before startup clears immediately.
    this.sweep().catch((e) => this.logger.warn(`initial sweep failed: ${e}`));
    this.timer = setInterval(() => {
      this.sweep().catch((e) => this.logger.warn(`sweep failed: ${e}`));
    }, this.sweepMs);
    this.timer.unref?.();
  }

  onModuleDestroy(): void {
    if (this.timer) clearInterval(this.timer);
  }

  private async sweep(): Promise<void> {
    // Compute the cutoff in JS instead of with SQL make_interval — avoids any
    // bound-parameter type ambiguity, and compares timestamptz to timestamptz.
    const cutoff = new Date(Date.now() - getBookingHoldMs());
    const result = await this.dataSource.query(
      `UPDATE bookings b
          SET status = 'cancelled', updated_at = now()
        WHERE b.status = 'pending'
          AND b.payment_status = 'unpaid'
          AND b.created_at < $1
          AND NOT EXISTS (
            SELECT 1 FROM payments p
             WHERE p.booking_id = b.id AND p.slip_path IS NOT NULL
          )`,
      [cutoff],
    );
    const count = Array.isArray(result) ? result[1] : undefined;
    if (typeof count === 'number' && count > 0) {
      this.logger.log(`released ${count} expired booking hold(s)`);
    }
  }
}
