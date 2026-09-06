import http from 'node:http';
import { randomBytes } from 'node:crypto';
import { DateTime } from 'luxon';
import { z } from 'zod';
import { transaction } from './db.js';
import { APIError, digest, verifyPassword, hashPassword, bookingInput, serviceInput, hoursInput, uuid, iso, availableSlots, fitsHours } from './domain.js';

async function body(req) {
  let size = 0;
  const chunks = [];
  for await (const chunk of req) {
    size += chunk.length;
    if (size > 65536) throw new APIError(413, 'Request too large');
    chunks.push(chunk);
  }
  try { return JSON.parse(Buffer.concat(chunks).toString('utf8')); }
  catch { throw new APIError(400, 'Invalid JSON'); }
}

function send(res, status, value) {
  res.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff' });
  res.end(JSON.stringify(value));
}

async function owned(db, accountId, businessId) {
  const business = (await db.query('SELECT * FROM businesses WHERE id=$1 AND owner_id=$2', [uuid.parse(businessId), accountId])).rows[0];
  if (!business) throw new APIError(404, 'Business not found');
  return business;
}

async function staffFor(db, accountId, staffId) {
  const row = (await db.query('SELECT s.* FROM staff s JOIN businesses b ON b.id=s.business_id WHERE s.id=$1 AND b.owner_id=$2 FOR UPDATE OF s', [uuid.parse(staffId), accountId])).rows[0];
  if (!row) throw new APIError(404, 'Staff not found');
  return row;
}

const bookingColumns = `e.*, c.name AS client_name, c.phone AS client_phone, s.name AS staff_name`;
const bookingJoins = `calendar_entries e LEFT JOIN clients c ON c.id=e.client_id JOIN staff s ON s.id=e.staff_id`;

