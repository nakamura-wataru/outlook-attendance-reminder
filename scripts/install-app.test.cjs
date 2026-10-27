const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const test = require('node:test');
const assert = require('node:assert/strict');
const { assertOwnedApp, replaceApp, makeBundle } = require('./install-app.cjs');
function fixture(t) { const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'attendance-install-test-')); t.after(() => fs.rmSync(dir, { recursive: true, force: true })); return dir; }
test('同名の別アプリを上書きしない', t => {
  const dir = fixture(t); const app = path.join(dir, '打刻リマインダー.app'); fs.mkdirSync(app);
  fs.writeFileSync(path.join(app, 'keep.txt'), 'existing app');
  assert.throws(() => assertOwnedApp(app, () => 'com.example.other'), /別アプリ/);
  assert.equal(fs.readFileSync(path.join(app, 'keep.txt'), 'utf8'), 'existing app');
});
test('置き換えに失敗した場合は以前のアプリを戻す', t => {
  const dir = fixture(t); const target = path.join(dir, 'old.app'); const stage = path.join(dir, 'new.app');
  fs.mkdirSync(target); fs.writeFileSync(path.join(target, 'version'), 'old'); fs.mkdirSync(stage);
  const rename = (from, to) => { if (from === stage) throw new Error('Disk failure'); fs.renameSync(from, to); };
  assert.throws(() => replaceApp(stage, target, rename), /Disk failure/);
  assert.equal(fs.readFileSync(path.join(target, 'version'), 'utf8'), 'old');
  assert.equal(fs.readdirSync(dir).some(name => name.includes('backup-')), false);
});
test('旧名のアプリを残さず、ときともへ置き換える', t => {
  const dir = fixture(t), legacy = path.join(dir, '打刻リマインダー.app'), target = path.join(dir, 'ときとも.app'), stage = path.join(dir, 'staged.app');
  fs.mkdirSync(legacy); fs.writeFileSync(path.join(legacy, 'version'), 'old');
  fs.mkdirSync(stage); fs.writeFileSync(path.join(stage, 'version'), 'new');
  replaceApp(stage, target, fs.renameSync, [legacy]);
  assert.equal(fs.readFileSync(path.join(target, 'version'), 'utf8'), 'new');
  assert.deepEqual(fs.readdirSync(dir), ['ときとも.app']);
});
test('名前変更に失敗した場合は旧名と更新先のアプリを両方戻す', t => {
  const dir = fixture(t), legacy = path.join(dir, '打刻リマインダー.app'), target = path.join(dir, 'ときとも.app'), stage = path.join(dir, 'staged.app');
  for (const [app, version] of [[legacy, 'legacy'], [target, 'current'], [stage, 'new']]) { fs.mkdirSync(app); fs.writeFileSync(path.join(app, 'version'), version); }
  const rename = (from, to) => { if (from === stage) throw new Error('Disk failure'); fs.renameSync(from, to); };
  assert.throws(() => replaceApp(stage, target, rename, [legacy]), /Disk failure/);
  assert.equal(fs.readFileSync(path.join(legacy, 'version'), 'utf8'), 'legacy');
  assert.equal(fs.readFileSync(path.join(target, 'version'), 'utf8'), 'current');
  assert.equal(fs.readdirSync(dir).some(name => name.includes('backup-')), false);
});
test('リンクをインストール先として使わない', t => {
  const dir = fixture(t); const real = path.join(dir, 'other'); const app = path.join(dir, 'linked.app');
  fs.mkdirSync(real); fs.symlinkSync(real, app);
  assert.throws(() => assertOwnedApp(app), /リンク/);
});
test('メインと出勤・退勤のアプリにFinder用アイコンを同梱する', t => {
  const dir = fixture(t), launcher = path.join(dir, 'launcher'); fs.writeFileSync(launcher, 'fixture');
  for (const suffix of ['app', 'start', 'end']) {
    const app = path.join(dir, `${suffix}.app`);
    makeBundle(app, `com.outlook-attendance-reminder.${suffix}`, '打刻リマインダー', 'test', launcher);
    const info = fs.readFileSync(path.join(app, 'Contents/Info.plist'), 'utf8');
    const iconName = info.match(/<key>CFBundleIconFile<\/key><string>([^<]+)<\/string>/)?.[1];
    assert.ok(iconName, 'Finder can resolve an icon from the bundle metadata');
    const icon = fs.readFileSync(path.join(app, 'Contents/Resources', iconName));
    assert.equal(icon.toString('ascii', 0, 4), 'icns'); assert.equal(icon.readUInt32BE(4), icon.length);
    const representations = [];
    for (let offset = 8; offset < icon.length;) {
      const size = icon.readUInt32BE(offset + 4); assert.ok(size >= 8 && offset + size <= icon.length);
      representations.push(icon.toString('ascii', offset, offset + 4)); offset += size;
    }
    for (const type of ['ic04', 'ic05', 'ic10', 'ic11', 'ic12']) assert.ok(representations.includes(type), `${type} supports small, Retina, and large icon displays`);
  }
});
