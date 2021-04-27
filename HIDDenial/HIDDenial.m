//
//  HIDDenial.m
//  HIDDenial
//
//  Created by Komachin on 11/04/2021.
//

#import "HIDDenial.h"
#import <IOKit/usb/IOUSBLib.h>
#import <IOKit/hid/IOHIDManager.h>
#import <IOKit/hid/IOHIDKeys.h>
#import "HIDDenialUtils.h"

static HIDDenial * instance = nil;

@interface HIDDenial() {
    mach_port_t masterPort;
    IONotificationPortRef ioNotifyPort;
    CFMutableDictionaryRef matchingDict;
    CFRunLoopSourceRef runLoopSource;
    io_iterator_t rawAddedIter;
    io_iterator_t rawRemovedIter;
    
    BOOL started;
    HIDDenialPolicy globalDefalutPolicy;
}

- (HIDDenialPolicy)addedHIDDevice:(HIDDeviceData *)dev;
- (void)removedHIDDevice:(HIDDeviceData *)dev;
@end

@interface ContinuousHIDWatching : NSObject {
    NSMutableArray<HIDDeviceData *> * subdevices;
    NSMutableArray<NSString *> * seenDevices;
    NSString * name;
    NSString * manufacturer;
    IOHIDManagerRef ioHIDManager;
    NSLock * hidLock;
    BOOL stop;
}

- (void)setDeviceName:(const char*)name manufacturer:(const char*)manufacturer;
- (void)startMonitoringDevice:(IOUSBDeviceInterface**)dev Vendor:(UInt16)vendor product:(UInt16)product;

@end

@implementation ContinuousHIDWatching

- (void)stop {
    if (ioHIDManager) {
        [hidLock lock];
        // Close the HID manager
        IOHIDManagerClose(ioHIDManager, kIOHIDOptionsTypeNone);
        CFRelease(ioHIDManager);
        ioHIDManager = NULL;
        stop = YES;
        [hidLock unlock];
    }
}

- (void)dealloc {
    [self stop];
}

- (void)setDeviceName:(const char*)name manufacturer:(const char*)manufacturer {
    if (name) {
        self->name = [NSString stringWithFormat:@"%s", name];
    }
    if (manufacturer) {
        self->manufacturer = [NSString stringWithFormat:@"%s", manufacturer];
    }
}

