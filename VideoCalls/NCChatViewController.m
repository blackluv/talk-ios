//
//  NCChatViewController.m
//  VideoCalls
//
//  Created by Ivan Sein on 23.04.18.
//  Copyright © 2018 struktur AG. All rights reserved.
//

#import "NCChatViewController.h"

#import "AFImageDownloader.h"
#import "ChatMessageTableViewCell.h"
#import "GroupedChatMessageTableViewCell.h"
#import "FileMessageTableViewCell.h"
#import "SystemMessageTableViewCell.h"
#import "DateHeaderView.h"
#import "PlaceholderView.h"
#import "NCAPIController.h"
#import "NCChatMessage.h"
#import "NCMessageParameter.h"
#import "NCChatTitleView.h"
#import "NCMessageTextView.h"
#import "NCFilePreviewSessionManager.h"
#import "NCRoomsManager.h"
#import "NCRoomController.h"
#import "NCSettingsController.h"
#import "NCUserInterfaceController.h"
#import "NSDate+DateTools.h"
#import "RoomInfoTableViewController.h"
#import "UIImageView+AFNetworking.h"
#import "UnreadMessagesView.h"

@interface NCChatViewController ()

@property (nonatomic, strong) NCRoom *room;
@property (nonatomic, strong) NCRoomController *roomController;
@property (nonatomic, strong) NCChatTitleView *titleView;
@property (nonatomic, strong) PlaceholderView *chatBackgroundView;
@property (nonatomic, strong) NSMutableDictionary *messages;
@property (nonatomic, strong) NSMutableArray *dateSections;
@property (nonatomic, strong) NSMutableArray *mentions;
@property (nonatomic, strong) NSMutableArray *autocompletionUsers;
@property (nonatomic, assign) BOOL stopReceivingNewMessages;
@property (nonatomic, assign) BOOL hasReceiveInitialHistory;
@property (nonatomic, assign) BOOL retrievingHistory;
@property (nonatomic, strong) UIActivityIndicatorView *loadingHistoryView;
@property (nonatomic, assign) NSInteger firstUnreadMessage;
@property (nonatomic, strong) UnreadMessagesView *unreadMessageView;

@end

@implementation NCChatViewController

- (instancetype)initForRoom:(NCRoom *)room
{
    self = [super initWithTableViewStyle:UITableViewStylePlain];
    if (self) {
        self.room = room;
        self.hidesBottomBarWhenPushed = YES;
        // Fixes problem with tableView contentSize on iOS 11
        self.tableView.estimatedRowHeight = 0;
        self.tableView.estimatedSectionHeaderHeight = 0;
        // Register a SLKTextView subclass, if you need any special appearance and/or behavior customisation.
        [self registerClassForTextView:[NCMessageTextView class]];
        // Set image downloader to file preview imageviews.
        AFImageDownloader *imageDownloader = [[AFImageDownloader alloc]
                                              initWithSessionManager:[NCFilePreviewSessionManager sharedInstance]
                                              downloadPrioritization:AFImageDownloadPrioritizationFIFO
                                              maximumActiveDownloads:4
                                              imageCache:[[AFAutoPurgingImageCache alloc] init]];
        [FilePreviewImageView setSharedImageDownloader:imageDownloader];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didJoinRoom:) name:NCRoomsManagerDidJoinRoomNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didReceiveInitialChatHistory:) name:NCRoomControllerDidReceiveInitialChatHistoryNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didReceiveChatHistory:) name:NCRoomControllerDidReceiveChatHistoryNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didReceiveChatMessages:) name:NCRoomControllerDidReceiveChatMessagesNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didSendChatMessage:) name:NCRoomControllerDidSendChatMessageNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didUpdateRoom:) name:NCRoomsManagerDidUpdateRoomNotification object:nil];
    }
    
    return self;
}
    
- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - View lifecycle

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    [self setTitleView];
    [self configureActionItems];
    
    // Disable room info until receiving first chat history
    _titleView.userInteractionEnabled = NO;
    
    self.messages = [[NSMutableDictionary alloc] init];
    self.mentions = [[NSMutableArray alloc] init];
    self.dateSections = [[NSMutableArray alloc] init];
    
    self.bounces = NO;
    self.shakeToClearEnabled = YES;
    self.keyboardPanningEnabled = YES;
    self.shouldScrollToBottomAfterKeyboardShows = YES;
    self.inverted = NO;
    
    [self.rightButton setTitle:NSLocalizedString(@"Send", nil) forState:UIControlStateNormal];
    
    self.textInputbar.autoHideRightButton = YES;
    self.textInputbar.maxCharCount = 1000;
    self.textInputbar.counterStyle = SLKCounterStyleCountdownReversed;
    self.textInputbar.counterPosition = SLKCounterPositionTop;
    self.textInputbar.translucent = NO;
    self.textInputbar.backgroundColor = [UIColor colorWithRed:0.98 green:0.98 blue:0.98 alpha:1.0]; //f9f9f9
    
    [self.textInputbar.editorTitle setTextColor:[UIColor darkGrayColor]];
    [self.textInputbar.editorLeftButton setTintColor:[UIColor colorWithRed:0.0/255.0 green:122.0/255.0 blue:255.0/255.0 alpha:1.0]];
    [self.textInputbar.editorRightButton setTintColor:[UIColor colorWithRed:0.0/255.0 green:122.0/255.0 blue:255.0/255.0 alpha:1.0]];
    
    self.navigationController.navigationBar.tintColor = [UIColor whiteColor];
    
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    [self.tableView registerClass:[ChatMessageTableViewCell class] forCellReuseIdentifier:ChatMessageCellIdentifier];
    [self.tableView registerClass:[GroupedChatMessageTableViewCell class] forCellReuseIdentifier:GroupedChatMessageCellIdentifier];
    [self.tableView registerClass:[FileMessageTableViewCell class] forCellReuseIdentifier:FileMessageCellIdentifier];
    [self.tableView registerClass:[FileMessageTableViewCell class] forCellReuseIdentifier:GroupedFileMessageCellIdentifier];
    [self.tableView registerClass:[SystemMessageTableViewCell class] forCellReuseIdentifier:SystemMessageCellIdentifier];
    [self.autoCompletionView registerClass:[ChatMessageTableViewCell class] forCellReuseIdentifier:AutoCompletionCellIdentifier];
    [self registerPrefixesForAutoCompletion:@[@"@"]];
    
    // Chat placeholder view
    _chatBackgroundView = [[PlaceholderView alloc] init];
    [_chatBackgroundView.placeholderView setHidden:YES];
    [_chatBackgroundView.loadingView startAnimating];
    self.tableView.backgroundView = _chatBackgroundView;
    
    // Unread messages indicator
    _firstUnreadMessage = -1;
    _unreadMessageView =  [[UnreadMessagesView alloc] init];
    _unreadMessageView.center = self.view.center;
    _unreadMessageView.frame = CGRectMake(_unreadMessageView.frame.origin.x,
                                          -40,
                                          _unreadMessageView.frame.size.width,
                                          _unreadMessageView.frame.size.height);
    _unreadMessageView.hidden = YES;
    [self.textInputbar addSubview:_unreadMessageView];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    if (_stopReceivingNewMessages) {
        _stopReceivingNewMessages = NO;
        [[NCRoomsManager sharedInstance] startReceivingChatMessagesInRoom:_room];
    }
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    
    _stopReceivingNewMessages = YES;
    [[NCRoomsManager sharedInstance] stopReceivingChatMessagesInRoom:_room];
    
    if (self.isMovingFromParentViewController) {
        [[NCRoomsManager sharedInstance] leaveChatInRoom:_room.token];
    }
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator
{
    if (_firstUnreadMessage > -1) {
        [coordinator animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext> context) {
            _unreadMessageView.hidden = YES;
        } completion:^(id<UIViewControllerTransitionCoordinatorContext> context) {
            _unreadMessageView.center = self.view.center;
            _unreadMessageView.frame = CGRectMake(_unreadMessageView.frame.origin.x,
                                                  -40,
                                                  _unreadMessageView.frame.size.width,
                                                  _unreadMessageView.frame.size.height);
            _unreadMessageView.hidden = NO;
        }];
    }
}

#pragma mark - Configuration

