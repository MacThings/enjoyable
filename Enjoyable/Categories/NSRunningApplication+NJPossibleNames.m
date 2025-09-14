// Enjoyable/Categories/NSRunningApplication+NJPossibleNames.m

#import "NSRunningApplication+NJPossibleNames.h"

@implementation NSRunningApplication (NJPossibleNames)

- (NSArray<NSString *> *)windowTitles {
    static CGWindowListOption s_OPTIONS = (CGWindowListOption)(kCGWindowListOptionOnScreenOnly | kCGWindowListExcludeDesktopElements);
    NSMutableArray<NSString *> *titles = [[NSMutableArray alloc] initWithCapacity:4];
    NSArray *windows = CFBridgingRelease(CGWindowListCopyWindowInfo(s_OPTIONS, kCGNullWindowID));
    for (NSDictionary *props in windows) {
        NSNumber *pid = props[(id)kCGWindowOwnerPID];
        NSString *title = props[(id)kCGWindowName];
        if (pid.longValue == self.processIdentifier && title.length > 0) {
            [titles addObject:title];
        }
    }
    return titles;
}

- (NSString *)frontWindowTitle {
    NSArray<NSString *> *titles = [self windowTitles];
    return titles.count > 0 ? titles[0] : nil;
}

- (NSArray<NSString *> *)possibleMappingNames {
    NSMutableArray<NSString *> *names = [[NSMutableArray alloc] initWithCapacity:4];
    if (self.bundleIdentifier)
        [names addObject:self.bundleIdentifier];
    if (self.localizedName)
        [names addObject:self.localizedName];
    if (self.bundleURL)
        [names addObject:self.bundleURL.lastPathComponent.stringByDeletingPathExtension];
    if (self.executableURL)
        [names addObject:self.executableURL.lastPathComponent];
    NSString *frontTitle = self.frontWindowTitle;
    if (frontTitle)
        [names addObject:frontTitle];
    return names;
}

- (NSString *)bestMappingName {
    NSArray<NSString *> *genericBundles = @[
        @"com.macromedia.Flash Player Debugger.app",
        @"com.macromedia.Flash Player.app",
    ];
    NSArray<NSString *> *genericExecutables = @[ @"wine.bin" ];
    BOOL probablyWrong = ([genericBundles containsObject:self.bundleIdentifier]
                          || [genericExecutables containsObject:self.localizedName]);
    if (!probablyWrong && self.localizedName)
        return self.localizedName;
    else if (!probablyWrong && self.bundleIdentifier)
        return self.bundleIdentifier;
    else if (self.bundleURL)
        return self.bundleURL.lastPathComponent.stringByDeletingPathExtension;
    else if (self.frontWindowTitle)
        return self.frontWindowTitle;
    else if (self.executableURL)
        return self.executableURL.lastPathComponent;
    else if (self.localizedName)
        return self.localizedName;
    else if (self.bundleIdentifier)
        return self.bundleIdentifier;
    else {
        return NSLocalizedString(@"@Application",
                                 @"Magic string to trigger automatic mapping renames. It should look like an identifier rather than normal word, with the @ on the front.");
    }
}

@end
