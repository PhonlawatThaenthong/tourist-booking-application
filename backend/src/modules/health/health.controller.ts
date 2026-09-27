import { Controller, Get } from '@nestjs/common';
import { HealthCheck, HealthCheckService, TypeOrmHealthIndicator } from '@nestjs/terminus';
import { RedisHealthIndicator } from './redis.health';

@Controller('health')
export class HealthController {
  constructor(
    private readonly health: HealthCheckService,
    private readonly db: TypeOrmHealthIndicator,
    private readonly redis: RedisHealthIndicator,
  ) {}

  /** Process is up. Never touches dependencies — used for restart decisions. */
  @Get('live')
  live() {
    return { status: 'ok', uptime: process.uptime() };
  }

  /** Dependencies reachable. Used by Nginx/orchestrator to route traffic. */
  @Get('ready')
  @HealthCheck()
  ready() {
    return this.health.check([
      () => this.db.pingCheck('database', { timeout: 1500 }),
      () => this.redis.pingCheck('redis', 1500),
    ]);
  }
}
