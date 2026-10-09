#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>
#include <fcntl.h>
#include <unistd.h>

static BOOL ReminderDarkAppearance(void) {
    return [[[NSAppearance currentDrawingAppearance] bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]] isEqualToString:NSAppearanceNameDarkAqua];
}
static NSColor *ReminderColor(NSString *token) {
    NSDictionary *light = @{ @"canvas": @0xffffff, @"surface": @0xf7f8fa, @"hairline": @0xe4e6ec, @"ink": @0x14161c, @"ink-mute": @0x565d6d, @"primary": @0x4f46e5, @"primary-soft": @0xeef0fe };
    NSDictionary *dark = @{ @"canvas": @0x0e1015, @"surface": @0x161922, @"hairline": @0x262a34, @"ink": @0xe9ebf0, @"ink-mute": @0x99a0ae, @"primary": @0x7b84ff, @"primary-soft": @0x1c2040 };
    unsigned int rgb = [(ReminderDarkAppearance() ? dark : light)[token] unsignedIntValue];
    return [NSColor colorWithSRGBRed:((rgb >> 16) & 255) / 255.0 green:((rgb >> 8) & 255) / 255.0 blue:(rgb & 255) / 255.0 alpha:1];
}
static void DrawReminderClock(NSRect bounds) {
    CGFloat size = MIN(bounds.size.width, bounds.size.height);
    CGFloat x = NSMidX(bounds) - size / 2, y = NSMidY(bounds) - size / 2;
    [ReminderColor(@"primary-soft") setFill];
    [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(x, y, size, size)] fill];
    NSRect face = NSMakeRect(x + size * .12, y + size * .12, size * .76, size * .76);
    [ReminderColor(@"canvas") setFill];
    NSBezierPath *circle = [NSBezierPath bezierPathWithOvalInRect:face]; [circle fill];
    [ReminderColor(@"primary") setStroke]; circle.lineWidth = size * .035; [circle stroke];
    NSBezierPath *hands = [NSBezierPath bezierPath]; hands.lineWidth = size * .045; hands.lineCapStyle = NSLineCapStyleRound;
    [hands moveToPoint:NSMakePoint(x + size * .5, y + size * .69)];
    [hands lineToPoint:NSMakePoint(x + size * .5, y + size * .52)];
    [hands lineToPoint:NSMakePoint(x + size * .65, y + size * .60)]; [hands stroke];
    [ReminderColor(@"ink") setFill];
    for (NSNumber *position in @[@.36, @.60]) [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(x + size * position.doubleValue, y + size * .39, size * .045, size * .06)] fill];
    NSBezierPath *smile = [NSBezierPath bezierPath]; smile.lineWidth = size * .025; smile.lineCapStyle = NSLineCapStyleRound;
    [ReminderColor(@"primary") setStroke]; [smile moveToPoint:NSMakePoint(x + size * .42, y + size * .32)];
    [smile curveToPoint:NSMakePoint(x + size * .58, y + size * .32) controlPoint1:NSMakePoint(x + size * .45, y + size * .25) controlPoint2:NSMakePoint(x + size * .55, y + size * .25)]; [smile stroke];
}
@interface ReminderCard : NSView
@property BOOL canvas;
@end
@implementation ReminderCard
- (void)drawRect:(NSRect)dirtyRect {
    [ReminderColor(self.canvas ? @"canvas" : @"surface") setFill];
    NSBezierPath *shape = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds, .5, .5) xRadius:8 yRadius:8]; [shape fill];
    if (!self.canvas) { [ReminderColor(@"hairline") setStroke]; shape.lineWidth = 1; [shape stroke]; }
}
- (void)viewDidChangeEffectiveAppearance { [super viewDidChangeEffectiveAppearance]; [self setNeedsDisplay:YES]; }
@end
@interface ReminderClock : NSView
@end
@implementation ReminderClock
- (void)drawRect:(NSRect)dirtyRect { DrawReminderClock(self.bounds); }
- (void)viewDidChangeEffectiveAppearance { [super viewDidChangeEffectiveAppearance]; [self setNeedsDisplay:YES]; }
@end

