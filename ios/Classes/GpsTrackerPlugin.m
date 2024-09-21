#import "GpsTrackerPlugin.h"

@implementation GpsTrackerPlugin

          /*
           int auth = 0;
           switch (locMgr.accuracyAuthorization) {
           case CLAccuracyAuthorization.fullAccuracy:
           auth = 1;
           break;
           case CLAccuracyAuthorization.reducedAccuracy:
           auth = 2;
           break;
           default:
           auth = 3;
           break;
           }
           //    locMgr = nil;
           */

/*
    int auth = -1;
    if (self.locationManager != nil)
    {
      auth = self.locationManager.accuracyAuthorization;

      switch (locMgr.accuracyAuthorization) {
      case CLAccuracyAuthorization.fullAccuracy:
        auth = 1;
        break;
      case CLAccuracyAuthorization.reducedAccuracy:
        auth = 2;
        break;
      default:
        auth = 3;
        break;
      }
*/



/**
  * FlutterViewController
  */
GpsTrackerEventHandler *eventHandler;
GpsTrackerEventHandler *trackerEventHandler;

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
  [trackerEventChannel setStreamHandler:trackerEventHandler];}

- (void)handleMethodCall:(FlutterMethodCall*)call result:(FlutterResult)result {
  if ([@"getBatteryLevel" isEqualToString:call.method]) {
    UIDevice *myDevice = [UIDevice currentDevice];
    [myDevice setBatteryMonitoringEnabled:YES];
    result(@((int)([myDevice batteryLevel]*100.0)));
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
    if (self.locationManager == nil)
    {
      self.locationManager = [[CLLocationManager alloc] init];
//      self.locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters;
//      self.locationManager.desiredAccuracy = kCLLocationAccuracyBest;
      self.locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation;
      self.locationManager.distanceFilter = kCLDistanceFilterNone;
      self.locationManager.allowsBackgroundLocationUpdates = YES;
      self.locationManager.delegate = self;
      [self.locationManager startUpdatingLocation];
    }
  } else if ([@"stop" isEqualToString:call.method]) {
      [self.locationManager stopUpdatingLocation];
//      _locationManager = nil;
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
   
//    NSLog(@"didUpdateLocations called");
    bool first = true;
    for (CLLocation *location in locations)
    {
        double distance = 0.0;
        if (_position != nil)
        {
            distance = [ _position distanceFromLocation:location];
        }
//        NSLog(@"didUpdateLocations distance %6.2f lat %6.6f lon %6.6f accuracy %6.6f",
//          distance,location.coordinate.latitude,location.coordinate.longitude,location.horizontalAccuracy);

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
        NSLog(@"Status not determined");
        break;
    // The user denied authorization
    case kCLAuthorizationStatusDenied:
        NSLog(@"Status denied");
        break;
    case kCLAuthorizationStatusRestricted:
        NSLog(@"Status restricted");
        break;
    case kCLAuthorizationStatusAuthorizedAlways:
        NSLog(@"Status authorised always");
        break;
    case kCLAuthorizationStatusAuthorizedWhenInUse:
        NSLog(@"Status authorised when in use");
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
  NSLog(@"onListenWithArguments");
  _eventSink = eventSink;
  return nil;
}

- (FlutterError*)onCancelWithArguments:(id)arguments {
  NSLog(@"onCancelWithArguments");
  _eventSink = nil;
  return nil;
}

- (void)updateStatus:(int)status {
  NSLog(@"Update status");
  if (_eventSink == nil) return;

  NSMutableDictionary *fix = [NSMutableDictionary dictionaryWithCapacity:2];
  fix[@"reason"] = @"FIX_UPDATE";
  fix[@"fix_valid"] = [NSNumber numberWithBool:true];
  _eventSink(fix);
}

- (void)updateLocation:(CLLocation*)location walkName:(NSString *) walkName distance:(double) distance {
  if (_eventSink == nil) return;

  NSMutableDictionary *coordinates = [NSMutableDictionary dictionaryWithCapacity:8];
  coordinates[@"reason"] = @"COORDINATE_UPDATE";
  coordinates[@"walk_name"] = walkName;
  coordinates[@"latitude"] = [NSNumber numberWithDouble:location.coordinate.latitude];
  coordinates[@"longitude"] = [NSNumber numberWithDouble:location.coordinate.longitude];
  coordinates[@"accuracy"] = [NSNumber numberWithDouble:location.horizontalAccuracy];
  coordinates[@"speed"] = [NSNumber numberWithDouble:location.speed];
  coordinates[@"distance"] = [NSNumber numberWithDouble:distance];
  coordinates[@"fix_valid"] = [NSNumber numberWithBool:true];
  _eventSink(coordinates);
}
@end
