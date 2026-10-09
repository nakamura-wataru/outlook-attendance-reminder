const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const crypto = require('node:crypto');
const { spawnSync } = require('node:child_process');
const appName = '打刻リマインダー.app';
const bundleIdentifier = 'com.outlook-attendance-reminder.app';
const project = path.resolve(__dirname, '..');
const xml = value => String(value).replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

function command(file, args) {
  const result = spawnSync(file, args, { encoding: 'utf8' });
  if (result.status !== 0) throw new Error(`${path.basename(file)}に失敗しました。${result.stderr?.trim() || ''}`);
  return result.stdout.trim();
}
function writable(directory) { try { fs.accessSync(directory, fs.constants.W_OK); return true; } catch { return false; } }
function installationDirectory(home = os.homedir()) {
  const existing = path.join('/Applications', appName);
  if (fs.existsSync(existing) && !writable('/Applications')) throw new Error('既存のアプリを更新する権限がありません。管理者にインストールを依頼してください。');
  return writable('/Applications') ? '/Applications' : path.join(home, 'Applications');
}
function assertOwnedApp(app, identify = filename => command('/usr/bin/plutil', ['-extract', 'CFBundleIdentifier', 'raw', '-o', '-', filename])) {
  if (!fs.existsSync(app)) return;
  if (fs.lstatSync(app).isSymbolicLink()) throw new Error('インストール先がリンクになっています。別の場所を指定してください。');
  let identifier;
  try { identifier = identify(path.join(app, 'Contents/Info.plist')); } catch { /* Refuse unknown contents. */ }
  if (identifier !== bundleIdentifier) throw new Error('同名の別アプリがあります。既存のアプリは変更していません。');
}
function replaceApp(staged, target, rename = fs.renameSync) {
  const backup = `${target}.backup-${crypto.randomUUID()}`;
  const exists = fs.existsSync(target);
  if (exists) rename(target, backup);
  try { rename(staged, target); }
  catch (error) { if (exists) rename(backup, target); throw error; }
  if (exists) fs.rmSync(backup, { recursive: true, force: true });
}
function makeBundle(app, identifier, name, version, launcher) {
  fs.mkdirSync(path.join(app, 'Contents/MacOS'), { recursive: true });
  fs.mkdirSync(path.join(app, 'Contents/Resources'), { recursive: true });
  fs.copyFileSync(launcher, path.join(app, 'Contents/MacOS/launcher'));
  fs.chmodSync(path.join(app, 'Contents/MacOS/launcher'), 0o755);
  fs.writeFileSync(path.join(app, 'Contents/Info.plist'), `<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>launcher</string>
<key>CFBundleIdentifier</key><string>${xml(identifier)}</string>
<key>CFBundleName</key><string>${xml(name)}</string>
<key>CFBundleDisplayName</key><string>${xml(name)}</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>${xml(version)}</string>
<key>CFBundleShortVersionString</key><string>${xml(version)}</string>
<key>LSMinimumSystemVersion</key><string>11.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>\n`);
}
function buildApp(app, runtime, arch) {
  if (!['arm64', 'x64'].includes(arch)) throw new Error('このMacの種類には対応していません。');
  const launcher = path.join(project, 'native/launcher');
  const expected = fs.readFileSync(path.join(project, 'native/launcher.sha256'), 'utf8').trim().split(/\s/)[0];
  if (crypto.createHash('sha256').update(fs.readFileSync(launcher)).digest('hex') !== expected) throw new Error('同梱アプリの検証に失敗しました。Gitから取得し直してください。');
  const { version } = JSON.parse(fs.readFileSync(path.join(project, 'package.json')));
  makeBundle(app, bundleIdentifier, '打刻リマインダー', version, launcher);
  const resources = path.join(app, 'Contents/Resources');
  const scripts = path.join(resources, 'app');
  fs.mkdirSync(scripts);
  for (const file of ['calendar-core.cjs', 'calendar-reminder.cjs', 'app-manager.cjs', 'configure.cjs', 'test-dialog.applescript', 'THIRD_PARTY_NOTICES.md']) fs.copyFileSync(path.join(project, 'source', file), path.join(scripts, file));
  fs.copyFileSync(path.join(project, 'package.json'), path.join(scripts, 'package.json'));
  fs.cpSync(path.join(project, 'node_modules'), path.join(scripts, 'node_modules'), { recursive: true });
  fs.copyFileSync(path.join(project, 'source/launch-manager.sh'), path.join(resources, 'launch-manager.sh'));
  fs.chmodSync(path.join(resources, 'launch-manager.sh'), 0o755);
  fs.copyFileSync(path.join(project, 'README.md'), path.join(resources, 'README.md'));
  const runtimeDir = path.join(resources, 'runtime', arch);
  fs.mkdirSync(runtimeDir, { recursive: true });
  fs.copyFileSync(path.join(runtime, 'bin/node'), path.join(runtimeDir, 'node'));
  fs.copyFileSync(path.join(runtime, 'LICENSE'), path.join(runtimeDir, 'LICENSE'));
  fs.chmodSync(path.join(runtimeDir, 'node'), 0o755);
  command('/usr/bin/codesign', ['--force', '--sign', '-', path.join(runtimeDir, 'node')]);
  for (const [kind, name] of [['start', '出勤リマインダー'], ['end', '退勤リマインダー']]) {
    const notification = path.join(resources, 'reminders', `${name}.app`);
    makeBundle(notification, `com.outlook-attendance-reminder.${kind}`, name, version, launcher);
    command('/usr/bin/codesign', ['--force', '--sign', '-', notification]);
  }
  command('/usr/bin/codesign', ['--force', '--sign', '-', app]);
  command('/usr/bin/codesign', ['--verify', '--deep', '--strict', app]);
}
function main() {
  if (process.platform !== 'darwin') throw new Error('このアプリはMac専用です。');
  if (process.getuid() === 0) throw new Error('sudoを付けずに、自分のアカウントでインストールしてください。');
  const args = process.argv.slice(2);
  const value = flag => { const index = args.indexOf(flag); return index < 0 ? undefined : args[index + 1]; };
  const runtime = value('--runtime');
  const arch = value('--arch');
  if (!runtime || !arch) throw new Error('install.commandまたはnpm installから実行してください。');
  const directory = path.resolve(process.env.ATTENDANCE_APPLICATIONS_DIR || installationDirectory());
  fs.mkdirSync(directory, { recursive: true });
  const target = path.join(directory, appName);
  assertOwnedApp(target);
  const stage = fs.mkdtempSync(path.join(directory, '.attendance-install-'));
  try {
    const app = path.join(stage, appName);
    console.log('Macアプリを作成しています…');
    buildApp(app, runtime, arch);
    assertOwnedApp(target);
    replaceApp(app, target);
  } finally { fs.rmSync(stage, { recursive: true, force: true }); }
  console.log(`インストール完了：${target}\n「打刻リマインダー」を開き、自分のOutlook予定表を設定してください。`);
  if (!args.includes('--no-open') && process.env.ATTENDANCE_NO_OPEN !== '1') command('/usr/bin/open', [target]);
}
module.exports = { assertOwnedApp, replaceApp, makeBundle };
if (require.main === module) {
  try { main(); } catch (error) { console.error(error.message); process.exitCode = 1; }
}
