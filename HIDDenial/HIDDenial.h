//
//  HIDDenial.h
//  HIDDenial
//
//  Created by Komachin on 11/04/2021.
//

#import <Foundation/Foundation.h>
#import "HIDDeviceData.h"

NS_ASSUME_NONNULL_BEGIN

typedef enum : NSUInteger {
    Allow = 100,
    AskEverytime = 200,
    Deny = 300,
} HIDDenialPolicy;

@protocol HIDDenialDelegate <NSObject>

- (HIDDenialPolicy)HIDDeviceAdded:(HIDDeviceData *)dev;
- (void)HIDDeviceRemoved:(HIDDeviceData *)dev;

@end

@interface HIDDenial : NSObject
+ (instancetype)sharedInstance;
- (BOOL)startWithDefaultPolicy:(HIDDenialPolicy)policy Error:(NSError **)err;
- (void)stop;
- (void)allowDevice:(HIDDeviceData *)dev;
- (void)denyDevice:(HIDDeviceData *)dev;

@property (weak) id<HIDDenialDelegate> delegate;
@end

NS_ASSUME_NONNULL_END
