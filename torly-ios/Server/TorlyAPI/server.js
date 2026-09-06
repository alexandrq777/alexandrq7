import http from "node:http";
import { randomUUID } from "node:crypto";

const PORT = Number(process.env.PORT || 3100);
const HOST = process.env.HOST || "127.0.0.1";

const locales = [
  { id: "en", name: "English", direction: "ltr" },
  { id: "he", name: "עברית", direction: "rtl" }
];

const currencies = [
  { code: "ILS", symbol: "₪", minorUnit: 100 },
  { code: "USD", symbol: "$", minorUnit: 100 },
  { code: "EUR", symbol: "€", minorUnit: 100 },
  { code: "GBP", symbol: "£", minorUnit: 100 }
];

const countries = [
  { code: "IL", name: "Israel", defaultCurrency: "ILS", defaultTimezone: "Asia/Jerusalem", phonePrefix: "+972" },
  { code: "US", name: "United States", defaultCurrency: "USD", defaultTimezone: "America/New_York", phonePrefix: "+1" },
  { code: "GB", name: "United Kingdom", defaultCurrency: "GBP", defaultTimezone: "Europe/London", phonePrefix: "+44" },
  { code: "DE", name: "Germany", defaultCurrency: "EUR", defaultTimezone: "Europe/Berlin", phonePrefix: "+49" },
  { code: "FR", name: "France", defaultCurrency: "EUR", defaultTimezone: "Europe/Paris", phonePrefix: "+33" },
  { code: "ES", name: "Spain", defaultCurrency: "EUR", defaultTimezone: "Europe/Madrid", phonePrefix: "+34" }
];

const whatsappTemplates = [
  {
    key: "booking_created",
    locale: "en",
    channel: "whatsapp",
    text: "Your appointment at {{business_name}} is booked for {{date}} at {{time}}."
  },
  {
    key: "booking_created",
    locale: "he",
    channel: "whatsapp",
    text: "התור שלך ב{{business_name}} נקבע ל{{date}} בשעה {{time}}."
  },
  {
    key: "same_day_confirmation",
    locale: "en",
    channel: "whatsapp",
    text: "You have an appointment today at {{time}}. Please confirm, reschedule, or cancel."
  },
  {
    key: "same_day_confirmation",
    locale: "he",
    channel: "whatsapp",
    text: "יש לך תור היום בשעה {{time}}. נא לאשר, לדחות או לבטל."
  }
];

const paymentConfig = {
  trialMonths: 2,
  defaultPlanId: "pro",
  providers: [
    { id: "stripe", status: "ready_for_integration", countries: ["US", "GB", "DE", "FR", "ES"] },
    { id: "israel_local", status: "planned", countries: ["IL"] }
  ]
};

const services = [
  { id: "svc_haircut", businessId: "biz_barber_dizengoff", name: "Men's haircut", priceMinor: 7900, currency: "ILS", minutes: 35 },
  { id: "svc_beard", businessId: "biz_barber_dizengoff", name: "Beard trim", priceMinor: 4900, currency: "ILS", minutes: 25 },
  { id: "svc_nails", businessId: "biz_nails_maya", name: "Gel manicure", priceMinor: 12000, currency: "ILS", minutes: 70 }
];

const businesses = [
  {
    id: "biz_barber_dizengoff",
    ownerId: "usr_owner_demo",
    slug: "barber-dizengoff",
    name: "Barber Dizengoff",
    category: "Барбер",
    countryCode: "IL",
    city: "Тель-Авив",
    phoneE164: "+972524441091",
    publicUrl: "https://torly.app/barber-dizengoff",
    rating: 4.9,
    timezone: "Asia/Jerusalem",
    defaultLocale: "en",
    supportedLocales: ["en", "he"],
    currency: "ILS"
  },
  {
    id: "biz_nails_maya",
    ownerId: "usr_maya_demo",
    slug: "nails-by-maya",
    name: "Nails by Maya",
    category: "Ногти",
    countryCode: "IL",
    city: "Рамат-Ган",
    phoneE164: "+972541187712",
    publicUrl: "https://torly.app/nails-by-maya",
    rating: 4.8,
    timezone: "Asia/Jerusalem",
    defaultLocale: "he",
    supportedLocales: ["en", "he"],
    currency: "ILS"
  }
];

