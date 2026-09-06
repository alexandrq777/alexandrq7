import { readFile } from 'node:fs/promises';
import assert from 'node:assert/strict';

const access = JSON.parse(await readFile(process.argv[2], 'utf8'));
assert.equal(new URL(access.server).protocol, 'https:');
const login = await fetch(`${access.server}/v1/session`, {
  method: 'POST', headers: {'Content-Type':'application/json'},
  body: JSON.stringify({email:access.email,password:access.password})
});
assert.equal(login.status,201);
const {token} = await login.json();
const headers = {Authorization:`Bearer ${token}`};
try {
  const response = await fetch(`${access.server}/v1/owner`,{headers});
  assert.equal(response.status,200);
  const {businesses} = await response.json();
  assert.equal(businesses.length,1);
  assert.equal(businesses[0].services.length,3);
  assert.equal(businesses[0].staff.length,1);
  assert.equal(businesses[0].hours.length,5);
  assert(businesses[0].hours.every(h=>h.weekday<5 && h.opens_at==='07:00:00' && h.closes_at==='15:00:00'));
  assert(businesses[0].services.every(s=>s.price_minor===null && s.minutes===null && !s.active));
  console.log('HTTPS login and Olga profile verified; secrets omitted.');
} finally {
  const response = await fetch(`${access.server}/v1/session`,{method:'DELETE',headers});
  assert.equal(response.status,200);
}
