import {
  Body, Controller, Get, HttpCode, Param, ParseUUIDPipe, Patch, Post, UseGuards,
} from '@nestjs/common';
import { BookingsService } from './bookings.service';
import { UpdateBookingDto } from './dto/update-booking.dto';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { RolesGuard } from '../../common/guards/roles.guard';
import { Roles } from '../../common/decorators/roles.decorator';
import { UserRole } from '../users/user.entity';

@Controller('staff/bookings')
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles(UserRole.STAFF, UserRole.ADMIN)
export class StaffBookingsController {
  constructor(private readonly bookings: BookingsService) {}

  @Get()
  findAll() {
    return this.bookings.findAll();
  }

  @Get(':id')
  findOne(@Param('id', ParseUUIDPipe) id: string) {
    return this.bookings.getOrFail(id);
  }

  @Patch(':id')
  update(@Param('id', ParseUUIDPipe) id: string, @Body() dto: UpdateBookingDto) {
    return this.bookings.update(id, dto);
  }

  @Post(':id/check-in')
  @HttpCode(200)
  checkIn(@Param('id', ParseUUIDPipe) id: string) {
    return this.bookings.checkIn(id);
  }

  @Post(':id/check-out')
  @HttpCode(200)
  checkOut(@Param('id', ParseUUIDPipe) id: string) {
    return this.bookings.checkOut(id);
  }
}
