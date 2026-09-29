import {
  Controller, Get, Param, ParseUUIDPipe, Query, StreamableFile,
} from '@nestjs/common';
import { createReadStream } from 'fs';
import { RoomsService } from './rooms.service';
import { QueryRoomsDto } from './dto/query-rooms.dto';

/** Public catalogue — browsing rooms does not require a login. */
@Controller('rooms')
export class RoomsController {
  constructor(private readonly rooms: RoomsService) {}

  @Get()
  find(@Query() query: QueryRoomsDto) {
    return this.rooms.search(query);
  }

  /**
   * Anonymised booked date-ranges across ALL customers, so the app can show
   * true availability (search + month calendar) without exposing who booked.
   * Declared before ':id' so 'availability' is not parsed as a room id.
   */
  @Get('availability')
  availability(@Query('from') from?: string, @Query('to') to?: string) {
    return this.rooms.bookedRanges(from, to);
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
