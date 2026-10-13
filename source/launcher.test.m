// Exercise routing and timers without opening windows, loading websites, or
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
static void Check(BOOL passed, NSString *message) {
    if (!passed) { fprintf(stderr, "FAIL: %s\n", message.UTF8String); exit(1); }
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
        puts("PASS: weekly saves preserve boolean selections and valid times");
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
