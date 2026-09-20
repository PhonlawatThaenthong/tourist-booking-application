import { join, isAbsolute } from 'path';

/**
 * Static PromptPay QR configuration. The resort shows ONE fixed QR image; the
 * amount is not embedded in the QR (the app already knows the booking total),
 * so there is no per-booking QR generation and no external gateway call.
 *
 * All values come from the environment so the account can be changed without a
 * rebuild. `UPLOAD_DIR` may be relative to the process working directory or
 * absolute. The QR itself is generated dynamically from `PAYMENT_PROMPTPAY_ID`.
 */
export interface PaymentConfig {
  accountName: string;
  promptPayId: string;
  note: string;
  uploadDir: string;
  slipDir: string;
  maxSlipBytes: number;
}

function resolvePath(value: string): string {
  return isAbsolute(value) ? value : join(process.cwd(), value);
}

export function getPaymentConfig(): PaymentConfig {
  const uploadDir = resolvePath(process.env.UPLOAD_DIR ?? './uploads');
  return {
    accountName: process.env.PAYMENT_ACCOUNT_NAME ?? 'Poonsuk Resort',
    promptPayId: process.env.PAYMENT_PROMPTPAY_ID ?? '000-000-0000',
    note: process.env.PAYMENT_NOTE
      ?? 'สแกน QR แล้วโอนตามยอดการจอง จากนั้นอัปโหลดสลิปเพื่อรอเจ้าหน้าที่ยืนยัน',
    uploadDir,
    slipDir: join(uploadDir, 'slips'),
    maxSlipBytes: Number(process.env.PAYMENT_MAX_SLIP_BYTES ?? 5 * 1024 * 1024),
  };
}

/** Image content types a slip upload is allowed to be. */
export const ALLOWED_SLIP_MIME: Record<string, string> = {
  'image/png': 'png',
  'image/jpeg': 'jpg',
  'image/jpg': 'jpg',
  'image/webp': 'webp',
};
