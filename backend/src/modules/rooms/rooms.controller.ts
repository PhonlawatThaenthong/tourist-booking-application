import {
  Controller, Get, Param, ParseUUIDPipe, Query, Res, StreamableFile,
} from '@nestjs/common';
import type { Response } from 'express';
import { createReadStream } from 'fs';
import { RoomsService } from './rooms.service';
import { QueryRoomsDto } from './dto/query-rooms.dto';

/** Public catalogue — browsing rooms does not require a login. */
@Controller('rooms')
export class RoomsController {
  constructor(private readonly rooms: RoomsService) {}

  /** `X-Cache: HIT | MISS | BYPASS` shows whether Redis answered (see RedisCacheService). */
  @Get()
  async find(@Query() query: QueryRoomsDto, @Res({ passthrough: true }) res: Response) {
    const { value, status } = await this.rooms.search(query);
    res.setHeader('X-Cache', status);
    return value;
  }

  /**
   * Anonymised booked date-ranges across ALL customers, so the app can show
   * true availability (search + month calendar) without exposing who booked.
   * Declared before ':id' so 'availability' is not parsed as a room id.
   */
  @Get('availability')
  async availability(
    @Res({ passthrough: true }) res: Response,
    @Query('from') from?: string,
    @Query('to') to?: string,
  ) {
    const { value, status } = await this.rooms.bookedRanges(from, to);
    res.setHeader('X-Cache', status);
    return value;
  }

  @Get(':id')
  findOne(@Param('id', ParseUUIDPipe) id: string) {
    return this.rooms.getOrFail(id);
  }

  /** `GET /api/rooms/:id/images/:file` — a photo staff uploaded; public, like the catalogue. */
  @Get(':id/images/:file')
  image(
    @Param('id', ParseUUIDPipe) id: string,
    @Param('file') file: string,
  ): StreamableFile {
    const { path, contentType } = this.rooms.getImageFile(id, file);
    return new StreamableFile(createReadStream(path), { type: contentType });
  }
}
