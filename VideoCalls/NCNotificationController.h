//
//  NCNotificationController.h
//  VideoCalls
//
//  Created by Ivan Sein on 23.10.18.
//  Copyright © 2018 struktur AG. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "NCPushNotification.h"

extern NSString * const NCNotificationControllerWillPresentNotification;

@interface NCNotificationController : NSObject

+ (instancetype)sharedInstance;
- (void)requestAuthorization;
- (void)processIncomingPushNotification:(NCPushNotification *)pushNotification;
- (void)cleanNotifications;

@end
