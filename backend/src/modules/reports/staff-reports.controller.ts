import { Controller, Get, Query, UseGuards } from '@nestjs/common';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { RolesGuard } from '../../common/guards/roles.guard';
import { Roles } from '../../common/decorators/roles.decorator';
import { UserRole } from '../users/user.entity';
import { ReportsService } from './reports.service';
import { ReportRangeDto, RevenueQueryDto } from './dto/report-query.dto';

@Controller('staff/reports')
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles(UserRole.STAFF, UserRole.ADMIN)
export class StaffReportsController {
  constructor(private readonly reports: ReportsService) {}

  /** `GET /api/staff/reports/revenue?from=&to=&groupBy=day|month` */
  @Get('revenue')
  revenue(@Query() q: RevenueQueryDto) {
    return this.reports.revenue(q);
  }

  /** `GET /api/staff/reports/occupancy?from=&to=` */
  @Get('occupancy')
  occupancy(@Query() q: ReportRangeDto) {
    return this.reports.occupancy(q);
  }
}
