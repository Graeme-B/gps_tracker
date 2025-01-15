#import "GpsTrackerPlugin.h"

@implementation GpsTrackerPlugin

GpsTrackerEventHandler    *eventHandler;
GpsTrackerEventHandler    *trackerEventHandler;
AccelerometerEventHandler *accelerometerEventHandler;

double         prevXSpeed;
double         prevYSpeed;
double         prevLatLon[2];
CFAbsoluteTime prevTime;

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
  FlutterEventChannel *accelerometerEventChannel = [FlutterEventChannel
      eventChannelWithName:@"com.moorwen.flutter.gps_tracker/accelerometer_event_channel"
      binaryMessenger:[registrar messenger]];
  [accelerometerEventChannel setStreamHandler:accelerometerEventHandler];
}

- (void)handleMethodCall:(FlutterMethodCall*)call result:(FlutterResult)result {
  if ([@"getBatteryLevel" isEqualToString:call.method]) {
      UIDevice *myDevice = [UIDevice currentDevice];
      [myDevice setBatteryMonitoringEnabled:YES];
      result(@((int) ([myDevice batteryLevel] * 100.0)));

  } else if ([@"getAttitude" isEqualToString:call.method]) {
      CMMotionManager *motionManager = [[CMMotionManager alloc] init];
      CMQuaternion q = motionManager.deviceMotion.attitude.quaternion;
      double quat[4];
      quat[0] = q.w;
      quat[1] = q.x;
      quat[2] = q.y;
      quat[3] = q.z;
      motionManager = nil;
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
            if ([self.motionManager isDeviceMotionAvailable]) {
                [self.motionManager startDeviceMotionUpdatesUsingReferenceFrame:CMAttitudeReferenceFrameXArbitraryZVertical];
            }
            NSOperationQueue *queue = [[NSOperationQueue alloc] init];
            [self.motionManager startAccelerometerUpdatesToQueue:queue withHandler:^(
                    CMAccelerometerData *accelerometerData, NSError *error) {
                dispatch_async(dispatch_get_main_queue(), ^{
//                    NSLog(@"GPSTracker - accelerometer time %6.4f raw [%6.4f %6.4f %6.4f] yaw %6.4f pitch %6.4f roll %6.4f",
//                          CACurrentMediaTime(), accelerometerData.acceleration.x,
//                          accelerometerData.acceleration.y,
//                          self.motionManager.deviceMotion.attitude.yaw, self.motionManager.deviceMotion.attitude.pitch,
//                          self.motionManager.deviceMotion.attitude.roll);

//                  self.xAxis.text = [NSString stringWithFormat:@"%.2f",accelerometerData.acceleration.x];
//                  self.yAxis.text = [NSString stringWithFormat:@"%.2f",accelerometerData.acceleration.y];
//                  self.zAxis.text = [NSString stringWithFormat:@"%.2f",accelerometerData.acceleration.z];

//                    CMMotionManager *motionManager = [[CMMotionManager alloc] init];
//                    CMRotationMatrix rotationMatrix = motionManager.deviceMotion.attitude.rotationMatrix;
//
//                    double accelX = rotationMatrix.m11*accelerometerData.acceleration.x +
//                             rotationMatrix.m12*accelerometerData.acceleration.y +
//                             rotationMatrix.m13*accelerometerData.acceleration.z;
//                    double accelY = rotationMatrix.m21*accelerometerData.acceleration.x +
//                             rotationMatrix.m22*accelerometerData.acceleration.y +
//                             rotationMatrix.m23*accelerometerData.acceleration.z;
//                    double accelZ = rotationMatrix.m31*accelerometerData.acceleration.x +
//                             rotationMatrix.m32*accelerometerData.acceleration.y +
//                             rotationMatrix.m33*accelerometerData.acceleration.z;
//                    NSLog(@"GPSTracker - accelerometer time %6.4f raw [%6.4f %6.4f %6.4f] normalised [%6.4f %6.4f %6.4f]",
//                          CACurrentMediaTime(), accelerometerData.acceleration.x, accelerometerData.acceleration.y,
//                          accelerometerData.acceleration.z, accelX, accelY, accelZ);
//                    NSLog(@"GPSTracker - matrix [%6.4f %6.4f %6.4f]",rotationMatrix.m11,rotationMatrix.m12,rotationMatrix.m13);
//                    NSLog(@"GPSTracker -        [%6.4f %6.4f %6.4f]",rotationMatrix.m21,rotationMatrix.m22,rotationMatrix.m23);
//                    NSLog(@"GPSTracker -        [%6.4f %6.4f %6.4f]",rotationMatrix.m31,rotationMatrix.m32,rotationMatrix.m33);

                    [accelerometerEventHandler updateAccelerometer:accelerometerData];

                });
            }];

        }
//        if ([self.motionManager isDeviceMotionAvailable]) {
//            [self.motionManager startDeviceMotionUpdatesUsingReferenceFrame: CMAttitudeReferenceFrameXArbitraryZVertical];
////            NSOperationQueue *queue = [[NSOperationQueue alloc] init];
////
////            [self.motionManager startDeviceMotionUpdatesUsingReferenceFrame: CMAttitudeReferenceFrameXArbitraryZVertical
////                                                                    toQueue:queue withHandler:^(CMDeviceMotion *motion, NSError *error){
////                dispatch_async(dispatch_get_main_queue(), ^{
////                    NSLog(@"GPSTracker - motion time %6.4f yaw %6.4f pitch %6.4f roll %6.4f",
////                          CACurrentMediaTime(), motion.attitude.yaw, motion.attitude.pitch, motion.attitude.roll);
////
//////                    CMMotionManager *motionManager = [[CMMotionManager alloc] init];
//////                    CMRotationMatrix rotationMatrix = motionManager.deviceMotion.attitude.rotationMatrix;
//////                    NSLog(@"GPSTracker - matrix [%6.4f %6.4f %6.4f]",rotationMatrix.m11,rotationMatrix.m12,rotationMatrix.m13);
//////                    NSLog(@"GPSTracker -        [%6.4f %6.4f %6.4f]",rotationMatrix.m21,rotationMatrix.m22,rotationMatrix.m23);
//////                    NSLog(@"GPSTracker -        [%6.4f %6.4f %6.4f]",rotationMatrix.m31,rotationMatrix.m32,rotationMatrix.m33);
//////                    motionManager = nil;
////
////
//////                    if self.attitudeReferenceFrame == CMAttitudeReferenceFrame.xMagneticNorthZVertical  (which it will always be!)
//////                      let yaw = (data!.attitude.yaw + Double.pi + Double.pi / 2).truncatingRemainder(dividingBy: Double.pi * 2) - Double.pi
//////                    events([yaw, data!.attitude.pitch, data!.attitude.roll])
////                });
////            }];
//        }
    }
  } else if ([@"stop" isEqualToString:call.method]) {
      [self.locationManager stopUpdatingLocation];
      self.locationManager = nil;
  } else if ([@"startTracking" isEqualToString:call.method]) {
      _walkName = call.arguments[@"walkName"];
      if ([_locationManager respondsToSelector:@selector(requestWhenInUseAuthorization)]) {
          [_locationManager requestWhenInUseAuthorization];
      }
      _locations = [[NSMutableArray alloc] init];
      _distance = 0;
      _position = nil;
      _paused = false;
      [accelerometerEventHandler setWalkName:_walkName];
  } else if ([@"stopTracking" isEqualToString:call.method]) {
      _walkName = nil;
      [accelerometerEventHandler setWalkName:_walkName];
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
//{
//  // Listeners
////  NSMutableDictionary* listeners;
////  FlutterEventSink     thisEventSink;
//}

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
  coordinates[@"reason"]    = @"COORDINATE_UPDATE";
  coordinates[@"walk_name"] = walkName;
  coordinates[@"latitude"]  = [NSNumber numberWithDouble:location.coordinate.latitude];
  coordinates[@"longitude"] = [NSNumber numberWithDouble:location.coordinate.longitude];
  coordinates[@"accuracy"]  = [NSNumber numberWithDouble:location.horizontalAccuracy];
  coordinates[@"speed"]     = [NSNumber numberWithDouble:location.speed];
  coordinates[@"heading"]   = [NSNumber numberWithDouble:location.course];
  coordinates[@"distance"]  = [NSNumber numberWithDouble:distance];
  coordinates[@"fix_valid"] = [NSNumber numberWithBool:true];
  coordinates[@"provider"]  = @"GPS";
  _eventSink(coordinates);

  // Calculate speed for the inertial navigation
  // Speed is M/Sec
  // Course is in degrees and is relative to due North
  prevXSpeed    = location.speed*cos((location.course*M_PI)/180);
  prevYSpeed    = location.speed*sin((location.course*M_PI)/180 );
  prevLatLon[0] = location.coordinate.latitude;
  prevLatLon[1] = location.coordinate.longitude;
  prevTime      = CFAbsoluteTimeGetCurrent();
}

