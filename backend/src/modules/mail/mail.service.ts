import { Injectable, Logger } from '@nestjs/common';
import * as nodemailer from 'nodemailer';

/**
 * No transactional-email provider existed anywhere in the codebase before
 * this — the notifications module only ever stubbed sending. Configured via
 * SMTP_* env vars; with SMTP_HOST unset (local/dev), it logs the message
 * instead of sending, the same fallback the notifications stub used.
 */
@Injectable()
export class MailService {
  private readonly logger = new Logger(MailService.name);
  private readonly transporter: nodemailer.Transporter | null;

  constructor() {
    const host = process.env.SMTP_HOST;
    if (!host) {
      this.transporter = null;
      return;
    }
    const port = Number(process.env.SMTP_PORT ?? 587);
    this.transporter = nodemailer.createTransport({
      host,
      port,
      secure: port === 465,
      auth: process.env.SMTP_USER
        ? { user: process.env.SMTP_USER, pass: process.env.SMTP_PASSWORD }
        : undefined,
    });
  }

  async sendPasswordResetCode(to: string, code: string): Promise<void> {
    const ttlMinutes = process.env.RESET_TOKEN_TTL_MINUTES ?? '15';
    const subject = 'รหัสยืนยันการรีเซ็ตรหัสผ่าน';
    const text = [
      `รหัสยืนยันของคุณคือ: ${code}`,
      `รหัสนี้จะหมดอายุใน ${ttlMinutes} นาที`,
      '',
      'หากคุณไม่ได้ร้องขอการรีเซ็ตรหัสผ่าน กรุณาเพิกเฉยต่ออีเมลฉบับนี้',
    ].join('\n');

    if (!this.transporter) {
      this.logger.warn(`SMTP not configured — stub-sending password reset code to ${to}: ${code}`);
      return;
    }

    await this.transporter.sendMail({
      from: process.env.SMTP_FROM ?? 'no-reply@poonsuk.example',
      to,
      subject,
      text,
    });
  }
}
