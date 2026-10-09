const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { createManager, makeAgent } = require('./app-manager.cjs');
const { defaultSchedule } = require('./weekly-schedule.cjs');
const label = 'com.outlook-attendance-reminder.calendar';
const calendar = 'BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//Reminder Test//EN\r\nEND:VCALENDAR\r\n';

function fixture(t) {
  const home = fs.mkdtempSync(path.join(os.tmpdir(), 'attendance-app-test-'));
  t.after(() => fs.rmSync(home, { recursive: true, force: true }));
  const root = path.join(home, 'Library/Application Support/OutlookAttendanceReminder');
  const bundle = path.join(home, 'Applications/打刻 & リマインダー.app');
  const calls = [], loaded = new Set(), fetches = [];
  let failNextBootstrap = false;
  const call = (command, args) => {
    calls.push({ command, args });
    if (command === '/usr/bin/plutil') {
      if (args[0] === '-lint') return { status: 0 };
      return { status: 0, stdout: fs.readFileSync(args.at(-1), 'utf8') };
    }
    if (command !== '/bin/launchctl') return { status: 0 };
    const name = args[1]?.split('/').at(-1);
    if (args[0] === 'print') return { status: loaded.has(name) ? 0 : 1 };
    if (args[0] === 'bootout') loaded.delete(name);
    if (args[0] === 'bootstrap') {
      if (failNextBootstrap) { failNextBootstrap = false; return { status: 1 }; }
      loaded.add(label);
    }
    return { status: 0 };
  };
  const manager = createManager({ home, root, bundle, arch: 'arm64', uid: 901, call, fetch: async () => { fetches.push(true); return new Response(calendar); } });
  const input = (value = 'https://example.invalid/calendar.ics') => { const file = path.join(home, 'private-input.txt'); fs.writeFileSync(file, value, { mode: 0o600 }); return file; };
  return { home, root, bundle, manager, input, calls, loaded, fetches, failBootstrap: () => { failNextBootstrap = true; } };
}

test('weekly mode configures without an Outlook account or network request and survives stop/restart', t => {
  const f = fixture(t); const weekly = { ...defaultSchedule(), mode: 'weekly' };
  const file = f.input(JSON.stringify(weekly)); f.manager.configureSchedule(file);
  assert.equal(fs.existsSync(file), false); assert.equal(fs.existsSync(path.join(f.root, 'config.json')), false);
  assert.equal(f.fetches.length, 0); assert.equal(f.manager.enabled(), true);
  assert.equal(fs.statSync(path.join(f.root, 'schedule.json')).mode & 0o777, 0o600);
  assert.match(f.manager.status(), /週間予定/);
  f.manager.stop(); f.manager.ensure(); assert.equal(f.manager.enabled(), false);
  f.manager.start(); assert.equal(f.manager.enabled(), true); assert.deepEqual(f.manager.schedule(), weekly);
});
test('mode changes preserve the Outlook link, weekday times, and notification history', async t => {
  const f = fixture(t); await f.manager.configure(f.input());
  const calendarConfig = fs.readFileSync(path.join(f.root, 'config.json'));
  const statePath = path.join(f.root, 'calendar-state.json'), state = { targets: [], notified: { previous: 123 }, fetchedAt: 0 };
  fs.writeFileSync(statePath, JSON.stringify(state));
  const weekly = { ...defaultSchedule(), mode: 'weekly' }; weekly.weekdays[3].end = '20:00';
  f.manager.configureSchedule(f.input(JSON.stringify(weekly)));
  f.manager.configureSchedule(f.input(JSON.stringify({ ...weekly, mode: 'outlook' })));
  assert.deepEqual(fs.readFileSync(path.join(f.root, 'config.json')), calendarConfig);
  assert.deepEqual(JSON.parse(fs.readFileSync(statePath)), state);
  assert.equal(f.manager.schedule().weekdays[3].end, '20:00'); assert.equal(f.fetches.length, 1);
});
test('Outlook saves without weekday inputs and keeps the previously saved weekly settings', async t => {
  const f = fixture(t); await f.manager.configure(f.input());
  const weekly = { ...defaultSchedule(), mode: 'weekly' };
  weekly.weekdays[1].end = '20:00'; weekly.weekdays[2].enabled = false;
  f.manager.configureSchedule(f.input(JSON.stringify(weekly)));
  const config = fs.readFileSync(path.join(f.root, 'config.json'));
  for (const value of [{ mode: 'outlook' }, { mode: 'outlook', weekdays: [{ enabled: 1, start: 'invalid' }] }]) {
    const input = f.input(JSON.stringify(value));
    assert.match(f.manager.configureSchedule(input), /Outlook/);
    assert.equal(fs.existsSync(input), false);
    assert.deepEqual(f.manager.schedule(), { ...weekly, mode: 'outlook' });
    assert.deepEqual(fs.readFileSync(path.join(f.root, 'config.json')), config);
    assert.equal(f.manager.enabled(), true);
  }
  assert.equal(f.fetches.length, 1);
});
test('invalid weekly settings and startup failures preserve the previous valid schedule', t => {
  const f = fixture(t), weekly = { ...defaultSchedule(), mode: 'weekly' };
  f.manager.configureSchedule(f.input(JSON.stringify(weekly)));
  for (const value of ['not json', JSON.stringify({ ...weekly, weekdays: [] }), JSON.stringify({ ...weekly, mode: 'outlook' })]) {
    const file = f.input(value); assert.throws(() => f.manager.configureSchedule(file));
    assert.equal(fs.existsSync(file), false); assert.deepEqual(f.manager.schedule(), weekly);
  }
  const changed = structuredClone(weekly); changed.weekdays[0].start = '10:00';
  f.failBootstrap(); assert.throws(() => f.manager.configureSchedule(f.input(JSON.stringify(changed))));
  assert.deepEqual(f.manager.schedule(), weekly); assert.equal(f.manager.enabled(), true);
});

