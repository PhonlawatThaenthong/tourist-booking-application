import {
  Body, Controller, Delete, Get, HttpCode, Param, ParseUUIDPipe, Patch, Post, UploadedFile,
  UseGuards, UseInterceptors,
} from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import { UploadedImage } from '../../common/uploaded-image';
import { RoomsService } from './rooms.service';
import { CreateRoomDto } from './dto/create-room.dto';
import { UpdateRoomDto } from './dto/update-room.dto';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { RolesGuard } from '../../common/guards/roles.guard';
import { Roles } from '../../common/decorators/roles.decorator';
import { UserRole } from '../users/user.entity';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { Room } from './room.entity';

/** Room administration. Staff see maintenance rooms too, customers never do. */
@Controller('staff/rooms')
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles(UserRole.STAFF, UserRole.ADMIN)
export class StaffRoomsController {
  constructor(
    private readonly rooms: RoomsService,
    @InjectRepository(Room) private readonly repo: Repository<Room>,
  ) {}

  @Get()
  findAll() {
    return this.repo.find({ order: { name: 'ASC' } });
  }

  @Post()
  create(@Body() dto: CreateRoomDto) {
    return this.rooms.create(dto);
  }

  @Patch(':id')
  update(@Param('id', ParseUUIDPipe) id: string, @Body() dto: UpdateRoomDto) {
    return this.rooms.update(id, dto);
  }

  /** Add one photo (multipart/form-data, field `image`); it goes to the end of the list. */
  @Post(':id/images')
  @HttpCode(200)
  @UseInterceptors(FileInterceptor('image'))
  addImage(
    @Param('id', ParseUUIDPipe) id: string,
    @UploadedFile() image: UploadedImage | undefined,
  ) {
    return this.rooms.addImage(id, image);
  }

  @Delete(':id')
  @HttpCode(204)
  async remove(@Param('id', ParseUUIDPipe) id: string): Promise<void> {
    await this.rooms.remove(id);
  }
}
