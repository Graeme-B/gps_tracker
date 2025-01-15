#import <Flutter/Flutter.h>
#import <Flutter/FlutterCodecs.h>
#import <CoreLocation/CoreLocation.h>
#import <CoreMotion/CoreMotion.h>
#import <QuartzCore/QuartzCore.h>
#import <math.h>

double const REPORTING_INTERVAL = 0.1;
double const EARTH_RADIUS       = 6378.137;
double const ONE_METRE          = (1.0/((2.0*M_PI/360.0)*EARTH_RADIUS))/1000.0;
double const ZERO_TOL           = 0.001;

@interface GpsTrackerEventHandler : NSObject<FlutterStreamHandler>
- (FlutterError* _Nullable)onListenWithArguments:(id _Nullable)arguments
                                       eventSink:(_Nonnull FlutterEventSink)events;
- (FlutterError* _Nullable)onCancelWithArguments:(id _Nullable)arguments;
- (void) updateLocation:( CLLocation* _Nonnull )location walkName:(NSString * _Nonnull) walkName distance:(double) distance;
- (void) updateStatus:(int)status;
- (void) sendCoordinateUpdate: (NSString * _Nonnull) walkName: (double) lat: (double) lon: (double) accuracy: (double) speed: (double) heading: (double) distance: (NSString *) provider;

@property (strong) NSMutableDictionary* _Nullable listeners;
@property (strong) FlutterEventSink _Nullable     eventSink;
@end

@interface AccelerometerEventHandler : NSObject<FlutterStreamHandler>
- (FlutterError* _Nullable)onListenWithArguments:(id _Nullable)arguments
                                       eventSink:(_Nonnull FlutterEventSink)events;
- (FlutterError* _Nullable)onCancelWithArguments:(id _Nullable)arguments;
- (void)updateAccelerometer:(CMAccelerometerData*)accelerometerData;
- (void)calculateDistanceAndSpeed:(double) accel: (double) initialSpeed: (int) time: (double*) distanceAndSpeed;
- (void)calculateNewLatLon:(double*) currentLatLon: (double) xDistance: (double) yDistance: (double*) newLatLon;
- (void)calculateNewLatLon:(double*) currentLatLon: (double) xDistance: (double) yDistance: (double*) newLatLon;
- (void)reportUpdatedPosition:(CMAccelerometerData*)accelerometerData;
- (void)setWalkName: (NSString*) walkName;
@property (strong) NSMutableDictionary* _Nullable listeners;
@property (strong) FlutterEventSink _Nullable     eventSink;
@property (strong) NSString * _Nonnull walkName;

@end

@interface GpsTrackerPlugin : NSObject<FlutterPlugin,CLLocationManagerDelegate>
@property (nonatomic, strong) CLLocationManager * _Nullable locationManager;
@property (nonatomic, strong) CMMotionManager * _Nullable motionManager;
@property (strong) CLLocation * _Nullable position;

@property (strong) NSString * _Nonnull walkName;
@property (strong) NSMutableArray * _Nullable locations;
@property double distance;
@property bool paused;
@end