test('configures using a private input file and only the bundled runtime, without changing the app bundle', async t => {
  const f = fixture(t); const file = f.input();
  await f.manager.configure(file);
  assert.equal(fs.existsSync(file), false);
  assert.equal(fs.statSync(path.join(f.root, 'config.json')).mode & 0o777, 0o600);
  assert.equal(fs.statSync(f.root).mode & 0o777, 0o700);
  assert.equal(fs.existsSync(f.bundle), false);
  const agent = fs.readFileSync(path.join(f.home, 'Library/LaunchAgents', `${label}.plist`), 'utf8');
  assert.ok(agent.includes('/Contents/Resources/runtime/arm64/node'));
  assert.ok(agent.includes('打刻 &amp; リマインダー.app'));
  assert.ok(!agent.includes('.nvm'));
  assert.ok(!agent.includes('example.invalid'));
  assert.equal(f.manager.enabled(), true);
});

test('invalid and inaccessible links retain the previous valid settings and remove temporary inputs', async t => {
  const f = fixture(t); await f.manager.configure(f.input());
  const before = fs.readFileSync(path.join(f.root, 'config.json'), 'utf8');
  for (const value of ['http://example.invalid/calendar.ics', 'https://name:secret@example.invalid/calendar.ics', 'not-a-url']) {
    const file = f.input(value); await assert.rejects(f.manager.configure(file)); assert.equal(fs.existsSync(file), false);
    assert.equal(fs.readFileSync(path.join(f.root, 'config.json'), 'utf8'), before);
  }
  const failed = createManager({ home: f.home, root: f.root, bundle: f.bundle, arch: 'arm64', uid: 901,
    call: () => ({ status: 0 }), fetch: async () => new Response('<html>sign in</html>') });
  await assert.rejects(failed.configure(f.input('https://example.invalid/wrong-link')));
  assert.equal(fs.readFileSync(path.join(f.root, 'config.json'), 'utf8'), before);
});

