import { Module } from '@nestjs/common';
import { ReportsService } from './reports.service';
import { StaffReportsController } from './staff-reports.controller';

@Module({
  controllers: [StaffReportsController],
  providers: [ReportsService],
})
export class ReportsModule {}
