import { IsDateString, IsIn, IsOptional, Matches } from 'class-validator';

const DATE_ONLY = /^\d{4}-\d{2}-\d{2}$/;

/**
 * Both ends are inclusive calendar days (`from=2026-10-01&to=2026-10-31` is
 * all of October) — unlike a booking's check-out, which is exclusive.
 */
export class ReportRangeDto {
  @IsDateString({ strict: true } as never, { message: 'from ต้องอยู่ในรูปแบบ YYYY-MM-DD' })
  @Matches(DATE_ONLY, { message: 'from ต้องอยู่ในรูปแบบ YYYY-MM-DD' })
  from!: string;

  @IsDateString({ strict: true } as never, { message: 'to ต้องอยู่ในรูปแบบ YYYY-MM-DD' })
  @Matches(DATE_ONLY, { message: 'to ต้องอยู่ในรูปแบบ YYYY-MM-DD' })
  to!: string;
}

export type RevenueGroupBy = 'day' | 'month';

export class RevenueQueryDto extends ReportRangeDto {
  @IsOptional() @IsIn(['day', 'month'], { message: 'groupBy ต้องเป็น day หรือ month' })
  groupBy: RevenueGroupBy = 'day';
}
