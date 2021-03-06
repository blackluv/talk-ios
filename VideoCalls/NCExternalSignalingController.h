//
//  NCExternalSignalingController.h
//  VideoCalls
//
//  Created by Ivan Sein on 07.09.18.
//  Copyright © 2018 struktur AG. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "NCSignalingMessage.h"

extern NSString * const NCESReceivedSignalingMessageNotification;
extern NSString * const NCESReceivedParticipantListMessageNotification;

@interface NCExternalSignalingController : NSObject

@property (nonatomic, strong) NSString* currentRoom;

+ (instancetype)sharedInstance;
- (BOOL)isEnabled;
- (BOOL)hasMCU;
- (NSString *)sessionId;
- (void)setServer:(NSString *)serverUrl andTicket:(NSString *)ticket;
- (void)joinRoom:(NSString *)roomId withSessionId:(NSString *)sessionId;
- (void)leaveRoom:(NSString *)roomId;
- (void)sendCallMessage:(NCSignalingMessage *)message;
- (void)requestOfferForSessionId:(NSString *)sessionId andRoomType:(NSString *)roomType;
- (NSString *)getUserIdFromSessionId:(NSString *)sessionId;
- (void)disconnect;

@end
