//
//  main.m
//  Enjoy
//
//  Created by Sam McCall on 4/05/09.
//

#import <Cocoa/Cocoa.h>

@interface EnjoyableApplication : NSApplication
@end

@implementation EnjoyableApplication

- (BOOL)restoreWindowWithIdentifier:(NSUserInterfaceItemIdentifier)identifier
                              state:(NSCoder *)state
                  completionHandler:(void (^)(NSWindow *window, NSError *error))completionHandler {
    // Enjoyable manages its single utility window explicitly. Consume stale
    // restoration records from older builds instead of asking AppKit to restore them.
    completionHandler(nil, nil);
    return YES;
}

@end

int main(int argc, char *argv[])
{
    return NSApplicationMain(argc, (const char **)argv);
}
