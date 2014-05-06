//
//  SBBeaconManager.h
//  SBBeaconManagerExample
//
//  Created by Cory Hymel on 2/3/14.
//  Copyright (c) 2014 Simble. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>
#import "SBBeacon.h"


/**
 The comapny identifier to initilize CLBeaconRegion
 */
#define kManufacturerUUID @"52af17a0-2a00-11e3-8224-0800200c9a66"

/**
 A region identifier to intilize CLBeaconRegion
 */
#define kRegionIdentifier @"com.Simble.myRegion"

/**
 Flex room for determining if user is facing a beacon. Lower value means a more precise direction is needed before updates are delivered.
 */
#define kHeadingTolerance 25.0f

/**
 How long a beacon can stay found after it's distance is unknown or it's RSSI is 0
 */
#define kBeaconRemovalTimerInterval 3.0

/**
 How long a beacon must be in range before alerting delegate
 */
#define kBeaconAddtionTimerInterval 2.0

/**
 Number of times a beacon must be consecutivly ranged with an RSSI of 0 before being removed
 */
#define kLostIterationThreshold 5

/**
 Represents the maximum deviation of where the magnetic heading may differ from the actual geomagnetic heading in degrees. The larger the number the larger deviation is needed to present calibartion view.
 */
#define kHeadingCalibrationThreshhold 10


/**
 Posted when a ranged SBBeacon RSSI values have been updated. Passes a userInfo dictionary with the corresponding SBBeacon.
 userInfo dictonary format: [SBBeacon that was update, @"sbBeacon"]
 */
#define kSBBeaconWasUpdatedNotification @"kSBBeaconWasUpdatedNotification"

/**
 Posted when PNBeaconManager is about to refresh beacon information from the server. A corresponding notification, kPNBeaconManagerDidRefreshBeacons is called after the refresh has been completed.
 
 @see PNBeaconManager
 */
#define kPNBeaconManagerWillRefreshBeacons @"kPNBeaconManagerWillRefreshBeacons"

/**
 Posted from BeaconController once refresh of SBBeacons from server has been called. A notification, kPNBeaconManagerDidRefreshBeacons, is posted before the refresh process begins.
 
 @see BeaconController
 */
#define kPNBeaconManagerDidRefreshBeacons @"kPNBeaconManagerDidRefreshBeacons"

/**
 *  The delegate of PNBeaconManager must adopt the PNBeaconManagerDelegate protocol.
 */
@protocol SBBeaconManagerDelegate <NSObject>


///---------------------------------------
/// @name Proximity Updates
///---------------------------------------

/**
 Called when a beacon has been lost
 @param beacon The beacon that has been lost
 */
- (void)didLoseBeacon:(SBBeacon*)beacon;

/**
 A new beacon has been ranged.
 @param beacon The new beacon that was ranged
 */
- (void)didFindBeacon:(SBBeacon*)beacon;


///---------------------------------------
/// @name Directional Updates
///---------------------------------------
/**
 When a beacons magnetic north, true north, and RSSI values from the server match the current heading and range.
 @param beacon The beacon that is being faced
 */
- (void)didStartFacingBeacon:(SBBeacon*)beacon;

/**
 When any of the magnetic north, true north, or RSSI values are broken
 @param beacon The beacon that was just being faced is no longer being faced
 */
- (void)didStopFacingBeacon:(SBBeacon*)beacon;


///---------------------------------------
/// @name Data Updates
///---------------------------------------

/**
 Called when beacon data has been completly refreshed from Parse server.
 */
- (void)didRefreshData;

@end