@interface ReminderController : NSObject <NSApplicationDelegate, WKNavigationDelegate, WKUIDelegate>
@property NSWindow *window;
@property NSTextField *statusLabel;
@property NSTextField *statusBadge;
@property NSButton *toggleButton;
@property NSButton *migrationButton;
@property NSMutableArray<NSButton *> *buttons;
@property BOOL notificationMode;
@property NSString *kind;
@property NSTimer *reminderTimer;
@property BOOL repeated;
@property BOOL showingAlert;
@property NSWindow *recorderWindow;
@property WKWebView *recorderWebView;
@property NSTextField *recorderStatus;
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
    alert.icon = [self clockImage];
    alert.informativeText = message; [alert addButtonWithTitle:@"閉じる"];
    [alert beginSheetModalForWindow:self.window completionHandler:nil];
}
- (void)refreshStatus {
    [self runCommand:@"status" input:nil completion:^(BOOL ok, NSString *text) {
        self.statusLabel.stringValue = text;
        self.statusBadge.stringValue = [text hasPrefix:@"予定表：未設定"] ? @"○ 未設定" : @"○ 確認中";
        if (!ok) return;
        [self runCommand:@"enabled" input:nil completion:^(BOOL enabledOK, NSString *value) {
            self.toggleButton.title = enabledOK && [value isEqualToString:@"yes"] ? @"通知を停止" : @"通知を再開";
            self.statusBadge.stringValue = enabledOK && [value isEqualToString:@"yes"] ? @"● お知らせ中" : ([text hasPrefix:@"予定表：未設定"] ? @"○ 未設定" : @"○ 停止中");
            [self runCommand:@"can-migrate" input:nil completion:^(BOOL migrationOK, NSString *canMigrate) {
                self.migrationButton.hidden = !(migrationOK && [canMigrate isEqualToString:@"yes"]);
                [self.window setContentSize:NSMakeSize(560, self.migrationButton.hidden ? 512 : 576)];
            }];
        }];
    }];
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
    [stack addArrangedSubview:[self label:arrival ? @"「出社」「出勤」に対応" : @"「退社」「退勤」に対応" size:13 strong:NO muted:YES]];
    return [self card:stack];
}
- (void)showManager {
    self.buttons = [NSMutableArray array];
    self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,560,620) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskMiniaturizable backing:NSBackingStoreBuffered defer:NO];
    self.window.title = @"打刻リマインダー"; [self.window center];
    ReminderCard *background = [[ReminderCard alloc] init]; background.canvas = YES; self.window.contentView = background;
    NSStackView *stack = [self verticalStack:16];
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
    NSView *statusCard = [self card:status]; [stack addArrangedSubview:statusCard];
    [statusCard.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
    [self.statusLabel.widthAnchor constraintEqualToAnchor:status.widthAnchor].active = YES;
    NSStackView *schedule = [NSStackView stackViewWithViews:@[[self scheduleCard:YES], [self scheduleCard:NO]]];
    schedule.spacing = 16; schedule.distribution = NSStackViewDistributionFillEqually; schedule.alignment = NSLayoutAttributeTop;
    [stack addArrangedSubview:schedule]; [schedule.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
    NSButton *configure = [self button:@"予定表を設定・変更" selector:@selector(configure:)]; configure.toolTip = @"自分のOutlook予定表のICSリンクを登録します";
    NSButton *test = [self button:@"表示をテスト" selector:@selector(testReminder:)]; test.toolTip = @"通知の表示を確認します。実際の打刻や再通知は行いません";
    NSButton *recorder = [self button:@"KING OF TIMEで打刻" selector:@selector(openRecorder:)]; recorder.toolTip = @"アプリ内に公式Myレコーダーを開きます。初回はログインしてください";
    NSStackView *actions = [NSStackView stackViewWithViews:@[configure, test, recorder]]; actions.spacing = 12; [stack addArrangedSubview:actions];
    self.toggleButton = [self button:@"通知を再開" selector:@selector(toggle:)]; self.toggleButton.toolTip = @"通知の停止・再開は、Macを再起動しても維持されます";
    NSButton *help = [self button:@"使い方" selector:@selector(help:)];
    NSStackView *secondary = [NSStackView stackViewWithViews:@[self.toggleButton, help]]; secondary.spacing = 12; [stack addArrangedSubview:secondary];
    self.migrationButton = [self button:@"既存の設定を引き継ぐ" selector:@selector(migrate:)]; self.migrationButton.hidden = YES; [stack addArrangedSubview:self.migrationButton];
    [stack addArrangedSubview:[self label:@"再通知は10分・30分・1時間・2時間から選べます。\n「KING OF TIMEで打刻」から公式画面を開けます。" size:12 strong:NO muted:YES]];
    [NSApp setApplicationIconImage:[self clockImage]];
    [self.window makeKeyAndOrderFront:nil]; [NSApp activateIgnoringOtherApps:YES];
    [self runCommand:@"ensure" input:nil completion:^(BOOL ok, NSString *message) { [self refreshStatus]; }];
}
- (void)configure:(id)sender {
    NSAlert *alert = [[NSAlert alloc] init]; alert.messageText = @"予定表の設定";
    alert.icon = [self clockImage];
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
- (NSUserDefaults *)recorderPreferences { return [[NSUserDefaults alloc] initWithSuiteName:@"com.outlook-attendance-reminder.recorder"]; }
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
    NSWindow *parent = self.recorderWindow.visible ? self.recorderWindow : self.window;
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
- (void)showRecorder {
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
        self.recorderStatus = [self label:@"Myレコーダーを開いています…" size:13 strong:NO muted:YES]; [stack addArrangedSubview:self.recorderStatus];
        [self.recorderStatus.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
        NSStackView *toolbar = [NSStackView stackViewWithViews:@[
            [self button:@"再読み込み" selector:@selector(reloadRecorder:)],
            [self button:@"接続設定" selector:@selector(configureRecorder:)],
            [self button:@"ブラウザで開く" selector:@selector(openRecorderInBrowser:)]]]; toolbar.spacing = 12; [stack addArrangedSubview:toolbar];
        WKWebViewConfiguration *configuration = [[WKWebViewConfiguration alloc] init];
        configuration.websiteDataStore = WKWebsiteDataStore.defaultDataStore;
        self.recorderWebView = [[WKWebView alloc] initWithFrame:NSZeroRect configuration:configuration];
        self.recorderWebView.navigationDelegate = self; self.recorderWebView.UIDelegate = self;
        self.recorderWebView.translatesAutoresizingMaskIntoConstraints = NO;
        [stack addArrangedSubview:self.recorderWebView];
        [self.recorderWebView.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
        [self.recorderWebView.heightAnchor constraintGreaterThanOrEqualToConstant:400].active = YES;
        [self.recorderWebView setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationVertical];
        [self.recorderWebView setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationVertical];
    }
    [self.recorderWindow makeKeyAndOrderFront:nil]; [NSApp activateIgnoringOtherApps:YES];
    self.recorderStatus.stringValue = @"公式画面でログインし、出勤・退勤ボタンを押してください。";
    [self.recorderWebView loadRequest:[NSURLRequest requestWithURL:[self recorderURL]]];
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
    [alert beginSheetModalForWindow:self.recorderWindow completionHandler:^(NSModalResponse response) { completionHandler(); }];
}
- (void)webView:(WKWebView *)webView runJavaScriptConfirmPanelWithMessage:(NSString *)message initiatedByFrame:(WKFrameInfo *)frame completionHandler:(void (^)(BOOL))completionHandler {
    NSAlert *alert = [self websiteDialog:message frame:frame];
    [alert addButtonWithTitle:@"OK"]; [alert addButtonWithTitle:@"キャンセル"];
    [alert beginSheetModalForWindow:self.recorderWindow completionHandler:^(NSModalResponse response) { completionHandler(response == NSAlertFirstButtonReturn); }];
}
- (void)webViewWebContentProcessDidTerminate:(WKWebView *)webView {
    self.recorderStatus.stringValue = @"画面の読み込みが停止しました。「再読み込み」で開き直してください。";
}
- (void)help:(id)sender {
    [self showMessage:@"OutlookのWeb版で、設定 → 予定表 → 共有の予定表 → 予定表の公開を開き、タイトルが見えるICSリンクを取得してください。\n\n「予定表を設定・変更」へ自分のリンクを入力すると、出社・出勤は予定の5分前、退社・退勤は予定時刻に通知します。再通知は10分後・30分後・1時間後・2時間後です。\n\nこの画面を閉じても通知は続きます。停止はこのアプリから行えます。"];
}
- (NSAlert *)reminderAlert:(BOOL)test {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.icon = [self clockImage];
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
    if (!test) [alert addButtonWithTitle:@"KING OF TIMEで打刻"];
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
    if (response == NSAlertThirdButtonReturn) {
        NSString *bundle = NSBundle.mainBundle.bundlePath;
        for (NSUInteger i = 0; i < 4; i++) bundle = [bundle stringByDeletingLastPathComponent];
        if ([[NSBundle bundleWithPath:bundle].bundleIdentifier isEqualToString:@"com.outlook-attendance-reminder.app"]) {
            [[self recorderPreferences] setBool:YES forKey:@"openRequested"];
            NSWorkspaceOpenConfiguration *configuration = [NSWorkspaceOpenConfiguration configuration];
            [[NSWorkspace sharedWorkspace] openApplicationAtURL:[NSURL fileURLWithPath:bundle] configuration:configuration completionHandler:nil];
        }
        [NSApp terminate:nil]; return;
    }
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
    } else if (!self.notificationMode) {
        [self.window makeKeyAndOrderFront:nil];
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
        [self performSelector:@selector(showNotification) withObject:nil afterDelay:0];
    } else {
        [self showManager];
        if ([[self recorderPreferences] boolForKey:@"openRequested"]) { [[self recorderPreferences] removeObjectForKey:@"openRequested"]; [self openRecorder:nil]; }
    }
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
