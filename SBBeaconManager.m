//
//  SBBeaconManager.m
//  SBBeaconManagerExample
//
//  Created by Cory Hymel on 2/3/14.
//  Copyright (c) 2014 Simble. All rights reserved.
//

#import "SBBeaconManager.h"

#import <Parse/Parse.h>
#import <CoreBluetooth/CoreBluetooth.h>


#define CC_RADIANS_TO_DEGREES(__ANGLE__) ((__ANGLE__) / (float)M_PI * 180.0f)

#define radianConst M_PI/180.0

@interface SBBeaconManager () <CLLocationManagerDelegate> {
    
    float       currentMagHeading;
    float       currentTruHeading;
    float       currentAccuracy;
    
    CLLocation  *currentLocation;
}

@property (nonatomic) BOOL beaconRequireHeading;

@property (strong, nonatomic) CLBeaconRegion    *beaconRegion;
@property (strong, nonatomic) CLLocationManager *locationManager;

@property (strong, nonatomic) CBCentralManager  *centralManager;
@property (strong, nonatomic) CBPeripheral      *discoveredPeripheral;

@property (strong, nonatomic) SBBeacon          *currentlyFacingBeacon;



@end

@implementation SBBeaconManager

+ (instancetype)sharedManager {
    static SBBeaconManager *_sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _sharedInstance = [[SBBeaconManager alloc] init];
    });
    
    return _sharedInstance;
}

- (id)init {
    self = [super init];
    
    self.shouldAcknowledgeAllBeacons = NO;
    self.beaconRequireHeading        = NO;
    
    self->_isRangingBeacons  = NO;
    self->_isUpdatingHeading = NO;
    
    self->_isRefreshingBeaconData = NO;
    
    NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:kManufacturerUUID];
    self.beaconRegion = [[CLBeaconRegion alloc] initWithProximityUUID:uuid identifier:kRegionIdentifier];
    
    self.beaconRegion.notifyEntryStateOnDisplay = YES;
    self.beaconRegion.notifyOnEntry = YES;
    self.beaconRegion.notifyOnExit = YES;
    
    self.currentlyFacingBeacon = nil;
    
    [self findObjects:nil];
    
    return self;
}

#pragma mark -
#pragma mark - Setup
- (void)hookCLLocationManager:(CLLocationManager*)manager {
    self.locationManager = manager;
    self.locationManager.delegate = self;
}


#pragma mark -
#pragma mark - System checks
- (void)checkForEligibility:(void(^)(CLAuthorizationStatus status))completion {
    completion([CLLocationManager authorizationStatus]);
}

- (void)checkForCapability:(void(^)(BOOL monitoring, BOOL ranging, BOOL location, BOOL heading))completion {
    completion([CLLocationManager isMonitoringAvailableForClass:[self.beaconRegion class]],
               [CLLocationManager isRangingAvailable],
               [CLLocationManager locationServicesEnabled],
               [CLLocationManager headingAvailable]);
}

- (void)locationManager:(CLLocationManager *)manager didChangeAuthorizationStatus:(CLAuthorizationStatus)status {}

#pragma mark -
#pragma mark - Refreshing data

- (void)refreshBeaconData {
    
    [self willChangeValueForKey:@"isRefreshingBeaconData"];
    self->_isRefreshingBeaconData = YES;
    [self didChangeValueForKey:@"isRefreshingBeaconData"];
    
    //Let everyone know we are about to begin refreshing beacon data
    [[NSNotificationCenter defaultCenter] postNotificationName:kPNBeaconManagerWillRefreshBeacons object:nil];
    
    //Get a hook back so we know when BeaconController is done parsing through the new data
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(beaconRefreshCompleted) name:kPNBeaconManagerDidRefreshBeacons object:nil];
    
    BOOL wasRanging = self.isRangingBeacons;
    BOOL wasHeading = self.isUpdatingHeading;
    
    [self stopRangingBeacons];
    [self stopUpdatingHeading];
    
    [self findObjects:^(BOOL success) {
        
        if (success) {
            
            if (wasRanging)
                [self startRangingBeacons];
            
            if (wasHeading)
                [self startUpdatingHeading];
            
        }
        
        [self.delegate didRefreshData];
    }];
}

