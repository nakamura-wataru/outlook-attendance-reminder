#pragma once
#import <Cocoa/Cocoa.h>

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
