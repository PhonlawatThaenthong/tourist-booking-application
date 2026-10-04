import { Injectable, Logger, ServiceUnavailableException } from '@nestjs/common';
import { randomUUID } from 'crypto';
import { JwtPayload } from '../../common/decorators/current-user.decorator';
import { UserRole } from '../users/user.entity';
import { ChatbotConfig, getChatbotConfig } from '../../config/chatbot.config';
import { ChatbotQueryDto } from './dto/chatbot-query.dto';

export interface ChatbotReply {
  sessionId: string;
  answer: string;
  answered: boolean;
}

const UNAVAILABLE_MESSAGE =
  'แชทบอทไม่พร้อมใช้งานชั่วคราว กรุณาลองใหม่อีกครั้ง หรือโทร 081-598-1199';

/**
 * Thin proxy to the chatbot service. Only `{ sessionId, answer, answered }`
 * reaches the app — the chatbot's sources, scores, tool names and token usage
 * are debug data.
 *
 * Never logs the token, the Authorization header, or the customer's message.
 */
@Injectable()
export class ChatbotService {
  private readonly logger = new Logger(ChatbotService.name);
  private readonly config: ChatbotConfig = getChatbotConfig();

  async query(
    dto: ChatbotQueryDto,
    user: JwtPayload | undefined,
    token: string | undefined,
  ): Promise<ChatbotReply> {
    const sessionId = dto.sessionId ?? randomUUID();
    const headers: Record<string, string> = { 'Content-Type': 'application/json' };
    // Only a customer's token is forwarded — the chatbot uses it for
    // /bookings/me. A staff/admin token would let it read other people's
    // data, so those callers are treated as anonymous.
    if (user?.role === UserRole.CUSTOMER && token) {
      headers.Authorization = `Bearer ${token}`;
    }

    let res: Response;
    try {
      res = await fetch(`${this.config.url}/api/v1/chatbot/query`, {
        method: 'POST',
        headers,
        body: JSON.stringify({
          session_id: sessionId,
          message: dto.message,
          language: dto.language ?? 'th',
        }),
        signal: AbortSignal.timeout(this.config.timeoutMs),
      });
    } catch (err) {
      throw this.unavailable(`request failed: ${errorName(err)}`);
    }

    if (!res.ok) throw this.unavailable(`chatbot responded ${res.status}`);

    let body: unknown;
    try {
      body = await res.json();
    } catch (err) {
      throw this.unavailable(`invalid response body: ${errorName(err)}`);
    }
    if (!isReply(body)) throw this.unavailable('unexpected response shape');

    return { sessionId: body.session_id, answer: body.answer, answered: body.answered };
  }

  private unavailable(reason: string): ServiceUnavailableException {
    this.logger.warn(`Chatbot unavailable: ${reason}`);
    return new ServiceUnavailableException(UNAVAILABLE_MESSAGE);
  }
}

function isReply(
  body: unknown,
): body is { session_id: string; answer: string; answered: boolean } {
  if (typeof body !== 'object' || body === null) return false;
  const b = body as Record<string, unknown>;
  return typeof b.session_id === 'string'
    && typeof b.answer === 'string'
    && typeof b.answered === 'boolean';
}

/** e.g. "TimeoutError" or "TypeError (ECONNREFUSED)" — never the message body. */
function errorName(err: unknown): string {
  const e = err as { name?: string; cause?: { code?: string } } | undefined;
  const code = e?.cause?.code;
  return `${e?.name ?? 'Error'}${code ? ` (${code})` : ''}`;
}