- (void)refreshBeaconData:(void(^)(UIBackgroundFetchResult backgroundFetchResult, BOOL success))completion {
    
}

- (void)beaconRefreshCompleted {
    
    [self willChangeValueForKey:@"isRefreshingBeaconData"];
    self->_isRefreshingBeaconData = NO;
    [self didChangeValueForKey:@"isRefreshingBeaconData"];
    
    //Remove the observer since it's added when refresh is called
    [[NSNotificationCenter defaultCenter] removeObserver:self name:kPNBeaconManagerDidRefreshBeacons object:nil];
}


#pragma mark -
#pragma mark - Searching start/stop
- (void)startRangingBeacons {
    if (self.isRangingBeacons)return;
    
    if (self.beaconRequireHeading)
        [self startUpdatingHeading];
    
    self->_isRangingBeacons = YES;
    
    [self.locationManager startMonitoringForRegion:self.beaconRegion];
}
- (void)stopRangingBeacons {
    
    if (!self.isRangingBeacons)return;
    
    if (self.beaconRequireHeading)
        [self stopUpdatingHeading];
    
    self->_isRangingBeacons = NO;
    
    [self.locationManager stopMonitoringForRegion:self.beaconRegion];
}

- (void)startUpdatingHeading {
    if (self.isUpdatingHeading) return;
    
    self->_isUpdatingHeading = YES;
    
    [self.locationManager startUpdatingHeading];
    [self.locationManager startUpdatingLocation];
}
- (void)stopUpdatingHeading {
    if (!self.isUpdatingHeading) return;
    
    self->_isUpdatingHeading = NO;
    
    [self.locationManager stopUpdatingHeading];
    [self.locationManager stopUpdatingLocation];
}

#pragma mark -
#pragma mark - Server interaction
- (void)findObjects:(void(^)(BOOL success))completion {
    
    self.fetchedBeacons = [NSMutableArray new];
    
    PFQuery *query = [PFQuery queryWithClassName:@"SBBeacon"];
    [query findObjectsInBackgroundWithBlock:^(NSArray *objects, NSError *error) {
        
        if (!error) {
            
            for (PFObject *object in objects) {
                
                SBBeacon *beacon = [self createSBBeaconFromPFObject:object];
                
                [self.fetchedBeacons addObject:beacon];
            }
            
            if (completion)
                completion(YES);
            
        } else {
            
            if (completion)
                completion(NO);
            // Log details of the failure
            NSLog(@"Error fetching beacons from server:\n ---%@\n ---%@", error, [error userInfo]);
        }
    }];
}

