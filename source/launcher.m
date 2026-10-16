#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>
#include <fcntl.h>
#include <unistd.h>
#import "reminder-artwork.h"
@interface ReminderCard : NSView
@property BOOL canvas;
@property BOOL accent;
@end
@implementation ReminderCard
- (void)drawRect:(NSRect)dirtyRect {
    [ReminderColor(self.canvas ? @"canvas" : (self.accent ? @"primary-soft" : @"surface")) setFill];
    NSBezierPath *shape = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds, .5, .5) xRadius:8 yRadius:8]; [shape fill];
    if (!self.canvas) { [ReminderColor(self.accent ? @"primary" : @"hairline") setStroke]; shape.lineWidth = 1; [shape stroke]; }
}
- (void)viewDidChangeEffectiveAppearance { [super viewDidChangeEffectiveAppearance]; [self setNeedsDisplay:YES]; }
@end
@interface ReminderClock : NSView
@end
@implementation ReminderClock
- (void)drawRect:(NSRect)dirtyRect { DrawReminderClock(self.bounds); }
- (void)viewDidChangeEffectiveAppearance { [super viewDidChangeEffectiveAppearance]; [self setNeedsDisplay:YES]; }
@end

static NSString *RecorderGuardScript(NSArray<NSString *> *lockedKinds) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:lockedKinds options:0 error:nil];
    NSString *initialLocks = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"[]";
    return [NSString stringWithFormat:@"(() => { if (!location.hostname.endsWith('.ta.kingoftime.jp')) return;"
        "const guard = window.__attendanceReminderGuard || (window.__attendanceReminderGuard = { locked: new Set(%@), approved: new WeakSet() });"
        "const kindFor = (target) => { const control = target.closest('button,input[type=button],input[type=submit],[role=button],a'); if (!control) return null; const label = (control.innerText || control.value || control.getAttribute('aria-label') || '').replace(/\\s/g, ''); return label === '出勤' || label === '退勤' ? { control, kind: label } : null; };"
        "const notify = (action, kind) => { try { window.webkit.messageHandlers.attendanceReminderGuard.postMessage({ action, kind }); } catch (_) {} };"
        "const controls = () => document.querySelectorAll('button,input[type=button],input[type=submit],[role=button],a');"
        "const apply = () => { controls().forEach((control) => { const item = kindFor(control); if (item && guard.locked.has(item.kind)) { control.style.pointerEvents = 'none'; control.style.opacity = '0.45'; control.setAttribute('aria-disabled', 'true'); } }); };"
        "const render = () => { const current = document.getElementById('attendance-reminder-guard'); if (current) current.remove(); if (!guard.locked.size || !document.body) return; const kinds = [...guard.locked].join('・'); const notice = document.createElement('div'); notice.id = 'attendance-reminder-guard'; notice.style.cssText = 'position:fixed;z-index:2147483647;top:12px;left:12px;right:12px;padding:12px 14px;border-radius:10px;background:#1c2040;color:#fff;font:14px -apple-system,BlinkMacSystemFont,sans-serif;box-shadow:0 4px 16px rgba(0,0,0,.25);display:flex;align-items:center;gap:12px'; notice.innerHTML = `<span>${kinds}をこの画面で選択済みです。公式画面の結果を確認してください。</span><button type=\"button\" style=\"margin-left:auto;border:0;border-radius:7px;padding:7px 10px;background:#fff;color:#1c2040;font:600 13px -apple-system,BlinkMacSystemFont,sans-serif\">選択を戻す</button>`; notice.querySelector('button').addEventListener('click', () => { guard.locked.clear(); controls().forEach((control) => { control.style.pointerEvents = ''; control.style.opacity = ''; control.removeAttribute('aria-disabled'); }); notify('unlock'); render(); }); document.body.appendChild(notice); };"
        "document.addEventListener('click', (event) => { const item = kindFor(event.target); if (!item) return; if (guard.approved.has(item.control)) { guard.approved.delete(item.control); return; } event.preventDefault(); event.stopImmediatePropagation(); if (guard.locked.has(item.kind)) return; if (!window.confirm(`${item.kind}を打刻しますか？`)) return; guard.locked.add(item.kind); notify('lock', item.kind); guard.approved.add(item.control); apply(); render(); item.control.click(); }, true);"
        "const observer = new MutationObserver(() => { apply(); });"
        "const start = () => { observer.observe(document.documentElement, { childList: true, subtree: true }); apply(); render(); };"
        "document.readyState === 'loading' ? document.addEventListener('DOMContentLoaded', start, { once: true }) : start();"
    "})();", initialLocks];
}

@interface ReminderController : NSObject <NSApplicationDelegate, NSWindowDelegate, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler>
@property NSWindow *window;
@property NSTextField *statusLabel;
@property NSTextField *statusBadge;
@property NSTextField *nextReminderTitle;
@property NSTextField *nextReminderDate;
@property NSTextField *nextReminderDetail;
@property NSStackView *managerLayout;
@property NSTimer *overviewTimer;
@property BOOL commandBusy;
@property BOOL overviewRefreshing;
@property BOOL overviewPendingRefresh;
@property NSUInteger overviewRevision;
@property NSButton *toggleButton;
@property NSMutableArray<NSButton *> *buttons;
@property BOOL notificationMode;
@property NSString *kind;
@property NSTimer *reminderTimer;
@property BOOL repeated;
@property BOOL showingAlert;
@property BOOL testMode;
@property BOOL launching;
@property NSMutableArray<NSString *> *pendingKinds;
@property (weak) ReminderController *owner;
@property NSMutableDictionary<NSString *, ReminderController *> *notifications;
@property NSTimer *enabledTimer;
@property NSTextField *reminderLabel;
@property NSPopUpButton *snoozeChoice;
@property NSWindow *recorderWindow;
@property WKWebView *recorderWebView;
@property NSTextField *recorderStatus;
@property NSWindow *scheduleWindow;
@property NSButton *scheduleSaveButton;
@property NSArray<NSButton *> *weekdayButtons;
@property NSArray<NSDatePicker *> *startPickers;
@property NSArray<NSDatePicker *> *endPickers;
@property BOOL scheduleBusy;
@property NSStackView *scheduleLayout;
@property NSView *weeklySettingsCard;
@property NSTextField *scheduleHint;
@property NSStackView *notificationLayout;
@property NSStackView *notificationRecorderPanel;
@property NSButton *notificationRecorderButton;
@property NSLayoutConstraint *notificationFillConstraint;
@property BOOL notificationRecorderOpen;
@end

