package com.moorwen.gps_tracker;

import android.Manifest;
import android.app.Activity;
import android.content.BroadcastReceiver;
import android.content.ComponentName;
import android.content.Context;
import android.content.ContextWrapper;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.ServiceConnection;
import android.location.LocationManager;
import android.os.IBinder;
import android.util.Log;

import java.util.HashMap;
import java.util.Map;

// If this doesn't compile - missing import
// https://stackoverflow.com/questions/62172420/flutter-not-found-when-developing-plugin-for-android
//   Open the main flutter project.
//   Go to Tools -> Flutter -> Open For Editing In Android Studio
// (yes, it doesn't >make sense because we are already in AS, but it works).
import androidx.annotation.NonNull;
import androidx.core.app.ActivityCompat;
import androidx.core.app.NotificationCompat;
import androidx.core.location.LocationManagerCompat;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.embedding.engine.plugins.activity.ActivityAware;
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;
import io.flutter.plugin.common.EventChannel;
import io.flutter.plugin.common.PluginRegistry;

import static com.moorwen.gps_tracker.GpsTrackerService.ACCURACY;
import static com.moorwen.gps_tracker.GpsTrackerService.COORDINATE_UPDATE;
import static com.moorwen.gps_tracker.GpsTrackerService.FIX_VALID;
import static com.moorwen.gps_tracker.GpsTrackerService.GPS_FIX_VALID;
import static com.moorwen.gps_tracker.GpsTrackerService.LATITUDE;
import static com.moorwen.gps_tracker.GpsTrackerService.LONGITUDE;
import static com.moorwen.gps_tracker.GpsTrackerService.REASON;
import static com.moorwen.gps_tracker.GpsTrackerService.WALK_NAME;
import static com.moorwen.gps_tracker.GpsTrackerService.SPEED;
import static com.moorwen.gps_tracker.GpsTrackerService.DISTANCE;
import static com.moorwen.gps_tracker.GpsTrackerService.TIME;

/**
 * GpsTrackerPlugin
 */
public class GpsTrackerPlugin implements FlutterPlugin, MethodCallHandler, ActivityAware
{
    /// The MethodChannel that will the communication between Flutter and native Android
    ///
    /// This local reference serves to register the plugin with the Flutter Engine and unregister it
    /// when the Flutter Engine is detached from the Activity

    public static final String METHOD_CHANNEL         = "com.moorwen.flutter.gps_tracker/method_channel";
    public static final String EVENT_CHANNEL          = "com.moorwen.flutter.gps_tracker/event_channel";
    public static final String TRACKER_EVENT_CHANNEL  = "com.moorwen.flutter.gps_tracker/gps_tracker_event_channel";
    public static       String STARTFOREGROUND_ACTION = "com.moorwen.flutter.gps_tracker.action.startforeground";
    public static       String STOPFOREGROUND_ACTION  = "com.moorwen.flutter.gps_tracker.action.stopforeground";

    private DataUpdateReceiver dataUpdateReceiver;
    private Context            context             = null;
    private Activity           activity            = null;
    private GpsTrackerService  mService            = null;
    private MethodChannel      methodChannel       = null;
    private EventChannel       eventChannel        = null;
    private EventChannel       trackerEventChannel = null;

    // Listeners
    EventChannel.EventSink listener;
    EventChannel.EventSink trackerListener;

    /*
     * Class to receive updates from the GPS service
     */
    private class DataUpdateReceiver extends BroadcastReceiver
    {
        @Override
        public void onReceive(Context context, Intent intent)
        {
            Log.d("GPSTrackerPlugin","onReceive");
            try
            {
                if (GpsTrackerService.LOCATION_UPDATE.equals(intent.getAction()))
                {
                    Log.d("GPSTrackerPlugin","locationUpdate");
                    int reason = intent.getIntExtra(GpsTrackerService.REASON, -1);
                    switch (reason)
                    {
                    case COORDINATE_UPDATE:
                        Log.d("GPSPlugin","Received location update");
                        Map<String,Object> coordinates = new HashMap<>();
                        coordinates.put(REASON, "COORDINATE_UPDATE");
                        coordinates.put(WALK_NAME, intent.getStringExtra(WALK_NAME));
                        coordinates.put(LATITUDE, intent.getDoubleExtra(LATITUDE,0.0));
                        coordinates.put(LONGITUDE, intent.getDoubleExtra(LONGITUDE,0.0));
                        coordinates.put(ACCURACY, intent.getFloatExtra(ACCURACY,0.0f));
                        coordinates.put(SPEED, intent.getFloatExtra(SPEED,0.0f));
                        coordinates.put(DISTANCE, intent.getDoubleExtra(DISTANCE,0.0f));
                        coordinates.put(TIME, intent.getLongExtra(TIME,0));
                        coordinates.put(FIX_VALID, true);
                        if (listener != null) listener.success(coordinates);
                        if (trackerListener != null) trackerListener.success(coordinates);
//                        for (Map.Entry<Object, EventChannel.EventSink> entry : listeners.entrySet())
//                        {
//                            entry.getValue().success(coordinates);
//                        }
                        break;
                    case GPS_FIX_VALID:
                        Log.d("GPSPlugin","Received fix valid");
                        Map<String,Object> fixStatus = new HashMap<>();
                        fixStatus.put(REASON, "FIX_UPDATE");
                        fixStatus.put(FIX_VALID, true);
                        if (listener != null) listener.success(fixStatus);
                        if (trackerListener != null) trackerListener.success(fixStatus);
//                        for (Map.Entry<Object, EventChannel.EventSink> entry : listeners.entrySet())
//                        {
//                            entry.getValue().success(fixStatus);
//                        }
                        break;
                    default:
                        break;
                    }
                }
            }
            catch (Exception e)
            {
                Log.d("GPSPlugin","MainActivity onReceive exception " + e.getClass() + " message " + e.getMessage());
            }
        }
    }

