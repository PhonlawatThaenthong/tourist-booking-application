import { Processor, WorkerHost } from '@nestjs/bullmq';
import { Job } from 'bullmq';
import { BookingsService } from './bookings.service';
import { BOOKING_EXPIRY_QUEUE } from '../../config/booking.config';

export interface BookingExpiryJobData {
  bookingId: string;
}

/**
 * Fires once, `BOOKING_HOLD_MINUTES` after a booking is created. It releases the
 * room only if the booking is still pending/unpaid AND no slip was uploaded —
 * otherwise it is either paid, cancelled, or waiting for staff verification, and
 * is left alone.
 */
@Processor(BOOKING_EXPIRY_QUEUE)
export class BookingExpiryProcessor extends WorkerHost {
  constructor(private readonly bookings: BookingsService) {
    super();
  }

  async process(job: Job<BookingExpiryJobData>): Promise<void> {
    await this.bookings.expireIfUnpaid(job.data.bookingId);
  }
}