//    NSMutableDictionary *coordinates = [NSMutableDictionary dictionaryWithCapacity:9];
//    coordinates[@"reason"] = @"COORDINATE_UPDATE";
//    coordinates[@"walk_name"] = walkName;
//    coordinates[@"latitude"] = [NSNumber numberWithDouble:newLatLon[0]];
//    coordinates[@"longitude"] = [NSNumber numberWithDouble:newLatLon[1]];
//    coordinates[@"accuracy"] = [NSNumber numberWithDouble:0.0];
//    coordinates[@"speed"] = [NSNumber numberWithDouble:sqrt(pow(xDistanceAndSpeed[1],2) + pow(yDistanceAndSpeed[1],2))];
//    coordinates[@"heading"] = [NSNumber numberWithDouble:heading];
//    coordinates[@"distance"] = [NSNumber numberWithDouble:sqrt(pow(xDistanceAndSpeed[0],2) + pow(yDistanceAndSpeed[0],2))];
//    coordinates[@"provider"] = @"INS";
//    coordinates[@"fix_valid"] = [NSNumber numberWithBool:true];
- (void) sendCoordinateUpdate: (NSString * _Nonnull) walkName: (double) lat: (double) lon: (double) accuracy: (double) speed: (double) heading: (double) distance: (NSString* ) provider {
    if (_eventSink == nil) return;

    NSMutableDictionary *coordinates = [NSMutableDictionary dictionaryWithCapacity:11];
    coordinates[@"reason"]    = @"COORDINATE_UPDATE";
    coordinates[@"walk_name"] = walkName;
    coordinates[@"latitude"]  = [NSNumber numberWithDouble:lat];
    coordinates[@"longitude"] = [NSNumber numberWithDouble:lon];
    coordinates[@"accuracy"]  = [NSNumber numberWithDouble:accuracy];
    coordinates[@"speed"]     = [NSNumber numberWithDouble:speed];
    coordinates[@"heading"]   = [NSNumber numberWithDouble:heading];
    coordinates[@"distance"]  = [NSNumber numberWithDouble:distance];
    coordinates[@"fix_valid"] = [NSNumber numberWithBool:true];
    coordinates[@"provider"]  = provider;
    NSLog(@"GPSTracker - Update Location from INS");
    _eventSink(coordinates);
}
@end

