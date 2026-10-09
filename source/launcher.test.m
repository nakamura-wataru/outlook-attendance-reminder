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
static void Check(BOOL passed, NSString *message) {
    if (!passed) { fprintf(stderr, "FAIL: %s\n", message.UTF8String); exit(1); }
}
int main(void) {
    @autoreleasepool {
        ScheduleSaveProbe *scheduleSave = [[ScheduleSaveProbe alloc] init];
        ScheduleControlProbe *weeklyMode = [[ScheduleControlProbe alloc] init];
        scheduleSave.weeklyModeButton = (NSButton *)weeklyMode;
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
        Check([scheduleSave.submitted isEqual:@{@"mode": @"outlook"}], @"Outlook saves without hidden weekly inputs");
        puts("PASS: Outlook saves do not submit hidden weekday settings");
        weeklyMode.state = NSControlStateValueOn; [scheduleSave saveSchedule:nil];
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