@implementation ReminderController
- (NSString *)resources { return [NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"Contents/Resources"]; }
- (void)setBusy:(BOOL)busy {
    self.commandBusy = busy;
    if (busy) self.overviewRevision++;
    for (NSButton *button in self.buttons) button.enabled = !busy;
}
- (void)runCommand:(NSString *)command input:(NSString *)input completion:(void (^)(BOOL, NSString *))completion {
    [self runCommand:command input:input blocking:YES completion:completion];
}
- (void)runCommand:(NSString *)command input:(NSString *)input blocking:(BOOL)blocking completion:(void (^)(BOOL, NSString *))completion {
    if (blocking) [self setBusy:YES];
    NSString *runner = [[self resources] stringByAppendingPathComponent:@"launch-manager.sh"];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        @autoreleasepool {
            NSTask *task = [[NSTask alloc] init];
            task.executableURL = [NSURL fileURLWithPath:@"/bin/bash"];
            task.arguments = input ? @[runner, command, input] : @[runner, command];
            NSPipe *pipe = [NSPipe pipe], *errors = [NSPipe pipe]; task.standardOutput = pipe; task.standardError = errors;
            NSError *error = nil;
            BOOL launched = [task launchAndReturnError:&error];
            __block NSData *errorData = nil;
            dispatch_group_t reads = dispatch_group_create();
            if (launched) dispatch_group_async(reads, dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{ errorData = [errors.fileHandleForReading readDataToEndOfFile]; });
            NSData *data = launched ? [pipe.fileHandleForReading readDataToEndOfFile] : nil;
            if (launched) { [task waitUntilExit]; dispatch_group_wait(reads, DISPATCH_TIME_FOREVER); }
            BOOL ok = launched && task.terminationStatus == 0;
            NSData *messageData = !ok && errorData.length ? errorData : data;
            NSString *message = messageData ? [[NSString alloc] initWithData:messageData encoding:NSUTF8StringEncoding] : @"アプリの操作を実行できませんでした。";
            message = [message stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            dispatch_async(dispatch_get_main_queue(), ^{ if (blocking) [self setBusy:NO]; completion(ok, message ?: @"もう一度お試しください。"); });
        }
    });
}
- (void)showMessage:(NSString *)message {
    NSAlert *alert = [[NSAlert alloc] init]; alert.messageText = @"打刻リマインダー";
    alert.icon = [self clockImage];
    alert.informativeText = message; [alert addButtonWithTitle:@"閉じる"];
    [alert beginSheetModalForWindow:self.scheduleWindow.visible ? self.scheduleWindow : self.window completionHandler:nil];
}
- (NSString *)overviewDate:(NSString *)value format:(NSString *)format {
    if (![value isKindOfClass:NSString.class]) return @"";
    NSISO8601DateFormatter *iso = [[NSISO8601DateFormatter alloc] init];
    iso.formatOptions = NSISO8601DateFormatWithInternetDateTime | NSISO8601DateFormatWithFractionalSeconds;
    NSDate *date = [iso dateFromString:value];
    if (!date) return @"";
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init]; formatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"ja_JP"];
    formatter.calendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    formatter.timeZone = [NSTimeZone timeZoneWithName:@"Asia/Tokyo"]; formatter.dateFormat = format;
    return [formatter stringFromDate:date];
}
- (void)updateManagerLayout {
    if (!self.managerLayout) return;
    [self.window.contentView layoutSubtreeIfNeeded];
    [self.window setContentSize:NSMakeSize(560, ceil(self.managerLayout.fittingSize.height + 48))];
}
- (void)applyOverview:(NSDictionary *)view {
    BOOL configured = [view[@"configured"] boolValue], enabled = [view[@"enabled"] boolValue];
    self.toggleButton.title = enabled ? @"通知を停止" : @"通知を再開";
    self.statusBadge.stringValue = configured ? @"● 週間予定を設定済み" : @"○ 予定はまだ未設定です";
    self.statusLabel.stringValue = configured ? @"選んだ曜日の出勤・退勤時刻に合わせてお知らせします。" : @"「通知の予定を設定」から始めましょう。";
    NSDictionary *next = [view[@"nextReminder"] isKindOfClass:NSDictionary.class] ? view[@"nextReminder"] : nil;
    self.nextReminderDate.hidden = !next; self.nextReminderDetail.hidden = !next;
    if (next) {
        BOOL arrival = [next[@"kind"] isEqualToString:@"start"];
        self.nextReminderTitle.stringValue = arrival ? @"次は出勤のお知らせ" : @"次は退勤のお知らせ";
        self.nextReminderDate.stringValue = [self overviewDate:next[@"dueAt"] format:@"M月d日（EEE）H:mm"];
        self.nextReminderDetail.stringValue = [NSString stringWithFormat:@"%@予定 %@%@", arrival ? @"出勤" : @"退勤", [self overviewDate:next[@"plannedAt"] format:@"H:mm"], arrival ? @" の5分前" : @" になったら"];
    } else {
        self.nextReminderTitle.stringValue = !configured ? @"次のお知らせは、設定後に表示します" : !enabled ? @"お知らせはお休み中です" : @"向こう8日間に出勤・退勤の予定はありません";
        if (configured && !enabled) self.statusLabel.stringValue = @"通知は停止中です。「通知を再開」から再開できます。";
    }
    [self updateManagerLayout];
}
- (void)refreshOverview:(BOOL)force {
    if (self.commandBusy || self.overviewRefreshing) { if (force) self.overviewPendingRefresh = YES; return; }
    self.overviewRefreshing = YES;
    NSUInteger revision = self.overviewRevision;
    if (force) self.statusLabel.stringValue = @"予定を確認しています…";
    [self runCommand:force ? @"overview-refresh" : @"overview" input:nil blocking:NO completion:^(BOOL ok, NSString *text) {
        self.overviewRefreshing = NO;
        if (revision == self.overviewRevision) {
            NSDictionary *view = ok ? [NSJSONSerialization JSONObjectWithData:[text dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil] : nil;
            if ([view isKindOfClass:NSDictionary.class]) [self applyOverview:view];
            else {
                self.statusBadge.stringValue = @"△ 予定を確認できませんでした";
                self.statusLabel.stringValue = @"しばらくしてから、もう一度お試しください。";
                self.nextReminderTitle.stringValue = @"次のお知らせを確認できませんでした";
                self.nextReminderDate.hidden = YES; self.nextReminderDetail.hidden = YES; [self updateManagerLayout];
            }
        }
        if (self.overviewPendingRefresh && !self.commandBusy) { self.overviewPendingRefresh = NO; [self refreshOverview:YES]; }
    }];
}
- (void)refreshStatus { [self refreshOverview:YES]; }
- (void)refreshOverviewTimer:(NSTimer *)timer {
    if (self.window.visible && !self.window.attachedSheet && !self.scheduleWindow.visible) [self refreshOverview:NO];
}
- (NSButton *)button:(NSString *)title selector:(SEL)selector {
    NSButton *button = [NSButton buttonWithTitle:title target:self action:selector];
    button.bezelStyle = NSBezelStyleRounded; button.translatesAutoresizingMaskIntoConstraints = NO;
    button.font = [NSFont systemFontOfSize:14];
    [button.heightAnchor constraintEqualToConstant:34].active = YES;
    [self.buttons addObject:button]; return button;
}
- (NSImage *)clockImage {
    return [NSImage imageWithSize:NSMakeSize(128, 128) flipped:NO drawingHandler:^BOOL(NSRect rect) { DrawReminderClock(rect); return YES; }];
}
- (NSTextField *)label:(NSString *)text size:(CGFloat)size strong:(BOOL)strong muted:(BOOL)muted {
    NSTextField *label = [NSTextField wrappingLabelWithString:text];
    label.font = [NSFont systemFontOfSize:size weight:strong ? NSFontWeightSemibold : NSFontWeightRegular];
    label.textColor = [NSColor colorWithName:nil dynamicProvider:^NSColor *(NSAppearance *appearance) {
        __block NSColor *color; [appearance performAsCurrentDrawingAppearance:^{ color = ReminderColor(muted ? @"ink-mute" : @"ink"); }]; return color;
    }];
    return label;
}
- (NSStackView *)verticalStack:(CGFloat)spacing {
    NSStackView *stack = [[NSStackView alloc] init]; stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading; stack.spacing = spacing; stack.translatesAutoresizingMaskIntoConstraints = NO;
    return stack;
}
- (NSView *)card:(NSView *)content {
    ReminderCard *card = [[ReminderCard alloc] init]; card.translatesAutoresizingMaskIntoConstraints = NO;
    content.translatesAutoresizingMaskIntoConstraints = NO; [card addSubview:content];
    [NSLayoutConstraint activateConstraints:@[
        [content.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16],
        [content.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16],
        [content.topAnchor constraintEqualToAnchor:card.topAnchor constant:16],
        [content.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-16]
    ]];
    return card;
}
- (NSView *)scheduleCard:(BOOL)arrival {
    NSStackView *stack = [self verticalStack:8];
    [stack addArrangedSubview:[self label:arrival ? @"出勤のお知らせ" : @"退勤のお知らせ" size:15 strong:YES muted:NO]];
    [stack addArrangedSubview:[self label:arrival ? @"予定の5分前" : @"予定時刻になったら" size:18 strong:YES muted:NO]];
    return [self card:stack];
}
- (void)showManager {
    self.buttons = [NSMutableArray array];
    self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,560,620) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskMiniaturizable backing:NSBackingStoreBuffered defer:NO];
    self.window.title = @"打刻リマインダー"; self.window.releasedWhenClosed = NO; [self.window center];
    ReminderCard *background = [[ReminderCard alloc] init]; background.canvas = YES; self.window.contentView = background;
    NSStackView *stack = [self verticalStack:16]; self.managerLayout = stack; stack.detachesHiddenViews = YES;
    [self.window.contentView addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:self.window.contentView.leadingAnchor constant:24],
        [stack.trailingAnchor constraintEqualToAnchor:self.window.contentView.trailingAnchor constant:-24],
        [stack.topAnchor constraintEqualToAnchor:self.window.contentView.topAnchor constant:24],
        [stack.bottomAnchor constraintLessThanOrEqualToAnchor:self.window.contentView.bottomAnchor constant:-24]
    ]];
    ReminderClock *clock = [[ReminderClock alloc] init]; clock.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[[clock.widthAnchor constraintEqualToConstant:72], [clock.heightAnchor constraintEqualToConstant:72]]];
    clock.accessibilityLabel = @"笑顔の時計"; clock.accessibilityRole = NSAccessibilityImageRole;
    NSStackView *greeting = [self verticalStack:8];
    [greeting addArrangedSubview:[self label:@"打刻のおとも" size:18 strong:YES muted:NO]];
    [greeting addArrangedSubview:[self label:@"仕事のはじめと、おわりをお知らせ。" size:14 strong:NO muted:YES]];
    NSStackView *header = [NSStackView stackViewWithViews:@[clock, greeting]]; header.spacing = 16; header.alignment = NSLayoutAttributeCenterY;
    [stack addArrangedSubview:header];
    NSStackView *status = [self verticalStack:8];
    self.statusBadge = [self label:@"○ 確認中" size:15 strong:YES muted:NO]; [status addArrangedSubview:self.statusBadge];
    self.statusLabel = [self label:@"設定を確認しています…" size:13 strong:NO muted:YES]; [status addArrangedSubview:self.statusLabel];
    NSStackView *next = [self verticalStack:4]; next.detachesHiddenViews = YES;
    self.nextReminderTitle = [self label:@"次のお知らせを確認しています…" size:15 strong:YES muted:NO];
    self.nextReminderDate = [self label:@"" size:18 strong:YES muted:NO]; self.nextReminderDate.hidden = YES;
    self.nextReminderDetail = [self label:@"" size:13 strong:NO muted:YES]; self.nextReminderDetail.hidden = YES;
    [next addArrangedSubview:self.nextReminderTitle]; [next addArrangedSubview:self.nextReminderDate]; [next addArrangedSubview:self.nextReminderDetail];
    ReminderClock *nextClock = [[ReminderClock alloc] init]; nextClock.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[[nextClock.widthAnchor constraintEqualToConstant:48], [nextClock.heightAnchor constraintEqualToConstant:48]]];
    NSStackView *nextRow = [NSStackView stackViewWithViews:@[nextClock, next]]; nextRow.spacing = 12; nextRow.alignment = NSLayoutAttributeCenterY;
    [status addArrangedSubview:nextRow]; [status setCustomSpacing:16 afterView:self.statusLabel];
    [nextRow.widthAnchor constraintEqualToAnchor:status.widthAnchor].active = YES;
    [next.widthAnchor constraintEqualToAnchor:status.widthAnchor constant:-60].active = YES;
    for (NSTextField *label in @[self.nextReminderTitle, self.nextReminderDate, self.nextReminderDetail]) [label.widthAnchor constraintEqualToAnchor:next.widthAnchor].active = YES;
    NSView *statusCard = [self card:status]; [stack addArrangedSubview:statusCard];
    [statusCard.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
    [self.statusLabel.widthAnchor constraintEqualToAnchor:status.widthAnchor].active = YES;
    NSStackView *schedule = [NSStackView stackViewWithViews:@[[self scheduleCard:YES], [self scheduleCard:NO]]];
    schedule.spacing = 16; schedule.distribution = NSStackViewDistributionFillEqually; schedule.alignment = NSLayoutAttributeTop;
    [stack addArrangedSubview:schedule]; [schedule.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
    NSButton *configure = [self button:@"通知の予定を設定" selector:@selector(configureSchedule:)]; configure.toolTip = @"曜日ごとの出勤・退勤時刻を設定します";
    NSButton *test = [self button:@"表示をテスト" selector:@selector(testReminder:)]; test.toolTip = @"通知内のKING OF TIMEと再通知の選択肢を確認します。再通知は予約しません";
    NSButton *recorder = [self button:@"KING OF TIMEで打刻" selector:@selector(openRecorder:)]; recorder.toolTip = @"アプリ内に公式Myレコーダーを開きます。初回はログインしてください";
    NSStackView *actions = [NSStackView stackViewWithViews:@[configure, test, recorder]]; actions.spacing = 12; [stack addArrangedSubview:actions];
    self.toggleButton = [self button:@"通知を再開" selector:@selector(toggle:)]; self.toggleButton.toolTip = @"通知の停止・再開は、Macを再起動しても維持されます";
    NSButton *help = [self button:@"使い方" selector:@selector(help:)];
    NSStackView *secondary = [NSStackView stackViewWithViews:@[self.toggleButton, help]]; secondary.spacing = 12; [stack addArrangedSubview:secondary];
    NSImage *appIcon = [[NSImage alloc] initWithContentsOfFile:[[self resources] stringByAppendingPathComponent:@"AppIcon.icns"]];
    [NSApp setApplicationIconImage:appIcon ?: [self clockImage]];
    if (!self.launching) { [self.window makeKeyAndOrderFront:nil]; [NSApp activateIgnoringOtherApps:YES]; }
    [self runCommand:@"ensure" input:nil completion:^(BOOL ok, NSString *message) { [self refreshStatus]; }];
    self.overviewTimer = [NSTimer scheduledTimerWithTimeInterval:60 target:self selector:@selector(refreshOverviewTimer:) userInfo:nil repeats:YES];
}
- (NSDateFormatter *)scheduleTimeFormatter:(BOOL)includeDate {
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init]; formatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
    formatter.timeZone = [NSTimeZone timeZoneWithName:@"Asia/Tokyo"]; formatter.dateFormat = includeDate ? @"yyyy-MM-dd HH:mm" : @"HH:mm"; return formatter;
}
- (NSDatePicker *)schedulePicker:(NSString *)time {
    NSDatePicker *picker = [[NSDatePicker alloc] init]; picker.translatesAutoresizingMaskIntoConstraints = NO;
    picker.datePickerStyle = NSDatePickerStyleTextFieldAndStepper; picker.datePickerElements = NSDatePickerElementFlagHourMinute;
    picker.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"ja_JP"]; picker.timeZone = [NSTimeZone timeZoneWithName:@"Asia/Tokyo"];
    picker.calendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian]; picker.calendar.timeZone = picker.timeZone;
    picker.font = [NSFont systemFontOfSize:14]; picker.drawsBackground = YES;
    picker.dateValue = [[self scheduleTimeFormatter:YES] dateFromString:[@"2001-01-01 " stringByAppendingString:time]];
    [NSLayoutConstraint activateConstraints:@[[picker.widthAnchor constraintEqualToConstant:128], [picker.heightAnchor constraintEqualToConstant:30]]];
    return picker;
}
- (void)updateScheduleControls:(id)sender {
    self.scheduleHint.stringValue = @"出勤は予定の5分前、退勤は予定時刻に通知します。\n日本時間で、チェックした曜日に毎週繰り返します。";
    self.scheduleSaveButton.enabled = !self.scheduleBusy;
    for (NSUInteger index = 0; index < self.weekdayButtons.count; index++) {
        NSButton *day = self.weekdayButtons[index]; day.enabled = !self.scheduleBusy;
        BOOL enabled = day.enabled && day.state == NSControlStateValueOn;
        self.startPickers[index].enabled = enabled; self.endPickers[index].enabled = enabled;
    }
    [self.scheduleWindow.contentView layoutSubtreeIfNeeded];
    [self.scheduleWindow setContentSize:NSMakeSize(560, ceil(self.scheduleLayout.fittingSize.height + 48))];
}
- (void)configureSchedule:(id)sender {
    if (!self.scheduleWindow) {
        self.scheduleWindow = [[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,560,536) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskMiniaturizable backing:NSBackingStoreBuffered defer:NO];
        self.scheduleWindow.title = @"通知の予定を設定"; self.scheduleWindow.releasedWhenClosed = NO; [self.scheduleWindow center];
        ReminderCard *background = [[ReminderCard alloc] init]; background.canvas = YES; self.scheduleWindow.contentView = background;
        NSStackView *stack = [self verticalStack:16]; self.scheduleLayout = stack; stack.detachesHiddenViews = YES; [self.scheduleWindow.contentView addSubview:stack];
        [NSLayoutConstraint activateConstraints:@[
            [stack.leadingAnchor constraintEqualToAnchor:self.scheduleWindow.contentView.leadingAnchor constant:24],
            [stack.trailingAnchor constraintEqualToAnchor:self.scheduleWindow.contentView.trailingAnchor constant:-24],
            [stack.topAnchor constraintEqualToAnchor:self.scheduleWindow.contentView.topAnchor constant:24],
            [stack.bottomAnchor constraintLessThanOrEqualToAnchor:self.scheduleWindow.contentView.bottomAnchor constant:-24]
        ]];
        [stack addArrangedSubview:[self label:@"月〜金の出勤・退勤時刻" size:18 strong:YES muted:NO]];
        NSStackView *weekly = [self verticalStack:12];
        NSTextField *dayHeader = [self label:@"通知する曜日" size:13 strong:YES muted:YES]; [dayHeader.widthAnchor constraintEqualToConstant:96].active = YES;
        NSTextField *startHeader = [self label:@"出勤予定" size:13 strong:YES muted:YES]; [startHeader.widthAnchor constraintEqualToConstant:128].active = YES;
        NSTextField *endHeader = [self label:@"退勤予定" size:13 strong:YES muted:YES]; [endHeader.widthAnchor constraintEqualToConstant:128].active = YES;
        NSStackView *columns = [NSStackView stackViewWithViews:@[dayHeader, startHeader, endHeader]]; columns.spacing = 24; [weekly addArrangedSubview:columns];
        NSMutableArray *days = [NSMutableArray array], *starts = [NSMutableArray array], *ends = [NSMutableArray array];
        for (NSString *name in @[@"月曜日", @"火曜日", @"水曜日", @"木曜日", @"金曜日"]) {
            NSButton *day = [NSButton checkboxWithTitle:name target:self action:@selector(updateScheduleControls:)]; day.font = [NSFont systemFontOfSize:14]; day.state = NSControlStateValueOn;
            [day.widthAnchor constraintEqualToConstant:96].active = YES;
            NSDatePicker *start = [self schedulePicker:@"09:45"], *end = [self schedulePicker:@"18:45"];
            start.accessibilityLabel = [name stringByAppendingString:@"の出勤予定時刻"]; end.accessibilityLabel = [name stringByAppendingString:@"の退勤予定時刻"];
            NSStackView *row = [NSStackView stackViewWithViews:@[day, start, end]]; row.spacing = 24; row.alignment = NSLayoutAttributeCenterY;
            [weekly addArrangedSubview:row]; [days addObject:day]; [starts addObject:start]; [ends addObject:end];
        }
        self.weekdayButtons = days; self.startPickers = starts; self.endPickers = ends;
        self.weeklySettingsCard = [self card:weekly]; [stack addArrangedSubview:self.weeklySettingsCard]; [self.weeklySettingsCard.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
        self.scheduleHint = [self label:@"" size:12 strong:NO muted:YES]; [stack addArrangedSubview:self.scheduleHint];
        [self.scheduleHint.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
        self.scheduleSaveButton = [self button:@"保存して開始" selector:@selector(saveSchedule:)]; [self.buttons removeObject:self.scheduleSaveButton];
        [stack addArrangedSubview:self.scheduleSaveButton];
    }
    [self.scheduleWindow makeKeyAndOrderFront:nil]; [NSApp activateIgnoringOtherApps:YES];
    self.scheduleBusy = YES; [self updateScheduleControls:nil];
    [self runCommand:@"schedule" input:nil completion:^(BOOL ok, NSString *text) {
        self.scheduleBusy = NO;
        NSDictionary *schedule = ok ? [NSJSONSerialization JSONObjectWithData:[text dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil] : nil;
        if ([schedule isKindOfClass:NSDictionary.class]) {
            NSArray *rows = schedule[@"weekdays"];
            if ([rows isKindOfClass:NSArray.class] && rows.count == 5) for (NSUInteger index = 0; index < 5; index++) {
                NSDictionary *row = rows[index]; self.weekdayButtons[index].state = [row[@"enabled"] boolValue] ? NSControlStateValueOn : NSControlStateValueOff;
                self.startPickers[index].dateValue = [[self scheduleTimeFormatter:YES] dateFromString:[@"2001-01-01 " stringByAppendingString:row[@"start"]]];
                self.endPickers[index].dateValue = [[self scheduleTimeFormatter:YES] dateFromString:[@"2001-01-01 " stringByAppendingString:row[@"end"]]];
            }
        } else [self showMessage:ok ? @"予定の設定を読み取れませんでした。" : text];
        [self updateScheduleControls:nil];
    }];
}
- (void)saveSchedule:(id)sender {
    NSMutableArray *days = [NSMutableArray array]; NSDateFormatter *formatter = [self scheduleTimeFormatter:NO];
    for (NSUInteger index = 0; index < 5; index++) [days addObject:@{
        @"day": @(index + 1), @"enabled": self.weekdayButtons[index].state == NSControlStateValueOn ? @YES : @NO,
        @"start": [formatter stringFromDate:self.startPickers[index].dateValue], @"end": [formatter stringFromDate:self.endPickers[index].dateValue]
    }];
    NSDictionary *schedule = @{@"mode": @"weekly", @"weekdays": days};
    NSData *data = [NSJSONSerialization dataWithJSONObject:schedule options:0 error:nil];
    NSString *temporary = [NSTemporaryDirectory() stringByAppendingPathComponent:[@"attendance-schedule-" stringByAppendingString:NSUUID.UUID.UUIDString]];
    int descriptor = open(temporary.fileSystemRepresentation, O_WRONLY|O_CREAT|O_EXCL, 0600);
    if (descriptor < 0) { [self showMessage:@"予定を保存する準備ができませんでした。"]; return; }
    const uint8_t *bytes = data.bytes; NSUInteger written = 0;
    while (written < data.length) { ssize_t count = write(descriptor, bytes + written, data.length - written); if (count <= 0) break; written += (NSUInteger)count; }
    close(descriptor);
    if (written != data.length) { unlink(temporary.fileSystemRepresentation); [self showMessage:@"予定を保存できませんでした。"]; return; }
    self.scheduleBusy = YES; [self updateScheduleControls:nil];
    [self runCommand:@"configure-schedule" input:temporary completion:^(BOOL ok, NSString *message) {
        unlink(temporary.fileSystemRepresentation); self.scheduleBusy = NO; [self updateScheduleControls:nil];
        if (ok) [self.scheduleWindow orderOut:nil];
        [self showMessage:message]; [self refreshStatus];
    }];
}
- (void)toggle:(id)sender {
    NSString *command = [self.toggleButton.title isEqualToString:@"通知を停止"] ? @"stop" : @"start";
    [self runCommand:command input:nil completion:^(BOOL ok, NSString *message) {
        if (ok && [command isEqualToString:@"stop"]) for (ReminderController *notification in self.notifications.allValues) [notification closeNotification:nil];
        [self showMessage:message]; [self refreshStatus];
    }];
}
- (NSUserDefaults *)recorderPreferences { return [[NSUserDefaults alloc] initWithSuiteName:@"com.outlook-attendance-reminder.recorder"]; }
- (NSString *)recorderGuardDate {
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
    formatter.calendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    formatter.timeZone = [NSTimeZone timeZoneWithName:@"Asia/Tokyo"];
    formatter.dateFormat = @"yyyy-MM-dd";
    return [formatter stringFromDate:NSDate.date];
}
- (NSString *)recorderGuardKey:(NSString *)kind { return [kind isEqualToString:@"出勤"] ? @"punchGuard.arrivalDate" : @"punchGuard.departureDate"; }
- (NSArray<NSString *> *)lockedRecorderKinds {
    NSUserDefaults *prefs = [self recorderPreferences];
    NSString *today = [self recorderGuardDate];
    NSMutableArray<NSString *> *locked = [NSMutableArray array];
    for (NSString *kind in @[@"出勤", @"退勤"]) if ([[prefs stringForKey:[self recorderGuardKey:kind]] isEqualToString:today]) [locked addObject:kind];
    return locked;
}
- (void)installRecorderGuard {
    if (!self.recorderWebView) return;
    WKUserContentController *content = self.recorderWebView.configuration.userContentController;
    [content removeAllUserScripts];
    [content addUserScript:[[WKUserScript alloc] initWithSource:RecorderGuardScript([self lockedRecorderKinds]) injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:YES]];
}
- (void)userContentController:(WKUserContentController *)controller didReceiveScriptMessage:(WKScriptMessage *)message {
    if (![message.name isEqualToString:@"attendanceReminderGuard"] || ![message.body isKindOfClass:NSDictionary.class] || ![message.frameInfo.request.URL.host hasSuffix:@".ta.kingoftime.jp"]) return;
    NSDictionary *body = message.body;
    NSString *action = body[@"action"], *kind = body[@"kind"];
    NSUserDefaults *prefs = [self recorderPreferences];
    if ([action isEqualToString:@"lock"] && ([@"出勤" isEqualToString:kind] || [@"退勤" isEqualToString:kind])) [prefs setObject:[self recorderGuardDate] forKey:[self recorderGuardKey:kind]];
    else if ([action isEqualToString:@"unlock"]) {
        [prefs removeObjectForKey:[self recorderGuardKey:@"出勤"]];
        [prefs removeObjectForKey:[self recorderGuardKey:@"退勤"]];
    } else return;
    [self installRecorderGuard];
}
- (NSURL *)recorderURL {
    NSUserDefaults *prefs = [self recorderPreferences];
    NSString *server = [prefs stringForKey:@"server"];
    if (![@[@"s2", @"s3", @"s4"] containsObject:server]) server = @"s2";
    NSString *path = [prefs boolForKey:@"saml"] ? @"recorder2" : @"recorder";
    return [NSURL URLWithString:[NSString stringWithFormat:@"https://%@.ta.kingoftime.jp/independent/%@/personal/", server, path]];
}
- (void)configureRecorder:(id)sender {
    NSAlert *alert = [[NSAlert alloc] init]; alert.messageText = @"Myレコーダーの接続設定"; alert.icon = [self clockImage];
    alert.informativeText = @"普段使うMyレコーダーのURLを見て選んでください。\nパスワードやAPIトークンはここでは入力しません。";
    NSUserDefaults *prefs = [self recorderPreferences];
    NSStackView *fields = [self verticalStack:12]; fields.frame = NSMakeRect(0,0,320,104);
    NSPopUpButton *server = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0,0,320,28) pullsDown:NO];
    [server addItemsWithTitles:@[@"s2.ta.kingoftime.jp", @"s3.ta.kingoftime.jp", @"s4.ta.kingoftime.jp"]];
    NSInteger index = [@[@"s2", @"s3", @"s4"] indexOfObject:[prefs stringForKey:@"server"] ?: @"s2"];
    [server selectItemAtIndex:index == NSNotFound ? 0 : index]; server.accessibilityLabel = @"KING OF TIMEのサーバー";
    NSPopUpButton *auth = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0,0,320,28) pullsDown:NO];
    [auth addItemsWithTitles:@[@"通常ログイン（/recorder/）", @"SAML・SSO（/recorder2/）"]];
    [auth selectItemAtIndex:[prefs boolForKey:@"saml"] ? 1 : 0]; auth.accessibilityLabel = @"ログイン方式";
    [fields addArrangedSubview:server]; [fields addArrangedSubview:auth]; alert.accessoryView = fields;
    [alert addButtonWithTitle:@"保存して開く"]; [alert addButtonWithTitle:@"キャンセル"];
    NSWindow *parent = self.recorderWebView.window ?: self.window;
    [alert beginSheetModalForWindow:parent completionHandler:^(NSModalResponse response) {
        if (response != NSAlertFirstButtonReturn) return;
        [prefs setObject:@[@"s2", @"s3", @"s4"][(NSUInteger)server.indexOfSelectedItem] forKey:@"server"];
        [prefs setBool:auth.indexOfSelectedItem == 1 forKey:@"saml"];
        [self showRecorder];
    }];
}
- (void)openRecorder:(id)sender {
    if (![[self recorderPreferences] stringForKey:@"server"]) [self configureRecorder:sender];
    else [self showRecorder];
}
- (NSStackView *)recorderPanel:(CGFloat)minimumHeight {
    NSStackView *panel = [self verticalStack:12];
    self.recorderStatus = [self label:@"Myレコーダーを開いています…" size:13 strong:NO muted:YES];
    [panel addArrangedSubview:self.recorderStatus];
    [self.recorderStatus.widthAnchor constraintEqualToAnchor:panel.widthAnchor].active = YES;
    NSButton *reload = [self button:@"再読み込み" selector:@selector(reloadRecorder:)]; reload.toolTip = @"公式の打刻画面を読み込み直します";
    NSButton *settings = [self button:@"接続設定" selector:@selector(configureRecorder:)]; settings.toolTip = @"KING OF TIMEのサーバーとログイン方式を選びます";
    NSButton *browser = [self button:@"ブラウザで開く" selector:@selector(openRecorderInBrowser:)]; browser.toolTip = @"公式Myレコーダーを既定のブラウザで開きます";
    NSStackView *toolbar = [NSStackView stackViewWithViews:@[reload, settings, browser]];
    toolbar.spacing = 12; [panel addArrangedSubview:toolbar];
    // All windows live in the main app, so WebKit shares its persistent session.
    WKWebViewConfiguration *configuration = [[WKWebViewConfiguration alloc] init];
    configuration.websiteDataStore = WKWebsiteDataStore.defaultDataStore;
    [configuration.userContentController addScriptMessageHandler:self name:@"attendanceReminderGuard"];
    self.recorderWebView = [[WKWebView alloc] initWithFrame:NSZeroRect configuration:configuration];
    self.recorderWebView.navigationDelegate = self; self.recorderWebView.UIDelegate = self;
    self.recorderWebView.translatesAutoresizingMaskIntoConstraints = NO;
    [panel addArrangedSubview:self.recorderWebView];
    [self.recorderWebView.widthAnchor constraintEqualToAnchor:panel.widthAnchor].active = YES;
    [self.recorderWebView.heightAnchor constraintGreaterThanOrEqualToConstant:minimumHeight].active = YES;
    [self.recorderWebView setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationVertical];
    [self.recorderWebView setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationVertical];
    [panel setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationVertical];
    return panel;
}
- (void)loadRecorder {
    self.recorderStatus.stringValue = @"公式画面でログインし、出勤・退勤ボタンを押してください。";
    [self installRecorderGuard];
    [self.recorderWebView loadRequest:[NSURLRequest requestWithURL:[self recorderURL]]];
}
- (void)showRecorder {
    if (self.notificationMode) { if (self.notificationRecorderOpen) [self loadRecorder]; return; }
    if (!self.recorderWindow) {
        self.recorderWindow = [[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,600,720) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskMiniaturizable|NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
        self.recorderWindow.title = @"KING OF TIME · Myレコーダー"; self.recorderWindow.releasedWhenClosed = NO;
        self.recorderWindow.contentMinSize = NSMakeSize(520, 540); [self.recorderWindow center];
        NSStackView *stack = [self verticalStack:12]; [self.recorderWindow.contentView addSubview:stack];
        [NSLayoutConstraint activateConstraints:@[
            [stack.leadingAnchor constraintEqualToAnchor:self.recorderWindow.contentView.leadingAnchor constant:16],
            [stack.trailingAnchor constraintEqualToAnchor:self.recorderWindow.contentView.trailingAnchor constant:-16],
            [stack.topAnchor constraintEqualToAnchor:self.recorderWindow.contentView.topAnchor constant:16],
            [stack.bottomAnchor constraintEqualToAnchor:self.recorderWindow.contentView.bottomAnchor constant:-16]
        ]];
        NSStackView *panel = [self recorderPanel:400]; [stack addArrangedSubview:panel];
        [panel.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
    }
    [self.recorderWindow makeKeyAndOrderFront:nil]; [NSApp activateIgnoringOtherApps:YES];
    [self loadRecorder];
}
- (void)reloadRecorder:(id)sender { [self.recorderWebView reload]; }
- (void)openRecorderInBrowser:(id)sender { [[NSWorkspace sharedWorkspace] openURL:[self recorderURL]]; }
- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)action decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    NSString *scheme = action.request.URL.scheme.lowercaseString;
    decisionHandler([scheme isEqualToString:@"https"] || [action.request.URL.absoluteString isEqualToString:@"about:blank"] ? WKNavigationActionPolicyAllow : WKNavigationActionPolicyCancel);
}
- (WKWebView *)webView:(WKWebView *)webView createWebViewWithConfiguration:(WKWebViewConfiguration *)configuration forNavigationAction:(WKNavigationAction *)action windowFeatures:(WKWindowFeatures *)features {
    if (!action.targetFrame && [action.request.URL.scheme.lowercaseString isEqualToString:@"https"]) [webView loadRequest:action.request];
    return nil;
}
- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    if (error.code != NSURLErrorCancelled) self.recorderStatus.stringValue = @"表示できませんでした。接続設定を確認するか、ブラウザで開いてください。";
}
- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    [self webView:webView didFailProvisionalNavigation:navigation withError:error];
}
- (NSAlert *)websiteDialog:(NSString *)message frame:(WKFrameInfo *)frame {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = [NSString stringWithFormat:@"%@ からの確認", frame.request.URL.host ?: @"Myレコーダー"];
    alert.informativeText = message.length > 2000 ? [message substringToIndex:2000] : message;
    return alert;
}
- (void)webView:(WKWebView *)webView runJavaScriptAlertPanelWithMessage:(NSString *)message initiatedByFrame:(WKFrameInfo *)frame completionHandler:(void (^)(void))completionHandler {
    NSAlert *alert = [self websiteDialog:message frame:frame]; [alert addButtonWithTitle:@"OK"];
    [alert beginSheetModalForWindow:webView.window completionHandler:^(NSModalResponse response) { completionHandler(); }];
}
- (void)webView:(WKWebView *)webView runJavaScriptConfirmPanelWithMessage:(NSString *)message initiatedByFrame:(WKFrameInfo *)frame completionHandler:(void (^)(BOOL))completionHandler {
    NSAlert *alert = [self websiteDialog:message frame:frame];
    [alert addButtonWithTitle:@"OK"]; [alert addButtonWithTitle:@"キャンセル"];
    [alert beginSheetModalForWindow:webView.window completionHandler:^(NSModalResponse response) { completionHandler(response == NSAlertFirstButtonReturn); }];
}
- (void)webViewWebContentProcessDidTerminate:(WKWebView *)webView {
    self.recorderStatus.stringValue = @"画面の読み込みが停止しました。「再読み込み」で開き直してください。";
}
- (void)help:(id)sender {
    [self showMessage:@"「通知の予定を設定」で、月〜金の出勤・退勤時刻を入力し、「保存して開始」を押してください。通知しない曜日はチェックを外します。出勤は5分前、退勤は予定時刻に通知します。\n\n通知の「打刻画面を開く」を押すと、KING OF TIMEを表示します。再通知は10分後・30分後・1時間後・2時間後です。設定画面を閉じても通知は続きます。停止はこのアプリから行えます。"];
}
- (NSString *)reminderMessage {
    NSString *message = @"表示テストです。再通知は予約しません。\n「打刻画面を開く」で実際のKING OF TIMEを表示します。";
    if (!self.testMode) {
        NSString *root = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/OutlookAttendanceReminder"];
        NSString *filename = [NSString stringWithFormat:@"calendar-%@.txt", self.kind];
        message = [NSString stringWithContentsOfFile:[root stringByAppendingPathComponent:filename] encoding:NSUTF8StringEncoding error:nil] ?: @"KING OF TIMEで打刻を確認してください。";
        if (self.repeated) {
            message = [message stringByReplacingOccurrencesOfString:@"の5分前です。" withString:@"の打刻リマインダーです。"];
            message = [message stringByReplacingOccurrencesOfString:@"の時刻になりました。" withString:@"の打刻リマインダーです。"];
        }
    }
    return message.length > 2000 ? [message substringToIndex:2000] : message;
}
- (BOOL)remindersEnabled {
    NSString *file = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/OutlookAttendanceReminder/preferences.json"];
    NSData *data = [NSData dataWithContentsOfFile:file];
    id prefs = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    return ![prefs isKindOfClass:NSDictionary.class] || ![prefs[@"enabled"] isEqual:@NO];
}
- (void)checkEnabled:(NSTimer *)timer {
    if (![self remindersEnabled]) [self closeNotification:nil];
}
- (void)presentReminderKind:(NSString *)kind test:(BOOL)test {
    if (!test && ![self remindersEnabled]) return;
    if (!self.notifications) self.notifications = [NSMutableDictionary dictionary];
    NSString *key = test ? @"test" : kind;
    ReminderController *controller = self.notifications[key];
    if (!controller) {
        controller = [[ReminderController alloc] init]; controller.owner = self;
        controller.notificationMode = YES; controller.kind = kind; controller.testMode = test;
        self.notifications[key] = controller;
    }
    [controller.reminderTimer invalidate]; controller.reminderTimer = nil; controller.repeated = NO;
    [controller showNotification];
}
- (void)testReminder:(id)sender { [self presentReminderKind:@"end" test:YES]; }
- (void)updateNotificationRecorderLayout {
    self.notificationRecorderPanel.hidden = !self.notificationRecorderOpen;
    self.notificationRecorderButton.title = self.notificationRecorderOpen ? @"打刻画面を閉じる" : @"打刻画面を開く";
    self.notificationRecorderButton.toolTip = self.notificationRecorderOpen ? @"打刻画面を隠し、小さな通知に戻します" : @"KING OF TIMEを表示します。出勤・退勤は開いた画面で選びます";
    self.notificationFillConstraint.active = self.notificationRecorderOpen;
    if (!self.notificationLayout) return;
    [self.window.contentView layoutSubtreeIfNeeded];
    NSSize size = self.notificationRecorderOpen ? NSMakeSize(640, 800) : NSMakeSize(560, ceil(self.notificationLayout.fittingSize.height + 32));
    self.window.contentMinSize = self.notificationRecorderOpen ? NSMakeSize(580, 620) : NSMakeSize(560, size.height);
    NSRect frame = [self.window frameRectForContentRect:NSMakeRect(0, 0, size.width, size.height)];
    NSRect visible = (self.window.screen ?: NSScreen.mainScreen).visibleFrame;
    frame.origin = NSMakePoint(round(NSMidX(visible) - frame.size.width / 2), round(NSMidY(visible) - frame.size.height / 2));
    frame.origin.x = MAX(NSMinX(visible), MIN(frame.origin.x, NSMaxX(visible) - frame.size.width));
    frame.origin.y = MAX(NSMinY(visible), MIN(frame.origin.y, NSMaxY(visible) - frame.size.height));
    [self.window setFrame:frame display:self.window.visible];
}
- (void)hideNotificationRecorder {
    self.notificationRecorderOpen = NO;
    [self.recorderWebView stopLoading];
    [self updateNotificationRecorderLayout];
}
- (void)toggleNotificationRecorder:(id)sender {
    if (self.notificationRecorderOpen) { [self hideNotificationRecorder]; return; }
    if (!self.testMode && ![self remindersEnabled]) { [self closeNotification:nil]; return; }
    if (!self.notificationRecorderPanel) {
        self.notificationRecorderPanel = [self recorderPanel:320];
        [self.notificationLayout insertArrangedSubview:self.notificationRecorderPanel atIndex:2];
        [self.notificationRecorderPanel.widthAnchor constraintEqualToAnchor:self.notificationLayout.widthAnchor].active = YES;
    }
    self.notificationRecorderOpen = YES; [self updateNotificationRecorderLayout];
    [self openRecorder:nil];
}
- (void)closeNotification:(id)sender {
    [self.reminderTimer invalidate]; self.reminderTimer = nil;
    [self.enabledTimer invalidate]; self.enabledTimer = nil;
    if (self.window.attachedSheet) [self.window endSheet:self.window.attachedSheet returnCode:NSModalResponseCancel];
    self.showingAlert = NO; [self.window orderOut:nil];
    [self hideNotificationRecorder];
}
- (BOOL)windowShouldClose:(NSWindow *)sender {
    if (self.notificationMode) { [self closeNotification:nil]; return NO; }
    return YES;
}
- (void)snoozeNotification:(id)sender {
    if (self.testMode) {
        NSAlert *alert = [[NSAlert alloc] init]; alert.icon = [self clockImage];
        alert.messageText = @"再通知の表示テスト";
        alert.informativeText = [NSString stringWithFormat:@"%@を選択しました。\n実際の再通知は予約しません。", self.snoozeChoice.titleOfSelectedItem];
        [alert addButtonWithTitle:@"閉じる"]; [alert beginSheetModalForWindow:self.window completionHandler:nil]; return;
    }
    NSInteger selected = self.snoozeChoice.indexOfSelectedItem;
    NSArray<NSNumber *> *durations = @[@600, @1800, @3600, @7200];
    [self.reminderTimer invalidate]; self.repeated = YES;
    self.reminderTimer = [NSTimer scheduledTimerWithTimeInterval:durations[(NSUInteger)MAX(0, MIN(selected, 3))].doubleValue target:self selector:@selector(reminderTimerFired:) userInfo:nil repeats:NO];
    self.showingAlert = NO; [self.window orderOut:nil];
    [self hideNotificationRecorder];
}
- (void)showNotification {
    if (!self.testMode && ![self remindersEnabled]) { [self closeNotification:nil]; return; }
    if (!self.window) {
        self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,640,800) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskMiniaturizable|NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
        self.window.title = self.testMode ? @"リマインダー表示テスト" : ([self.kind isEqualToString:@"start"] ? @"出勤リマインダー" : @"退勤リマインダー");
        self.window.releasedWhenClosed = NO; self.window.delegate = self;
        [self.window center];
        ReminderCard *background = [[ReminderCard alloc] init]; background.canvas = YES; self.window.contentView = background;
        NSStackView *stack = [self verticalStack:16]; self.notificationLayout = stack; stack.detachesHiddenViews = YES; [self.window.contentView addSubview:stack];
        [NSLayoutConstraint activateConstraints:@[
            [stack.leadingAnchor constraintEqualToAnchor:self.window.contentView.leadingAnchor constant:16],
            [stack.trailingAnchor constraintEqualToAnchor:self.window.contentView.trailingAnchor constant:-16],
            [stack.topAnchor constraintEqualToAnchor:self.window.contentView.topAnchor constant:16],
            [stack.bottomAnchor constraintLessThanOrEqualToAnchor:self.window.contentView.bottomAnchor constant:-16]
        ]];
        self.notificationFillConstraint = [stack.bottomAnchor constraintEqualToAnchor:self.window.contentView.bottomAnchor constant:-16];
        ReminderClock *clock = [[ReminderClock alloc] init]; clock.translatesAutoresizingMaskIntoConstraints = NO;
        clock.accessibilityLabel = @"笑顔の時計"; clock.accessibilityRole = NSAccessibilityImageRole;
        [NSLayoutConstraint activateConstraints:@[[clock.widthAnchor constraintEqualToConstant:48], [clock.heightAnchor constraintEqualToConstant:48]]];
        NSStackView *text = [self verticalStack:8];
        [text addArrangedSubview:[self label:self.testMode ? @"リマインダー表示テスト" : @"打刻しましょう！" size:18 strong:YES muted:NO]];
        self.reminderLabel = [self label:[self reminderMessage] size:13 strong:NO muted:YES]; [text addArrangedSubview:self.reminderLabel];
        NSStackView *header = [NSStackView stackViewWithViews:@[clock, text]]; header.spacing = 16; header.alignment = NSLayoutAttributeTop;
        [self.reminderLabel.widthAnchor constraintEqualToAnchor:text.widthAnchor].active = YES;
        NSView *card = [self card:header]; [stack addArrangedSubview:card]; [card.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
        self.notificationRecorderButton = [self button:@"打刻画面を開く" selector:@selector(toggleNotificationRecorder:)];
        [stack addArrangedSubview:self.notificationRecorderButton];
        self.snoozeChoice = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO]; self.snoozeChoice.translatesAutoresizingMaskIntoConstraints = NO;
        [self.snoozeChoice addItemsWithTitles:@[@"10分後", @"30分後", @"1時間後", @"2時間後"]];
        self.snoozeChoice.accessibilityLabel = @"再通知までの時間"; self.snoozeChoice.toolTip = @"まだ仕事中なら、次の通知までの時間を選べます";
        self.snoozeChoice.controlSize = NSControlSizeLarge; self.snoozeChoice.font = [NSFont systemFontOfSize:15 weight:NSFontWeightSemibold]; self.snoozeChoice.contentTintColor = ReminderColor(@"primary");
        [self.snoozeChoice.widthAnchor constraintEqualToConstant:152].active = YES;
        NSStackView *snoozeControls = [self verticalStack:5];
        [snoozeControls addArrangedSubview:[self label:@"再通知までの時間" size:12 strong:YES muted:NO]];
        [snoozeControls addArrangedSubview:self.snoozeChoice];
        ReminderCard *snoozeArea = (ReminderCard *)[self card:snoozeControls]; snoozeArea.accent = YES;
        NSButton *snooze = [self button:@"再通知" selector:@selector(snoozeNotification:)]; snooze.toolTip = @"選んだ時間が過ぎたら、もう一度通知します";
        NSButton *close = [self button:@"閉じる" selector:@selector(closeNotification:)]; close.toolTip = @"この通知と、その再通知を終了します";
        NSStackView *footer = [NSStackView stackViewWithViews:@[snoozeArea, snooze, close]];
        footer.spacing = 12; footer.alignment = NSLayoutAttributeCenterY; [stack addArrangedSubview:footer];
    }
    self.reminderLabel.stringValue = [self reminderMessage];
    [self hideNotificationRecorder];
    [self.snoozeChoice selectItemAtIndex:0];
    [self.window makeFirstResponder:self.snoozeChoice];
    self.showingAlert = YES; [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
    if (!self.testMode && !self.enabledTimer) self.enabledTimer = [NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(checkEnabled:) userInfo:nil repeats:YES];
}
- (void)reminderTimerFired:(NSTimer *)timer { self.reminderTimer = nil; [self showNotification]; }
- (void)forwardNotification {
    NSString *bundle = NSBundle.mainBundle.bundlePath;
    for (NSUInteger i = 0; i < 4; i++) bundle = [bundle stringByDeletingLastPathComponent];
    if (![[NSBundle bundleWithPath:bundle].bundleIdentifier isEqualToString:@"com.outlook-attendance-reminder.app"]) { [NSApp terminate:nil]; return; }
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"outlook-attendance-reminder://remind/%@", self.kind]];
    NSWorkspaceOpenConfiguration *configuration = [NSWorkspaceOpenConfiguration configuration]; configuration.arguments = @[@"--reminder"];
    [[NSWorkspace sharedWorkspace] openURLs:@[url] withApplicationAtURL:[NSURL fileURLWithPath:bundle] configuration:configuration completionHandler:^(NSRunningApplication *application, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) {
                NSAlert *alert = [[NSAlert alloc] init]; alert.messageText = @"打刻リマインダーを開けませんでした。";
                alert.informativeText = @"アプリケーションから「打刻リマインダー」を開き直してください。"; [alert runModal];
            }
            [NSApp terminate:nil];
        });
    }];
}
- (void)application:(NSApplication *)application openURLs:(NSArray<NSURL *> *)urls {
    if (self.notificationMode) return;
    for (NSURL *url in urls) {
        if (![url.scheme.lowercaseString isEqualToString:@"outlook-attendance-reminder"] || ![url.host isEqualToString:@"remind"] || url.query.length || url.fragment.length || url.user || url.password || url.port) continue;
        NSString *kind = [url.path isEqualToString:@"/start"] ? @"start" : ([url.path isEqualToString:@"/end"] ? @"end" : nil);
        if (!kind) continue;
        if (!self.window) { if (!self.pendingKinds) self.pendingKinds = [NSMutableArray array]; [self.pendingKinds addObject:kind]; }
        else [self presentReminderKind:kind test:NO];
    }
}
- (BOOL)applicationShouldHandleReopen:(NSApplication *)application hasVisibleWindows:(BOOL)visible {
    if (self.notificationMode) [self forwardNotification];
    else {
        [self.window makeKeyAndOrderFront:nil];
        [self refreshStatus];
        if ([[self recorderPreferences] boolForKey:@"openRequested"]) { [[self recorderPreferences] removeObjectForKey:@"openRequested"]; [self openRecorder:nil]; }
    }
    return YES;
}
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    NSString *identifier = NSBundle.mainBundle.bundleIdentifier;
    self.notificationMode = [identifier hasSuffix:@".start"] || [identifier hasSuffix:@".end"];
    if (self.notificationMode) {
        self.kind = [identifier hasSuffix:@".start"] ? @"start" : @"end";
        [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
        [self performSelector:@selector(forwardNotification) withObject:nil afterDelay:0];
    } else {
        self.launching = [NSProcessInfo.processInfo.arguments containsObject:@"--reminder"] || self.pendingKinds.count > 0;
        [self showManager];
        for (NSString *kind in self.pendingKinds) [self presentReminderKind:kind test:NO];
        self.pendingKinds = nil;
        if ([[self recorderPreferences] boolForKey:@"openRequested"]) { [[self recorderPreferences] removeObjectForKey:@"openRequested"]; [self openRecorder:nil]; }
    }
}
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    if (self.notificationMode) return NO;
    for (ReminderController *notification in self.notifications.allValues) if (notification.reminderTimer || notification.showingAlert) return NO;
    return YES;
}
@end

