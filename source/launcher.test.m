// Exercise native windows, routing and timers without loading websites or
// reading/writing the user's calendar configuration.
#define main AttendanceApplicationMain
#include "launcher.m"
#undef main

@interface RoutingProbe : ReminderController
@property NSMutableArray<NSString *> *received;
@end
@implementation RoutingProbe
- (void)presentReminderKind:(NSString *)kind test:(BOOL)test { [self.received addObject:kind]; }
@end
@interface OwnerProbe : ReminderController
@property BOOL allowed;
@end
@implementation OwnerProbe
- (BOOL)remindersEnabled { return self.allowed; }
@end
@interface NotificationProbe : OwnerProbe
@property NSUInteger displays;
@end
@implementation NotificationProbe
- (void)showNotification { self.displays++; }
@end
@interface RecorderIntentProbe : OwnerProbe
@property NSUInteger loads;
@end
@implementation RecorderIntentProbe
- (void)loadRecorder { self.loads++; }
@end
@interface RecorderSurfaceProbe : NSObject
@property BOOL hidden;
@property NSUInteger stops;
@end
@implementation RecorderSurfaceProbe
- (void)stopLoading { self.stops++; }
@end
@interface WindowProbe : NSObject
@property NSUInteger hides;
@end
@implementation WindowProbe
- (void)orderOut:(id)sender { self.hides++; }
- (NSWindow *)attachedSheet { return nil; }
@end
@interface ChoiceProbe : NSObject
@property NSInteger selection;
@end
@implementation ChoiceProbe
- (NSInteger)indexOfSelectedItem { return self.selection; }
@end
@interface ScheduleControlProbe : NSObject
@property NSControlStateValue state;
@property NSDate *dateValue;
@end
@implementation ScheduleControlProbe
@end
@interface ScheduleSaveProbe : ReminderController
@property NSDictionary *submitted;
@end
@implementation ScheduleSaveProbe
- (void)updateScheduleControls:(id)sender {}
- (void)refreshStatus {}
- (void)showMessage:(NSString *)message {}
- (void)runCommand:(NSString *)command input:(NSString *)input completion:(void (^)(BOOL, NSString *))completion {
    NSData *data = [NSData dataWithContentsOfFile:input];
    self.submitted = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    completion(YES, @"saved");
}
@end
@interface ScheduleWindowProbe : ReminderController
@end
@implementation ScheduleWindowProbe
- (void)runCommand:(NSString *)command input:(NSString *)input completion:(void (^)(BOOL, NSString *))completion {
    completion(YES, @"{\"weekdays\":[{\"enabled\":true,\"start\":\"09:45\",\"end\":\"18:45\"},{\"enabled\":true,\"start\":\"09:45\",\"end\":\"18:45\"},{\"enabled\":true,\"start\":\"09:45\",\"end\":\"18:45\"},{\"enabled\":true,\"start\":\"09:45\",\"end\":\"18:45\"},{\"enabled\":true,\"start\":\"09:45\",\"end\":\"18:45\"}]}");
}
@end
@interface OverviewFieldProbe : NSObject
@property NSString *stringValue;
@property NSString *title;
@property (getter=isHidden) BOOL hidden;
@end
@implementation OverviewFieldProbe
@end
@interface OverviewProbe : ReminderController
@end
@implementation OverviewProbe
- (void)updateManagerLayout {}
@end
@interface CommandOutputProbe : ReminderController
@property NSString *fixtureResources;
@end
@implementation CommandOutputProbe
- (NSString *)resources { return self.fixtureResources; }
@end
@interface PomodoroProbe : ReminderController
@property NSUInteger announcements;
@end
@implementation PomodoroProbe
- (NSInteger)pomodoroFocusMinutes { return 25; }
- (NSInteger)pomodoroBreakMinutes { return 5; }
- (void)showPomodoroTransition { self.announcements++; }
- (void)updateManagerLayout {}
@end
@interface ManagerWindowProbe : ScheduleWindowProbe
@end
@implementation ManagerWindowProbe
- (void)runCommand:(NSString *)command input:(NSString *)input completion:(void (^)(BOOL, NSString *))completion {
    if ([command isEqualToString:@"ensure"]) completion(YES, @"");
    else [super runCommand:command input:input completion:completion];
}
- (void)runCommand:(NSString *)command input:(NSString *)input blocking:(BOOL)blocking completion:(void (^)(BOOL, NSString *))completion {
    completion(YES, @"{\"configured\":true,\"enabled\":true,\"nextReminder\":null}");
}
- (void)showPomodoroTransition {}
@end
static NSButton *ButtonForAction(NSView *view, SEL action) {
    if ([view isKindOfClass:NSButton.class] && ((NSButton *)view).action == action) return (NSButton *)view;
    for (NSView *child in view.subviews) { NSButton *button = ButtonForAction(child, action); if (button) return button; }
    return nil;
}
static NSView *ViewWithIdentifier(NSView *view, NSString *identifier) {
    if ([view.identifier isEqual:identifier]) return view;
    for (NSView *child in view.subviews) { NSView *match = ViewWithIdentifier(child, identifier); if (match) return match; }
    return nil;
}
static void Check(BOOL passed, NSString *message) {
    if (!passed) { fprintf(stderr, "FAIL: %s\n", message.UTF8String); exit(1); }
}
static void CheckSummaryAlignment(ReminderController *manager) {
    [manager.window.contentView layoutSubtreeIfNeeded];
    CGFloat textStart = -1, iconStart = -1;
    for (NSView *card in manager.managerLayout.arrangedSubviews) {
        if (![card.identifier isEqual:@"summaryCard"]) continue;
        NSView *icon = ViewWithIdentifier(card, @"summaryIcon");
        NSStackView *text = (NSStackView *)ViewWithIdentifier(card, @"summaryText");
        NSRect iconFrame = [icon convertRect:icon.bounds toView:manager.window.contentView];
        NSRect textFrame = [text convertRect:text.bounds toView:manager.window.contentView];
        NSRect cardFrame = [card convertRect:card.bounds toView:manager.window.contentView];
        Check(NSEqualSizes(iconFrame.size, NSMakeSize(56, 56)), @"Every summary card renders a 56 point icon");
        if (textStart < 0) { textStart = NSMinX(textFrame); iconStart = NSMinX(iconFrame); }
        Check(fabs(NSMinX(textFrame) - textStart) < .5 && fabs(NSMinX(iconFrame) - iconStart) < .5, @"Summary icons and text share the same columns");
        Check(fabs(NSMinX(textFrame) - NSMaxX(iconFrame) - 12) < .5, @"Summary text keeps the shared icon gap");
        Check(NSContainsRect(cardFrame, iconFrame) && NSContainsRect(cardFrame, textFrame), @"Summary content stays within its card even when text wraps");
        for (NSView *label in text.arrangedSubviews) if (!label.hidden) {
            NSRect frame = [label.superview convertRect:[label alignmentRectForFrame:label.frame] toView:manager.window.contentView];
            Check(fabs(NSMinX(frame) - textStart) < .5 && NSWidth(frame) <= NSWidth(textFrame) + .5, @"All lines use the same text column");
        }
    }
}
int main(void) {
    @autoreleasepool {
        OverviewProbe *overview = [[OverviewProbe alloc] init];
        NSString *fixtureRoot = [NSTemporaryDirectory() stringByAppendingPathComponent:[@"attendance-native-test-" stringByAppendingString:NSUUID.UUID.UUIDString]];
        [NSFileManager.defaultManager createDirectoryAtPath:fixtureRoot withIntermediateDirectories:YES attributes:nil error:nil];
        CommandOutputProbe *command = [[CommandOutputProbe alloc] init]; command.fixtureResources = fixtureRoot;
        NSString *runner = [command.fixtureResources stringByAppendingPathComponent:@"launch-manager.sh"];
        [@"printf '[manager] warning\\n' >&2\nprintf '{\"configured\":true}\\n'\n" writeToFile:runner atomically:YES encoding:NSUTF8StringEncoding error:nil];
        __block BOOL commandFinished = NO, commandOK = NO; __block NSString *commandMessage;
        [command runCommand:@"overview" input:nil blocking:NO completion:^(BOOL ok, NSString *message) { commandFinished = YES; commandOK = ok; commandMessage = message; }];
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:10];
        while (!commandFinished && deadline.timeIntervalSinceNow > 0) [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
        Check(commandOK && [commandMessage isEqual:@"{\"configured\":true}"], @"Manager warnings do not corrupt structured command output");
        [@"printf 'not a result\\n'\nprintf 'settings failed\\n' >&2\nexit 1\n" writeToFile:runner atomically:YES encoding:NSUTF8StringEncoding error:nil];
        commandFinished = NO;
        [command runCommand:@"configure" input:nil blocking:NO completion:^(BOOL ok, NSString *message) { commandFinished = YES; commandOK = ok; commandMessage = message; }];
        deadline = [NSDate dateWithTimeIntervalSinceNow:10];
        while (!commandFinished && deadline.timeIntervalSinceNow > 0) [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
        Check(commandFinished && !commandOK && [commandMessage isEqual:@"settings failed"], @"Failed operations still display their error message");
        puts("PASS: manager warnings remain separate from structured command results");
        [NSFileManager.defaultManager removeItemAtPath:fixtureRoot error:nil];
        overview.statusBadge = (NSTextField *)[[OverviewFieldProbe alloc] init]; overview.statusLabel = (NSTextField *)[[OverviewFieldProbe alloc] init];
        overview.nextReminderTitle = (NSTextField *)[[OverviewFieldProbe alloc] init]; overview.nextReminderDate = (NSTextField *)[[OverviewFieldProbe alloc] init]; overview.nextReminderDetail = (NSTextField *)[[OverviewFieldProbe alloc] init];
        overview.toggleButton = (NSButton *)[[OverviewFieldProbe alloc] init];
        NSMutableDictionary *view = [@{@"configured": @YES, @"enabled": @YES, @"nextReminder": @{@"kind": @"start", @"plannedAt": @"2026-10-09T00:45:00.000Z", @"dueAt": @"2026-10-09T00:40:00.000Z"}} mutableCopy];
        [overview applyOverview:view];
        Check([overview.statusBadge.stringValue isEqual:@"● 週間予定を設定済み"] && [overview.nextReminderDate.stringValue isEqual:@"10月9日（金）9:40"] && [overview.nextReminderDetail.stringValue containsString:@"9:45 の5分前"], @"Connected preview uses Japan time and the actual reminder time");
        view[@"configured"] = @NO; view[@"nextReminder"] = NSNull.null; [overview applyOverview:view];
        Check(overview.nextReminderDate.hidden && [overview.nextReminderTitle.stringValue containsString:@"設定後"], @"Unconfigured schedules hide the previous reminder time");
        view[@"configured"] = @YES; view[@"enabled"] = @NO; [overview applyOverview:view];
        Check([overview.nextReminderTitle.stringValue isEqual:@"お知らせはお休み中です"] && [overview.toggleButton.title isEqual:@"通知を再開"], @"Stopped notifications do not advertise a scheduled reminder");
        puts("PASS: overview distinguishes configured, unconfigured, and stopped states");
        PomodoroProbe *pomodoro = [[PomodoroProbe alloc] init];
        pomodoro.pomodoroModeLabel = [NSTextField labelWithString:@""]; pomodoro.pomodoroTimerLabel = [NSTextField labelWithString:@""];
        pomodoro.pomodoroDetailLabel = [NSTextField labelWithString:@""]; pomodoro.pomodoroIllustration = [[PomodoroIllustration alloc] init];
        pomodoro.pomodoroPrimaryButton = [NSButton new]; pomodoro.pomodoroStopButton = [NSButton new];
        [pomodoro startPomodoro:nil];
        Check(pomodoro.pomodoroRunning && !pomodoro.pomodoroResting && pomodoro.pomodoroRemainingSeconds == 1500 && pomodoro.announcements == 1, @"Pomodoro starts in a 25 minute focus mode");
        [pomodoro pauseOrResumePomodoro:nil];
        Check(pomodoro.pomodoroPaused && [pomodoro.pomodoroPrimaryButton.title isEqual:@"再開"] && !pomodoro.pomodoroTimer.valid, @"The same action changes from pause to resume");
        [pomodoro pauseOrResumePomodoro:nil]; pomodoro.pomodoroRemainingSeconds = 1; [pomodoro pomodoroTick:nil];
        Check(!pomodoro.pomodoroPaused && pomodoro.pomodoroResting && pomodoro.pomodoroRemainingSeconds == 300 && pomodoro.announcements == 2, @"Focus automatically changes to a five minute break");
        NSApplication *pomodoroApplication = [NSApplication sharedApplication];
        Check(![pomodoro applicationShouldTerminateAfterLastWindowClosed:pomodoroApplication], @"An active Pomodoro survives closing the window");
        [pomodoro stopPomodoro:nil];
        Check(!pomodoro.pomodoroRunning && [pomodoro.pomodoroPrimaryButton.title isEqual:@"開始"] && pomodoro.pomodoroRemainingSeconds == 1500, @"Stopping returns the timer to its focus duration");
        puts("PASS: Pomodoro repeats focus and short breaks until stopped");
        ScheduleSaveProbe *scheduleSave = [[ScheduleSaveProbe alloc] init];
        NSMutableArray *days = [NSMutableArray array], *starts = [NSMutableArray array], *ends = [NSMutableArray array];
        for (NSUInteger index = 0; index < 5; index++) {
            ScheduleControlProbe *day = [[ScheduleControlProbe alloc] init]; day.state = index == 2 ? NSControlStateValueOff : NSControlStateValueOn;
            ScheduleControlProbe *start = [[ScheduleControlProbe alloc] init], *end = [[ScheduleControlProbe alloc] init];
            start.dateValue = [[scheduleSave scheduleTimeFormatter:YES] dateFromString:@"2001-01-01 09:45"];
            end.dateValue = [[scheduleSave scheduleTimeFormatter:YES] dateFromString:@"2001-01-01 18:45"];
            [days addObject:day]; [starts addObject:start]; [ends addObject:end];
        }
        scheduleSave.weekdayButtons = days; scheduleSave.startPickers = starts; scheduleSave.endPickers = ends;
        [scheduleSave saveSchedule:nil];
        Check([scheduleSave.submitted[@"mode"] isEqual:@"weekly"], @"Weekly saves include the selected source");
        NSArray *submittedDays = scheduleSave.submitted[@"weekdays"];
        Check(submittedDays.count == 5, @"Weekly saves include five weekdays");
        for (NSUInteger index = 0; index < 5; index++) {
            NSDictionary *day = submittedDays[index];
            Check(CFGetTypeID((__bridge CFTypeRef)day[@"enabled"]) == CFBooleanGetTypeID(), @"Weekday selections serialize as JSON booleans");
            Check([day[@"enabled"] boolValue] == (index != 2), @"Checked and unchecked weekday selections are preserved");
            Check([day[@"start"] isEqual:@"09:45"] && [day[@"end"] isEqual:@"18:45"], @"Weekly times use the validated HH:mm format");
        }
        ScheduleControlProbe *commonStart = [[ScheduleControlProbe alloc] init], *commonEnd = [[ScheduleControlProbe alloc] init];
        commonStart.dateValue = [[scheduleSave scheduleTimeFormatter:YES] dateFromString:@"2001-01-01 10:00"];
        commonEnd.dateValue = [[scheduleSave scheduleTimeFormatter:YES] dateFromString:@"2001-01-01 19:00"];
        scheduleSave.commonStartPicker = (NSDatePicker *)commonStart; scheduleSave.commonEndPicker = (NSDatePicker *)commonEnd;
        [scheduleSave applyCommonSchedule:nil];
        for (NSUInteger index = 0; index < 5; index++) Check(scheduleSave.weekdayButtons[index].state == NSControlStateValueOn && [scheduleSave.startPickers[index].dateValue isEqual:commonStart.dateValue] && [scheduleSave.endPickers[index].dateValue isEqual:commonEnd.dateValue], @"Common times apply to every weekday and enable notifications");
        puts("PASS: weekly saves preserve boolean selections and valid times");
        [NSApplication sharedApplication];
        ScheduleWindowProbe *scheduleWindow = [[ScheduleWindowProbe alloc] init];
        [scheduleWindow configureSchedule:nil];
        Check(scheduleWindow.scheduleWindow.visible && scheduleWindow.commonStartPicker && scheduleWindow.commonEndPicker && scheduleWindow.applyCommonScheduleButton, @"Schedule button opens a configured settings window");
        [scheduleWindow.scheduleWindow orderOut:nil];
        puts("PASS: schedule settings open from the main action");
        ManagerWindowProbe *manager = [[ManagerWindowProbe alloc] init]; [manager showManager];
        Check([manager.window.title isEqual:@"ときとも"], @"The main window uses the new app name");
        Check([manager.pomodoroTitleLabel.stringValue isEqual:@"ポモドーロ"] && manager.pomodoroModeLabel.hidden, @"The idle card identifies the Pomodoro feature without claiming a running mode");
        NSTitlebarAccessoryViewController *accessory = manager.window.titlebarAccessoryViewControllers.firstObject;
        NSButton *gear = ButtonForAction(accessory.view, @selector(openSettings:));
        Check(accessory.layoutAttribute == NSLayoutAttributeRight && ![gear isDescendantOf:manager.window.contentView], @"Settings lives at the trailing end of the native title bar");
        Check(gear && ButtonForAction(manager.window.contentView, @selector(help:)) && ButtonForAction(manager.window.contentView, @selector(openRecorder:)), @"Main keeps settings, help and the recorder accessible");
        CheckSummaryAlignment(manager);
        [manager applyOverview:@{@"configured": @YES, @"enabled": @YES, @"nextReminder": @{@"kind": @"end", @"dueAt": @"2026-10-27T09:45:00Z", @"plannedAt": @"2026-10-27T09:45:00Z"}}];
        CheckSummaryAlignment(manager);
        NSStackView *futureText = [manager verticalStack:4];
        [futureText addArrangedSubview:[manager label:@"長いお知らせの文章が複数行に折り返されても、アイコンと文字の開始位置は変わりません。" size:15 strong:YES muted:NO]];
        NSView *futureCard = [manager summaryCardWithIcon:[[ReminderClock alloc] init] content:futureText actions:nil];
        [manager.managerLayout addArrangedSubview:futureCard]; [futureCard.widthAnchor constraintEqualToAnchor:manager.managerLayout.widthAnchor].active = YES;
        [manager updateManagerLayout]; CheckSummaryAlignment(manager);
        [manager.managerLayout removeArrangedSubview:futureCard]; [futureCard removeFromSuperview]; [manager updateManagerLayout];
        for (NSString *action in @[@"configureSchedule:", @"configurePomodoro:", @"testReminder:", @"toggle:"]) Check(!ButtonForAction(manager.window.contentView, NSSelectorFromString(action)), @"Secondary actions no longer appear on main");
        Check(manager.pomodoroStopButton.hidden, @"An idle Pomodoro does not display an end action");
        [gear performClick:nil]; NSWindow *settings = manager.settingsWindow;
        Check(settings.visible, @"The gear opens settings");
        for (NSString *action in @[@"configureSchedule:", @"configurePomodoro:", @"testReminder:", @"toggle:"]) Check(ButtonForAction(settings.contentView, NSSelectorFromString(action)) != nil, @"Settings keeps every relocated action accessible");
        Check([manager.toggleButton.title isEqual:@"通知を停止"], @"Opening settings uses the current reminder state");
        [ButtonForAction(settings.contentView, @selector(configureSchedule:)) performClick:nil];
        Check(manager.scheduleWindow.visible && manager.startPickers.count == 5, @"The schedule editor opens from settings with all weekdays");
        [manager.scheduleWindow orderOut:nil];
        [ButtonForAction(settings.contentView, @selector(configurePomodoro:)) performClick:nil];
        Check(settings.attachedSheet != nil && manager.window.attachedSheet == nil, @"Pomodoro editing attaches to the settings window");
        [settings endSheet:settings.attachedSheet returnCode:NSAlertSecondButtonReturn];
        [settings orderOut:nil]; [gear performClick:nil]; Check(manager.settingsWindow == settings, @"Reopening settings reuses the same window");
        [manager startPomodoro:nil]; [manager.window.contentView layoutSubtreeIfNeeded];
        NSRect actionBefore = [manager.pomodoroPrimaryButton convertRect:manager.pomodoroPrimaryButton.bounds toView:manager.window.contentView];
        [manager pauseOrResumePomodoro:nil]; [manager.window.contentView layoutSubtreeIfNeeded];
        NSRect actionAfter = [manager.pomodoroPrimaryButton convertRect:manager.pomodoroPrimaryButton.bounds toView:manager.window.contentView];
        Check(NSEqualRects(actionBefore, actionAfter) && [manager.pomodoroPrimaryButton.title isEqual:@"再開"] && !manager.pomodoroStopButton.hidden, @"Pause and resume stay in place while end remains available");
        CheckSummaryAlignment(manager);
        Check([manager.pomodoroTitleLabel.stringValue isEqual:@"ポモドーロ"] && [manager.pomodoroModeLabel.stringValue isEqual:@"集中モード・一時停止中"], @"Pausing changes the status without changing the card title");
        manager.pomodoroResting = YES; [manager updatePomodoroUI]; CheckSummaryAlignment(manager);
        Check([manager.pomodoroTitleLabel.stringValue isEqual:@"ポモドーロ"] && [manager.pomodoroModeLabel.stringValue isEqual:@"休憩モード・一時停止中"], @"The break uses the same title and a separate paused status");
        manager.pomodoroPaused = NO; [manager updatePomodoroUI];
        Check([manager.pomodoroModeLabel.stringValue isEqual:@"休憩モード"], @"A running break is shown beside the timer");
        manager.pomodoroRemainingSeconds = 7200; manager.pomodoroPaused = YES; [manager updatePomodoroUI];
        CheckSummaryAlignment(manager);
        NSRect numberFrame = manager.pomodoroTimerLabel.frame, modeFrame = manager.pomodoroModeLabel.frame;
        Check(NSMaxX(numberFrame) <= NSMinX(modeFrame) && NSMaxX(modeFrame) <= NSWidth(manager.pomodoroModeLabel.superview.bounds), @"A three-digit timer and the longest status fit without overlapping");
        [manager stopPomodoro:nil]; Check(manager.pomodoroStopButton.hidden, @"Ending the timer hides end again");
        Check(manager.pomodoroModeLabel.hidden && [manager.pomodoroTitleLabel.stringValue isEqual:@"ポモドーロ"], @"Ending hides the running status and keeps the feature title");
        [manager.overviewTimer invalidate]; [manager.window orderOut:nil]; [manager.settingsWindow orderOut:nil];
        puts("PASS: compact main screen routes settings without losing timer controls");
        WindowProbe *window = [[WindowProbe alloc] init];
        RecorderIntentProbe *intent = [[RecorderIntentProbe alloc] init]; intent.notificationMode = YES; intent.allowed = YES;
        [intent showRecorder]; Check(intent.loads == 0, @"A closed notification cannot load the recorder");
        intent.notificationRecorderOpen = YES; [intent showRecorder]; Check(intent.loads == 1, @"The recorder loads only after being opened");
        puts("PASS: notification recorder requires an explicit open action");
        RecorderSurfaceProbe *surface = [[RecorderSurfaceProbe alloc] init], *web = [[RecorderSurfaceProbe alloc] init];
        intent.notificationRecorderPanel = (NSStackView *)surface; intent.recorderWebView = (WKWebView *)web; intent.window = (NSWindow *)window;
        [intent snoozeNotification:nil];
        Check(!intent.notificationRecorderOpen && surface.hidden && web.stops == 1 && intent.reminderTimer.valid, @"Snoozing hides the recorder and preserves the reminder timer");
        intent.notificationRecorderOpen = YES; surface.hidden = NO;
        NSTimer *intentTimer = intent.reminderTimer; [intent closeNotification:nil];
        Check(!intent.notificationRecorderOpen && surface.hidden && web.stops == 2 && !intentTimer.valid, @"Closing resets the recorder and cancels the pending reminder");
        puts("PASS: snooze and close reset the notification recorder");
        ReminderController *punch = [[ReminderController alloc] init];
        punch.notificationMode = YES; punch.kind = @"start";
        Check([[punch blockedPunchLabel] isEqual:@"退勤"], @"Arrival reminders hide the departure button");
        punch.kind = @"end";
        Check([[punch blockedPunchLabel] isEqual:@"出勤"], @"Departure reminders hide the arrival button");
        [punch showBothPunches:nil];
        Check(punch.recorderShowsBothPunches && punch.blockedPunchLabel == nil, @"Showing both punches clears the hidden button");
        punch.notificationMode = NO; punch.recorderShowsBothPunches = NO; punch.kind = @"start";
        Check(punch.blockedPunchLabel == nil, @"The main recorder keeps both punch buttons");
        intent.notificationMode = YES; intent.kind = @"end"; intent.recorderShowsBothPunches = YES; intent.notificationRecorderOpen = YES; surface.hidden = NO;
        [intent hideNotificationRecorder];
        Check(!intent.recorderShowsBothPunches && [[intent blockedPunchLabel] isEqual:@"出勤"] && surface.hidden && web.stops == 3, @"Closing the recorder hides the opposite button again");
        puts("PASS: reminder kind chooses the hidden punch button");
        window.hides = 0;
        NSApplication *application = (NSApplication *)[[NSObject alloc] init];
        RoutingProbe *routing = [[RoutingProbe alloc] init]; routing.received = [NSMutableArray array]; routing.window = (NSWindow *)window;
        [routing application:application openURLs:@[
            [NSURL URLWithString:@"outlook-attendance-reminder://remind/start"],
            [NSURL URLWithString:@"outlook-attendance-reminder://remind/end"],
            [NSURL URLWithString:@"https://remind/end"],
            [NSURL URLWithString:@"outlook-attendance-reminder://other/end"],
            [NSURL URLWithString:@"outlook-attendance-reminder://remind/unknown"],
            [NSURL URLWithString:@"outlook-attendance-reminder://remind/end?url=https://example.com"],
            [NSURL URLWithString:@"outlook-attendance-reminder://remind/end#fragment"],
            [NSURL URLWithString:@"outlook-attendance-reminder://user@remind/end"],
            [NSURL URLWithString:@"outlook-attendance-reminder://remind:42/end"]]];
        Check([routing.received isEqual:@[@"start", @"end"]], @"Only known local reminder actions are accepted");
        puts("PASS: reminder URL validation");
        routing.window = nil;
        [routing application:application openURLs:@[[NSURL URLWithString:@"outlook-attendance-reminder://remind/start"], [NSURL URLWithString:@"outlook-attendance-reminder://remind/end"]]];
        Check([routing.pendingKinds isEqual:@[@"start", @"end"]], @"Startup preserves both notification kinds");
        puts("PASS: notifications received before application startup");

        OwnerProbe *owner = [[OwnerProbe alloc] init]; owner.allowed = YES;
        NotificationProbe *start = [[NotificationProbe alloc] init]; start.allowed = YES;
        NotificationProbe *end = [[NotificationProbe alloc] init]; end.allowed = YES; end.window = (NSWindow *)window;
        ChoiceProbe *choice = [[ChoiceProbe alloc] init]; end.snoozeChoice = (NSPopUpButton *)choice;
        owner.notifications = [@{@"start":start, @"end":end} mutableCopy];
        NSArray<NSNumber *> *seconds = @[@600, @1800, @3600, @7200];
        for (NSUInteger index = 0; index < seconds.count; index++) {
            choice.selection = (NSInteger)index; [end snoozeNotification:nil];
            Check(fabs(end.reminderTimer.fireDate.timeIntervalSinceNow - seconds[index].doubleValue) < 2 && end.repeated && !end.showingAlert, @"Snooze duration and hidden window");
            [end.reminderTimer invalidate]; end.reminderTimer = nil;
        }
        Check(window.hides == 4, @"Each snooze hides the notification");
        puts("PASS: 10 minutes, 30 minutes, 1 hour, 2 hours snooze");
        [start snoozeNotification:nil]; // A nil selector has the default index, 10 minutes.
        [end snoozeNotification:nil];
        NSTimer *startTimer = start.reminderTimer, *endTimer = end.reminderTimer;
        end.repeated = YES; [owner presentReminderKind:@"end" test:NO];
        Check(!endTimer.valid && !end.reminderTimer && !end.repeated && end.displays == 1, @"A new departure notification replaces its old snooze");
        Check(startTimer.valid && start.reminderTimer == startTimer, @"Arrival and departure snoozes stay independent");
        Check(![owner applicationShouldTerminateAfterLastWindowClosed:application], @"Closing settings must preserve a pending snooze");
        puts("PASS: independent arrival/departure notifications and new-event reset");
        owner.allowed = NO; [owner presentReminderKind:@"end" test:NO];
        Check(end.displays == 1, @"A disabled reminder must not appear");
        end.allowed = NO; [end snoozeNotification:nil];
        NSTimer *disabledTimer = end.reminderTimer;
        end.enabledTimer = [NSTimer scheduledTimerWithTimeInterval:1 target:end selector:@selector(checkEnabled:) userInfo:nil repeats:YES];
        NSTimer *enabledTimer = end.enabledTimer; [end checkEnabled:nil];
        Check(!disabledTimer.valid && !enabledTimer.valid && !end.reminderTimer && !end.enabledTimer, @"Disabling cancels both timers");
        [start closeNotification:nil];
        Check([owner applicationShouldTerminateAfterLastWindowClosed:application], @"With no active reminders closing settings may exit");
        puts("PASS: disabled reminders cancel pending timers");
        NotificationProbe *displayTest = [[NotificationProbe alloc] init]; displayTest.testMode = YES;
        owner.notifications[@"test"] = displayTest;
        [owner presentReminderKind:@"end" test:YES];
        Check(displayTest.displays == 1 && !displayTest.reminderTimer && end.displays == 1, @"Display tests are distinct from real reminders and work while disabled");
        [owner.notifications[@"test"] closeNotification:nil];
        puts("PASS: display tests are separated from real reminders");
    }
    return 0;
}
