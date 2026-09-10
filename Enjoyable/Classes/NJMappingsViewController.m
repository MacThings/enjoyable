//
//  NJMappingsViewController.m
//  Enjoyable
//
//  Created by Joe Wreschnig on 3/17/13.
//
//

#import "NJMappingsViewController.h"
#import "NJMapping.h"

#define PB_ROW @"de.slsoft.Enjoyable.MappingRow"

static const CGFloat NJMappingPopoverWidth = 300.0;
static const CGFloat NJMappingRowHeight = 30.0;
static const CGFloat NJMappingPopoverFooterHeight = 58.0;
static const NSInteger NJMappingPopoverMinVisibleRows = 2;
static const NSInteger NJMappingPopoverMaxVisibleRows = 8;

@interface NJMappingsViewController () <NSFilePromiseProviderDelegate>
@property (nonatomic, strong) NSButton *launchEnabledCheckbox;
@end

@implementation NJMappingsViewController

- (void)awakeFromNib {
    [self.mappingList registerForDraggedTypes:@[PB_ROW, NSPasteboardTypeURL, NSPasteboardTypeFileURL]];
    [self.mappingList setDraggingSourceOperationMask:NSDragOperationCopy forLocal:NO];

    self.mappingList.usesAlternatingRowBackgroundColors = NO;
    self.mappingList.rowHeight = NJMappingRowHeight;
    self.mappingList.intercellSpacing = NSMakeSize(0.0, 0.0);
    self.mappingList.selectionHighlightStyle = NSTableViewSelectionHighlightStyleRegular;
    self.mappingList.columnAutoresizingStyle = NSTableViewUniformColumnAutoresizingStyle;

    NSTableColumn *column = self.mappingList.tableColumns.firstObject;
    column.resizingMask = NSTableColumnAutoresizingMask;

    NSScrollView *scrollView = self.mappingList.enclosingScrollView;
    scrollView.autohidesScrollers = YES;
    scrollView.hasHorizontalScroller = NO;
    scrollView.horizontalScrollElasticity = NSScrollElasticityNone;

    NSString *launchTitle = NSLocalizedString(@"Enable at Launch",
                                               @"checkbox to enable mappings automatically when Enjoyable starts");
    self.launchEnabledCheckbox = [NSButton checkboxWithTitle:launchTitle
                                                     target:self
                                                     action:@selector(toggleLaunchEnabled:)];
    self.launchEnabledCheckbox.frame = NSMakeRect(8.0, 32.0, 284.0, 22.0);
    self.launchEnabledCheckbox.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
    self.launchEnabledCheckbox.controlSize = NSControlSizeSmall;
    self.launchEnabledCheckbox.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
    self.launchEnabledCheckbox.toolTip = launchTitle;
    self.launchEnabledCheckbox.state = [NSUserDefaults.standardUserDefaults boolForKey:@"launch enabled"]
        ? NSControlStateValueOn
        : NSControlStateValueOff;
    [self.view addSubview:self.launchEnabledCheckbox];

    [self updateMappingPopoverSize];
}

- (IBAction)toggleLaunchEnabled:(NSButton *)sender {
    [NSUserDefaults.standardUserDefaults setBool:(sender.state == NSControlStateValueOn)
                                          forKey:@"launch enabled"];
}

- (void)updateMappingPopoverSize {
    NSInteger rowCount = self.mappingList.numberOfRows;
    NSInteger visibleRows = MAX(NJMappingPopoverMinVisibleRows, rowCount);
    visibleRows = MIN(NJMappingPopoverMaxVisibleRows, visibleRows);

    CGFloat listHeight = (CGFloat)visibleRows * NJMappingRowHeight + 2.0;
    CGFloat contentHeight = NJMappingPopoverFooterHeight + listHeight;

    NSScrollView *scrollView = self.mappingList.enclosingScrollView;
    scrollView.hasVerticalScroller = rowCount > NJMappingPopoverMaxVisibleRows;
    self.mappingListPopover.contentSize = NSMakeSize(NJMappingPopoverWidth, contentHeight);
}

- (IBAction)addClicked:(id)sender {
    NJMapping *newMapping = [[NJMapping alloc] init];
    [self.delegate mappingsViewController:self addMapping:newMapping];
}

- (IBAction)removeClicked:(id)sender {
    NSInteger index = self.mappingList.selectedRow;
    if (index < 0 || ![self.delegate mappingsViewController:self canRemoveMappingAtIndex:index])
        return;

    [self.delegate mappingsViewController:self removeMappingAtIndex:index];
}

