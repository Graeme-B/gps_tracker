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
import android.content.Context;
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
import android.hardware.SensorEventListener;
import android.hardware.SensorManager;
import android.hardware.Sensor;
import android.hardware.SensorEvent;

import java.util.ArrayList;
import java.util.List;

import android.location.Location;
import android.location.LocationManager;
import android.util.Pair;

import androidx.core.app.NotificationCompat;

public class GpsTrackerService extends Service implements LocationListener, SensorEventListener// , GpsStatus.Listener
{
    private static final long MIN_DISTANCE_CHANGE_FOR_UPDATES = 1;    // 1 meter
    private static final long MIN_TIME_BW_UPDATES             = 1000; // 1 second
    private static final int  TIMER_TICK                      = 500;
    private static final int  REPORTING_INTERVAL              = 100;

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

    static final String ACCELEROMETER_UPDATE    = "com.moorwen.coursewalker.AccelerometerUpdate";
    static final String ACCELEROMETER_X         = "accelerometerX";
    static final String ACCELEROMETER_Y         = "accelerometerY";
    static final String ACCELEROMETER_Z         = "accelerometerZ";
    static final String ACCELEROMETER_TIMESTAMP = "accelerometerTimestamp";

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
    private final float[] accelerometerReading = new float[3];
    private final float[] magnetometerReading  = new float[3];
    private final float[] rotationMatrix       = new float[9];
    private final float[] orientationAngles    = new float[3];

    private long          mSensorTimeStamp = 0;
    private SensorManager mSensorManager   = null;
    private Sensor        mAccelerometer   = null;
    private Sensor        mMagneticField   = null;
    private Sensor        mRotationVector  = null;

    /*
     * Methods to get some of the internal variables
     */
    public double getDistance()           { return (distance); }
    public String getWalkName()           { return (walkName); }
    public int    getNumWalkTrackPoints() { return(walkTrack.size());}

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
        Log.d("GPSService", "Battery");

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

    @Override
    public int onStartCommand(Intent intent, int flags, int startId)
    {

        Log.d("GPSService", "OnStartCommand");
        if (intent.getAction().equals(GpsTrackerPlugin.STARTFOREGROUND_ACTION))
        {
            Log.d("GPSService", "Start");

            mNotifyManager = (NotificationManager) getApplicationContext().getSystemService(NOTIFICATION_SERVICE);
            mBuilder = new NotificationCompat.Builder(this, "MyChannelID");
            mBuilder.setContentTitle("My App")
                    .setContentText("Always running...")
                    .setTicker("Always running...")
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
                  startForeground(1, mBuilder.build(),FOREGROUND_SERVICE_TYPE_LOCATION);
            }
            else
            {
                mBuilder.setChannelId(NOTIFICATION_CHANNEL_ID);
                mNotifyManager.notify(1, mBuilder.build());
            }
//            timerHandler.postDelayed(timerRunnable, 0);
        }
        else if (intent.getAction().equals( GpsTrackerPlugin.STOPFOREGROUND_ACTION)) {
            Log.d("GPSService", "Stop");
            //your end service code
            if (tracking) stopTracking();
            if (mSensorManager != null) mSensorManager.unregisterListener(this);
            if (mNotifyManager != null) {
                mNotifyManager.cancelAll();
            }
            stopForeground(true);
            stopSelf();
        }