- (void)setTitleView
{
    _titleView = [[NCChatTitleView alloc] init];
    _titleView.frame = CGRectMake(0, 0, 800, 30);
    _titleView.autoresizingMask=UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth;
    [_titleView.title setTitle:_room.displayName forState:UIControlStateNormal];
    [_titleView.title addTarget:self action:@selector(titleButtonPressed:) forControlEvents:UIControlEventTouchUpInside];
    
    // Set room image
    switch (_room.type) {
        case kNCRoomTypeOneToOneCall:
        {
            // Request user avatar to the server and set it if exist
            [_titleView.image setImageWithURLRequest:[[NCAPIController sharedInstance] createAvatarRequestForUser:_room.name andSize:96]
                                    placeholderImage:nil success:nil failure:nil];
        }
            break;
        case kNCRoomTypeGroupCall:
            [_titleView.image setImage:[UIImage imageNamed:@"group-bg"]];
            break;
        case kNCRoomTypePublicCall:
            [_titleView.image setImage:(_room.hasPassword) ? [UIImage imageNamed:@"public-password-bg"] : [UIImage imageNamed:@"public-bg"]];
            break;
        default:
            break;
    }
    
    self.navigationItem.titleView = _titleView;
}

- (void)configureActionItems
{
    UIBarButtonItem *videoCallButton = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"videocall-action"]
                                                                        style:UIBarButtonItemStylePlain
                                                                       target:self
                                                                       action:@selector(videoCallButtonPressed:)];
    
    UIBarButtonItem *voiceCallButton = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"call-action"]
                                                                        style:UIBarButtonItemStylePlain
                                                                       target:self
                                                                       action:@selector(voiceCallButtonPressed:)];
    
    self.navigationItem.rightBarButtonItems = @[videoCallButton, voiceCallButton];
}

#pragma mark - Utils

- (NSString *)getTimeFromDate:(NSDate *)date
{
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setDateFormat:@"HH:mm"];
    return [formatter stringFromDate:date];
}

- (NSString *)getHeaderStringFromDate:(NSDate *)date
{
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateStyle = NSDateFormatterMediumStyle;
    formatter.doesRelativeDateFormatting = YES;
    return [formatter stringFromDate:date];
}

- (NSString *)createSendingMessage:(NSString *)text
{
    NSString *sendingMessage = [text copy];
    for (NCMessageParameter *mention in _mentions) {
        sendingMessage = [sendingMessage stringByReplacingOccurrencesOfString:mention.name withString:mention.parameterId];
    }
    _mentions = [[NSMutableArray alloc] init];
    return sendingMessage;
}

#pragma mark - Action Methods

- (void)titleButtonPressed:(id)sender
{
    RoomInfoTableViewController *roomInfoVC = [[RoomInfoTableViewController alloc] initForRoom:_room];
    [self.navigationController pushViewController:roomInfoVC animated:YES];
}

- (void)videoCallButtonPressed:(id)sender
{
    [[NCRoomsManager sharedInstance] startCall:YES inRoom:_room];
}

- (void)voiceCallButtonPressed:(id)sender
{
    [[NCRoomsManager sharedInstance] startCall:NO inRoom:_room];
}

- (void)didPressRightButton:(id)sender
{
    NSString *sendingText = [self createSendingMessage:self.textView.text];
    [[NCRoomsManager sharedInstance] sendChatMessage:sendingText toRoom:_room];
    [super didPressRightButton:sender];
}

#pragma mark - UIScrollViewDelegate Methods

- (void)scrollViewDidScroll:(UIScrollView *)scrollView
{
    [super scrollViewDidScroll:scrollView];
    
    if ([scrollView isEqual:self.tableView] && scrollView.contentOffset.y < 0) {
        if ([self shouldRetireveHistory]) {
            _retrievingHistory = YES;
            [self showLoadingHistoryView];
            NSDate *dateSection = [_dateSections objectAtIndex:0];
            NCChatMessage *firstMessage = [[_messages objectForKey:dateSection] objectAtIndex:0];
            [_roomController getChatHistoryFromMessagesId:firstMessage.messageId];
        }
    }
    
    if (_firstUnreadMessage > -1) {
        [self checkUnreadMessagesVisibility];
    }
}

#pragma mark - UITextViewDelegate Methods

- (BOOL)textView:(SLKTextView *)textView shouldChangeTextInRange:(NSRange)range replacementText:(NSString *)text
{
    if ([text isEqualToString:@""]) {
        UITextRange *selectedRange = [textView selectedTextRange];
        NSInteger cursorOffset = [textView offsetFromPosition:textView.beginningOfDocument toPosition:selectedRange.start];
        NSString *text = textView.text;
        NSString *substring = [text substringToIndex:cursorOffset];
        NSMutableString *lastPossibleMention = [[[substring componentsSeparatedByString:@"@"] lastObject] mutableCopy];
        [lastPossibleMention insertString:@"@" atIndex:0];
        for (NCMessageParameter *mention in _mentions) {
            if ([lastPossibleMention isEqualToString:mention.name]) {
                // Delete mention
                textView.text =  [[self.textView text] stringByReplacingOccurrencesOfString:lastPossibleMention withString:@""];
                [_mentions removeObject:mention];
                return NO;
            }
        }
    }
    
    return [super textView:textView shouldChangeTextInRange:range replacementText:text];
}

