const test = require('node:test');
const assert = require('node:assert/strict');
const { dueTargets, reminderMessage, nextReminder } = require('./calendar-core.cjs');

test('notifies within the five-minute window, once, and catches wake before the event', () => {
  const target = { id: 'test', kind: 'start', dueAt: '2026-10-02T09:40:00Z', plannedAt: '2026-10-02T09:45:00Z' };
  assert.deepEqual(dueTargets([target], {}, new Date('2026-10-02T09:39:59Z')), []);
  assert.deepEqual(dueTargets([target], {}, new Date('2026-10-02T09:40:00Z')), [target]);
  assert.deepEqual(dueTargets([target], {}, new Date('2026-10-02T09:44:00Z')), [target]);
  assert.deepEqual(dueTargets([target], { test: 1 }, new Date('2026-10-02T09:44:00Z')), []);
  assert.deepEqual(dueTargets([target], {}, new Date('2026-10-02T09:45:00Z')), []);
});

test('departure notifies at the scheduled time and once, including delayed minute checks', () => {
  const target = { id: 'departure', kind: 'end', dueAt: '2026-10-02T11:00:00Z', plannedAt: '2026-10-02T11:00:00Z' };
  assert.deepEqual(dueTargets([target], {}, new Date('2026-10-02T10:59:59Z')), []);
  for (const time of ['2026-10-02T11:00:00Z', '2026-10-02T11:00:59Z', '2026-10-02T11:04:59.999Z']) {
    assert.deepEqual(dueTargets([target], {}, new Date(time)), [target]);
    assert.deepEqual(dueTargets([target], { departure: 1 }, new Date(time)), []);
  }
  assert.deepEqual(dueTargets([target], {}, new Date('2026-10-02T11:05:00Z')), []);
});

test('a cached departure from the older five-minute rule cannot notify early', () => {
  const target = { id: 'departure', kind: 'end', dueAt: '2026-10-02T10:55:00Z', plannedAt: '2026-10-02T11:00:00Z' };
  assert.deepEqual(dueTargets([target], {}, new Date('2026-10-02T10:55:00Z')), []);
  assert.deepEqual(dueTargets([target], {}, new Date('2026-10-02T11:00:15Z')), [target]);
});

test('the message distinguishes arrival before work from the scheduled departure time', () => {
  const plannedAt = '2026-10-02T11:00:00Z';
  assert.match(reminderMessage({ kind: 'start', plannedAt }), /出勤予定 20:00 の5分前です。/);
  assert.match(reminderMessage({ kind: 'end', plannedAt }), /退勤予定 20:00 の時刻になりました。/);
  assert.doesNotMatch(reminderMessage({ kind: 'end', plannedAt }), /5分前/);
});

test('next reminder honours arrival expiration and the departure grace window instead of advertising missed notifications', () => {
  const targets = [
    { id: 'arrival', kind: 'start', plannedAt: '2026-10-09T00:45:00Z', dueAt: '2026-10-09T00:40:00Z' },
    { id: 'departure', kind: 'end', plannedAt: '2026-10-09T09:45:00Z', dueAt: '2026-10-09T09:40:00Z' },
  ];
  assert.equal(nextReminder(targets, {}, new Date('2026-10-09T00:44:59Z')).kind, 'start');
  assert.equal(nextReminder(targets, {}, new Date('2026-10-09T00:45:00Z')).kind, 'end');
  assert.equal(nextReminder(targets, {}, new Date('2026-10-09T09:49:59Z')).kind, 'end');
  assert.equal(nextReminder(targets, {}, new Date('2026-10-09T09:50:00Z')), null);
  assert.equal(nextReminder(targets, { arrival: 1, departure: 1 }, new Date('2026-10-09T00:30:00Z')), null);
});