- (void)updateObjects:(void(^)(BOOL success))completion {
    
    PFQuery *query = [PFQuery queryWithClassName:@"SBBeacon"];
    [query findObjectsInBackgroundWithBlock:^(NSArray *objects, NSError *error) {
        
        if (!error) {
            
            for (PFObject *object in objects) {
                
                NSPredicate *sPredicate = [NSPredicate predicateWithFormat:@"(major == %@) && (minor == %@)", [object objectForKey:@"major"], [object objectForKey:@"minor"]];
                
                NSArray *existingBeacons = [self.foundSBBeacons filteredArrayUsingPredicate:sPredicate];
                
                if (existingBeacons && existingBeacons.count > 0) {
                    
                    SBBeacon *existingBeacon = existingBeacons[0];
                    
                    //The updated at dates are different
                    if ([existingBeacon.updatedAt compare:object.updatedAt] == NSOrderedDescending && [existingBeacon.updatedAt compare:object.updatedAt] == NSOrderedAscending) {
                        [self updateSBBeacon:existingBeacon fromPFObject:object];
                        
                    }
                    //The updated at dates are the same so we don't have to do anything
                    else {}
                }
                
                
                SBBeacon *beacon = [SBBeacon new];
                
                beacon.proximityUUID        = [object objectForKey:@"proximityUUID"];
                beacon.objectId             = object.objectId;
                
                beacon.createdAt            = object.createdAt;
                beacon.updatedAt            = object.updatedAt;
                
                beacon.distance             = [object objectForKey:@"distance"];
                
                beacon.reqMagHeading        = [object objectForKey:@"magneticHeading"];
                beacon.reqTruHeading        = [object objectForKey:@"trueHeading"];
                beacon.reqHeadingAccuracy   = [object objectForKey:@"headingAccuracy"];
                
                beacon.rssi                 = [object objectForKey:@""];
                beacon.latitude             = [object objectForKey:@"latitude"];
                beacon.longitude            = [object objectForKey:@"longitude"];
                beacon.major                = [object objectForKey:@"major"];
                beacon.minor                = [object objectForKey:@"minor"];
                
                if (beacon.reqMagHeading && beacon.reqTruHeading) {
                    self.beaconRequireHeading = YES;
                    
                    if (!self.isUpdatingHeading)
                        [self performSelectorOnMainThread:@selector(startUpdatingHeading) withObject:nil waitUntilDone:NO];
                }
                
                [self.fetchedBeacons addObject:beacon];
            }
            
            if (completion)
                completion(YES);
            
        } else {
            
            if (completion)
                completion(NO);
            // Log details of the failure
            NSLog(@"Error fetching beacons from server:\n ---%@\n ---%@", error, [error userInfo]);
        }
    }];
}

- (SBBeacon*)createSBBeaconFromPFObject:(PFObject*)object {
    SBBeacon *beacon = [SBBeacon new];
    
    beacon.proximityUUID        = [object objectForKey:@"proximityUUID"];
    beacon.objectId             = object.objectId;
    
    beacon.createdAt            = object.createdAt;
    beacon.updatedAt            = object.updatedAt;
    
    beacon.distance             = [object objectForKey:@"distance"];
    
    beacon.reqMagHeading        = [object objectForKey:@"magneticHeading"];
    beacon.reqTruHeading        = [object objectForKey:@"trueHeading"];
    beacon.reqHeadingAccuracy   = [object objectForKey:@"headingAccuracy"];
    
    beacon.rssi                 = [object objectForKey:@""];
    beacon.latitude             = [object objectForKey:@"latitude"];
    beacon.longitude            = [object objectForKey:@"longitude"];
    beacon.major                = [object objectForKey:@"major"];
    beacon.minor                = [object objectForKey:@"minor"];
    
    if (beacon.reqMagHeading && beacon.reqTruHeading) {
        self.beaconRequireHeading = YES;
        
        if (!self.isUpdatingHeading)
            [self performSelectorOnMainThread:@selector(startUpdatingHeading) withObject:nil waitUntilDone:NO];
    }
    
    return beacon;
}

- (void)updateSBBeacon:(SBBeacon*)sbBeacon fromPFObject:(PFObject*)object {
    
    sbBeacon.proximityUUID        = [object objectForKey:@"proximityUUID"];
    sbBeacon.objectId             = object.objectId;
    
    sbBeacon.createdAt            = object.createdAt;
    sbBeacon.updatedAt            = object.updatedAt;
    
    sbBeacon.distance             = [object objectForKey:@"distance"];
    
    sbBeacon.reqMagHeading        = [object objectForKey:@"magneticHeading"];
    sbBeacon.reqTruHeading        = [object objectForKey:@"trueHeading"];
    sbBeacon.reqHeadingAccuracy   = [object objectForKey:@"headingAccuracy"];
    
    sbBeacon.rssi                 = [object objectForKey:@""];
    sbBeacon.latitude             = [object objectForKey:@"latitude"];
    sbBeacon.longitude            = [object objectForKey:@"longitude"];
    sbBeacon.major                = [object objectForKey:@"major"];
    sbBeacon.minor                = [object objectForKey:@"minor"];
    
    if (sbBeacon.reqMagHeading && sbBeacon.reqTruHeading) {
        self.beaconRequireHeading = YES;
        
        if (!self.isUpdatingHeading)
            [self performSelectorOnMainThread:@selector(startUpdatingHeading) withObject:nil waitUntilDone:NO];
    }
}



