//
//  ViewController.h
//  HIDDenial
//
//  Created by Komachin on 11/04/2021.
//

#import <Cocoa/Cocoa.h>

@interface ViewController : NSViewController

@property (weak) IBOutlet NSTableView *HIDDeviceTableView;
@property (weak) IBOutlet NSButton *denyAnyNewHIDDeviceCheckBox;
@property (weak) IBOutlet NSPopUpButton *defaultPolicy;

@end

