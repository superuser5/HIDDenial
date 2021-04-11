//
//  HIDDeviceTableCellView.m
//  HIDDenial
//
//  Created by Komachin on 11/04/2021.
//

#import "HIDDeviceTableCellView.h"

@implementation HIDDeviceTableCellView

- (void)viewDidAppear {
    if (self.policy.tag != 400) {
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(popUpSelectionChanged:)
                                                     name:NSMenuDidSendActionNotification
                                                   object:[[self policy] menu]];
        self.policy.tag = 400;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.vendorID setStringValue:[NSString stringWithFormat:@"Vendor: 0x%04x", self.dev.vendorID]];
        [self.productID setStringValue:[NSString stringWithFormat:@"Product: 0x%04x", self.dev.productID]];
        [self.deviceIndex setStringValue:[NSString stringWithFormat:@"Index: %ld", self.dev.deviceset_index]];
        if (self.dev.name) {
            [self.deviceName setStringValue:self.dev.name];
        }
        if (self.dev.manufacturer) {
            [self.manufacturer setStringValue:[NSString stringWithFormat:@"Manufacturer: %@", self.dev.manufacturer]];
        }
        
        NSInteger selectTag = 0;
        switch (self.dev.policy) {
            case Allow:
                selectTag = 0;
                break;
            case AskEverytime:
                selectTag = 1;
                break;
            default:
                selectTag = 2;
                break;
        }
        [self.policy selectItemAtIndex:selectTag];
    });
}

- (void)popUpSelectionChanged:(NSNotification *)noti {
    HIDDenialPolicy newPolicy;
    switch (self.policy.indexOfSelectedItem) {
        case 0:
            newPolicy = Allow;
            break;
        case 1:
            newPolicy = AskEverytime;
            break;
        default:
            newPolicy = Deny;
            break;
    }
    if (newPolicy != self.dev.policy) {
        [self.delegate updatePolicy:newPolicy ForDevice:self.dev];
    }
}

@end
