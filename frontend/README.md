# 📱 Poonsuk Resort — Flutter App

แอปมือถือสำหรับลูกค้าและพนักงานของพูนสุข รีสอร์ท ทำงานกับ [Backend API](../backend/README.md) จริง

> ภาพรวมทั้งโปรเจกต์ วิธีรันทั้งระบบ และ CI/CD อยู่ใน [README หลัก](../README.md)
> ดาวน์โหลด APK ได้ที่ [Releases](https://github.com/PhonlawatThaenthong/tourist-booking-application/releases/latest)

---

## สารบัญ

- [รันแอป](#รันแอป)
- [ค่าที่ตั้งตอน build](#ค่าที่ตั้งตอน-build)
- [โครงสร้างโค้ด](#โครงสร้างโค้ด)
- [การอัปเดตในแอป](#การอัปเดตในแอป)
- [เทส](#เทส)
- [Build APK](#build-apk)

---

## รันแอป

ต้องมี Flutter SDK (stable) และ backend ที่รันอยู่ ดูวิธีรัน backend ใน [README หลัก](../README.md#1-backend)

```bash
flutter pub get
```

| รันบน | คำสั่ง |
|---|---|
| เบราว์เซอร์ | `flutter run -d web-server --web-port=8081` แล้วเปิด `http://localhost:8081` |
| Android emulator | `flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000` |
| มือถือจริง | `flutter run --dart-define=API_BASE_URL=http://<IP เครื่องคอม>:3000` |

emulator มองเครื่องคอมเป็น `10.0.2.2` ไม่ใช่ `localhost` ส่วนมือถือจริงต้องอยู่ Wi-Fi เดียวกับเครื่องคอม

---

## ค่าที่ตั้งตอน build

ส่งผ่าน `--dart-define=KEY=value` ทุกค่าอยู่ใน [`lib/config.dart`](lib/config.dart)

| Key | ใช้ทำอะไร | ค่าเริ่มต้น |
|---|---|---|
| `API_BASE_URL` | ที่อยู่ backend | `http://localhost:3000` |
| `SENTRY_DSN` | ส่ง crash report ไป Sentry | ว่าง = ปิด |
| `SENTRY_ENVIRONMENT` | แยก report ตามสภาพแวดล้อม | `development` |
| `APP_BUILD` | เลข build ใช้เทียบอัปเดตและแสดงในหน้า Profile | `0` = build สำหรับพัฒนา ปิดการเช็กอัปเดต |
| `APP_VERSION` | ชื่อเวอร์ชัน เช่น `1.0.0` | `1.0.0` |
| `RELEASES_REPO` | repo บน GitHub ที่เก็บ APK | repo นี้ |
| `ADMIN_CONTACT_NAME` · `ADMIN_PHONE` | ชื่อและเบอร์ติดต่อเจ้าหน้าที่ในหน้าการจอง | `Poonsuk Resort front desk` · `081-598-1199` |
| `ADMIN_EMAIL` · `ADMIN_LINE_ID` | อีเมลและ LINE ของเจ้าหน้าที่ | ว่าง = ซ่อนแถวนั้น |

release workflow ใส่ `API_BASE_URL`, `APP_BUILD`, `APP_VERSION` และ Sentry ให้เอง ไม่ต้องแก้โค้ด

---

## โครงสร้างโค้ด

```
lib/
├── main.dart              ประกอบแอป เลือก repository, สร้าง Bloc, Sentry, Firebase
├── config.dart            ค่าคงที่และค่าจาก --dart-define
├── models/                Room, Booking, Payment, User, Restaurant, Report, ChatMessage
├── repositories/
│   ├── *_repository.dart  interface ของแต่ละส่วน
│   ├── api/               ตัวเรียก API จริง (ใช้ในแอป)
│   └── mock/              ข้อมูลในหน่วยความจำ (ใช้ในเทส)
├── blocs/                 auth · room · booking · payment · restaurant · chat
├── screens/
│   ├── auth/              ล็อกอิน สมัคร ลืมรหัสผ่าน
│   ├── customer/          ค้นหาห้อง จอง จ่ายเงิน การจองของฉัน ร้านอาหาร แผนที่ แชต Profile
│   └── admin/             แดชบอร์ด ปฏิทิน การจอง สลิป ห้อง พนักงาน รายงาน
├── services/              แผนที่, การแจ้งเตือน, เช็กอัปเดต
├── widgets/               ชิ้นส่วน UI ที่ใช้ซ้ำ
└── utils/                 จัดรูปแบบเงิน วันที่ ระยะทาง
```

**ลำดับการทำงาน** หน้าจอส่ง event ให้ Bloc → Bloc เรียก repository → repository เรียก API ผ่าน `ApiClient`

**`ApiClient`** ([`lib/repositories/api/api_client.dart`](lib/repositories/api/api_client.dart)) ดูแลเรื่องที่ทุก request ต้องมี
- แนบ access token และเก็บ session ใน `SharedPreferences` ปิดแอปแล้วเปิดใหม่ยังล็อกอินอยู่
- เจอ `401` จะขอ token ใหม่หนึ่งครั้งแล้วส่งซ้ำ ถ้าหลาย request ล้มพร้อมกันจะขอ token ใหม่แค่ครั้งเดียว
- แปลง error จาก API เป็น `RepositoryException` ที่มีข้อความจาก server ให้ Bloc แสดงต่อ

**หลังล็อกอิน** บทบาท `customer` เข้าหน้าลูกค้า ส่วน `staff` และ `admin` เข้าหน้าหลังบ้าน

---

## การอัปเดตในแอป

แอปที่ลงจาก APK ไม่มี store คอยแจ้งอัปเดต จึงเช็กเองตอนเปิดแอป

1. [`UpdateService`](lib/services/update_service.dart) ถาม GitHub ว่า release ล่าสุดคือ `v<version>-build.<N>` อะไร
2. ถ้า `N` มากกว่า `APP_BUILD` ของแอป [`UpdateGate`](lib/widgets/update_gate.dart) จะเด้งถาม
3. กด Update แอปโหลด APK ผ่าน `ota_update` แล้วเปิดหน้าติดตั้งของ Android ผู้ใช้กดยืนยันเอง
4. ถ้าติดตั้งในแอปไม่สำเร็จ จะเปิดลิงก์ APK ในเบราว์เซอร์แทน

ทำงานเฉพาะแอป Android ที่ build จาก release workflow ไม่มีผลกับ `flutter run` เว็บ หรือเทส

---

## เทส

| ชุด | คำสั่ง | ต้องมี |
|---|---|---|
| Unit + widget | `flutter test` | — |
| Lint | `flutter analyze` | — |
| E2E บนอุปกรณ์ | `patrol test --dart-define=API_BASE_URL=http://10.0.2.2:3000` | emulator และ backend ที่รันอยู่ |

**Unit + widget** ใน [`test/`](test/) ครอบคลุม model, การอ่าน JSON จาก API, `ApiClient`, Bloc, การจัดรูปแบบ, การเช็กอัปเดต และบางหน้าจอ ไม่ต้องมี backend CI รันทุกครั้งที่แก้ `frontend/`

**Patrol** ใน [`patrol_test/`](patrol_test/) เปิดแอปจริงบน emulator แล้วกดตามขั้นตอน เช่น ล็อกอิน สมัคร และจองห้อง ยังไม่ได้รันใน CI ก่อนรันต้องรู้ไว้สองเรื่อง:
- เทสล็อกอินด้วย `customer@hotel.com` และ `staff@hotel.com` ใน [`patrol_test/support/app_helpers.dart`](patrol_test/support/app_helpers.dart) แต่ backend ไม่ seed บัญชีเหล่านี้แล้ว ต้องสร้างเองก่อน
- `pubspec.yaml` ส่วน `patrol:` ยังตั้ง `package_name` เป็น `com.example.hotel_booking` แต่แอปจริงคือ `com.poonsuk.resort`

---

## Build APK

ปกติไม่ต้อง build เอง ทุกครั้งที่โค้ดเข้า `main` และเทสผ่าน GitHub Actions จะ build, sign และรอให้ผู้อนุมัติปล่อยเป็น release

ถ้าจะ build ในเครื่อง:

```bash
flutter build apk --release --dart-define=API_BASE_URL=https://<API domain>
```

ถ้าไม่มี `android/key.properties` กับ `android/upload-keystore.jks` APK จะ sign ด้วย debug key ติดตั้งทับแอปจาก Releases ไม่ได้
รายละเอียดเรื่อง signing key อยู่หัวไฟล์ [`frontend-release.yml`](../.github/workflows/frontend-release.yml)

Firebase เปิดใช้เฉพาะบน Android ตามไฟล์ `android/app/google-services.json` บนเว็บจะข้ามไป
