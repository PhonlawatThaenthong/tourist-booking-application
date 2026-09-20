import {
  BadRequestException, Controller, Get, NotFoundException, Query, StreamableFile,
} from '@nestjs/common';
import { createReadStream, existsSync } from 'fs';
import { getPaymentConfig } from '../../config/payment.config';

// promptpay-qr is CommonJS with a default export function; qrcode is CommonJS
// too. Loaded via require (with typed casts) so no esModuleInterop / @types are
// needed just for these two.
const generatePayload = require('promptpay-qr') as (
  target: string,
  opts?: { amount?: number },
) => string;
const QRCode = require('qrcode') as {
  toBuffer: (text: string, opts?: Record<string, unknown>) => Promise<Buffer>;
};

/**
 * Public payment information + a dynamic PromptPay QR.
 *
 * `GET /api/payment/qr?amount=1234.50` generates an EMVCo PromptPay payload for
 * the resort's PromptPay ID with the amount embedded, then renders it to a PNG.
 * No auth — the QR contains no secret, and the amount is a public figure the
 * app already shows. `GET /api/payment/qr-image` remains as a static fallback.
 */
@Controller('payment')
export class PaymentInfoController {
  private readonly cfg = getPaymentConfig();

  @Get('info')
  info() {
    return {
      accountName: this.cfg.accountName,
      promptPayId: this.cfg.promptPayId,
      note: this.cfg.note,
      // Base URL; the app appends ?amount=<booking total> for a dynamic QR.
      qrImageUrl: '/api/payment/qr',
    };
  }

  /** Dynamic PromptPay QR with the amount embedded. */
  @Get('qr')
  async qr(@Query('amount') amount?: string): Promise<StreamableFile> {
    let amt: number | undefined;
    if (amount !== undefined && amount !== '') {
      amt = Number(amount);
      if (!Number.isFinite(amt) || amt <= 0) {
        throw new BadRequestException('amount ไม่ถูกต้อง');
      }
    }
    const payload = generatePayload(this.cfg.promptPayId, amt !== undefined ? { amount: amt } : {});
    const png = await QRCode.toBuffer(payload, { type: 'png', width: 512, margin: 1 });
    return new StreamableFile(png, { type: 'image/png' });
  }

  /** Static QR fallback (used only if a fixed image is configured). */
  @Get('qr-image')
  qrImage(): StreamableFile {
    if (!existsSync(this.cfg.qrImagePath)) {
      throw new NotFoundException('ยังไม่ได้ตั้งค่ารูป QR สำหรับการชำระเงิน');
    }
    return new StreamableFile(createReadStream(this.cfg.qrImagePath), { type: 'image/png' });
  }
}
