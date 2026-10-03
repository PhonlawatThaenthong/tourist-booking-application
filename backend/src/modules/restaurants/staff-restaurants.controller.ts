import {
  Body, Controller, Delete, HttpCode, Param, ParseUUIDPipe, Patch, Post, UploadedFile,
  UseGuards, UseInterceptors,
} from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import { RestaurantsService } from './restaurants.service';
import { toRestaurantResponse } from './restaurant.response';
import { UploadedImage } from '../../common/uploaded-image';
import { CreateRestaurantDto } from './dto/create-restaurant.dto';
import { UpdateRestaurantDto } from './dto/update-restaurant.dto';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { RolesGuard } from '../../common/guards/roles.guard';
import { Roles } from '../../common/decorators/roles.decorator';
import { UserRole } from '../users/user.entity';

/** Restaurant listing administration. */
@Controller('staff/restaurants')
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles(UserRole.STAFF, UserRole.ADMIN)
export class StaffRestaurantsController {
  constructor(private readonly restaurants: RestaurantsService) {}

  @Post()
  async create(@Body() dto: CreateRestaurantDto) {
    return toRestaurantResponse(await this.restaurants.create(dto));
  }

  @Patch(':id')
  async update(@Param('id', ParseUUIDPipe) id: string, @Body() dto: UpdateRestaurantDto) {
    return toRestaurantResponse(await this.restaurants.update(id, dto));
  }

  /** Upload or replace the photo (multipart/form-data, field `image`). */
  @Post(':id/image')
  @HttpCode(200)
  @UseInterceptors(FileInterceptor('image'))
  async uploadImage(
    @Param('id', ParseUUIDPipe) id: string,
    @UploadedFile() image: UploadedImage | undefined,
  ) {
    return toRestaurantResponse(await this.restaurants.setImage(id, image));
  }

  @Delete(':id')
  @HttpCode(204)
  async remove(@Param('id', ParseUUIDPipe) id: string): Promise<void> {
    await this.restaurants.remove(id);
  }
}
