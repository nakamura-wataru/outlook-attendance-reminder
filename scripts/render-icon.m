#import "../source/reminder-artwork.h"

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc != 2) return 1;
        NSString *directory = [NSString stringWithUTF8String:argv[1]];
        __block BOOL saved = YES;
        // App icons keep the same face and colours regardless of system theme.
        [[NSAppearance appearanceNamed:NSAppearanceNameDarkAqua] performAsCurrentDrawingAppearance:^{
            for (NSNumber *pointSize in @[@16, @32, @128, @256, @512]) {
                for (NSInteger scale = 1; scale <= 2; scale++) {
                    NSInteger pixels = pointSize.integerValue * scale;
                    NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:pixels pixelsHigh:pixels bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
                    [NSGraphicsContext saveGraphicsState];
                    [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:bitmap]];
                    CGContextClearRect(NSGraphicsContext.currentContext.CGContext, CGRectMake(0, 0, pixels, pixels));
                    CGFloat padding = pixels / 16.0;
                    DrawReminderClock(NSMakeRect(padding, padding, pixels - padding * 2, pixels - padding * 2));
                    [NSGraphicsContext restoreGraphicsState];
                    NSString *filename = [NSString stringWithFormat:@"icon_%ldx%ld%@.png", pointSize.longValue, pointSize.longValue, scale == 2 ? @"@2x" : @""];
                    NSData *png = [bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
                    if (!png || ![png writeToFile:[directory stringByAppendingPathComponent:filename] atomically:YES]) saved = NO;
                }
            }
        }];
        return saved ? 0 : 1;
    }
}