@implementation AccelerometerEventHandler
- (FlutterError*)onListenWithArguments:(id)arguments eventSink:(FlutterEventSink)eventSink {
    NSLog(@"GPSTracker - accelerometer onListenWithArguments");
    _eventSink = eventSink;
    return nil;
}

- (FlutterError*)onCancelWithArguments:(id)arguments {
    NSLog(@"GPSTracker - accelerometer onCancelWithArguments");
    _eventSink = nil;
    return nil;
}

- (void)updateAccelerometer:(CMAccelerometerData*)accelerometerData {
    if (_eventSink == nil) return;

    NSMutableDictionary *values = [NSMutableDictionary dictionaryWithCapacity:4];
    values[@"reason"] = @"ACCELEROMETER_UPDATE";
    values[@"accelerometerX"] = [NSNumber numberWithDouble:accelerometerData.acceleration.x];
    values[@"accelerometerY"] = [NSNumber numberWithDouble:accelerometerData.acceleration.y];
    values[@"accelerometerZ"] = [NSNumber numberWithDouble:accelerometerData.acceleration.z];
    values[@"accelerometerTimestamp"] = 0; // [NSNumber numberWithLong:accelerometerData.accelerometer.timestamp];
    _eventSink(values);
    [self reportUpdatedPosition : accelerometerData];
}

