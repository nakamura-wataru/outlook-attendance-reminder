const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
function saveConfig(raw, root) {
  const input = raw.trim();
  let url;
  try { url = new URL(input); } catch { throw new Error('ICSリンクの形式を確認してください。'); }
  if (url.protocol !== 'https:' || url.username || url.password) throw new Error('HTTPS形式のICSリンクを入力してください。');
  fs.mkdirSync(root, { recursive: true, mode: 0o700 });
  const filename = path.join(root, 'config.json');
  const temporary = `${filename}.tmp`;
  fs.writeFileSync(temporary, JSON.stringify({ icsUrl: input }, null, 2), { mode: 0o600 });
  fs.renameSync(temporary, filename);
  fs.chmodSync(filename, 0o600);
}
module.exports = { saveConfig };
if (require.main === module) {
  const root = process.env.ATTENDANCE_REMINDER_ROOT || path.join(os.homedir(), 'Library/Application Support/OutlookAttendanceReminder');
  try { saveConfig(fs.readFileSync(0, 'utf8'), root); }
  catch (error) { console.error(error.message); process.exitCode = 1; }
}
