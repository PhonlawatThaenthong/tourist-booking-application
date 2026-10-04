import { Body, Controller, HttpCode, Post, Req, UseGuards } from '@nestjs/common';
import { Throttle } from '@nestjs/throttler';
import { Request } from 'express';
import { OptionalJwtAuthGuard } from '../../common/guards/optional-jwt-auth.guard';
import { JwtPayload } from '../../common/decorators/current-user.decorator';
import { ChatbotQueryDto } from './dto/chatbot-query.dto';
import { ChatbotService } from './chatbot.service';

@Controller('chatbot')
export class ChatbotController {
  constructor(private readonly chatbot: ChatbotService) {}

  // Login optional: guests can ask about rooms, prices and policies.
  // This is where the LLM cost is, so it gets the tight limit. Per IP: the
  // global throttler runs before route guards, so the user is not known yet.
  @Post('query')
  @HttpCode(200)
  @UseGuards(OptionalJwtAuthGuard)
  @Throttle({ default: { limit: 10, ttl: 60_000 } })
  query(@Body() dto: ChatbotQueryDto, @Req() req: Request) {
    const user = req.user as JwtPayload | undefined;
    return this.chatbot.query(dto, user, bearerToken(req.headers.authorization));
  }
}

function bearerToken(header: string | undefined): string | undefined {
  const match = header?.match(/^Bearer\s+(\S+)$/i);
  return match?.[1];
}
