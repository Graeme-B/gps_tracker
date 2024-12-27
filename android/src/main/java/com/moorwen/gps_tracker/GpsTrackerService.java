package com.moorwen.gps_tracker;

import static android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.Service;
import android.content.ContextWrapper;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.pm.ServiceInfo;
import android.graphics.Color;
import android.location.GnssStatus;
import android.location.LocationListener;
import android.os.BatteryManager;
import android.os.Binder;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.IBinder;
import android.util.Log;

import java.util.ArrayList;
import java.util.List;

import android.location.Location;
import android.location.LocationManager;
import android.util.Pair;

import androidx.core.app.NotificationCompat;

public class GpsTrackerService extends Service implements LocationListener// , GpsStatus.Listener
{
    private static final long MIN_DISTANCE_CHANGE_FOR_UPDATES = 1;    // 1 meter
    private static final long MIN_TIME_BW_UPDATES             = 1000; // 1 second
    private static final int  TIMER_TICK                      = 500;

    static final String LOCATION_UPDATE = "com.moorwen.coursewalker.LocationUpdate";
    static final String WALK_NAME       = "walk_name";
    static final String REASON          = "reason";
    static final String LATITUDE        = "latitude";
    static final String LONGITUDE       = "longitude";
    static final String ACCURACY        = "accuracy";
    static final String PROVIDER        = "provider";
    static final String DISTANCE        = "distance";
    static final String SPEED           = "speed";
    static final String HEADING         = "heading";
    static final String TIME            = "time";
    static final String FIX_VALID       = "fix_valid";

    static final int COORDINATE_UPDATE = 0;
    static final int GPS_FIX_VALID     = 3;
    static final int GPS_FIX_INVALID   = 4;

    NotificationManager mNotifyManager;
    NotificationCompat.Builder mBuilder;
    NotificationChannel notificationChannel;
    GpsStatus gpsStatus;

    String NOTIFICATION_CHANNEL_ID    = "1";
    LocationManager  locationManager  = null;
    private boolean  tracking         = false;
    private Location currLocation     = null;
    private String   walkName         = null;
    private boolean  paused           = false;
    private double   distance         = 0.0;
    private long     elapsedTime      = 0;
    private long     prevTime         = 0;
    private boolean  isGPSFix         = false;
    private final ArrayList<Pair<Double,Double>> walkTrack = new ArrayList<>();

    /*
     * Methods to get some of the internal variables
     */
//    public Location getLocation()   { return(currLocation); }
    public double                    getDistance()           { return (distance); }
    public String                    getWalkName()           { return (walkName); }
//    public long                      getElapsedTime()        { return (elapsedTime); }
//    public boolean                   isPaused()              { return(paused); }
//    public boolean                   isTracking()            { return(tracking); }
//    public List<Pair<Double,Double>> getWalkTrack()          { return(walkTrack); }
//    public boolean                   isFixValid()            { return(isGPSFix);}
//    public int                       timeSinceLastFix()      { return(timeSinceLastFix/1000);}
//    public boolean                   setFromLastLoc()        { return(setFromLastLoc);}
    public int                       getNumWalkTrackPoints() { return(walkTrack.size());}

    public List<double[]> getWalkTrackPoints(int start, int end)
    {
        if (start < 0) start = 0;
        if (end >= walkTrack.size() || end < 0) end = walkTrack.size();
        List<double[]> walkTrackPoints = new ArrayList<>();
        for (int i = start; i < end; i++)
        {
            Pair<Double,Double> latLong = walkTrack.get(i);
            double[] point = new double[2];
            point[0] = latLong.first;
            point[1] = latLong.second;
            walkTrackPoints.add(point);
        }
        return(walkTrackPoints);
    }

    /*
     * runs without a timer by reposting this handler at the end of the runnable
     */
    Handler timerHandler = new Handler();
    Runnable timerRunnable = new Runnable()
    {
        @Override
        public void run()
        {
            try
            {
                if (prevTime > 0)
                {
                    elapsedTime = elapsedTime + System.currentTimeMillis() - prevTime;
                }
                prevTime = System.currentTimeMillis();
                timerHandler.postDelayed(this, TIMER_TICK);
            }
            catch (Exception e)
            {
                Log.d("GPSService","Run exception " + e.getClass() + " message " + e.getMessage());
            }
        }
    };


