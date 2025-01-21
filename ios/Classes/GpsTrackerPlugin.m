#import "GpsTrackerPlugin.h"

@implementation GpsTrackerPlugin

GpsTrackerEventHandler    *eventHandler;
GpsTrackerEventHandler    *trackerEventHandler;
AccelerometerEventHandler *accelerometerEventHandler;

double         prevXSpeed;
double         prevYSpeed;
double         prevLatLon[2];
bool           firstGPSFix = false;
CFAbsoluteTime prevTime;
CFAbsoluteTime startTime;
NSTimer *timer = nil;

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  FlutterMethodChannel* methodChannel = [FlutterMethodChannel
      methodChannelWithName:@"com.moorwen.flutter.gps_tracker/method_channel"
      binaryMessenger:[registrar messenger]];
  GpsTrackerPlugin* instance = [[GpsTrackerPlugin alloc] init];
  [registrar addMethodCallDelegate:instance channel:methodChannel];

  eventHandler = [[GpsTrackerEventHandler alloc] init];
  FlutterEventChannel* eventChannel = [FlutterEventChannel
      eventChannelWithName:@"com.moorwen.flutter.gps_tracker/event_channel"
      binaryMessenger:[registrar messenger]];
  [eventChannel setStreamHandler:eventHandler];

  trackerEventHandler = [[GpsTrackerEventHandler alloc] init];
  FlutterEventChannel *trackerEventChannel = [FlutterEventChannel
      eventChannelWithName:@"com.moorwen.flutter.gps_tracker/gps_tracker_event_channel"
      binaryMessenger:[registrar messenger]];
  [trackerEventChannel setStreamHandler:trackerEventHandler];

  accelerometerEventHandler = [[AccelerometerEventHandler alloc] init];
}