const workingHours = [
  { businessId: "biz_barber_dizengoff", weekday: 0, isOpen: true, start: "09:00", end: "18:00" },
  { businessId: "biz_barber_dizengoff", weekday: 1, isOpen: true, start: "09:00", end: "18:00" },
  { businessId: "biz_barber_dizengoff", weekday: 2, isOpen: true, start: "10:00", end: "19:00" },
  { businessId: "biz_barber_dizengoff", weekday: 3, isOpen: true, start: "09:00", end: "18:00" },
  { businessId: "biz_barber_dizengoff", weekday: 4, isOpen: true, start: "10:00", end: "20:00" },
  { businessId: "biz_barber_dizengoff", weekday: 5, isOpen: true, start: "09:00", end: "14:00" },
  { businessId: "biz_barber_dizengoff", weekday: 6, isOpen: false, start: null, end: null }
];

const bookings = [
  {
    id: "book_001",
    businessId: "biz_barber_dizengoff",
    serviceId: "svc_haircut",
    clientName: "Даниэль Коэн",
    clientPhoneE164: "+972524441091",
    startsAtUtc: "2026-09-03T06:30:00.000Z",
    businessTimezone: "Asia/Jerusalem",
    locale: "he",
    status: "confirmed",
    reminderStatus: "scheduled",
    reminderTemplateKey: "same_day_confirmation"
  },
  {
    id: "book_002",
    businessId: "biz_barber_dizengoff",
    serviceId: "svc_beard",
    clientName: "Алекс Розен",
    clientPhoneE164: "+972502208820",
    startsAtUtc: "2026-09-04T10:15:00.000Z",
    businessTimezone: "Asia/Jerusalem",
    locale: "en",
    status: "pending",
    reminderStatus: "none",
    reminderTemplateKey: null
  }
];

const clients = [
  { id: "client_001", businessId: "biz_barber_dizengoff", name: "Даниэль Коэн", phoneE164: "+972524441091", locale: "he", visits: 8, totalSpentMinor: 64000, currency: "ILS", note: "Любит утренние слоты" },
  { id: "client_002", businessId: "biz_barber_dizengoff", name: "Алекс Розен", phoneE164: "+972502208820", locale: "en", visits: 3, totalSpentMinor: 21000, currency: "ILS", note: "Часто пишет в WhatsApp" }
];

const plans = [
  { id: "trial", name: "Trial", priceMinor: 0, currency: "ILS", trialMonths: 2, note: "первые 2 месяца бесплатно" },
  { id: "pro", name: "Torly Pro", priceMinor: 4900, currency: "ILS", trialMonths: 2, note: "основной тариф после trial" }
];