        return START_STICKY;
    }

    @Override
    public IBinder onBind(Intent intent)
    {
        return new LocalBinder();
    }

    /*
     * Called when we start tracking
     */
    public void startTracking(String walkName)
    {
        Log.d("GPSService", "startTracking - walk name " + walkName);
        paused        = false;
        distance      = 0.0;
        elapsedTime   = 0;
        prevTime      = System.currentTimeMillis();
        this.walkName = walkName;
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
        tracking = true;
        timerHandler.postDelayed(timerRunnable, 0);
    }

    /*
     * Called when we stop tracking
     */
    public void stopTracking()
    {
        Log.d("GPSService", "stopTracking");
        tracking = false;
        walkName = null;
        timerHandler.removeCallbacks(timerRunnable);
    }

    /*
     * Called to pause tracking
     */
    public void pauseTracking()
    {
        paused = true;
    }

    /*
     * Called to resume tracking
     */
    public void resumeTracking()
    {
        paused   = false;
    }

    /*
     * Broadcasts the new location
     */
    private void broadcastLocationChange()
    {
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
//        Log.d("GPSService", "sending broadcast");
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
     * Broadcast an accelerometer change message
     */
    private void broadcastAccelerometerChange()
    {
        Intent intent = new Intent();
        intent.setAction(ACCELEROMETER_UPDATE);
        intent.addFlags(Intent.FLAG_INCLUDE_STOPPED_PACKAGES);
        intent.putExtra(ACCELEROMETER_X,accelerometerReading[0]);
        intent.putExtra(ACCELEROMETER_Y,accelerometerReading[1]);
        intent.putExtra(ACCELEROMETER_Z,accelerometerReading[2]);
        intent.putExtra(ACCELEROMETER_TIMESTAMP,mSensorTimeStamp);
//        Log.d("GPSService","Broadcast accelerometer change");
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
        try
        {
            mSensorManager = (SensorManager) getApplicationContext().getSystemService(Context.SENSOR_SERVICE);

            mAccelerometer = mSensorManager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER);
            if (mAccelerometer != null) {
                mSensorManager.registerListener(this, mAccelerometer,
                        SensorManager.SENSOR_DELAY_NORMAL, SensorManager.SENSOR_DELAY_UI);
            }
            mRotationVector = mSensorManager.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR);
            if (mRotationVector != null) {
                mSensorManager.registerListener(this, mRotationVector,
                        SensorManager.SENSOR_DELAY_NORMAL, SensorManager.SENSOR_DELAY_UI);
            } else {
                mMagneticField = mSensorManager.getDefaultSensor(Sensor.TYPE_MAGNETIC_FIELD);
                if (mMagneticField != null) {
                    mSensorManager.registerListener(this, mMagneticField,
                            SensorManager.SENSOR_DELAY_NORMAL, SensorManager.SENSOR_DELAY_UI);
                }
            }

//            Log.d("GPSService", String.format("Accelerometer %s rotation %s orientation %s magnetometer %s",
//                    mSensorManager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER) == null ? "missing" : "present",
//                    mSensorManager.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR) == null ? "missing" : "present",
//                    mSensorManager.getDefaultSensor(Sensor.TYPE_ORIENTATION) == null ? "missing" : "present",
//                    mSensorManager.getDefaultSensor(Sensor.TYPE_MAGNETIC_FIELD) == null ? "missing" : "present"));

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
//            Log.d("GPSService", "onLocationChanged");

            if (location.getProvider().equals(LocationManager.GPS_PROVIDER))
            {
//                Log.d("GPSService", "onLocationChange");
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
                        distance += d;
                        walkTrack.add(new Pair<>(location.getLatitude(), location.getLongitude()));
                    }
                }
                broadcastLocationChange();
                currLocation = location;
            }
        }
        catch (SecurityException e)
        {
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
    }

    /*
     * Called when the GPS is enabled - tell anyone who's interested
     */
    @Override
    public void onProviderEnabled(String provider)
    {
    }

    /*
     * Called when the status changes - just log the event
     * NB - what's the difference between this and GPS status changed????
     */
    @Override
    public void onStatusChanged(String provider, int status, Bundle extras)
    {
    }

    @Override
    public void onSensorChanged(SensorEvent event) {
//        Log.d("GPSService", String.format("onSensorChanged - sensor %d", event.sensor.getType()));
        if (event.sensor.getType() == Sensor.TYPE_ACCELEROMETER) {
            System.arraycopy(event.values, 0, accelerometerReading,0, accelerometerReading.length);
            if (System.currentTimeMillis() - mSensorTimeStamp > REPORTING_INTERVAL) {
                mSensorTimeStamp = System.currentTimeMillis();
                Log.d("GPSService", String.format("Sensor changed.....time %d",mSensorTimeStamp));
            }

//// Rotation matrix based on current readings from accelerometer and magnetometer.
//            final float[] rotationMatrix = new float[9];
//            mSensorManager.getRotationMatrix(rotationMatrix, null,
//                    accelerometerReading, magnetometerReading);
//
//// Express the updated rotation matrix as three orientation angles.
//            final float[] orientationAngles = new float[3];


//            Log.d("GPSService", String.format("onSensorChanged - time %d x %3f y %3f z %3f",
//                    System.currentTimeMillis(), accelerometerReading[0], accelerometerReading[1], accelerometerReading[2]));
            broadcastAccelerometerChange();
        } else if (event.sensor.getType() == Sensor.TYPE_ROTATION_VECTOR) {
            System.arraycopy(event.values, 0, orientationAngles, 0, orientationAngles.length);
            // here i am
            // Also need to set up the interval!
            // Then calculate (for both) the new lat/lon based on the inertial navigation values
//            Log.d("GPSService", String.format("onSensorChanged - time %d yaw %3f pitch %3f roll %3f",
//                    System.currentTimeMillis(), orientationAngles[0], orientationAngles[2], orientationAngles[2]));
        } else if (event.sensor.getType() == Sensor.TYPE_MAGNETIC_FIELD) {
            System.arraycopy(event.values, 0, magnetometerReading, 0, magnetometerReading.length);
//            Log.d("GPSService", String.format("onSensorChanged - time %d magX %3f magY %3f magZ %3f",
//                    System.currentTimeMillis(), magnetometerReading[0], magnetometerReading[2], magnetometerReading[2]));
        }

    }

    // Compute the three orientation angles based on the most recent readings from
    // the device's accelerometer and magnetometer.
    public void updateOrientationAngles() {
        // Update rotation matrix, which is needed to update orientation angles.
        SensorManager.getRotationMatrix(rotationMatrix, null,
                accelerometerReading, magnetometerReading);

        // "rotationMatrix" now has up-to-date information.

        SensorManager.getOrientation(rotationMatrix, orientationAngles);

        // "orientationAngles" now has up-to-date information.
    }

    @Override
    public void onAccuracyChanged(Sensor sensor, int accuracy) {
    }
}

