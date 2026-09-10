//
//  EnjoyableApplicationDelegate.m
//  Enjoy
//
//  Created by Sam McCall on 4/05/09.
//

#import "EnjoyableApplicationDelegate.h"

#import "NJMapping.h"
#import "NJInput.h"
#import "NJEvents.h"

static NSToolbarItemIdentifier const NJMappingToolbarItemIdentifier = @"de.slsoft.Enjoyable.toolbar.mapping";
static NSToolbarItemIdentifier const NJEnabledToolbarItemIdentifier = @"de.slsoft.Enjoyable.toolbar.enabled";
static NSToolbarIdentifier const NJToolbarIdentifier = @"de.slsoft.Enjoyable.toolbar";
static NSString *const NJLaunchEnabledDefaultsKey = @"launch enabled";

static NSString *NJInterfaceString(NSString *key, NSString *fallback) {
    return [NSBundle.mainBundle localizedStringForKey:key value:fallback table:@"MainMenu"];
}

static NSImage *NJStatusLampImage(NSColor *color) {
    NSImage *image = [NSImage imageWithSize:NSMakeSize(12.0, 12.0)
                                    flipped:NO
                             drawingHandler:^BOOL(NSRect dstRect) {
        NSRect circleRect = NSInsetRect(dstRect, 1.0, 1.0);
        [color setFill];
        [[NSBezierPath bezierPathWithOvalInRect:circleRect] fill];
        [[NSColor colorWithWhite:0.0 alpha:0.25] setStroke];
        NSBezierPath *outline = [NSBezierPath bezierPathWithOvalInRect:NSInsetRect(circleRect, 0.5, 0.5)];
        outline.lineWidth = 0.75;
        [outline stroke];
        return YES;
    }];
    image.template = NO;
    return image;
}

@implementation EnjoyableApplicationDelegate {
    NSStatusItem *statusItem;
    NSMutableArray *_errors;
    NSToolbar *_toolbar;
    NSToolbarItem *_mappingToolbarItem;
    NSToolbarItem *_enabledToolbarItem;
}

- (void)mappingToolbarClicked:(id)sender {
    [self.mvc mappingTriggerClicked:sender];
}

- (void)updateEnabledToolbarItem {
    BOOL enabled = self.ic.simulatingEvents;
    NSString *title = enabled
        ? NSLocalizedString(@"Enabled", @"toolbar state when mapped actions are enabled")
        : NSLocalizedString(@"Disabled", @"toolbar state when mapped actions are disabled");
    _enabledToolbarItem.label = title;
    _enabledToolbarItem.title = title;
    _enabledToolbarItem.image = NJStatusLampImage(enabled ? NSColor.systemGreenColor : NSColor.systemRedColor);
    _enabledToolbarItem.toolTip = enabled
        ? NSLocalizedString(@"Disable mapped actions", @"toolbar tooltip while mappings are enabled")
        : NSLocalizedString(@"Enable mapped actions", @"toolbar tooltip while mappings are disabled");
}

- (void)configureToolbar {
    NSString *mappingTitle = NJInterfaceString(@"83.title", @"Mappings");

    _mappingToolbarItem = [[NSToolbarItem alloc] initWithItemIdentifier:NJMappingToolbarItemIdentifier];
    _mappingToolbarItem.label = NJInterfaceString(@"837.label", @"Mapping Selector");
    _mappingToolbarItem.paletteLabel = _mappingToolbarItem.label;
    _mappingToolbarItem.title = mappingTitle;
    _mappingToolbarItem.toolTip = NJInterfaceString(@"835.ibShadowedToolTip", @"Change the active mapping");
    _mappingToolbarItem.image = [NSImage imageNamed:NSImageNameListViewTemplate];
    _mappingToolbarItem.bordered = YES;
    _mappingToolbarItem.target = self;
    _mappingToolbarItem.action = @selector(mappingToolbarClicked:);
    _mappingToolbarItem.autovalidates = NO;
    if (@available(macOS 13.0, *))
        _mappingToolbarItem.possibleLabels = [NSSet setWithObject:mappingTitle];

    _enabledToolbarItem = [[NSToolbarItem alloc] initWithItemIdentifier:NJEnabledToolbarItemIdentifier];
    _enabledToolbarItem.paletteLabel = NSLocalizedString(@"Status", @"toolbar status item");
    _enabledToolbarItem.bordered = YES;
    _enabledToolbarItem.target = self;
    _enabledToolbarItem.action = @selector(toggleSimulation:);
    if (@available(macOS 13.0, *)) {
        _enabledToolbarItem.possibleLabels = [NSSet setWithObjects:
            NSLocalizedString(@"Enabled", @"toolbar state when mapped actions are enabled"),
            NSLocalizedString(@"Disabled", @"toolbar state when mapped actions are disabled"),
            nil];
    }
    [self updateEnabledToolbarItem];

    _toolbar = [[NSToolbar alloc] initWithIdentifier:NJToolbarIdentifier];
    _toolbar.delegate = self;
    _toolbar.allowsUserCustomization = NO;
    _toolbar.displayMode = NSToolbarDisplayModeIconOnly;
    _toolbar.sizeMode = NSToolbarSizeModeRegular;
    _toolbar.showsBaselineSeparator = NO;
    self.window.toolbar = _toolbar;

    self.mvc.mappingToolbarItem = _mappingToolbarItem;
    self.mvc.mappingPopoverAnchorView = self.window.contentView;
}