- (void)handleMethodCall:(FlutterMethodCall*)call result:(FlutterResult)result {
  if ([@"getBatteryLevel" isEqualToString:call.method]) {
      UIDevice *myDevice = [UIDevice currentDevice];
      [myDevice setBatteryMonitoringEnabled:YES];
      result(@((int) ([myDevice batteryLevel] * 100.0)));

  } else if ([@"getAttitude" isEqualToString:call.method]) {
      CMQuaternion q = self.motionManager.deviceMotion.attitude.quaternion;
      double quat[4];
      quat[0] = q.w;
      quat[1] = q.x;
      quat[2] = q.y;
      quat[3] = q.z;
      NSData *data  = [NSData dataWithBytes: quat length: sizeof(quat)];
      FlutterStandardTypedData* typedData = [FlutterStandardTypedData typedDataWithFloat64:data];
      result(typedData);
  } else if ([@"isLocationEnabled" isEqualToString:call.method]) {
    int enabled = 0;
    if ([CLLocationManager locationServicesEnabled]) {
      if ([CLLocationManager authorizationStatus] == kCLAuthorizationStatusDenied) {
        enabled = -1;
      } else {
        enabled = 1;
      }
    } else {
      enabled = 0;
    }
    result(@((int)(enabled)));
  } else if ([@"getAccuracyLevel" isEqualToString:call.method]) {
    int auth = 0;
    CLLocationManager *locMgr = [[CLLocationManager alloc] init];
    if (@available(iOS 14.0, *)) {
      auth = locMgr.accuracyAuthorization;
    }
    result(@(auth));
  } else if ([@"start" isEqualToString:call.method]) {
    if (self.locationManager == nil) {
        self.locationManager = [[CLLocationManager alloc] init];
//      self.locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters;
//      self.locationManager.desiredAccuracy = kCLLocationAccuracyBest;
        self.locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation;
        self.locationManager.distanceFilter = kCLDistanceFilterNone;
        self.locationManager.allowsBackgroundLocationUpdates = YES;
        self.locationManager.delegate = self;
        [self.locationManager startUpdatingLocation];

        self.motionManager = [[CMMotionManager alloc] init];
        if ([self.motionManager isAccelerometerAvailable]) {
            [self.motionManager setAccelerometerUpdateInterval:REPORTING_INTERVAL];
            [self.motionManager setDeviceMotionUpdateInterval:REPORTING_INTERVAL];
            if (([CMMotionManager availableAttitudeReferenceFrames] & CMAttitudeReferenceFrameXTrueNorthZVertical) != 0){
                NSLog(@"GPSTracker - available");
            } else {
                NSLog(@"GPSTracker - NOT available");
            }

            if ([self.motionManager isDeviceMotionAvailable]) {
                [self.motionManager startDeviceMotionUpdatesUsingReferenceFrame:CMAttitudeReferenceFrameXTrueNorthZVertical];

//                CMDeviceMotionHandler dmHandler = ^(CMDeviceMotion *aMotion, NSError *error) {
//                    // Check for an error.
//                    if (error) {
//                        // Add error handling here.
//                    } else {
//                        // Get the rotation matrix.
//                        CMAttitude *attitude = self.motionManager.deviceMotion.attitude;
//                        CMRotationMatrix rm = attitude.rotationMatrix;
//                        NSLog(@"GPSTracker - heading matrix [%6.2f,%6.2f,%6.2f]",rm.m11,rm.m12,rm.m13);
//                        NSLog(@"GPSTracker -                [%6.2f,%6.2f,%6.2f]",rm.m21,rm.m22,rm.m23);
//                        NSLog(@"GPSTracker -                [%6.2f,%6.2f,%6.2f]",rm.m31,rm.m32,rm.m33);
//
//                        // Get the heading.
//                        double heading = M_PI + atan2(rm.m22, rm.m12);
//                        heading = heading*180/M_PI;
//                        NSLog(@"GPSTracker - heading %45.2f",heading);
//                    }
//                };
//                NSOperationQueue *motionQueue = [[NSOperationQueue alloc] init];
//                [self.motionManager startDeviceMotionUpdatesUsingReferenceFrame: CMAttitudeReferenceFrameXTrueNorthZVertical
//                                                                        toQueue: motionQueue
//                                                                    withHandler: dmHandler];
//
            }
        }
    }
  } else if ([@"stop" isEqualToString:call.method]) {
      [self.locationManager stopUpdatingLocation];
      self.locationManager = nil;
  } else if ([@"startTracking" isEqualToString:call.method]) {
      _walkName = call.arguments[@"walkName"];
      if ([_locationManager respondsToSelector:@selector(requestWhenInUseAuthorization)]) {
          [_locationManager requestWhenInUseAuthorization];
      }
      _locations  = [[NSMutableArray alloc] init];
      _distance   = 0;
      _position   = nil;
      _paused     = false;
      firstGPSFix = false;
      startTime   = CFAbsoluteTimeGetCurrent();

      [accelerometerEventHandler setWalkName:_walkName];
      [accelerometerEventHandler setMotionManager:self.motionManager];
      NSOperationQueue *queue = [[NSOperationQueue alloc] init];
//      [self.motionManager startAccelerometerUpdatesToQueue:queue withHandler:^(
//              CMAccelerometerData *accelerometerData, NSError *error) {
//          dispatch_async(dispatch_get_main_queue(), ^{
//              [accelerometerEventHandler updateAccelerometer:accelerometerData];
//          });
//      }];
      timer = [NSTimer scheduledTimerWithTimeInterval:0.5
                                       target:self
                                     selector:@selector(targetMethod:)
                                     userInfo:nil
                                      repeats:YES];
  } else if ([@"stopTracking" isEqualToString:call.method]) {
      _walkName = nil;
      [accelerometerEventHandler setWalkName:_walkName];
      [self.motionManager stopDeviceMotionUpdates];
      if ([self.motionManager isAccelerometerActive] == YES) {
          [self.motionManager stopAccelerometerUpdates];
      }
      [timer invalidate];
      timer = nil;
  } else if ([@"getLocation" isEqualToString:call.method]) {
      double posn[2];
      posn[0] = _position.coordinate.latitude;
      posn[1] = _position.coordinate.longitude;
      NSData *data = [NSData dataWithBytes: posn length: sizeof(posn)];
      FlutterStandardTypedData* typedData = [FlutterStandardTypedData typedDataWithFloat64:data];
      result(typedData);
  } else if ([@"getNumWalkTrackPoints" isEqualToString:call.method]) {
      result(@((int)[_locations count]));
  } else if ([@"getWalkTrackPoints" isEqualToString:call.method]) {
    NSMutableArray *locations = [[NSMutableArray alloc] init];
    for (CLLocation *location in _locations)
    {
      double posn[2];
      posn[0] = location.coordinate.latitude;
      posn[1] = location.coordinate.longitude;
      NSData *data = [NSData dataWithBytes: posn length: sizeof(posn)];
      FlutterStandardTypedData* typedData = [FlutterStandardTypedData typedDataWithFloat64:data];
      [locations addObject:typedData];
    }
    result(locations);
  } else if ([@"getDistance" isEqualToString:call.method]) {
    result(@(_distance));
  } else if ([@"getWalkName" isEqualToString:call.method]) {
    result(_walkName);
  } else if ([@"pause" isEqualToString:call.method]) {
      _paused = true;
  } else if ([@"resume" isEqualToString:call.method]) {
      _paused = false;
  } else {
    result(FlutterMethodNotImplemented);
  }
}

- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray *)locations {
    if ([[locations lastObject] horizontalAccuracy] < 0) {
        return;
    }

    if (_paused) {
        return;
    }
   
    bool first = true;
    for (CLLocation *location in locations)
    {
        double distance = 0.0;
        if (_position != nil)
        {
            distance = [ _position distanceFromLocation:location];
        }
//        NSLog(@"GPSTracker - didUpdateLocations time %6.4f distance %6.2f lat %6.6f lon %6.6f accuracy %6.6f",
//              CACurrentMediaTime(),distance,location.coordinate.latitude,location.coordinate.longitude,location.horizontalAccuracy);

        if (first && _position == nil)
        {
            [eventHandler updateLocation:location walkName:_walkName distance:0.0];
            if (_walkName != nil)
            {
                [trackerEventHandler updateLocation:location walkName:_walkName distance:0.0];
                [_locations addObject:location];
            }
            _position = location;
        }
        if (distance >= location.horizontalAccuracy)
        {
            [eventHandler updateLocation:location walkName:_walkName distance:_distance];
            if (_walkName != nil)
            {
                [_locations addObject:location];
                [trackerEventHandler updateLocation:location walkName:_walkName distance:_distance];
                _distance += distance;
            }
            _position = location;
        }
        first = false;
    }
}

- (void)targetMethod:(NSTimer*)theTimer {
    NSLog(@"Timer started on %6.2f", CFAbsoluteTimeGetCurrent());
    CMRotationMatrix rotationMatrix = self.motionManager.deviceMotion.attitude.rotationMatrix;
    CMAcceleration accelerometerData = self.motionManager.deviceMotion.userAcceleration;

    NSLog(@"GPSTracker - timer matrix [%6.2f,%6.2f,%6.2f]",rotationMatrix.m11,rotationMatrix.m12,rotationMatrix.m13);
    NSLog(@"GPSTracker -              [%6.2f,%6.2f,%6.2f]",rotationMatrix.m21,rotationMatrix.m22,rotationMatrix.m23);
    NSLog(@"GPSTracker -              [%6.2f,%6.2f,%6.2f]",rotationMatrix.m31,rotationMatrix.m32,rotationMatrix.m33);
    NSLog(@"GPSTracker - timer accel [%6.2f,%6.2f,%6.2f]", accelerometerData.x, accelerometerData.y, accelerometerData.z);
}

- (void)locationManager:(CLLocationManager *)manager didChangeAuthorizationStatus:(CLAuthorizationStatus)status {
    switch (status)
    {
    case kCLAuthorizationStatusNotDetermined:
        NSLog(@"GPSTracker - Status not determined");
        break;
    // The user denied authorization
    case kCLAuthorizationStatusDenied:
        NSLog(@"GPSTracker - Status denied");
        break;
    case kCLAuthorizationStatusRestricted:
        NSLog(@"GPSTracker - Status restricted");
        break;
    case kCLAuthorizationStatusAuthorizedAlways:
        NSLog(@"GPSTracker - Status authorised always");
        break;
    case kCLAuthorizationStatusAuthorizedWhenInUse:
        NSLog(@"GPSTracker - Status authorised when in use");
        break;
//    default:
//        break;
    }
    [eventHandler updateStatus:status];
    [trackerEventHandler updateStatus:status];
}

- (void)locationManager:(CLLocationManager *)manager didFailWithError:(NSError *)error {
    // The location "unknown" error simply means the manager is currently unable to get the location.
    if ([error code] != kCLErrorLocationUnknown) {
        [self stopUpdatingLocationWithMessage:NSLocalizedString(@"Error", @"Error")];
    }
}