#pragma mark -
#pragma mark - Public methods
- (NSDictionary*)syncableHeadingInformation {
    return @{@"magNorth":@(currentMagHeading),
             @"truNorth":@(currentTruHeading),
             @"accuracy":@(currentAccuracy),
             @"latitude":@(currentLocation.coordinate.latitude),
             @"longitude":@(currentLocation.coordinate.longitude),
             @"altitude":@(currentLocation.altitude)};
}

- (void)syncHeadingForSBBeacon:(SBBeacon*)sbBeacon completion:(void(^)(NSError *error))completion {
    
    PFQuery *query = [PFQuery queryWithClassName:@"SBBeacon"];
    
    if (sbBeacon.objectId) {
        
        [query getObjectInBackgroundWithId:sbBeacon.objectId block:^(PFObject *gameScore, NSError *error) {
            
            if (error) {
                completion(error);
                return;
            }
            
            //Save the updated values in the background
            [[self formatPFObjectFromBeacon:gameScore beacon:sbBeacon] saveInBackgroundWithBlock:^(BOOL succeeded, NSError *error) {
                if (error) {
                    completion(error);
                }
                else {
                    completion(nil);
                }
            }];
        }];
    }
    
    else {
        
        PFObject *gameScore = [self formatPFObjectFromBeacon:nil beacon:sbBeacon];
        
        //Save the updated values in the background
        [gameScore saveInBackgroundWithBlock:^(BOOL succeeded, NSError *error) {
            
            if (error) {
                completion(error);
            }
            else {
                completion(nil);
            }
        }];
    }
}

#pragma mark -
#pragma mark - Private methods

/**
 Creates a beacon object that can be sync'd with the server.
 @param object PFObject if you are fetching an existing one from the server. (Optional)
 @param sbBeacon The beacon that needs to be sync'd. (required)
 @return A PFObject that is ready to sync with Parse server.
 */
- (PFObject*)formatPFObjectFromBeacon:(PFObject*)object beacon:(SBBeacon*)sbBeacon {
    
    PFObject *beacon;
    
    if (!beacon) {
        beacon = [PFObject objectWithClassName:@"SBBeacon"];
    }
    else {
        beacon = object;
    }
    
    //Update the values of the beacon object
    beacon[@"magneticHeading"] = @(self.currentHeading.magneticHeading);
    beacon[@"trueHeading"]     = @(self.currentHeading.trueHeading);
    beacon[@"headingAccuracy"] = @(self.currentHeading.headingAccuracy);
    beacon[@"latitude"]        = @(self.locationManager.location.coordinate.latitude);
    beacon[@"longitude"]       = @(self.locationManager.location.coordinate.longitude);
    beacon[@"rssi"]            = sbBeacon.rssi;
    beacon[@"major"]           = sbBeacon.major;
    beacon[@"minor"]           = sbBeacon.minor;
    beacon[@"distance"]        = sbBeacon.distance;
    
    return beacon;
}

/**
 If PNBeaconManager should notify delegate of SBBeacon interaction.
 @param sbBeacon SBBeacon that needs evaluation
 @return If the sbBeacon should be sent to delegate
 
 @see shouldAcknowledgeAllBeacons
 */
- (BOOL)shouldNotifyDelegateOfBeacon:(SBBeacon*)sbBeacon {
    
    if (self.shouldAcknowledgeAllBeacons || //If we want all found beacons to be sent to our delegate
        (!self.shouldAcknowledgeAllBeacons && sbBeacon.objectId)) //We only want beacons that exist on the server returned
    {
        return YES;
    }
    else {
        return NO;
    }
    
}