const server = http.createServer(async (req, res) => {
  try {
    const url = new URL(req.url || "/", `http://${req.headers.host || "localhost"}`);

    if (req.method === "OPTIONS") {
      sendEmpty(res, 204);
      return;
    }

    if (req.method === "GET" && url.pathname === "/health") {
      sendJson(res, 200, { ok: true, service: "torly-api", version: "0.1.0" });
      return;
    }

    if (req.method === "GET" && url.pathname === "/api/bootstrap") {
      sendJson(res, 200, {
        plans,
        suggestedDefaultPlan: "pro",
        locales,
        currencies,
        countries,
        whatsappTemplates,
        paymentConfig
      });
      return;
    }

    if (req.method === "GET" && url.pathname === "/api/businesses") {
      sendJson(res, 200, {
        businesses: businesses.map(business => ({
          ...business,
          services: services.filter(service => service.businessId === business.id),
          nextSlot: nextAvailableSlot(business.id)
        }))
      });
      return;
    }

    const publicBusinessMatch = url.pathname.match(/^\/api\/businesses\/([\w-]+)$/);
    if (req.method === "GET" && publicBusinessMatch) {
      const business = findBusiness(publicBusinessMatch[1]);
      if (!business) {
        sendJson(res, 404, { error: "Business not found" });
        return;
      }

      sendJson(res, 200, {
        business,
        services: services.filter(service => service.businessId === business.id),
        workingHours: workingHours.filter(day => day.businessId === business.id)
      });
      return;
    }

    const availabilityMatch = url.pathname.match(/^\/api\/businesses\/([\w-]+)\/availability$/);
    if (req.method === "GET" && availabilityMatch) {
      const business = findBusiness(availabilityMatch[1]);
      if (!business) {
        sendJson(res, 404, { error: "Business not found" });
        return;
      }

      sendJson(res, 200, buildAvailability({
        businessId: business.id,
        month: url.searchParams.get("month") || "2026-09"
      }));
      return;
    }

    if (req.method === "POST" && url.pathname === "/api/bookings") {
      const body = await readJson(req);
      const booking = createBooking(body);
      bookings.push(booking);
      upsertClientFromBooking(booking);
      sendJson(res, 201, { booking });
      return;
    }

    if (req.method === "GET" && url.pathname === "/api/owner/dashboard") {
      const businessId = url.searchParams.get("businessId") || "biz_barber_dizengoff";
      const businessBookings = bookings.filter(booking => booking.businessId === businessId);
      const revenue = businessBookings.reduce((sum, booking) => {
        const service = services.find(item => item.id === booking.serviceId);
        return sum + (service?.priceMinor || 0);
      }, 0);

      sendJson(res, 200, {
        metrics: {
          bookingsToday: businessBookings.length,
          revenueMinor: revenue,
          currency: findBusiness(businessId)?.currency || "ILS",
          clients: clients.filter(client => client.businessId === businessId).length,
          reminders: businessBookings.filter(booking => booking.reminderStatus === "scheduled").length
        },
        bookings: businessBookings.map(expandBooking),
        clients: clients.filter(client => client.businessId === businessId),
        services: services.filter(service => service.businessId === businessId)
      });
      return;
    }

    if (req.method === "PUT" && url.pathname === "/api/owner/settings") {
      const body = await readJson(req);
      sendJson(res, 200, {
        saved: true,
        business: body.business || null,
        services: body.services || [],
        workingHours: body.workingHours || []
      });
      return;
    }

    sendJson(res, 404, { error: "Not found" });
  } catch (error) {
    console.error(error);
    sendJson(res, 500, { error: "Server error" });
  }
});

server.listen(PORT, HOST, () => {
  console.log(`torly-api listening on http://${HOST}:${PORT}`);
});

function findBusiness(slugOrId) {
  return businesses.find(business => business.slug === slugOrId || business.id === slugOrId);
}

function buildAvailability({ businessId, month }) {
  const [year, monthNumber] = month.split("-").map(Number);
  const daysInMonth = new Date(year, monthNumber, 0).getDate();
  const days = [];

  for (let day = 1; day <= daysInMonth; day += 1) {
    const date = `${month}-${String(day).padStart(2, "0")}`;
    const weekday = new Date(`${date}T12:00:00+03:00`).getDay();
    const hours = workingHours.find(item => item.businessId === businessId && item.weekday === weekday);
    const allSlots = hours?.isOpen ? slotsBetween(hours.start, hours.end) : [];
    const occupied = new Set(
      bookings
        .filter(booking => booking.businessId === businessId && localDateTimeParts(booking).date === date)
        .map(booking => localDateTimeParts(booking).time)
    );
    const slots = allSlots.filter(slot => !occupied.has(slot));

    days.push({
      date,
      isOpen: Boolean(hours?.isOpen),
      slots
    });
  }

  return { businessId, month, days };
}

function slotsBetween(start, end) {
  const result = [];
  let cursor = minutesFromTime(start);
  const endMinutes = minutesFromTime(end);

  while (cursor + 30 <= endMinutes) {
    result.push(timeFromMinutes(cursor));
    cursor += 30;
  }

  return result;
}

function createBooking(body) {
  const business = findBusiness(String(body.businessSlug || body.businessId || ""));
  const service = services.find(item => item.id === body.serviceId);

  if (!business || !service || service.businessId !== business.id) {
    throw new Error("Invalid booking business or service");
  }

  if (!body.startsAt || !body.clientName || !body.clientPhone) {
    throw new Error("Missing booking fields");
  }

  const locale = locales.some(item => item.id === body.locale) ? body.locale : business.defaultLocale;
  const phoneE164 = normalizePhone(body.clientPhone, business.countryCode);

  return {
    id: `book_${randomUUID()}`,
    businessId: business.id,
    serviceId: service.id,
    clientName: String(body.clientName).trim(),
    clientPhoneE164: phoneE164,
    startsAtUtc: toUtcIso(String(body.startsAt), business.timezone),
    businessTimezone: business.timezone,
    locale,
    status: "pending",
    reminderStatus: "scheduled",
    reminderTemplateKey: "same_day_confirmation"
  };
}

