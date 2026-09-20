import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { BullModule } from '@nestjs/bullmq';
import { Booking } from './booking.entity';
import { BookingsService } from './bookings.service';
import { BookingsController } from './bookings.controller';
import { StaffBookingsController } from './staff-bookings.controller';
import { StaffPaymentActionsController } from './staff-payment-actions.controller';
import { BookingExpiryProcessor } from './booking-expiry.processor';
import { RoomsModule } from '../rooms/rooms.module';
import { PaymentsModule } from '../payments/payments.module';
import { NotificationsModule } from '../notifications/notifications.module';
import { BOOKING_EXPIRY_QUEUE } from '../../config/booking.config';

@Module({
  imports: [
    TypeOrmModule.forFeature([Booking]),
    BullModule.registerQueue({ name: BOOKING_EXPIRY_QUEUE }),
    RoomsModule,
    PaymentsModule,
    NotificationsModule,
  ],
  controllers: [BookingsController, StaffBookingsController, StaffPaymentActionsController],
  providers: [BookingsService, BookingExpiryProcessor],
  exports: [BookingsService],
})
export class BookingsModule {}
