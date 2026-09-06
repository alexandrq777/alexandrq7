import test from 'node:test';
import assert from 'node:assert/strict';
import { DateTime } from 'luxon';
import { availableSlots, fitsHours, hashPassword, verifyPassword } from '../domain.js';

const hours = [0,1,2,3,4].map(weekday => ({ weekday, opens_at: '07:00:00', closes_at: '15:00:00' }));
test('Jerusalem opening time uses winter and summer offsets', () => {
  for (const [date, expected] of [['2027-01-03','05:00'], ['2027-07-04','04:00']]) {
    const slots = availableSlots(date, 'Asia/Jerusalem', 60, hours, [], DateTime.fromISO('2026-01-01'));
    assert.equal(slots[0].slice(11,16), expected);
  }
});
test('Friday and Saturday closed; whole treatment must fit', () => {
  assert.deepEqual(availableSlots('2027-01-01','Asia/Jerusalem',60,hours,[]), []);
  assert.deepEqual(availableSlots('2027-01-02','Asia/Jerusalem',60,hours,[]), []);
  assert.equal(fitsHours('2027-01-03T14:30:00+02:00',60,'Asia/Jerusalem',hours), false);
});
test('overlap removes slots but adjacent bookings remain available', () => {
  const entries = [{starts_at:'2027-01-03T06:00:00Z', ends_at:'2027-01-03T07:00:00Z'}];
  const slots = availableSlots('2027-01-03','Asia/Jerusalem',60,hours,entries,DateTime.fromISO('2026-01-01'));
  assert(slots.includes('2027-01-03T05:00:00.000Z'));
  assert(!slots.includes('2027-01-03T05:15:00.000Z'));
  assert(slots.includes('2027-01-03T07:00:00.000Z'));
});
test('password verification never accepts a different password', async () => {
  const hash = await hashPassword('a-long-test-password');
  assert(await verifyPassword('a-long-test-password', hash));
  assert.equal(await verifyPassword('wrong', hash), false);
});
