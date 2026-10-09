#!/usr/bin/env node
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { execFileSync } = require('node:child_process');
const ical = require('node-ical');
const { targetsFromCalendar, dueTargets, reminderMessage } = require('./calendar-core.cjs');

const root = process.env.ATTENDANCE_REMINDER_ROOT || path.join(os.homedir(), 'Library/Application Support/OutlookAttendanceReminder');
const statePath = path.join(root, 'calendar-state.json');
const syncPeriod = 5 * 60000;
const maxCacheAge = 15 * 60000;

function writeAtomic(filename, value) {
  const temporary = `${filename}.tmp`;
  fs.writeFileSync(temporary, value, { mode: 0o600 });
  fs.renameSync(temporary, filename);
}

async function fetchTargets(now) {
  const config = JSON.parse(fs.readFileSync(path.join(root, 'config.json'), 'utf8'));
  if (new URL(config.icsUrl).protocol !== 'https:') throw new Error('HTTPSRequired');
  const response = await fetch(config.icsUrl, { signal: AbortSignal.timeout(20000) });
  if (!response.ok) throw new Error('CalendarFetchFailed');
  const body = await response.text();
  if (!/^BEGIN:VCALENDAR\s*$/m.test(body)) throw new Error('InvalidCalendarData');
  const data = await ical.async.parseICS(body);
  return targetsFromCalendar(data, ical, now);
}

function preview(targets) {
  const format = new Intl.DateTimeFormat('sv-SE', { timeZone: 'Asia/Tokyo', dateStyle: 'short', timeStyle: 'short' });
  console.log(JSON.stringify({
    matched: targets.length,
    upcoming: targets.filter(target => new Date(target.plannedAt) > new Date()).slice(0, 6).map(target => ({
      subject: target.subject,
      planned: format.format(new Date(target.plannedAt)),
      reminder: format.format(new Date(target.dueAt)),
    })),
  }, null, 2));
}

async function main() {
  const now = new Date();
  if (process.argv.includes('--preview')) {
    const targets = await fetchTargets(now);
    preview(targets);
    return;
  }
  if (process.argv.includes('--test-dialog')) {
    // The display check has its own title and never writes a real reminder's
    // message or inserts fictional dates into an attendance notification.
    execFileSync('/usr/bin/osascript', [path.join(__dirname, 'test-dialog.applescript')], { timeout: 30000, stdio: 'ignore' });
    return;
  }

  let state = { targets: [], notified: {}, fetchedAt: 0 };
  try {
    const stored = JSON.parse(fs.readFileSync(statePath, 'utf8'));
    if (Array.isArray(stored.targets) && stored.notified && Number.isFinite(stored.fetchedAt)) state = stored;
  } catch (error) {
    if (error.code !== 'ENOENT') console.error('通知履歴を読み込めません。予定を再取得します。');
  }
  if (now.getTime() - state.fetchedAt >= syncPeriod) {
    try {
      state.targets = await fetchTargets(now);
      state.fetchedAt = Date.now();
      console.log(`[${new Date().toISOString()}] 出社・退社予定を同期しました。対象${state.targets.length}件。`);
    } catch (error) {
      // Never log the ICS URL, credential-bearing URLs, or a fetch stack trace.
      console.error(`[${new Date().toISOString()}] 予定を取得できません（${error.name}）。次の実行で再試行します。`);
      if (Date.now() - state.fetchedAt > maxCacheAge) {
        process.exitCode = 1;
        return;
      }
    }
  }
  const current = new Date();
  for (const target of dueTargets(state.targets, state.notified, current)) {
    const appName = target.kind === 'start' ? '出勤リマインダー' : '退勤リマインダー';
    writeAtomic(path.join(root, `calendar-${target.kind}.txt`), reminderMessage(target));
    try {
      const reminderApp = process.env.ATTENDANCE_REMINDER_APP_PATH ? path.join(process.env.ATTENDANCE_REMINDER_APP_PATH, 'Contents/Resources/reminders', `${appName}.app`) : path.join(root, `${appName}.app`);
      execFileSync('/usr/bin/open', [reminderApp], { timeout: 10000, stdio: 'ignore' });
      state.notified[target.id] = Date.now();
      console.log(`[${new Date().toISOString()}] ${target.kind === 'start' ? '出社' : '退社'}の通知を表示しました。`);
    } catch {
      console.error('リマインダーを開けません。次の実行で再試行します。');
    }
  }
  for (const [id, at] of Object.entries(state.notified)) {
    if (current.getTime() - at > 14 * 86400000) delete state.notified[id];
  }
  writeAtomic(statePath, JSON.stringify(state, null, 2));
}

main().catch(error => {
  console.error(`リマインダーを実行できません（${error.name}）。`);
  process.exitCode = 1;
});
