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
  if (process.argv.includes('--expect-empty')) assert.equal(businesses.length,0);
  const categories = await fetch(`${access.server}/v1/categories`);
  assert.equal(categories.status,200);
  assert((await categories.json()).categories.length >= 18);
  const page = await fetch(`${access.server}/book/unpublished-smoke-check`);
  assert.equal(page.status,200);
  assert((await page.text()).includes('booking-form'));
  for (const asset of ['/booking.js','/booking.css','/torly-icon.png']) {
    assert.equal((await fetch(access.server+asset)).status,200);
  }
  assert.equal((await fetch(access.server+'/v1/public/unpublished-smoke-check')).status,404);
  console.log('HTTPS login, account and categories verified; secrets omitted.');
} finally {
  const response = await fetch(`${access.server}/v1/session`,{method:'DELETE',headers});
  assert.equal(response.status,200);
}
