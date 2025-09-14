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

@interface NJMappingsViewController () <NSFilePromiseProviderDelegate>
@end

@implementation NJMappingsViewController

- (void)awakeFromNib {
    [self.mappingList registerForDraggedTypes:@[PB_ROW, NSPasteboardTypeURL, NSPasteboardTypeFileURL]];
    [self.mappingList setDraggingSourceOperationMask:NSDragOperationCopy forLocal:NO];
}

- (IBAction)addClicked:(id)sender {
    NJMapping *newMapping = [[NJMapping alloc] init];
    [self.delegate mappingsViewController:self addMapping:newMapping];
}

- (IBAction)removeClicked:(id)sender {
    [self.delegate mappingsViewController:self
                     removeMappingAtIndex:self.mappingList.selectedRow];
}

- (IBAction)moveUpClicked:(id)sender {
    NSInteger fromIdx = self.mappingList.selectedRow;
    NSInteger toIdx = fromIdx - 1;
    if (toIdx < 0) return; // Verhindert ungültigen Index
    [self.delegate mappingsViewController:self moveMappingFromIndex:fromIdx toIndex:toIdx];
    [self.mappingList scrollRowToVisible:toIdx];
    [self.mappingList selectRowIndexes:[[NSIndexSet alloc] initWithIndex:toIdx] byExtendingSelection:NO];
}

- (IBAction)moveDownClicked:(id)sender {
    NSInteger fromIdx = self.mappingList.selectedRow;
    NSInteger toIdx = fromIdx + 1;
    if (toIdx >= [self.mappingList numberOfRows]) return; // Verhindert ungültigen Index
    [self.delegate mappingsViewController:self moveMappingFromIndex:fromIdx toIndex:toIdx];
    [self.mappingList scrollRowToVisible:toIdx];
    [self.mappingList selectRowIndexes:[[NSIndexSet alloc] initWithIndex:toIdx] byExtendingSelection:NO];
}

- (IBAction)mappingTriggerClicked:(id)sender {
    [self.mappingListPopover showRelativeToRect:self.mappingListTrigger.bounds
                                         ofView:self.mappingListTrigger
                                  preferredEdge:NSMinXEdge];
    self.mappingListTrigger.state = NSControlStateValueOn;
}

- (void)popoverWillShow:(NSNotification *)notification {
    self.mappingListTrigger.state = NSControlStateValueOn;
}

- (void)popoverWillClose:(NSNotification *)notification {
    self.mappingListTrigger.state = NSControlStateValueOff;
}

- (void)beginUpdates {
    [self.mappingList beginUpdates];
}

- (void)endUpdates {
    [self.mappingList endUpdates];
    [self changedActiveMappingToIndex:self.mappingList.selectedRow];
}

- (void)addedMappingAtIndex:(NSInteger)index startEditing:(BOOL)startEditing {
    [self.mappingList abortEditing];
    [self.mappingList insertRowsAtIndexes:[[NSIndexSet alloc] initWithIndex:index]
                            withAnimation:startEditing ? 0 : NSTableViewAnimationSlideLeft];
    if (startEditing) {
        [self.mappingListTrigger performClick:self];
        [self.mappingList editColumn:0 row:index withEvent:nil select:YES];
        [self.mappingList scrollRowToVisible:index];
    }
}

- (void)removedMappingAtIndex:(NSInteger)index {
    [self.mappingList abortEditing];
    [self.mappingList removeRowsAtIndexes:[[NSIndexSet alloc] initWithIndex:index]
                            withAnimation:NSTableViewAnimationEffectFade];
}

- (void)changedActiveMappingToIndex:(NSInteger)index {
    NJMapping *mapping = [self.delegate mappingsViewController:self
                                               mappingForIndex:index];
    self.removeMapping.enabled = [self.delegate mappingsViewController:self
                                               canRemoveMappingAtIndex:index];
    self.moveUp.enabled = YES;
    self.moveDown.enabled = YES;
    self.mappingListTrigger.title = mapping.name;
    [self.mappingList selectRowIndexes:[NSIndexSet indexSetWithIndex:index] byExtendingSelection:NO];
    [self.mappingList scrollRowToVisible:index];
    [NSUserDefaults.standardUserDefaults setInteger:index forKey:@"selected"];
}

- (void)tableViewSelectionDidChange:(NSNotification *)note {
    [self.mappingList abortEditing];
    NSTableView *tableView = note.object;
    [self.delegate mappingsViewController:self
                      choseMappingAtIndex:tableView.selectedRow];
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
        NSError *error;
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
        [tableView setDropRow:MAX(1, row) dropOperation:NSTableViewDropAbove];
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
    [coder encodeObject:self.mappingListTrigger forKey:@"mappingListTrigger"];
    [coder encodeObject:self.removeMapping forKey:@"removeMapping"];
    [coder encodeObject:self.moveUp forKey:@"moveUp"];
    [coder encodeObject:self.moveDown forKey:@"moveDown"];
    // Füge weitere Properties hinzu, falls nötig
}

@end
