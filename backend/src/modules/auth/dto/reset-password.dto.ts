import { IsEmail, IsString, Matches, MinLength } from 'class-validator';

export class ResetPasswordDto {
  @IsEmail()
  email!: string;

  @IsString() @Matches(/^\d{6}$/, { message: 'รหัสยืนยันไม่ถูกต้อง' })
  code!: string;

  @IsString() @MinLength(8, { message: 'รหัสผ่านต้องยาวอย่างน้อย 8 ตัวอักษร' })
  newPassword!: string;
}