static ReminderController *reminderController;
int main(void) {
    @autoreleasepool {
        NSApplication *application = [NSApplication sharedApplication];
        [application setActivationPolicy:NSApplicationActivationPolicyRegular];
        NSString *name = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleDisplayName"] ?: @"打刻リマインダー";
        NSMenu *menu = [[NSMenu alloc] initWithTitle:@""];
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:name action:nil keyEquivalent:@""];
        NSMenu *sub = [[NSMenu alloc] initWithTitle:name];
        NSMenuItem *quit = [[NSMenuItem alloc] initWithTitle:[name stringByAppendingString:@"を終了"] action:@selector(terminate:) keyEquivalent:@"q"];
        quit.target = application; [sub addItem:quit]; item.submenu = sub; [menu addItem:item];
        NSMenuItem *editItem = [[NSMenuItem alloc] initWithTitle:@"編集" action:nil keyEquivalent:@""];
        NSMenu *editMenu = [[NSMenu alloc] initWithTitle:@"編集"];
        [editMenu addItem:[[NSMenuItem alloc] initWithTitle:@"切り取り" action:@selector(cut:) keyEquivalent:@"x"]];
        [editMenu addItem:[[NSMenuItem alloc] initWithTitle:@"コピー" action:@selector(copy:) keyEquivalent:@"c"]];
        [editMenu addItem:[[NSMenuItem alloc] initWithTitle:@"ペースト" action:@selector(paste:) keyEquivalent:@"v"]];
        [editMenu addItem:[[NSMenuItem alloc] initWithTitle:@"すべてを選択" action:@selector(selectAll:) keyEquivalent:@"a"]];
        editItem.submenu = editMenu; [menu addItem:editItem]; application.mainMenu = menu;
        reminderController = [[ReminderController alloc] init]; application.delegate = reminderController;
        [application run];
    }
    return 0;
}
