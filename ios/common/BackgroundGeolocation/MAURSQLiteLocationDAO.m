//
//  MAURSQLiteLocationDAO.m
//  BackgroundGeolocation
//
//  Created by Marian Hello on 10/06/16.
//

#import <sqlite3.h>
#import <CoreLocation/CoreLocation.h>
#import "MAURSQLiteHelper.h"
#import "MAURGeolocationOpenHelper.h"
#import "MAURSQLiteLocationDAO.h"
#import "MAURLocationContract.h"

@implementation MAURSQLiteLocationDAO {
    FMDatabaseQueue* queue;
    MAURGeolocationOpenHelper *helper;
}

#pragma mark Singleton Methods

+ (instancetype) sharedInstance
{
    static MAURSQLiteLocationDAO *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });

    return instance;
}

- (id) init {
    if (self = [super init]) {
        helper = [[MAURGeolocationOpenHelper alloc] init];
        queue = [helper getWritableDatabase];
    }
    return self;
}

- (NSArray<MAURLocation*>*) getValidLocations
{
    __block NSMutableArray* locations = [[NSMutableArray alloc] init];
    
    NSString *sql = [[self getLocationSelectString] stringByAppendingString: @" WHERE " @LC_COLUMN_NAME_STATUS @" = ? ORDER BY " @LC_COLUMN_NAME_RECORDED_AT];

    [queue inDatabase:^(FMDatabase *database) {
        FMResultSet *rs = [database executeQuery:sql, [NSString stringWithFormat:@"%ld", MAURLocationPostPending]];
        while([rs next]) {
            MAURLocation *location = [self convertToLocation:rs];
            [locations addObject:location];
        }
        // TODO
        // NSLog(@"Retrieving locations failed code: %d: message: %s", sqlite3_errcode(database), sqlite3_errmsg(database));

        [rs close];
    }];

    return locations;
}

- (NSArray<MAURLocation*>*) getAllLocations
{
    __block NSMutableArray* locations = [[NSMutableArray alloc] init];

    NSString *sql = [[self getLocationSelectString] stringByAppendingString: @" ORDER BY " @LC_COLUMN_NAME_RECORDED_AT];

    [queue inDatabase:^(FMDatabase *database) {
        FMResultSet *rs = [database executeQuery:sql];
        while([rs next]) {
            MAURLocation *location = [self convertToLocation:rs];
            [locations addObject:location];
        }
        // TODO
        // NSLog(@"Retrieving locations failed code: %d: message: %s", sqlite3_errcode(database), sqlite3_errmsg(database));

        [rs close];
    }];

    return locations;
}

- (NSArray<MAURLocation*>*) getLocationsForSync
{
    __block NSMutableArray* locations = [[NSMutableArray alloc] init];

    [queue inTransaction:^(FMDatabase *database, BOOL *rollback) {
        NSString *sql = [[self getLocationSelectString] stringByAppendingString: @" WHERE " @LC_COLUMN_NAME_STATUS @" = ? ORDER BY " @LC_COLUMN_NAME_RECORDED_AT];

        FMResultSet *rs = [database executeQuery:sql, [NSString stringWithFormat:@"%ld", MAURLocationPostPending]];
        while([rs next]) {
            MAURLocation *location = [self convertToLocation:rs];
            [locations addObject:location];
        }
        [rs close];

        sql = @"UPDATE " @LC_TABLE_NAME @" SET " @LC_COLUMN_NAME_STATUS @" = ?";
        if (![database executeUpdate:sql, [NSString stringWithFormat:@"%ld", MAURLocationDeleted]]) {
            NSLog(@"Deleting all location failed code: %d: message: %@", [database lastErrorCode], [database lastErrorMessage]);
        }
    }];

    return locations;

}

- (NSNumber*) getLocationsForSyncCount
{
    __block NSNumber* rowCount = nil;

    [queue inTransaction:^(FMDatabase *database, BOOL *rollback) {
        NSString *sql = @"SELECT COUNT(*) FROM " @LC_TABLE_NAME @" WHERE " @LC_COLUMN_NAME_STATUS @" = ?";

        FMResultSet *rs = [database executeQuery:sql, [NSString stringWithFormat:@"%ld", MAURLocationPostPending]];
        if ([rs next]) {
            rowCount = [NSNumber numberWithInt:[rs intForColumnIndex:0]];
        }
        [rs close];
    }];

    return rowCount;
}

// NOTE: Persisting location is not used for functionality.
// When resolving merge conflicts, always overwrite from remote and replace these methods with placeholders again.
- (NSNumber*) persistLocation:(MAURLocation*)location intoDatabase:(FMDatabase*)database
{
    return 0;  
}

- (NSNumber*) persistLocation:(MAURLocation*)location
{
    return 0;
}

- (NSNumber*) persistLocation:(MAURLocation*)location limitRows:(NSInteger)maxRows
{
    return 0;
}

