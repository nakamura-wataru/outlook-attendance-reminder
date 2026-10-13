const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { createManager, makeAgent, UiError } = require('./app-manager.cjs');
const { defaultSchedule } = require('./weekly-schedule.cjs');
const label = 'com.outlook-attendance-reminder.calendar';

function fixture(t, options = {}) {
  const home = fs.mkdtempSync(path.join(os.tmpdir(), 'attendance-app-test-'));
  t.after(() => fs.rmSync(home, { recursive: true, force: true }));
  const root = path.join(home, 'Library/Application Support/OutlookAttendanceReminder');
  const bundle = path.join(home, 'Applications/打刻リマインダー.app');
  const calls = [], loaded = new Set(); let failNextBootstrap = false;
  const call = (command, args) => {
    calls.push({ command, args });
    if (command === '/usr/bin/plutil') return args[0] === '-lint' ? { status: 0 } : { status: 0, stdout: fs.readFileSync(args.at(-1), 'utf8') };
    if (command !== '/bin/launchctl') return { status: 0 };
    const name = args[1]?.split('/').at(-1);
    if (args[0] === 'print') return { status: loaded.has(name) ? 0 : 1 };
    if (args[0] === 'bootout') loaded.delete(name);
    if (args[0] === 'bootstrap') { if (failNextBootstrap) { failNextBootstrap = false; return { status: 1 }; } loaded.add(label); }
    return { status: 0 };
  };
  const manager = createManager({ home, root, bundle, arch: 'arm64', uid: 901, call, ...options });
  const input = value => { const file = path.join(home, 'private-input.json'); fs.writeFileSync(file, JSON.stringify(value), { mode: 0o600 }); return file; };
  return { home, root, bundle, manager, input, calls, loaded, failBootstrap: () => { failNextBootstrap = true; } };
}
const now = new Date('2026-10-13T00:30:00Z');
const weekly = () => structuredClone(defaultSchedule());

test('a fresh install stays unconfigured and never requests a calendar connection', t => {
  const f = fixture(t, { now: () => now });
  assert.deepEqual(f.manager.overview(), { configured: false, enabled: false, source: 'weekly', nextReminder: null });
  assert.equal(f.loaded.size, 0);
  assert.equal(f.calls.some(call => call.command === '/usr/bin/curl'), false);
});

test('a weekly schedule starts offline and survives stopping and restarting', t => {
  const f = fixture(t, { now: () => now }), schedule = weekly();
  schedule.weekdays[1].start = '10:15'; schedule.weekdays[1].end = '20:00';
  assert.match(f.manager.configureSchedule(f.input(schedule)), /週間予定/);
  assert.equal(f.manager.enabled(), true);
  assert.equal(fs.existsSync(path.join(f.home, 'private-input.json')), false);
  assert.equal(fs.statSync(path.join(f.root, 'schedule.json')).mode & 0o777, 0o600);
  assert.equal(f.manager.overview().nextReminder.kind, 'start');
  f.manager.stop(); f.manager.ensure();
  assert.equal(f.manager.enabled(), false);
  assert.deepEqual(f.manager.schedule().weekdays[1], { day: 2, enabled: true, start: '10:15', end: '20:00' });
  f.manager.start(); assert.equal(f.manager.enabled(), true);
});

test('only five weekday rows are accepted and an invalid private input is consumed', t => {
  const f = fixture(t);
  for (const invalid of [{ mode: 'outlook', weekdays: weekly().weekdays }, { mode: 'weekly', weekdays: [] }]) {
    const file = f.input(invalid); assert.throws(() => f.manager.configureSchedule(file), UiError); assert.equal(fs.existsSync(file), false);
  }
  assert.equal(f.manager.configured(), false);
});

test('an older Outlook setup is converted to weekly times and its downloaded data is discarded', t => {
  const f = fixture(t, { now: () => now }); fs.mkdirSync(f.root, { recursive: true });
  const legacy = weekly(); legacy.mode = 'outlook'; legacy.weekdays[3].enabled = false; legacy.weekdays[4].end = '20:00'; legacy.icsUrl = 'private-link';
  fs.writeFileSync(path.join(f.root, 'schedule.json'), JSON.stringify(legacy), { mode: 0o600 });
  fs.writeFileSync(path.join(f.root, 'config.json'), JSON.stringify({ icsUrl: 'private-link' }), { mode: 0o600 });
  fs.writeFileSync(path.join(f.root, 'calendar-state.json'), JSON.stringify({ targets: [{ id: 'old' }], notified: { sent: 1 } }), { mode: 0o600 });
  fs.writeFileSync(path.join(f.root, 'calendar-start.txt'), 'private event', { mode: 0o600 });
  f.manager.ensure();
  assert.equal(f.manager.enabled(), true);
  assert.deepEqual(f.manager.schedule().weekdays[3], { day: 4, enabled: false, start: '09:45', end: '18:45' });
  assert.equal(f.manager.schedule().weekdays[4].end, '20:00');
  assert.equal(fs.existsSync(path.join(f.root, 'config.json')), false);
  assert.equal(fs.existsSync(path.join(f.root, 'calendar-start.txt')), false);
  assert.deepEqual(JSON.parse(fs.readFileSync(path.join(f.root, 'calendar-state.json'))), { notified: { sent: 1 } });
  assert.equal(JSON.stringify(f.manager.schedule()).includes('private-link'), false);
});

