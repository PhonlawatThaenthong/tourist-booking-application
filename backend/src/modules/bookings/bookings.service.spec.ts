import { ForbiddenException } from '@nestjs/common';
import { BookingsService } from './bookings.service';
import { BookingStatus, PaymentStatus } from './booking.entity';
import { UserRole } from '../users/user.entity';

/**
 * Cancelling is staff-only: a customer is refused before anything is read
 * or written, and staff still cancel (and refund) as before.
 */
describe('BookingsService.cancel', () => {
  const BOOKING_ID = '11111111-1111-1111-1111-111111111111';

  function setup() {
    const booking = {
      id: BOOKING_ID,
      customerId: 'customer-1',
      status: BookingStatus.APPROVED,
      paymentStatus: PaymentStatus.PAID,
      checkIn: '2099-01-10',
      checkOut: '2099-01-12',
    };
    const repo = {
      findOne: jest.fn().mockResolvedValue(booking),
      save: jest.fn().mockImplementation(async (b) => b),
    };
    const payments = { recordRefund: jest.fn().mockResolvedValue(undefined) };
    const cache = { invalidateNamespace: jest.fn().mockResolvedValue(undefined) };
    const service = new BookingsService(
      repo as never, {} as never, payments as never, {} as never,
      {} as never, cache as never, {} as never,
    );
    // The response mapping needs relations the fake repo does not load.
    const response = { id: BOOKING_ID } as never;
    jest.spyOn(service, 'getOrFail').mockResolvedValue(response);
    jest
      .spyOn(service as unknown as { availabilityChanged(): Promise<void> }, 'availabilityChanged')
      .mockResolvedValue(undefined);
    return { service, repo, payments, booking, response };
  }

  it('refuses a customer, even on their own booking, without touching it', async () => {
    const { service, repo, payments } = setup();
    await expect(service.cancel(BOOKING_ID, 'customer-1', UserRole.CUSTOMER))
      .rejects.toBeInstanceOf(ForbiddenException);
    expect(repo.findOne).not.toHaveBeenCalled();
    expect(repo.save).not.toHaveBeenCalled();
    expect(payments.recordRefund).not.toHaveBeenCalled();
  });

  it.each([UserRole.STAFF, UserRole.ADMIN])('lets %s cancel and refund a paid booking', async (role) => {
    const { service, repo, payments, booking, response } = setup();
    await expect(service.cancel(BOOKING_ID, 'staff-1', role)).resolves.toBe(response);
    expect(booking.status).toBe(BookingStatus.CANCELLED);
    expect(booking.paymentStatus).toBe(PaymentStatus.REFUNDED);
    expect(repo.save).toHaveBeenCalledTimes(1);
    expect(payments.recordRefund).toHaveBeenCalledWith(BOOKING_ID);
  });
});
