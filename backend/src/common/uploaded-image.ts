import { BadRequestException } from '@nestjs/common';
import { ALLOWED_SLIP_MIME, getPaymentConfig } from '../config/payment.config';
import { UploadedSlip } from '../modules/payments/payment.response';

/**
 * Shared rules for photos staff upload (restaurants, rooms): the same image
 * types a payment slip may be, stored under the same UPLOAD_DIR volume.
 */

/** Multer's in-memory file, as FileInterceptor hands it over. */
export type UploadedImage = UploadedSlip;

export const MAX_IMAGE_BYTES = Number(process.env.IMAGE_MAX_BYTES ?? 5 * 1024 * 1024);

/** Root every stored upload lives under (slips, restaurant and room photos). */
export function uploadRoot(): string {
  return getPaymentConfig().uploadDir;
}

/** Checks type and size; returns the extension to save the file under. */
export function imageExtension(file: UploadedImage | undefined): string {
  if (!file) throw new BadRequestException('กรุณาแนบไฟล์รูป (field: image)');
  const ext = ALLOWED_SLIP_MIME[file.mimetype];
  if (!ext) {
    throw new BadRequestException('รองรับเฉพาะไฟล์รูปภาพ PNG, JPG หรือ WEBP');
  }
  if (file.size > MAX_IMAGE_BYTES) {
    const mb = Math.round(MAX_IMAGE_BYTES / (1024 * 1024));
    throw new BadRequestException(`ไฟล์รูปต้องไม่เกิน ${mb} MB`);
  }
  return ext;
}

export function imageContentType(fileName: string): string {
  const ext = fileName.split('.').pop();
  return ext === 'png' ? 'image/png' : ext === 'webp' ? 'image/webp' : 'image/jpeg';
}