// Calculate distance travelled and final speed from acceleration, initial speed and time.
// Acceleration is m/s**2
// Speed is m/s
// Time is in milliseconds
// Output distance is in metres
- (void)calculateDistanceAndSpeed:(double) accel: (double) initialSpeed: (int) time: (double*) distanceAndSpeed {
    double finalSpeed   = initialSpeed + (accel*time)/1000.0;
    distanceAndSpeed[0] = finalSpeed;
    distanceAndSpeed[1] = (initialSpeed + finalSpeed)*0.5*(time/1000.0);
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
    CMMotionManager *motionManager  = [[CMMotionManager alloc] init];
    CMRotationMatrix rotationMatrix = motionManager.deviceMotion.attitude.rotationMatrix;

    double accelX = rotationMatrix.m11 * accelerometerData.acceleration.x +
                    rotationMatrix.m12 * accelerometerData.acceleration.y +
                    rotationMatrix.m13 * accelerometerData.acceleration.z;
    double accelY = rotationMatrix.m21 * accelerometerData.acceleration.x +
                    rotationMatrix.m22 * accelerometerData.acceleration.y +
                    rotationMatrix.m23 * accelerometerData.acceleration.z;

    long interval = [[NSNumber numberWithDouble:(currTime - prevTime)*1000.0] longValue];
//    [self calculateDistanceAndSpeed:accelX : prevXSpeed : [NSNumber numberWithDouble:(currTime - prevTime)*1000.0] : xDistanceAndSpeed];
    [self calculateDistanceAndSpeed:accelX : prevXSpeed : interval : xDistanceAndSpeed];
//    [self calculateDistanceAndSpeed:accelY : prevYSpeed : [NSNumber numberWithDouble:(currTime - prevTime)*1000.0] : yDistanceAndSpeed)];
    [self calculateDistanceAndSpeed:accelY : prevYSpeed : interval : yDistanceAndSpeed];
    [self calculateNewLatLon:prevLatLon : xDistanceAndSpeed[0] : yDistanceAndSpeed[0] : newLatLon];

    // Calculate the heading, allowing for tan approaching infinity (y approaching 0)
    double heading = yDistanceAndSpeed[0] > ZERO_TOL ? atan(xDistanceAndSpeed[0]/yDistanceAndSpeed[0]) : 90.0;

    double xx = [[NSNumber numberWithDouble:sqrt(pow(xDistanceAndSpeed[1],2) + pow(yDistanceAndSpeed[1],2))] doubleValue];

    // Send the event on
    if (_walkName != nil) {
        [trackerEventHandler sendCoordinateUpdate:
           _walkName:
           [[NSNumber numberWithDouble:newLatLon[0]] doubleValue] :
           [[NSNumber numberWithDouble:newLatLon[1]] doubleValue] :
           [[NSNumber numberWithDouble:0.0] doubleValue] :
           [[NSNumber numberWithDouble:sqrt(pow(xDistanceAndSpeed[1], 2) + pow(yDistanceAndSpeed[1],2))] doubleValue] :
           [[NSNumber numberWithDouble:heading] doubleValue] :
           [[NSNumber numberWithDouble:sqrt(pow(xDistanceAndSpeed[0], 2) + pow(yDistanceAndSpeed[0],2))] doubleValue] :
           @"INS"
        ];
    }

    prevXSpeed    = xDistanceAndSpeed[1];
    prevYSpeed    = yDistanceAndSpeed[1];
    prevLatLon[0] = newLatLon[0];
    prevLatLon[1] = newLatLon[1];
    prevTime      = currTime;
}

- (void)setWalkName: (NSString*) walkName {
    _walkName = walkName;
}

@end

//static const double EARTH_RADIUS = 6378.137;

//Matrix3 rotationMatrixFromOrientationVector(Vector3 o) {
//    Matrix4 m = Matrix4.zero();
//    simpleSensor.getOrientation(m);
//
//    return Matrix3(
//            cos(o.x)*cos(o.z) - sin(o.x)*cos(o.y)*sin(o.z),
//            sin(o.x)*cos(o.z) + cos(o.y)*cos(o.x)*sin(o.z),
//            sin(o.y)*sin(o.z),
//            -cos(o.x)*sin(o.z) - cos(o.y)*sin(o.x)*cos(o.z),
//            -sin(o.x)*sin(o.z) + cos(o.y)*cos(o.x)*cos(o.z),
//            sin(o.y)*cos(o.z),
//            sin(o.x)*sin(o.y),
//            -cos(o.x)*sin(o.y),
//            cos(o.y));
//}