#pragma mark -
#pragma mark - Beacon handling

- (void)locationManager:(CLLocationManager *)manager didDetermineState:(CLRegionState)state forRegion:(CLRegion *)region
{
    /*
     A user can transition in or out of a region while the application is not running. When this happens CoreLocation will launch the application momentarily, call this delegate method and we will let the user know via a local notification.
     */
    
    if(state == CLRegionStateInside)
    {
        [self.locationManager startRangingBeaconsInRegion:self.beaconRegion];
    }
    
    else if(state == CLRegionStateOutside)
    {
        
    }
    
    else
    {
        return;
    }
    
}

#pragma mark - CLLocationManager Delegate
- (void)locationManager:(CLLocationManager *)manager didStartMonitoringForRegion:(CLRegion *)region {
    [self.locationManager startRangingBeaconsInRegion:self.beaconRegion];
}

- (void)locationManager:(CLLocationManager *)manager didEnterRegion:(CLRegion *)region {
    [self.locationManager startRangingBeaconsInRegion:self.beaconRegion];
}

-(void)locationManager:(CLLocationManager *)manager didExitRegion:(CLRegion *)region {
    [self.locationManager stopRangingBeaconsInRegion:self.beaconRegion];
}

-(void)locationManager:(CLLocationManager *)manager didRangeBeacons:(NSArray *)beacons inRegion:(CLBeaconRegion *)region {
    
    //Alloc array if needed
    if (!self.foundSBBeacons)
        self.foundSBBeacons = [NSMutableArray new];
    
    [beacons enumerateObjectsUsingBlock:^(CLBeacon *beacon, NSUInteger idx, BOOL *stop) {
        
        //We look to see if we already have
        NSPredicate *searchPredicate = [NSPredicate predicateWithFormat:@"(minor == %@) AND (major == %@)", beacon.minor, beacon.major];
        
        //Find the beacon if it exist in our already found array
        NSArray *filteredArray = [self.foundSBBeacons filteredArrayUsingPredicate:searchPredicate];
        
        //If the beacon exist, we grab it.
        if (filteredArray.count > 0) {
            [self processExistingSBBeacon:[filteredArray objectAtIndex:0] withCLBeacon:beacon];
        }
        else {
            if (beacon.proximity != CLProximityUnknown && beacon.rssi != 0.0)
                [self processNewSBBeaconFromCLBeacon:beacon];
        }
        
    }];
}

#pragma mark - Beacon processing



- (void)processNewSBBeaconFromCLBeacon:(CLBeacon*)beacon {
    
    SBBeacon *foundBeacon = [SBBeacon new];
    
    //Set all the pertinent values
    foundBeacon.beacon = beacon;
    foundBeacon.rssi   = [NSNumber numberWithInteger:beacon.rssi];
    foundBeacon.major  = beacon.major;
    foundBeacon.minor  = beacon.minor;
    
    foundBeacon.numberLostIterations = 0;
    
    //Check through the beacons that we pulled from the server to see if any match. If they do, then copy over the pertinent values
    NSArray *compared = [self.fetchedBeacons filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"(minor == %@) AND (major == %@)", beacon.minor, beacon.major]];
    if (compared.count > 0) {
        SBBeacon *syncdBeacon = [compared objectAtIndex:0];
        foundBeacon.reqMagHeading       = syncdBeacon.reqMagHeading;
        foundBeacon.reqTruHeading       = syncdBeacon.reqTruHeading;
        foundBeacon.reqHeadingAccuracy  = syncdBeacon.reqHeadingAccuracy;
        foundBeacon.objectId            = syncdBeacon.objectId;
        foundBeacon.latitude            = syncdBeacon.latitude;
        foundBeacon.longitude           = syncdBeacon.longitude;
        foundBeacon.rssi                = syncdBeacon.rssi;
        foundBeacon.distance            = syncdBeacon.distance;
    }
    
    //Check to see if we should notify our delegate
    if ([self shouldNotifyDelegateOfBeacon:foundBeacon]) {
        foundBeacon.additionTimer = [NSTimer scheduledTimerWithTimeInterval:kBeaconAddtionTimerInterval target:self selector:@selector(newSBBeaconWasFound:) userInfo:@{@"beacon":foundBeacon} repeats:NO];
    }
    
    [self.foundSBBeacons addObject:foundBeacon];
}