/**
 PNBeaconManager abstracts all iBeacon boiler plate code to allow simple interation with iBeacons. PNBeaconManagerDelegate sends callbacks when an iBeacon is found, lost, user facing, user stopped facing.
 
 
 #Parse#
 PNBeaconManager uses Parse as a backing server store to associate content with discovered iBeacons. A SBBeacon item on Parse is required to have the following variables:
 
 |  Variable Name  |  Type  |
 |-----------------|-------:|
 | proximityUUID   | String |
 | magneticHeading | Number |
 | trueHeading     | Number |
 | headingAccuracy | Number |
 | latitude        | Number |
 | longitude       | Number |
 | major           | Number |
 | minor           | Number |
 
 
 #Required Frameworks#
 
 ### PNBeaconManager
 The following frameworks are required:
 
 - CoreBluetooth.framework
 - CoreLocation.framework
 - Parse.framework
 
 ### Parse
 The following frameworks are required:
 
 - AudioToolbox.framework
 - CFNetwork.framework
 - CoreGraphics.framework
 - CoreLocation.framework
 - libz.1.1.3.dylib
 - MobileCoreServices.framework
 - QuartzCore.framework
 - Security.framework
 - StoreKit.framework
 - SystemConfiguration.framework
 
 
 For more information on how to setup Parse see http://www.parse.com .
 
 */
@interface SBBeaconManager : NSObject

/**
 @return Shared instance of PNBeaconManager
 */
+ (instancetype)sharedManager;


///---------------------------------------
/// @name Setup
///---------------------------------------
- (void)hookCLLocationManager:(CLLocationManager*)manager;


///---------------------------------------
/// @name Determining Device Capabilities
///---------------------------------------

/**
 Checks if the app is authorized to use location features. The authorization status of a given application is managed by the system and determined by several factors. Applications must be explicitly authorized to use location services by the user and location services must themselves currently be enabled for the system. A request for user authorization is displayed automatically when your application first attempts to use location services.
 
 @param completion Passes back current location authorization status as CLAuthorizationStatus
 
 @see CLLocationManager
 */
- (void)checkForEligibility:(void(^)(CLAuthorizationStatus status))completion;

/**
 Checks the current system for required hardware.
 
 `monitoring` Indicating whether the device supports CLBeaconRegion monitoring
 
 `ranging`    Indicating whether the device supports ranging of Bluetooth beacons
 
 `location`   Indicating whether location services are enabled on the device
 
 `heading`    Indicating whether the location manager is able to generate heading-related events
 
 @param completion Called when all systems have been checked
 */
- (void)checkForCapability:(void(^)(BOOL monitoring, BOOL ranging, BOOL location, BOOL heading))completion;


///---------------------------------------
/// @name Refreshing Data
///---------------------------------------

/**
 Refreshes the beacon data from Parse. While fetching occurs, if ranging is enabled, it is paused until download is complete.
 */
- (void)refreshBeaconData;

/**
 Refreshes the beacon data from Parse when a remote notification is received and the app is in the background. Calls the backbroundFetchResults completion handler when finished.
 
 @param completion Called once refresh has finished.
 */
- (void)refreshBeaconData:(void(^)(UIBackgroundFetchResult backgroundFetchResult, BOOL success))completion;


/**
 If the PNBeaconManager is currently refreshing beacon data. PNBeaconManager post kPNBeaconManagerWillRefreshBeacons before the refresh begins then BeaconController post kPNBeaconManagerDidRefreshBeacons once the refresh ends. isRefreshingBeaconData is KVO compliant.
 */
@property (nonatomic, readonly) BOOL isRefreshingBeaconData;

///---------------------------------------
/// @name Searching Control
///---------------------------------------

/**
 *  Start searching for beacons
 */
- (void)startRangingBeacons;

/**
 *  Stop searching for beacons
 */
- (void)stopRangingBeacons;

/**
 *  Start updating heading
 */
- (void)startUpdatingHeading;

/**
 *  Stop updating heading
 */
- (void)stopUpdatingHeading;

/**
 If the location manager is currently ranging beacons or not
 */
@property (nonatomic, readonly) BOOL isRangingBeacons;

/**
 If the location manager is currently updating heading
 */
@property (nonatomic, readonly) BOOL isUpdatingHeading;


///---------------------------------------
/// @name Syncing Heading
///---------------------------------------

/**
 Sync's a beacon with the server. If the beacon already exist on the server it will update its information. If the beacon is not already on the server, it will create a new instance of it on the server with all pertinent information.
 @param sbBeacon The beacon to be sync'd with the server
 @param completion Called when it's done sycing with the server. Error could represent a fetching error or a save (sync) error.
 */
- (void)syncHeadingForSBBeacon:(SBBeacon*)sbBeacon completion:(void(^)(NSError *error))completion;