- (void)startMonitoringDevice:(IOUSBDeviceInterface**)dev Vendor:(UInt16)vendor product:(UInt16)product {
    // Try to match HID S by vendor ID and product ID
    CFMutableDictionaryRef matching = CFDictionaryCreateMutable(kCFAllocatorDefault,
                                                                kIOHIDOptionsTypeNone,
                                                                &kCFTypeDictionaryKeyCallBacks,
                                                                &kCFTypeDictionaryValueCallBacks);
    CFNumberRef v = CFNumberCreate(kCFAllocatorDefault, kCFNumberShortType, &vendor);
    CFDictionarySetValue(matching, CFSTR(kIOHIDVendorIDKey), v);
    CFRelease(v);
    CFNumberRef p = CFNumberCreate(kCFAllocatorDefault, kCFNumberShortType, &product);
    CFDictionarySetValue(matching, CFSTR(kIOHIDProductIDKey), p);
    CFRelease(p);
    
    dispatch_async(dispatch_queue_create(NULL, NULL), ^{
        // Create an IO HID manager
        IOHIDManagerRef hidMgr = IOHIDManagerCreate(kCFAllocatorDefault, kIOHIDOptionsTypeNone);
        if (hidMgr) {
            self->ioHIDManager = hidMgr;
            IOHIDManagerScheduleWithRunLoop(hidMgr, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
        } else {
            printf("Cannot create ioHIDManager\n");
            return;
        }
        self->seenDevices = [NSMutableArray new];
        self->hidLock = [[NSLock alloc] init];
        self->stop = NO;
        
        while (!self->stop) {
            // sleep 100ms
            usleep(1000 * 100);
            CFRetain(matching);
            
            [self->hidLock lock];
            IOHIDManagerSetDeviceMatching(hidMgr, matching);
            if (matching != NULL) {
                CFRelease(matching);
            }
            
            // Get devices
            CFSetRef device_set = IOHIDManagerCopyDevices(hidMgr);
            if (device_set != NULL) {
                // Iterate over each device
                CFIndex num_devices = CFSetGetCount(device_set);
                IOHIDDeviceRef *device_array = (IOHIDDeviceRef*) calloc(num_devices, sizeof(IOHIDDeviceRef));
                CFSetGetValues(device_set, (const void **)device_array);
                for (NSUInteger i = self->seenDevices.count; i < num_devices; i++) {
                    IOHIDDeviceRef devref = device_array[i];
                    if (!devref) {
                        continue;
                    }
                    
                    HIDDeviceData * device_data = [[HIDDeviceData alloc] init];
                    device_data.vendorID = vendor;
                    device_data.productID = product;
                    device_data.deviceset_index = i;
                    device_data.name = self->name;
                    device_data.manufacturer = self->manufacturer;
                    
                    NSString * uniqueID = [NSString stringWithFormat:@"%04x-%04x-%lu", vendor, product, (unsigned long)i];
                    [self->seenDevices addObject:uniqueID];
                    
                    io_object_t iokit_dev = IOHIDDeviceGetService(devref);
                    io_string_t path;
                    kern_return_t res = IORegistryEntryGetPath(iokit_dev, kIOServicePlane, path);
                    if (res == KERN_SUCCESS) {
                        memcpy(*[device_data getPathRef], path, sizeof(path));
                        device_data.servicePath = [NSString stringWithFormat:@"%s", path];
                    } else {
                        fprintf(stderr, "Cannot get device path: vendor 0x%04x, product 0x%04x\n", vendor, product);
                    }
                    
                    int is_usb_hid = get_int_property(devref, CFSTR(kUSBInterfaceClass)) == kUSBHIDClass;
                    if (is_usb_hid) {
                        device_data.usbdev = dev;
                        dispatch_async(dispatch_get_main_queue(), ^{
                            HIDDenialPolicy policy = [instance addedHIDDevice:device_data];
                            device_data.policy = policy;
                            if (policy != Allow) {
                                [instance denyDevice:device_data];
                            }
                        });
                    }
                }
                
                free(device_array);
                CFRelease(device_set);
                
                [self->hidLock unlock];
            }
        }
    });
}

@end

void HIDRawDeviceAdded(void *refCon, io_iterator_t iterator) {
    kern_return_t               kr;
    io_service_t                usbDevice;
    IOCFPlugInInterface         **plugInInterface = NULL;
    IOUSBDeviceInterface        **dev = NULL;
    
    HRESULT                     result;
    SInt32                      score;
    UInt16                      vendor;
    UInt16                      product;
    
    while ((usbDevice = IOIteratorNext(iterator))) {
        // Reset to NULL
        plugInInterface = NULL;
        // Create an intermediate plug-in
        kr = IOCreatePlugInInterfaceForService(usbDevice,
                                               kIOUSBDeviceUserClientTypeID,
                                               kIOCFPlugInInterfaceID,
                                               &plugInInterface,
                                               &score);
        // Don’t need the device object after intermediate plug-in is created
        kr = IOObjectRelease(usbDevice);
        if ((kIOReturnSuccess != kr) || !plugInInterface) {
            fprintf(stderr, "Unable to create a plug-in (%08x)\n", kr);
            continue;
        }
        
        // Now create the device interface
        result = (*plugInInterface)->QueryInterface(plugInInterface,
                                                    CFUUIDGetUUIDBytes(kIOUSBDeviceInterfaceID),
                                                    (LPVOID *)&dev);
        // Don't need the intermediate plug-in after device interface is created
        (*plugInInterface)->Release(plugInInterface);
        if (result || !dev) {
            fprintf(stderr, "Couldn't create a device interface (%08x)\n", (int)result);
            continue;
        }
        
        // Get vendor ID and product ID
        kr = (*dev)->GetDeviceVendor(dev, &vendor);
        kr = (*dev)->GetDeviceProduct(dev, &product);
        
        // Get name and manufacturer
        UInt8 nameIndex, manufacturerIndex;
        kr = (*dev)->USBGetProductStringIndex(dev, &nameIndex);
        kr = (*dev)->USBGetManufacturerStringIndex(dev, &manufacturerIndex);
        const char * name, * manufacturer;
        name = getUSBStringDescriptor(dev, nameIndex);
        manufacturer = getUSBStringDescriptor(dev, manufacturerIndex);
        
        ContinuousHIDWatching * watching = [[ContinuousHIDWatching alloc] init];
        [watching setDeviceName:name manufacturer:manufacturer];
        [watching startMonitoringDevice:dev Vendor:vendor product:product];

        if (name) free((void *)name);
        if (manufacturer) free((void *)manufacturer);
    }
}

void HIDRawDeviceRemoved(void *refCon, io_iterator_t iterator) {
    kern_return_t kr;
    io_service_t object;
 
    while ((object = IOIteratorNext(iterator))) {
        kr = IOObjectRelease(object);
        if (kr != kIOReturnSuccess) {
            fprintf(stderr, "Couldn’t release raw device object: %08x: %s\n", kr, mach_error_string(kr));
            continue;
        }
    }
}

@implementation HIDDenial
@synthesize delegate;

+ (instancetype)sharedInstance {
    if (instance == nil) {
        instance = [[HIDDenial alloc] init];
        instance->started = NO;
    }
    return instance;
}

- (BOOL)startWithDefaultPolicy:(HIDDenialPolicy)policy Error:(NSError **)err {
    if (started) {
        return YES;
    }
    
    kern_return_t kr;
    // Create a master port for communication with the I/O Kit
    kr = IOMasterPort(MACH_PORT_NULL, &masterPort);
    if (kr || !masterPort) {
        if (err) {
            *err = [NSError errorWithDomain:NSCocoaErrorDomain code:1 userInfo:@{
                NSDebugDescriptionErrorKey: [NSString stringWithFormat:@"Couldn’t create a master I/O Kit port(%08x): %s", kr, mach_error_string(kr)]
            }];
        }
        return NO;
    }
    
    // Set up matching dictionary for class IOUSBDevice and its subclasses
    matchingDict = IOServiceMatching(kIOUSBDeviceClassName);
    if (!matchingDict)
    {
        if (err) {
            *err = [NSError errorWithDomain:NSCocoaErrorDomain code:1 userInfo:@{
                NSDebugDescriptionErrorKey: @"Couldn’t create a USB matching dictionary"
            }];
        }
        mach_port_deallocate(mach_task_self(), masterPort);
        masterPort = 0;
        return NO;
    }
    
    ioNotifyPort = IONotificationPortCreate(masterPort);
    runLoopSource = IONotificationPortGetRunLoopSource(ioNotifyPort);
    
    CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, kCFRunLoopDefaultMode);
    
    // Retain additional dictionary references because each call to
    // IOServiceAddMatchingNotification consumes one reference
    matchingDict = (CFMutableDictionaryRef) CFRetain(matchingDict);
    matchingDict = (CFMutableDictionaryRef) CFRetain(matchingDict);
    matchingDict = (CFMutableDictionaryRef) CFRetain(matchingDict);
    
    // Now set up two notifications: one to be called when a raw device
    // is first matched by the I/O Kit and another to be called when the
    // device is terminated
    // Notification of first match
    kr = IOServiceAddMatchingNotification(ioNotifyPort,
                                          kIOFirstMatchNotification,
                                          matchingDict,
                                          HIDRawDeviceAdded,
                                          NULL,
                                          &rawAddedIter);
    // Iterate over set of matching devices to access already-present devices
    // and to arm the notification
    HIDRawDeviceAdded(NULL, rawAddedIter);
    
    // Notification of termination
    kr = IOServiceAddMatchingNotification(ioNotifyPort,
                                          kIOTerminatedNotification,
                                          matchingDict,
                                          HIDRawDeviceRemoved,
                                          NULL,
                                          &rawRemovedIter);
    // Iterate over set of matching devices to release each one and to
    // arm the notification
    HIDRawDeviceRemoved(NULL, rawRemovedIter);
    
    
    // Finished with master port
    mach_port_deallocate(mach_task_self(), masterPort);
    masterPort = 0;
    
    started = YES;
    globalDefalutPolicy = policy;
    return YES;
}