    /*
     * Class used for the client Binder.  Because we know this service always
     * runs in the same process as its clients, we don't need to deal with IPC.
     */
    class LocalBinder extends Binder
    {
        GpsTrackerService getService()
        {
            // Return this instance of LocalService so clients can call public methods
            return GpsTrackerService.this;
        }
    }

    // Debug purposes only
    public int getBatteryLevel()
    {
        Log.d("GPSService", "\nBattery");

        int batteryLevel;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP)
        {
            BatteryManager batteryManager = (BatteryManager) getSystemService(BATTERY_SERVICE);
            batteryLevel = batteryManager.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY);
        }
        else
        {
            Intent intent = new ContextWrapper(getApplicationContext()).
                    registerReceiver(null, new IntentFilter(Intent.ACTION_BATTERY_CHANGED), RECEIVER_EXPORTED);
            batteryLevel = (intent.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) * 100) /
                    intent.getIntExtra(BatteryManager.EXTRA_SCALE, -1);
        }
        return (batteryLevel);
    }

    public double[] getLocation()
    {
        double [] loc = new double[2];
        if (currLocation != null)
        {
            loc[0] = currLocation.getLatitude();
            loc[1] = currLocation.getLongitude();
        }
        return (loc);
    }

    public GpsTrackerService() {
        gpsStatus = new GpsStatus(this);
    }

//    @Override
//    public void onCreate()
//    {
//        super.onCreate();
//
//        Log.d("GPSService", "OnCreate... \n");
//
//    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId)
    {

        Log.d("GPSService", "\nOnStartCommand");
        if (intent.getAction().equals(GpsTrackerPlugin.STARTFOREGROUND_ACTION))
        {
            Log.d("GPSService", "\nStart");

            mNotifyManager = (NotificationManager) getApplicationContext().getSystemService(NOTIFICATION_SERVICE);
            mBuilder = new NotificationCompat.Builder(this, "MyChannelID");
            mBuilder.setContentTitle("My App")
                    .setContentText("Always running...")
                    .setTicker("Always running...")
//                    .setSmallIcon(R.mipmap.ic_launcher)
//                .setLargeIcon(IconLg)
                    .setPriority(Notification.PRIORITY_HIGH)
                    .setVibrate(new long[]{1000})
                    .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                    .setOngoing(true)
                    .setAutoCancel(false);

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            {
                notificationChannel = new NotificationChannel(NOTIFICATION_CHANNEL_ID, "My Notifications", NotificationManager.IMPORTANCE_HIGH);

                // Configure the notification channel.
                notificationChannel.setDescription("Channel description");
                notificationChannel.enableLights(true);
                notificationChannel.setLightColor(Color.RED);
                notificationChannel.setVibrationPattern(new long[]{1000});
                notificationChannel.enableVibration(true);
                notificationChannel.setLockscreenVisibility(Notification.VISIBILITY_PUBLIC);
                mNotifyManager.createNotificationChannel(notificationChannel);

                mBuilder.setChannelId(NOTIFICATION_CHANNEL_ID);
//                if (Build.VERSION.SDK_INT >= 34) {
//                    startForeground(1, mBuilder.build(),                            ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE);
//                    ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION);
//                } else {
//                    startForeground(1, mBuilder.build());
//                }
                  startForeground(1, mBuilder.build(),FOREGROUND_SERVICE_TYPE_LOCATION);
            }
            else
            {
                mBuilder.setChannelId(NOTIFICATION_CHANNEL_ID);
                mNotifyManager.notify(1, mBuilder.build());
            }
            timerHandler.postDelayed(timerRunnable, 0);
        }
        else if (intent.getAction().equals( GpsTrackerPlugin.STOPFOREGROUND_ACTION)) {
            Log.d("GPSService", "Stop");
            //your end servce code
            stopForeground(true);
            if (mNotifyManager != null) {
                mNotifyManager.cancelAll();
            }
            stopSelf();
        }

        return START_STICKY;
    }

