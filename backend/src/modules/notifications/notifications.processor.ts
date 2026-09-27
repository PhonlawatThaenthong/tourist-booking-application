import { Processor, WorkerHost } from '@nestjs/bullmq';
import { InjectRepository } from '@nestjs/typeorm';
import { Job } from 'bullmq';
import { Repository } from 'typeorm';
import {
  BookingConfirmationJobData, BookingConfirmationPayload, NOTIFICATIONS_QUEUE,
} from './notifications.service';
import { NotificationChannel, NotificationLog, NotificationStatus } from './notification-log.entity';
import { MailService } from '../mail/mail.service';

/**
 * Delivers queued notifications. Email goes out through MailService (SMTP);
 * a failure is recorded on the `notifications_log` row and rethrown so BullMQ
 * retries with backoff.
 */
@Processor(NOTIFICATIONS_QUEUE)
export class NotificationsProcessor extends WorkerHost {
  constructor(
    @InjectRepository(NotificationLog) private readonly repo: Repository<NotificationLog>,
    private readonly mail: MailService,
  ) {
    super();
  }

  async process(job: Job<BookingConfirmationJobData>): Promise<void> {
    const log = await this.repo.findOne({ where: { id: job.data.notificationLogId } });
    if (!log) return;

    log.attempts += 1;
    try {
      await this.send(log);
      log.status = NotificationStatus.SENT;
      log.lastError = null;
      await this.repo.save(log);
    } catch (err) {
      log.status = NotificationStatus.FAILED;
      log.lastError = err instanceof Error ? err.message : String(err);
      await this.repo.save(log);
      throw err; // BullMQ retries per the job's attempts/backoff config.
    }
  }

  private async send(log: NotificationLog): Promise<void> {
    if (log.channel !== NotificationChannel.EMAIL) {
      // No SMS provider yet (issue #28). Fail rather than mark a message
      // `sent` that never left the building.
      throw new Error(`No provider configured for ${log.channel}`);
    }
    await this.mail.sendBookingConfirmation(
      log.recipient,
      log.payload as unknown as BookingConfirmationPayload,
    );
  }
}