//// Calculate distance travelled and final speed from acceleration, initial speed and time.
//// Acceleration is m/s**2
//// Speed is m/s
//// Time is in milliseconds
//// Output distance is in metres
//void calculateDistanceAndSpeed(double accel, double initialSpeed, int time, double* distanceAndSpeed) {
//    double finalSpeed   = initialSpeed + (accel*time)/1000.0;
//    distanceAndSpeed[0] = finalSpeed;
//    distanceAndSpeed[1] = (initialSpeed + finalSpeed)*0.5*(time/1000.0);
//}
//
//// Calculate the new lat/lon from the current lat/lon and x/y distance (x - NorthSouth, y - EastWest)
//// https://stackoverflow.com/questions/7477003/calculating-new-longitude-latitude-from-old-n-meters
//// Latitude:
////    var earth = 6378.137,  //radius of the earth in kilometer
////       pi = Math.PI,
////       m = (1 / ((2 * pi / 360) * earth)) / 1000;  //1 meter in degree`
////    var new_latitude = latitude + (your_meters * m);
//// Longitude:
////   var earth = 6378.137,  //radius of the earth in kilometer
////      pi = Math.PI,
////      cos = Math.cos,
////      m = (1 / ((2 * pi / 360) * earth)) / 1000;  //1 meter in degree
////   var new_longitude = longitude + (your_meters * m) / cos(latitude * (pi / 180));
//void calculateNewLatLon(double* currentLatLon, double xDistance, double yDistance, double* newLatLon) {
//    newLatLon[0] = currentLatLon[0] + (xDistance*ONE_METRE);
//    newLatLon[1] = currentLatLon[1] + (yDistance*ONE_METRE)/(cos((currentLatLon[1]*M_PI)/180.0));
//}
//
//void reportUpdatedPosition((CMAccelerometerData*)accelerometerData) {
//    double[2] xDistanceAndSpeed;
//    double[2] yDistanceAndSpeed;
//    double[2] newLatLon;
//
//    CMMotionManager  *motionManager = [[CMMotionManager alloc] init];
//    CMRotationMatrix rotationMatrix = motionManager.deviceMotion.attitude.rotationMatrix;
//
//    double accelX = rotationMatrix.m11 * accelerometerData.acceleration.x +
//                    rotationMatrix.m12 * accelerometerData.acceleration.y +
//                    rotationMatrix.m13 * accelerometerData.acceleration.z;
//    double accelY = rotationMatrix.m21 * accelerometerData.acceleration.x +
//                    rotationMatrix.m22 * accelerometerData.acceleration.y +
//                    rotationMatrix.m23 * accelerometerData.acceleration.z;
//
//    calculateDistanceAndSpeed(accelX, _previousXSpeed, interval, xDistanceAndSpeed);
//    calculateDistanceAndSpeed(accelY, _previousYSpeed, interval, yDistanceAndSpeed);
//    calculateNewLatLon(prevLatLon, distanceX, distanceY, newLatLon);
//
//    // Send the event on
//    NSMutableDictionary *coordinates = [NSMutableDictionary dictionaryWithCapacity:9];
//    coordinates[@"reason"] = @"COORDINATE_UPDATE";
//    coordinates[@"walk_name"] = walkName;
//    coordinates[@"latitude"] = [NSNumber numberWithDouble:newLatLon[0]];
//    coordinates[@"longitude"] = [NSNumber numberWithDouble:newPatLon[1]];
//    coordinates[@"accuracy"] = [NSNumber numberWithDouble:0.0];
//    coordinates[@"speed"] = [NSNumber numberWithDouble:sqrt(xDistanceAndSpeed[1]**2 + yDistanceAndSpeed[1]**2)];
//    coordinates[@"heading"] = [NSNumber numberWithDouble:];  // atan(xDistanceAndSpeed[0]/yDistanceAndSpeed[0]) - but watch out as Y approaches 0!!!!
//    coordinates[@"distance"] = [NSNumber numberWithDouble:sqrt(xDistanceAndSpeed[0]**2 + yDistanceAndSpeed[0]**2)];
//    coordinates[@"fix_valid"] = [NSNumber numberWithBool:true];
//    [trackerEventHandler _eventSink(coordinates)];
//
//    prevXSpeed    = xDistanceAndSpeed[1];
//    prevYSpeed    = yDistanceAndSpeed[1];
//    prevLatLon[0] = newLatLon[0];
//    prevLatLon[1] = newLatLon[1];
//}