#pragma mark - Room Manager notifications

- (void)didUpdateRoom:(NSNotification *)notification
{
    NCRoom *room = [notification.userInfo objectForKey:@"room"];
    if (!room || ![room.token isEqualToString:_room.token]) {
        return;
    }
    
    _room = room;
    [self setTitleView];
}

- (void)didJoinRoom:(NSNotification *)notification
{
    NCRoomController *roomController = [notification.userInfo objectForKey:@"roomController"];
    if (![roomController.roomToken isEqualToString:_room.token]) {
        return;
    }
    
    if (!_roomController) {
        _roomController = roomController;
        [_roomController getInitialChatHistory];
    }
}

- (void)didReceiveInitialChatHistory:(NSNotification *)notification
{
    NSString *room = [notification.userInfo objectForKey:@"room"];
    if (![room isEqualToString:_room.token]) {
        return;
    }
    
    _hasReceiveInitialHistory = YES;
    _titleView.userInteractionEnabled = YES;
    [_chatBackgroundView.loadingView stopAnimating];
    [_chatBackgroundView.loadingView setHidden:YES];
    
    NSMutableArray *messages = [notification.userInfo objectForKey:@"messages"];
    if (messages) {
        [self sortMessages:messages inDictionary:_messages];
        [self.tableView reloadData];
        NSMutableArray *messagesForLastDate = [_messages objectForKey:[_dateSections lastObject]];
        NSIndexPath *lastMessageIndexPath = [NSIndexPath indexPathForRow:messagesForLastDate.count - 1 inSection:_dateSections.count - 1];
        [self.tableView scrollToRowAtIndexPath:lastMessageIndexPath atScrollPosition:UITableViewScrollPositionNone animated:NO];
    } else {
        [_chatBackgroundView.placeholderView setHidden:NO];
    }
}

- (void)didReceiveChatHistory:(NSNotification *)notification
{
    NSString *room = [notification.userInfo objectForKey:@"room"];
    if (![room isEqualToString:_room.token]) {
        return;
    }
    
    NSMutableArray *messages = [notification.userInfo objectForKey:@"messages"];
    if (messages) {
        NSIndexPath *lastHistoryMessageIP = [self sortHistoryMessages:messages];
        [self.tableView reloadData];
        [self.tableView scrollToRowAtIndexPath:lastHistoryMessageIP atScrollPosition:UITableViewScrollPositionNone animated:NO];
    }
    
    _retrievingHistory = NO;
    [self hideLoadingHistoryView];
}

- (void)didReceiveChatMessages:(NSNotification *)notification
{
    NSString *room = [notification.userInfo objectForKey:@"room"];
    if (![room isEqualToString:_room.token]) {
        return;
    }
    
    NSMutableArray *messages = [notification.userInfo objectForKey:@"messages"];
    if (messages.count > 0) {
        NSInteger lastSectionBeforeUpdate = _dateSections.count - 1;
        BOOL singleMessage = (messages.count == 1);
        BOOL scroll = [self shouldScrollOnNewMessages];
        if (!scroll && _firstUnreadMessage < 0) {
            [self showNewMessagesViewUntilMessage:[messages firstObject]];
        }
        
        [self sortMessages:messages inDictionary:_messages];
        
        NSMutableArray *messagesForLastDate = [_messages objectForKey:[_dateSections lastObject]];
        NSIndexPath *lastMessageIndexPath = [NSIndexPath indexPathForRow:messagesForLastDate.count - 1 inSection:_dateSections.count - 1];
        
        if (messages.count > 1) {
            [self.tableView reloadData];
        } else if (singleMessage) {
            [self.tableView beginUpdates];
            NSInteger newLastSection = _dateSections.count - 1;
            BOOL newSection = lastSectionBeforeUpdate != newLastSection;
            if (newSection) {
                [self.tableView insertSections:[NSIndexSet indexSetWithIndex:newLastSection] withRowAnimation:UITableViewRowAnimationNone];
            } else {
                [self.tableView insertRowsAtIndexPaths:@[lastMessageIndexPath] withRowAnimation:UITableViewRowAnimationNone];
            }
            [self.tableView endUpdates];
        }
        
        if (scroll) {
            [self.tableView scrollToRowAtIndexPath:lastMessageIndexPath atScrollPosition:UITableViewScrollPositionNone animated:YES];
        }
    }
    
}

