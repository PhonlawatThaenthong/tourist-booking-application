import 'dotenv/config';
import { MailService } from '../modules/mail/mail.service';

/**
 * `npm run mail:test -- you@example.com`
 * Sends one test email with the SMTP_* settings from .env, so the SMTP setup
 * can be checked without going through the app.
 */
async function main(): Promise<void> {
  const to = process.argv[2];
  if (!to) {
    console.error('usage: npm run mail:test -- you@example.com');
    process.exit(1);
  }
  if (!process.env.SMTP_HOST) {
    console.error('SMTP_HOST is empty in .env — nothing would be sent.');
    process.exit(1);
  }
  await new MailService().sendTest(to);
  console.log(`sent to ${to} via ${process.env.SMTP_HOST}`);
}

main().catch((err) => {
  console.error('send failed:', err instanceof Error ? err.message : err);
  process.exit(1);
});
