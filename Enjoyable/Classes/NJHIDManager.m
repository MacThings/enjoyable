#import "NJHIDManager.h"

#import <mach/mach_time.h>

// On Bluetooth the DualSense stops sending its basic input report and
// sends an "enhanced" one instead as soon as anything (GameController,
// SDL, ...) reads its feature reports. The HID descriptor only declares
// that report as an opaque vendor blob, so the stick and button elements
// never change again. Decode it here and replay it onto those elements.
enum {
    NJSonyVendorID = 0x054C,
    NJDualSenseProductID = 0x0CE6,
    NJDualSenseBasicReportID = 0x01,
    NJDualSenseEnhancedReportID = 0x31,
    NJDualSenseEnhancedReportSize = 78,
    NJDualSenseAxisCount = 6,
    NJDualSenseButtonCount = 14,
    NJDualSenseHatSlot = NJDualSenseAxisCount,
    NJDualSenseButtonSlot = NJDualSenseHatSlot + 1,
    NJDualSenseSlotCount = NJDualSenseButtonSlot + NJDualSenseButtonCount,
};

static BOOL NJIsDualSense(IOHIDDeviceRef device) {
    int vendorId = [(__bridge NSNumber *)IOHIDDeviceGetProperty(device, CFSTR(kIOHIDVendorIDKey)) intValue];
    int productId = [(__bridge NSNumber *)IOHIDDeviceGetProperty(device, CFSTR(kIOHIDProductIDKey)) intValue];
    return vendorId == NJSonyVendorID && productId == NJDualSenseProductID;
}

static int NJDualSenseSlotForElement(IOHIDElementRef element) {
    IOHIDElementType type = IOHIDElementGetType(element);
    if (!(type == kIOHIDElementTypeInput_Misc
          || type == kIOHIDElementTypeInput_Axis
          || type == kIOHIDElementTypeInput_Button))
        return -1;
    if (IOHIDElementGetReportID(element) != NJDualSenseBasicReportID)
        return -1;

    uint32_t usage = IOHIDElementGetUsage(element);
    switch (IOHIDElementGetUsagePage(element)) {
        case kHIDPage_GenericDesktop:
            switch (usage) {
                case kHIDUsage_GD_X: return 0;  // left stick
                case kHIDUsage_GD_Y: return 1;
                case kHIDUsage_GD_Z: return 2;  // right stick
                case kHIDUsage_GD_Rz: return 3;
                case kHIDUsage_GD_Rx: return 4; // L2
                case kHIDUsage_GD_Ry: return 5; // R2
                case kHIDUsage_GD_Hatswitch: return NJDualSenseHatSlot;
                default: return -1;
            }
        case kHIDPage_Button:
            return usage >= 1 && usage <= NJDualSenseButtonCount
                ? NJDualSenseButtonSlot + (int)usage - 1
                : -1;
        default:
            return -1;
    }
}

@interface NJDualSenseReportDecoder : NSObject

- (id)initWithDevice:(IOHIDDeviceRef)device manager:(NJHIDManager *)manager;
- (void)invalidate;

@property (nonatomic, readonly) IOHIDDeviceRef device;

@end

@implementation NJDualSenseReportDecoder {
    __weak NJHIDManager *_manager;
    CFArrayRef _allElements;
    IOHIDElementRef _elements[NJDualSenseSlotCount];
    CFIndex _values[NJDualSenseSlotCount];
    BOOL _hasValues;
    uint8_t _report[NJDualSenseEnhancedReportSize];
}

static void _dualSenseReport(void *ctx, IOReturn inResult, void *inSender,
                             IOHIDReportType type, uint32_t reportID,
                             uint8_t *report, CFIndex length) {
    NJDualSenseReportDecoder *self = (__bridge NJDualSenseReportDecoder *)ctx;
    if (inResult == kIOReturnSuccess
        && length >= 12
        && report[0] == NJDualSenseEnhancedReportID)
        [self decode:report];
}

- (id)initWithDevice:(IOHIDDeviceRef)device manager:(NJHIDManager *)manager {
    if ((self = [super init])) {
        _manager = manager;
        _device = (IOHIDDeviceRef)CFRetain(device);
        _allElements = IOHIDDeviceCopyMatchingElements(device, NULL, kIOHIDOptionsTypeNone);
        CFIndex count = _allElements ? CFArrayGetCount(_allElements) : 0;
        for (CFIndex i = 0; i < count; i++) {
            IOHIDElementRef element = (IOHIDElementRef)CFArrayGetValueAtIndex(_allElements, i);
            int slot = NJDualSenseSlotForElement(element);
            if (slot >= 0 && !_elements[slot])
                _elements[slot] = element;
        }
        IOHIDDeviceRegisterInputReportCallback(_device, _report, sizeof(_report),
                                               _dualSenseReport, (__bridge void *)self);
    }
    return self;
}

- (void)dealloc {
    if (_allElements)
        CFRelease(_allElements);
    CFRelease(_device);
}

- (void)invalidate {
    IOHIDDeviceRegisterInputReportCallback(_device, _report, sizeof(_report), NULL, NULL);
}