//    @Override
//    public void onDestroy()
//    {
//        Log.d("GPSService", "\nDestroyed....");
//        super.onDestroy();
//    }


    @Override
    public IBinder onBind(Intent intent)
    {
//        mainActivityClass = (Class)intent.getSerializableExtra("MainActivityClass");
//        return mBinder;
        return new LocalBinder();
    }

    /*
     * Called when we start tracking
     */
    public void startTracking(String walkName)
    {
        Log.d("GPSService", "\nstartTracking - walk name " + walkName);
        paused      = false;
        distance    = 0.0;
        elapsedTime = 0;
        prevTime      = System.currentTimeMillis();
//        try
//        {
//            myDb.addWalk(walkName);
//        }
//        catch (Exception e)
//        {
//            Log.d("GPSService","GPSTracker startTracking exception " + e.getClass().toString() + " message " + e.getMessage());
//        }

        this.walkName = walkName;
        paused        = false;
        distance      = 0.0;
        elapsedTime   = 0;
        prevTime      = System.currentTimeMillis();
        walkTrack.clear();
        if (currLocation == null)
        {
            try
            {
                currLocation = locationManager.getLastKnownLocation(LocationManager.GPS_PROVIDER);
            }
            catch (SecurityException e)
            {
            }
        }
//        if (currLocation != null)
//        {
//            try
//            {
//                myDb.addWalkTrackPoint(walkName,
//                        new WalkTrackPoint(new Pair<>(currLocation.getLatitude(), currLocation.getLongitude()),
//                                distance, elapsedTime, currLocation.getProvider(), currLocation.getAccuracy()));
//                walkTrack.add(new Pair<>(currLocation.getLatitude(), currLocation.getLongitude()));
//            }
//            catch (NonExistentWalkException e)
//            {
//                Log.d("GPSService","GPSTracker startTracking Non existent walk " + walkName);
//            }
//        }
        tracking = true;
//        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
//        {
//            ((NotificationManager) getSystemService(Context.NOTIFICATION_SERVICE)).notify(CHANNEL_ID, createNotification(getResources().getString(R.string.tracking)));
//            startForeground(CHANNEL_ID, createNotification(getResources().getString(R.string.tracking)));
//        }

        timerHandler.postDelayed(timerRunnable, 0);
    }

    /*
     * Called when we stop tracking
     */
    public void stopTracking()
    {
        Log.d("GPSService", "\nstopTracking");
        tracking = false;
        walkName = null;
//        paused   = false;
//        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
//        {
//            ((NotificationManager) getSystemService(Context.NOTIFICATION_SERVICE)).notify(CHANNEL_ID, createNotification(getResources().getString(R.string.ready_to_track)));
//            stopForeground(STOP_FOREGROUND_REMOVE);
//        }
        timerHandler.removeCallbacks(timerRunnable);
    }

    /*
     * Called to pause tracking
     */
    public void pauseTracking()
    {
        paused = true;
//        ((NotificationManager) getSystemService(Context.NOTIFICATION_SERVICE)).notify(CHANNEL_ID, createNotification(getResources().getString(R.string.paused)));
////        timerHandler.removeCallbacks(timerRunnable);
    }

    /*
     * Called to resume tracking
     */
    public void resumeTracking()
    {
        paused   = false;
//        prevTime = System.currentTimeMillis();
//        ((NotificationManager) getSystemService(Context.NOTIFICATION_SERVICE)).notify(CHANNEL_ID, createNotification(getResources().getString(R.string.tracking)));
////        timerHandler.postDelayed(timerRunnable, 0);
    }

    /*
     * Called if we're switched out
     */
//    public void appPaused()
//    {
//        Logger.logDebug(String.format("GPSTracker paused - tracking %b",tracking));
//        if (!tracking)
//        {
//            locationManager.removeUpdates(GPSTracker.this);
//        }
//    }

    /*
     * Called when we're switched back in
     */
