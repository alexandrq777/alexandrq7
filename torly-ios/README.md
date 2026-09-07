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
- Owner-controlled publication and native ShareLink on Calendar and Business tabs.
- Public client page: Hebrew/English/Russian, month calendar, staff/service selection,
  real availability and booking requests without installing the owner app.
- Passwords are not stored on the phone; session tokens use Keychain.
- Settings includes Hebrew, English, Spanish and Russian. The selected language
  persists on device, updates native date/currency formatting and enables Hebrew RTL.
  Language selection is also available before login and during onboarding.

## Open in Xcode

1. Open `Torly.xcodeproj`.
2. Select scheme `Torly` and a simulator or connected iPhone.
3. Run. Physical-device signing uses the configured Aleksandr Podgaets team;
   sign in to that Apple Developer account in Xcode, or select your own team.

Bundle ID: `app.torly.mvp`. The owner can use the existing private login or
register a new account. Login credentials are never included in this repository.

## Remaining launch work

Photos, email verification and password
recovery, Apple/Google login, push delivery, WhatsApp/Telegram reminders, waitlist,
reviews, forms, calendar integrations and subscriptions are not connected.
The backend's plan metadata is ILS 39/month; it does not charge anyone.
This is a working owner prototype, not an App Store-ready complete service.

To share: add an active service and working hours, enable online booking, then
use Share with client. Public requests are pending until the owner confirms.
Clients currently contact the business to cancel or move; self-service management
and reminder delivery are not connected. Phone numbers are not OTP-verified.

See `Docs/server-architecture.md` and `Server/TorlyAPI/README.md`.

Legacy uppercase booking links remain supported. New links use lowercase slugs;
booking pages support GET and HEAD with HTML content types for browser/share previews.

The original icon and Torly wordmark appear above the signed-in tabs. Settings now
include four languages, notification authorization and a local test, notification
sound and haptic preferences, an app-switcher privacy cover, data visibility
information, refresh, sign-out confirmation and version information.

While the app is active and its SSE connection is live, a new public booking emits
a private-data-free local notification (with permission). This works for any booking
date, not just the visible calendar day. Reconnects do not replay alerts. Background
APNs delivery is NOT implemented: an APNs key/capability, device registration and a
server delivery worker are still required. The notification test proves only local
iPhone permission, not remote push delivery. iOS Focus and sound settings still apply.
