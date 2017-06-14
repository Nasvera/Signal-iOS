//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "DebugUITableViewController.h"
#import "Environment.h"
#import "Signal-Swift.h"
#import "ThreadUtil.h"
#import <SignalServiceKit/TSStorageManager+SessionStore.h>
#import <SignalServiceKit/TSThread.h>

NS_ASSUME_NONNULL_BEGIN

@implementation DebugUITableViewController

#pragma mark - Logging

+ (NSString *)tag
{
    return [NSString stringWithFormat:@"[%@]", self.class];
}

- (NSString *)tag
{
    return self.class.tag;
}

#pragma mark - Factory Methods

+ (void)presentDebugUIForThread:(TSThread *)thread
             fromViewController:(UIViewController *)fromViewController {
    OWSAssert(thread);
    OWSAssert(fromViewController);

    OWSTableContents *contents = [OWSTableContents new];
    contents.title = @"Debug: Conversation";

    [contents
        addSection:[OWSTableSection
                       sectionWithTitle:@"Messages View"
                                  items:@[
                                      [OWSTableItem itemWithTitle:@"Send 10 messages (1/sec.)"
                                                      actionBlock:^{
                                                          [DebugUITableViewController sendTextMessage:10 thread:thread];
                                                      }],
                                      [OWSTableItem itemWithTitle:@"Send 100 messages (1/sec.)"
                                                      actionBlock:^{
                                                          [DebugUITableViewController sendTextMessage:100
                                                                                               thread:thread];
                                                      }],
                                      [OWSTableItem itemWithTitle:@"Send 1,000 messages (1/sec.)"
                                                      actionBlock:^{
                                                          [DebugUITableViewController sendTextMessage:1000
                                                                                               thread:thread];
                                                      }],
                                      [OWSTableItem itemWithTitle:@"Send fake 1,000 messages (1/sec.)"
                                                      actionBlock:^{
                                                          [DebugUITableViewController sendFakeTextMessage:1000
                                                                                                   thread:thread];
                                                      }],
                                      [OWSTableItem itemWithTitle:@"Send text/x-signal-plain"
                                                      actionBlock:^{
                                                          [DebugUITableViewController sendOversizeTextMessage:thread];
                                                      }],
                                      [OWSTableItem
                                          itemWithTitle:@"Send unknown mimetype"
                                            actionBlock:^{
                                                [DebugUITableViewController
                                                    sendRandomAttachment:thread
                                                                     uti:SignalAttachment.kUnknownTestAttachmentUTI];
                                            }],
                                      [OWSTableItem itemWithTitle:@"Send pdf"
                                                      actionBlock:^{
                                                          [DebugUITableViewController
                                                              sendRandomAttachment:thread
                                                                               uti:(NSString *)kUTTypePDF];
                                                      }],
                                  ]]];

    [contents
        addSection:[OWSTableSection
                       sectionWithTitle:@"Session State"
                                  items:@[
                                      [OWSTableItem itemWithTitle:@"Print all sessions"
                                                      actionBlock:^{
                                                          dispatch_async([OWSDispatch sessionStoreQueue], ^{
                                                              [[TSStorageManager sharedManager] printAllSessions];
                                                          });
                                                      }],
                                      [OWSTableItem
                                          itemWithTitle:@"Delete session (Contact Thread Only)"
                                            actionBlock:^{
                                                if (![thread isKindOfClass:[TSContactThread class]]) {
                                                    DDLogError(@"Refusing to delete session for group thread.");
                                                    OWSAssert(NO);
                                                    return;
                                                }
                                                TSContactThread *contactThread = (TSContactThread *)thread;
                                                dispatch_async([OWSDispatch sessionStoreQueue], ^{
                                                    [[TSStorageManager sharedManager]
                                                        deleteAllSessionsForContact:contactThread.contactIdentifier];
                                                });
                                            }],
                                      [OWSTableItem
                                          itemWithTitle:@"Send session reset (Contact Thread Only)"
                                            actionBlock:^{
                                                if (![thread isKindOfClass:[TSContactThread class]]) {
                                                    DDLogError(@"Refusing to reset session for group thread.");
                                                    OWSAssert(NO);
                                                    return;
                                                }
                                                TSContactThread *contactThread = (TSContactThread *)thread;
                                                [OWSSessionResetJob
                                                    runWithContactThread:contactThread
                                                           messageSender:[Environment getCurrent].messageSender
                                                          storageManager:[TSStorageManager sharedManager]];
                                            }]

                                  ]]];

    DebugUITableViewController *viewController = [DebugUITableViewController new];
    viewController.contents = contents;
    [viewController presentFromViewController:fromViewController];
}

+ (void)sendTextMessage:(int)counter
                 thread:(TSThread *)thread {
    OWSMessageSender *messageSender = [Environment getCurrent].messageSender;
    if (counter < 1) {
        return;
    }
    [ThreadUtil sendMessageWithText:[@(counter) description]
                           inThread:thread
                      messageSender:messageSender];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t) 1.f * NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{
                       [self sendTextMessage:counter - 1 thread:thread];
                   });
}

