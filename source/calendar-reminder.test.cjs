const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { runReminder } = require('./calendar-reminder.cjs');
const { defaultSchedule } = require('./weekly-schedule.cjs');
function fixture(t) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'attendance-worker-test-'));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  fs.writeFileSync(path.join(root, 'preferences.json'), JSON.stringify({ enabled: true })); fs.writeFileSync(path.join(root, 'schedule.json'), JSON.stringify(defaultSchedule())); return root;
}
test('the worker generates reminders from the weekly schedule and stores only deduplication history', t => {
  const root = fixture(t), shown = []; fs.writeFileSync(path.join(root, 'calendar-state.json'), JSON.stringify({ targets: [{ id: 'downloaded-end' }], notified: {} }));
  const now = new Date('2026-10-05T00:40:00Z'); runReminder({ root, now, show: target => shown.push(target) }); runReminder({ root, now, show: target => shown.push(target) });
  assert.deepEqual(shown.map(target => target.kind), ['start']); const state = JSON.parse(fs.readFileSync(path.join(root, 'calendar-state.json')));
  assert.deepEqual(Object.keys(state), ['notified']); assert.equal(Object.keys(state.notified).length, 1); assert.equal(fs.statSync(path.join(root, 'calendar-state.json')).mode & 0o777, 0o600);
});
test('the worker follows custom weekday times, skips weekends, and honours the stopped preference', t => {
  const root = fixture(t), schedule = defaultSchedule(), shown = []; schedule.weekdays[1].end = '20:00'; fs.writeFileSync(path.join(root, 'schedule.json'), JSON.stringify(schedule));
  runReminder({ root, now: new Date('2026-10-06T11:00:00Z'), show: target => shown.push(target) }); runReminder({ root, now: new Date('2026-10-10T00:40:00Z'), show: target => shown.push(target) });
  fs.writeFileSync(path.join(root, 'preferences.json'), JSON.stringify({ enabled: false })); runReminder({ root, now: new Date('2026-10-07T00:40:00Z'), show: target => shown.push(target) }); assert.deepEqual(shown.map(target => target.kind), ['end']);
});
test('a failed display is retried on the next minute instead of being marked complete', t => {
  const root = fixture(t), now = new Date('2026-10-05T00:40:00Z'); assert.doesNotThrow(() => runReminder({ root, now, show: () => { throw new Error('closed'); } }));
  let calls = 0; runReminder({ root, now: new Date('2026-10-05T00:41:00Z'), show: () => { calls += 1; } }); assert.equal(calls, 1);
});
