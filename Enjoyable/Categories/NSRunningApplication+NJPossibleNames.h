//
//  NSRunningApplication+NJPossibleNames.h
//  Enjoyable
//
//  Created by Joe Wreschnig on 3/8/13.
//
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSRunningApplication (NJPossibleNames)

/// Gibt eine Liste möglicher Mapping-Namen für diese Anwendung zurück.
- (NSArray<NSString *> *)possibleMappingNames;

/// Gibt den besten Mapping-Namen zurück, unter Berücksichtigung häufiger Namensprobleme.
- (NSString *)bestMappingName;

@end

NS_ASSUME_NONNULL_END
