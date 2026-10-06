import { IsDateString, IsEnum, IsOptional } from 'class-validator';
import { BookingStatus } from '../booking.entity';

/**
 * `PATCH /api/staff/bookings/:id` — serves both Flutter calls:
 * `updateStatus` sends `status`, `reschedule` sends the two dates.
 */
export class UpdateBookingDto {
  @IsOptional() @IsEnum(BookingStatus)
  status?: BookingStatus;

  @IsOptional() @IsDateString({ strict: true })
  checkIn?: string;

  @IsOptional() @IsDateString({ strict: true })
  checkOut?: string;
}