- (void)stop {
    if (!started) return;
    
    CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, kCFRunLoopDefaultMode);
    started = NO;
}

- (void)allowDevice:(HIDDeviceData *)dev {
    if (dev.hiddev == NULL) return;
    
    IOHIDDeviceRegisterInputReportCallback(dev.hiddev,
                                           dev.buf,
                                           dev.max_report_len,
                                           NULL,
                                           dev.usbdev);
    IOHIDDeviceRegisterRemovalCallback(dev.hiddev, NULL, dev.usbdev);
    IOHIDDeviceClose(dev.hiddev, kIOHIDOptionsTypeSeizeDevice);

    dev.hiddev = NULL;
}

- (void)denyDevice:(HIDDeviceData *)dev {
    if (dev.hiddev != NULL) return;
    
    io_registry_entry_t entry = MACH_PORT_NULL;
    IOReturn ret = kIOReturnInvalid;
    
    entry = IORegistryEntryFromPath(kIOMasterPortDefault, *[dev getPathRef]);
    if (entry == MACH_PORT_NULL) {
        fprintf(stderr, "Cannot create IORegistryEntry from path: %s\n", *[dev getPathRef]);
        return;
    }
    
    dev.hiddev = IOHIDDeviceCreate(kCFAllocatorDefault, entry);
    if (dev.hiddev == NULL) {
        fprintf(stderr, "Cannot create IOHIDDevice for vendor 0x%04x, product 0x%04x\n", dev.vendorID, dev.productID);
        return;
    }
    
    ret = IOHIDDeviceOpen(dev.hiddev, kIOHIDOptionsTypeSeizeDevice);
    if (ret == kIOReturnSuccess) {
        dev.max_report_len = get_int_property(dev.hiddev, CFSTR(kIOHIDMaxInputReportSizeKey));
        if (dev.buf != NULL) {
            free(dev.buf);
        }
        dev.buf = calloc(dev.max_report_len, sizeof(uint8_t));
        IOHIDDeviceRegisterInputReportCallback(dev.hiddev,
                                               dev.buf,
                                               dev.max_report_len,
                                               &hid_report_callback,
                                               dev.usbdev);
        IOHIDDeviceRegisterRemovalCallback(dev.hiddev, hid_device_removal_callback, dev.usbdev);
        IOObjectRelease(entry);
    } else {
        fprintf(stderr, "Cannot open IOHIDDevice for vendor 0x%04x, product 0x%04x: %s\n", dev.vendorID, dev.productID, mach_error_string(ret));
    }
}

- (HIDDenialPolicy)addedHIDDevice:(HIDDeviceData *)dev {
    if (self.delegate) {
        return [self.delegate HIDDeviceAdded:dev];
    }
    return Allow;
}

- (void)removedHIDDevice:(HIDDeviceData *)dev {
    if (self.delegate) {
        [self.delegate HIDDeviceRemoved:dev];
    }
}

@end

