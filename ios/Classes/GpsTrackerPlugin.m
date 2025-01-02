#import "GpsTrackerPlugin.h"

@implementation GpsTrackerPlugin

GpsTrackerEventHandler    *eventHandler;
GpsTrackerEventHandler    *trackerEventHandler;
AccelerometerEventHandler *accelerometerEventHandler;

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
            [self.motionManager setAccelerometerUpdateInterval:0.1];
            [self.motionManager setDeviceMotionUpdateInterval:0.1];
            if ([self.motionManager isDeviceMotionAvailable]) {
                [self.motionManager startDeviceMotionUpdatesUsingReferenceFrame:CMAttitudeReferenceFrameXArbitraryZVertical];
            }
            NSOperationQueue *queue = [[NSOperationQueue alloc] init];
            [self.motionManager startAccelerometerUpdatesToQueue:queue withHandler:^(
                    CMAccelerometerData *accelerometerData, NSError *error) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    NSLog(@"GPSTracker - accelerometer time %6.4f raw [%6.4f %6.4f %6.4f] yaw %6.4f pitch %6.4f roll %6.4f",
                          CACurrentMediaTime(), accelerometerData.acceleration.x,
                          accelerometerData.acceleration.y,
                          self.motionManager.deviceMotion.attitude.yaw, self.motionManager.deviceMotion.attitude.pitch,
                          self.motionManager.deviceMotion.attitude.roll);

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
  } else if ([@"stopTracking" isEqualToString:call.method]) {
      _walkName = nil;
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
        NSLog(@"GPSTracker - didUpdateLocations time %6.4f distance %6.2f lat %6.6f lon %6.6f accuracy %6.6f",
              CACurrentMediaTime(),distance,location.coordinate.latitude,location.coordinate.longitude,location.horizontalAccuracy);

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
  NSLog(@"GPSTracker - Update Location");
  if (_eventSink == nil) return;

  NSMutableDictionary *coordinates = [NSMutableDictionary dictionaryWithCapacity:9];
  coordinates[@"reason"] = @"COORDINATE_UPDATE";
  coordinates[@"walk_name"] = walkName;
  coordinates[@"latitude"] = [NSNumber numberWithDouble:location.coordinate.latitude];
  coordinates[@"longitude"] = [NSNumber numberWithDouble:location.coordinate.longitude];
  coordinates[@"accuracy"] = [NSNumber numberWithDouble:location.horizontalAccuracy];
  coordinates[@"speed"] = [NSNumber numberWithDouble:location.speed];
  coordinates[@"heading"] = [NSNumber numberWithDouble:location.course];
  coordinates[@"distance"] = [NSNumber numberWithDouble:distance];
  coordinates[@"fix_valid"] = [NSNumber numberWithBool:true];
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
}
@end