//    public void appResumed()
//    {
//        Logger.logDebug(String.format("GPSTracker resumed - tracking %b",tracking));
//        if (!tracking)
//        {
//            try
//            {
//                locationManager.addGpsStatusListener(this);
//                locationManager.requestLocationUpdates(
//                        LocationManager.GPS_PROVIDER,
//                        MIN_TIME_BW_UPDATES,
//                        MIN_DISTANCE_CHANGE_FOR_UPDATES, this);
//            }
//            catch (SecurityException e)
//            {
//            }
//        }
//    }

    /*
     * Broadcasts the new location
     */
    private void broadcastLocationChange()
    {
        Log.d("GPSService", "\nbroadcastLocationChange");

//        double speed = 0.0;
//        if (elapsedTime > 0)
//        {
//            speed = (distance / elapsedTime) * 60000.0;
//        }

        Intent intent = new Intent();
        intent.setAction(LOCATION_UPDATE);
        intent.addFlags(Intent.FLAG_INCLUDE_STOPPED_PACKAGES);
        intent.putExtra(REASON, COORDINATE_UPDATE);
        intent.putExtra(WALK_NAME, walkName);
        if (currLocation != null)
        {
            intent.putExtra(LATITUDE, currLocation.getLatitude());
            intent.putExtra(LONGITUDE, currLocation.getLongitude());
            intent.putExtra(ACCURACY, currLocation.getAccuracy());
            intent.putExtra(PROVIDER, currLocation.getProvider());
            intent.putExtra(SPEED, currLocation.getSpeed());
            intent.putExtra(HEADING,currLocation.getBearing());
        }
        intent.putExtra(DISTANCE, distance);
        intent.putExtra(TIME, elapsedTime);
        Log.d("GPSService", "\nsending broadcast");
        sendBroadcast(intent);
    }

    /*
     * Broadcast a GPS fix status message
     */
    private void broadcastFixStatus()
    {
        Intent intent = new Intent();
        intent.setAction(LOCATION_UPDATE);
        intent.addFlags(Intent.FLAG_INCLUDE_STOPPED_PACKAGES);
        intent.putExtra(REASON, isGPSFix ? GPS_FIX_VALID : GPS_FIX_INVALID);
        sendBroadcast(intent);
    }

    /*
     * onCreate
     */
    @Override
    public void onCreate()
    {
        super.onCreate();
        Log.d("GPSService","onCreate");
//        myDb = DBHelper.getInstance(this);
        try
        {
            locationManager = (LocationManager) getApplicationContext().getSystemService(LOCATION_SERVICE);

            try
            {
                locationManager.registerGnssStatusCallback(gpsStatus);
                if (locationManager.isProviderEnabled(LocationManager.GPS_PROVIDER))
                {
                    Log.d("GPSService","Requesting updates");
                    locationManager.requestLocationUpdates(LocationManager.GPS_PROVIDER,
                            MIN_TIME_BW_UPDATES,
                            MIN_DISTANCE_CHANGE_FOR_UPDATES, this);
                }
                else
                {
                    Log.d("GPSService","Setting intent");
                    Intent gpsOptionsIntent = new Intent(
                            android.provider.Settings.ACTION_LOCATION_SOURCE_SETTINGS);
                    gpsOptionsIntent.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                    startActivity(gpsOptionsIntent);
                }
            }
            catch (SecurityException e)
            {
            }

//            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
//            {
//                startForeground(CHANNEL_ID, createNotification(getResources().getString(R.string.waiting_for_gps)));
//            }
        }
        catch (Exception e)
        {
            Log.d("GPSService","onCreate Exception " + e.getClass().getName() + " starting GPS tracker - error is " + e.getMessage());
        }
    }

    /*
     * onDestroy
     */
    @Override
    public void onDestroy()
    {
        super.onDestroy();
//        Logger.logDebug("GPSTracker onDestroy");
    }

    /*
     * onLocationChanged - message from the GPS
     * Update the distance etc, add to the database,
     * and tell anyone who's listening
     */
    @Override
    public void onLocationChanged(Location location)
    {
        try
        {
            Log.d("GPSService", "\nonLocationChanged");

            if (location.getProvider().equals(LocationManager.GPS_PROVIDER))
            {
                Log.d("GPSService", "onLocationChange");
                isGPSFix = true;

                if (tracking)
                {
                    if (!paused)
                    {
                        double d = 0.0;
                        if (currLocation != null)
                        {
                            d = location.distanceTo(currLocation);
                        }
//                        if (d > location.getAccuracy())
//                        {
                        distance += d;
//                        try
//                        {
//                            myDb.addWalkTrackPoint(walkName,
//                                    new WalkTrackPoint(new Pair<>(location.getLatitude(), location.getLongitude()),
//                                            distance, elapsedTime, location.getProvider(), location.getAccuracy()));
//                        }
//                        catch (NonExistentWalkException e)
//                        {
//                            Log.d("GPSService","GPSTracker onLocationChanged Non existent walk " + walkName);
//                        }
                        walkTrack.add(new Pair<>(location.getLatitude(), location.getLongitude()));
                    }
                }
                broadcastLocationChange();
//
//                if (setFromLastLoc)
//                {
//                    setFromLastLoc = false;
//                    double d = location.distanceTo(currLocation);
//                    Logger.logInfo(String.format("GPSTracker - set from last loc - distance %2.5f",d));
//                }
                currLocation = location;
//                prevFixTime  = SystemClock.elapsedRealtime();
            }
            //Logger.logDebug("GPS onLocation changed - provider " + location.getProvider() + " accuracy " + location.getAccuracy());
        }
        catch (SecurityException e)
        {
            //Logger.logDebug("GPSTracker onLocationChanged exception " + e.getClass().toString() + " message " + e.getMessage());
            Log.d("GPSService","onLocationChanged securtyException message " + e.getMessage());

        }
        catch (Exception e)
        {
            Log.d("GPSService","onLocationChanged exception " + e.getClass() + " message " + e.getMessage());
        }
    }

    void gpsFirstFix(int ttffMillis) {
        isGPSFix = true;
        broadcastFixStatus();
    }

    void gpsStopped() {
        isGPSFix = false;
        broadcastFixStatus();
    }

    void gpsStarted() {
    }

    void gpsSatelliteStatus(GnssStatus status) {
    }

    /*
     * Called when the GPS is disabled - tell anyone who's interested
     */
    @Override
    public void onProviderDisabled(String provider) {
//        Logger.logDebug("GPSTracker onProviderDisabled");
//
//        Intent intent = new Intent();
//        intent.setAction(LOCATION_UPDATE);
//        intent.addFlags(Intent.FLAG_INCLUDE_STOPPED_PACKAGES);
//        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
//        intent.putExtra(REASON, GPS_DISABLED);
//        sendBroadcast(intent);
    }

    /*
     * Called when the GPS is enabled - tell anyone who's interested
     */
    @Override
    public void onProviderEnabled(String provider)
    {
//        Intent intent = new Intent();
//        intent.setAction(LOCATION_UPDATE);
//        intent.addFlags(Intent.FLAG_INCLUDE_STOPPED_PACKAGES);
//        intent.putExtra(REASON, GPS_ENABLED);
//        sendBroadcast(intent);
    }

    /*
     * Called when the status changes - just log the event
     * NB - what's the difference between this and GPS status changed????
     */
    @Override
    public void onStatusChanged(String provider, int status, Bundle extras)
    {
//        String newStatus;
//        switch (status)
//        {
//        case LocationProvider.AVAILABLE:
//            newStatus = "AVAILABLE";
//            break;
//        case LocationProvider.TEMPORARILY_UNAVAILABLE:
//            newStatus = "TEMPORARILY UNAVAILABLE";
//            break;
//        case LocationProvider.OUT_OF_SERVICE:
//            newStatus = "OUT OF SERVICE";
//            break;
//        default:
//            newStatus = "UNKNOWN - VALUE " + status;
//            break;
//        }
//        //Logger.logDebug("GPSTracker onStatusChanged - provider " + provider + " new status " + newStatus);
    }
}