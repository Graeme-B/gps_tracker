#import <Flutter/Flutter.h>
#import <Flutter/FlutterCodecs.h>
#import <CoreLocation/CoreLocation.h>
#import <CoreMotion/CoreMotion.h>

@interface GpsTrackerEventHandler : NSObject<FlutterStreamHandler>
- (FlutterError* _Nullable)onListenWithArguments:(id _Nullable)arguments
                                       eventSink:(_Nonnull FlutterEventSink)events;
- (FlutterError* _Nullable)onCancelWithArguments:(id _Nullable)arguments;
-  (void)updateLocation:( CLLocation* _Nonnull )location walkName:( NSString * _Nonnull ) walkName distance:(double) distance;
- (void) updateStatus:(int)status;

@property (strong) NSMutableDictionary* _Nullable listeners;
@property (strong) FlutterEventSink _Nullable     eventSink;
@end

@interface AccelerometerEventHandler : NSObject<FlutterStreamHandler>
- (FlutterError* _Nullable)onListenWithArguments:(id _Nullable)arguments
                                       eventSink:(_Nonnull FlutterEventSink)events;
- (FlutterError* _Nullable)onCancelWithArguments:(id _Nullable)arguments;
-  (void)updateAccelerometer:( CLLocation* _Nonnull )location walkName:( NSString * _Nonnull ) walkName distance:(double) distance;

@property (strong) NSMutableDictionary* _Nullable listeners;
@property (strong) FlutterEventSink _Nullable     eventSink;
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