- (void)stopUpdatingLocationWithMessage:(NSString *)state {
    [self.locationManager stopUpdatingLocation];
    self.locationManager.delegate = nil;
}

@end

@implementation GpsTrackerEventHandler

- (FlutterError*)onListenWithArguments:(id)arguments eventSink:(FlutterEventSink)eventSink {
  NSLog(@"GPSTracker - onListenWithArguments");
  _eventSink = eventSink;
  return nil;
}

- (FlutterError*)onCancelWithArguments:(id)arguments {
  NSLog(@"GPSTracker - onCancelWithArguments");
  _eventSink = nil;
  return nil;
}

- (void)updateStatus:(int)status {
  NSLog(@"GPSTracker - Update status");
  if (_eventSink == nil) return;

  NSMutableDictionary *fix = [NSMutableDictionary dictionaryWithCapacity:2];
  fix[@"reason"] = @"FIX_UPDATE";
  fix[@"fix_valid"] = [NSNumber numberWithBool:true];
  _eventSink(fix);
}

- (void)updateLocation:(CLLocation*)location walkName:(NSString *) walkName distance:(double) distance {
  NSLog(@"GPSTracker - Update Location from GPS");
  if (_eventSink == nil) return;

  // Send the event on
  NSMutableDictionary *coordinates = [NSMutableDictionary dictionaryWithCapacity:9];
  coordinates[@"reason"]       = @"COORDINATE_UPDATE";
  coordinates[@"walk_name"]    = walkName;
  coordinates[@"latitude"]     = [NSNumber numberWithDouble:location.coordinate.latitude];
  coordinates[@"longitude"]    = [NSNumber numberWithDouble:location.coordinate.longitude];
  coordinates[@"accuracy"]     = [NSNumber numberWithDouble:location.horizontalAccuracy];
  coordinates[@"speed"]        = [NSNumber numberWithDouble:location.speed];
  coordinates[@"heading"]      = [NSNumber numberWithDouble:location.course];
  coordinates[@"distance"]     = [NSNumber numberWithDouble:distance];
  coordinates[@"fix_valid"]    = [NSNumber numberWithBool:true];
  coordinates[@"provider"]     = @"GPS";
  coordinates[@"elapsedTime"] = [NSNumber numberWithLong:((CFAbsoluteTimeGetCurrent() - startTime)*1000.0)];

  _eventSink(coordinates);

  // Calculate speed for the inertial navigation
  // Speed is M/Sec
  // Course is in degrees and is relative to due North
  prevXSpeed    = abs(location.speed*cos((location.course*M_PI)/180));
  prevYSpeed    = abs(location.speed*sin((location.course*M_PI)/180));
  prevLatLon[0] = location.coordinate.latitude;
  prevLatLon[1] = location.coordinate.longitude;
  prevTime      = CFAbsoluteTimeGetCurrent();
  firstGPSFix   = true;
  NSLog(@"GPSTracker - Update Location from GPS prev speed [%6.2f,%6.2f]",prevXSpeed,prevYSpeed);
}

- (void) sendCoordinateUpdate: (NSString * _Nonnull) walkName: (double) lat: (double) lon: (double) accuracy: (double) speed: (double) heading: (double) distance: (NSString* ) provider {
    if (_eventSink == nil) return;

    NSMutableDictionary *coordinates = [NSMutableDictionary dictionaryWithCapacity:11];
    coordinates[@"reason"]       = @"COORDINATE_UPDATE";
    coordinates[@"walk_name"]    = walkName;
    coordinates[@"latitude"]     = [NSNumber numberWithDouble:lat];
    coordinates[@"longitude"]    = [NSNumber numberWithDouble:lon];
    coordinates[@"accuracy"]     = [NSNumber numberWithDouble:accuracy];
    coordinates[@"speed"]        = [NSNumber numberWithDouble:speed];
    coordinates[@"heading"]      = [NSNumber numberWithDouble:heading];
    coordinates[@"distance"]     = [NSNumber numberWithDouble:distance];
    coordinates[@"fix_valid"]    = [NSNumber numberWithBool:true];
    coordinates[@"provider"]     = provider;
    coordinates[@"elapsedTime"] = [NSNumber numberWithLong:((CFAbsoluteTimeGetCurrent() - startTime)*1000.0)];
    NSLog(@"GPSTracker - Update Location from INS");
    _eventSink(coordinates);
}
@end

