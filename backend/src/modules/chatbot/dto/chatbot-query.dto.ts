import { Transform } from 'class-transformer';
import { IsIn, IsNotEmpty, IsOptional, IsString, MaxLength } from 'class-validator';

export const CHATBOT_LANGUAGES = ['th', 'en'] as const;
export type ChatbotLanguage = (typeof CHATBOT_LANGUAGES)[number];

export class ChatbotQueryDto {
  // Trimmed first so a whitespace-only message is rejected as empty.
  @Transform(({ value }: { value: unknown }) => (typeof value === 'string' ? value.trim() : value))
  @IsString() @IsNotEmpty() @MaxLength(1000)
  message!: string;

  /** Omit on the first message; reuse the one the response returns. */
  @IsOptional() @IsString() @MaxLength(100)
  sessionId?: string;

  @IsOptional() @IsIn(CHATBOT_LANGUAGES)
  language?: ChatbotLanguage = 'th';
}