- (BOOL) deleteLocation:(NSNumber*)locationId error:(NSError * __autoreleasing *)outError
{
    __block BOOL success;
    NSString *sql = @"UPDATE " @LC_TABLE_NAME @" SET " @LC_COLUMN_NAME_STATUS @" = ? WHERE " @LC_COLUMN_NAME_ID @" = ?";

    [queue inDatabase:^(FMDatabase *database) {
        if ([database executeUpdate:sql, [NSString stringWithFormat:@"%ld", MAURLocationDeleted], locationId]) {
            success = YES;
        } else {
            int errorCode = [database lastErrorCode];
            NSString *errorMessage = [database lastErrorMessage];
            NSLog(@"Delete location %@ failed code: %d: message: %@", locationId, errorCode, errorMessage);

            if (outError != NULL) {
                NSDictionary *errorDictionary = @{
                                                  NSLocalizedDescriptionKey: NSLocalizedString(errorMessage, nil)
                                                  };
                *outError = [NSError errorWithDomain:Domain code:errorCode userInfo:errorDictionary];
            }

            success = NO;
        }
    }];

    return success;
}

- (BOOL) deleteAllLocations:(NSError * __autoreleasing *)outError
{
    __block BOOL success;
    NSString *sql = @"UPDATE " @LC_TABLE_NAME @" SET " @LC_COLUMN_NAME_STATUS @" = ?";

    [queue inDatabase:^(FMDatabase *database) {
        if ([database executeUpdate:sql, [NSString stringWithFormat:@"%ld", MAURLocationDeleted]]) {
            success = YES;
        } else {
            int errorCode = [database lastErrorCode];
            NSString *errorMessage = [database lastErrorMessage];
            NSLog(@"Deleting all locations failed code: %d: message: %@", errorCode, errorMessage);

            if (outError != NULL) {
                NSDictionary *errorDictionary = @{
                                                  NSLocalizedDescriptionKey: NSLocalizedString(errorMessage, nil)
                                                  };
                *outError = [NSError errorWithDomain:Domain code:errorCode userInfo:errorDictionary];
            }

            success = NO;
        }
    }];

    return success;
}

- (BOOL) clearDatabase
{
    __block BOOL success;

    [queue inDatabase:^(FMDatabase *database) {
        NSString *sql = [NSString stringWithFormat: @"DROP TABLE %@", @LC_TABLE_NAME];
        if (![database executeStatements:sql]) {
            NSLog(@"%@ failed code: %d: message: %@", sql, [database lastErrorCode], [database lastErrorMessage]);
        }
        sql = [MAURLocationContract createTableSQL];
        if (![database executeStatements:sql]) {
            NSLog(@"%@ failed code: %d: message: %@", sql, [database lastErrorCode], [database lastErrorMessage]);
            success = NO;
        } else {
            success = YES;
        }
    }];

    return success;
}

- (NSString*) getDatabaseName
{
    return [helper getDatabaseName];
}

- (NSString*) getDatabasePath
{
    return [helper getDatabasePath];
}

- (NSString*) getLocationSelectString {
    return @"SELECT " @LC_COLUMN_NAME_ID
    @COMMA_SEP @LC_COLUMN_NAME_TIME
    @COMMA_SEP @LC_COLUMN_NAME_ACCURACY
    @COMMA_SEP @LC_COLUMN_NAME_SPEED
    @COMMA_SEP @LC_COLUMN_NAME_BEARING
    @COMMA_SEP @LC_COLUMN_NAME_ALTITUDE
    @COMMA_SEP @LC_COLUMN_NAME_LATITUDE
    @COMMA_SEP @LC_COLUMN_NAME_LONGITUDE
    @COMMA_SEP @LC_COLUMN_NAME_PROVIDER
    @COMMA_SEP @LC_COLUMN_NAME_LOCATION_PROVIDER
    @COMMA_SEP @LC_COLUMN_NAME_STATUS
    @COMMA_SEP @LC_COLUMN_NAME_RECORDED_AT
    @" FROM " @LC_TABLE_NAME;
}

- (MAURLocation*) convertToLocation:(FMResultSet*)rs {
    MAURLocation *location = [[MAURLocation alloc] init];
    location.locationId = [NSNumber numberWithLongLong:[rs longLongIntForColumnIndex:0]];
    NSTimeInterval timestamp = [rs doubleForColumnIndex:1];
    location.time = [NSDate dateWithTimeIntervalSince1970:timestamp];
    location.accuracy = [NSNumber numberWithDouble:[rs doubleForColumnIndex:2]];
    location.speed = [NSNumber numberWithDouble:[rs doubleForColumnIndex:3]];
    location.heading = [NSNumber numberWithDouble:[rs doubleForColumnIndex:4]];
    location.altitude = [NSNumber numberWithDouble:[rs doubleForColumnIndex:5]];
    location.latitude = [NSNumber numberWithDouble:[rs doubleForColumnIndex:6]];
    location.longitude = [NSNumber numberWithDouble:[rs doubleForColumnIndex:7]];
    location.provider = [rs stringForColumnIndex:8];
    location.locationProvider = [NSNumber numberWithInt:[rs intForColumnIndex:9]];
    location.isValid = [rs intForColumnIndex:10] == 1 ? YES : NO;
    NSTimeInterval recordedAt = [rs longForColumnIndex:11];
    location.recordedAt = [NSDate dateWithTimeIntervalSince1970:recordedAt];
    return location;
}

- (void) dealloc {
    [helper close];
    [queue close];
    helper = nil;
    queue = nil;
}

@end
