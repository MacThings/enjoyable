//
//  NSApplication+LoginItem.m
//  Enjoyable
//
//  Created by Joe Wreschnig on 3/13/13.
//
//

#import "NSRunningApplication+LoginItem.h"
#import <ServiceManagement/ServiceManagement.h>
#import <CoreServices/CoreServices.h>

@implementation NSRunningApplication (LoginItem)

- (NSString *)helperBundleIdentifier {
    // Passe die Bundle-ID deines Login-Item-Helpers hier an!
    return @"de.slsoft.Enjoyable";
}

- (BOOL)isLoginItem {
    // Status wird in den UserDefaults verwaltet
    NSString *key = [NSString stringWithFormat:@"loginItem_%@", [self helperBundleIdentifier]];
    return [[NSUserDefaults standardUserDefaults] boolForKey:key];
}

- (void)addToLoginItems {
    NSString *bundleID = [self helperBundleIdentifier];
    if (SMLoginItemSetEnabled((__bridge CFStringRef)bundleID, true)) {
        NSString *key = [NSString stringWithFormat:@"loginItem_%@", bundleID];
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:key];
    }
}

- (void)removeFromLoginItems {
    NSString *bundleID = [self helperBundleIdentifier];
    if (SMLoginItemSetEnabled((__bridge CFStringRef)bundleID, false)) {
        NSString *key = [NSString stringWithFormat:@"loginItem_%@", bundleID];
        [[NSUserDefaults standardUserDefaults] setBool:NO forKey:key];
    }
}

@end
