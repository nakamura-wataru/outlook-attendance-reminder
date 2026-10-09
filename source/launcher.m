#import <Cocoa/Cocoa.h>
#include <fcntl.h>
#include <unistd.h>

@interface ReminderController : NSObject <NSApplicationDelegate>
@property NSWindow *window;
@property NSTextField *statusLabel;
@property NSButton *toggleButton;
@property NSButton *migrationButton;
@property NSMutableArray<NSButton *> *buttons;
@property BOOL notificationMode;
@property NSString *kind;
@property NSTimer *reminderTimer;
@property BOOL repeated;
@property BOOL showingAlert;
@end

@implementation ReminderController
- (NSString *)resources { return [NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"Contents/Resources"]; }
- (void)setBusy:(BOOL)busy { for (NSButton *button in self.buttons) button.enabled = !busy; }
- (void)runCommand:(NSString *)command input:(NSString *)input completion:(void (^)(BOOL, NSString *))completion {
    [self setBusy:YES];
    NSString *runner = [[self resources] stringByAppendingPathComponent:@"launch-manager.sh"];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        @autoreleasepool {
            NSTask *task = [[NSTask alloc] init];
            task.executableURL = [NSURL fileURLWithPath:@"/bin/bash"];
            task.arguments = input ? @[runner, command, input] : @[runner, command];
            NSPipe *pipe = [NSPipe pipe]; task.standardOutput = pipe; task.standardError = pipe;
            NSError *error = nil;
            BOOL launched = [task launchAndReturnError:&error];
            NSData *data = launched ? [pipe.fileHandleForReading readDataToEndOfFile] : nil;
            if (launched) [task waitUntilExit];
            NSString *message = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"アプリの操作を実行できませんでした。";
            message = [message stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            BOOL ok = launched && task.terminationStatus == 0;
            dispatch_async(dispatch_get_main_queue(), ^{ [self setBusy:NO]; completion(ok, message ?: @"もう一度お試しください。"); });
        }
    });
}
- (void)showMessage:(NSString *)message {
    NSAlert *alert = [[NSAlert alloc] init]; alert.messageText = @"打刻リマインダー";
    alert.informativeText = message; [alert addButtonWithTitle:@"閉じる"];
    [alert beginSheetModalForWindow:self.window completionHandler:nil];
}
- (void)refreshStatus {
    [self runCommand:@"status" input:nil completion:^(BOOL ok, NSString *text) {
        self.statusLabel.stringValue = text;
        if (!ok) return;
        [self runCommand:@"enabled" input:nil completion:^(BOOL enabledOK, NSString *value) {
            self.toggleButton.title = enabledOK && [value isEqualToString:@"yes"] ? @"通知を停止" : @"通知を再開";
            [self runCommand:@"can-migrate" input:nil completion:^(BOOL migrationOK, NSString *canMigrate) {
                self.migrationButton.hidden = !(migrationOK && [canMigrate isEqualToString:@"yes"]);
            }];
        }];
    }];
}
- (NSButton *)button:(NSString *)title selector:(SEL)selector {
    NSButton *button = [NSButton buttonWithTitle:title target:self action:selector];
    button.bezelStyle = NSBezelStyleRounded; button.translatesAutoresizingMaskIntoConstraints = NO;
    [self.buttons addObject:button]; return button;
}
- (void)showManager {
    self.buttons = [NSMutableArray array];
    self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,460,350) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskMiniaturizable backing:NSBackingStoreBuffered defer:NO];
    self.window.title = @"打刻リマインダー"; [self.window center];
    NSStackView *stack = [[NSStackView alloc] init]; stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading; stack.spacing = 12; stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.window.contentView addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:self.window.contentView.leadingAnchor constant:20],
        [stack.trailingAnchor constraintEqualToAnchor:self.window.contentView.trailingAnchor constant:-20],
        [stack.topAnchor constraintEqualToAnchor:self.window.contentView.topAnchor constant:20]
    ]];
    NSTextField *title = [NSTextField labelWithString:@"出社・退社の打刻を忘れないために"];
    title.font = [NSFont systemFontOfSize:18 weight:NSFontWeightSemibold]; [stack addArrangedSubview:title];
    self.statusLabel = [NSTextField wrappingLabelWithString:@"設定を確認しています…"];
    self.statusLabel.font = [NSFont systemFontOfSize:13]; [stack addArrangedSubview:self.statusLabel];
    [stack addArrangedSubview:[self button:@"予定表を設定・変更" selector:@selector(configure:)]];
    [stack addArrangedSubview:[self button:@"表示をテスト" selector:@selector(testReminder:)]];
    self.toggleButton = [self button:@"通知を再開" selector:@selector(toggle:)]; [stack addArrangedSubview:self.toggleButton];
    self.migrationButton = [self button:@"既存の設定を引き継ぐ" selector:@selector(migrate:)]; self.migrationButton.hidden = YES; [stack addArrangedSubview:self.migrationButton];
    [stack addArrangedSubview:[self button:@"使い方" selector:@selector(help:)]];
    [self.window makeKeyAndOrderFront:nil]; [NSApp activateIgnoringOtherApps:YES];
    [self runCommand:@"ensure" input:nil completion:^(BOOL ok, NSString *message) { [self refreshStatus]; }];
}
- (void)configure:(id)sender {
    NSAlert *alert = [[NSAlert alloc] init]; alert.messageText = @"予定表の設定";
    alert.informativeText = @"自分のOutlook予定表のICSリンクを入力してください。リンクは自分のMacにだけ保存します。";
    NSSecureTextField *field = [[NSSecureTextField alloc] initWithFrame:NSMakeRect(0,0,360,26)];
    field.placeholderString = @"https://…"; alert.accessoryView = field;
    [alert addButtonWithTitle:@"設定"]; [alert addButtonWithTitle:@"キャンセル"];
    [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
        if (response != NSAlertFirstButtonReturn) return;
        NSString *temporary = [NSTemporaryDirectory() stringByAppendingPathComponent:[@"attendance-calendar-" stringByAppendingString:NSUUID.UUID.UUIDString]];
        int descriptor = open(temporary.fileSystemRepresentation, O_WRONLY|O_CREAT|O_EXCL, 0600);
        if (descriptor < 0) { [self showMessage:@"設定を保存する準備ができませんでした。"]; return; }
        NSData *data = [field.stringValue dataUsingEncoding:NSUTF8StringEncoding];
        const uint8_t *bytes = data.bytes; NSUInteger written = 0;
        while (written < data.length) { ssize_t count = write(descriptor, bytes + written, data.length - written); if (count <= 0) break; written += (NSUInteger)count; }
        close(descriptor);
        if (written != data.length) { unlink(temporary.fileSystemRepresentation); [self showMessage:@"リンクを保存できませんでした。"]; return; }
        self.statusLabel.stringValue = @"予定表への接続を確認しています…";
        [self runCommand:@"configure" input:temporary completion:^(BOOL ok, NSString *message) {
            unlink(temporary.fileSystemRepresentation); [self showMessage:message]; [self refreshStatus];
        }];
    }];
}
- (void)toggle:(id)sender {
    NSString *command = [self.toggleButton.title isEqualToString:@"通知を停止"] ? @"stop" : @"start";
    [self runCommand:command input:nil completion:^(BOOL ok, NSString *message) { [self showMessage:message]; [self refreshStatus]; }];
}
- (void)migrate:(id)sender {
    [self runCommand:@"migrate" input:nil completion:^(BOOL ok, NSString *message) { [self showMessage:message]; [self refreshStatus]; }];
}
- (void)help:(id)sender {
    [self showMessage:@"OutlookのWeb版で、設定 → 予定表 → 共有の予定表 → 予定表の公開を開き、タイトルが見えるICSリンクを取得してください。\n\n「予定表を設定・変更」へ自分のリンクを入力すると、出社・出勤は予定の5分前、退社・退勤は予定時刻に通知します。再通知は10分後・30分後・1時間後・2時間後です。\n\nこの画面を閉じても通知は続きます。停止はこのアプリから行えます。"];
}
- (NSAlert *)reminderAlert:(BOOL)test {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = test ? @"リマインダー表示テスト" : @"打刻しましょう！";
    NSString *message = @"表示テストです。実際の出社・退社予定の通知ではありません。";
    if (!test) {
        NSString *root = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/OutlookAttendanceReminder"];
        NSString *filename = [NSString stringWithFormat:@"calendar-%@.txt", self.kind];
        message = [NSString stringWithContentsOfFile:[root stringByAppendingPathComponent:filename] encoding:NSUTF8StringEncoding error:nil] ?: @"KING OF TIMEで打刻を確認してください。";
        if (self.repeated) {
            message = [message stringByReplacingOccurrencesOfString:@"の5分前です。" withString:@"の打刻リマインダーです。"];
            message = [message stringByReplacingOccurrencesOfString:@"の時刻になりました。" withString:@"の打刻リマインダーです。"];
        }
    }
    alert.informativeText = [message stringByAppendingString:@"\n\n再通知までの時間を選んでください。"];
    NSPopUpButton *choice = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0,0,220,28) pullsDown:NO];
    [choice addItemsWithTitles:@[@"10分後", @"30分後", @"1時間後", @"2時間後"]];
    [choice selectItemAtIndex:0]; alert.accessoryView = choice;
    [alert addButtonWithTitle:@"再通知"]; [alert addButtonWithTitle:@"閉じる"];
    return alert;
}
- (void)testReminder:(id)sender {
    NSAlert *alert = [self reminderAlert:YES];
    [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
        if (response == NSAlertFirstButtonReturn) {
            NSString *choice = [(NSPopUpButton *)alert.accessoryView titleOfSelectedItem];
            [self showMessage:[NSString stringWithFormat:@"表示テストです。%@を選択しました。\n実際の再通知は予約しません。", choice]];
        }
    }];
}
- (void)showNotification {
    if (self.showingAlert) return;
    [NSApp activateIgnoringOtherApps:YES];
    NSAlert *alert = [self reminderAlert:NO];
    self.showingAlert = YES;
    NSModalResponse response = [alert runModal];
    self.showingAlert = NO;
    if (response != NSAlertFirstButtonReturn) { [NSApp terminate:nil]; return; }
    NSInteger selected = [(NSPopUpButton *)alert.accessoryView indexOfSelectedItem];
    NSArray<NSNumber *> *durations = @[@600, @1800, @3600, @7200];
    self.repeated = YES;
    self.reminderTimer = [NSTimer scheduledTimerWithTimeInterval:durations[(NSUInteger)selected].doubleValue target:self selector:@selector(reminderTimerFired:) userInfo:nil repeats:NO];
}
- (void)reminderTimerFired:(NSTimer *)timer { self.reminderTimer = nil; [self showNotification]; }
- (BOOL)applicationShouldHandleReopen:(NSApplication *)application hasVisibleWindows:(BOOL)visible {
    if (self.notificationMode && !self.showingAlert) {
        [self.reminderTimer invalidate]; self.reminderTimer = nil;
        [self performSelector:@selector(showNotification) withObject:nil afterDelay:0];
    }
    return YES;
}
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    NSString *identifier = NSBundle.mainBundle.bundleIdentifier;
    self.notificationMode = [identifier hasSuffix:@".start"] || [identifier hasSuffix:@".end"];
    if (self.notificationMode) {
        self.kind = [identifier hasSuffix:@".start"] ? @"start" : @"end";
        [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
        [self performSelector:@selector(showNotification) withObject:nil afterDelay:0];
    } else [self showManager];
}
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender { return !self.notificationMode; }
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
