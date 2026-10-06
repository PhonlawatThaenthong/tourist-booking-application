# 🛠️ Poonsuk Resort — Backend API

NestJS API ของแอปจองห้องพัก ใช้ PostgreSQL เก็บข้อมูล และ Redis สำหรับ cache, lock และ queue

> ภาพรวมทั้งโปรเจกต์ วิธีรันทั้งระบบ และ CI/CD อยู่ใน [README หลัก](../README.md)
> การ deploy ขึ้น Google Cloud อยู่ใน [`deploy/README.md`](../deploy/README.md)

---

## สารบัญ

- [เริ่มต้นใช้งาน](#เริ่มต้นใช้งาน)
- [คำสั่ง npm](#คำสั่ง-npm)
- [Environment variables](#environment-variables)
- [API](#api)
- [กฎสำคัญของระบบ](#กฎสำคัญของระบบ)
- [ข้อตกลงในโค้ด](#ข้อตกลงในโค้ด)
- [เทส](#เทส)

---

## เริ่มต้นใช้งาน

ต้องมี Node.js 20+ และ Docker Desktop ตัวอย่างไฟล์ `.env` สำหรับเครื่องตัวเองอยู่ใน [README หลัก](../README.md#1-backend)

```bash
npm install
docker compose up -d postgres redis   # Postgres ที่ :5433, Redis ที่ :6379
npm run migration:run
npm run seed:rooms
npm run seed:restaurants
npm run start:dev                     # http://localhost:3000
```

สร้าง admin คนแรก รหัสผ่านอย่างน้อย 12 ตัวอักษร สคริปต์ไม่มีค่าเริ่มต้นให้

```powershell
$env:SEED_ADMIN_EMAIL="you@example.com"; $env:SEED_ADMIN_PASSWORD="<strong password>"
npm run seed:admin
```

รัน API ใน Docker ทั้งชุดก็ได้: `docker compose up --build`

---

## คำสั่ง npm

| คำสั่ง | ทำอะไร |
|---|---|
| `npm run start:dev` | รัน API แบบ watch |
| `npm run build` | compile ไป `dist/` |
| `npm test` | unit tests |
| `npm run test:e2e` | e2e tests ต้องมี Postgres + Redis |
| `npm run lint` | ESLint และแก้ให้อัตโนมัติ |
| `npm run migration:run` | รัน migration ที่ค้างอยู่ |
| `npm run migration:revert` | ย้อน migration ล่าสุดหนึ่งตัว |
| `npm run migration:generate -- src/migrations/<Name>` | สร้าง migration จาก entity ที่แก้ |
| `npm run seed:rooms` | ใส่ห้องพัก รันซ้ำได้ ไม่สร้างซ้ำ |
| `npm run seed:restaurants` | ใส่ร้านอาหาร |
| `npm run seed:admin` | สร้างบัญชี admin จาก `SEED_ADMIN_*` |
| `npm run upload:restaurant-photos` | อัปโหลดรูปร้านอาหาร |
| `npm run mail:test` | ลองส่งอีเมลด้วยค่า SMTP ปัจจุบัน |

---

## Environment variables

<details>
<summary><b>ดูทั้งหมด</b></summary>

| กลุ่ม | ตัวแปร | หมายเหตุ |
|---|---|---|
| ทั่วไป | `NODE_ENV`, `PORT` | `production` บังคับให้ต้องตั้ง `JWT_ACCESS_SECRET` |
| ฐานข้อมูล | `DB_HOST`, `DB_PORT`, `DB_USER`, `DB_PASSWORD`, `DB_NAME` | เครื่อง dev ใช้พอร์ต `5433` |
| Redis | `REDIS_URL` | ใส่รหัสใน URL เช่น `redis://:<password>@localhost:6379` |
| Redis | `REDIS_PASSWORD` | `docker-compose.yml` ใช้ตั้งรหัสให้ Redis |
| Auth | `JWT_ACCESS_SECRET`, `JWT_ACCESS_TTL`, `JWT_REFRESH_TTL_DAYS` | |
| Auth | `RESET_TOKEN_TTL_MINUTES` | อายุรหัสรีเซ็ตรหัสผ่าน |
| อีเมล | `SMTP_HOST`, `SMTP_PORT`, `SMTP_USER`, `SMTP_PASSWORD`, `SMTP_FROM` | ไม่ตั้ง `SMTP_HOST` = แสดงรหัสใน log แทนการส่ง |
| ชำระเงิน | `PAYMENT_ACCOUNT_NAME`, `PAYMENT_PROMPTPAY_ID`, `PAYMENT_NOTE`, `PAYMENT_MAX_SLIP_BYTES` | |
| ไฟล์ | `UPLOAD_DIR`, `IMAGE_MAX_BYTES` | ที่เก็บสลิปและรูป |
| การจอง | `BOOKING_HOLD_MINUTES`, `BOOKING_SWEEP_SECONDS` | เวลาถือห้องก่อนยกเลิกอัตโนมัติ และรอบการเช็ก |
| Cache, lock | `CACHE_ENABLED`, `CACHE_TTL_SECONDS`, `CACHE_OP_TIMEOUT_MS`, `LOCK_ENABLED` | |
| Chatbot | `CHATBOT_URL`, `CHATBOT_TIMEOUT_MS`, `CHATBOT_INTERNAL_KEY` | |
| Proxy | `TRUST_PROXY` | จำนวน proxy หน้า API ใช้ให้ rate limit เห็น IP จริง |
| Sentry | `SENTRY_DSN`, `SENTRY_ENVIRONMENT`, `SENTRY_RELEASE`, `SENTRY_TRACES_SAMPLE_RATE` | ไม่ตั้ง DSN = ปิด Sentry |
| Seed | `SEED_ADMIN_EMAIL`, `SEED_ADMIN_PASSWORD`, `SEED_ADMIN_NAME` | ใช้กับ `npm run seed:admin` เท่านั้น |

</details>

---

## API

ทุก route ขึ้นต้นด้วย `/api` ยกเว้น `/health/*`
ส่ง token แบบ `Authorization: Bearer <accessToken>`

**สิทธิ์:** 🌐 ไม่ต้องล็อกอิน · 🔑 ล็อกอิน · 🛎️ staff หรือ admin · 👑 admin เท่านั้น

<details open>
<summary><b>Auth</b></summary>

| | Method | Path | หมายเหตุ |
|---|---|---|---|
| 🌐 | POST | `/api/auth/register` | ได้ access + refresh token + user |
| 🌐 | POST | `/api/auth/login` | |
| 🌐 | POST | `/api/auth/refresh` | หมุน refresh token ตัวเก่าใช้ซ้ำไม่ได้ |
| 🌐 | POST | `/api/auth/logout` | ยกเลิก refresh token ตอบ 204 |
| 🌐 | POST | `/api/auth/forgot-password` | ส่งรหัส 6 หลักทางอีเมล ตอบเหมือนกันไม่ว่าอีเมลจะมีในระบบหรือไม่ |
| 🌐 | POST | `/api/auth/reset-password` | |
| 🔑 | GET | `/api/auth/me` | |

</details>

<details>
<summary><b>ห้องพัก</b></summary>

| | Method | Path | หมายเหตุ |
|---|---|---|---|
| 🌐 | GET | `/api/rooms` | |
| 🌐 | GET | `/api/rooms/availability` | ช่วงวันที่ถูกจองของทุกห้อง ไม่มีข้อมูลลูกค้า |
| 🌐 | GET | `/api/rooms/:id` | |
| 🌐 | GET | `/api/rooms/:id/images/:file` | |
| 🛎️ | GET · POST | `/api/staff/rooms` | |
| 🛎️ | PATCH · DELETE | `/api/staff/rooms/:id` | |
| 🛎️ | POST | `/api/staff/rooms/:id/images` | |

</details>

<details>
<summary><b>การจองและการชำระเงิน</b></summary>

| | Method | Path | หมายเหตุ |
|---|---|---|---|
| 🔑 | POST | `/api/bookings` | ส่งแค่ `roomId`, `checkIn`, `checkOut`, `guests` |
| 🔑 | GET | `/api/bookings/me` | |
| 🔑 | POST | `/api/bookings/:id/pay` | อัปโหลดสลิป field `slip` แบบ multipart |
| 🔑 | GET | `/api/bookings/:id/payment` | |
| 🛎️ | POST | `/api/bookings/:id/cancel` | ลูกค้ายกเลิกเองไม่ได้ ต้องให้พนักงานยกเลิก |
| 🛎️ | GET | `/api/staff/bookings` · `/api/staff/bookings/:id` | |
| 🛎️ | PATCH | `/api/staff/bookings/:id` | เปลี่ยนสถานะ หรือเลื่อนวัน ระบบคิดราคาใหม่ |
| 🛎️ | POST | `/api/staff/bookings/:id/check-in` · `/check-out` | |
| 🌐 | GET | `/api/payment/info` · `/api/payment/qr` | ข้อมูลบัญชีและ QR PromptPay |
| 🛎️ | GET | `/api/staff/payments` | |
| 🛎️ | GET | `/api/staff/payments/:id/slip` | รูปสลิป |
| 🛎️ | PATCH | `/api/staff/payments/:id` | `{ action: "approve" }` หรือ `{ action: "reject", reason }` |

</details>

<details>
<summary><b>ร้านอาหาร · รายงาน · ผู้ใช้ · chatbot · health</b></summary>

| | Method | Path | หมายเหตุ |
|---|---|---|---|
| 🌐 | GET | `/api/restaurants` · `/api/restaurants/:id` · `/api/restaurants/:id/image` | |
| 🛎️ | POST | `/api/staff/restaurants` | |
| 🛎️ | PATCH · DELETE | `/api/staff/restaurants/:id` | |
| 🛎️ | POST | `/api/staff/restaurants/:id/image` | |
| 🛎️ | GET | `/api/staff/reports/revenue` · `/api/staff/reports/occupancy` | |
| 🛎️ | GET | `/api/staff/users` | |
| 👑 | POST | `/api/staff/users` | สร้างบัญชีพนักงาน |
| 👑 | DELETE | `/api/staff/users/:id` | |
| 🌐 | POST | `/api/chatbot/query` | ล็อกอินหรือไม่ก็ได้ |
| 🌐 | GET | `/health/live` | API ยังทำงานอยู่ |
| 🌐 | GET | `/health/ready` | เช็ก Postgres และ Redis |

</details>

---

## กฎสำคัญของระบบ

- **ราคาคิดที่ server เสมอ** จากราคาต่อคืนในฐานข้อมูล × จำนวนคืน ราคาที่ client ส่งมาจะถูกปฏิเสธ
- **กันจองซ้ำสองชั้น** API ล็อกต่อห้องผ่าน Redis และฐานข้อมูลมี exclusion constraint `EXC_bookings_no_overlap` ช่วงวันเป็นแบบ `[checkIn, checkOut)` วันออกของคนหนึ่งจึงเป็นวันเข้าของคนถัดไปได้ จองชนกันได้ `409`
- **ถือห้องชั่วคราว** การจองที่ยังไม่จ่ายและยังไม่อัปโหลดสลิป จะถูกยกเลิกอัตโนมัติหลัง `BOOKING_HOLD_MINUTES`
- **การจ่ายเงินต้องมีคนยืนยัน** อัปโหลดสลิปแล้วสถานะเป็น `awaiting_verification` การจองเปลี่ยนเป็นจ่ายแล้วเฉพาะเมื่อพนักงานกดยืนยัน
- **เช็คอิน** ได้เฉพาะการจองที่อนุมัติแล้ว และตั้งแต่วันเข้าพักจนถึงก่อนวันออก นับวันตามเวลาไทย
- **Rate limit** ทุก route จำกัดต่อ IP บาง route เข้มกว่า เช่น สมัคร 5 ครั้งต่อนาที ล็อกอิน 10 ครั้งต่อนาที และขอรหัสรีเซ็ต 3 ครั้งต่อ 15 นาที

---

## ข้อตกลงในโค้ด

- `synchronize` ปิดถาวร ทุกการเปลี่ยน schema ต้องเป็น migration
- migration ต้องใช้กับโค้ดเวอร์ชันก่อนหน้าได้ เพราะ deploy รัน migration ก่อนสลับ API และ rollback ย้อนแค่ image
- รหัสผ่านเก็บเป็น bcrypt cost 12 คอลัมน์ `password_hash` เป็น `select: false`
- refresh token เก็บเป็น sha256 และหมุนทุกครั้งที่ใช้ รีเซ็ตรหัสผ่านแล้วทุก session ถูกยกเลิก
- `ValidationPipe` เปิด `whitelist` และ `forbidNonWhitelisted` ทั้งแอป field ที่ไม่รู้จักได้ `400`
- คอลัมน์ `numeric` ส่งออกเป็น JSON number เสมอ แอป Flutter อ่านแบบ `num`
- จำกัดสิทธิ์ด้วย `@UseGuards(JwtAuthGuard, RolesGuard)` คู่กับ `@Roles(UserRole.ADMIN)`

---

## เทส

| ชุด | ไฟล์ | รันด้วย |
|---|---|---|
| Unit | `src/**/*.spec.ts` | `npm test` |
| E2E | `test/*.e2e-spec.ts` | `npm run test:e2e` |

E2E ยิง HTTP จริงเข้า API ที่ต่อ Postgres และ Redis จริง ครอบคลุม auth, กฎการจอง, จองพร้อมกัน, ตรวจสลิป, รายงาน และ cache ห้อง
แต่ละไฟล์สร้างห้องและผู้ใช้ของตัวเอง จึงรันซ้ำบนฐานข้อมูลเดิมได้ CI รันทั้งสองชุดทุกครั้งที่มีการแก้ `backend/`
