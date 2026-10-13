const timeFormat = new Intl.DateTimeFormat('en-GB', { timeZone: 'Asia/Tokyo', hour: '2-digit', minute: '2-digit', second: '2-digit', hourCycle: 'h23' });
const dateFormat = new Intl.DateTimeFormat('sv-SE', { timeZone: 'Asia/Tokyo', year: 'numeric', month: '2-digit', day: '2-digit' });

function dueTargets(targets, notified, now = new Date()) {
  return targets.filter(target => {
    const planned = new Date(target.plannedAt).getTime();
    // Use the planned departure time even when the cache was made by an older
    // version. Allow five minutes for the minute-based worker or a brief sleep.
    const due = target.kind === 'end' ? planned : new Date(target.dueAt).getTime();
    const expires = planned + (target.kind === 'end' ? 5 * 60000 : 0);
    return !notified[target.id] && due <= now.getTime() && now.getTime() < expires;
  });
}

function reminderMessage(target) {
  const kind = target.kind === 'start' ? '出勤' : '退勤';
  const time = timeFormat.format(new Date(target.plannedAt)).slice(0, 5);
  const date = dateFormat.format(new Date(target.plannedAt));
  const action = target.kind === 'start' ? '出勤' : '退勤';
  const timing = target.kind === 'start' ? 'の5分前です。' : 'の時刻になりました。';
  return `${date} ${kind}予定 ${time} ${timing}\nKING OF TIMEで${action}の打刻を確認してください。\n${target.kind === 'end' ? 'まだ仕事中なら再通知までの時間を選べます。' : '打刻は実際に業務を開始する時刻に行ってください。'}`;
}

function nextReminder(targets, notified, now = new Date()) {
  const due = new Set(dueTargets(targets, notified, now).map(target => target.id));
  const upcoming = targets.flatMap(target => {
    if (!['start', 'end'].includes(target.kind) || notified[target.id]) return [];
    const plannedAt = new Date(target.plannedAt), dueAt = new Date(target.kind === 'end' ? target.plannedAt : target.dueAt);
    if (!Number.isFinite(plannedAt.getTime()) || !Number.isFinite(dueAt.getTime()) || (dueAt <= now && !due.has(target.id))) return [];
    return [{ kind: target.kind, plannedAt: plannedAt.toISOString(), dueAt: dueAt.toISOString() }];
  }).sort((a, b) => a.dueAt.localeCompare(b.dueAt));
  return upcoming[0] || null;
}

module.exports = { dueTargets, reminderMessage, nextReminder };
