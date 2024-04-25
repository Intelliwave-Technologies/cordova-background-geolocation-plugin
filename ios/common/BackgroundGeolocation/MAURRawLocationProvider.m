//
//  MAURRawLocationProvider.m
//  BackgroundGeolocation
//
//  Created by Marian Hello on 06/11/2017.
//  Copyright © 2017 mauron85. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "MAURRawLocationProvider.h"
#import "MAURLocationManager.h"
#import "MAURLogging.h"
#import "NotificationHelper.h"

static NSString * const TAG = @"RawLocationProvider";
static NSString * const Domain = @"com.marianhello";

static NSString * const APP_TERMINATED_NOTIFICATION_IDENTIFIER = @"BackgroundGeolocation";
static NSString * const APP_TERMINATED_NOTIFICATION_REPEATING_IDENTIFIER = @"BackgroundGeolocationRepeating";

enum {
    maxLocationWaitTimeInSeconds = 15,
    maxLocationAgeInSeconds = 30,
    maxDistanceFilter = 9999,
    
    // Time to reset notifications so they don't fire while app is running.
    // These should be smaller then notificationTime & recurringNotificationTime
    notificationResetTime = 30, //s
    notificationTime = 60, //s
    recurringNotificationTime = 86400, //s
};

@implementation MAURRawLocationProvider {

    BOOL isStarted;
    MAURLocationManager *locationManager;
    
    MAURConfig *_config;

    NotificationHelper *notificationHelper;

    NSTimer *startScanTimer; // Timer to control accuracy to save battery.
    NSTimer *scanTimer; // Timer to control length of scan and reset starting scan.
    NSTimer *notificationTimer; // Timer to reset notification delivery to determine if app is killed.

    NSTimeInterval scanInterval;
    NSTimeInterval intervalBetweenScans;
}

- (instancetype) init
{
    self = [super init];

    notificationHelper = [[NotificationHelper alloc] init];
    scanInterval = 30;
    intervalBetweenScans = 5*60;

    if (self) {
        isStarted = NO;
    }

    return self;
}

- (void) onCreate {
    locationManager = [MAURLocationManager sharedInstance];
    locationManager.delegate = self;
}

- (BOOL) onConfigure:(MAURConfig*)config error:(NSError * __autoreleasing *)outError
{
    DDLogVerbose(@"%@ configure", TAG);
    _config = config;
    
    // NOTE: Only possible on certain platforms. This being false would use more battery but should let us run in the background.
    locationManager.pausesLocationUpdatesAutomatically = false;
    
    // NOTE: Since iOS16+ this is required to run in the background forever: https://developer.apple.com/forums/thread/726945
    [locationManager setShowsBackgroundLocationIndicator:true];

    locationManager.activityType = CLActivityTypeOther;

    // NOTE: Distance filter doesn't affect battery usage, only changing accuracy does.
    // Increasing distance filter only reduces # of updates we get.
    locationManager.distanceFilter = maxDistanceFilter; // meters
    locationManager.desiredAccuracy = kCLLocationAccuracyThreeKilometers; // Start scanning with low accuracy.
    
    scanInterval = config.intervalOfScan.integerValue;
    intervalBetweenScans = config.intervalBetweenScans.integerValue;

    return YES;
}

-(void)resetNotifications
{
    [notificationHelper removeNotifications];
    [notificationHelper showNotification: notificationTime
                   repeats:false
                identifier:APP_TERMINATED_NOTIFICATION_IDENTIFIER];

    [notificationHelper showNotification: recurringNotificationTime
                   repeats:true
                identifier:APP_TERMINATED_NOTIFICATION_REPEATING_IDENTIFIER];
}

-(void)resetNotificationTimer
{
    if (notificationTimer == nil || ![notificationTimer isValid]) {
         NSLog(@"RawLocationProvider - Starting notificationTimer %f", intervalBetweenScans);
         notificationTimer = [NSTimer scheduledTimerWithTimeInterval:notificationResetTime
                             target: self
                             selector: @selector(resetNotifications)
                             userInfo: nil
                             repeats: YES];
     }
}

// Uses the significant changes location API to trigger location updates.
- (BOOL) onStart:(NSError * __autoreleasing *)outError
{
    NSLog(@"%@ will start", TAG);
    
    UNUserNotificationCenter* center = [UNUserNotificationCenter currentNotificationCenter];
    UNAuthorizationOptions options = (UNAuthorizationOptionAlert | UNAuthorizationOptionBadge | UNAuthorizationOptionSound);
    [center requestAuthorizationWithOptions:options completionHandler:^(BOOL granted, NSError* e) {
        NSLog(@"RawLocationProvider - Got permissions for push notifications.");
    }];

    if (!isStarted) {
        [locationManager stopMonitoringSignificantLocationChanges];
        isStarted = [locationManager start:outError];
        
        [self resetNotifications];
        [self resetNotificationTimer];
        [self resetStartScanTimer];
    }

    return isStarted;
}

