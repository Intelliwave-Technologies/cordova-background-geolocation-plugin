#import <Foundation/Foundation.h>
#import "NotificationHelper.h"
#import <UserNotifications/UserNotifications.h>
@import UserNotifications;

@implementation NotificationHelper {}

static NSString * const APP_TERMINATED_NOTIFICATION_IDENTIFIER = @"BackgroundGeolocation";
static NSString * const APP_TERMINATED_NOTIFICATION_REPEATING_IDENTIFIER = @"BackgroundGeolocationRepeating";

-(void)scheduleNotification:(UNUserNotificationCenter *)center
           secondsToTrigger:(double)secondsToTrigger
                    repeats:(BOOL)repeats
                 identifier:(NSString*)requestIndentifier
                       body:(NSString*)body
{
    UNMutableNotificationContent *content = [[UNMutableNotificationContent alloc] init];
    content.title = @"SiteSense - Background Geolocation Notification";
    content.body = body;
    
    content.sound = UNNotificationSound.defaultSound;
    content.badge = @1;
    
    if (@available(iOS 15, *)) {
        content.interruptionLevel = UNNotificationInterruptionLevelActive;
    }
    
    NSDictionary* userInfo = @{@"isGeolocationNotification": @(TRUE), @"repeats": @(repeats)};
    content.userInfo = userInfo;

    NSTimeInterval notificationTrigger = secondsToTrigger;

    UNNotificationTrigger* trigger = [UNTimeIntervalNotificationTrigger
                                      triggerWithTimeInterval:notificationTrigger
                                                      repeats:repeats];
    
    // Passing UNTimeIntervalNotificationTrigger with time = 0 is still little slow to deliver.
    // It will triggers instantly if trigger is null.
    if (secondsToTrigger == 0) {
        trigger = Nil;
    }

    UNNotificationRequest *request = [UNNotificationRequest requestWithIdentifier:requestIndentifier
                                                                          content:content
                                                                          trigger:trigger];
    
    [center addNotificationRequest:request withCompletionHandler:^(NSError * _Nullable error) {
        if (error != nil) {
            NSLog(@"NotificationProvider - %@", error.localizedDescription);
        }
        NSLog(@"NotificationProvider - Successfully maybe scheduled notification.");
    }];
}

-(void)removeNotifications {
    UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
    NSArray *array = [NSArray arrayWithObjects:APP_TERMINATED_NOTIFICATION_IDENTIFIER, APP_TERMINATED_NOTIFICATION_REPEATING_IDENTIFIER, nil];
    
    [center getPendingNotificationRequestsWithCompletionHandler:^(NSArray<UNNotificationRequest*> *requests){
        NSLog(@"requests: %@", requests);
    }];
    
    
    [center removePendingNotificationRequestsWithIdentifiers:array];
}

-(void)showNotification:(double)secondsToTrigger
                repeats:(BOOL)repeats
             identifier:(NSString*)requestIndentifier
                    body:(NSString*)body
{
    UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];

    // Launched in background likely after app terminate, display notification that background geolocation is restricted.
    if (@available(iOS 10, *))
    {
        [self isNotificationPermitted:center withCompletionHandler:^(BOOL permitted) {
            if (permitted) {
                [self scheduleNotification:center
                          secondsToTrigger:secondsToTrigger
                                   repeats:repeats
                                identifier:requestIndentifier
                                      body:body];
            }
        }];
    }
}

-(void)showNotification:(double)secondsToTrigger
                repeats:(BOOL)repeats
             identifier:(NSString*)requestIndentifier
{
    [self showNotification:secondsToTrigger 
                   repeats:repeats 
                identifier:requestIndentifier 
                      body:@"App has been terminated due to out of memory or closed by user. Background BLE scanning is not active or active with restricted performance. Tap here to wake up the app and resume normal scanning."];
}

-(void)isNotificationPermitted:(UNUserNotificationCenter *)center
    withCompletionHandler:(void (^)(BOOL permitted))completionHandler
{
    [center getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings* settings) {
        BOOL authorized = settings.authorizationStatus == UNAuthorizationStatusAuthorized;
        BOOL enabled    = settings.notificationCenterSetting == UNNotificationSettingEnabled;
        BOOL permitted  = authorized && enabled;
        NSLog(@"NotificationProvider - Is Permitted: %s",  permitted ? "true" : "false");
        completionHandler(permitted);
    }];
}

@end
