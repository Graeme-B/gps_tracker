import 'dart:async';
import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:gps_tracker_db/gps_tracker_db.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// https://testfairy.com/blog/listeners-with-eventchannel-in-flutter/

class GpsTracker {
  static const TRACKING_OFF    = 0;
  static const TRACKING        = 1;
  static const TRACKING_PAUSED = 2;

  static const GRANTED             = 0;
  static const LOCATION_OFF        = 1;
  static const INACCURATE_LOCATION = 2;
  static const DENIED              = 3;
  static const PARTLY_DENIED       = 4;
  static const PERMANENTLY_DENIED  = 5;

  static const FULL_ACCURACY_LEVEL    = 0;
  static const REDUCED_ACCURACY_LEVEL = 1;

  static const LOCATION_ENABLED        = 1;
  static const LOCATION_DISABLED       = 0;
  static const LOCATION_QUERY_DISABLED = -1;

  static const ERR_NO_GPS_PERMISSIONS = "GPS permissions have not been granted";

  static const MethodChannel _methodChannel = const MethodChannel(
      'com.moorwen.flutter.gps_tracker/method_channel');
  static const EventChannel _eventChannel = const EventChannel(
      'com.moorwen.flutter.gps_tracker/event_channel');
  static StreamSubscription? eventChannelStreamSubscription; // ignore: cancel_subscriptions
  static const EventChannel _gpsTrackerEventChannel = const EventChannel(
      'com.moorwen.flutter.gps_tracker/gps_tracker_event_channel');
  static StreamSubscription? gpsTrackerStreamSubscription;   // ignore: cancel_subscriptions
  static int tracking = TRACKING_OFF;

  // Testing and information
  static Future<int> get batteryLevel async {
    final int batteryLevel = await _methodChannel.invokeMethod(
        'getBatteryLevel');
    return batteryLevel;
  }

  // Testing and information
  static Future<bool> get locationPermanentlyDenied async {
    bool? permanentlyDenied;
    if (Platform.isAndroid) {
      final prefs = await SharedPreferences.getInstance();
      permanentlyDenied = prefs.getBool('permanentlyDenied');
    } else {
      var status = await Permission.location.status;
      if (status == PermissionStatus.permanentlyDenied) {
        permanentlyDenied = true;
      }
    }
    return permanentlyDenied == null ? false : permanentlyDenied;
  }

  // 0 - full accuracy (precise location allowed Ios)
  // 1 - reduced accuracy (precise location denied on Ios)
  // Always 0 on Android
  // static const FULL_ACCURACY_LEVEL    = 0;
  // static const REDUCED_ACCURACY_LEVEL = 1;
    static Future<int> get accuracyLevel async {
    final int accuracyLevel = await _methodChannel.invokeMethod(
        'getAccuracyLevel');
    return accuracyLevel;
  }

  // static const LOCATION_ENABLED = 1;
  // static const LOCATION_DENIED  = -1;
  static Future<int> get locationEnabled async {
    final int locationEnabled = await _methodChannel.invokeMethod('isLocationEnabled');
    return locationEnabled;
  }

  static Future<PermissionStatus> _requestLocationPermission(Permission permission) async {

    PermissionStatus status = await permission.status;
    if (status != PermissionStatus.granted)
    {
      if (status != PermissionStatus.permanentlyDenied) {
        status = await permission.request();
      }
    }
    return (status);

  }

  static void permissionDenied(Function onPermissionDenied) {
    onPermissionDenied();
    openAppSettings();
  }

// returns
//  static const GRANTED             = 0;
//  static const LOCATION_OFF        = 1;
//  static const INACCURATE_LOCATION = 2;
//  static const DENIED              = 3;
//  static const PARTLY_DENIED       = 4;
//  static const PERMANENTLY_DENIED  = 5;
//   static Future<bool> get permanentlyDenied async {
//     TRUE - permanently denied
//     FALSE - not permanently denied
//   static Future<int> get accuracyLevel async {
//     static const FULL_ACCURACY_LEVEL    = 0;
//     static const REDUCED_ACCURACY_LEVEL = 1;
//   static Future<int> get locationEnabled async {
//     static const LOCATION_ENABLED        = 1;
//     static const LOCATION_DISABLED       = 0;
//     static const LOCATION_QUERY_DISABLED = -1;
// Need a hierarchy of results!
//   LOCATION DISABLED - locationEnabled applies to both IOS and Android
//   REDUCED ACCURACY - accurayLevel applies to both IOS and Android
//   PERMANENTLY (or PARTLY) DENIED - permanentlyDenied applies to both IOS and Android
//                                  - partially denied is a bit different?
//   GRANTED - if non of the above apply?
// Main app will react to these
//   LOCATION DISABLED, REDUCED ACCURACY, PERMANENT (OR PART) DENIED
//     - show dialog, show settings and check again on return (will be RETURN TO FOREGROUND)
//   DENIED - show dialog, show permission request window: check result: show settings if any of above
//   GRANTED - continue as normal
  static Future<int> getCurrentLocationPermissions() async {
    int status = PERMANENTLY_DENIED;
    int result = await locationEnabled;
    if (result != LOCATION_ENABLED) {
      status = LOCATION_OFF;
    } else {
      result = await accuracyLevel;
      if (result != FULL_ACCURACY_LEVEL) {
        status = INACCURATE_LOCATION;
      } else {
        bool permanentlyDenied = await locationPermanentlyDenied;
        if (permanentlyDenied) {
          status = PERMANENTLY_DENIED;
        } else {
          PermissionStatus s1 = await Permission.location.status;
          PermissionStatus s2 = await Permission.locationAlways.status;
          PermissionStatus s3 = await Permission.locationWhenInUse.status;
          if (s1 == PermissionStatus.denied) {
            status = DENIED;
          }
          else if (s1 == PermissionStatus.granted) {
            if (s2 == PermissionStatus.granted && s3 == PermissionStatus.granted) {
              status = GRANTED;
            } else {
              status = PARTLY_DENIED;
            }
          }
        }
      }
    }

    return(status);
  }

