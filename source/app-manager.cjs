const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const { spawnSync } = require('node:child_process');
const ical = require('node-ical');
const { saveConfig } = require('./configure.cjs');
const label = 'com.outlook-attendance-reminder.calendar';
class UiError extends Error {}
const xml = value => String(value).replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
const processDirectory = value => `(${[...new Set(['NFC', 'NFD'].map(form => value.normalize(form)))].map(entry => entry.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')).join('|')})`;

function makeAgent(bundle, root, arch, uid) {
  const runtime = path.join(bundle, 'Contents/Resources/runtime', arch, 'node');
  const worker = path.join(bundle, 'Contents/Resources/app/calendar-reminder.cjs');
  return `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>${label}</string>
<key>ProgramArguments</key><array><string>${xml(runtime)}</string><string>${xml(worker)}</string></array>
<key>EnvironmentVariables</key><dict><key>ATTENDANCE_REMINDER_ROOT</key><string>${xml(root)}</string><key>ATTENDANCE_REMINDER_APP_PATH</key><string>${xml(bundle)}</string></dict>
<key>StartCalendarInterval</key><dict/>
<key>RunAtLoad</key><true/>
<key>LimitLoadToSessionType</key><string>Aqua</string>
<key>ProcessType</key><string>Background</string>
<key>StandardOutPath</key><string>${xml(path.join(root, 'calendar.log'))}</string>
<key>StandardErrorPath</key><string>${xml(path.join(root, 'calendar-error.log'))}</string>
</dict></plist>`;
}

