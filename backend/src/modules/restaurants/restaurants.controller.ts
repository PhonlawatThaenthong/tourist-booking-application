import {
  Controller, Get, Param, ParseUUIDPipe, StreamableFile,
} from '@nestjs/common';
import { createReadStream } from 'fs';
import { RestaurantsService } from './restaurants.service';
import { toRestaurantResponse } from './restaurant.response';

/** Public catalogue — browsing restaurants does not require a login. */
@Controller('restaurants')
export class RestaurantsController {
  constructor(private readonly restaurants: RestaurantsService) {}

  @Get()
  async findAll() {
    return (await this.restaurants.findAll()).map(toRestaurantResponse);
  }

  @Get(':id')
  async findOne(@Param('id', ParseUUIDPipe) id: string) {
    return toRestaurantResponse(await this.restaurants.getOrFail(id));
  }

  /** `GET /api/restaurants/:id/image` — the uploaded photo, public like the listing. */
  @Get(':id/image')
  async image(@Param('id', ParseUUIDPipe) id: string): Promise<StreamableFile> {
    const { path, contentType } = await this.restaurants.getImageFile(id);
    return new StreamableFile(createReadStream(path), { type: contentType });
  }
}
