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

New public bookings also create a durable, owner-scoped inbox entry. The native bell
shows unread entries; opening one selects its business and booking day. SSE triggers
an inbox refresh, with a 15-second foreground polling fallback. On reopen the app
fetches missed alerts, with per-device deduplication of local notification attempts.
The in-app banner does not require iOS notification permission. Inbox entries are
marked read explicitly, not when a delivery attempt is made. Legacy bookings created
before migration 002 are not backfilled because their public/manual origin is unknown.
This works for any booking date, not just the visible calendar day. Background
APNs delivery is NOT implemented: an APNs key/capability, device registration and a
server delivery worker are still required. The notification test proves only local
iPhone permission, not remote push delivery. iOS Focus and sound settings still apply.

Settings use native switches; server addresses are not exposed in settings. Tap and
scroll haptics default to enabled and are independently configurable. Non-cancelling,
simultaneous window gestures preserve native control and scroll handling; scroll
feedback is distance/time throttled and only active over scroll views during a drag.
The two-second cold-start animation honors Reduce Motion. The compact variant is
shown during owner data operations without a forced delay. Tab titles are inline
under the compact rounded Torly wordmark, avoiding double large-title spacing.
