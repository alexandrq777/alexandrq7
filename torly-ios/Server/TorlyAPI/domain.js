import { DateTime, IANAZone } from 'luxon';
import { z } from 'zod';
import { randomBytes, scrypt as scryptCallback, timingSafeEqual, createHash } from 'node:crypto';
import { promisify } from 'node:util';

const scrypt = promisify(scryptCallback);
export const text = z.string().trim().min(1).max(200);
export const uuid = z.uuid();
export const phone = z.string().regex(/^\+[1-9]\d{7,14}$/);
export const timezone = z.string().refine(value => IANAZone.isValidZone(value));
export const iso = z.iso.datetime({ offset: true });
export const serviceInput = z.object({ name: text, priceMinor: z.number().int().min(0).max(100000000), minutes: z.number().int().min(5).max(480) });
export const bookingInput = z.object({ businessId: uuid, staffId: uuid, serviceId: uuid, startsAt: iso, clientName: text, clientPhone: phone, requestKey: uuid });
export const hoursInput = z.array(z.object({ weekday: z.number().int().min(0).max(6), opensAt: z.string().regex(/^([01]\d|2[0-3]):[0-5]\d$/), closesAt: z.string().regex(/^([01]\d|2[0-3]):[0-5]\d$/) }).refine(day => day.opensAt < day.closesAt)).max(7).refine(days => new Set(days.map(d => d.weekday)).size === days.length);
export const businessInput = z.object({ name: text, phone, address: text, categoryId: text, timezone,
  currency: z.enum(['ILS','USD','EUR','GBP']), locale: z.enum(['he','en']), country: z.enum(['IL','US','GB','DE','FR','ES']) });

export class APIError extends Error {
  constructor(status, message) { super(message); this.status = status; }
}
export const digest = value => createHash('sha256').update(value).digest('hex');
export async function hashPassword(password) {
  const salt = randomBytes(16).toString('hex');
  return `${salt}:${(await scrypt(password, salt, 64)).toString('hex')}`;
}
export async function verifyPassword(password, encoded) {
  const [salt, hash] = encoded.split(':');
  const candidate = await scrypt(password, salt, 64);
  const expected = Buffer.from(hash, 'hex');
  return candidate.length === expected.length && timingSafeEqual(candidate, expected);
}

export function fitsHours(startsAt, minutes, zone, hours) {
  const start = DateTime.fromISO(startsAt, { setZone: true }).setZone(zone);
  const end = start.plus({ minutes });
  const day = hours.find(h => h.weekday === start.weekday % 7);
  return !!day && start.isValid && start.second === 0 && start.millisecond === 0 &&
    start.toISODate() === end.toISODate() && start.toFormat('HH:mm:ss') >= day.opens_at &&
    end.toFormat('HH:mm:ss') <= day.closes_at;
}

export function availableSlots(date, zone, minutes, hours, entries, now = DateTime.utc()) {
  const day = DateTime.fromISO(date, { zone });
  if (!day.isValid || day.toISODate() !== date) throw new APIError(400, 'Invalid date');
  const result = [];
  // Iterate real instants, not wall-clock strings: DST folds and gaps stay unambiguous.
  for (let time = day.startOf('day'); time < day.plus({ days: 1 }).startOf('day'); time = time.plus({ minutes: 15 })) {
    const end = time.plus({ minutes });
    if (time <= now || !fitsHours(time.toISO(), minutes, zone, hours)) continue;
    if (entries.some(e => time.toMillis() < new Date(e.ends_at).getTime() && end.toMillis() > new Date(e.starts_at).getTime())) continue;
    result.push(time.toUTC().toISO());
  }
  return result;
}