test('a stopped older setup is migrated without re-enabling notifications', t => {
  const f = fixture(t); fs.mkdirSync(f.root, { recursive: true }); const legacy = weekly(); legacy.mode = 'outlook';
  fs.writeFileSync(path.join(f.root, 'schedule.json'), JSON.stringify(legacy)); fs.writeFileSync(path.join(f.root, 'preferences.json'), JSON.stringify({ enabled: false }));
  f.manager.ensure(); assert.equal(f.manager.configured(), true); assert.equal(f.manager.enabled(), false); assert.equal(f.loaded.size, 0);
});

test('unusable older calendar data requires a new weekday setup instead of inventing notifications', t => {
  const f = fixture(t); fs.mkdirSync(f.root, { recursive: true }); const legacy = weekly(); legacy.mode = 'outlook'; legacy.weekdays.forEach(day => { day.enabled = false; });
  fs.writeFileSync(path.join(f.root, 'schedule.json'), JSON.stringify(legacy)); f.manager.ensure();
  assert.equal(f.manager.configured(), false); assert.equal(fs.existsSync(path.join(f.root, 'schedule.json')), false);
});

test('only a verified legacy helper is retired and unrelated settings remain intact', t => {
  const home = fs.mkdtempSync(path.join(os.tmpdir(), 'attendance-legacy-test-')); t.after(() => fs.rmSync(home, { recursive: true, force: true }));
  const root = path.join(home, 'Library/Application Support/OutlookAttendanceReminder'), legacyRoot = path.join(home, 'Library/Application Support/AttendanceReminder'), agents = path.join(home, 'Library/LaunchAgents');
  fs.mkdirSync(legacyRoot, { recursive: true }); fs.mkdirSync(agents, { recursive: true }); fs.writeFileSync(path.join(legacyRoot, 'calendar-reminder.cjs'), 'old');
  const config = path.join(home, '.outlook-calendar-sync/config.json'); fs.mkdirSync(path.dirname(config), { recursive: true }); fs.writeFileSync(config, JSON.stringify({ icsUrl: 'private-link', otherSetting: true }));
  fs.writeFileSync(path.join(agents, 'old-attendance-reminder.plist'), 'owned'); fs.writeFileSync(path.join(agents, 'unrelated-attendance-reminder.plist'), 'other');
  const calls = [], manager = createManager({ home, root, bundle: '/Applications/打刻リマインダー.app', arch: 'arm64', uid: 901, call: (command, args) => {
    calls.push({ command, args }); if (command === '/usr/bin/plutil') return { status: 0, stdout: JSON.stringify(args.at(-1).includes('old-') ? { Label: 'old-attendance-reminder', ProgramArguments: [path.join(legacyRoot, 'calendar-reminder.cjs')] } : { Label: 'unrelated', ProgramArguments: ['/tmp/other'] }) };
    if (command === '/bin/launchctl') return { status: args[0] === 'print' ? 1 : 0 }; return { status: 0 };
  } });
  manager.cleanupOutlook();
  assert.deepEqual(JSON.parse(fs.readFileSync(config)), { otherSetting: true });
  assert.equal(calls.some(call => call.args?.includes('gui/901/old-attendance-reminder')), true);
  assert.equal(calls.some(call => call.args?.includes('gui/901/unrelated')), false);
});

test('a failed automatic start restores the previous weekly schedule', t => {
  const f = fixture(t), original = weekly(); original.weekdays[0].start = '08:30'; f.manager.configureSchedule(f.input(original)); f.failBootstrap();
  const changed = weekly(); changed.weekdays[0].start = '10:00'; assert.throws(() => f.manager.configureSchedule(f.input(changed)), UiError);
  assert.equal(f.manager.schedule().weekdays[0].start, '08:30');
});

test('the launch agent uses the bundled runtime for the current architecture', () => {
  const agent = makeAgent('/Applications/打刻リマインダー.app', '/Users/example/Library/Application Support/OutlookAttendanceReminder', 'arm64', 501);
  assert.match(agent, /Resources\/runtime\/arm64\/node/); assert.match(agent, /calendar-reminder\.cjs/); assert.doesNotMatch(agent, /node-ical|icsUrl/);
});
