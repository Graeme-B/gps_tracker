// import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:gps_tracker/gps_tracker.dart';
import 'package:gps_tracker_db/gps_tracker_db.dart';
import 'package:intl/intl.dart';

final navigatorKey = GlobalKey<NavigatorState>();

void main() => runApp(
  MaterialApp(
    home: const MyApp(),
    navigatorKey: navigatorKey, // Setting a global key for navigator
  ),
);

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  String LISTENER_NAME              = "com.moorwen.main";
  String _permissionStatus          = 'Unknown status.';
  String _batteryLevel              = 'Unknown battery level.';
  String _locationPermanentlyDenied = 'Unknown location permanently denied.';
  String _locationEnabled           = 'Unknown location enabled.';
  String _accuracyLevel             = 'Unknown accuracy level.';
  String _location                  = 'Unknown location.';
  String _numWalkTrackPoints        = 'Unknown points.';
  String _distance                  = 'Unknown distance.';
  Timer? _timer;
  bool permissionsGranted = false;
  bool serviceStarted = false;
  bool tracking = false;

  ElevatedButton startServiceButton =
    const ElevatedButton(
      onPressed: null,
      child: Text('Start'),
    );
  ElevatedButton stopServiceButton =
    const ElevatedButton(
      onPressed: null,
      child: Text('Stop'),
    );
  ElevatedButton startTrackingButton =
    const ElevatedButton(
      onPressed: null,
      child: Text('Start Tracking'),
    );
  ElevatedButton stopTrackingButton =
    const ElevatedButton(
      onPressed: null,
      child: Text('Stop Tracking'),
    );
  ElevatedButton showDistanceButton =
    const ElevatedButton(
      onPressed: null,
      child: Text('Distance'),
    );
  ElevatedButton showNumPointsButton =
    const ElevatedButton(
      onPressed: null,
      child: Text('Num points'),
    );
  ElevatedButton showLocationButton =
    const ElevatedButton(
      onPressed: null,
      child: Text('Location'),
    );

    @override
    void initState() {
      super.initState();
      // IsFirstRun.isFirstCall().then((firstCall){
      //   int i = 3;
      // });
      WidgetsBinding.instance.addObserver(this);
    }

    void _actionsWhenPermissionGranted() {
    if (!permissionsGranted) {
      setState(() {
        startServiceButton =
            ElevatedButton(
              onPressed: _startService,
              child: const Text('Start'),
            );
      });
    }
  }

  void _actionsWhenServiceStarted() {
    setState(() {
      startServiceButton =
          const ElevatedButton(
            onPressed: null,
            child: Text('Start'),
          );
      stopServiceButton =
          ElevatedButton(
            onPressed: _stopService,
            child: const Text('Stop'),
          );
      startTrackingButton =
          ElevatedButton(
            onPressed: _startTracking,
            child: const Text('Start Tracking'),
          );
    });
  }

  void _actionsWhenServiceStopped() {
    setState(() {
      startServiceButton =
          ElevatedButton(
            onPressed: _startService,
            child: const Text('Start'),
          );
      stopServiceButton =
          const ElevatedButton(
            onPressed: null,
            child: Text('Stop'),
          );
      startTrackingButton =
          const ElevatedButton(
            onPressed: null,
            child: Text('Start Tracking'),
          );
    });
  }

  void _actionsWhenTrackingStarted() {
    setState(() {
      stopServiceButton =
          const ElevatedButton(
            onPressed: null,
            child: Text('Stop'),
          );
      startTrackingButton =
          const ElevatedButton(
            onPressed: null,
            child: Text('Start Tracking'),
          );
      stopTrackingButton =
          ElevatedButton(
            onPressed: _stopTracking,
            child: const Text('Stop Tracking'),
          );
      showDistanceButton =
          ElevatedButton(
            onPressed: _getDistance,
            child: const Text('Distance'),
          );
      showNumPointsButton =
          ElevatedButton(
            onPressed: _getNumWalkTrackPoints,
            child: const Text('Num points'),
          );
      showLocationButton =
          ElevatedButton(
            onPressed: _getLocation,
            child: const Text('Location'),
          );
    });
  }

  void _actionsWhenTrackingStopped() {
    setState(() {
      stopServiceButton =
          ElevatedButton(
            onPressed: _stopService,
            child: const Text('Stop'),
          );
      startTrackingButton =
          ElevatedButton(
            onPressed: _startTracking,
            child: const Text('Start Tracking'),
          );
      stopTrackingButton =
          const ElevatedButton(
            onPressed: null,
            child: Text('Stop Tracking'),
          );
      showDistanceButton =
          const ElevatedButton(
            onPressed: null,
            child: Text('Distance'),
          );
      showNumPointsButton =
          const ElevatedButton(
            onPressed: null,
            child: Text('Num points'),
          );
      showLocationButton =
          const ElevatedButton(
            onPressed: null,
            child: Text('Location'),
          );
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Tracker Test App'),
        ),
        body: Center(
          child: Column(
            children: <Widget>[
              Row(
                  children: <Widget>[
                    const Spacer(flex: 20),
                    ElevatedButton(
                      onPressed: _checkPermissions,
                      child: const Text('Permissions'),
                    ),
                    const Spacer(flex: 20),
                  ]
              ),
              Text(_permissionStatus),

              Row(
                  children: <Widget>[
                    const Spacer(flex: 20),
                    ElevatedButton(
                      onPressed: _requestPermissions,
                      child: const Text('Request permissions'),
                    ),
                    const Spacer(flex: 20),
                  ]
              ),

              ElevatedButton(
                onPressed: _getBatteryLevel,
                child: const Text('Get Battery Level'),
              ),
              Text(_batteryLevel),
              ElevatedButton(
                onPressed: _getLocationPermanentlyDenied,
                child: const Text('Show location permanently denied'),
              ),
              Text(_locationPermanentlyDenied),
              ElevatedButton(
                onPressed: _getLocationEnabled,
                child: const Text('Get Location Enabled'),
              ),
              Text(_locationEnabled),

              ElevatedButton(
                onPressed: _getAccuracyLevel,
                child: const Text('Get Accuracy Level'),
              ),
              Text(_accuracyLevel),

              Row(
                  children: <Widget>[
                    const Spacer(flex: 20),
                    startServiceButton,
                    const Spacer(),
                    stopServiceButton,
                    const Spacer(flex: 20),
                  ]
              ),

              Row(
                  children: <Widget>[
                    const Spacer(flex: 20),
                    startTrackingButton,
                    const Spacer(),
                    stopTrackingButton,
                    const Spacer(flex: 20),
                  ]
              ),
              Row(
                  children: <Widget>[
                    const Spacer(flex: 20),
                    showDistanceButton,
                    const Spacer(),
                    showNumPointsButton,
                    const Spacer(),
                    showLocationButton,
                    const Spacer(flex: 20),
                  ]
              ),

              Text(_numWalkTrackPoints),
              Text(_location),
              Text(_distance),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _checkPermissions() async {
    int status = await GpsTracker.getCurrentLocationPermissions();
    String statusMsg = "Permission status: unknown";
    switch (status) {
      case GpsTracker.GRANTED:
        statusMsg = "Permission status: granted ($status)";
        break;
      case GpsTracker.LOCATION_OFF:
        statusMsg = "Permission status: location off ($status)";
        break;
      case GpsTracker.INACCURATE_LOCATION:
        statusMsg = "Permission status: inaccurate location ($status)";
        break;
      case GpsTracker.DENIED:
        statusMsg = "Permission status: denied ($status)";
        break;
      case GpsTracker.PARTLY_DENIED:
        statusMsg = "Permission status: partly denied ($status)";
        break;
      case GpsTracker.PERMANENTLY_DENIED:
        statusMsg = "Permission status: permanently denied ($status)";
        break;
      default:
        statusMsg = "Permission status: unknown ($status)";
        break;
    }
    setState(() {
      _permissionStatus = statusMsg;
    });
  }

  Future<void> _requestPermissions() async {

    int status = await GpsTracker.getCurrentLocationPermissions();
    switch (status) {
      case GpsTracker.GRANTED:
        _actionsWhenPermissionGranted();
        break;
      case GpsTracker.DENIED:
        while (status == GpsTracker.DENIED) {
          status = await GpsTracker.requestLocationPermissions();
        }
        if (status == GpsTracker.GRANTED) {
          _actionsWhenPermissionGranted();
        }
        else if (status == GpsTracker.PERMANENTLY_DENIED) {
          showDialog(
              context: context,
              builder: (BuildContext context) {
                return const LoginSucessDialog(fred: 'Status');
              }).then((val) {
            // Navigator.pop(context);
            if (val) {
              openAppSettings();
            }
          });
        }
        break;
      case GpsTracker.LOCATION_OFF:
      case GpsTracker.INACCURATE_LOCATION:
      case GpsTracker.PARTLY_DENIED:
      case GpsTracker.PERMANENTLY_DENIED:
        showDialog(
            context: context,
            builder: (BuildContext context) {
              return const LoginSucessDialog(fred: 'Status');
            }).then((val) {
          // Navigator.pop(context);
          if (val) {
            openAppSettings();
          }
        });
        break;
      default:
        break;
    }
  }

  Future<void> _startService() async
  {
    if (!serviceStarted) {
      GpsTracker.addGpsListener(_listener);
      await GpsTracker.start(
        title: "GPS Tracker",
        text: "Text",
        subText: "Subtext",
        ticker: "Ticker",
      );
      serviceStarted = true;
    }
    _actionsWhenServiceStarted();
  }

  Future<void> _stopService() async
  {
    if (serviceStarted) {
      GpsTracker.removeGpsListener(_listener);
      GpsTracker.stop();
      serviceStarted = false;
    }
    _actionsWhenServiceStopped();
  }

  Future<void> _getBatteryLevel() async
  {
    String batteryLevel;
    try {
      final int result = await GpsTracker.batteryLevel;
      batteryLevel = 'Battery level at $result % .';
    }
    on PlatformException catch (e) {
      batteryLevel = "Failed to get battery level: '${e.message}'.";
    }

    setState(() {
      _batteryLevel = batteryLevel;
    });
  }

  Future<void> _getLocationPermanentlyDenied() async
  {
    String loctionPermanentlyDenied;
    try {
      final bool result = await GpsTracker.locationPermanentlyDenied;
      loctionPermanentlyDenied = 'Location permanently denied $result.';
    }
    on PlatformException catch (e) {
      loctionPermanentlyDenied = "Failed to get location permanently denied: '${e.message}'.";
    }

    setState(() {
      _locationPermanentlyDenied = loctionPermanentlyDenied;
    });
  }

  Future<void> _getLocationEnabled() async
  {
    String locationEnabled;
    try {
      final int result = await GpsTracker.locationEnabled;
      locationEnabled = 'Location enabled $result.';
    }
    on PlatformException catch (e) {
      locationEnabled = "Failed to get location enabled: '${e.message}'.";
    }

    setState(() {
      _locationEnabled = locationEnabled;
    });
  }

  Future<void> _getAccuracyLevel() async
  {
    String accuracyLevel;
    try {
      final int result = await GpsTracker.accuracyLevel;
      accuracyLevel = 'Accuracy level at $result.';
    }
    on PlatformException catch (e) {
      accuracyLevel = "Failed to get battery level: '${e.message}'.";
    }

    setState(() {
      _accuracyLevel = accuracyLevel;
    });
  }

  Future<void> _startTracking() async
  {
    if (serviceStarted && !tracking) {
      var db = await DatabaseHelper.getDatabaseHelper();
      DateTime now = DateTime.now();
      String formattedDate = DateFormat("yyyy-MM-dd HH:mm:ss").format(now);
      await db.addWalk(formattedDate);
      GpsTracker.startTracking(formattedDate);
      tracking = true;
//    startTimer();
    }
    _actionsWhenTrackingStarted();
  }

  void _listener(dynamic o) {
    print("MAIN - GPS tracker update"); // - reason $reason status $status lat $lat lon $lon");
    // print("type "  + o.runtimeType.toString());
    // Map retval = o as Map;
    // print("retval type "  + retval.runtimeType.toString());
    // retval.forEach((k,v) {
    //   print("k type " + k.runtimeType.toString() + " v type " + v.runtimeType.toString());
    //   print("k $k v $v");
    // });
    Map map = o as Map;
    var reason = map["reason"];
    var fixValid = map["fix_valid"] as bool;
    if (reason == "COORDINATE_UPDATE") {
      var latitude = map["latitude"] as num;
      var longitude = map["longitude"] as num;
      var accuracy = map["accuracy"] as num;
      var speed = map["speed"] as num;
      print("COORDINATE UPDATE - latitude $latitude longitude $longitude speed $speed accuracy $accuracy fix_valid $fixValid");
    } else {
      print("FIX UPDATE - fix valid $fixValid");
    }

  }

  Future<void> _stopTracking() async
  {
    if (serviceStarted && tracking) {
      GpsTracker.stopTracking();
      if (_timer != null) {
        _timer!.cancel();
        _timer = null;
      }
      tracking = false;
    }
    _actionsWhenTrackingStopped();
  }

  Future<void> _getLocation() async
  {
    String location;
    try {
      final result = await GpsTracker.getLocation();
      var lat = result!.first;
      var long = result.last;
      var f = NumberFormat("#.#######", "en_UK");
      location = "Lat ${f.format(lat)} long ${f.format(long)}";
    }
    on PlatformException catch (e) {
      location = "Failed to get location: '${e.message}'.";
    }
    setState(() {
      _location = location;
    });
  }

  Future<void> _getNumWalkTrackPoints() async
  {
    String numWalkTrackPoints;
    try {
      final result = await GpsTracker.getNumWalkTrackPoints();
      numWalkTrackPoints = "There are $result track points";
    }
    on PlatformException catch (e) {
      numWalkTrackPoints = "Failed to get num track points: '${e.message}'.";
    }
    setState(() {
      _numWalkTrackPoints = numWalkTrackPoints;
    });
  }

  Future<void> _getWalkTrackPoints() async
  {
    try {
      final numPoints = await GpsTracker.getNumWalkTrackPoints();
      final result = await GpsTracker.getWalkTrackPoints(0,numPoints);
      String resultType = result.runtimeType.toString();
      int numEntries = result.length;
      for (final latLong in result)
      {
        var currentElement = latLong;
        resultType = currentElement.runtimeType.toString();
        int numElements = latLong.length;
        var lat = latLong[0];
        var lon = latLong[1];
      }
    }
    on PlatformException {
    }
  }

  Future<void> _getDistance() async
  {
    String distance;
    try {
      final result = await GpsTracker.getDistance();
      final resultToPrint = result.toInt();
      distance = "Travelled $resultToPrint metres";
    }
    on PlatformException catch (e) {
      distance = "Failed to get distance: '${e.message}'.";
    }
    setState(() {
      _distance = distance;
    });
  }

  void startTimer() {
    const oneSec = Duration(seconds: 1);
    _timer = Timer.periodic(oneSec,(Timer timer) {
// Put code to read stuff here
        _getNumWalkTrackPoints();
        _getLocation();
        _getDistance();
        _getWalkTrackPoints();
      },
    );
  }

  @override
  void dispose() {
    _timer!.cancel();
    _timer = null;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycleState) {
    if (lifecycleState == AppLifecycleState.resumed) {
      GpsTracker.checkForLocationPermissionChanges();
    } else if(lifecycleState == AppLifecycleState.paused) {
      int i = 3;
    }
  }

}

class LoginSucessDialog extends StatefulWidget {
  final String fred;

  const LoginSucessDialog({super.key,  required this.fred });
  @override
  _LoginSucessDialogState createState() => _LoginSucessDialogState();
}

class _LoginSucessDialogState extends State<LoginSucessDialog> {

  @override
  Widget build(BuildContext context) {
    // return Dialog(
    //   shape: RoundedRectangleBorder(
    //     borderRadius: BorderRadius.circular(20),
    //   ),
    //   elevation: 0,
    //   backgroundColor: Colors.white,
    //   child: contentBox(context),
    // );

    return AlertDialog(
      title: const Text('Location Status'),
      content: const SingleChildScrollView(
        child: ListBody(
          children: <Widget>[
            Text(
'In order for this application to function, it requires location tracking to be enabled, precise accuracy to be turned on, and access to all location functions. Press the SETTINGS button to open the settings window then enable all these features to continue.'),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          child: const Text('Settings'),
          onPressed: () {
            Navigator.of(context).pop(true);
          },
        ),
        TextButton(
          child: const Text('Disable'),
          onPressed: () {
            Navigator.of(context).pop(false);
          },
        ),
      ],
    );


  }

  contentBox(context) {
    return Stack(
      children: <Widget>[
        Container(

          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[

              Text(widget.fred),

            ],
          ),
        ),
      ],
    );
  }
}
