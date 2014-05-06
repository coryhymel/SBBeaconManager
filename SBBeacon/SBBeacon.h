//
//  SBBeacon.h
//  SBBeaconManagerExample
//
//  Created by Cory Hymel on 2/3/14.
//  Copyright (c) 2014 Simble. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface SBBeacon : NSObject

///The associated CLBeacon
@property (strong, nonatomic) CLBeacon *beacon;

///ObjectID represending this beacon on the server
@property (strong, nonatomic) NSString *objectId;

@property (strong, nonatomic) NSString *proximityUUID;

@property (strong, nonatomic) NSNumber *major, *minor;

@property (strong, nonatomic) NSNumber *distance;

@property (strong, nonatomic) NSDate *createdAt, *updatedAt;

///Values that are set by the user. When a beacon is sync'd down from the server, these are set from that data. When a user sets a beacon, these are set as well as the corresponding values on the server.
@property (nonatomic) NSNumber *reqMagHeading;
@property (nonatomic) NSNumber *reqTruHeading;
@property (nonatomic) NSNumber *reqHeadingAccuracy;
@property (nonatomic) NSNumber *latitude, *longitude;
@property (nonatomic) NSNumber *rssi;

///If the beacons RSSI drops to 0, this timer is set to fire after 3 seconds. If the beacon is found again within that timeframe the timer is invalidated.
@property (nonatomic) NSTimer *removalTimer;

/**
 *  When the beacon is found, it's RSSI cannot drop to 0 for a given period before being added
 */
@property (nonatomic, strong) NSTimer *additionTimer;

/**
 *  The number of times its RSSI has been 0 consecutivly
 */
@property (nonatomic) NSInteger numberLostIterations;

@end
