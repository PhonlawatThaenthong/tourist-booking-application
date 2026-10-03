import { Injectable, Logger, OnModuleInit } from '@nestjs/common';
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
export class MailService implements OnModuleInit {
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

  /**
   * Checks the SMTP login once at startup so a wrong host/port/app password
   * shows up in the boot log, not as a silent failure on the first reset
   * email. Never blocks or fails startup.
   */
  onModuleInit(): void {
    if (!this.transporter) {
      this.logger.warn('SMTP_HOST not set — emails are logged to the console, not sent');
      return;
    }
    this.transporter.verify().then(
      () => this.logger.log(`SMTP ready (${process.env.SMTP_HOST}:${process.env.SMTP_PORT ?? 587})`),
      (err) => this.logger.error(`SMTP login failed — emails will not be delivered: ${err}`),
    );
  }

  /** For `npm run mail:test`: sends one plain message and lets errors surface. */
  async sendTest(to: string): Promise<void> {
    await this.send(
      to,
      'ทดสอบการส่งอีเมล — Poonsuk Resort',
      'ถ้าคุณได้รับอีเมลนี้ แปลว่าการตั้งค่า SMTP ของระบบใช้งานได้แล้ว',
    );
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

  /**
   * Sent when staff verify the payment slip (paid), or when an admin approves
   * a booking before payment (unpaid — the email then asks the guest to pay).
   */
  async sendBookingConfirmation(to: string, b: BookingConfirmationPayload): Promise<void> {
    const nights = Math.round(
      (Date.parse(`${b.checkOut}T00:00:00Z`) - Date.parse(`${b.checkIn}T00:00:00Z`)) / 86_400_000,
    );
    const paid = b.paid !== false;
    const subject = paid
      ? `ยืนยันการจองห้อง ${b.roomName} — Poonsuk Resort`
      : `การจองห้อง ${b.roomName} ได้รับการอนุมัติ — Poonsuk Resort`;
    const text = [
      `เรียน คุณ${b.customerName}`,
      '',
      paid
        ? 'การจองของคุณได้รับการยืนยันและชำระเงินเรียบร้อยแล้ว'
        : 'การจองของคุณได้รับการอนุมัติจากเจ้าหน้าที่แล้ว',
      '',
      `ห้อง: ${b.roomName}`,
      `เช็คอิน: ${thaiDate(b.checkIn)} ตั้งแต่เวลา ${CHECK_IN_TIME} น.`,
      `เช็คเอาท์: ${thaiDate(b.checkOut)} ภายในเวลา ${CHECK_OUT_TIME} น.`,
      `จำนวน: ${nights} คืน · ${b.guests} ท่าน`,
      paid
        ? `ยอดชำระ: ${THB.format(b.totalPrice)}`
        : `ยอดที่ต้องชำระ: ${THB.format(b.totalPrice)}`,
      `หมายเลขการจอง: ${b.bookingId}`,
      '',
      ...(paid
        ? []
        : ['กรุณาชำระเงินผ่าน QR PromptPay ในแอป (เมนู My Bookings) แล้วอัปโหลดสลิป', '']),
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
