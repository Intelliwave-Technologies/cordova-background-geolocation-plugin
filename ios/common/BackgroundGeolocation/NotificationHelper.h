#ifndef NotificationHelper_h
#define NotificationHelper_h
#import <UserNotifications/UserNotifications.h>

@interface NotificationHelper : NSObject

- (void)scheduleNotification:(UNUserNotificationCenter *)center
           secondsToTrigger:(double)secondsToTrigger
                    repeats:(BOOL)repeats
                 identifier:(NSString*)requestIndentifier;

-(void)removeNotifications;

-(void)showNotification:(double)secondsToTrigger
                repeats:(BOOL)repeats
             identifier:(NSString*)requestIndentifier;

-(BOOL)isNotificationPermitted:(UNUserNotificationCenter *)center
    withCompletionHandler:(void (^)(BOOL permitted))completionHandler;

@end

#endif /* NotificationHelper_h */