- (IBAction)moveUpClicked:(id)sender {
    NSInteger fromIdx = self.mappingList.selectedRow;
    NSInteger toIdx = fromIdx - 1;
    if (![self.delegate mappingsViewController:self
                       canMoveMappingFromIndex:fromIdx
                                       toIndex:toIdx]) {
        return;
    }

    [self.delegate mappingsViewController:self moveMappingFromIndex:fromIdx toIndex:toIdx];
    [self.mappingList scrollRowToVisible:toIdx];
    [self.mappingList selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)toIdx]
                 byExtendingSelection:NO];
}

- (IBAction)moveDownClicked:(id)sender {
    NSInteger fromIdx = self.mappingList.selectedRow;
    NSInteger toIdx = fromIdx + 1;
    if (![self.delegate mappingsViewController:self
                       canMoveMappingFromIndex:fromIdx
                                       toIndex:toIdx]) {
        return;
    }

    [self.delegate mappingsViewController:self moveMappingFromIndex:fromIdx toIndex:toIdx];
    [self.mappingList scrollRowToVisible:toIdx];
    [self.mappingList selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)toIdx]
                 byExtendingSelection:NO];
}

- (IBAction)mappingTriggerClicked:(id)sender {
    [self updateMappingPopoverSize];

    if (@available(macOS 14.0, *)) {
        if ([sender isKindOfClass:NSToolbarItem.class]) {
            [self.mappingListPopover showRelativeToToolbarItem:(NSToolbarItem *)sender];
            return;
        }
    }

    NSView *anchorView = [sender isKindOfClass:NSView.class] ? sender : self.mappingPopoverAnchorView;
    if (!anchorView)
        return;
    [self.mappingListPopover showRelativeToRect:anchorView.bounds
                                         ofView:anchorView
                                  preferredEdge:NSMaxYEdge];
}

- (void)beginUpdates {
    [self.mappingList beginUpdates];
}

- (void)endUpdates {
    [self.mappingList endUpdates];
    [self changedActiveMappingToIndex:self.mappingList.selectedRow];
    [self updateMappingPopoverSize];
}

- (void)addedMappingAtIndex:(NSInteger)index startEditing:(BOOL)startEditing {
    [self.mappingList abortEditing];
    [self.mappingList insertRowsAtIndexes:[[NSIndexSet alloc] initWithIndex:index]
                            withAnimation:startEditing ? 0 : NSTableViewAnimationSlideLeft];
    [self updateMappingPopoverSize];
    if (startEditing) {
        id anchor = self.mappingToolbarItem;
        if (!anchor)
            anchor = self.mappingPopoverAnchorView;
        [self mappingTriggerClicked:anchor];
        [self.mappingList editColumn:0 row:index withEvent:nil select:YES];
        [self.mappingList scrollRowToVisible:index];
    }
}

- (void)removedMappingAtIndex:(NSInteger)index {
    [self.mappingList abortEditing];
    [self.mappingList removeRowsAtIndexes:[[NSIndexSet alloc] initWithIndex:index]
                            withAnimation:NSTableViewAnimationEffectFade];
    [self updateMappingPopoverSize];
}

- (void)changedActiveMappingToIndex:(NSInteger)index {
    NSInteger count = [self.delegate numberOfMappings:self];
    if (index < 0 || index >= count) {
        self.removeMapping.enabled = NO;
        self.moveUp.enabled = NO;
        self.moveDown.enabled = NO;
        return;
    }

    self.removeMapping.enabled = [self.delegate mappingsViewController:self
                                               canRemoveMappingAtIndex:index];
    self.moveUp.enabled = index > 0 &&
        [self.delegate mappingsViewController:self canMoveMappingFromIndex:index toIndex:index - 1];
    self.moveDown.enabled = index + 1 < count &&
        [self.delegate mappingsViewController:self canMoveMappingFromIndex:index toIndex:index + 1];
    [self.mappingList selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)index]
                 byExtendingSelection:NO];
    [self.mappingList scrollRowToVisible:index];
    [NSUserDefaults.standardUserDefaults setInteger:index forKey:@"selected"];
}

- (void)tableViewSelectionDidChange:(NSNotification *)note {
    [self.mappingList abortEditing];
    NSTableView *tableView = note.object;
    if (tableView.selectedRow >= 0) {
        [self.delegate mappingsViewController:self
                          choseMappingAtIndex:tableView.selectedRow];
    }
}

- (id)tableView:(NSTableView *)view objectValueForTableColumn:(NSTableColumn *)column row:(NSInteger)index {
    return [self.delegate mappingsViewController:self
                                 mappingForIndex:index].name;
}

- (void)tableView:(NSTableView *)view
   setObjectValue:(NSString *)obj
   forTableColumn:(NSTableColumn *)col
              row:(NSInteger)index {
    [self.delegate mappingsViewController:self
                     renameMappingAtIndex:index
                                   toName:obj];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return [self.delegate numberOfMappings:self];
}

