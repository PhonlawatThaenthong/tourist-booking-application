/** BullMQ queue that holds delayed "release this unpaid booking" jobs. */
export const BOOKING_EXPIRY_QUEUE = 'booking-expiry';

/**
 * How long a freshly created, still-unpaid booking holds its room before it is
 * auto-cancelled and the slot is released. Configurable via `BOOKING_HOLD_MINUTES`
 * (minutes); defaults to 3. A booking whose slip has already been uploaded is
 * NOT expired — it is waiting for staff verification.
 */
export function getBookingHoldMs(): number {
  const minutes = Number(process.env.BOOKING_HOLD_MINUTES ?? 3);
  const safe = Number.isFinite(minutes) && minutes > 0 ? minutes : 3;
  return Math.round(safe * 60_000);
}
