import http from 'node:http';
import { readFile } from 'node:fs/promises';
import { randomBytes } from 'node:crypto';
import { isIP } from 'node:net';
import { DateTime } from 'luxon';
import { z } from 'zod';
import { transaction } from './db.js';
import { APIError, digest, verifyPassword, hashPassword, bookingInput, serviceInput, hoursInput, businessInput, text, uuid, iso, availableSlots, fitsHours } from './domain.js';

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

async function availability(pool,business,staffId,serviceId,requestedDate,isPublic=false) {
        const staff = (await pool.query('SELECT id FROM staff WHERE id=$1 AND business_id=$2', [staffId, business.id])).rows[0];
        const service = (await pool.query('SELECT * FROM services WHERE id=$1 AND business_id=$2 AND active=true', [serviceId, business.id])).rows[0];
        if (!staff || !service) throw new APIError(404, 'Staff or active service not found');
        const date = z.string().regex(/^\d{4}-\d{2}-\d{2}$/).parse(requestedDate);
        const day = DateTime.fromISO(date, { zone: business.timezone });
        if (isPublic && (day < DateTime.now().setZone(business.timezone).startOf('day') || day > DateTime.now().setZone(business.timezone).plus({days:180}).startOf('day'))) throw new APIError(400,'Choose a date within 180 days');
        if (!day.isValid) throw new APIError(400, 'Invalid date');
        const hours = (await pool.query('SELECT * FROM working_hours WHERE staff_id=$1', [staffId])).rows;
        const entries = (await pool.query("SELECT starts_at,ends_at FROM calendar_entries WHERE staff_id=$1 AND status<>'cancelled' AND starts_at<$3 AND ends_at>$2", [staffId, day.toISO(), day.plus({ days: 1 }).toISO()])).rows;
        return availableSlots(date, business.timezone, service.minutes, hours, entries);
}

async function createBooking(pool, accountId, input, isPublic = false) {
        return await transaction(pool, async db => {
          const business = isPublic
            ? (await db.query('SELECT * FROM businesses WHERE id=$1 AND published=true FOR SHARE',[input.businessId])).rows[0]
            : await owned(db, accountId, input.businessId);
          if (!business) throw new APIError(404,'Business not found');
          const staff = (await db.query('SELECT * FROM staff WHERE id=$1 AND business_id=$2 FOR UPDATE',[input.staffId,business.id])).rows[0];
          if (!staff) throw new APIError(404,'Staff not found');
          if (isPublic && DateTime.fromISO(input.startsAt).setZone(business.timezone).startOf('day') > DateTime.now().setZone(business.timezone).plus({days:180}).startOf('day')) throw new APIError(400,'Choose a date within 180 days');
          if (staff.business_id !== business.id) throw new APIError(400, 'Staff belongs to another business');
          const hash = digest((isPublic ? 'public:' : '') + JSON.stringify(input));
          const previous = (await db.query('SELECT * FROM calendar_entries WHERE request_key=$1', [input.requestKey])).rows[0];
          if (previous) {
            if (previous.business_id !== business.id || previous.request_hash !== hash) throw new APIError(409, 'Request key already used');
            return previous;
          }
          const service = (await db.query('SELECT * FROM services WHERE id=$1 AND business_id=$2 AND active=true', [input.serviceId, business.id])).rows[0];
          if (!service) throw new APIError(400, 'Configure service price and duration first');
          const hours = (await db.query('SELECT * FROM working_hours WHERE staff_id=$1', [staff.id])).rows;
          if (new Date(input.startsAt) <= new Date() || !fitsHours(input.startsAt, service.minutes, business.timezone, hours)) throw new APIError(409, 'Appointment is outside working hours or in the past');
          const client = (await db.query('INSERT INTO clients(business_id,name,phone) VALUES($1,$2,$3) ON CONFLICT(business_id,phone) DO UPDATE SET name=CASE WHEN $4 THEN clients.name ELSE excluded.name END RETURNING id', [business.id, input.clientName, input.clientPhone, isPublic])).rows[0];
          const end = DateTime.fromISO(input.startsAt).plus({ minutes: service.minutes }).toUTC().toISO();
          const entry = (await db.query("INSERT INTO calendar_entries(business_id,staff_id,service_id,client_id,kind,starts_at,ends_at,service_name,price_minor,currency,request_key,request_hash) VALUES($1,$2,$3,$4,'booking',$5,$6,$7,$8,$9,$10,$11) RETURNING *", [business.id, staff.id, service.id, client.id, input.startsAt, end, service.name, service.price_minor, business.currency, input.requestKey, hash])).rows[0];
          await db.query("INSERT INTO notification_jobs(booking_id,channel,run_at) VALUES($1,'whatsapp',$2)", [entry.id, DateTime.fromISO(input.startsAt).minus({ hours: 2 }).toUTC().toISO()]);
          await db.query("SELECT pg_notify('torly_calendar',$1)", [business.id]);
          if (isPublic) await db.query("SELECT pg_notify('torly_online_booking',$1)", [business.id]);
          return entry;
        });

}