- (NSArray<NSToolbarItemIdentifier> *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar {
    return @[NJMappingToolbarItemIdentifier, NSToolbarFlexibleSpaceItemIdentifier, NJEnabledToolbarItemIdentifier];
}

- (NSArray<NSToolbarItemIdentifier> *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar {
    return @[NJMappingToolbarItemIdentifier, NSToolbarFlexibleSpaceItemIdentifier, NJEnabledToolbarItemIdentifier];
}

- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar
     itemForItemIdentifier:(NSToolbarItemIdentifier)itemIdentifier
 willBeInsertedIntoToolbar:(BOOL)flag {
    if ([itemIdentifier isEqualToString:NJMappingToolbarItemIdentifier])
        return _mappingToolbarItem;
    if ([itemIdentifier isEqualToString:NJEnabledToolbarItemIdentifier])
        return _enabledToolbarItem;
    return nil;
}

- (void)didSwitchApplication:(NSNotification *)note {
    NSRunningApplication *activeApp = note.userInfo[NSWorkspaceApplicationKey];
    if (activeApp)
        [self.ic activateMappingForProcess:activeApp];
}

- (void)applicationWillFinishLaunching:(NSNotification *)notification {
    self.window.restorable = NO;

    [NSNotificationCenter.defaultCenter
        addObserver:self
        selector:@selector(mappingDidChange:)
        name:NJEventMappingChanged
        object:nil];
    [NSNotificationCenter.defaultCenter
        addObserver:self
        selector:@selector(eventSimulationStarted:)
        name:NJEventSimulationStarted
        object:nil];
    [NSNotificationCenter.defaultCenter
        addObserver:self
        selector:@selector(eventSimulationStopped:)
        name:NJEventSimulationStopped
        object:nil];

    [self configureToolbar];
    [self.ic load];
    [self.mvc.mappingList reloadData];
    [self.mvc changedActiveMappingToIndex:
     [self.ic indexOfMapping:
      self.ic.currentMapping]];

    statusItem = [NSStatusBar.systemStatusBar statusItemWithLength:36];
    if (statusItem.button) {
        statusItem.button.image = [NSImage imageNamed:@"Status Menu Icon Disabled"];
        statusItem.button.target = self;
        statusItem.button.action = @selector(statusItemClicked:);
        if ([statusItem.button.cell isKindOfClass:[NSButtonCell class]]) {
            ((NSButtonCell *)statusItem.button.cell).highlightsBy = NSContentsCellMask;
        }
    }
    statusItem.menu = self.statusItemMenu;

    BOOL launchEnabled = [NSUserDefaults.standardUserDefaults boolForKey:NJLaunchEnabledDefaultsKey];
    if (launchEnabled)
        self.ic.simulatingEvents = YES;
}

- (void)statusItemClicked:(id)sender {
    // Hier kannst du z.B. das Menü anzeigen oder ein Fenster öffnen
    [self.window makeKeyAndOrderFront:nil];
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    BOOL hidden = [NSUserDefaults.standardUserDefaults boolForKey:@"hidden in status item"];
    BOOL launchedAsLoginItem = [NSProcessInfo.processInfo.environment objectForKey:@"XPC_SERVICE_NAME"] != nil;
    if (hidden && launchedAsLoginItem) {
        [self transformIntoElement:nil];
    } else {
        [self.window makeKeyAndOrderFront:nil];
    }
}
- (BOOL)applicationSupportsSecureRestorableState:(NSApplication *)application {
    return YES;
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)theApplication
                    hasVisibleWindows:(BOOL)flag {
    [self restoreToForeground:theApplication];
    return NO;
}

- (void)restoreToForeground:(id)sender {
    ProcessSerialNumber psn = { 0, kCurrentProcess };
    TransformProcessType(&psn, kProcessTransformToForegroundApplication);
    [NSApplication.sharedApplication activateIgnoringOtherApps:YES];
    [self.window makeKeyAndOrderFront:sender];
    [NSObject cancelPreviousPerformRequestsWithTarget:self
                                             selector:@selector(transformIntoElement:)
                                               object:self];
    [NSUserDefaults.standardUserDefaults setBool:NO forKey:@"hidden in status item"];
}

- (void)applicationWillBecomeActive:(NSNotification *)notification {
    if (self.window.isVisible)
        [self restoreToForeground:notification];
}

- (void)transformIntoElement:(id)sender {
    ProcessSerialNumber psn = { 0, kCurrentProcess };
    TransformProcessType(&psn, kProcessTransformToUIElementApplication);
    [NSUserDefaults.standardUserDefaults setBool:YES forKey:@"hidden in status item"];
}

- (void)flashStatusItem {
    if ([statusItem.button.image.name isEqualToString:@"Status Menu Icon"]) {
        statusItem.button.image = [NSImage imageNamed:@"Status Menu Icon Disabled"];
    } else {
        statusItem.button.image = [NSImage imageNamed:@"Status Menu Icon"];
    }
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)theApplication {
    [theApplication hide:theApplication];
    // If we turn into a UIElement right away, the application cancels
    // the deactivation events. The dock icon disappears, but an
    // unresponsive menu bar remains until the user clicks somewhere.
    // So delay just long enough to be past the end handling that.
    [self performSelector:@selector(transformIntoElement:) withObject:self afterDelay:0.001];
    return NO;
}

- (void)eventSimulationStarted:(NSNotification *)note {
    [self updateEnabledToolbarItem];
    if (statusItem.button) {
        statusItem.button.image = [NSImage imageNamed:@"Status Menu Icon"];
    }
    [NSProcessInfo.processInfo
        disableAutomaticTermination:@"Event simulation running."];
    [NSWorkspace.sharedWorkspace.notificationCenter
        addObserver:self
        selector:@selector(didSwitchApplication:)
        name:NSWorkspaceDidActivateApplicationNotification
        object:nil];
}

- (void)eventSimulationStopped:(NSNotification *)note {
    [self updateEnabledToolbarItem];
    if (statusItem.button) {
        statusItem.button.image = [NSImage imageNamed:@"Status Menu Icon Disabled"];
    }
    [NSProcessInfo.processInfo enableAutomaticTermination:@"Event simulation running."];
    [NSWorkspace.sharedWorkspace.notificationCenter
        removeObserver:self
        name:NSWorkspaceDidActivateApplicationNotification
        object:nil];
}

- (void)mappingDidChange:(NSNotification *)note {
    NSUInteger idx = [note.userInfo[NJMappingIndexKey] intValue];
    [self.mvc changedActiveMappingToIndex:idx];

    if (!self.window.isVisible)
        for (int i = 0; i < 4; ++i)
            [self performSelector:@selector(flashStatusItem)
                       withObject:self
                       afterDelay:0.2 * i];
    [self loadOutputForInput:self.dvc.selectedHandler];
}

- (NSMenu *)applicationDockMenu:(NSApplication *)sender {
    return self.dockMenu;
}

- (void)showNextError {
    if (!self.window.attachedSheet && _errors.count) {
        NSError *error = _errors.lastObject;
        [_errors removeLastObject];
        [NSApplication.sharedApplication activateIgnoringOtherApps:YES];
        [self.window makeKeyAndOrderFront:nil];
        [self.window presentError:error
                   modalForWindow:self.window
                         delegate:self
               didPresentSelector:@selector(didPresentErrorWithRecovery:contextInfo:)
                      contextInfo:nil];
    }
}

- (void)didPresentErrorWithRecovery:(BOOL)didRecover
                        contextInfo:(void *)contextInfo {
    [self showNextError];
}

- (void)presentErrorSheet:(NSError *)error {
    if (!_errors)
        _errors = [[NSMutableArray alloc] initWithCapacity:1];
    [_errors insertObject:error atIndex:0];
    [self showNextError];
}

- (BOOL)application:(NSApplication *)sender openFile:(NSString *)filename {
    [self restoreToForeground:sender];
    NSError *error = nil;
    NSURL *URL = [NSURL fileURLWithPath:filename];
    NJMapping *mapping = [NJMapping mappingWithContentsOfURL:URL
                                                       error:&error];
    NJMapping *existing = mapping ? [self.ic mappingForKey:mapping.name] : nil;
    if ([existing hasConflictWith:mapping]) {
        [self promptForMapping:mapping atIndex:self.ic.mappings.count];
    } else if (existing) {
        [existing mergeEntriesFrom:mapping];
    } else if (mapping) {
        [self.mvc beginUpdates];
        [self.ic addMapping:mapping];
        [self.mvc addedMappingAtIndex:self.ic.mappings.count - 1 startEditing:NO];
        [self.mvc endUpdates];
        [self.ic activateMapping:mapping];
    } else {
        [self presentErrorSheet:error];
    }
    return !!mapping;
}

- (void)mappingWasChosen:(NJMapping *)mapping {
    [self.ic activateMapping:mapping];
}

- (void)mappingListShouldOpen {
    [self restoreToForeground:self];
    [self.mvc mappingTriggerClicked:self];
}

- (NSString *)uniqueCloneNameForMapping:(NJMapping *)mapping {
    NSString *baseName = [NSString stringWithFormat:
        NSLocalizedString(@"%@ copy", @"default name for a cloned mapping"), mapping.name];
    if (![self.ic mappingForKey:baseName])
        return baseName;

    NSInteger suffix = 2;
    NSString *candidate = nil;
    do {
        candidate = [NSString stringWithFormat:
            NSLocalizedString(@"%@ copy %ld", @"default name for an additional cloned mapping"),
            mapping.name, (long)suffix++];
    } while ([self.ic mappingForKey:candidate]);
    return candidate;
}

- (IBAction)cloneMappingClicked:(id)sender {
    NJMapping *source = self.ic.currentMapping;
    if (!source)
        return;

    NJMapping *clone = [[NJMapping alloc] initWithSerialization:[source serialize]];
    clone.name = [self uniqueCloneNameForMapping:source];

    NSInteger sourceIndex = [self.ic indexOfMapping:source];
    NSInteger insertIndex = sourceIndex == NSNotFound
        ? (NSInteger)self.ic.mappings.count
        : sourceIndex + 1;

    [self.mvc beginUpdates];
    [self.ic insertMapping:clone atIndex:insertIndex];
    [self.mvc addedMappingAtIndex:insertIndex startEditing:YES];
    [self.mvc endUpdates];
    [self.ic activateMapping:clone];
}

- (void)importMappingClicked:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.allowedFileTypes = @[ @"enjoyable", @"json", @"txt" ];
    [panel beginSheetModalForWindow:self.window
                  completionHandler:^(NSInteger result) {
                      if (result != NSModalResponseOK)
                          return;
                      [panel close];
                      NSError *error = nil;
                      NJMapping *mapping = [NJMapping mappingWithContentsOfURL:panel.URL
                                                                         error:&error];
                      NJMapping *existing = mapping ? [self.ic mappingForKey:mapping.name] : nil;
                      if ([existing hasConflictWith:mapping]) {
                          [self promptForMapping:mapping atIndex:self.ic.mappings.count];
                      } else if (existing) {
                          [existing mergeEntriesFrom:mapping];
                          [self.mvc.mappingList reloadData];
                      } else if (mapping) {
                          [self.ic addMapping:mapping];
                          [self.mvc.mappingList reloadData];
                      } else {
                          [self presentErrorSheet:error];
                      }
                  }];
}

- (void)exportMappingClicked:(id)sender {
    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.allowedFileTypes = @[ @"enjoyable" ];
    NJMapping *mapping = self.ic.currentMapping;
    panel.nameFieldStringValue = [mapping.name stringByFixingPathComponent];
    [panel beginSheetModalForWindow:self.window
                  completionHandler:^(NSInteger result) {
                      if (result != NSModalResponseOK)
                          return;
                      [panel close];
                      NSError *error = nil;
                      if (![mapping writeToURL:panel.URL error:&error]) {
                          [self presentErrorSheet:error];
                      }
                  }];
}

- (void)mappingConflictDidResolve:(NSAlert *)alert
                       returnCode:(NSInteger)returnCode
                      contextInfo:(void *)contextInfo {
    NSDictionary *userInfo = CFBridgingRelease(contextInfo);
    NJMapping *oldMapping = userInfo[@"old mapping"];
    NJMapping *newMapping = userInfo[@"new mapping"];
    NSInteger idx = [userInfo[@"index"] intValue];
    [alert.window orderOut:nil];
    if (returnCode == NSAlertFirstButtonReturn) { // Merge
        [self.ic mergeMapping:newMapping intoMapping:oldMapping];
        [self.ic activateMapping:oldMapping];
    } else if (returnCode == NSAlertThirdButtonReturn) { // New Mapping
        [self.mvc beginUpdates];
        [self.ic addMapping:newMapping];
        [self.mvc addedMappingAtIndex:idx startEditing:YES];
        [self.mvc endUpdates];
        [self.ic activateMapping:newMapping];
    }
}

- (void)promptForMapping:(NJMapping *)mapping atIndex:(NSInteger)idx {
    NJMapping *mergeInto = [self.ic mappingForKey:mapping.name];
    NSAlert *conflictAlert = [[NSAlert alloc] init];
    conflictAlert.messageText = NSLocalizedString(@"import conflict prompt", @"Title of import conflict alert");
    conflictAlert.informativeText =
        [NSString stringWithFormat:NSLocalizedString(@"import conflict in %@", @"Explanation of import conflict"),
         mapping.name];
    [conflictAlert addButtonWithTitle:NSLocalizedString(@"import and merge", @"button to merge imported mappings")];
    [conflictAlert addButtonWithTitle:NSLocalizedString(@"cancel import", @"button to cancel import")];
    [conflictAlert addButtonWithTitle:NSLocalizedString(@"import new mapping", @"button to import as new mapping")];

    NSDictionary *userInfo = @{ @"index": @(idx),
                                @"old mapping": mergeInto,
                                @"new mapping": mapping };

    [conflictAlert beginSheetModalForWindow:self.window
                          completionHandler:^(NSModalResponse returnCode) {
        [self mappingConflictDidResolve:conflictAlert
                            returnCode:returnCode
                           contextInfo:(__bridge void *)userInfo];
    }];
}

- (NSInteger)numberOfMappings:(NJMappingsViewController *)mvc {
    return self.ic.mappings.count;
}

- (NJMapping *)mappingsViewController:(NJMappingsViewController *)mvc
                      mappingForIndex:(NSUInteger)idx {
    return self.ic.mappings[idx];
}

- (void)mappingsViewController:(NJMappingsViewController *)mvc
          renameMappingAtIndex:(NSInteger)index
                        toName:(NSString *)name {
    [self.ic renameMapping:self.ic.mappings[index] to:name];
}

- (BOOL)mappingsViewController:(NJMappingsViewController *)mvc
       canMoveMappingFromIndex:(NSInteger)fromIdx
                       toIndex:(NSInteger)toIdx {
    NSInteger count = (NSInteger)self.ic.mappings.count;
    return fromIdx >= 0 && fromIdx < count &&
           toIdx >= 0 && toIdx < count &&
           fromIdx != toIdx;
}

- (void)mappingsViewController:(NJMappingsViewController *)mvc
          moveMappingFromIndex:(NSInteger)fromIdx
                       toIndex:(NSInteger)toIdx {
    [mvc beginUpdates];
    [mvc.mappingList moveRowAtIndex:fromIdx toIndex:toIdx];
    [self.ic moveMoveMappingFromIndex:fromIdx toIndex:toIdx];
    [mvc endUpdates];
}

- (BOOL)mappingsViewController:(NJMappingsViewController *)mvc
       canRemoveMappingAtIndex:(NSInteger)idx {
    return idx != 0;
}

- (void)mappingsViewController:(NJMappingsViewController *)mvc
          removeMappingAtIndex:(NSInteger)idx {
    [mvc beginUpdates];
    [mvc removedMappingAtIndex:idx];
    [self.ic removeMappingAtIndex:idx];
    [mvc endUpdates];
}

- (BOOL)mappingsViewController:(NJMappingsViewController *)mvc
          importMappingFromURL:(NSURL *)url
                       atIndex:(NSInteger)index
                         error:(NSError **)error {
    NJMapping *mapping = [NJMapping mappingWithContentsOfURL:url
                                                       error:error];
    NJMapping *existing = mapping ? [self.ic mappingForKey:mapping.name] : nil;
    if ([existing hasConflictWith:mapping]) {
        [self promptForMapping:mapping atIndex:index];
    } else if (existing) {
        [existing mergeEntriesFrom:mapping];
    } else if (mapping) {
        [self.mvc beginUpdates];
        [self.mvc addedMappingAtIndex:index startEditing:NO];
        [self.ic insertMapping:mapping atIndex:index];
        [self.mvc endUpdates];
    }
    return !!mapping;
}

- (void)mappingsViewController:(NJMappingsViewController *)mvc
                    addMapping:(NJMapping *)mapping {
    [mvc beginUpdates];
    [mvc addedMappingAtIndex:self.ic.mappings.count startEditing:YES];
    [self.ic addMapping:mapping];
    [mvc endUpdates];
    [self.ic activateMapping:mapping];
}

- (void)mappingsViewController:(NJMappingsViewController *)mvc
           choseMappingAtIndex:(NSInteger)idx {
    [self.ic activateMapping:self.ic.mappings[idx]];
}

- (id)deviceViewController:(NJDeviceViewController *)dvc
             elementForUID:(NSString *)uid {
    return [self.ic elementForUID:uid];
}

- (void)loadOutputForInput:(NJInput *)input {
    NJOutput *output = self.ic.currentMapping[input];
    [self.oc loadOutput:output forInput:input];
}

- (void)deviceViewControllerDidSelectNothing:(NJDeviceViewController *)dvc {
    [self loadOutputForInput:nil];
}

- (void)deviceViewController:(NJDeviceViewController *)dvc
             didSelectBranch:(NJInputPathElement *)handler {
    [self loadOutputForInput:dvc.selectedHandler];
}

- (void)deviceViewController:(NJDeviceViewController *)dvc
            didSelectHandler:(NJInputPathElement *)handler {
    [self loadOutputForInput:dvc.selectedHandler];
}

- (void)deviceViewController:(NJDeviceViewController *)dvc
             didSelectDevice:(NJInputPathElement *)device {
    [self loadOutputForInput:dvc.selectedHandler];
}

- (void)inputController:(NJInputController *)ic
           didAddDevice:(NJDevice *)device {
    [self.dvc addedDevice:device atIndex:ic.devices.count - 1];
}

- (void)inputController:(NJInputController *)ic
 didRemoveDeviceAtIndex:(NSInteger)idx {
    [self.dvc removedDeviceAtIndex:idx];
}

- (void)inputControllerDidStartHID:(NJInputController *)ic {
    [self.dvc hidStarted];
}

- (void)inputControllerDidStopHID:(NJInputController *)ic {
    [self.dvc hidStopped];
}

- (void)inputController:(NJInputController *)ic didInput:(NJInput *)input {
    [self.dvc expandAndSelectItem:input];
    [self loadOutputForInput:input];
    [self.oc focusKey];
}

- (void)inputController:(NJInputController *)ic didError:(NSError *)error {
    [self presentErrorSheet:error];
}

- (NSInteger)numberOfDevicesInDeviceList:(NJDeviceViewController *)dvc {
    return self.ic.devices.count;
}

- (NJDevice *)deviceViewController:(NJDeviceViewController *)dvc
                    deviceForIndex:(NSUInteger)idx {
    return self.ic.devices[idx];
}

- (IBAction)toggleSimulation:(id)sender {
    self.ic.simulatingEvents = !self.ic.simulatingEvents;
}


- (void)outputViewController:(NJOutputViewController *)ovc
                   setOutput:(NJOutput *)output
                    forInput:(NJInput *)input {
    self.ic.currentMapping[input] = output;
    [self.ic save];
}

- (NJMapping *)outputViewController:(NJOutputViewController *)ovc
                    mappingForIndex:(NSUInteger)index {
    return self.ic.mappings[index];
}

@end