/**
 Get all information required to sync current heading for a beacon.
 
 |   Key    |  Type  | Description                          |
 |----------|:------:|:------------------------------------:|
 | magNorth | String | Magnetic north of current heading    |
 | truNorth | Number | True north of current heading        |
 | accuracy | Number | Accuracy of current heading reading  |
 | latitude | Number | Current latitude location            |
 | longitude| Number | Current longitude location           |
 | altitude | Number | Current altitude                     |
 
 
 @return Dictionary of heading information
 */
- (NSDictionary*)syncableHeadingInformation;




///---------------------------------------
/// @name Receiving Updates
///---------------------------------------

/**
 Our delegate.
 */
@property (nonatomic, assign) id <SBBeaconManagerDelegate> delegate;

/**
 Filters SBBeacons sent to PNBeaconManagerDelegate.
 
 ####YES
 If you wish to have all SBBeacons encountered sent to delegate.
 ####NO
 If you wish to have only SBBeacons that exist on the Parse server sent to delegate.
 
 @note Default is set to `NO`.
 */
@property (nonatomic, assign) BOOL shouldAcknowledgeAllBeacons;

/**
 The current heading of the compass
 */
@property (nonatomic, strong) CLHeading *currentHeading;

/**
 If you wish to create a compass to show to the user, this image will rotate to always point to magnetic north.
 */
@property (nonatomic, assign) UIImageView *compassImg;

/**
 If you wish to create a compass to show to the user, this image will rotate to always point to true north.
 */
@property (nonatomic, assign) UIImageView *trueNorth;

/**
 Differnce between the compass and gyroscope
 */
@property (nonatomic, assign) UILabel *compassDif;

/**
 Current magnetic north heading.
 
 The value in this property represents the heading relative to the magnetic North Pole, which is different from the geographic North Pole. The value 0 means the device is pointed toward magnetic north, 90 means it is pointed east, 180 means it is pointed south, and so on. The value in this property should always be valid.
 */
@property (nonatomic, assign) UILabel *magNorthCompassHeading;

/**
 Current true north heading.
 
 The value in this property represents the heading relative to the geographic North Pole. The value 0 means the device is pointed toward true north, 90 means it is pointed due east, 180 means it is pointed due south, and so on. A negative value indicates that the heading could not be determined.
 
 @warning This property contains a valid value only if location updates are also enabled for the corresponding location manager object. Because the position of true north is different from the position of magnetic north on the Earth’s surface, CoreLocation needs the current location of the device to compute the value of this property.
 */
@property (nonatomic, assign) UILabel *trueNorthCompassHeading;

/**
 A positive value in this property represents the potential error between the value reported by the magneticHeading property and the actual direction of magnetic north. Thus, the lower the value of this property, the more accurate the heading. A negative value means that the reported heading is invalid, which can occur when the device is uncalibrated or there is strong interference from local magnetic fields.
 */
@property (nonatomic, assign) UILabel *headingAccuracy;

/**
 The latitude in degrees. Positive values indicate latitudes north of the equator. Negative values indicate latitudes south of the equator.
 */
@property (nonatomic, assign) UILabel *latitude;

/**
 The longitude in degrees. Measurements are relative to the zero meridian, with positive values extending east of the meridian and negative values extending west of the meridian.
 */
@property (nonatomic, assign) UILabel *longitude;

/**
 The altitude measured in meters. Positive values indicate altitudes above sea level. Negative values indicate altitudes below sea level.
 */
@property (nonatomic, assign) UILabel *altitude;

/**
 If you want tableView reloads when the beacons are ranged, you can set the tableView as reference here and addition/subtraction of data will take place automatically
 */
@property (nonatomic, assign) UITableView *subscribedTableView;




///---------------------------------------
/// @name Accessing Beacons
///---------------------------------------

/**
 All the beacons that are currently in range.
 */
@property (strong, nonatomic) NSMutableArray *foundSBBeacons;

/**
 All the beacons that are available on the server. Beacons in this array are not necessary within range.
 */
@property (strong, nonatomic) NSMutableArray *fetchedBeacons;

@end