// Must stay first: Sentry patches http/express/pg as it loads, so any
// module imported above it would go uninstrumented.
import './instrument';
import 'reflect-metadata';
import { NestFactory } from '@nestjs/core';
import { NestExpressApplication } from '@nestjs/platform-express';
import { ValidationPipe, Logger } from '@nestjs/common';
import { AppModule } from './app.module';

async function bootstrap() {
  const app = await NestFactory.create<NestExpressApplication>(AppModule);

  // Behind a reverse proxy every request arrives from the proxy's IP, which
  // would make all clients share one rate-limit bucket. Opt-in only: trusting
  // X-Forwarded-For without a proxy lets clients spoof their IP.
  const trustProxy = process.env.TRUST_PROXY;
  if (trustProxy) {
    app.set('trust proxy', /^\d+$/.test(trustProxy) ? Number(trustProxy) : trustProxy);
  }

  app.setGlobalPrefix('api', { exclude: ['health/live', 'health/ready'] });
  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,          // strip unknown properties (mass-assignment guard)
      forbidNonWhitelisted: true,
      transform: true,
    }),
  );
  app.enableCors({ origin: true });

  // Lets Nest run its shutdown sequence on SIGTERM/SIGINT, which gives the
  // Sentry transport a chance to flush buffered events before the process
  // exits — otherwise the crash that killed the container is the one report
  // you never receive.
  app.enableShutdownHooks();

  const port = Number(process.env.PORT ?? 3000);
  await app.listen(port, '0.0.0.0');
  Logger.log(`API listening on :${port}`, 'Bootstrap');
}
void bootstrap();