+ (NSString *)randomText
{
    NSArray<NSString *> *randomTexts = @[
        @"Lorem ipsum dolor sit amet, consectetur adipiscing elit. ",
        (@"Lorem ipsum dolor sit amet, consectetur adipiscing elit. "
         @"Suspendisse rutrum, nulla vitae pretium hendrerit, tellus "
         @"turpis pharetra libero, vitae sodales tortor ante vel sem."),
        @"In a time of universal deceit - telling the truth is a revolutionary act.",
        @"If you want a vision of the future, imagine a boot stamping on a human face - forever.",
        @"Who controls the past controls the future. Who controls the present controls the past.",
        @"All animals are equal, but some animals are more equal than others.",
        @"War is peace. Freedom is slavery. Ignorance is strength.",
        (@"All the war-propaganda, all the screaming and lies and hatred, comes invariably from people who are not "
         @"fighting."),
        (@"Political language. . . is designed to make lies sound truthful and murder respectable, and to give an "
         @"appearance of solidity to pure wind."),
        (@"The nationalist not only does not disapprove of atrocities committed by his own side, but he has a "
         @"remarkable capacity for not even hearing about them."),
        (@"Every generation imagines itself to be more intelligent than the one that went before it, and wiser than "
         @"the "
         @"one that comes after it."),
        @"War against a foreign country only happens when the moneyed classes think they are going to profit from it.",
    ];
    NSString *randomText = randomTexts[(NSUInteger)arc4random_uniform((uint32_t)randomTexts.count)];
    return randomText;
}

+ (void)sendFakeTextMessage:(int)counter thread:(TSThread *)thread
{
    NSMutableArray<TSMessage *> *messages = [NSMutableArray new];
    for (int i = 0; i < counter; i++) {
        NSString *randomText = [self randomText];
        BOOL isIncoming = arc4random_uniform(2) == 0;
        if (isIncoming) {
            [messages addObject:[[TSIncomingMessage alloc] initWithTimestamp:[NSDate ows_millisecondTimeStamp]
                                                                    inThread:thread
                                                                    authorId:@"+19174054215"
                                                              sourceDeviceId:0
                                                                 messageBody:randomText]];
        } else {
            [messages addObject:[[TSOutgoingMessage alloc] initWithTimestamp:[NSDate ows_millisecondTimeStamp]
                                                                    inThread:thread
                                                                 messageBody:randomText]];
        }
    }
    [TSStorageManager.sharedManager.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        for (TSMessage *message in messages) {
            [message saveWithTransaction:transaction];
        }
    }];
}

+ (void)sendOversizeTextMessage:(TSThread *)thread {
    OWSMessageSender *messageSender = [Environment getCurrent].messageSender;
    NSMutableString *message = [NSMutableString new];
    for (int i=0; i < 32; i++) {
        [message appendString:@"Lorem ipsum dolor sit amet, consectetur adipiscing elit. Suspendisse rutrum, nulla vitae pretium hendrerit, tellus turpis pharetra libero, vitae sodales tortor ante vel sem. Fusce sed nisl a lorem gravida tincidunt. Suspendisse efficitur non quam ac sodales. Aenean ut velit maximus, posuere sem a, accumsan nunc. Donec ullamcorper turpis lorem. Quisque dignissim purus eu placerat ultricies. Proin at urna eget mi semper congue. Aenean non elementum ex. Praesent pharetra quam at sem vestibulum, vestibulum ornare dolor elementum. Vestibulum massa tortor, scelerisque sit amet pulvinar a, rhoncus vitae nisl. Sed mi nunc, tempus at varius in, malesuada vitae dui. Vivamus efficitur pulvinar erat vitae congue. Proin vehicula turpis non felis congue facilisis. Nullam aliquet dapibus ligula ac mollis. Etiam sit amet posuere lorem, in rhoncus nisi."];
    }

    SignalAttachment *attachment = [SignalAttachment attachmentWithData:[message dataUsingEncoding:NSUTF8StringEncoding]
                                                                dataUTI:SignalAttachment.kOversizeTextAttachmentUTI
                                                               filename:nil];
    [ThreadUtil sendMessageWithAttachment:attachment
                                 inThread:thread
                            messageSender:messageSender];
}

+ (NSData*)createRandomNSDataOfSize:(size_t)size
{
    OWSAssert(size % 4 == 0);
    
    NSMutableData* data = [NSMutableData dataWithCapacity:size];
    for (size_t i = 0; i < size / 4; ++i)
    {
        u_int32_t randomBits = arc4random();
        [data appendBytes:(void *)&randomBits length:4];
    }
    return data;
}

+ (void)sendRandomAttachment:(TSThread *)thread
                         uti:(NSString *)uti {
    OWSMessageSender *messageSender = [Environment getCurrent].messageSender;
    SignalAttachment *attachment =
        [SignalAttachment attachmentWithData:[self createRandomNSDataOfSize:256] dataUTI:uti filename:nil];
    [ThreadUtil sendMessageWithAttachment:attachment
                                 inThread:thread
                            messageSender:messageSender];
}

@end

NS_ASSUME_NONNULL_END
