import {
  Body, Controller, Get, HttpCode, Param, ParseUUIDPipe, Post, UploadedFile,
  UseGuards, UseInterceptors,
} from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import { BookingsService } from './bookings.service';
import { CreateBookingDto } from './dto/create-booking.dto';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { CurrentUser, JwtPayload } from '../../common/decorators/current-user.decorator';
import { getPaymentConfig } from '../../config/payment.config';
import { UploadedSlip } from '../payments/payment.response';

/** Customer-facing bookings. The customer is always taken from the JWT. */
@Controller('bookings')
@UseGuards(JwtAuthGuard)
export class BookingsController {
  constructor(private readonly bookings: BookingsService) {}

  @Post()
  create(@CurrentUser() user: JwtPayload, @Body() dto: CreateBookingDto) {
    return this.bookings.create(user.sub, dto);
  }

  @Get('me')
  mine(@CurrentUser() user: JwtPayload) {
    return this.bookings.findForCustomer(user.sub);
  }

  /**
   * Upload the PromptPay transfer slip (multipart/form-data, field `slip`).
   * This records the slip and moves the payment to `awaiting_verification`; a
   * staff member confirms it before the booking is marked paid.
   */
  @Post(':id/pay')
  @HttpCode(200)
  @UseInterceptors(FileInterceptor('slip', {
    limits: { fileSize: getPaymentConfig().maxSlipBytes },
  }))
  pay(
    @CurrentUser() user: JwtPayload,
    @Param('id', ParseUUIDPipe) id: string,
    @UploadedFile() slip: UploadedSlip | undefined,
  ) {
    return this.bookings.submitSlip(id, user.sub, user.role, slip);
  }

  @Get(':id/payment')
  payment(@CurrentUser() user: JwtPayload, @Param('id', ParseUUIDPipe) id: string) {
    return this.bookings.getPaymentForCustomer(id, user.sub, user.role);
  }

  /**
   * Staff/admin only (a customer gets 403 and is told to contact the
   * resort). Kept on this path because a staff token passes JwtAuthGuard
   * here too; the role check lives in BookingsService.cancel.
   */
  @Post(':id/cancel')
  @HttpCode(200)
  cancel(@CurrentUser() user: JwtPayload, @Param('id', ParseUUIDPipe) id: string) {
    return this.bookings.cancel(id, user.sub, user.role);
  }
}
