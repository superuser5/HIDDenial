//
//  HIDDeviceData.m
//  HIDDenial
//
//  Created by Komachin on 11/04/2021.
//

#import "HIDDeviceData.h"

@implementation HIDDeviceData

- (io_string_t*)getPathRef {
    return &self->path;
}

- (void)dealloc {
    if (self.usbdev) {
        (*self.usbdev)->USBDeviceClose(self.usbdev);
        (*self.usbdev)->Release(self.usbdev);
        self.usbdev = NULL;
    }
}

@end