- (void)didSendChatMessage:(NSNotification *)notification
{
    NSError *error = [notification.userInfo objectForKey:@"error"];
    NSString *message = [notification.userInfo objectForKey:@"message"];
    if (error) {
        self.textView.text = message;
        UIAlertController * alert = [UIAlertController
                                     alertControllerWithTitle:@"Could not send the message"
                                     message:@"An error occurred while sending the message"
                                     preferredStyle:UIAlertControllerStyleAlert];
        
        UIAlertAction* okButton = [UIAlertAction
                                   actionWithTitle:@"OK"
                                   style:UIAlertActionStyleDefault
                                   handler:nil];
        
        [alert addAction:okButton];
        
        [[NCUserInterfaceController sharedInstance] presentAlertViewController:alert];
    }
}

#pragma mark - Chat functions

- (NSDate *)getKeyForDate:(NSDate *)date inDictionary:(NSDictionary *)dictionary
{
    NSDate *keyDate = nil;
    for (NSDate *key in dictionary.allKeys) {
        if ([[NSCalendar currentCalendar] isDate:date inSameDayAsDate:key]) {
            keyDate = key;
        }
    }
    return keyDate;
}

- (NSIndexPath *)sortHistoryMessages:(NSMutableArray *)historyMessages
{
    NSMutableDictionary *historyDict = [[NSMutableDictionary alloc] init];
    [self sortMessages:historyMessages inDictionary:historyDict];
    
    NSDate *chatSection = nil;
    NSMutableArray *historyMessagesForSection = nil;
    // Sort history sections
    NSMutableArray *historySections = [NSMutableArray arrayWithArray:historyDict.allKeys];
    [historySections sortUsingSelector:@selector(compare:)];
    
    for (NSDate *historySection in historySections) {
        historyMessagesForSection = [historyDict objectForKey:historySection];
        chatSection = [self getKeyForDate:historySection inDictionary:_messages];
        if (!chatSection) {
            [_messages setObject:historyMessagesForSection forKey:historySection];
        }
    }
    
    [self sortDateSections];
    
    NSMutableArray *lastHistoryMessages = [historyDict objectForKey:[historySections lastObject]];
    NSIndexPath *lastHistoryMessageIP = [NSIndexPath indexPathForRow:lastHistoryMessages.count - 1 inSection:historySections.count - 1];
    
    if (chatSection) {
        NSMutableArray *chatMessages = [_messages objectForKey:chatSection];
        NCChatMessage *lastHistoryMessage = [historyMessagesForSection lastObject];
        NCChatMessage *firstChatMessage = [chatMessages firstObject];
        
        BOOL canGroup = [self shouldGroupMessage:firstChatMessage withMessage:lastHistoryMessage];
        if (canGroup) {
            firstChatMessage.groupMessage = YES;
            firstChatMessage.groupMessageNumber = lastHistoryMessage.groupMessageNumber + 1;
            for (int i = 1; i < chatMessages.count; i++) {
                NCChatMessage *currentMessage = chatMessages[i];
                NCChatMessage *messageBefore = chatMessages[i-1];
                if ([self shouldGroupMessage:currentMessage withMessage:messageBefore]) {
                    currentMessage.groupMessage = YES;
                    currentMessage.groupMessageNumber = messageBefore.groupMessageNumber + 1;
                } else if ([currentMessage.actorId isEqualToString:messageBefore.actorId] &&
                           (currentMessage.timestamp - messageBefore.timestamp) < kChatMessageGroupTimeDifference &&
                           messageBefore.groupMessageNumber == kChatMessageMaxGroupNumber) {
                    // Check if message groups need to be changed
                    currentMessage.groupMessage = NO;
                    currentMessage.groupMessageNumber = 0;
                } else {
                    break;
                }
            }
        }
        
        [historyMessagesForSection addObjectsFromArray:chatMessages];
        [_messages setObject:historyMessagesForSection forKey:chatSection];
    }
    
    return lastHistoryMessageIP;
}