- (BOOL)checkRSSIToServer:(SBBeacon*)sbBeacon withCLBeacon:(CLBeacon*)beacon {
    
    if (((sbBeacon.distance.integerValue == 0) && (beacon.proximity == CLProximityImmediate)) ||
        ((sbBeacon.distance.integerValue == 1) && (beacon.proximity == CLProximityNear)) ||
        ((sbBeacon.distance.integerValue == 2) && (beacon.proximity == CLProximityFar)) ||
        (sbBeacon.distance == nil)) {
        
        return YES;
        
    }
    else {
        return NO;
    }
}

- (void)processExistingSBBeacon:(SBBeacon*)sbBeacon withCLBeacon:(CLBeacon*)beacon {
    
    //The proximity and distance to the beacon is not known
    if (beacon.proximity == CLProximityUnknown || beacon.rssi == 0.0) {
        
        //Check to see if we've reached our lost iteration threshold
        if (sbBeacon.numberLostIterations == kLostIterationThreshold) {
            
            //If the beacon hasn't been found in X checks but is still waiting to notify delegate it's there, we stop the addTimer so it doesn't
            if (sbBeacon.additionTimer) {
                [sbBeacon.additionTimer invalidate]; sbBeacon.additionTimer = nil;
            }
            
            //Let everyone know we lost the beacon
            [self existingSBBeaconWasLost:sbBeacon];
        }
        
        //We havn't reached our threshold so we increment
        else {
            sbBeacon.numberLostIterations++;
        }
        
    }
    
    //The proximity is valid so reset the number of lost iterations. This would also be the place to add checks if we want to be able to specify a distance for a server beacon.
    else {
        
        if (sbBeacon.additionTimer) return;
        
        sbBeacon.numberLostIterations = 0;
        
        //Assign the updated values to the existing SBBeacon
        sbBeacon.rssi = @(beacon.rssi);
        sbBeacon.beacon = beacon;
        
        
        //Check to see if we should notify our delegate
        if ([self shouldNotifyDelegateOfBeacon:sbBeacon]) {
            
            [[NSNotificationCenter defaultCenter] postNotificationName:kSBBeaconWasUpdatedNotification object:nil userInfo:[NSDictionary dictionaryWithObject:sbBeacon forKey:@"sbBeacon"]];
            
            if (self.subscribedTableView) {
                [self.subscribedTableView reloadData];
            }
        }
        
    }
}

#pragma mark - Beacon helpers
/**
 *  Notifies the delegate that a new beacon was found
 *
 *  @param timer Timer containing the newly found beacon
 */
