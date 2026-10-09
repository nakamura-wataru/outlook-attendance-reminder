const test = require('node:test');
const assert = require('node:assert/strict');
const ical = require('node-ical');
const { attendanceKind, targetsFromCalendar, dueTargets, reminderMessage, nextReminder } = require('./calendar-core.cjs');

const now = new Date('2026-10-02T07:00:00Z');
function parse(body) {
  return ical.sync.parseICS(`BEGIN:VCALENDAR\r\nVERSION:2.0\r\n${body}\r\nEND:VCALENDAR`);
}
function event(uid, subject, start, end, extra = '') {
  return `BEGIN:VEVENT\r\nUID:${uid}\r\nDTSTART:${start}\r\nDTEND:${end}\r\nSUMMARY:${subject}\r\n${extra}\r\nEND:VEVENT`;
}

test('accepts only attendance titles, with optional brackets and clock times', () => {
  for (const subject of ['出社', '【出社】9:45', '９：４５ 出社', '出勤', '【出勤】9:45', '９：４５ 出勤']) assert.equal(attendanceKind(subject), 'start');
  for (const subject of ['退社', '18:45 退社', '退勤', '【退勤】20:00', '１８：４５ 退勤']) assert.equal(attendanceKind(subject), 'end');
  for (const subject of ['退社後の打合せ', '出社しようねリマインド', '出勤承認', '退勤後の面談', '勤怠承認', 'キャンセル済み: 退社']) assert.equal(attendanceKind(subject), null);
});

test('uses the end of an arrival block and the actual start of departure, not title times', () => {
  const data = parse([
    event('arrival', '【出社】9:45', '20261001T150000Z', '20261002T020000Z'),
    event('departure', '20:00 退社', '20261002T113000Z', '20261002T144500Z'),
  ].join('\r\n'));
  const targets = targetsFromCalendar(data, ical, now);
  assert.equal(targets[0].plannedAt, '2026-10-02T02:00:00.000Z');
  assert.equal(targets[0].dueAt, '2026-10-02T01:55:00.000Z');
  assert.equal(targets[1].plannedAt, '2026-10-02T11:30:00.000Z');
  assert.equal(targets[1].dueAt, '2026-10-02T11:30:00.000Z');
});

test('arrival and departure aliases produce the same timing and deduplication ID', () => {
  const arrival = subject => targetsFromCalendar(parse(event('arrival', subject, '20261001T150000Z', '20261002T004500Z')), ical, now)[0];
  const departure = subject => targetsFromCalendar(parse(event('departure', subject, '20261002T110000Z', '20261002T144500Z')), ical, now)[0];
  const a = arrival('出勤'), b = arrival('出社');
  assert.equal(a.kind, 'start');
  assert.equal(a.dueAt, '2026-10-02T00:40:00.000Z');
  assert.equal(a.id, b.id);
  const c = departure('退勤'), d = departure('退社');
  assert.equal(c.kind, 'end');
  assert.equal(c.dueAt, '2026-10-02T11:00:00.000Z');
  assert.equal(c.id, d.id);
});

test('supports a conventional arrival appointment starting at the arrival time', () => {
  const data = parse(event('arrival', '出社', '20261002T004500Z', '20261002T010000Z'));
  assert.equal(targetsFromCalendar(data, ical, now)[0].dueAt, '2026-10-02T00:40:00.000Z');
});

test('skips cancelled and all-day attendance entries', () => {
  const data = parse([
    event('cancelled', '退社', '20261002T094500Z', '20261002T144500Z', 'STATUS:CANCELLED'),
    'BEGIN:VEVENT\r\nUID:all-day\r\nDTSTART;VALUE=DATE:20261002\r\nDTEND;VALUE=DATE:20261003\r\nSUMMARY:出社\r\nEND:VEVENT',
  ].join('\r\n'));
  assert.deepEqual(targetsFromCalendar(data, ical, now), []);
});

test('honours recurring exceptions, cancellations, and modified instance times', () => {
  const data = parse([
    event('series', '18:45 退社', '20261001T094500Z', '20261001T144500Z', 'RRULE:FREQ=DAILY;COUNT=4\r\nEXDATE:20261002T094500Z'),
    event('series', '18:45 退社', '20261003T110000Z', '20261003T144500Z', 'RECURRENCE-ID:20261003T094500Z'),
    event('series', '18:45 退社', '20261004T094500Z', '20261004T144500Z', 'RECURRENCE-ID:20261004T094500Z\r\nSTATUS:CANCELLED'),
  ].join('\r\n'));
  const targets = targetsFromCalendar(data, ical, now);
  assert.deepEqual(targets.map(t => t.plannedAt), ['2026-10-01T09:45:00.000Z', '2026-10-03T11:00:00.000Z']);
});

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
