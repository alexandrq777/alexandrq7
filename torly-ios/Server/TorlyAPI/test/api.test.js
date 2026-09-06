import test from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { once, EventEmitter } from 'node:events';
import pgDriver from 'pg';
import { migrate } from '../migrate.js';
import { provision } from '../provision.js';
import { createAPI } from '../api.js';

test('owner API persists changes, isolates tenants and rejects overlaps', async () => {
  const realPostgres = process.env.TORLY_VERIFY_PG === '1';
  let pg;
  if (!realPostgres) {
    const { PGlite } = await import('@electric-sql/pglite');
    const { btree_gist } = await import('@electric-sql/pglite/contrib/btree_gist');
    pg = new PGlite({ extensions: { btree_gist } });
  }
  const query = async (sql, params = []) => {
    if (!params.length && sql.includes('CREATE EXTENSION')) return pg.exec(sql);
    const result = await pg.query(sql, params);
    return { rows: result.rows, rowCount: result.rows.length || result.affectedRows || 0 };
  };
  let pool;
  if (realPostgres) {
    const url = new URL(process.env.DATABASE_URL);
    url.pathname = '/torly_verify';
    pool = new pgDriver.Pool({ connectionString: url.toString() });
  } else {
    pool = { query, connect: async () => Object.assign(new EventEmitter(), { query, release() {} }) };
  }
  await migrate(pool);
  await migrate(pool);
  const provisionData = index => ({ email: `owner${index}@example.com`, password: 'a-long-test-password', business: { name:'Test', slug:`studio-${index}`, phone:'+972500000000', address:'Test', categoryId:'skin-care', timezone:'Asia/Jerusalem', staffName:'Owner' }, services:['Peeling'], hours:[0,1,2,3,4].map(weekday=>({weekday,opensAt:'07:00',closesAt:'15:00'})) });
  await provision(pool, provisionData(1));
  await provision(pool, provisionData(2));
  const server = await createAPI(pool);
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  const base = `http://127.0.0.1:${server.address().port}`;
  const request = async (path, method='GET', data, token) => {
    const response = await fetch(base+path,{method,headers:{'Content-Type':'application/json',...(token?{Authorization:`Bearer ${token}`}:{})},...(data?{body:JSON.stringify(data)}:{})});
    return {status:response.status, body:await response.json()};
  };
  try {
    assert.equal((await request('/v1/owner')).status,401);
    assert.equal((await request('/v1/session','POST',{email:'owner1@example.com',password:'wrong'})).status,401);
    const token = (await request('/v1/session','POST',{email:'owner1@example.com',password:'a-long-test-password'})).body.token;
    const token2 = (await request('/v1/session','POST',{email:'owner2@example.com',password:'a-long-test-password'})).body.token;
    const registration = await request('/v1/accounts','POST',{email:'fresh@example.com',password:'a-long-test-password'});
    assert.equal(registration.status,201);
    const freshToken = registration.body.token;
    assert.deepEqual((await request('/v1/owner','GET',null,freshToken)).body.businesses,[]);
    assert.equal((await request('/v1/accounts','POST',{email:'fresh@example.com',password:'a-long-test-password'})).status,409);
    assert.equal((await request('/v1/accounts','POST',{email:'short@example.com',password:'short'})).status,400);
    const categories = (await request('/v1/categories')).body.categories;
    assert(categories.some(c=>c.id==='skin-care'));
    const businessInput = {name:'Fresh business',phone:'+972522222222',address:'Owner address',categoryId:'skin-care',
      timezone:'Asia/Jerusalem',currency:'ILS',locale:'he',country:'IL',staffName:'Owner',
      hours:[{weekday:0,opensAt:'09:00',closesAt:'17:00'}],requestKey:randomUUID()};
    assert.equal((await request('/v1/businesses','POST',{...businessInput,categoryId:'invalid'},freshToken)).status,400);
    const newBusiness = await request('/v1/businesses','POST',businessInput,freshToken);
    assert.equal(newBusiness.status,201,JSON.stringify(newBusiness.body));
    assert.equal((await request('/v1/businesses','POST',businessInput,freshToken)).body.business.id,newBusiness.body.business.id);
    const fresh = (await request('/v1/owner','GET',null,freshToken)).body.businesses[0];
    assert.equal(fresh.services.length,0);
    assert.equal(fresh.staff.length,1);
    assert.equal(fresh.published,false);
    assert.deepEqual((await request('/v1/clients?businessId='+fresh.id,'GET',null,freshToken)).body.clients,[]);
    const freshServiceInput = {businessId:fresh.id,name:'New service',priceMinor:12550,minutes:30,requestKey:randomUUID()};
    assert.equal((await request('/v1/services','POST',freshServiceInput,token2)).status,404);
    const freshService = await request('/v1/services','POST',freshServiceInput,freshToken);
    assert.equal(freshService.status,201);
    assert.equal((await request('/v1/services','POST',freshServiceInput,freshToken)).body.service.id,freshService.body.service.id);
    const staffInput = {businessId:fresh.id,name:'Colleague',hours:businessInput.hours,requestKey:randomUUID()};
    assert.equal((await request('/v1/staff','POST',staffInput,freshToken)).status,201);
    assert.equal((await request('/v1/staff','POST',staffInput,token2)).status,404);
    const blockInput = {staffId:fresh.staff[0].id,kind:'break',startsAt:'2030-01-06T10:00:00+02:00',endsAt:'2030-01-06T11:00:00+02:00',requestKey:randomUUID()};
    assert.equal((await request('/v1/blocks','POST',blockInput,token2)).status,404);
    const block = await request('/v1/blocks','POST',blockInput,freshToken);
    assert.equal(block.status,201,JSON.stringify(block.body));
    assert.equal((await request('/v1/blocks','POST',blockInput,freshToken)).body.block.id,block.body.block.id);
    assert.equal((await request('/v1/blocks','POST',{...blockInput,requestKey:randomUUID()},freshToken)).status,409);
    const freshBooking = {businessId:fresh.id,staffId:fresh.staff[0].id,serviceId:freshService.body.service.id,
      startsAt:blockInput.startsAt,clientName:'Actual client',clientPhone:'+972533333333',requestKey:randomUUID()};
    assert.equal((await request('/v1/bookings','POST',freshBooking,freshToken)).status,409);
    assert.deepEqual((await request('/v1/clients?businessId='+fresh.id,'GET',null,freshToken)).body.clients,[]);
    assert.equal((await request('/v1/bookings','POST',{...freshBooking,startsAt:'2030-01-06T11:00:00+02:00'},freshToken)).status,201);
    const client = (await request('/v1/clients?businessId='+fresh.id,'GET',null,freshToken)).body.clients[0];
    assert.equal(client.visits,0);
    assert.equal(client.no_show_count,0);
    assert.equal((await request('/v1/clients/'+client.id,'PUT',{note:'Preference'},freshToken)).status,200);
    assert.equal((await request('/v1/clients/'+client.id,'PUT',{note:'Foreign'},token2)).status,404);
    assert.equal((await request('/v1/clients?businessId='+fresh.id,'GET',null,freshToken)).body.clients[0].note,'Preference');
    assert.equal((await request('/v1/businesses/'+fresh.id,'PUT',{...businessInput,currency:'USD'},freshToken)).status,409);
    assert.equal((await request('/v1/businesses/'+fresh.id,'PUT',{...businessInput,name:'Updated'},freshToken)).status,200);
    assert.equal((await request('/v1/services/'+freshService.body.service.id,'DELETE',null,freshToken)).status,200);
    assert.equal((await request('/v1/bookings','POST',{...freshBooking,startsAt:'2030-01-06T12:00:00+02:00',requestKey:randomUUID()},freshToken)).status,400);
    const business = (await request('/v1/owner','GET',null,token)).body.businesses[0];
    const service = business.services[0];
    assert.equal(service.active,false);
    assert.equal(service.minutes,null);
    const update = {name:'Peeling',priceMinor:15000,minutes:60};
    assert.equal((await request(`/v1/services/${service.id}`,'PUT',update,token2)).status,404);
    assert.equal((await request(`/v1/services/${service.id}`,'PUT',update,token)).status,200);
    const input = {businessId:business.id,staffId:business.staff[0].id,serviceId:service.id,startsAt:'2030-01-06T07:00:00+02:00',clientName:'Test Client',clientPhone:'+972511111111',requestKey:randomUUID()};
    const created = await request('/v1/bookings','POST',input,token);
    assert.equal(created.status,201,JSON.stringify(created.body));
    const booking = created.body.booking;
    assert.equal((await request('/v1/bookings','POST',input,token)).body.booking.id,booking.id);
    assert.equal((await request('/v1/bookings','POST',{...input,requestKey:randomUUID(),startsAt:'2030-01-06T07:15:00+02:00'},token)).status,409);
    assert.equal((await request('/v1/bookings','POST',{...input,requestKey:randomUUID()},token2)).status,404);
    assert.equal((await request(`/v1/bookings/${booking.id}`,'PATCH',{status:'confirmed',revision:1},token)).status,200);
    assert.equal((await request(`/v1/bookings/${booking.id}`,'PATCH',{status:'cancelled',revision:1},token)).status,409);
    assert.equal((await request(`/v1/bookings/${booking.id}`,'PATCH',{startsAt:'2030-01-06T09:00:00+02:00',revision:2},token)).status,200);
    assert.equal((await request(`/v1/bookings/${booking.id}`,'PATCH',{status:'cancelled',revision:3},token)).status,200);
    assert.equal((await request('/v1/bookings','POST',{...input,requestKey:randomUUID()},token)).status,201);
    const jobs = (await pool.query('SELECT status FROM notification_jobs')).rows;
    assert(jobs.some(j=>j.status==='disabled'));
    assert(jobs.some(j=>j.status==='cancelled'));
    const queryString = `?businessId=${business.id}&from=2030-01-01T00:00:00Z&to=2030-02-01T00:00:00Z`;
    assert.equal((await request('/v1/bookings'+queryString,'GET',null,token2)).status,404);
    assert.equal((await request('/v1/bookings'+queryString,'GET',null,token)).body.bookings.length,2);
    assert.equal((await request('/v1/public/studio-1')).status,404);
    if (realPostgres) {
      const controller = new AbortController();
      const response = await fetch(base+'/v1/events',{headers:{Authorization:`Bearer ${token}`},signal:controller.signal});
      assert.equal(response.status,200);
      const reader = response.body.getReader();
      const firstEvent = new TextDecoder().decode((await reader.read()).value);
      assert(firstEvent.includes('event: connected'));
      const simultaneous = await Promise.all([1,2].map(() => request('/v1/bookings','POST',{...input,startsAt:'2030-01-06T12:00:00+02:00',requestKey:randomUUID()},token)));
      assert.deepEqual(simultaneous.map(r=>r.status).sort(),[201,409]);
      let timeout;
      try {
        const event = await Promise.race([reader.read(),new Promise((_,reject)=>{timeout=setTimeout(()=>reject(new Error('SSE notification timeout')),5000);})]);
        assert(new TextDecoder().decode(event.value).includes('event: calendar'));
      } finally { clearTimeout(timeout); controller.abort(); }
    }
    await request('/v1/session','DELETE',null,token);
    assert.equal((await request('/v1/owner','GET',null,token)).status,401);
  } finally {
    server.closeAllConnections();
    await new Promise(resolve=>server.close(resolve));
    if (realPostgres) await pool.end();
    else await pg.close();
  }
});