- (void)decode:(const uint8_t *)report {
    // Byte 0 is the report ID and byte 1 a sequence tag.
    CFIndex values[NJDualSenseSlotCount];
    for (int i = 0; i < NJDualSenseAxisCount; i++)
        values[i] = report[2 + i];
    values[NJDualSenseHatSlot] = report[9] & 0x0F;
    uint32_t buttons = (report[9] >> 4) | (report[10] << 4) | ((report[11] & 0x03) << 12);
    for (int i = 0; i < NJDualSenseButtonCount; i++)
        values[NJDualSenseButtonSlot + i] = (buttons >> i) & 1;

    // HID only reports changes, so the first report is just a baseline.
    if (!_hasValues) {
        memcpy(_values, values, sizeof(_values));
        _hasValues = YES;
        return;
    }

    NJHIDManager *manager = _manager;
    uint64_t timestamp = mach_absolute_time();
    for (int i = 0; i < NJDualSenseSlotCount; i++) {
        if (!_elements[i] || values[i] == _values[i])
            continue;
        _values[i] = values[i];
        IOHIDValueRef value = IOHIDValueCreateWithIntegerValue(kCFAllocatorDefault, _elements[i],
                                                               timestamp, values[i]);
        [manager.delegate HIDManager:manager valueChanged:value];
        CFRelease(value);
    }
}

@end

@implementation NJHIDManager {
    NSArray *_criteria;
    IOHIDManagerRef _manager;
    NSMutableArray *_decoders;
}

- (id)initWithCriteria:(NSArray *)criteria
              delegate:(id <NJHIDManagerDelegate>)delegate
{
    if ((self = [super init])) {
        self.criteria = criteria;
        self.delegate = delegate;
    }
    return self;
}

- (void)dealloc {
    [self stop];
}

static void _input(void *ctx, IOReturn inResult, void *inSender, IOHIDValueRef value) {
    NJHIDManager *self = (__bridge NJHIDManager *)ctx;
    [self.delegate HIDManager:self valueChanged:value];
}

static void _add(void *ctx, IOReturn inResult, void *inSender, IOHIDDeviceRef device) {
    NJHIDManager *self = (__bridge NJHIDManager *)ctx;
    [self.delegate HIDManager:self deviceAdded:device];
    IOHIDDeviceRegisterInputValueCallback(device, _input, ctx);
    if (NJIsDualSense(device)) {
        if (!self->_decoders)
            self->_decoders = [[NSMutableArray alloc] init];
        [self->_decoders addObject:[[NJDualSenseReportDecoder alloc] initWithDevice:device
                                                                            manager:self]];
    }
}

static void _remove(void *ctx, IOReturn inResult, void *inSender, IOHIDDeviceRef device) {
    NJHIDManager *self = (__bridge NJHIDManager *)ctx;
    for (NJDualSenseReportDecoder *decoder in [self->_decoders copy]) {
        if (decoder.device == device) {
            [decoder invalidate];
            [self->_decoders removeObject:decoder];
        }
    }
    [self.delegate HIDManager:self deviceRemoved:device];
}

- (void)start {
    if (self.running)
        return;
    IOHIDManagerRef manager = IOHIDManagerCreate(kCFAllocatorDefault, kIOHIDOptionsTypeNone);
    IOHIDManagerSetDeviceMatchingMultiple(manager, (__bridge CFArrayRef)self.criteria);
    IOReturn ret = IOHIDManagerOpen(manager, kIOHIDOptionsTypeNone);
    if (ret != kIOReturnSuccess) {
        NSError *error = [NSError errorWithDomain:NSMachErrorDomain code:ret userInfo:nil];
        IOHIDManagerClose(manager, kIOHIDOptionsTypeNone);
        CFRelease(manager);
        [self.delegate HIDManager:self didError:error];
        NSLog(@"Error starting HID manager: %@.", error);
    } else {
        _manager = manager;
        IOHIDManagerScheduleWithRunLoop(_manager, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
        IOHIDManagerRegisterDeviceMatchingCallback(_manager, _add, (__bridge void *)self);
        IOHIDManagerRegisterDeviceRemovalCallback(_manager, _remove, (__bridge void *)self);
        [self.delegate HIDManagerDidStart:self];
        NSLog(@"Started HID manager.");
    }
}

- (void)stop {
    if (!self.running)
        return;
    [_decoders makeObjectsPerformSelector:@selector(invalidate)];
    [_decoders removeAllObjects];
    IOHIDManagerUnscheduleFromRunLoop(_manager, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
    IOHIDManagerClose(_manager, kIOHIDOptionsTypeNone);
    CFRelease(_manager);
    _manager = NULL;
    [self.delegate HIDManagerDidStop:self];
    NSLog(@"Stopped HID manager.");
}

- (BOOL)running {
    return !!_manager;
}

- (void)setRunning:(BOOL)running {
    if (running)
        [self start];
    else
        [self stop];
}

- (NSArray *)criteria {
    return _criteria;
}

- (void)setCriteria:(NSArray *)criteria {
    if (!criteria)
        criteria = @[];
    if (![criteria isEqualToArray:_criteria]) {
        BOOL running = !!_manager;
        [self stop];
        _criteria = [criteria copy];
        if (running)
            [self start];
    }    
}

@end