- (void)newSBBeaconWasFound:(NSTimer*)timer {
    
    NSAssert([NSThread mainThread], @"I have to be on the main thread!");
    
    SBBeacon *newBeacon = [timer.userInfo objectForKey:@"beacon"];
    
    [newBeacon.additionTimer invalidate]; newBeacon.additionTimer = nil;
    
    if (!newBeacon)
        return;
    
    //If the beacon requires a heading then we don't notify for didFindBeacon
    if (![self sbBeaconRequiredHeading:newBeacon] && [self shouldNotifyDelegateOfBeacon:newBeacon]) {
        if ([self.delegate respondsToSelector:@selector(didFindBeacon:)]) {
            [self.delegate didFindBeacon:newBeacon];
        }
    }
    
    
    //If we have a subscribed table view, we add the rows
    if (self.subscribedTableView) {
        
        //Placeholder until below is fixed
        [self.subscribedTableView reloadData];
        
        /*
         BUG
         12.18.13
         
         This is causing the following error:
         
         Assertion failure in -[UITableView _endCellAnimationsWithContext:]
         
         I believe it is becuase we are adding the sbBeacon to self.foundSBBeacons in -processNewSBBeaconFromCLBeacon rather that in this method once it's addition timer has fired. So the number of expectied rows for the subscribed table does not match up correctly.
         
         [self.subscribedTableView beginUpdates];
         [self.subscribedTableView insertRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:self.foundSBBeacons.count - 1 inSection:0]] withRowAnimation:UITableViewRowAnimationAutomatic];
         [self.subscribedTableView endUpdates];
         */
    }
}

/**
 *  An existing beacon was lost
 *
 *  @param sbBeacon The beacon that was lost
 */
- (void)existingSBBeaconWasLost:(SBBeacon*)sbBeacon {
    
    NSLog(@"existingSBBeaconWasLost");
    
    [self.foundSBBeacons removeObject:sbBeacon];
    
    if ([self shouldNotifyDelegateOfBeacon:sbBeacon]) //We only want beacons that exist on the server returned
    {
        
        //If a beacon required heading and we lost it for some reason
        if ([self sbBeaconRequiredHeading:sbBeacon]) {
            if (self.currentlyFacingBeacon == sbBeacon) {
                if ([self.delegate respondsToSelector:@selector(didStopFacingBeacon:)]) {
                    [self.delegate didStopFacingBeacon:self.currentlyFacingBeacon];
                    self.currentlyFacingBeacon = nil;
                }
            }
        }
        
        //The beacon does not require a heading so deal with it normally
        else {
            if ([self.delegate respondsToSelector:@selector(didLoseBeacon:)]) {
                [self.delegate didLoseBeacon:sbBeacon];
            }
            
            if (self.subscribedTableView) {
                [self.subscribedTableView reloadData];
            }
        }
    }
}


#pragma mark -
#pragma mark - Heading handling

- (void)locationManager:(CLLocationManager *)manager didUpdateToLocation: (CLLocation *)newLocation fromLocation:(CLLocation *)oldLocation
{
    currentLocation = newLocation;
    
    if (self.latitude)
        self.latitude.text = [NSString stringWithFormat:@"%0.2f°", newLocation.coordinate.latitude];
    
    if (self.longitude)
        self.longitude.text = [NSString stringWithFormat:@"%0.2f°", newLocation.coordinate.longitude];
    
    if (self.altitude)
        self.altitude.text = [NSString stringWithFormat:@"%0.2fft", newLocation.altitude];
}

- (void)locationManager:(CLLocationManager *)manager didUpdateHeading:(CLHeading *)newHeading
{
    // Update variable updateHeading to be used in updater method
    
    float headingFloat = 0 - newHeading.magneticHeading;
    
    self.currentHeading = newHeading;
    
    [self checkForFacingBeacons];
    
    currentMagHeading = newHeading.magneticHeading;
    currentTruHeading = newHeading.trueHeading;
    currentAccuracy   = newHeading.headingAccuracy;
    
    if (self.magNorthCompassHeading)
        self.magNorthCompassHeading.text = [NSString stringWithFormat:@"%0.2f°", newHeading.magneticHeading];
    
    if (self.trueNorthCompassHeading)
        self.trueNorthCompassHeading.text = [NSString stringWithFormat:@"%0.2f°", newHeading.trueHeading];
    
    if (self.headingAccuracy)
        self.headingAccuracy.text = [NSString stringWithFormat:@"%0.2f", newHeading.headingAccuracy];
    
    // Update rotation of graphic compassImg
    if (self.compassImg)
        self.compassImg.transform = CGAffineTransformMakeRotation(headingFloat *radianConst);
    
    // Update rotation of graphic trueNorth
    if (self.trueNorth)
        self.trueNorth.transform = CGAffineTransformMakeRotation(headingFloat*radianConst);
}

