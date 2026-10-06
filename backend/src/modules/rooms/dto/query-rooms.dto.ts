import { Type } from 'class-transformer';
import { IsDateString, IsEnum, IsInt, IsOptional, Min } from 'class-validator';
import { RoomType } from '../room.entity';

/** `GET /api/rooms?checkIn=&checkOut=&guests=&type=` */
export class QueryRoomsDto {
  @IsOptional() @IsDateString({ strict: true }, { message: 'checkIn ต้องอยู่ในรูปแบบ YYYY-MM-DD' })
  checkIn?: string;

  @IsOptional() @IsDateString({ strict: true }, { message: 'checkOut ต้องอยู่ในรูปแบบ YYYY-MM-DD' })
  checkOut?: string;

  @IsOptional() @Type(() => Number) @IsInt() @Min(1)
  guests?: number;

  @IsOptional() @IsEnum(RoomType)
  type?: RoomType;
}