function createManager(options = {}) {
  const home = options.home || os.homedir();
  const root = options.root || process.env.ATTENDANCE_REMINDER_ROOT || path.join(home, 'Library/Application Support/OutlookAttendanceReminder');
  const bundle = options.bundle || path.resolve(__dirname, '../../..');
  const arch = options.arch || process.arch;
  const uid = options.uid ?? process.getuid();
  const domain = `gui/${uid}`;
  const agents = path.join(home, 'Library/LaunchAgents');
  const agentPath = path.join(agents, `${label}.plist`);
  const configPath = path.join(root, 'config.json');
  const prefsPath = path.join(root, 'preferences.json');
  const legacyRoot = path.join(home, 'Library/Application Support/AttendanceReminder');
  const legacyConfig = path.join(home, '.outlook-calendar-sync/config.json');
  const call = options.call || ((command, args) => spawnSync(command, args, { encoding: 'utf8', timeout: 20000 }));
  const json = (filename, fallback) => { try { return JSON.parse(fs.readFileSync(filename, 'utf8')); } catch { return fallback; } };
  function ensureRoot() { fs.mkdirSync(root, { recursive: true, mode: 0o700 }); fs.chmodSync(root, 0o700); }
  function atomic(filename, data) {
    ensureRoot();
    const temporary = `${filename}.tmp`;
    fs.writeFileSync(temporary, data, { mode: 0o600 });
    fs.renameSync(temporary, filename);
    fs.chmodSync(filename, 0o600);
  }
  const loaded = () => call('/bin/launchctl', ['print', `${domain}/${label}`]).status === 0;
  const configured = () => {
    try { const value = new URL(json(configPath, {}).icsUrl); return value.protocol === 'https:' && !value.username && !value.password; }
    catch { return false; }
  };
  const enabled = () => configured() && json(prefsPath, {}).enabled !== false && loaded();
  function requiredCall(command, args) {
    if (call(command, args).status !== 0) throw new UiError('通知の自動実行を設定できませんでした。Macにログインした状態で、もう一度お試しください。');
  }
  function retireLegacy() {
    const currentURL = json(configPath, {}).icsUrl;
    if (!currentURL || json(legacyConfig, {}).icsUrl !== currentURL) return;
    if (!fs.existsSync(agents)) return;
    const legacyPrograms = ['calendar-reminder.cjs', '出勤リマインダー.app', '退勤リマインダー.app'].map(file => path.join(legacyRoot, file));
    for (const entry of fs.readdirSync(agents)) {
      if (!entry.endsWith('.plist') || !entry.includes('attendance-reminder') || entry === `${label}.plist`) continue;
      const result = call('/usr/bin/plutil', ['-convert', 'json', '-o', '-', path.join(agents, entry)]);
      if (result.status !== 0) continue;
      let old; try { old = JSON.parse(result.stdout); } catch { continue; }
      if (typeof old.Label !== 'string' || !Array.isArray(old.ProgramArguments) || !old.ProgramArguments.some(arg => legacyPrograms.includes(arg))) continue;
      requiredCall('/bin/launchctl', ['disable', `${domain}/${old.Label}`]);
      if (call('/bin/launchctl', ['print', `${domain}/${old.Label}`]).status === 0) requiredCall('/bin/launchctl', ['bootout', `${domain}/${old.Label}`]);
    }
  }
  function stopLegacyApplets() {
    const currentURL = json(configPath, {}).icsUrl;
    if (!currentURL || json(legacyConfig, {}).icsUrl !== currentURL) return;
    // A migration preserves already snoozed alerts; explicit Stop cancels them.
    call('/usr/bin/pkill', ['-f', `^${processDirectory(legacyRoot)}/[^/]+[.]app/Contents/MacOS/(applet|launcher)( |$)`]);
  }
  function start() {
    if (!configured()) throw new UiError('先に自分のOutlook予定表を設定してください。');
    if (!['arm64', 'x64'].includes(arch)) throw new UiError('このMacの種類には対応していません。');
    ensureRoot();
    fs.mkdirSync(agents, { recursive: true, mode: 0o700 });
    for (const filename of ['calendar.log', 'calendar-error.log']) {
      const file = path.join(root, filename);
      fs.closeSync(fs.openSync(file, 'a', 0o600));
      fs.chmodSync(file, 0o600);
    }
    const previous = fs.existsSync(agentPath) ? fs.readFileSync(agentPath) : null;
    const wasLoaded = loaded();
    const temporary = `${agentPath}.tmp`;
    fs.writeFileSync(temporary, makeAgent(bundle, root, arch, uid), { mode: 0o600 });
    requiredCall('/usr/bin/plutil', ['-lint', temporary]);
    if (wasLoaded) requiredCall('/bin/launchctl', ['bootout', `${domain}/${label}`]);
    fs.renameSync(temporary, agentPath);
    try {
      requiredCall('/bin/launchctl', ['enable', `${domain}/${label}`]);
      requiredCall('/bin/launchctl', ['bootstrap', domain, agentPath]);
    } catch (error) {
      if (previous) fs.writeFileSync(agentPath, previous, { mode: 0o600 });
      else fs.rmSync(agentPath, { force: true });
      if (wasLoaded && previous) call('/bin/launchctl', ['bootstrap', domain, agentPath]);
      throw error;
    }
    atomic(prefsPath, JSON.stringify({ enabled: true }));
    retireLegacy();
    return '通知を開始しました。アプリを閉じても通知は続きます。';
  }
  function stop() {
    requiredCall('/bin/launchctl', ['disable', `${domain}/${label}`]);
    if (loaded()) requiredCall('/bin/launchctl', ['bootout', `${domain}/${label}`]);
    const reminderApps = processDirectory(path.join(bundle, 'Contents/Resources/reminders'));
    call('/usr/bin/pkill', ['-f', `^${reminderApps}/[^/]+[.]app/Contents/MacOS/(applet|launcher)( |$)`]);
    atomic(prefsPath, JSON.stringify({ enabled: false }));
    retireLegacy();
    stopLegacyApplets();
    return '通知を停止しました。再開するまで通知しません。';
  }
  async function configure(inputFile) {
    let raw;
    try { raw = fs.readFileSync(inputFile, 'utf8').trim(); }
    finally { if (inputFile) fs.rmSync(inputFile, { force: true }); }
    let url;
    try { url = new URL(raw); } catch { throw new UiError('Outlook予定表のICSリンクを確認してください。'); }
    if (url.protocol !== 'https:' || url.username || url.password) throw new UiError('HTTPS形式のICSリンクを入力してください。');
    try {
      const response = await (options.fetch || fetch)(raw, { signal: AbortSignal.timeout(20000) });
      if (!response.ok) throw new Error('FetchFailed');
      const body = await response.text();
      if (!/^BEGIN:VCALENDAR\s*$/m.test(body)) throw new Error('InvalidCalendar');
      await ical.async.parseICS(body);
    } catch { throw new UiError('予定表を取得できませんでした。ICSリンクとネットワーク接続を確認してください。'); }
    const changed = json(configPath, {}).icsUrl !== raw;
    saveConfig(raw, root);
    if (changed) fs.rmSync(path.join(root, 'calendar-state.json'), { force: true });
    return start();
  }
  function migrate() {
    if (!configured()) {
      const oldURL = json(legacyConfig, {}).icsUrl;
      if (!oldURL || !fs.existsSync(path.join(legacyRoot, 'calendar-reminder.cjs'))) throw new UiError('引き継げる通知設定が見つかりません。予定表を設定してください。');
      saveConfig(oldURL, root);
      const oldState = path.join(legacyRoot, 'calendar-state.json');
      if (fs.existsSync(oldState)) atomic(path.join(root, 'calendar-state.json'), fs.readFileSync(oldState));
    }
    return start();
  }
  function ensure() {
    if (!configured() || json(prefsPath, {}).enabled === false) return;
    const wanted = makeAgent(bundle, root, arch, uid);
    if (!loaded() || !fs.existsSync(agentPath) || fs.readFileSync(agentPath, 'utf8') !== wanted) start();
  }
  function status() {
    if (!configured()) return '予定表：未設定\n自分のOutlook予定表を設定してください。';
    return enabled() ? '通知：有効\n出社・出勤は5分前、退社・退勤は予定時刻にお知らせします。\nこの画面を閉じても通知は続きます。' : '通知：停止中\n「通知を再開」から再開できます。';
  }
  return { root, bundle, configured, enabled, start, stop, configure, migrate, ensure, status,
    canMigrate: () => !configured() && typeof json(legacyConfig, {}).icsUrl === 'string' && fs.existsSync(path.join(legacyRoot, 'calendar-reminder.cjs')) };
}
module.exports = { createManager, makeAgent, UiError };
if (require.main === module) {
  (async () => {
    const manager = createManager();
    const command = process.argv[2];
    if (command === 'configured') console.log(manager.configured() ? 'yes' : 'no');
    else if (command === 'enabled') console.log(manager.enabled() ? 'yes' : 'no');
    else if (command === 'can-migrate') console.log(manager.canMigrate() ? 'yes' : 'no');
    else if (command === 'agent-preview') console.log(makeAgent(manager.bundle, manager.root, process.arch, process.getuid()));
    else if (['status', 'start', 'stop', 'migrate', 'ensure'].includes(command)) { const result = manager[command](); if (result) console.log(result); }
    else if (command === 'configure') console.log(await manager.configure(process.argv[3]));
    else throw new UiError('この操作には対応していません。');
  })().catch(error => { console.error(error instanceof UiError ? error.message : '設定を変更できませんでした。もう一度お試しください。'); process.exitCode = 1; });
}
