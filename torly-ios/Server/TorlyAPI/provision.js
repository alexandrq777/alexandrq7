import { readFile } from 'node:fs/promises';
import { z } from 'zod';
import { createPool, transaction } from './db.js';
import { hashPassword, phone, text, timezone, hoursInput } from './domain.js';

const schema = z.object({
  email: z.email(), password: z.string().min(16).max(200),
  business: z.object({ name: text, slug: z.string().regex(/^[a-z0-9-]{3,80}$/), phone, address: text, categoryId: text, timezone, staffName: text }),
  services: z.array(text).min(1), hours: hoursInput
});

export async function provision(pool, raw) {
  const input = schema.parse(raw);
  const passwordHash = await hashPassword(input.password);
  return transaction(pool, async db => {
    const account = (await db.query('INSERT INTO accounts(email,password_hash) VALUES($1,$2) RETURNING id', [input.email.toLowerCase(), passwordHash])).rows[0];
    const b = input.business;
    const business = (await db.query('INSERT INTO businesses(owner_id,slug,name,phone,address,category_id,timezone) VALUES($1,$2,$3,$4,$5,$6,$7) RETURNING id', [account.id,b.slug,b.name,b.phone,b.address,b.categoryId,b.timezone])).rows[0];
    const staff = (await db.query('INSERT INTO staff(business_id,name) VALUES($1,$2) RETURNING id', [business.id,b.staffName])).rows[0];
    for (const day of input.hours) await db.query('INSERT INTO working_hours VALUES($1,$2,$3,$4)', [staff.id,day.weekday,day.opensAt,day.closesAt]);
    // Unknown prices and durations stay NULL and cannot be booked accidentally.
    for (const name of input.services) await db.query('INSERT INTO services(business_id,name) VALUES($1,$2)', [business.id,name]);
    return business.id;
  });
}
if (import.meta.url === `file://${process.argv[1]}`) {
  if (!process.argv[2]) throw new Error('Usage: node provision.js /path/to/account.private.json');
  const input = JSON.parse(await readFile(process.argv[2], 'utf8'));
  const pool = createPool();
  try { console.log('Business created:', await provision(pool, input)); }
  finally { await pool.end(); }
}
