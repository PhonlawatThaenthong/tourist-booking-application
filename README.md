# Azure Bay Hotel — Flutter Booking App

A complete hotel reservation app built with Flutter, covering both a **Customer
module** and an **Administrator / Staff module**. Built for a final project, it
runs fully offline using in-memory mock data (no backend required), so you can
demo every feature immediately.

## Features

### Customer module
- **Sign up & sign in** — email/password registration and login, with the
  session persisted across restarts (`shared_preferences`).
- **Real-time room search with filters** — filter live by **date range**, **room
  type**, **price range**, guests and free-text. Results update instantly and
  already-booked rooms are excluded for the selected dates.
- **Room details** — image carousel, description, amenities and price.
- **Booking + secure online payment** — review dates/guests, then a simulated
  secure payment screen (card or PromptPay QR). Double-booking is prevented.
- **Automatic email/SMS confirmation** — on successful payment the app composes
  and "sends" a confirmation (mocked `NotificationService`) and shows the exact
  message that would be delivered.
- **Google Maps integration** — hotel location page with a Google Static Map
  preview plus **Get directions** / **Open in Google Maps** deep links.
- **Restaurant recommendations** — nearby restaurants sorted by distance, each
  with **View on map** and **Directions** via Google Maps.

### Administrator / Staff module
- **Staff login with role-based permissions** — `staff` and `admin` roles.
  Staff manage bookings & rooms; only admins also manage staff accounts.
- **Central dashboard** — revenue, total bookings, pending approvals, occupancy,
  and recent bookings.
- **Booking management** — approve, cancel (auto-refund), and reschedule
  bookings, filtered by status.
- **Room management** — add / remove rooms, edit details, update price, and
  toggle a maintenance status (maintenance rooms disappear from customer search).
- **Reports & statistics** — total revenue, occupancy rate (next 30 days),
  bookings-by-status bar chart, and room inventory summary.

## Demo accounts

| Role     | Email                | Password      |
|----------|----------------------|---------------|
| Customer | customer@hotel.com   | customer123   |
| Staff    | staff@hotel.com      | staff123      |
| Admin    | admin@hotel.com      | admin123      |

The login screen has one-tap chips to fill each of these.

## Running

```bash
flutter pub get
flutter run            # pick a device (Android emulator, Chrome, etc.)
```

Other useful commands:

```bash
flutter analyze        # static analysis (clean)
flutter test           # unit + widget tests
flutter build apk      # Android release build
flutter build web      # web build
```

## Project structure

```
lib/
  main.dart                  App entry + Provider setup
  config.dart                Hotel name / coordinates / address
  theme.dart                 Material 3 theme
  models/                    user, room, booking, restaurant
  data/mock_data.dart        Seed data (swap for API calls to go live)
  providers/                 auth, room, booking, restaurant (ChangeNotifier)
  services/
    notification_service.dart  Email/SMS confirmation (mock)
    maps_service.dart          Google Maps deep links
  screens/
    splash_screen.dart       Routes by auth state + role
    auth/                    login, register
    customer/                search, detail, booking, payment,
                             confirmation, my bookings, restaurants,
                             location, profile
    admin/                   dashboard, manage bookings, manage rooms,
                             room form, reports, manage staff
  widgets/                   room_card, stat_card
```

## Notes on the integrations (demo vs. production)

These features are implemented end-to-end in the UI but stubbed at the network
boundary so the app runs with zero setup:

- **Payment** — `PaymentScreen` simulates a gateway charge. To go live, hand off
  to a PCI-compliant SDK (Stripe / Omise / 2C2P) and mark the booking paid on
  the gateway callback.
- **Email / SMS** — `NotificationService` composes and logs the message. Wire it
  to an email API (e.g. SendGrid) and an SMS gateway (e.g. Twilio).
- **Google Maps** — location & directions use Google Maps URL deep links, which
  need no API key. The hotel **map preview image** uses the Google Static Maps
  API; supply a key to remove the development watermark:

  ```bash
  flutter run --dart-define=MAPS_API_KEY=YOUR_KEY
  ```

  To embed a fully interactive in-app map, add `google_maps_flutter` and
  configure the key per platform.
- **Data** — everything is seeded from `lib/data/mock_data.dart` and held in
  memory. Replace the provider bodies with REST/Firebase calls to persist.

## Tech

- Flutter 3.44 / Dart 3.12, Material 3
- State management: `provider`
- `intl`, `uuid`, `url_launcher`, `shared_preferences`