- (BOOL) onStop:(NSError * __autoreleasing *)outError
{
    NSLog(@"%@ will stop", TAG);

    if (!isStarted) {
        return YES;
    }

    NSLog(@"CDVBackgroundGeolocation - Going to stop significant");
    [locationManager stopMonitoringSignificantLocationChanges];
    if ([locationManager stop:outError]) {
        isStarted = NO;
        
        [startScanTimer invalidate];
        [scanTimer invalidate];
        startScanTimer = nil;
        scanTimer = nil;
        
        [notificationTimer invalidate];
        [notificationHelper removeNotifications];
        notificationTimer = nil;
        
        return YES;
    }

    return NO;
}

- (void) onTerminate
{
    NSLog(@"%@ will terminate", TAG);

    if (isStarted) {
    }
}

- (void) onAuthorizationChanged:(MAURLocationAuthorizationStatus)authStatus
{
    [self.delegate onAuthorizationChanged:authStatus];
}

- (void) resetStartScanTimer
{
   if (startScanTimer == nil || ![startScanTimer isValid]) {
        NSLog(@"RawLocationProvider - Starting startScanTimer");
        
        // When this timer fires start aggressively scanning.
        startScanTimer = [NSTimer scheduledTimerWithTimeInterval:intervalBetweenScans
                            target: self
                            selector: @selector(changeLocationAccuracy)
                            userInfo: nil
                            repeats: NO];
    }
}

// Toggles location accuracy between aggressive location scanning and
// almost passive location scanning to save battery while waiting for startScanTimer to expire.
- (void) changeLocationAccuracy
{
    CLLocationAccuracy currentAccuracy = locationManager.desiredAccuracy;
    NSLog(@"RawLocationProvider - Changing accuracy, %f", currentAccuracy);
    
    if (currentAccuracy <= kCLLocationAccuracyBest) {
        
        [locationManager setDesiredAccuracy:kCLLocationAccuracyThreeKilometers];
        [locationManager setDistanceFilter:maxDistanceFilter];
        [self resetStartScanTimer];

    } else if (currentAccuracy <= kCLLocationAccuracyThreeKilometers) {
        
        [locationManager setDesiredAccuracy:kCLLocationAccuracyBest];
        [locationManager setDistanceFilter:kCLDistanceFilterNone];

        // Allow high accuracy location scan for an interval and then reset accuracy and startScanTimer.
        scanTimer = [NSTimer scheduledTimerWithTimeInterval:scanInterval
                        target: self
                        selector: @selector(changeLocationAccuracy)
                        userInfo: nil
                        repeats: NO];

    } else {
        NSLog(@"RawLocationProvider - Unknown accuracy, accuracy not changed");
    }

}

- (void) onLocationsChanged:(NSArray*)locations
{
    NSLog(@"RawLocationProvider - Location received");
    MAURLocation *bestLocation = nil;
    for (CLLocation *location in locations) {
        MAURLocation *bgloc = [MAURLocation fromCLLocation:location];
        
        NSLog(@"RawLocationProvider - Location age %f", [bgloc locationAge]);
        if ([bgloc locationAge] > maxLocationAgeInSeconds || ![bgloc hasAccuracy] || ![bgloc hasTime]) {
            continue;
        }
        
        if (bestLocation == nil) {
            bestLocation = bgloc;
            continue;
        }
        
        if ([bgloc isBetterLocation:bestLocation]) {
            NSLog(@"RawLocationProvider - Better location found: %@", bgloc);
            bestLocation = bgloc;
        }
    }
    
    if (bestLocation == nil) {
        return;
    }

    for (CLLocation *location in locations) {
        MAURLocation *bgloc = [MAURLocation fromCLLocation:location];
        [self.delegate onLocationChanged:bgloc];
    }
}

- (void) onError:(NSError*)error
{
    [self.delegate onError:error];
}

- (void) onPause:(CLLocationManager*)manager
{
    [self.delegate onLocationPause];
}

- (void) onResume:(CLLocationManager*)manager
{
    [self.delegate onLocationResume];
}

- (void) onSwitchMode:(MAUROperationalMode)mode
{
}

- (void) onDestroy {
    NSLog(@"Destroying %@ ", TAG);
    [self onStop:nil];
}

- (void) dealloc
{
    //    locationController.delegate = nil;
}

@end
