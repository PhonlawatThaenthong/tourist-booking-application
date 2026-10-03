import { Type } from 'class-transformer';
import { IsNumber, IsOptional, IsString, Length, Max, Min } from 'class-validator';

export class CreateRestaurantDto {
  @IsString() @Length(1, 120)
  name!: string;

  @IsString() @Length(1, 60)
  cuisine!: string;

  @Type(() => Number) @IsNumber({ maxDecimalPlaces: 1 }) @Min(0) @Max(5)
  rating!: number;

  @IsString() @Length(1, 10)
  priceRange!: string;

  @IsString() @Length(1, 4000)
  description!: string;

  /** Optional now that photos are uploaded to POST /staff/restaurants/:id/image. */
  @IsOptional() @IsString() @Length(0, 500)
  imageUrl?: string;

  @IsString() @Length(1, 255)
  address!: string;

  @Type(() => Number) @IsNumber({ maxDecimalPlaces: 6 }) @Min(-90) @Max(90)
  latitude!: number;

  @Type(() => Number) @IsNumber({ maxDecimalPlaces: 6 }) @Min(-180) @Max(180)
  longitude!: number;
}
