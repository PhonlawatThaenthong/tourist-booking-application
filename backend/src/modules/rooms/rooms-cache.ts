/**
 * Cache namespace for the public room catalogue: `GET /api/rooms` (search)
 * and `GET /api/rooms/availability`. Both answers depend on rooms AND bookings,
 * so every write that can change which room is free on which night must call
 * `RedisCacheService.invalidate(ROOMS_CACHE_NAMESPACE)` after it commits:
 *
 * - RoomsService            create / update / addImage / remove
 * - BookingsService         create / update (status, reschedule) / cancel / expireIfUnpaid
 * - BookingExpirySweeper    when it released at least one hold
 *
 * Check-in, check-out and payment approval do not change availability (the
 * exclusion constraint counts every status except `cancelled`), so they don't.
 * A write that bypasses these paths (seed scripts, manual SQL) shows up once
 * the TTL (`CACHE_TTL_SECONDS`) runs out.
 */
export const ROOMS_CACHE_NAMESPACE = 'rooms';
