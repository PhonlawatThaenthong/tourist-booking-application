import { Injectable, NotFoundException, OnModuleInit } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { promises as fs } from 'fs';
import { join } from 'path';
import { Repository } from 'typeorm';
import { Restaurant } from './restaurant.entity';
import { CreateRestaurantDto } from './dto/create-restaurant.dto';
import { UpdateRestaurantDto } from './dto/update-restaurant.dto';
import {
  imageContentType, imageExtension, UploadedImage, uploadRoot,
} from '../../common/uploaded-image';

/** Photos live beside the payment slips, under the same UPLOAD_DIR volume. */
const IMAGE_SUBDIR = 'restaurants';

@Injectable()
export class RestaurantsService implements OnModuleInit {
  private readonly uploadDir = uploadRoot();

  constructor(
    @InjectRepository(Restaurant) private readonly repo: Repository<Restaurant>,
  ) {}

  async onModuleInit(): Promise<void> {
    await fs.mkdir(join(this.uploadDir, IMAGE_SUBDIR), { recursive: true });
  }

  /** `GET /api/restaurants`. No filters yet — the app lists all of them. */
  findAll(): Promise<Restaurant[]> {
    return this.repo.find({ order: { rating: 'DESC' } });
  }

  async getOrFail(id: string): Promise<Restaurant> {
    const restaurant = await this.repo.findOne({ where: { id } });
    if (!restaurant) throw new NotFoundException('ไม่พบร้านอาหาร');
    return restaurant;
  }

  create(dto: CreateRestaurantDto): Promise<Restaurant> {
    return this.repo.save(this.repo.create(dto));
  }

  async update(id: string, dto: UpdateRestaurantDto): Promise<Restaurant> {
    const restaurant = await this.getOrFail(id);
    Object.assign(restaurant, dto);
    return this.repo.save(restaurant);
  }

  /**
   * `POST /api/staff/restaurants/:id/image`. Same image rules as a payment
   * slip (PNG/JPG/WEBP). Replaces any earlier photo.
   */
  async setImage(id: string, file: UploadedImage | undefined): Promise<Restaurant> {
    const ext = imageExtension(file);
    const restaurant = await this.getOrFail(id);
    const relPath = join(IMAGE_SUBDIR, `${id}.${ext}`);
    await fs.writeFile(join(this.uploadDir, relPath), file!.buffer);

    // An earlier photo with a different extension would otherwise linger.
    if (restaurant.imagePath && restaurant.imagePath !== relPath) {
      await fs.rm(join(this.uploadDir, restaurant.imagePath), { force: true });
    }
    restaurant.imagePath = relPath;
    // Always bump updated_at, even when re-uploading to the same path: it is
    // what changes the `v` in the photo URL and busts the app's cache.
    restaurant.updatedAt = new Date();
    return this.repo.save(restaurant);
  }

  /** Absolute path + content type of the uploaded photo, for streaming. */
  async getImageFile(id: string): Promise<{ path: string; contentType: string }> {
    const restaurant = await this.getOrFail(id);
    if (!restaurant.imagePath) throw new NotFoundException('ร้านนี้ยังไม่มีรูป');
    return {
      path: join(this.uploadDir, restaurant.imagePath),
      contentType: imageContentType(restaurant.imagePath),
    };
  }

  /** No booking history ever references a restaurant, so this is a plain hard delete. */
  async remove(id: string): Promise<void> {
    const restaurant = await this.getOrFail(id);
    await this.repo.remove(restaurant);
    if (restaurant.imagePath) {
      await fs.rm(join(this.uploadDir, restaurant.imagePath), { force: true });
    }
  }
}