- (void)sortMessages:(NSMutableArray *)messages inDictionary:(NSMutableDictionary *)dictionary
{
    for (NCChatMessage *newMessage in messages) {
        NSDate *newMessageDate = [NSDate dateWithTimeIntervalSince1970: newMessage.timestamp];
        NSDate *keyDate = [self getKeyForDate:newMessageDate inDictionary:dictionary];
        NSMutableArray *messagesForDate = [dictionary objectForKey:keyDate];
        if (messagesForDate) {
            NCChatMessage *lastMessage = [messagesForDate lastObject];
            if ([self shouldGroupMessage:newMessage withMessage:lastMessage]) {
                newMessage.groupMessage = YES;
                newMessage.groupMessageNumber = lastMessage.groupMessageNumber + 1;
            }
            [messagesForDate addObject:newMessage];
        } else {
            NSMutableArray *newMessagesInDate = [NSMutableArray new];
            [dictionary setObject:newMessagesInDate forKey:newMessageDate];
            [newMessagesInDate addObject:newMessage];
        }
    }
    
    [self sortDateSections];
}

- (void)sortDateSections
{
    _dateSections = [NSMutableArray arrayWithArray:_messages.allKeys];
    [_dateSections sortUsingSelector:@selector(compare:)];
}

- (BOOL)shouldGroupMessage:(NCChatMessage *)newMessage withMessage:(NCChatMessage *)lastMessage
{
    BOOL sameActor = [newMessage.actorId isEqualToString:lastMessage.actorId];
    BOOL sameType = ([newMessage isSystemMessage] == [lastMessage isSystemMessage]);
    BOOL timeDiff = (newMessage.timestamp - lastMessage.timestamp) < kChatMessageGroupTimeDifference;
    BOOL notMaxGroup = lastMessage.groupMessageNumber < kChatMessageMaxGroupNumber;
    
    return sameActor & sameType & timeDiff & notMaxGroup;
}

- (BOOL)shouldRetireveHistory
{
    return _hasReceiveInitialHistory && !_retrievingHistory && [_roomController hasHistory];
}

- (void)showLoadingHistoryView
{
    _loadingHistoryView = [[UIActivityIndicatorView alloc] initWithFrame:CGRectMake(0, 0, 30, 30)];
    _loadingHistoryView.color = [UIColor darkGrayColor];
    [_loadingHistoryView startAnimating];
    self.tableView.tableHeaderView = _loadingHistoryView;
}

- (void)hideLoadingHistoryView
{
    _loadingHistoryView = nil;
    self.tableView.tableHeaderView = nil;
}

- (BOOL)shouldScrollOnNewMessages
{
    // Scroll if table view is at the bottom (or 80px up)
    CGFloat minimumOffset = (self.tableView.contentSize.height - self.tableView.frame.size.height) - 80;
    if (self.tableView.contentOffset.y >= minimumOffset) {
        return YES;
    }
    
    return NO;
}

- (void)showNewMessagesViewUntilMessage:(NCChatMessage *)message
{
    _firstUnreadMessage = message.messageId;
    _unreadMessageView.hidden = NO;
}

- (void)hideNewMessagesView
{
    _firstUnreadMessage = -1;
    _unreadMessageView.hidden = YES;
}

- (void)checkUnreadMessagesVisibility
{
    NSArray* cells = self.tableView.visibleCells;
    for (ChatTableViewCell *cell in cells) {
        if (cell.messageId == _firstUnreadMessage) {
            [self hideNewMessagesView];
        }
    }
}

#pragma mark - Autocompletion

- (void)didChangeAutoCompletionPrefix:(NSString *)prefix andWord:(NSString *)word
{
    if ([prefix isEqualToString:@"@"]) {
        [self showSuggestionsForString:word];
    }
}

- (CGFloat)heightForAutoCompletionView
{
    return kChatMessageCellMinimumHeight * self.autocompletionUsers.count;
}

- (void)showSuggestionsForString:(NSString *)string
{
    self.autocompletionUsers = nil;
    [[NCAPIController sharedInstance] getMentionSuggestionsInRoom:_room.token forString:string withCompletionBlock:^(NSMutableArray *mentions, NSError *error) {
        if (!error) {
            self.autocompletionUsers = [[NSMutableArray alloc] initWithArray:mentions];
            BOOL show = (self.autocompletionUsers.count > 0);
            // Check if the '@' is still there
            [self.textView lookForPrefixes:self.registeredPrefixes completion:^(NSString *prefix, NSString *word, NSRange wordRange) {
                if (prefix.length > 0 && word.length > 0) {
                    [self showAutoCompletionView:show];
                } else {
                    [self cancelAutoCompletion];
                }
            }];
        }
    }];
}