export async function createAPI(pool) {
  const dummyHash = await hashPassword(randomBytes(32).toString('hex'));
  const attempts = new Map();
  const throttle = (key, limit) => {
    const now = Date.now();
    for (const [id,value] of attempts) if (value.until < now) attempts.delete(id);
    const item = attempts.get(key) || {count:0,until:now+900000};
    if (attempts.size > 10000 || item.count >= limit) throw new APIError(429, 'Too many attempts. Try again in 15 minutes.');
    item.count++;
    attempts.set(key,item);
  };
  const subscribers = new Set();
  const events = await pool.connect();
  await events.query('LISTEN torly_calendar');
  await events.query('LISTEN torly_online_booking');
  events.on?.('notification', message => {
    const event = message.channel === 'torly_online_booking' ? 'online-booking' : 'calendar';
    for (const stream of subscribers) {
      if (stream.businessIds.has(message.payload)) stream.res.write(`event: ${event}\ndata: changed\n\n`);
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
      const forwardedIP = req.headers['x-real-ip'];
      const remoteIP = process.env.TRUST_PROXY === '1' && typeof forwardedIP === 'string' && isIP(forwardedIP) ? forwardedIP : req.socket.remoteAddress;
      if (req.method === 'GET' && path === '/health') {
        await pool.query('SELECT 1');
        return send(res, 200, { ok: true, service: 'torly-api', version: '0.4.0' });
      }
      if (req.method === 'POST' && path === '/v1/accounts') {
        throttle(`register:${remoteIP}`,10);
        const input = z.object({email:z.email().max(254),password:z.string().min(12).max(200)}).parse(await body(req));
        const passwordHash = await hashPassword(input.password);
        const token = randomBytes(32).toString('base64url');
        await transaction(pool, async db => {
          if ((await db.query('SELECT id FROM accounts WHERE email=$1',[input.email.toLowerCase()])).rowCount) throw new APIError(409,'This email is already registered');
          const account = (await db.query('INSERT INTO accounts(email,password_hash) VALUES($1,$2) RETURNING id',[input.email.toLowerCase(),passwordHash])).rows[0];
          await db.query("INSERT INTO sessions VALUES($1,$2,now()+interval '7 days')",[digest(token),account.id]);
        });
        return send(res,201,{token});
      }
      if (req.method === 'POST' && path === '/v1/session') {
        const input = z.object({ email: z.email().max(254), password: z.string().min(1).max(200) }).parse(await body(req));
        const email = input.email.toLowerCase();
        throttle(`email:${email}`,20);
        throttle(`login:${remoteIP}`,120);
        const account = (await pool.query('SELECT * FROM accounts WHERE email=$1', [email])).rows[0];
        const valid = await verifyPassword(input.password, account?.password_hash || dummyHash);
        if (!account || !valid) throw new APIError(401, 'Invalid email or password');
        const token = randomBytes(32).toString('base64url');
        await pool.query('DELETE FROM sessions WHERE expires_at < now()');
        await pool.query("INSERT INTO sessions VALUES($1,$2,now()+interval '7 days')", [digest(token), account.id]);
        return send(res, 201, { token });
      }
      if (req.method === 'GET' && path === '/v1/categories') return send(res, 200, { categories: (await pool.query('SELECT * FROM categories ORDER BY id')).rows });
      if (['GET','HEAD'].includes(req.method) && /^\/book\/[a-z0-9-]+\/?$/i.test(path)) {
        res.writeHead(200, {'Content-Type':'text/html; charset=utf-8','Cache-Control':'no-store',
          'Content-Security-Policy':"default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self'; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'",
          'Referrer-Policy':'no-referrer','X-Content-Type-Options':'nosniff'});
        return res.end(req.method === 'HEAD' ? undefined : await readFile(new URL('./public/booking.html',import.meta.url)));
      }
      const assets = {'/booking.js':['booking.js','text/javascript'],'/booking.css':['booking.css','text/css'],'/torly-icon.png':['torly-icon.png','image/png']};
      if (['GET','HEAD'].includes(req.method) && assets[path]) {
        const [file,type] = assets[path];
        res.writeHead(200,{'Content-Type':type,'Cache-Control':'no-cache','X-Content-Type-Options':'nosniff'});
        return res.end(req.method === 'HEAD' ? undefined : await readFile(new URL('./public/'+file,import.meta.url)));
      }
      const publicMatch = path.match(/^\/v1\/public\/([a-z0-9-]+)(?:\/(availability|bookings))?$/i);
      if (publicMatch) {
        throttle('public:'+remoteIP,300);
        const business = (await pool.query('SELECT id,slug,name,address,phone,timezone,currency,locale,category_id FROM businesses WHERE lower(slug)=lower($1) AND published=true', [publicMatch[1]])).rows[0];
        if (!business) throw new APIError(404, 'Business not found');
        if (req.method === 'GET' && !publicMatch[2]) {
          return send(res,200,{business,
            services:(await pool.query('SELECT id,name,price_minor,minutes FROM services WHERE business_id=$1 AND active=true ORDER BY name',[business.id])).rows,
            staff:(await pool.query('SELECT id,name FROM staff WHERE business_id=$1 ORDER BY name',[business.id])).rows});
        }
        if (req.method === 'GET' && publicMatch[2]==='availability') {
          const staffId=uuid.parse(url.searchParams.get('staffId'));
          const serviceId=uuid.parse(url.searchParams.get('serviceId'));
          return send(res,200,{slots:await availability(pool,business,staffId,serviceId,url.searchParams.get('date'),true)});
        }
        if (req.method === 'POST' && publicMatch[2]==='bookings') {
          throttle('public-write:'+remoteIP,10);
          const input=bookingInput.parse({...await body(req),businessId:business.id});
          throttle('public-phone:'+digest(input.clientPhone),10);
          const entry=await createBooking(pool,null,input,true);
          // Public callers receive only this submission, never client records or owner credentials.
          return send(res,201,{booking:{id:entry.id,starts_at:entry.starts_at,ends_at:entry.ends_at,status:entry.status,service_name:entry.service_name}});
        }
        throw new APIError(404,'Not found');
      }

      const token = req.headers.authorization?.match(/^Bearer ([A-Za-z0-9_-]{43})$/)?.[1];
      const session = token && (await pool.query('SELECT account_id, expires_at FROM sessions WHERE token_hash=$1 AND expires_at>now()', [digest(token)])).rows[0];
      if (!session) throw new APIError(401, 'Sign in required');
      const accountId = session.account_id;
      if (req.method === 'POST' && path === '/v1/businesses') {
        const input = businessInput.extend({staffName:text,hours:hoursInput,requestKey:uuid}).parse(await body(req));
        const result = await transaction(pool,async db=>{
          await db.query('SELECT id FROM accounts WHERE id=$1 FOR UPDATE',[accountId]);
          const previous = (await db.query('SELECT id FROM businesses WHERE id=$1 AND owner_id=$2',[input.requestKey,accountId])).rows[0];
          if (previous) return previous;
          const category = (await db.query('SELECT id FROM categories WHERE id=$1',[input.categoryId])).rows[0];
          if (!category) throw new APIError(400,'Unknown category');
          const business = (await db.query('INSERT INTO businesses(id,owner_id,slug,name,phone,address,category_id,timezone,currency,locale,country) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11) RETURNING id',[input.requestKey,accountId,`b-${input.requestKey.toLowerCase()}`,input.name,input.phone,input.address,input.categoryId,input.timezone,input.currency,input.locale,input.country])).rows[0];
          const staff = (await db.query('INSERT INTO staff(business_id,name) VALUES($1,$2) RETURNING id',[business.id,input.staffName])).rows[0];
          for (const h of input.hours) await db.query('INSERT INTO working_hours VALUES($1,$2,$3,$4)',[staff.id,h.weekday,h.opensAt,h.closesAt]);
          await db.query("SELECT pg_notify('torly_calendar',$1)",[business.id]);
          return business;
        });
        // Membership changed: reconnect so stream scopes include the new business.
        for (const stream of subscribers) if (stream.tokenHash===digest(token)) stream.res.end();
        return send(res,201,{business:result});
      }
      const publishMatch=path.match(/^\/v1\/businesses\/([\w-]+)\/publishing$/);
      if (req.method==='PUT' && publishMatch) {
        const {published}=z.object({published:z.boolean()}).parse(await body(req));
        await transaction(pool,async db=>{
          const business=await owned(db,accountId,publishMatch[1]);
          if (published) {
            const services=await db.query('SELECT id FROM services WHERE business_id=$1 AND active=true LIMIT 1',[business.id]);
            const hours=await db.query('SELECT h.staff_id FROM working_hours h JOIN staff s ON s.id=h.staff_id WHERE s.business_id=$1 LIMIT 1',[business.id]);
            if (!services.rowCount || !hours.rowCount) throw new APIError(409,'Add an active service and working hours before publishing');
          }
          await db.query('UPDATE businesses SET published=$2 WHERE id=$1',[business.id,published]);
          await db.query("SELECT pg_notify('torly_calendar',$1)",[business.id]);
        });
        return send(res,200,{ok:true});
      }
      const businessMatch = path.match(/^\/v1\/businesses\/([\w-]+)$/);
      if (req.method === 'PUT' && businessMatch) {
        const input = businessInput.parse(await body(req));
        const business = await owned(pool,accountId,businessMatch[1]);
        if (!(await pool.query('SELECT id FROM categories WHERE id=$1',[input.categoryId])).rowCount) throw new APIError(400,'Unknown category');
        if (input.timezone !== business.timezone || input.currency !== business.currency) {
          if ((await pool.query("SELECT id FROM calendar_entries WHERE business_id=$1 AND status IN ('pending','confirmed') AND ends_at>now() LIMIT 1",[business.id])).rowCount) throw new APIError(409,'Cancel or complete upcoming appointments before changing timezone or currency');
        }
        await pool.query('UPDATE businesses SET name=$2,phone=$3,address=$4,category_id=$5,timezone=$6,currency=$7,locale=$8,country=$9 WHERE id=$1',[business.id,input.name,input.phone,input.address,input.categoryId,input.timezone,input.currency,input.locale,input.country]);
        await pool.query("SELECT pg_notify('torly_calendar',$1)",[business.id]);
        return send(res,200,{ok:true});
      }
      if (req.method === 'POST' && path === '/v1/services') {
        const input = serviceInput.extend({businessId:uuid,requestKey:uuid}).parse(await body(req));
        await owned(pool,accountId,input.businessId);
        const existing = (await pool.query('SELECT id FROM services WHERE id=$1 AND business_id=$2',[input.requestKey,input.businessId])).rows[0];
        if (existing) return send(res,200,{service:existing});
        const service = (await pool.query('INSERT INTO services(id,business_id,name,price_minor,minutes,active) VALUES($1,$2,$3,$4,$5,true) RETURNING *',[input.requestKey,input.businessId,input.name,input.priceMinor,input.minutes])).rows[0];
        await pool.query("SELECT pg_notify('torly_calendar',$1)",[input.businessId]);
        return send(res,201,{service});
      }
      if (req.method === 'POST' && path === '/v1/staff') {
        const input = z.object({businessId:uuid,name:text,hours:hoursInput,requestKey:uuid}).parse(await body(req));
        const staff = await transaction(pool,async db=>{
          await owned(db,accountId,input.businessId);
          const existing = (await db.query('SELECT id FROM staff WHERE id=$1 AND business_id=$2',[input.requestKey,input.businessId])).rows[0];
          if (existing) return existing;
          const created = (await db.query('INSERT INTO staff(id,business_id,name) VALUES($1,$2,$3) RETURNING *',[input.requestKey,input.businessId,input.name])).rows[0];
          for (const h of input.hours) await db.query('INSERT INTO working_hours VALUES($1,$2,$3,$4)',[created.id,h.weekday,h.opensAt,h.closesAt]);
          await db.query("SELECT pg_notify('torly_calendar',$1)",[input.businessId]);
          return created;
        });
        return send(res,201,{staff});
      }
      if (req.method === 'GET' && path === '/v1/clients') {
        const business = await owned(pool,accountId,url.searchParams.get('businessId'));
        const clients = (await pool.query("SELECT c.*,count(e.id) FILTER (WHERE e.status='completed')::integer AS visits,coalesce(sum(e.price_minor) FILTER (WHERE e.status='completed'),0)::bigint::text AS completed_value_minor FROM clients c LEFT JOIN calendar_entries e ON e.client_id=c.id WHERE c.business_id=$1 GROUP BY c.id ORDER BY c.name",[business.id])).rows;
        return send(res,200,{clients});
      }
      const clientMatch = path.match(/^\/v1\/clients\/([\w-]+)$/);
      if (req.method === 'PUT' && clientMatch) {
        const input = z.object({note:z.string().max(2000)}).parse(await body(req));
        const client = (await pool.query('UPDATE clients c SET note=$3 FROM businesses b WHERE c.id=$1 AND c.business_id=b.id AND b.owner_id=$2 RETURNING c.id',[uuid.parse(clientMatch[1]),accountId,input.note])).rows[0];
        if (!client) throw new APIError(404,'Client not found');
        return send(res,200,{ok:true});
      }
      if (req.method === 'POST' && path === '/v1/blocks') {
        const input = z.object({staffId:uuid,startsAt:iso,endsAt:iso,kind:z.enum(['break','time_off']),requestKey:uuid}).parse(await body(req));
        if (new Date(input.endsAt)<=new Date(input.startsAt) || new Date(input.endsAt)-new Date(input.startsAt)>366*86400000) throw new APIError(400,'Invalid date range');
        const block = await transaction(pool,async db=>{
          const staff = await staffFor(db,accountId,input.staffId);
          const business = await owned(db,accountId,staff.business_id);
          const existing = (await db.query('SELECT * FROM calendar_entries WHERE request_key=$1 AND business_id=$2',[input.requestKey,business.id])).rows[0];
          const hash = digest(JSON.stringify(input));
          if (existing) {
            if (existing.request_hash!==hash) throw new APIError(409,'Request key already used');
            return existing;
          }
          const entry = (await db.query("INSERT INTO calendar_entries(business_id,staff_id,kind,starts_at,ends_at,status,currency,request_key,request_hash) VALUES($1,$2,$3,$4,$5,'confirmed',$6,$7,$8) RETURNING *",[business.id,staff.id,input.kind,input.startsAt,input.endsAt,business.currency,input.requestKey,hash])).rows[0];
          await db.query("SELECT pg_notify('torly_calendar',$1)",[business.id]);
          return entry;
        });
        return send(res,201,{block});
      }
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
        return send(res,200,{slots:await availability(pool,business,staffId,serviceId,url.searchParams.get('date'))});
      }
      if (req.method === 'POST' && path === '/v1/bookings') {
        const input = bookingInput.parse(await body(req));
        return send(res,201,{booking:await createBooking(pool,accountId,input)});
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
      if (req.method === 'DELETE' && serviceMatch) {
        const row = (await pool.query('UPDATE services s SET active=false FROM businesses b WHERE s.id=$1 AND s.business_id=b.id AND b.owner_id=$2 RETURNING s.business_id',[uuid.parse(serviceMatch[1]),accountId])).rows[0];
        if (!row) throw new APIError(404,'Service not found');
        await pool.query("SELECT pg_notify('torly_calendar',$1)",[row.business_id]);
        return send(res,200,{ok:true});
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