- (BOOL)tableView:(NSTableView *)tableView
       acceptDrop:(id <NSDraggingInfo>)info
              row:(NSInteger)row
    dropOperation:(NSTableViewDropOperation)dropOperation {
    NSPasteboard *pboard = [info draggingPasteboard];
    if ([pboard.types containsObject:PB_ROW]) {
        NSString *value = [pboard stringForType:PB_ROW];
        NSInteger srcRow = [value intValue];
        row -= srcRow < row;
        [self.delegate mappingsViewController:self
                         moveMappingFromIndex:srcRow
                                      toIndex:row];
        return YES;
    } else if ([pboard.types containsObject:NSPasteboardTypeURL]) {
        NSURL *url = [NSURL URLFromPasteboard:pboard];
        NSError *error = nil;
        if (![self.delegate mappingsViewController:self
                              importMappingFromURL:url
                                           atIndex:row
                                             error:&error]) {
            [tableView presentError:error];
            return NO;
        } else {
            return YES;
        }
    } else {
        return NO;
    }
}

- (NSDragOperation)tableView:(NSTableView *)tableView
                validateDrop:(id <NSDraggingInfo>)info
                 proposedRow:(NSInteger)row
       proposedDropOperation:(NSTableViewDropOperation)dropOperation {
    NSPasteboard *pboard = [info draggingPasteboard];
    if ([pboard.types containsObject:PB_ROW]) {
        [tableView setDropRow:MAX(0, row) dropOperation:NSTableViewDropAbove];
        return NSDragOperationMove;
    } else if ([pboard.types containsObject:NSPasteboardTypeURL]) {
        NSURL *url = [NSURL URLFromPasteboard:pboard];
        if ([url.pathExtension isEqualToString:@"enjoyable"]) {
            [tableView setDropRow:MAX(1, row) dropOperation:NSTableViewDropAbove];
            return NSDragOperationCopy;
        } else {
            return NSDragOperationNone;
        }
    } else {
        return NSDragOperationNone;
    }
}

// Moderne Drag & Drop Unterstützung mit NSFilePromiseProvider (ab macOS 10.13)
- (id<NSPasteboardWriting>)tableView:(NSTableView *)tableView pasteboardWriterForRow:(NSInteger)row {
    NJMapping *mapping = [self.delegate mappingsViewController:self mappingForIndex:row];
    NSString *safeName = [mapping.name stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    NSString *filename = [safeName stringByAppendingPathExtension:@"enjoyable"];
    NSFilePromiseProvider *provider = [[NSFilePromiseProvider alloc] initWithFileType:@"de.slsoft.Enjoyable" delegate:self];
    provider.userInfo = @{@"mapping": mapping, @"filename": filename};
    return provider;
}

- (void)filePromiseProvider:(NSFilePromiseProvider *)filePromiseProvider
         writePromiseToURL:(NSURL *)url
         completionHandler:(void (^)(NSError * _Nullable))completionHandler {
    NJMapping *mapping = filePromiseProvider.userInfo[@"mapping"];
    NSString *filename = filePromiseProvider.userInfo[@"filename"];
    NSURL *dst = [url URLByAppendingPathComponent:filename];
    NSError *error = nil;
    [mapping writeToURL:dst error:&error];
    completionHandler(error);
}

- (nonnull NSString *)filePromiseProvider:(nonnull NSFilePromiseProvider *)filePromiseProvider fileNameForType:(nonnull NSString *)fileType { 
    return filePromiseProvider.userInfo[@"filename"];
}

- (void)reloadData {
    [self.mappingList reloadData];
    [self updateMappingPopoverSize];
}


- (BOOL)commitEditingAndReturnError:(NSError *__autoreleasing  _Nullable * _Nullable)error {
    if ([self.mappingList commitEditing]) {
        return YES;
    } else {
        if (error) {
            *error = [NSError errorWithDomain:NSCocoaErrorDomain
                                         code:NSUserCancelledError
                                     userInfo:@{NSLocalizedDescriptionKey: @"Bearbeitung konnte nicht abgeschlossen werden."}];
        }
        return NO;
    }
}

- (void)encodeWithCoder:(nonnull NSCoder *)coder {
    [coder encodeObject:self.mappingList forKey:@"mappingList"];
    [coder encodeObject:self.mappingListPopover forKey:@"mappingListPopover"];
    [coder encodeObject:self.removeMapping forKey:@"removeMapping"];
    [coder encodeObject:self.moveUp forKey:@"moveUp"];
    [coder encodeObject:self.moveDown forKey:@"moveDown"];
    // Füge weitere Properties hinzu, falls nötig
}

@end