- (BOOL)locationManagerShouldDisplayHeadingCalibration:(CLLocationManager *)manager{
    
    // Got nothing, We can assume we got to calibrate.
    if( !self.currentHeading ) {
        return YES;
    }
    
    // 0 means invalid heading. we probably need to calibrate
    else if( self.currentHeading.headingAccuracy < 0 ) {
        return YES;
    }
    
    // 5 degrees is a small value correct for my needs. Tweak yours according to your needs.
    else if( self.currentHeading.headingAccuracy > kHeadingCalibrationThreshhold ) {
        return YES;
    }
    
    // All is good. Compass is precise enough.
    else {
        return NO;
    }
}

#pragma mark - Heading helpers

- (void)checkForFacingBeacons {
    
    //Per documenation: If the headingAccuracy property contains a negative value, the value in this property should be considered unreliable.
    if (self.currentHeading.magneticHeading < 0)
        return;
    
    [self.foundSBBeacons enumerateObjectsUsingBlock:^(SBBeacon *sbBeacon, NSUInteger idx, BOOL *stop) {
        
        if (![self sbBeaconRequiredHeading:sbBeacon]) {
            return;
        }
        
        //We have to wait until it is actually added before trying to compare heading values. This keeps it from flashing as found or not found.
        if (sbBeacon.additionTimer) {
            return;
        }
        
        if ((sbBeacon.reqMagHeading.floatValue >= (self.currentHeading.magneticHeading - kHeadingTolerance)) &&
            (sbBeacon.reqMagHeading.floatValue <= (self.currentHeading.magneticHeading + kHeadingTolerance)))
        {
            
            //We are already looking at a beacon
            if (self.currentlyFacingBeacon) {
                
                //Check to see if it's a different beacon than self.currentlyFacingBeacon, if it is different, we need to tell our delegate
                if (self.currentlyFacingBeacon.beacon.minor.floatValue != sbBeacon.beacon.minor.floatValue) {
                    
                    //Check to see if we should notify our delegate that we are about to stop facing our old beacon
                    if ([self shouldNotifyDelegateOfBeacon:self.currentlyFacingBeacon]) {
                        [self.delegate didStopFacingBeacon:self.currentlyFacingBeacon];
                    }
                    
                    //Check to see if we should notify our delegate of the new beacon we are facing
                    if ([self shouldNotifyDelegateOfBeacon:sbBeacon]) {
                        [self.delegate didStartFacingBeacon:sbBeacon];
                    }
                }
                
            }
            
            //We have not looked at any beacon yet
            else {
                
                //Check to see if we should notify our delegate
                if ([self shouldNotifyDelegateOfBeacon:sbBeacon]) {
                    [self.delegate didStartFacingBeacon:sbBeacon];
                }
            }
            
            //Update the new one
            self.currentlyFacingBeacon = sbBeacon;
            
            //We are facing a beacon so no need to keep searching.
            *stop = YES;
            
        }
        
        //We were looking at a beacon, but now we are not.
        else if (self.currentlyFacingBeacon.beacon.minor.floatValue == sbBeacon.beacon.minor.floatValue){
            
            //Check to see if we should notify our delegate
            if ([self shouldNotifyDelegateOfBeacon:self.currentlyFacingBeacon]) {
                [self.delegate didStopFacingBeacon:self.currentlyFacingBeacon];
            }
            
            self.currentlyFacingBeacon = nil;
            
            //We don't put a *stop=YES call here because we do have to keep searching. We could be facing a new beacon.
        }
        
    }];
}

- (BOOL)sbBeaconRequiredHeading:(SBBeacon*)sbBeacon {
    if (sbBeacon.reqMagHeading && sbBeacon.reqTruHeading && sbBeacon.reqHeadingAccuracy)
        return YES;
    else
        return NO;
}

@end
