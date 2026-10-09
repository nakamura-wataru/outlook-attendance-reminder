const { createHash } = require('node:crypto');
const timeFormat = new Intl.DateTimeFormat('en-GB', { timeZone: 'Asia/Tokyo', hour: '2-digit', minute: '2-digit', second: '2-digit', hourCycle: 'h23' });
const dateFormat = new Intl.DateTimeFormat('sv-SE', { timeZone: 'Asia/Tokyo', year: 'numeric', month: '2-digit', day: '2-digit' });

function text(value) {
  return typeof value === 'string' ? value : value?.val ?? '';
}

function attendanceKind(subject) {
  const normalized = text(subject).normalize('NFKC').replace(/[\s【】\[\]()]/gu, '');
  const match = /^(?:\d{1,2}:\d{2})?(出社|退社)(?:\d{1,2}:\d{2})?$/u.exec(normalized);
  return match ? (match[1] === '出社' ? 'start' : 'end') : null;
}

function targetsFromCalendar(data, ical, now = new Date()) {
  const targets = new Map();
  const from = new Date(now.getTime() - 86400000);
  const to = new Date(now.getTime() + 8 * 86400000);
  for (const event of Object.values(data)) {
    if (event?.type !== 'VEVENT') continue;
    for (const instance of ical.expandRecurringEvent(event, { from, to, expandOngoing: true })) {
      const kind = attendanceKind(instance.summary);
      if (!kind || instance.isFullDay || text(instance.event.status).toUpperCase() === 'CANCELLED' || text(event.status).toUpperCase() === 'CANCELLED') continue;
      let planned = instance.start;
      // In this calendar, arrival blocks run from midnight to the arrival time.
      if (kind === 'start' && timeFormat.format(instance.start) === '00:00:00') {
        if (dateFormat.format(instance.start) !== dateFormat.format(instance.end)) continue;
        planned = instance.end;
      }
      if (!Number.isFinite(planned.getTime()) || timeFormat.format(planned) === '00:00:00') continue;
      const due = new Date(planned.getTime() - 5 * 60000);
      if (planned < from || planned > to) continue;
      const id = createHash('sha256').update(`${event.uid}\n${kind}\n${planned.toISOString()}`).digest('hex');
      targets.set(id, { id, kind, subject: text(instance.summary), plannedAt: planned.toISOString(), dueAt: due.toISOString() });
    }
  }
  return [...targets.values()].sort((a, b) => a.dueAt.localeCompare(b.dueAt));
}

function dueTargets(targets, notified, now = new Date()) {
  return targets.filter(target => !notified[target.id] && new Date(target.dueAt) <= now && new Date(target.plannedAt) > now);
}

function reminderMessage(target) {
  const kind = target.kind === 'start' ? '出社' : '退社';
  const time = timeFormat.format(new Date(target.plannedAt)).slice(0, 5);
  const date = dateFormat.format(new Date(target.plannedAt));
  const action = target.kind === 'start' ? '出勤' : '退勤';
  return `${date} ${kind}予定 ${time} の5分前です。\nKING OF TIMEで${action}の打刻を確認してください。\n${target.kind === 'end' ? 'まだ仕事中なら再通知までの時間を選べます。' : '打刻は実際に業務を開始する時刻に行ってください。'}`;
}

module.exports = { attendanceKind, targetsFromCalendar, dueTargets, reminderMessage };