// - Get initial GPS fix
// - Set previous report time so we know we're tracking
// - When we get a sensor update, calcualte lat/long from IN values and broadcast location change
// - When we get a GPS fix, update lat/long and broadcast location change
// - Provider is set to IN or GPS
//
//static const double EARTH_RADIUS = 6378.137;
//
//// Pass in accel and magnetometer
//// Get out normalised acceleration vector
//// Rotation matrix based on current readings from accelerometer and magnetometer.
//            final float[] rotationMatrix = new float[9];
//            mSensorManager.getRotationMatrix(rotationMatrix, null,
//                    accelerometerReading, magnetometerReading);
// final float[] normalisedAccel = new float[3];
// normalisedAccl[0] = rotationMatrix[0]*accel[0] + rotationMatrix[1]*accel[1] + rotationMatrix[2]*accel[2];
// normalisedAccl[1] = rotationMatrix[3]*accel[0] + rotationMatrix[4]*accel[1] + rotationMatrix[5]*accel[2];
// normalisedAccl[2] = rotationMatrix[6]*accel[0] + rotationMatrix[7]*accel[1] + rotationMatrix[8]*accel[2];
//
//
//
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
//
//// Calculate distance travelled and final speed from acceleration, initial speed and time.
//// Acceleration is m/s**2
//// Speed is m/s
//// Time is in milliseconds
//// Output distance is in metres
//List<double> calculateDistanceAndSpeed(double accel, double initialSpeed, int time) {
//    var distanceAndSpeed = <double>[0.0,0.0];
//    double finalSpeed = initialSpeed + (accel*time)/1000.0;
//    distanceAndSpeed[0] = finalSpeed;
//    distanceAndSpeed[1] = (initialSpeed + finalSpeed)*0.5*(time/1000.0);
//
//    return distanceAndSpeed;
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
