const test = require('node:test');
const assert = require('node:assert/strict');
const { defaultSchedule, validateSchedule, weeklyTargets } = require('./weekly-schedule.cjs');
const { dueTargets } = require('./calendar-core.cjs');
const { refreshTargets } = require('./calendar-reminder.cjs');
const now = new Date('2026-10-05T09:40:00+09:00');
const weekly = () => ({ ...defaultSchedule(), mode: 'weekly' });

test('weekly schedules use each weekday in Japan time and omit weekends and unchecked days', () => {
  const schedule = weekly();
  schedule.weekdays[1].start = '10:15'; schedule.weekdays[1].end = '20:00';
  schedule.weekdays[2].enabled = false;
  const targets = weeklyTargets(schedule, now);
  const monday = targets.filter(target => target.plannedAt.startsWith('2026-10-05'));
  assert.equal(monday.length, 2);
  assert.equal(monday[0].plannedAt, '2026-10-05T00:45:00.000Z');
  assert.equal(monday[0].dueAt, '2026-10-05T00:40:00.000Z');
  const tuesday = targets.filter(target => target.plannedAt.startsWith('2026-10-06'));
  assert.equal(tuesday[0].plannedAt, '2026-10-06T01:15:00.000Z');
  assert.equal(tuesday[1].dueAt, '2026-10-06T11:00:00.000Z');
  assert.equal(targets.some(target => ['2026-10-07', '2026-10-10', '2026-10-11'].some(day => target.plannedAt.startsWith(day))), false);
  assert.deepEqual(dueTargets(targets, {}, now).map(target => target.kind), ['start']);
  assert.deepEqual(dueTargets(targets, {}, new Date('2026-10-05T18:45:00+09:00')).map(target => target.kind), ['end']);
});
test('weekly reminder IDs remain stable across refreshes and changes to a different weekday', () => {
  const schedule = weekly(); const initial = weeklyTargets(schedule, now);
  schedule.weekdays[4].end = '21:00';
  const refreshed = weeklyTargets(schedule, new Date(now.getTime() + 60000));
  const arrival = initial.find(target => target.kind === 'start' && target.plannedAt.startsWith('2026-10-05'));
  assert.ok(refreshed.some(target => target.id === arrival.id));
  assert.equal(dueTargets(refreshed, { [arrival.id]: now.getTime() }, now).length, 0);
});
test('an arrival at midnight can notify before midnight without shifting its weekday', () => {
  const schedule = weekly(); schedule.weekdays[0].start = '00:00';
  const sunday = new Date('2026-10-04T23:55:00+09:00');
  const due = dueTargets(weeklyTargets(schedule, sunday), {}, sunday);
  assert.equal(due.length, 1); assert.equal(due[0].plannedAt, '2026-10-04T15:00:00.000Z');
});
test('weekly schedules reject invalid hours, duplicate days, missing days, and no selected days', () => {
  for (const time of ['24:00', '09:60', '9:45', null]) {
    const value = weekly(); value.weekdays[0].start = time; assert.throws(() => validateSchedule(value));
  }
  const duplicate = weekly(); duplicate.weekdays[1].day = 1; assert.throws(() => validateSchedule(duplicate));
  const missing = weekly(); missing.weekdays.pop(); assert.throws(() => validateSchedule(missing));
  const unchecked = weekly(); unchecked.weekdays.forEach(row => { row.enabled = false; }); assert.throws(() => validateSchedule(unchecked));
  assert.throws(() => validateSchedule({ ...weekly(), mode: 'both' }));
});
test('weekly mode works offline, ignores old Outlook targets, and keeps notification history', async () => {
  const state = { source: 'outlook', targets: [{ id: 'old-outlook' }], notified: { previous: 123 }, fetchedAt: now.getTime() };
  let fetches = 0;
  const result = await refreshTargets(state, weekly(), now, async () => { fetches++; throw new Error('Offline'); });
  assert.equal(fetches, 0); assert.equal(result.state.source, 'weekly');
  assert.deepEqual(result.state.notified, state.notified);
  assert.ok(result.state.targets.every(target => target.id !== 'old-outlook'));
  const changed = weekly(); changed.weekdays[0].end = '20:00';
  const updated = await refreshTargets(result.state, changed, now);
  assert.ok(updated.state.targets.some(target => target.kind === 'end' && target.plannedAt === '2026-10-05T11:00:00.000Z'));
});
test('switching to Outlook never falls back to a fresh weekly cache when Outlook is unavailable', async () => {
  const state = { source: 'weekly', targets: weeklyTargets(weekly(), now), notified: {}, fetchedAt: now.getTime() };
  let fetches = 0;
  const result = await refreshTargets(state, defaultSchedule(), now, async () => { fetches++; throw new Error('Offline'); });
  assert.equal(fetches, 1); assert.equal(result.stale, true); assert.deepEqual(result.state.targets, []);
});
test('Outlook retains its bounded cached-calendar behavior', async () => {
  let fetches = 0; const fail = async () => { fetches++; throw new Error('Offline'); };
  const state = { source: 'outlook', targets: [{ id: 'outlook' }], notified: {}, fetchedAt: now.getTime() - 60000 };
  assert.equal((await refreshTargets(state, defaultSchedule(), now, fail)).state, state); assert.equal(fetches, 0);
  state.fetchedAt = now.getTime() - 10 * 60000;
  const cached = await refreshTargets(state, defaultSchedule(), now, fail); assert.equal(cached.stale, false); assert.deepEqual(cached.state.targets, state.targets);
  state.fetchedAt = now.getTime() - 16 * 60000;
  assert.equal((await refreshTargets(state, defaultSchedule(), now, fail)).stale, true);
});