function upsertClientFromBooking(booking) {
  const existing = clients.find(client => client.businessId === booking.businessId && client.phoneE164 === booking.clientPhoneE164);
  const service = services.find(item => item.id === booking.serviceId);
  const business = findBusiness(booking.businessId);

  if (existing) {
    existing.visits += 1;
    existing.totalSpentMinor += service?.priceMinor || 0;
    return;
  }

  clients.push({
    id: `client_${randomUUID()}`,
    businessId: booking.businessId,
    name: booking.clientName,
    phoneE164: booking.clientPhoneE164,
    locale: booking.locale,
    visits: 1,
    totalSpentMinor: service?.priceMinor || 0,
    currency: business?.currency || "ILS",
    note: ""
  });
}

function expandBooking(booking) {
  const service = services.find(service => service.id === booking.serviceId) || null;
  const business = findBusiness(booking.businessId);
  const local = localDateTimeParts(booking);

  return {
    ...booking,
    localDate: local.date,
    localTime: local.time,
    currency: business?.currency || service?.currency || "ILS",
    totalMinor: service?.priceMinor || 0,
    service
  };
}

function nextAvailableSlot(businessId) {
  const today = "2026-09-03";
  const availability = buildAvailability({ businessId, month: "2026-09" });
  const day = availability.days.find(item => item.date >= today && item.slots.length > 0);
  return day ? `${day.date} ${day.slots[0]}` : null;
}

function minutesFromTime(value) {
  const [hours, minutes] = String(value).split(":").map(Number);
  return hours * 60 + minutes;
}

function timeFromMinutes(value) {
  const hours = Math.floor(value / 60);
  const minutes = value % 60;
  return `${String(hours).padStart(2, "0")}:${String(minutes).padStart(2, "0")}`;
}

function toUtcIso(value, timezone) {
  if (value.endsWith("Z") || /[+-]\d\d:\d\d$/.test(value)) {
    return new Date(value).toISOString();
  }

  const offset = timezone === "Asia/Jerusalem" ? "+03:00" : "Z";
  return new Date(`${value}${offset}`).toISOString();
}

function localDateTimeParts(booking) {
  const date = new Date(booking.startsAtUtc);
  const formatter = new Intl.DateTimeFormat("en-CA", {
    timeZone: booking.businessTimezone || "UTC",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    hour12: false
  });
  const parts = Object.fromEntries(formatter.formatToParts(date).map(part => [part.type, part.value]));

  return {
    date: `${parts.year}-${parts.month}-${parts.day}`,
    time: `${parts.hour}:${parts.minute}`
  };
}

function normalizePhone(phone, countryCode) {
  const value = String(phone).trim().replace(/[\s()-]/g, "");
  if (value.startsWith("+")) return value;

  const country = countries.find(item => item.code === countryCode);
  if (!country) return value;

  const withoutLeadingZero = value.startsWith("0") ? value.slice(1) : value;
  return `${country.phonePrefix}${withoutLeadingZero}`;
}

function readJson(req) {
  return new Promise((resolve, reject) => {
    let data = "";
    req.on("data", chunk => {
      data += chunk;
      if (data.length > 128 * 1024) {
        req.destroy();
        reject(new Error("Request too large"));
      }
    });
    req.on("end", () => {
      try {
        resolve(data ? JSON.parse(data) : {});
      } catch (error) {
        reject(error);
      }
    });
    req.on("error", reject);
  });
}

function sendJson(res, status, payload) {
  const body = JSON.stringify(payload, null, 2);
  res.writeHead(status, {
    "Content-Type": "application/json; charset=utf-8",
    "Content-Length": Buffer.byteLength(body),
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "GET,POST,PUT,OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type,Authorization"
  });
  res.end(body);
}

function sendEmpty(res, status) {
  res.writeHead(status, {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "GET,POST,PUT,OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type,Authorization"
  });
  res.end();
}
