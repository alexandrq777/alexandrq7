// Optional browser QA. All business/client fixtures live in an in-memory database.
import assert from 'node:assert/strict';
import { EventEmitter, once } from 'node:events';
import { randomUUID } from 'node:crypto';
import { PGlite } from '@electric-sql/pglite';
import { btree_gist } from '@electric-sql/pglite/contrib/btree_gist';
import { DateTime } from 'luxon';
import { migrate } from '../migrate.js';
import { createAPI } from '../api.js';
const {chromium}=await import(process.env.PLAYWRIGHT_MODULE || 'playwright');
const pg=new PGlite({extensions:{btree_gist}});
const query=async(sql,params=[])=>{
 if(!params.length&&sql.includes('CREATE EXTENSION'))return pg.exec(sql);
 const r=await pg.query(sql,params);return {rows:r.rows,rowCount:r.rows.length||r.affectedRows||0};
};
const pool={query,connect:async()=>Object.assign(new EventEmitter(),{query,release(){}})};
await migrate(pool);
const server=await createAPI(pool);
server.listen(0,'127.0.0.1');await once(server,'listening');
const base='http://127.0.0.1:'+server.address().port;
let browser;
try {
 const request=async(path,method='GET',data,token)=>{
  const r=await fetch(base+path,{method,headers:{'Content-Type':'application/json',...(token?{Authorization:'Bearer '+token}:{})},...(data?{body:JSON.stringify(data)}:{})});
  assert(r.ok,await r.clone().text());return r.json();
 };
 const {token}=await request('/v1/accounts','POST',{email:'browser@example.com',password:'browser-testing-password'});
 const {business}=await request('/v1/businesses','POST',{name:'Studio QA',phone:'+972500000000',address:'Test address',staffName:'Specialist',
 categoryId:'skin-care',timezone:'Asia/Jerusalem',currency:'ILS',country:'IL',locale:'en',requestKey:randomUUID(),
 hours:Array.from({length:7},(_,weekday)=>({weekday,opensAt:'00:00',closesAt:'23:59'}))},token);
 await request('/v1/services','POST',{businessId:business.id,name:'Consultation',priceMinor:12000,minutes:30,requestKey:randomUUID()},token);
 await request('/v1/businesses/'+business.id+'/publishing','PUT',{published:true},token);
 await pool.query('UPDATE businesses SET slug=upper(slug) WHERE id=$1',[business.id]);
 const path='/book/B-'+business.id.toUpperCase()+'/';
 browser=await chromium.launch({headless:true,...(process.env.BROWSER_CHANNEL?{channel:process.env.BROWSER_CHANNEL}:{})});
 for(const [width,height,lang] of [[390,844,'ru'],[1440,1000,'en'],[390,844,'he'],[390,844,'es']]){
  const page=await browser.newPage({viewport:{width,height}});
  const errors=[];page.on('pageerror',e=>errors.push(e.message));
  await page.goto(base+path);await page.locator('#profile').waitFor({state:'visible'});
  await page.locator('#language').selectOption(lang);
  await page.reload();
  await page.locator('#profile').waitFor({state:'visible'});
  assert.equal(await page.locator('#language').inputValue(),lang);
  await page.waitForFunction(()=>document.querySelector('#slot-status').textContent!=='Loading...');
  assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false);
  assert.equal(await page.locator('.brand img').evaluate(img=>img.complete&&img.naturalWidth>0),true);
  await page.screenshot({path:'/private/tmp/torly-booking-'+lang+'.png',fullPage:true});
  assert.deepEqual(errors,[]);
  await page.close();
 }
 const page=await browser.newPage({viewport:{width:390,height:844}});
 await page.goto(base+path);await page.locator('#profile').waitFor({state:'visible'});
 await page.locator('#language').selectOption('en');
 const now=DateTime.now().setZone('Asia/Jerusalem'),tomorrow=now.plus({days:1});
 if(tomorrow.month!==now.month)await page.locator('#next').click();
 await page.locator('#days button').getByText(String(tomorrow.day),{exact:true}).click();
 await page.locator('#slots button').first().waitFor();
 await page.locator('#slots button').first().click();
 await page.locator('#client-name').fill('Browser client');
 await page.locator('#phone').fill('+972511111111');
 await page.locator('#consent').check();
 await page.locator('#submit').click();
 await page.locator('#success').waitFor({state:'visible'});
 assert.match(await page.locator('#receipt').textContent(),/Consultation/);
 const entries=await request('/v1/bookings?'+new URLSearchParams({businessId:business.id,from:now.startOf('day').toISO(),to:now.plus({days:3}).toISO()}),'GET',null,token);
 assert.equal(entries.bookings.length,1);assert.equal(entries.bookings[0].client_name,'Browser client');
 await page.screenshot({path:'/private/tmp/torly-booking-success.png',fullPage:true});
 await request('/v1/businesses/'+business.id+'/publishing','PUT',{published:false},token);
 await page.reload();await page.locator('#retry').waitFor({state:'visible'});
 assert.equal(await page.locator('#profile').isVisible(),false);
 console.log('Browser QA passed: mobile/desktop/RTL, actual booking, owner visibility, unpublished page.');
} finally {
 await browser?.close();server.closeAllConnections();await new Promise(r=>server.close(r));await pg.close();
}