@implementation AccelerometerEventHandler
- (void)updateAccelerometer:(CMAccelerometerData*)accelerometerData {
//    NSMutableDictionary *values = [NSMutableDictionary dictionaryWithCapacity:4];
//    values[@"reason"] = @"ACCELEROMETER_UPDATE";
//    values[@"accelerometerX"] = [NSNumber numberWithDouble:accelerometerData.acceleration.x];
//    values[@"accelerometerY"] = [NSNumber numberWithDouble:accelerometerData.acceleration.y];
//    values[@"accelerometerZ"] = [NSNumber numberWithDouble:accelerometerData.acceleration.z];
//    values[@"accelerometerTimestamp"] = 0; // [NSNumber numberWithLong:accelerometerData.accelerometer.timestamp];
    if (firstGPSFix) {
        [self reportUpdatedPosition:accelerometerData];
    }
}

// Calculate distance travelled and final speed from acceleration, initial speed and time.
// Acceleration is m/s**2
// Speed is m/s
// Time is in milliseconds
// Output distance is in metres
- (void)calculateDistanceAndSpeed:(double) accel: (double) initialSpeed: (int) time: (double *) distanceAndSpeed {
    double deltaSpeed                = (accel*time)/1000.0;
    double finalSpeed                = initialSpeed + deltaSpeed;
    distanceAndSpeed[SPEED_INDEX]    = finalSpeed;
    distanceAndSpeed[DISTANCE_INDEX] = (initialSpeed + finalSpeed)*0.5*((double)time/1000.0);
    NSLog(@"GPSTracker - accel %6.2f speed %6.2f delta %6.4f time %d final speed %6.2f speed %6.2f distance %6.2f",
          accel, initialSpeed, deltaSpeed, time, distanceAndSpeed[SPEED_INDEX], distanceAndSpeed[DISTANCE_INDEX]);
 }

// Calculate the new lat/lon from the current lat/lon and x/y distance (x - NorthSouth, y - EastWest)
// https://stackoverflow.com/questions/7477003/calculating-new-longitude-latitude-from-old-n-meters
// Latitude:
//    var earth = 6378.137,  //radius of the earth in kilometer
//       pi = Math.PI,
//       m = (1 / ((2 * pi / 360) * earth)) / 1000;  //1 meter in degree`
//    var new_latitude = latitude + (your_meters * m);
// Longitude:
//   var earth = 6378.137,  //radius of the earth in kilometer
//      pi = Math.PI,
//      cos = Math.cos,
//      m = (1 / ((2 * pi / 360) * earth)) / 1000;  //1 meter in degree
//   var new_longitude = longitude + (your_meters * m) / cos(latitude * (pi / 180));
- (void)calculateNewLatLon:(double*) currentLatLon: (double) xDistance: (double) yDistance: (double*) newLatLon {
    newLatLon[0] = currentLatLon[0] + (xDistance*ONE_METRE);
    newLatLon[1] = currentLatLon[1] + (yDistance*ONE_METRE)/(cos((currentLatLon[1]*M_PI)/180.0));
}