//// Calculate the new lat/lon from the current lat/lon and x/y distance (x - NorthSouth, y - EastWest)
//// https://stackoverflow.com/questions/7477003/calculating-new-longitude-latitude-from-old-n-meters
//// Latitude:
////    var earth = 6378.137,  //radius of the earth in kilometer
////       pi = Math.PI,
////       m = (1 / ((2 * pi / 360) * earth)) / 1000;  //1 meter in degree`
////    var new_latitude = latitude + (your_meters * m);
//// Longitude:
////   var earth = 6378.137,  //radius of the earth in kilometer
////      pi = Math.PI,
////      cos = Math.cos,
////      m = (1 / ((2 * pi / 360) * earth)) / 1000;  //1 meter in degree
////   var new_longitude = longitude + (your_meters * m) / cos(latitude * (pi / 180));
//LatLng newPosition(LatLng currentPosition, double x, double y) {
//    var oneMetre  = (1.0 / ((2.0 * pi / 360) * EARTH_RADIUS)) / 1000;
//    var newLat = currentPosition.latitude + (x*oneMetre);
//    var newLon = currentPosition.longitude + (x*oneMetre)/(cos(currentPosition.longitudeInRad));
//    return LatLng(newLat, newLon);
//}
//
//void calculateLocation(Vector3 orientation, Vector3 acceleration) {
//    if (_previousReportTime >= 0) {
//        int now = DateTime.now().millisecondsSinceEpoch;
//        int interval = now - _previousReportTime;

/*
coordinates[@"speed"] = [NSNumber numberWithDouble:location.speed];
coordinates[@"heading"] = [NSNumber numberWithDouble:location.course];

double prevXSpeed;
double prevYSpeed;
When we get a GPS fix:
  prevXSpeed = location.speed*cos(location.course);
  prevYSpeed = location.speed*sin(location.course);
Speed is M/Sec
Course is in degrees and is relative to due North

CMMotionManager *motionManager = [[CMMotionManager alloc] init];
CMRotationMatrix rotationMatrix = motionManager.deviceMotion.attitude.rotationMatrix;

                    double accelX = rotationMatrix.m11*accelerometerData.acceleration.x +
                             rotationMatrix.m12*accelerometerData.acceleration.y +
                             rotationMatrix.m13*accelerometerData.acceleration.z;
                    double accelY = rotationMatrix.m21*accelerometerData.acceleration.x +
                             rotationMatrix.m22*accelerometerData.acceleration.y +
                             rotationMatrix.m23*accelerometerData.acceleration.z;
                    double accelZ = rotationMatrix.m31*accelerometerData.acceleration.x +
                             rotationMatrix.m32*accelerometerData.acceleration.y +
                             rotationMatrix.m33*accelerometerData.acceleration.z;
*/

//        Matrix3 transformer = rotationMatrixFromOrientationVector(
//                Vector3(radians(orientation.x), radians(orientation.y),
//                        radians(orientation.z))
//        );
//        transformer.transform(acceleration);
//
//        List<double> distAndSpeed = calculateDistanceAndSpeed(
//                acceleration.x, _previousXSpeed, interval);
//        _distanceX = _distanceX + distAndSpeed[0];
//        _previousXSpeed = distAndSpeed[1];
//        distAndSpeed =
//                calculateDistanceAndSpeed(acceleration.y, _previousYSpeed, interval);
//        _distanceY = _distanceY + distAndSpeed[0];
//        _previousYSpeed = distAndSpeed[1];
//        distAndSpeed =
//                calculateDistanceAndSpeed(acceleration.z, _previousZSpeed, interval);
//        _distanceZ = distAndSpeed[0];
//        _previousZSpeed = _distanceZ + distAndSpeed[1];
//
//        _previousReportTime = now;
//        var f = NumberFormat("#.#######", "en_UK");
//        LatLng estimate = newPosition(_prevLatLng, _distanceX, _distanceY);
//
//        if (!_paused) {
//            setState(() {
//                _inLatLon = "in lat ${f.format(estimate.latitude)} lon ${f.format(
//                estimate.longitude)}";
//            _inDistance =
//                    "in X ${f.format(_distanceX)} Y ${f.format(_distanceY)}";
//        });
//    }
//}
//}