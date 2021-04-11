//
//  HIDDenialUtils.h
//  HIDDenial
//
//  Created by Komachin on 11/04/2021.
//

#ifndef HIDDenialUtils_h
#define HIDDenialUtils_h

#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/usb/IOUSBLib.h>
#include <IOKit/hid/IOHIDManager.h>
#include <IOKit/hid/IOHIDKeys.h>

int32_t get_int_property(IOHIDDeviceRef device, CFStringRef key);
void hid_report_callback(void *context, IOReturn result, void *sender,
                                IOHIDReportType report_type, uint32_t report_id,
                                uint8_t *report, CFIndex report_length);

void hid_device_removal_callback(void *context, IOReturn result, void *sender);
const char * getUSBStringDescriptor(IOUSBDeviceInterface ** usbDevice, UInt8 idx);

#endif /* HIDDenialUtils_h */