  static Future<void> checkForLocationPermissionChanges() async {
    if (Platform.isAndroid) {
      PermissionStatus s1 = await Permission.location.status;
      if (s1 == PermissionStatus.granted) {
        final prefs = await SharedPreferences.getInstance();
        prefs.setBool('permanentlyDenied', false);
      }
    }
  }

  static Future<int> requestLocationPermissions() async {
    int retval = DENIED;
    if (Platform.isAndroid) {
      PermissionStatus status = await Permission.location.request();
      final prefs = await SharedPreferences.getInstance();
      if (status == PermissionStatus.permanentlyDenied) {
        prefs.setBool('permanentlyDenied',true);
        retval = PERMANENTLY_DENIED;
      } else {
        prefs.setBool('permanentlyDenied',false);
        retval = status == PermissionStatus.granted ? GRANTED : DENIED;
      }
    } else if (Platform.isIOS) {
      PermissionStatus status = await _requestLocationPermission(Permission.location);
      if (status.isGranted) {
        status = await _requestLocationPermission(Permission.locationAlways);
        retval = status == PermissionStatus.granted ? GRANTED : DENIED;
      } else if (status == PermissionStatus.permanentlyDenied) {
        retval = PERMANENTLY_DENIED;
      }
    }
    return(retval);
  }

  static Future<void> addGpsListener(_listener) async {
    var s = _eventChannel.receiveBroadcastStream();
    eventChannelStreamSubscription = s.listen(_listener);
  }

  static Future<void> removeGpsListener(_listener) async {
    if (eventChannelStreamSubscription != null)
      eventChannelStreamSubscription!.cancel();
    eventChannelStreamSubscription = null;
  }

  static void _listener(dynamic o) async {
    if (tracking == TRACKING) {
      var db = await DatabaseHelper.getDatabaseHelper();

      Map map = o as Map;

      var reason = map["reason"];
      if (reason == "COORDINATE_UPDATE") {
        var walkName = map["walk_name"];
        if (walkName != null && walkName
            .toString()
            .length > 0) {
          List<WalkTrackPoint> waypoints = [];
          WalkTrackPoint wtp = new WalkTrackPoint(
              create_date: DateFormat('dd-MM-yyyy – hh:mm:ss').format(
                  DateTime.now()),
              latitude: map["latitude"] as double,
              longitude: map["longitude"] as double,
              distance: map["distance"] as double,
              provider: "gps",
              accuracy: map["accuracy"] as double,
              elapsed_time: 0);
          waypoints.add(wtp);
          try {
            await db.addWalkTrackPoints(walkName, waypoints);
          } catch (err) {
            await writeDebug(
                "Error $err adding walk track points for walk '$walkName'");
          }
        }
      }
    }
  }

  static Future<void> start (
    {required String title, required String text, required String subText, required String ticker}) async {
    int status = await getCurrentLocationPermissions();
    if (status == GRANTED || status == PARTLY_DENIED) {
      _methodChannel.invokeMethod('start');
    } else {
      throw Exception(ERR_NO_GPS_PERMISSIONS);
    }
  }

  static Future<void> stop() {
    return _methodChannel.invokeMethod('stop');
  }

  static Future<void> startTracking(String trackName) {
    final args = {
      'walkName': trackName,
    };
    gpsTrackerStreamSubscription = _gpsTrackerEventChannel.receiveBroadcastStream().listen(_listener);
    tracking = TRACKING;
    return _methodChannel.invokeMethod('startTracking', args);
  }

  static void stopTracking() {
    if (gpsTrackerStreamSubscription != null)
      gpsTrackerStreamSubscription!.cancel();
    gpsTrackerStreamSubscription = null;
    tracking = TRACKING_OFF;
    _methodChannel.invokeMethod('stopTracking');
    _methodChannel.invokeMethod('resume');
  }

  static Future<void> pauseTracking() {
    tracking = TRACKING_PAUSED;
    return _methodChannel.invokeMethod('pause');
  }

  static Future<void> resumeTracking() {
    tracking = TRACKING;
    return _methodChannel.invokeMethod('resume');
  }

  static Future<Float64List>? getLocation() async {
    final Float64List location = await _methodChannel.invokeMethod('getLocation');
    return location;
  }

  static Future<int> getNumWalkTrackPoints() async {
    final int numPoints = await _methodChannel.invokeMethod('getNumWalkTrackPoints');
    return numPoints;
  }

  static Future<List<dynamic>> getWalkTrackPoints(int start, int end) async {
    final args = {
      'start': start,
      'end': end,
    };
    List<dynamic> points = await _methodChannel.invokeMethod('getWalkTrackPoints', args);
    return points;
  }

  static Future<double> getDistance() async {
    double distance = await  _methodChannel.invokeMethod('getDistance');
    return distance;
  }

  static Future<String> getWalkName() async {
    String walkName = await  _methodChannel.invokeMethod('getWalkName');
    return walkName;
  }

  static Future<String> get _localPath async {
    final directory = await getApplicationDocumentsDirectory();
    return directory.path;
  }

  static Future<File> get _localFile async {
    final path = await _localPath;
    return File('$path/log.txt');
  }

  static Future<void> writeDebug(String message) async {
    final file = await _localFile;
    await file.writeAsString(DateFormat("yyyy-MM-dd HH:mm:ss").format(DateTime.now()) + ": GPS_TRACKER: " + message + "\n", mode: FileMode.append);
  }
}
