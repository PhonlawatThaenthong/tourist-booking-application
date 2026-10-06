import { Type } from 'class-transformer';
import { IsDateString, IsInt, IsUUID, Max, Min } from 'class-validator';

/**
 * `POST /api/bookings`.
 *
 * Note what is NOT here: totalPrice, customerId, roomName. The price is
 * recomputed server-side from the stored nightly rate and the customer comes
 * from the JWT — a client must not be able to name its own price or book on
 * someone else's behalf. The Flutter `createAndPay` still sends those fields
 * today; `forbidNonWhitelisted` would reject them, so Sprint 3 trims the
 * request body when `ApiBookingRepository` lands.
 */
export class CreateBookingDto {
  @IsUUID()
  roomId!: string;

  @IsDateString({ strict: true }, { message: 'checkIn ต้องอยู่ในรูปแบบ YYYY-MM-DD' })
  checkIn!: string;

  @IsDateString({ strict: true }, { message: 'checkOut ต้องอยู่ในรูปแบบ YYYY-MM-DD' })
  checkOut!: string;

  @Type(() => Number) @IsInt() @Min(1) @Max(20)
  guests!: number;
}
