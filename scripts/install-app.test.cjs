const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const test = require('node:test');
const assert = require('node:assert/strict');
const { assertOwnedApp, replaceApp } = require('./install-app.cjs');
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
test('リンクをインストール先として使わない', t => {
  const dir = fixture(t); const real = path.join(dir, 'other'); const app = path.join(dir, 'linked.app');
  fs.mkdirSync(real); fs.symlinkSync(real, app);
  assert.throws(() => assertOwnedApp(app), /リンク/);
});
