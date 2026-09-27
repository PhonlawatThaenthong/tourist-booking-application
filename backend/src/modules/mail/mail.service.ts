import { Injectable, Logger } from '@nestjs/common';
import * as nodemailer from 'nodemailer';
import type { BookingConfirmationPayload } from '../notifications/notifications.service';
import { CHECK_IN_TIME, CHECK_OUT_TIME } from '../../config/booking.config';

// Gregorian year, to match the dates the app shows; the stored dates are
// calendar days, so they are formatted in UTC to keep them from shifting.
const THAI_DATE = new Intl.DateTimeFormat('th-TH-u-ca-gregory', {
  day: 'numeric', month: 'long', year: 'numeric', timeZone: 'UTC',
});
const THB = new Intl.NumberFormat('th-TH', {
  style: 'currency', currency: 'THB', maximumFractionDigits: 0,
});

function thaiDate(ymd: string): string {
  return THAI_DATE.format(new Date(`${ymd}T00:00:00Z`));
}

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

    await this.send(to, subject, text);
  }

  /** Sent once staff verify the payment slip. */
  async sendBookingConfirmation(to: string, b: BookingConfirmationPayload): Promise<void> {
    const nights = Math.round(
      (Date.parse(`${b.checkOut}T00:00:00Z`) - Date.parse(`${b.checkIn}T00:00:00Z`)) / 86_400_000,
    );
    const subject = `ยืนยันการจองห้อง ${b.roomName} — Poonsuk Resort`;
    const text = [
      `เรียน คุณ${b.customerName}`,
      '',
      'การจองของคุณได้รับการยืนยันและชำระเงินเรียบร้อยแล้ว',
      '',
      `ห้อง: ${b.roomName}`,
      `เช็คอิน: ${thaiDate(b.checkIn)} ตั้งแต่เวลา ${CHECK_IN_TIME} น.`,
      `เช็คเอาท์: ${thaiDate(b.checkOut)} ภายในเวลา ${CHECK_OUT_TIME} น.`,
      `จำนวน: ${nights} คืน · ${b.guests} ท่าน`,
      `ยอดชำระ: ${THB.format(b.totalPrice)}`,
      `หมายเลขการจอง: ${b.bookingId}`,
      '',
      'แล้วพบกันที่ Poonsuk Resort',
    ].join('\n');

    await this.send(to, subject, text);
  }

  private async send(to: string, subject: string, text: string): Promise<void> {
    if (!this.transporter) {
      this.logger.warn(`SMTP not configured — stub-sending "${subject}" to ${to}:\n${text}`);
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
