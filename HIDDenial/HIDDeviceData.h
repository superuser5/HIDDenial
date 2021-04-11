//
//  HIDDeviceData.h
//  HIDDenial
//
//  Created by Komachin on 11/04/2021.
//

#import <Foundation/Foundation.h>
#import <IOKit/usb/IOUSBLib.h>
#import <IOKit/hid/IOHIDManager.h>
#import <IOKit/hid/IOHIDKeys.h>

NS_ASSUME_NONNULL_BEGIN

@interface HIDDeviceData : NSObject {
    io_string_t path;
}
- (io_string_t*)getPathRef;

@property (assign) NSUInteger deviceset_index;
@property (assign) NSUInteger policy;
@property (assign) UInt16 vendorID;
@property (assign) UInt16 productID;
@property (strong) NSString * name;
@property (strong) NSString * manufacturer;
@property (assign) IOUSBDeviceInterface ** usbdev;
@property (assign, nullable) IOHIDDeviceRef hiddev;
@property (strong) NSString * servicePath;
@property (nonatomic) BOOL denied;
@property (assign) int max_report_len;
@property (nonatomic) uint8_t * buf;
@end

NS_ASSUME_NONNULL_END