    /*
     * Defines callbacks for service binding, passed to bindService()
     */
    private final ServiceConnection mConnection = new ServiceConnection()
    {

        @Override
        public void onServiceConnected(ComponentName className,
                                       IBinder service)
        {
            // We've bound to LocalService, cast the IBinder and get LocalService instance
//            ForegroundService.LocalBinder binder = (ForegroundService.LocalBinder) service;
            Log.d("GPSPlugin", "\nConnect");
            GpsTrackerService.LocalBinder binder = (GpsTrackerService.LocalBinder) service;
            mService                             = binder.getService();

            if (dataUpdateReceiver == null)
            {
                dataUpdateReceiver = new DataUpdateReceiver();
                IntentFilter intentFilter = new IntentFilter(GpsTrackerService.LOCATION_UPDATE);
                context.registerReceiver(dataUpdateReceiver, intentFilter, Context.RECEIVER_EXPORTED);
            }
        }

        @Override
        public void onServiceDisconnected(ComponentName arg0)
        {
            Log.d("GPSPlugin", "\nDisconnect");
            if (dataUpdateReceiver != null)
            {
                context.unregisterReceiver(dataUpdateReceiver);
                dataUpdateReceiver = null;
            }
            mService = null;
        }
    };

    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding flutterPluginBinding)
    {
        context = flutterPluginBinding.getApplicationContext();
        methodChannel = new MethodChannel(flutterPluginBinding.getBinaryMessenger(), METHOD_CHANNEL);
        methodChannel.setMethodCallHandler(this);

        eventChannel = new EventChannel(flutterPluginBinding.getBinaryMessenger(),EVENT_CHANNEL);
        eventChannel.setStreamHandler(
                new EventChannel.StreamHandler() {
                    @Override
                    public void onListen(Object obj, final EventChannel.EventSink eventSink) {
                        Log.d("GPSPlugin", "adding listener");
                        listener = eventSink;
                    }

                    @Override
                    public void onCancel(Object listener) {
                        Log.d("GPSPlugin", "cancelling listener");
                    }
                }
        );
        trackerEventChannel = new EventChannel(flutterPluginBinding.getBinaryMessenger(),TRACKER_EVENT_CHANNEL);
        trackerEventChannel.setStreamHandler(
                new EventChannel.StreamHandler() {
                    @Override
                    public void onListen(Object listener, final EventChannel.EventSink eventSink) {
                        Log.d("GPSPlugin", "adding tracker listener");
                        trackerListener = eventSink;
                    }

                    @Override
                    public void onCancel(Object listener) {
                        Log.d("GPSPlugin", "cancelling tracker listener");
                        trackerListener = null;
                    }
                }
        );
    }

    @Override
    @SuppressWarnings("ConstantConditions")
    public void onMethodCall(@NonNull MethodCall call, @NonNull Result result)
    {
        switch (call.method) {
        case "getPlatformVersion":
            result.success("Android " + android.os.Build.VERSION.RELEASE);
            break;
        case "getBatteryLevel":
            if (mService != null)
            {
                int batteryLevel = mService.getBatteryLevel();

                if (batteryLevel != -1)
                {
                    result.success(batteryLevel);
                }
                else
                {
                    result.error("UNAVAILABLE", "Battery level not available.", null);
                }
            }
            else
            {
                result.error("UNAVAILABLE", "Battery level not available as the service is not running.", null);
            }
            break;
        case "isLocationEnabled":
            LocationManager locationManager = (LocationManager) context.getSystemService(Context.LOCATION_SERVICE);
            int enabled = LocationManagerCompat.isLocationEnabled(locationManager) ? 1 : 0;
            result.success(enabled);
            break;
        case "getAccuracyLevel":
            result.success(0);
            break;
        case "start":
// https://stackoverflow.com/questions/20857120/what-is-the-proper-way-to-stop-a-service-running-as-foreground
//start
//            Intent startIntent = new Intent(MainActivity.this, ForegroundService.class);
//            startIntent.setAction(Constants.ACTION.STARTFOREGROUND_ACTION);
//            startService(startIntent);
//stop
//            Intent stopIntent = new Intent(MainActivity.this, ForegroundService.class);
//            stopIntent.setAction(Constants.ACTION.STOPFOREGROUND_ACTION);
//            startService(stopIntent);
            Intent startIntent = new Intent(context, GpsTrackerService.class);
            startIntent.setAction(STARTFOREGROUND_ACTION);
            context.startService(startIntent);
            context.bindService(startIntent, mConnection, Context.BIND_AUTO_CREATE);

//            Intent intent = new Intent(context, GpsTrackerService.class);
//            intent.setAction(STARTFOREGROUND_ACTION);
//            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
//            {
//                context.startForegroundService(intent);
//            }
//            else
//            {
//                context.startService(intent);
//            }
//            context.bindService(startIntent, mConnection, Context.BIND_AUTO_CREATE);
            result.success(null);
        break;
        case "stop":
            Intent stopIntent = new Intent(context, GpsTrackerService.class);
            stopIntent.setAction(STOPFOREGROUND_ACTION);
            context.startService(stopIntent);

//            Intent stopIntent = new Intent(context, GpsTrackerService.class);
//            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
//            {
//                stopIntent.setAction(STOPFOREGROUND_ACTION);
//                context.unbindService(mConnection);
//                context.startService(stopIntent);
//            }
//            else
//            {
//                context.unbindService(mConnection);
//                context.stopService(stopIntent);
//            }
            break;
        case "startTracking":
            if (mService != null)
            {
                mService.startTracking((String) call.argument("walkName"));
                result.success(null);
            }
            else
            {
                result.error("UNAVAILABLE", "Tracking not available as the service is not running.", null);
            }
            break;
        case "stopTracking":
            if (mService != null)
            {
                mService.stopTracking();
                result.success(null);
            }
            else
            {
                result.error("UNAVAILABLE", "Tracking not available as the service is not running.", null);
            }
            break;
        case "pause":
            if (mService != null)
            {
                mService.pauseTracking();
                result.success(null);
            }
            else
            {
                result.error("UNAVAILABLE", "Walk name not available as the service is not running.", null);
            }
            break;
        case "resume":
            if (mService != null)
            {
                mService.resumeTracking();
                result.success(null);
            }
            else
            {
                result.error("UNAVAILABLE", "Walk name not available as the service is not running.", null);
            }
            break;
        case "getLocation":
            if (mService != null)
            {
                result.success(mService.getLocation());
            }
            else
            {
                result.error("UNAVAILABLE", "Location not available as the service is not running.", null);
            }
            break;
        case "getNumWalkTrackPoints":
            if (mService != null)
            {
                result.success(mService.getNumWalkTrackPoints());
            }
            else
            {
                result.error("UNAVAILABLE", "Num track points not available as the service is not running.", null);
            }
            break;
        case "getWalkTrackPoints":
            if (mService != null) {
                int start;
                int end;
                try {
                    start = call.argument("start");
                    end   = call.argument("end");
                } catch (NullPointerException e) {
                    start = -1;
                    end = -1;
                }
                result.success(mService.getWalkTrackPoints(start, end));
//                result.success(mService.getWalkTrackPoints((int) call.argument("start"),(int) call.argument("end")));
            }
            else
            {
                result.error("UNAVAILABLE", "Num track points not available as the service is not running.", null);
            }
            break;
        case "getDistance":
            if (mService != null)
            {
                result.success(mService.getDistance());
            }
            else
            {
                result.error("UNAVAILABLE", "Distance not available as the service is not running.", null);
            }
            break;
        case "getWalkName":
            if (mService != null)
            {
                result.success(mService.getWalkName());
            }
            else
            {
                result.error("UNAVAILABLE", "Walk name not available as the service is not running.", null);
            }
            break;
        default:
            result.notImplemented();
            break;
        }
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding)
    {
        methodChannel.setMethodCallHandler(null);
        eventChannel.setStreamHandler(null);
        trackerEventChannel.setStreamHandler(null);
    }

    @Override
    public void onAttachedToActivity(ActivityPluginBinding binding) {
        activity = binding.getActivity();
        // Your plugin is now associated with an Android Activity.
        //
        // If this method is invoked, it is always invoked after
        // onAttachedToFlutterEngine().
        //
        // You can obtain an Activity reference with
        // binding.getActivity()
        //
        // You can listen for Lifecycle changes with
        // binding.getLifecycle()
        //
        // You can listen for Activity results, new Intents, user
        // leave hints, and state saving callbacks by using the
        // appropriate methods on the binding.
    }

    @Override
    public void onDetachedFromActivityForConfigChanges() {
        activity = null;
        // The Activity your plugin was associated with has been
        // destroyed due to config changes. It will be right back
        // but your plugin must clean up any references to that
        // Activity and associated resources.
    }

    @Override
    public void onReattachedToActivityForConfigChanges(ActivityPluginBinding binding) {
        activity = binding.getActivity();
        // Your plugin is now associated with a new Activity instance
        // after config changes took place. You may now re-establish
        // a reference to the Activity and associated resources.
    }
    @Override
    public void onDetachedFromActivity() {
        activity = null;
        // Your plugin is no longer associated with an Activity.
        // You must clean up all resources and references. Your
        // plugin may, or may not ever be associated with an Activity
        // again.
    }
}
