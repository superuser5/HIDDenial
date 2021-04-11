//
//  HIDDenialUtils.c
//  HIDDenial
//
//  Created by Komachin on 11/04/2021.
//

#include "HIDDenialUtils.h"

int32_t get_int_property(IOHIDDeviceRef device, CFStringRef key) {
    CFTypeRef ref;
    int32_t value;

    ref = IOHIDDeviceGetProperty(device, key);
    if (ref) {
        if (CFGetTypeID(ref) == CFNumberGetTypeID()) {
            CFNumberGetValue((CFNumberRef) ref, kCFNumberSInt32Type, &value);
            return value;
        }
    }
    return 0;
}

void hid_report_callback(void *context, IOReturn result, void *sender,
                         IOHIDReportType report_type, uint32_t report_id,
                                uint8_t *report, CFIndex report_length) {
    
}

void hid_device_removal_callback(void *context, IOReturn result,
                                        void *sender) {
    
}

// https://oroboro.com/usb-serial-number-osx/
const char * getUSBStringDescriptor(IOUSBDeviceInterface ** usbDevice, UInt8 idx) {
    if (usbDevice == NULL) return NULL;
    UInt16 buffer[64];

    // wow... we're actually forced to make hard coded bus requests. Its like
    // hard disk programming in the 80's!
    IOUSBDevRequest request;

    request.bmRequestType = USBmakebmRequestType(kUSBIn,
                                                 kUSBStandard,
                                                 kUSBDevice);
    request.bRequest = kUSBRqGetDescriptor;
    request.wValue = (kUSBStringDesc << 8) | idx;
    request.wIndex = 0x409; // english
    request.wLength = sizeof( buffer );
    request.pData = buffer;

    kern_return_t err = (*usbDevice)->DeviceRequest( usbDevice, &request );
    if ( err != 0 )
    {
       // the request failed... fairly uncommon for the USB disk driver, but not
       // so uncommon for other devices. This can also be less reliable if your
       // disk is mounted through an external USB hub. At this level we actually
       // have to worry about hardware issues like this.
       return NULL;
    }
 
    // be careful
    uint32_t count = ( request.wLenDone - 1 ) / 2;
    if (count > 256) {
        count = 256;
    }
    if (count == 0) return NULL;
    
    char * string = malloc(count);
    uint32_t i;
    for (i = 0; i < count; i++) {
        string[i] = buffer[i+1];
    }
    string[i] = '\0';

    return string;
}
