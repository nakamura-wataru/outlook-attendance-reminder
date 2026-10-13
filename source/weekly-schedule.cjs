const fs = require('node:fs');
const path = require('node:path');
const { createHash } = require('node:crypto');
const dateFormat = new Intl.DateTimeFormat('sv-SE', { timeZone: 'Asia/Tokyo', year: 'numeric', month: '2-digit', day: '2-digit' });

function defaultSchedule() {
  return { mode: 'weekly', weekdays: [1, 2, 3, 4, 5].map(day => ({ day, enabled: true, start: '09:45', end: '18:45' })) };
}
function validateSchedule(value) {
  if (!value || value.mode !== 'weekly' || !Array.isArray(value.weekdays) || value.weekdays.length !== 5) throw new Error('月〜金の出勤・退勤時刻を設定してください。');
  const weekdays = [1, 2, 3, 4, 5].map(day => {
    const matches = value.weekdays.filter(row => row?.day === day);
    const row = matches[0];
    if (matches.length !== 1 || typeof row.enabled !== 'boolean' || ![row.start, row.end].every(time => typeof time === 'string' && /^(?:[01]\d|2[0-3]):[0-5]\d$/.test(time))) throw new Error('各曜日の出勤・退勤時刻を00:00〜23:59で設定してください。');
    return { day, enabled: row.enabled, start: row.start, end: row.end };
  });
  if (value.mode === 'weekly' && !weekdays.some(row => row.enabled)) throw new Error('通知する曜日を少なくとも1つ選んでください。');
  return { mode: value.mode, weekdays };
}
function readSchedule(root) {
  let raw;
  try { raw = fs.readFileSync(path.join(root, 'schedule.json'), 'utf8'); }
  catch (error) { if (error.code === 'ENOENT') return defaultSchedule(); throw error; }
  const value = JSON.parse(raw);
  // Retain saved weekday times from older versions without using their link.
  return validateSchedule(value.mode === 'outlook' ? { ...value, mode: 'weekly' } : value);
}
function weeklyTargets(value, now = new Date()) {
  const schedule = validateSchedule(value);
  const midnight = new Date(`${dateFormat.format(now)}T00:00:00+09:00`);
  const targets = [];
  // Include yesterday so a brief sleep around midnight is handled consistently.
  for (let offset = -1; offset <= 8; offset++) {
    const day = new Date(midnight.getTime() + offset * 86400000);
    const row = schedule.weekdays.find(row => row.day === new Date(day.getTime() + 9 * 3600000).getUTCDay());
    if (!row?.enabled) continue;
    for (const kind of ['start', 'end']) {
      const planned = new Date(`${dateFormat.format(day)}T${row[kind]}:00+09:00`);
      const plannedAt = planned.toISOString();
      const id = createHash('sha256').update(`weekly\n${kind}\n${plannedAt}`).digest('hex');
      targets.push({ id, kind, subject: kind === 'start' ? '出勤' : '退勤', plannedAt, dueAt: new Date(planned.getTime() - (kind === 'start' ? 5 * 60000 : 0)).toISOString() });
    }
  }
  return targets.sort((a, b) => a.dueAt.localeCompare(b.dueAt));
}
module.exports = { defaultSchedule, validateSchedule, readSchedule, weeklyTargets };