#pragma mark - UITableViewDataSource Methods

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    if ([tableView isEqual:self.autoCompletionView]) {
        return 1;
    }
    
    return _dateSections.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    if ([tableView isEqual:self.autoCompletionView]) {
        return _autocompletionUsers.count;
    }
    
    NSDate *date = [_dateSections objectAtIndex:section];
    NSMutableArray *messages = [_messages objectForKey:date];
    
    if ([tableView isEqual:self.tableView] && messages.count > 0) {
        self.tableView.backgroundView = nil;
    }
    
    return messages.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    if ([tableView isEqual:self.autoCompletionView]) {
        return nil;
    }
    
    NSDate *date = [_dateSections objectAtIndex:section];
    return [self getHeaderStringFromDate:date];
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section
{
    if ([tableView isEqual:self.autoCompletionView]) {
        return 0;
    }
    
    return kDateHeaderViewHeight;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section
{
    if ([tableView isEqual:self.autoCompletionView]) {
        return nil;
    }
    
    DateHeaderView *headerView = [[DateHeaderView alloc] init];
    headerView.dateLabel.text = [self tableView:tableView titleForHeaderInSection:section];
    headerView.dateLabel.layer.cornerRadius = 12;
    headerView.dateLabel.clipsToBounds = YES;
    
    return headerView;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    if ([tableView isEqual:self.autoCompletionView]) {
        NSDictionary *suggestion = [_autocompletionUsers objectAtIndex:indexPath.row];
        NSString *suggestionId = [suggestion objectForKey:@"id"];
        NSString *suggestionName = [suggestion objectForKey:@"label"];
        ChatMessageTableViewCell *suggestionCell = (ChatMessageTableViewCell *)[self.autoCompletionView dequeueReusableCellWithIdentifier:AutoCompletionCellIdentifier];
        suggestionCell.titleLabel.text = suggestionName;
        // Request user avatar to the server and set it if exist
        [suggestionCell.avatarView setImageWithURLRequest:[[NCAPIController sharedInstance] createAvatarRequestForUser:suggestionId andSize:96]
                                     placeholderImage:nil success:nil failure:nil];
        return suggestionCell;
    }
    
    NSDate *sectionDate = [_dateSections objectAtIndex:indexPath.section];
    NCChatMessage *message = [[_messages objectForKey:sectionDate] objectAtIndex:indexPath.row];
    UITableViewCell *cell = [UITableViewCell new];
    if (message.isSystemMessage) {
        SystemMessageTableViewCell *systemCell = (SystemMessageTableViewCell *)[self.tableView dequeueReusableCellWithIdentifier:SystemMessageCellIdentifier];
        systemCell.bodyTextView.attributedText = message.systemMessageFormat;
        systemCell.messageId = message.messageId;
        if (!message.groupMessage) {
            NSDate *date = [[NSDate alloc] initWithTimeIntervalSince1970:message.timestamp];
            systemCell.dateLabel.text = [self getTimeFromDate:date];
        }
        return systemCell;
    }
    if (message.filePreview) {
        NSString *fileCellIdentifier = (message.groupMessage) ? GroupedFileMessageCellIdentifier : FileMessageCellIdentifier;
        FileMessageTableViewCell *fileCell = (FileMessageTableViewCell *)[self.tableView dequeueReusableCellWithIdentifier:fileCellIdentifier];
        fileCell.titleLabel.text = message.actorDisplayName;
        fileCell.bodyTextView.attributedText = message.parsedMessage;
        fileCell.messageId = message.messageId;
        NSDate *date = [[NSDate alloc] initWithTimeIntervalSince1970:message.timestamp];
        fileCell.dateLabel.text = [self getTimeFromDate:date];
        [fileCell.avatarView setImageWithURLRequest:[[NCAPIController sharedInstance] createAvatarRequestForUser:message.actorId andSize:96]
                                   placeholderImage:nil success:nil failure:nil];
        [fileCell.previewImageView setImageWithURLRequest:[[NCFilePreviewSessionManager sharedInstance] createPreviewRequestForFile:message.filePreview width:120 height:120]
                                         placeholderImage:[UIImage imageNamed:@"file-default-preview"] success:nil failure:nil];
        return fileCell;
    }
    if (message.groupMessage) {
        GroupedChatMessageTableViewCell *groupedCell = (GroupedChatMessageTableViewCell *)[self.tableView dequeueReusableCellWithIdentifier:GroupedChatMessageCellIdentifier];
        groupedCell.bodyTextView.attributedText = message.parsedMessage;
        groupedCell.messageId = message.messageId;
        return groupedCell;
    } else {
        ChatMessageTableViewCell *normalCell = (ChatMessageTableViewCell *)[self.tableView dequeueReusableCellWithIdentifier:ChatMessageCellIdentifier];
        normalCell.titleLabel.text = message.actorDisplayName;
        normalCell.bodyTextView.attributedText = message.parsedMessage;
        normalCell.messageId = message.messageId;
        NSDate *date = [[NSDate alloc] initWithTimeIntervalSince1970:message.timestamp];
        normalCell.dateLabel.text = [self getTimeFromDate:date];
        
        if ([message.actorType isEqualToString:@"guests"]) {
            normalCell.titleLabel.text = ([message.actorDisplayName isEqualToString:@""]) ? @"Guest" : message.actorDisplayName;
            [normalCell setGuestAvatar:message.actorDisplayName];
        } else {
            [normalCell.avatarView setImageWithURLRequest:[[NCAPIController sharedInstance] createAvatarRequestForUser:message.actorId andSize:96]
                                         placeholderImage:nil success:nil failure:nil];
        }
        
        return normalCell;
    }
    
    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    if ([tableView isEqual:self.tableView]) {
        NSDate *sectionDate = [_dateSections objectAtIndex:indexPath.section];
        NCChatMessage *message = [[_messages objectForKey:sectionDate] objectAtIndex:indexPath.row];
        
        NSMutableParagraphStyle *paragraphStyle = [NSMutableParagraphStyle new];
        paragraphStyle.lineBreakMode = NSLineBreakByWordWrapping;
        paragraphStyle.alignment = NSTextAlignmentLeft;
        
        CGFloat pointSize = [ChatMessageTableViewCell defaultFontSize];
        
        NSDictionary *attributes = @{NSFontAttributeName: [UIFont systemFontOfSize:pointSize],
                                     NSParagraphStyleAttributeName: paragraphStyle};
        
        CGFloat width = CGRectGetWidth(tableView.frame) - kChatMessageCellAvatarHeight;
        width -= (message.isSystemMessage)? 80.0 : 30.0; // 4*right(10) + dateLabel(40) : 3*right(10)
        
        CGRect titleBounds = [message.actorDisplayName boundingRectWithSize:CGSizeMake(width, CGFLOAT_MAX) options:NSStringDrawingUsesLineFragmentOrigin attributes:attributes context:NULL];
        CGRect bodyBounds = [message.parsedMessage boundingRectWithSize:CGSizeMake(width, CGFLOAT_MAX) options:(NSStringDrawingUsesLineFragmentOrigin|NSStringDrawingUsesFontLeading) context:NULL];
        
        if (message.message.length == 0) {
            return 0.0;
        }
        
        CGFloat height = CGRectGetHeight(titleBounds);
        height += CGRectGetHeight(bodyBounds);
        height += 40.0;
        
        if (height < kChatMessageCellMinimumHeight) {
            height = kChatMessageCellMinimumHeight;
        }
        
        if (message.groupMessage || message.isSystemMessage) {
            height = CGRectGetHeight(bodyBounds) + 20;
            
            if (height < kGroupedChatMessageCellMinimumHeight) {
                height = kGroupedChatMessageCellMinimumHeight;
            }
        }
        
        if (message.filePreview) {
            height += kFileMessageCellFilePreviewHeight + 10;
        }
        
        return height;
    }
    else {
        return kChatMessageCellMinimumHeight;
    }
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    if ([tableView isEqual:self.autoCompletionView]) {
        NCMessageParameter *mention = [[NCMessageParameter alloc] init];
        mention.parameterId = [NSString stringWithFormat:@"@%@", [self.autocompletionUsers[indexPath.row] objectForKey:@"id"]];
        mention.name = [NSString stringWithFormat:@"@%@", [self.autocompletionUsers[indexPath.row] objectForKey:@"label"]];
        [_mentions addObject:mention];
        
        NSMutableString *mentionString = [[self.autocompletionUsers[indexPath.row] objectForKey:@"label"] mutableCopy];
        [mentionString appendString:@" "];
        [self acceptAutoCompletionWithString:mentionString keepPrefix:YES];
    }
}

@end
