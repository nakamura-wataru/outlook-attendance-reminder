const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const { spawnSync } = require('node:child_process');
const { readSchedule, validateSchedule, weeklyTargets } = require('./weekly-schedule.cjs');
const { nextReminder } = require('./calendar-core.cjs');
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
  const domain = `gui/${options.uid ?? process.getuid()}`;
  const agents = path.join(home, 'Library/LaunchAgents'), agentPath = path.join(agents, `${label}.plist`);
  const prefsPath = path.join(root, 'preferences.json'), schedulePath = path.join(root, 'schedule.json'), statePath = path.join(root, 'calendar-state.json');
  const legacyRoot = path.join(home, 'Library/Application Support/AttendanceReminder');
  const legacyConfig = path.join(home, '.outlook-calendar-sync/config.json');
  const call = options.call || ((command, args) => spawnSync(command, args, { encoding: 'utf8', timeout: 20000 }));
  const json = (file, fallback) => { try { return JSON.parse(fs.readFileSync(file, 'utf8')); } catch { return fallback; } };
  function ensureRoot() { fs.mkdirSync(root, { recursive: true, mode: 0o700 }); fs.chmodSync(root, 0o700); }
  function atomic(file, data) {
    ensureRoot(); fs.writeFileSync(`${file}.tmp`, JSON.stringify(data), { mode: 0o600 });
    fs.renameSync(`${file}.tmp`, file); fs.chmodSync(file, 0o600);
  }
  const loaded = () => call('/bin/launchctl', ['print', `${domain}/${label}`]).status === 0;
  const configured = () => { try { return fs.existsSync(schedulePath) && !!readSchedule(root); } catch { return false; } };
  const enabled = () => configured() && json(prefsPath, {}).enabled !== false && loaded();
  function requiredCall(command, args) {
    if (call(command, args).status !== 0) throw new UiError('通知の自動実行を設定できませんでした。Macにログインした状態で、もう一度お試しください。');
  }
  function retireLegacy() {
    if (!fs.existsSync(agents)) return;
    const programs = ['calendar-reminder.cjs', '出勤リマインダー.app', '退勤リマインダー.app'].map(file => path.join(legacyRoot, file));
    for (const entry of fs.readdirSync(agents)) {
      if (!entry.endsWith('.plist') || !entry.includes('attendance-reminder') || entry === `${label}.plist`) continue;
      const result = call('/usr/bin/plutil', ['-convert', 'json', '-o', '-', path.join(agents, entry)]);
      if (result.status !== 0) continue;
      let old; try { old = JSON.parse(result.stdout); } catch { continue; }
      if (typeof old.Label !== 'string' || !Array.isArray(old.ProgramArguments) || !old.ProgramArguments.some(arg => programs.includes(arg))) continue;
      requiredCall('/bin/launchctl', ['disable', `${domain}/${old.Label}`]);
      if (call('/bin/launchctl', ['print', `${domain}/${old.Label}`]).status === 0) requiredCall('/bin/launchctl', ['bootout', `${domain}/${old.Label}`]);
    }
  }
  function cleanupOutlook() {
    const saved = json(schedulePath, null), state = json(statePath, {}) || {};
    const legacyOwned = fs.existsSync(path.join(legacyRoot, 'calendar-reminder.cjs'));
    const oldConfig = (legacyOwned ? json(legacyConfig, {}) : {}) || {};
    const files = ['config.json', 'config.json.tmp', 'calendar-state.json.tmp'];
    const needsCleanup = files.some(file => fs.existsSync(path.join(root, file))) || saved?.mode === 'outlook' || Array.isArray(state.targets) || Object.hasOwn(oldConfig, 'icsUrl');
    if (!needsCleanup) return;
    // Stop the previous worker before removing its link and downloaded data.
    if (loaded()) requiredCall('/bin/launchctl', ['bootout', `${domain}/${label}`]);
    retireLegacy();
    call('/usr/bin/pkill', ['-f', `^${processDirectory(legacyRoot)}/[^/]+[.]app/Contents/MacOS/(applet|launcher)( |$)`]);
    if (saved?.mode === 'outlook') {
      let weekly;
      try { weekly = validateSchedule({ ...saved, mode: 'weekly' }); }
      catch { fs.rmSync(schedulePath, { force: true }); weekly = null; }
      if (weekly) atomic(schedulePath, weekly);
    }
    if (fs.existsSync(statePath)) atomic(statePath, { notified: state.notified && typeof state.notified === 'object' && !Array.isArray(state.notified) ? state.notified : {} });
    for (const name of [...files, 'calendar-start.txt', 'calendar-end.txt', 'calendar-start.txt.tmp', 'calendar-end.txt.tmp', 'calendar.log', 'calendar-error.log']) fs.rmSync(path.join(root, name), { force: true });
    if (legacyOwned) {
      delete oldConfig.icsUrl;
      if (fs.existsSync(legacyConfig)) {
        if (Object.keys(oldConfig).length) { fs.writeFileSync(legacyConfig, JSON.stringify(oldConfig), { mode: 0o600 }); fs.chmodSync(legacyConfig, 0o600); }
        else fs.rmSync(legacyConfig);
      }
      fs.rmSync(`${legacyConfig}.tmp`, { force: true });
      for (const name of ['config.json', 'config.json.tmp', 'calendar-state.json', 'calendar-state.json.tmp', 'calendar-start.txt', 'calendar-end.txt', 'calendar.log', 'calendar-error.log']) fs.rmSync(path.join(legacyRoot, name), { force: true });
    }
  }
  function start() {
    cleanupOutlook();
    if (!configured()) throw new UiError('先に月〜金の出勤・退勤時刻を設定してください。');
    if (!['arm64', 'x64'].includes(arch)) throw new UiError('このMacの種類には対応していません。');
    ensureRoot(); fs.mkdirSync(agents, { recursive: true, mode: 0o700 });
    for (const filename of ['calendar.log', 'calendar-error.log']) {
      const file = path.join(root, filename); fs.closeSync(fs.openSync(file, 'a', 0o600)); fs.chmodSync(file, 0o600);
    }
    const previous = fs.existsSync(agentPath) ? fs.readFileSync(agentPath) : null, wasLoaded = loaded();
    fs.writeFileSync(`${agentPath}.tmp`, makeAgent(bundle, root, arch, options.uid ?? process.getuid()), { mode: 0o600 });
    requiredCall('/usr/bin/plutil', ['-lint', `${agentPath}.tmp`]);
    if (wasLoaded) requiredCall('/bin/launchctl', ['bootout', `${domain}/${label}`]);
    fs.renameSync(`${agentPath}.tmp`, agentPath);
    try { requiredCall('/bin/launchctl', ['enable', `${domain}/${label}`]); requiredCall('/bin/launchctl', ['bootstrap', domain, agentPath]); }
    catch (error) {
      if (previous) fs.writeFileSync(agentPath, previous, { mode: 0o600 }); else fs.rmSync(agentPath, { force: true });
      if (wasLoaded && previous) call('/bin/launchctl', ['bootstrap', domain, agentPath]);
      throw error;
    }
    atomic(prefsPath, { enabled: true }); retireLegacy();
    return '通知を開始しました。アプリを閉じても通知は続きます。';
  }
  function stop() {
    requiredCall('/bin/launchctl', ['disable', `${domain}/${label}`]);
    if (loaded()) requiredCall('/bin/launchctl', ['bootout', `${domain}/${label}`]);
    const reminders = processDirectory(path.join(bundle, 'Contents/Resources/reminders'));
    call('/usr/bin/pkill', ['-f', `^${reminders}/[^/]+[.]app/Contents/MacOS/(applet|launcher)( |$)`]);
    atomic(prefsPath, { enabled: false }); retireLegacy();
    return '通知を停止しました。再開するまで通知しません。';
  }
  function configureSchedule(inputFile) {
    let value;
    try { value = JSON.parse(fs.readFileSync(inputFile, 'utf8')); }
    catch { throw new UiError('週間予定を読み取れませんでした。もう一度設定してください。'); }
    finally { if (inputFile) fs.rmSync(inputFile, { force: true }); }
    let schedule; try { schedule = validateSchedule(value); } catch (error) { throw new UiError(error.message); }
    cleanupOutlook();
    const previous = fs.existsSync(schedulePath) ? fs.readFileSync(schedulePath) : null;
    atomic(schedulePath, schedule);
    try { start(); } catch (error) {
      if (previous) atomic(schedulePath, JSON.parse(previous)); else fs.rmSync(schedulePath, { force: true });
      throw error;
    }
    return '月〜金の週間予定で通知を開始しました。出勤は5分前、退勤は予定時刻にお知らせします。';
  }
  function ensure() {
    cleanupOutlook();
    if (!configured() || json(prefsPath, {}).enabled === false) return;
    const wanted = makeAgent(bundle, root, arch, options.uid ?? process.getuid());
    if (!loaded() || !fs.existsSync(agentPath) || fs.readFileSync(agentPath, 'utf8') !== wanted) start();
  }
  function status() {
    if (!configured()) return '週間予定：未設定\n月〜金の出勤・退勤時刻を設定してください。';
    return enabled() ? '通知：有効\n通知元：週間予定（月〜金）\n出勤は5分前、退勤は予定時刻にお知らせします。' : '通知：停止中\n「通知を再開」から再開できます。';
  }
  function overview() {
    const now = options.now ? options.now() : new Date(), ready = configured(), active = enabled();
    const notified = json(statePath, {}).notified || {};
    return { configured: ready, enabled: active, source: 'weekly', nextReminder: active ? nextReminder(weeklyTargets(readSchedule(root), now), notified, now) : null };
  }
  return { root, bundle, configured, enabled, start, stop, configureSchedule, schedule: () => readSchedule(root), cleanupOutlook, ensure, status, overview };
}
module.exports = { createManager, makeAgent, UiError };
if (require.main === module) {
  try {
    const manager = createManager(), command = process.argv[2];
    if (command === 'configured') console.log(manager.configured() ? 'yes' : 'no');
    else if (command === 'enabled') console.log(manager.enabled() ? 'yes' : 'no');
    else if (['status', 'start', 'stop', 'ensure'].includes(command)) { const result = manager[command](); if (result) console.log(result); }
    else if (command === 'schedule') console.log(JSON.stringify(manager.schedule()));
    else if (command === 'overview' || command === 'overview-refresh') console.log(JSON.stringify(manager.overview()));
    else if (command === 'configure-schedule') console.log(manager.configureSchedule(process.argv[3]));
    else throw new UiError('この操作には対応していません。');
  } catch (error) { console.error(error instanceof UiError ? error.message : '設定を変更できませんでした。もう一度お試しください。'); process.exitCode = 1; }
}
