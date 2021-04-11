//
//  AppDelegate.m
//  HIDDenial
//
//  Created by Komachin on 11/04/2021.
//

#import "AppDelegate.h"

@interface AppDelegate ()


@end

@implementation AppDelegate

- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)flag {
    if (!flag) {
        for (id window in sender.windows) {
            [window makeKeyAndOrderFront:self];
        }
    }
    return YES;
}


@end
