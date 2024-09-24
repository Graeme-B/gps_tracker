package com.moorwen.gps_tracker;

import android.location.GnssStatus;

public class GpsStatus extends GnssStatus.Callback {
    GpsTrackerService parent;

    public GpsStatus(GpsTrackerService parent) {
        this.parent = parent;
    }

    // Called when the GNSS system has received its first fix since starting.
    @Override
    public void onFirstFix(int ttffMillis) {
        parent.gpsFirstFix(ttffMillis);
        super.onFirstFix(ttffMillis);
    }

    // Called periodically to report GNSS satellite status.
    @Override
    public void onSatelliteStatusChanged(GnssStatus status) {
        parent.gpsSatelliteStatus(status);
        super.onSatelliteStatusChanged(status);
    }

    // Called when GNSS system has started.
    @Override
    public void onStarted() {
        parent.gpsStarted();
        super.onStarted();
    }

    // Called when GNSS system has stopped.
    @Override
    public void onStopped() {
        super.onStopped();
    }
}
