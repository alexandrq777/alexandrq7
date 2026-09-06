# Torly

Native SwiftUI iPhone owner prototype, connected to https://torly.cybermemo.dev.
There is no demo mode and no bundled client, business or appointment data.

## Working flows

- Email/password registration and login; new accounts start empty.
- Three-step business setup: contact/region, database-backed category, employee hours.
- Separate Calendar, Clients, Services and Business tabs.
- Services: create, edit price/duration, archive; staff creation and individual hours.
- Real availability, manual booking, confirmation, cancellation and rescheduling.
- Breaks and leave block overlapping appointments.
- Client cards, notes and recorded no-shows; day totals from actual appointments only.
- HTTPS persistence and authenticated real-time calendar refresh.
- Passwords are not stored on the phone; session tokens use Keychain.

## Open in Xcode

1. Open `Torly.xcodeproj`.
2. Select scheme `Torly` and a simulator or connected iPhone.
3. Run. Physical-device signing uses the configured Aleksandr Podgaets team;
   sign in to that Apple Developer account in Xcode, or select your own team.

Bundle ID: `app.torly.mvp`. The owner can use the existing private login or
register a new account. Login credentials are never included in this repository.

## Remaining launch work

Public client booking/link publishing, photos, email verification and password
recovery, Apple/Google login, push delivery, WhatsApp/Telegram reminders, waitlist,
reviews, forms, calendar integrations and subscriptions are not connected.
The backend's plan metadata is ILS 39/month; it does not charge anyone.
This is a working owner prototype, not an App Store-ready complete service.

See `Docs/server-architecture.md` and `Server/TorlyAPI/README.md`.