export async function createAPI(pool) {
  const dummyHash = await hashPassword(randomBytes(32).toString('hex'));
  const attempts = new Map();
  const subscribers = new Set();
  const events = await pool.connect();
  await events.query('LISTEN torly_calendar');
  events.on?.('notification', message => {
    for (const stream of subscribers) {
      if (stream.businessIds.has(message.payload)) stream.res.write('event: calendar\ndata: changed\n\n');
    }
  });
  // If the database listener disconnects, close streams so clients reconnect and refetch.
  events.on?.('error', () => {
    for (const stream of subscribers) stream.res.end();
    server.emit('databaseDisconnected');
  });
  const server = http.createServer(async (req, res) => {
    try {
      const url = new URL(req.url, 'http://localhost');
      const path = url.pathname;
      if (req.method === 'GET' && path === '/health') {
        await pool.query('SELECT 1');
        return send(res, 200, { ok: true, service: 'torly-api', version: '0.2.0' });
      }
      if (req.method === 'POST' && path === '/v1/session') {
        const input = z.object({ email: z.email().max(254), password: z.string().min(1).max(200) }).parse(await body(req));
        const email = input.email.toLowerCase();
        const now = Date.now();
        for (const [key, value] of attempts) if (value.until < now) attempts.delete(key);
        const keys = [`email:${email}`, `ip:${req.socket.remoteAddress}`];
        if (attempts.size > 10000 || keys.some(key => (attempts.get(key)?.count || 0) >= 20)) throw new APIError(429, 'Too many attempts. Try again in 15 minutes.');
        for (const key of keys) { const item = attempts.get(key) || { count: 0, until: now + 900000 }; item.count++; attempts.set(key, item); }
        const account = (await pool.query('SELECT * FROM accounts WHERE email=$1', [email])).rows[0];
        const valid = await verifyPassword(input.password, account?.password_hash || dummyHash);
        if (!account || !valid) throw new APIError(401, 'Invalid email or password');
        const token = randomBytes(32).toString('base64url');
        await pool.query('DELETE FROM sessions WHERE expires_at < now()');
        await pool.query("INSERT INTO sessions VALUES($1,$2,now()+interval '7 days')", [digest(token), account.id]);
        return send(res, 201, { token });
      }
      if (req.method === 'GET' && path === '/v1/categories') return send(res, 200, { categories: (await pool.query('SELECT * FROM categories ORDER BY id')).rows });
      const publicMatch = path.match(/^\/v1\/public\/([a-z0-9-]+)$/);
      if (req.method === 'GET' && publicMatch) {
        const business = (await pool.query('SELECT id,slug,name,address,phone,timezone,currency,locale,category_id FROM businesses WHERE slug=$1 AND published=true', [publicMatch[1]])).rows[0];
        if (!business) throw new APIError(404, 'Business not found');
        return send(res, 200, { business, services: (await pool.query('SELECT id,name,price_minor,minutes FROM services WHERE business_id=$1 AND active=true', [business.id])).rows });
      }

      const token = req.headers.authorization?.match(/^Bearer ([A-Za-z0-9_-]{43})$/)?.[1];
      const session = token && (await pool.query('SELECT account_id, expires_at FROM sessions WHERE token_hash=$1 AND expires_at>now()', [digest(token)])).rows[0];
      if (!session) throw new APIError(401, 'Sign in required');
      const accountId = session.account_id;
      if (req.method === 'DELETE' && path === '/v1/session') {
        await pool.query('DELETE FROM sessions WHERE token_hash=$1', [digest(token)]);
        for (const stream of subscribers) if (stream.tokenHash === digest(token)) stream.res.end();
        return send(res, 200, { ok: true });
      }
      if (req.method === 'GET' && path === '/v1/events') {
        const rows = (await pool.query('SELECT id FROM businesses WHERE owner_id=$1', [accountId])).rows;
        res.writeHead(200, { 'Content-Type': 'text/event-stream', 'Cache-Control': 'no-cache', 'X-Accel-Buffering': 'no' });
        res.write('event: connected\ndata: ready\n\n');
        const stream = { res, businessIds: new Set(rows.map(b => b.id)), tokenHash: digest(token) };
        subscribers.add(stream);
        const heartbeat = setInterval(() => {
          if (Date.now() >= new Date(session.expires_at).getTime()) res.end();
          else res.write(': heartbeat\n\n');
        }, 25000);
        res.on('close', () => { clearInterval(heartbeat); subscribers.delete(stream); });
        return;
      }
      if (req.method === 'GET' && path === '/v1/owner') {
        const businesses = (await pool.query('SELECT * FROM businesses WHERE owner_id=$1 ORDER BY created_at', [accountId])).rows;
        const result = [];
        for (const business of businesses) {
          result.push({ ...business,
            services: (await pool.query('SELECT * FROM services WHERE business_id=$1 ORDER BY name', [business.id])).rows,
            staff: (await pool.query('SELECT * FROM staff WHERE business_id=$1 ORDER BY name', [business.id])).rows,
            hours: (await pool.query('SELECT h.* FROM working_hours h JOIN staff s ON s.id=h.staff_id WHERE s.business_id=$1 ORDER BY h.weekday', [business.id])).rows
          });
        }
        return send(res, 200, { businesses: result });
      }
      if (req.method === 'GET' && path === '/v1/bookings') {
        const businessId = url.searchParams.get('businessId');
        await owned(pool, accountId, businessId);
        const from = iso.parse(url.searchParams.get('from'));
        const to = iso.parse(url.searchParams.get('to'));
        if (new Date(to) <= new Date(from) || new Date(to) - new Date(from) > 32 * 86400000) throw new APIError(400, 'Choose at most 32 days');
        return send(res, 200, { bookings: (await pool.query(`SELECT ${bookingColumns} FROM ${bookingJoins} WHERE e.business_id=$1 AND e.starts_at<$3 AND e.ends_at>$2 ORDER BY e.starts_at`, [businessId, from, to])).rows });
      }
      if (req.method === 'GET' && path === '/v1/availability') {
        const business = await owned(pool, accountId, url.searchParams.get('businessId'));
        const staffId = uuid.parse(url.searchParams.get('staffId'));
        const serviceId = uuid.parse(url.searchParams.get('serviceId'));
        const staff = (await pool.query('SELECT id FROM staff WHERE id=$1 AND business_id=$2', [staffId, business.id])).rows[0];
        const service = (await pool.query('SELECT * FROM services WHERE id=$1 AND business_id=$2 AND active=true', [serviceId, business.id])).rows[0];
        if (!staff || !service) throw new APIError(404, 'Staff or active service not found');
        const date = z.string().regex(/^\d{4}-\d{2}-\d{2}$/).parse(url.searchParams.get('date'));
        const day = DateTime.fromISO(date, { zone: business.timezone });
        if (!day.isValid) throw new APIError(400, 'Invalid date');
        const hours = (await pool.query('SELECT * FROM working_hours WHERE staff_id=$1', [staffId])).rows;
        const entries = (await pool.query("SELECT starts_at,ends_at FROM calendar_entries WHERE staff_id=$1 AND status<>'cancelled' AND starts_at<$3 AND ends_at>$2", [staffId, day.toISO(), day.plus({ days: 1 }).toISO()])).rows;
        return send(res, 200, { slots: availableSlots(date, business.timezone, service.minutes, hours, entries) });
      }
      if (req.method === 'POST' && path === '/v1/bookings') {
        const input = bookingInput.parse(await body(req));
        const result = await transaction(pool, async db => {
          const business = await owned(db, accountId, input.businessId);
          const staff = await staffFor(db, accountId, input.staffId);
          if (staff.business_id !== business.id) throw new APIError(400, 'Staff belongs to another business');
          const hash = digest(JSON.stringify(input));
          const previous = (await db.query('SELECT * FROM calendar_entries WHERE request_key=$1', [input.requestKey])).rows[0];
          if (previous) {
            if (previous.business_id !== business.id || previous.request_hash !== hash) throw new APIError(409, 'Request key already used');
            return previous;
          }
          const service = (await db.query('SELECT * FROM services WHERE id=$1 AND business_id=$2 AND active=true', [input.serviceId, business.id])).rows[0];
          if (!service) throw new APIError(400, 'Configure service price and duration first');
          const hours = (await db.query('SELECT * FROM working_hours WHERE staff_id=$1', [staff.id])).rows;
          if (new Date(input.startsAt) <= new Date() || !fitsHours(input.startsAt, service.minutes, business.timezone, hours)) throw new APIError(409, 'Appointment is outside working hours or in the past');
          const client = (await db.query('INSERT INTO clients(business_id,name,phone) VALUES($1,$2,$3) ON CONFLICT(business_id,phone) DO UPDATE SET name=excluded.name RETURNING id', [business.id, input.clientName, input.clientPhone])).rows[0];
          const end = DateTime.fromISO(input.startsAt).plus({ minutes: service.minutes }).toUTC().toISO();
          const entry = (await db.query("INSERT INTO calendar_entries(business_id,staff_id,service_id,client_id,kind,starts_at,ends_at,service_name,price_minor,currency,request_key,request_hash) VALUES($1,$2,$3,$4,'booking',$5,$6,$7,$8,$9,$10,$11) RETURNING *", [business.id, staff.id, service.id, client.id, input.startsAt, end, service.name, service.price_minor, business.currency, input.requestKey, hash])).rows[0];
          await db.query("INSERT INTO notification_jobs(booking_id,channel,run_at) VALUES($1,'whatsapp',$2)", [entry.id, DateTime.fromISO(input.startsAt).minus({ hours: 2 }).toUTC().toISO()]);
          await db.query("SELECT pg_notify('torly_calendar',$1)", [business.id]);
          return entry;
        });
        return send(res, 201, { booking: result });
      }
      const bookingMatch = path.match(/^\/v1\/bookings\/([\w-]+)$/);
      if (req.method === 'PATCH' && bookingMatch) {
        const input = z.object({ revision: z.number().int().positive(), status: z.enum(['confirmed','cancelled','completed','no_show']).optional(), startsAt: iso.optional() }).refine(v => !!v.status !== !!v.startsAt).parse(await body(req));
        const result = await transaction(pool, async db => {
          const entry = (await db.query('SELECT e.* FROM calendar_entries e JOIN businesses b ON b.id=e.business_id WHERE e.id=$1 AND b.owner_id=$2 FOR UPDATE OF e', [uuid.parse(bookingMatch[1]), accountId])).rows[0];
          if (!entry) throw new APIError(404, 'Booking not found');
          if (entry.revision !== input.revision) throw new APIError(409, 'Booking changed. Refresh and try again.');
          if (['cancelled','completed','no_show'].includes(entry.status)) throw new APIError(409, 'Booking is already closed');
          if (input.startsAt) {
            await staffFor(db, accountId, entry.staff_id);
            const business = await owned(db, accountId, entry.business_id);
            const minutes = (new Date(entry.ends_at) - new Date(entry.starts_at)) / 60000;
            const hours = (await db.query('SELECT * FROM working_hours WHERE staff_id=$1', [entry.staff_id])).rows;
            if (new Date(input.startsAt) <= new Date() || !fitsHours(input.startsAt, minutes, business.timezone, hours)) throw new APIError(409, 'Outside working hours');
            await db.query("UPDATE calendar_entries SET starts_at=$2,ends_at=$3,status='pending',revision=revision+1 WHERE id=$1", [entry.id, input.startsAt, DateTime.fromISO(input.startsAt).plus({ minutes }).toUTC().toISO()]);
            await db.query("UPDATE notification_jobs SET run_at=$2,status='disabled' WHERE booking_id=$1", [entry.id, DateTime.fromISO(input.startsAt).minus({ hours: 2 }).toUTC().toISO()]);
          } else {
            if (['completed','no_show'].includes(input.status) && new Date(entry.starts_at) > new Date()) throw new APIError(409, 'Appointment has not started');
            await db.query('UPDATE calendar_entries SET status=$2,revision=revision+1 WHERE id=$1', [entry.id, input.status]);
            if (input.status === 'no_show') await db.query('UPDATE clients SET no_show_count=no_show_count+1 WHERE id=$1', [entry.client_id]);
            if (input.status !== 'confirmed') await db.query("UPDATE notification_jobs SET status='cancelled' WHERE booking_id=$1 AND status<>'sent'", [entry.id]);
          }
          await db.query("SELECT pg_notify('torly_calendar',$1)", [entry.business_id]);
          return (await db.query('SELECT * FROM calendar_entries WHERE id=$1', [entry.id])).rows[0];
        });
        return send(res, 200, { booking: result });
      }
      const serviceMatch = path.match(/^\/v1\/services\/([\w-]+)$/);
      if (req.method === 'PUT' && serviceMatch) {
        const input = serviceInput.parse(await body(req));
        const service = (await pool.query('UPDATE services s SET name=$3,price_minor=$4,minutes=$5,active=true FROM businesses b WHERE s.id=$1 AND b.id=s.business_id AND b.owner_id=$2 RETURNING s.*', [uuid.parse(serviceMatch[1]), accountId, input.name, input.priceMinor, input.minutes])).rows[0];
        if (!service) throw new APIError(404, 'Service not found');
        await pool.query("SELECT pg_notify('torly_calendar',$1)", [service.business_id]);
        return send(res, 200, { service });
      }
      const hoursMatch = path.match(/^\/v1\/staff\/([\w-]+)\/hours$/);
      if (req.method === 'PUT' && hoursMatch) {
        const hours = hoursInput.parse(await body(req));
        await transaction(pool, async db => {
          const staff = await staffFor(db, accountId, hoursMatch[1]);
          await db.query('DELETE FROM working_hours WHERE staff_id=$1', [staff.id]);
          for (const day of hours) await db.query('INSERT INTO working_hours VALUES($1,$2,$3,$4)', [staff.id, day.weekday, day.opensAt, day.closesAt]);
          await db.query("SELECT pg_notify('torly_calendar',$1)", [staff.business_id]);
        });
        return send(res, 200, { ok: true });
      }
      throw new APIError(404, 'Not found');
    } catch (error) {
      if (res.headersSent) return res.end();
      const status = error instanceof z.ZodError ? 400 : ['23P01','23505','40P01'].includes(error.code) ? 409 : error.status || 500;
      if (status === 500) console.error(JSON.stringify({ event: 'request_error', code: error.code || 'unknown' }));
      send(res, status, { error: status === 500 ? 'Server unavailable' : status === 400 ? 'Invalid request fields' : status === 409 && !error.status ? 'Slot or request is already taken. Refresh and try again.' : error.message });
    }
  });
  server.requestTimeout = 15000;
  server.headersTimeout = 10000;
  server.on('close', () => {
    for (const stream of subscribers) stream.res.end();
    events.release();
  });
  return server;
}
