//
//  ViewController.m
//  HIDDenial
//
//  Created by Komachin on 11/04/2021.
//

#import "ViewController.h"
#import "HIDDenial.h"
#import "HIDDeviceData.h"
#import "HIDDeviceTableCellView.h"
#import <unistd.h>

extern const char** NXArgv;

@interface ViewController() <NSTableViewDataSource, NSTableViewDelegate, HIDDenialDelegate, HIDDeviceTableCellDelegate>
@property (strong, atomic) NSMutableArray<HIDDeviceData *> * devices;
@end

@implementation ViewController
@synthesize HIDDeviceTableView;

- (void)viewDidLoad {
    [super viewDidLoad];
		[self checkPermission];

    self.devices = [NSMutableArray new];
    [self.HIDDeviceTableView setDataSource:self];
    [self.HIDDeviceTableView setDelegate:self];
    
    NSUserDefaults * defaults = [NSUserDefaults standardUserDefaults];
    NSUInteger val = [[defaults valueForKey:@"global_default_policy"] unsignedIntegerValue];
    NSInteger selectedIndex = 2;
    switch (val) {
        case Allow:
            selectedIndex = 0;
            break;
        case AskEverytime:
            selectedIndex = 1;
            break;
        default:
            break;
    }
    [self.defaultPolicy selectItemAtIndex:selectedIndex];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(popUpSelectionChanged:)
                                                 name:NSMenuDidSendActionNotification
                                               object:[[self defaultPolicy] menu]];
    
    // wait 1 sec so that the UI is shown to the user
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        NSError * error = nil;
        HIDDenial * hiddenial = [HIDDenial sharedInstance];
        [hiddenial setDelegate:self];
        if ([hiddenial startWithDefaultPolicy:Deny Error:&error]) {
            if (error) {
                NSAlert *alert = [[NSAlert alloc] init];
                [alert addButtonWithTitle:@"OK"];
                [alert setMessageText:@"Error"];
                [alert setInformativeText:error.debugDescription];
                [alert setAlertStyle:NSAlertStyleCritical];
                [alert runModal];
            }
        }
    });
}

- (void)checkPermission {
    uid_t uid = getuid();
    if (uid != 0) {
        NSString * command = [NSString stringWithFormat:@"sudo %s", NXArgv[0]];
        NSAlert *alert = [[NSAlert alloc] init];
        [alert addButtonWithTitle:@"Copy and Exit"];
        [alert addButtonWithTitle:@"Ignore and Continue"];
        [alert setMessageText:[NSString stringWithFormat:@"HIDDenial is not running with correct permissions. Please copy the following command and run HIDDenial as root:\n%@", command]];
        [alert setAlertStyle:NSAlertStyleCritical];
        if ([alert runModal] == 1000) {
            NSPasteboard * pasteboard = [NSPasteboard generalPasteboard];
            [pasteboard declareTypes:@[NSPasteboardTypeString] owner:nil];
            [pasteboard setString:command forType:NSPasteboardTypeString];
            [NSApp terminate:nil];
        }
    }
}

- (HIDDenialPolicy)getDefaultPolicyFromPopUp {
    NSInteger selected = [self.defaultPolicy indexOfSelectedItem];
    HIDDenialPolicy policy;
    switch (selected) {
        case 0:
            policy = Allow;
            break;
        case 1:
            policy = AskEverytime;
            break;
        default:
            policy = Deny;
            break;
    }
    return policy;
}

- (HIDDenialPolicy)getDefaultPolicy:(HIDDeviceData *)dev Global:(BOOL*)is_global {
    NSUserDefaults * defaults = [NSUserDefaults standardUserDefaults];
    NSString * key = dev.servicePath;
    if (key.length == 0) {
        key = [NSString stringWithFormat:@"0x%04x,0x%04x,%ld", dev.vendorID, dev.productID, dev.deviceset_index];
    } else {
        key = [key stringByAppendingFormat:@",%ld", dev.deviceset_index];
    }
    
    NSUInteger val = [[defaults valueForKey:key] unsignedIntegerValue];
    if (val == Allow) {
        return Allow;
    } else if (val == AskEverytime) {
        return AskEverytime;
    } else if (val == Deny) {
        return Deny;
    } else {
        if (is_global) *is_global = YES;
        return [self getDefaultPolicyFromPopUp];
    }
}