- (void)reportUpdatedPosition:(CMAccelerometerData*)accelerometerData {
    double xDistanceAndSpeed[2];
    double yDistanceAndSpeed[2];
    double newLatLon[2];

    CFAbsoluteTime   currTime       = CFAbsoluteTimeGetCurrent();
    CMRotationMatrix rotationMatrix = self.motionManager.deviceMotion.attitude.rotationMatrix;

//    double accelX = rotationMatrix.m11 * accelerometerData.acceleration.x +
//                    rotationMatrix.m12 * accelerometerData.acceleration.y +
//                    rotationMatrix.m13 * accelerometerData.acceleration.z;
//    double accelY = rotationMatrix.m21 * accelerometerData.acceleration.x +
//                    rotationMatrix.m22 * accelerometerData.acceleration.y +
//                    rotationMatrix.m23 * accelerometerData.acceleration.z;
    double accelX = rotationMatrix.m11 * self.motionManager.deviceMotion.userAcceleration.x +
                    rotationMatrix.m12 * self.motionManager.deviceMotion.userAcceleration.y +
                    rotationMatrix.m13 * self.motionManager.deviceMotion.userAcceleration.z;
    double accelY = rotationMatrix.m21 * self.motionManager.deviceMotion.userAcceleration.x +
                    rotationMatrix.m22 * self.motionManager.deviceMotion.userAcceleration.y +
                    rotationMatrix.m23 * self.motionManager.deviceMotion.userAcceleration.z;
    NSLog(@"GPSTracker - reportUpdatedPosition raw accel [%6.2f,%6.2f,%6.2f] adjusted [%6.2f,%6.2f] speed [%6.2f,%6.2f]",
          self.motionManager.deviceMotion.userAcceleration.x,
          self.motionManager.deviceMotion.userAcceleration.y,
          self.motionManager.deviceMotion.userAcceleration.z,
          accelX, accelY, prevXSpeed, prevYSpeed);
    NSLog(@"GPSTracker - reportUpdatedPosition matrix [%6.2f,%6.2f,%6.2f]",rotationMatrix.m11,rotationMatrix.m12,rotationMatrix.m13);
    NSLog(@"GPSTracker -                              [%6.2f,%6.2f,%6.2f]",rotationMatrix.m21,rotationMatrix.m22,rotationMatrix.m23);
    NSLog(@"GPSTracker -                              [%6.2f,%6.2f,%6.2f]",rotationMatrix.m31,rotationMatrix.m32,rotationMatrix.m33);

    long interval = [[NSNumber numberWithDouble:(currTime - prevTime)*1000.0] longValue];
    [self calculateDistanceAndSpeed:accelX : prevXSpeed : interval : xDistanceAndSpeed];
    [self calculateDistanceAndSpeed:accelY : prevYSpeed : interval : yDistanceAndSpeed];
    [self calculateNewLatLon:prevLatLon : xDistanceAndSpeed[DISTANCE_INDEX] : yDistanceAndSpeed[DISTANCE_INDEX] : newLatLon];

    // Calculate the heading, allowing for tan approaching infinity (y approaching 0)
    double heading = yDistanceAndSpeed[1] > ZERO_TOL ? atan(xDistanceAndSpeed[DISTANCE_INDEX]/yDistanceAndSpeed[SPEED_INDEX]) : 90.0;

    NSLog(@"GPSTracker - reportUpdatedPosition interval %4d dist[%6.2f,%6.2f] speed [%6.6f,%6.6f] accel[%6.6f,%6.6f] pos [%6.6f,%6.6f]",
              interval,
              xDistanceAndSpeed[DISTANCE_INDEX], yDistanceAndSpeed[DISTANCE_INDEX],
              xDistanceAndSpeed[SPEED_INDEX], yDistanceAndSpeed[SPEED_INDEX],
              accelX, accelY, newLatLon[0], newLatLon[1]);

    // Send the event on
    if (_walkName != nil) {
        [trackerEventHandler sendCoordinateUpdate:
           _walkName:
           [[NSNumber numberWithDouble:newLatLon[0]] doubleValue] :
           [[NSNumber numberWithDouble:newLatLon[1]] doubleValue] :
           [[NSNumber numberWithDouble:0.0] doubleValue] :
           [[NSNumber numberWithDouble:sqrt(pow(xDistanceAndSpeed[SPEED_INDEX], 2) + pow(yDistanceAndSpeed[SPEED_INDEX],2))] doubleValue] :
           [[NSNumber numberWithDouble:heading] doubleValue] :
           [[NSNumber numberWithDouble:sqrt(pow(xDistanceAndSpeed[DISTANCE_INDEX], 2) + pow(yDistanceAndSpeed[DISTANCE_INDEX],2))] doubleValue] :
           @"INS"
        ];
    }

    prevXSpeed    = xDistanceAndSpeed[SPEED_INDEX];
    prevYSpeed    = yDistanceAndSpeed[SPEED_INDEX];
    prevLatLon[0] = newLatLon[0];
    prevLatLon[1] = newLatLon[1];
    prevTime      = currTime;
}

- (void)setWalkName: (NSString*) walkName {
    _walkName = walkName;
}

- (void)setMotionManger: (CMMotionManager *) motionManager {
    self.motionManager = motionManager;
}
@end