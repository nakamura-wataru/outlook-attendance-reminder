#!/usr/bin/env node
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { execFileSync } = require('node:child_process');
const { dueTargets, reminderMessage } = require('./calendar-core.cjs');
const { readSchedule, weeklyTargets } = require('./weekly-schedule.cjs');
function readJSON(file, fallback) { try { return JSON.parse(fs.readFileSync(file, 'utf8')); } catch { return fallback; } }
function runReminder(options = {}) {
  const root = options.root || process.env.ATTENDANCE_REMINDER_ROOT || path.join(os.homedir(), 'Library/Application Support/OutlookAttendanceReminder');
  if (readJSON(path.join(root, 'preferences.json'), {}).enabled === false || !fs.existsSync(path.join(root, 'schedule.json'))) return;
  const now = options.now || new Date(), statePath = path.join(root, 'calendar-state.json');
  const stored = readJSON(statePath, {});
  const notified = stored.notified && typeof stored.notified === 'object' && !Array.isArray(stored.notified) ? stored.notified : {};
  const targets = weeklyTargets(readSchedule(root), now);
  const show = options.show || (target => {
    const name = target.kind === 'start' ? '出勤リマインダー' : '退勤リマインダー';
    const file = path.join(root, `calendar-${target.kind}.txt`);
    fs.writeFileSync(file, reminderMessage(target), { mode: 0o600 }); fs.chmodSync(file, 0o600);
    const bundle = process.env.ATTENDANCE_REMINDER_APP_PATH;
    const app = bundle ? path.join(bundle, 'Contents/Resources/reminders', `${name}.app`) : path.join(root, `${name}.app`);
    execFileSync('/usr/bin/open', [app], { timeout: 10000, stdio: 'ignore' });
  });
  for (const target of dueTargets(targets, notified, now)) {
    try { show(target); notified[target.id] = now.getTime(); }
    catch { console.error('リマインダーを開けません。次の実行で再試行します。'); }
  }
  for (const [id, at] of Object.entries(notified)) if (now.getTime() - at > 14 * 86400000) delete notified[id];
  // Keep only deduplication history, never a downloaded calendar or event cache.
  fs.writeFileSync(`${statePath}.tmp`, JSON.stringify({ notified }), { mode: 0o600 });
  fs.renameSync(`${statePath}.tmp`, statePath); fs.chmodSync(statePath, 0o600);
}
module.exports = { runReminder };
if (require.main === module) {
  try { runReminder(); } catch { console.error('リマインダーを実行できません。週間予定を設定し直してください。'); process.exitCode = 1; }
}
