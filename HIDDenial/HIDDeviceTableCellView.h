//
//  HIDDeviceTableCellView.h
//  HIDDenial
//
//  Created by Komachin on 11/04/2021.
//

#import <Cocoa/Cocoa.h>
#import "HIDDeviceData.h"
#import "HIDDenial.h"

NS_ASSUME_NONNULL_BEGIN

@protocol HIDDeviceTableCellDelegate <NSObject>

- (void)updatePolicy:(HIDDenialPolicy)policy ForDevice:(HIDDeviceData *)dev;

@end

@interface HIDDeviceTableCellView : NSTableCellView

- (void)viewDidAppear;

@property (nonatomic) HIDDeviceData * dev;
@property (weak) IBOutlet NSTextField *deviceIndex;
@property (weak) IBOutlet NSPopUpButton *policy;
@property (weak) IBOutlet NSTextField *deviceName;
@property (weak) IBOutlet NSTextField *vendorID;
@property (weak) IBOutlet NSTextField *productID;
@property (weak) IBOutlet NSTextField *manufacturer;
@property (weak) id<HIDDeviceTableCellDelegate> delegate;

@end

NS_ASSUME_NONNULL_END