test('stop survives reopening, and restart preserves the calendar and notification history', async t => {
  const f = fixture(t); await f.manager.configure(f.input());
  const statePath = path.join(f.root, 'calendar-state.json'); const state = { notified: { 'test-event': 123 }, targets: [], fetchedAt: 456 };
  fs.writeFileSync(statePath, JSON.stringify(state));
  f.manager.stop(); assert.equal(f.manager.enabled(), false);
  const notificationPattern = f.calls.find(c => c.command === '/usr/bin/pkill').args[1];
  const notificationMatcher = new RegExp(notificationPattern);
  assert.ok(notificationMatcher.test(`${f.bundle}/Contents/Resources/reminders/退勤リマインダー.app/Contents/MacOS/launcher`));
  assert.equal(notificationMatcher.test('/Applications/another.app/Contents/MacOS/launcher'), false);
  const before = f.calls.length; f.manager.ensure(); assert.equal(f.calls.length, before);
  f.manager.start(); assert.equal(f.manager.enabled(), true);
  assert.deepEqual(JSON.parse(fs.readFileSync(statePath)), state);
});

test('migrates only this feature, preserves deduplication, and retires its old schedule after startup', t => {
  const f = fixture(t); const oldRoot = path.join(f.home, 'Library/Application Support/AttendanceReminder');
  fs.mkdirSync(oldRoot, { recursive: true }); fs.mkdirSync(path.join(f.home, '.outlook-calendar-sync'));
  fs.writeFileSync(path.join(f.home, '.outlook-calendar-sync/config.json'), JSON.stringify({ icsUrl: 'https://example.invalid/calendar.ics' }));
  fs.writeFileSync(path.join(oldRoot, 'calendar-reminder.cjs'), 'legacy fixture');
  const state = { notified: { 'test-event': 123 }, targets: [], fetchedAt: 456 };
  fs.writeFileSync(path.join(oldRoot, 'calendar-state.json'), JSON.stringify(state));
  const agents = path.join(f.home, 'Library/LaunchAgents'); fs.mkdirSync(agents, { recursive: true });
  const oldLabel = 'com.example.attendance-reminder.calendar'; f.loaded.add(oldLabel);
  fs.writeFileSync(path.join(agents, `${oldLabel}.plist`), JSON.stringify({ Label: oldLabel, ProgramArguments: ['node', path.join(oldRoot, 'calendar-reminder.cjs')] }));
  const unrelated = 'com.example.attendance-reminder.other'; f.loaded.add(unrelated);
  fs.writeFileSync(path.join(agents, `${unrelated}.plist`), JSON.stringify({ Label: unrelated, ProgramArguments: ['node', path.join(f.home, 'unrelated.cjs')] }));
  assert.equal(f.manager.canMigrate(), true); f.manager.migrate();
  assert.deepEqual(JSON.parse(fs.readFileSync(path.join(f.root, 'calendar-state.json'))), state);
  assert.equal(f.loaded.has(oldLabel), false); assert.equal(f.loaded.has(unrelated), true);
  const bootstrap = f.calls.findIndex(c => c.args[0] === 'bootstrap');
  const disableOld = f.calls.findIndex(c => c.args[0] === 'disable' && c.args[1].endsWith(oldLabel));
  assert.ok(bootstrap < disableOld);
});

test('a failed startup restores the previous schedule instead of leaving it unloaded', async t => {
  const f = fixture(t); await f.manager.configure(f.input());
  const agentPath = path.join(f.home, 'Library/LaunchAgents', `${label}.plist`);
  const before = fs.readFileSync(agentPath, 'utf8'); f.failBootstrap();
  assert.throws(() => f.manager.start());
  assert.equal(fs.readFileSync(agentPath, 'utf8'), before); assert.equal(f.loaded.has(label), true);
});

test('Intel and Apple silicon schedules point at their respective bundled executables', () => {
  const root = '/Users/example/Library/Application Support/OutlookAttendanceReminder';
  for (const arch of ['x64', 'arm64']) {
    const agent = makeAgent('/Applications/打刻リマインダー.app', root, arch, 901);
    assert.ok(agent.includes(`/runtime/${arch}/node`)); assert.ok(agent.includes('ATTENDANCE_REMINDER_APP_PATH'));
  }
});