- (void)popUpSelectionChanged:(NSNotification *)noti {
    HIDDenialPolicy policy = [self getDefaultPolicyFromPopUp];
    NSUserDefaults * defaults = [NSUserDefaults standardUserDefaults];
    [defaults setValue:@(policy) forKey:@"global_default_policy"];
}

#pragma mark -
#pragma mark NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return self.devices.count;
}

- (NSTableRowView *)tableView:(NSTableView *)tableView rowViewForRow:(NSInteger)row {
    return [tableView rowViewAtRow:row makeIfNecessary:YES];
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    HIDDeviceTableCellView * cell = [tableView makeViewWithIdentifier:@"hiddevicerow" owner:self];
    [cell setDev:[self.devices objectAtIndex:row]];
    [cell setDelegate:self];
    [cell viewDidAppear];
    return cell;
}

- (CGFloat)tableView:(NSTableView *)tableView heightOfRow:(NSInteger)row {
    return 80.0f;
}

#pragma mark -
#pragma mark HIDDenialDelegate

- (HIDDenialPolicy)HIDDeviceAdded:(HIDDeviceData *)dev {
    HIDDenialPolicy policy;
    BOOL is_global;
    for (HIDDeviceData * data in self.devices) {
        if ([data.servicePath isEqualToString:dev.servicePath]) {
            if (data.deviceset_index == dev.deviceset_index) {
                policy = [self getDefaultPolicy:dev Global:&is_global];
                break;
            }
        }
    }
    
    [self.devices addObject:dev];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.HIDDeviceTableView reloadData];
    });
    
    if ([self.denyAnyNewHIDDeviceCheckBox state] == NSControlStateValueOn) {
        return Deny;
    }

    policy = [self getDefaultPolicy:dev Global:&is_global];
    
    if (policy == AskEverytime) {
        NSAlert *alert = [[NSAlert alloc] init];
        [alert addButtonWithTitle:@"Allow"];
        [alert addButtonWithTitle:@"Deny"];
        [alert setMessageText:@"Alert"];
        [alert setInformativeText:[NSString stringWithFormat:@"Detect new HID device, '%@', (Vendor 0x%04x, Product 0x%04x)\nManufacturer: %@, Index: %ld", dev.name, dev.vendorID, dev.productID, dev.manufacturer, dev.deviceset_index]];
        [alert setAlertStyle:NSAlertStyleCritical];
        dispatch_async(dispatch_get_main_queue(), ^{
            NSInteger selected = [alert runModal];
            if (selected == 1000) {
                dev.policy = Allow;
                [[HIDDenial sharedInstance] allowDevice:dev];
                if (!is_global) {
                    dev.policy = AskEverytime;
                }
            }
        });
        dev.policy = Deny;
        return Deny;
    }
    
    return policy;
}

- (void)HIDDeviceRemoved:(HIDDeviceData *)dev {
    for (NSUInteger i = 0; i < self.devices.count; i++) {
        HIDDeviceData * device = self.devices[i];
        if ([device.servicePath isEqualToString:dev.servicePath]) {
            [self.devices removeObjectAtIndex:i];
            break;
        }
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.HIDDeviceTableView reloadData];
    });
}

#pragma mark -
#pragma mark HIDDeviceTableCellDelegate

- (void)updatePolicy:(HIDDenialPolicy)policy ForDevice:(HIDDeviceData *)dev {
    NSUserDefaults * defaults = [NSUserDefaults standardUserDefaults];
    NSString * key = dev.servicePath;
    if (key.length == 0) {
        key = [NSString stringWithFormat:@"0x%04x,0x%04x,%ld", dev.vendorID, dev.productID, dev.deviceset_index];
    } else {
        key = [key stringByAppendingFormat:@",%ld", dev.deviceset_index];
    }
    [defaults setInteger:policy forKey:key];
    dev.policy = policy;
    
    HIDDenial * denial = [HIDDenial sharedInstance];
    if (policy == Deny) {
        [denial denyDevice:dev];
    } else if (policy == Allow) {
        [denial allowDevice:dev];
    }
}

@end
