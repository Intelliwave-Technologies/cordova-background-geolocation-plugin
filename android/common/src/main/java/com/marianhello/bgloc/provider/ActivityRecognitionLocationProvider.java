package com.marianhello.bgloc.provider;

import android.content.Context;
import android.location.Location;
import android.os.Bundle;
import android.os.Handler;
import android.util.Log;

import com.google.android.gms.common.ConnectionResult;
import com.google.android.gms.common.api.GoogleApiClient;
import com.google.android.gms.location.ActivityRecognition;
import com.google.android.gms.location.LocationListener;
import com.google.android.gms.location.LocationRequest;
import com.google.android.gms.location.LocationServices;
import com.marianhello.bgloc.Config;

// TODO: No longer the ActivityRecognitionProvider, should rename later, too risky now.
public class ActivityRecognitionLocationProvider extends AbstractLocationProvider implements GoogleApiClient.ConnectionCallbacks,
        GoogleApiClient.OnConnectionFailedListener, LocationListener {

    private static final String TAG = ActivityRecognitionLocationProvider.class.getSimpleName();
    private static final int LOCATION_SCAN_TIME = 5000;
    private GoogleApiClient googleApiClient;

    private boolean isStarted = true;
    private boolean isTracking = false;

    // Initialize default scan intervals, these are updated by onConfigure().
    private int SCAN_INTERVAL = 60000; // 60 seconds
	private int INTERVAL_BETWEEN_SCANS = 60000; // 60 seconds

	// Pretends to be a timer as timerHandler can post a delayed runnable.
	// Can repeat timer by reposting this handler at the end of the runnable.
	Handler resetScanTimerHandler = new Handler();
	Handler scanTimerHandler = new Handler();

    public ActivityRecognitionLocationProvider(Context context) {
        super(context);
        PROVIDER_ID = Config.ACTIVITY_PROVIDER;
    }

    @Override
    public void onCreate() {
        super.onCreate();
    }

    @Override
    public void onStart() {
        logger.info("Start recording");
        this.isStarted = true;
        attachRecorder();
        resetScanTimer();
    }

    @Override
    public void onStop() {
        logger.info("Stop recording");
        this.isStarted = false;
        stopTracking();

        resetScanTimerHandler.removeCallbacksAndMessages(null);
        scanTimerHandler.removeCallbacksAndMessages(null);
    }

    @Override
    public void onConfigure(Config config) {
        super.onConfigure(config);

        // intervalOfScan and intervalBetweenScans is provided in seconds, need to convert to
		// milliseconds for use with timers.
        SCAN_INTERVAL = config.getIntervalOfScan() * 1000;
        INTERVAL_BETWEEN_SCANS = config.getIntervalBetweenScans() * 1000;

        if (isStarted) {
            onStop();
            onStart();
        }
    }

	/**
	 * Wait for intervalBetweenScans and then aggressively poll location fixes
	 * for scanInterval. Repeat forever.
	 */
	public void resetScanTimer() {
		Runnable resetScanTimerRunnable = new Runnable() {
			@Override
			public void run() {
				startScan();
			}
		};

		resetScanTimerHandler.postDelayed(resetScanTimerRunnable, INTERVAL_BETWEEN_SCANS);
	}

	public void startScan() {
    	startTracking();
    	Log.d("LOCATION UPDATE", "Starting scan");

		Runnable scanTimerRunnable = new Runnable() {
			@Override
			public void run() {
				Log.d("LOCATION UPDATE", "Timer fired, stopping scan");
				stopTracking();
				resetScanTimer();
			}
		};

		scanTimerHandler.postDelayed(scanTimerRunnable, SCAN_INTERVAL);
	}

    @Override
    public boolean isStarted() {
        return isStarted;
    }

    @Override
    public void onLocationChanged(Location location) {
        logger.debug("Location change: {}", location.toString());
        showDebugToast("acy:" + location.getAccuracy() + ",v:" + location.getSpeed());
        handleLocation(location);
    }

    public void startTracking() {
        if (isTracking) { return; }

		// Skip scan cycle if googleApiClient is still setting up.
		if (!googleApiClient.isConnected()) {
			Log.e(TAG, "GoogleApiClient has not been initialized, skipping scan cycle");
			return;
		}

        Integer priority = translateDesiredAccuracy(mConfig.getDesiredAccuracy());
        LocationRequest locationRequest = LocationRequest.create()
                .setPriority(priority) // this.accuracy
                .setFastestInterval(LOCATION_SCAN_TIME)
                .setInterval(LOCATION_SCAN_TIME);

        try {
            LocationServices.FusedLocationApi.requestLocationUpdates(googleApiClient, locationRequest, this);
            isTracking = true;
            logger.debug("Start tracking with priority={} fastestInterval={} interval={} activitiesInterval={} stopOnStillActivity={}",
				priority,
				mConfig.getFastestInterval(),
				mConfig.getInterval(),
				mConfig.getActivitiesInterval(),
				mConfig.getStopOnStillActivity());

        } catch (SecurityException e) {
            logger.error("Security exception: {}", e.getMessage());
            this.handleSecurityException(e);
        }
    }

    public void stopTracking() {
        if (!isTracking) { return; }

        LocationServices.FusedLocationApi.removeLocationUpdates(googleApiClient, this);
        isTracking = false;
    }

    private void connectToPlayAPI() {
        logger.debug("Connecting to Google Play Services");
        googleApiClient =  new GoogleApiClient.Builder(mContext)
                .addApi(LocationServices.API)
                .addApi(ActivityRecognition.API)
                .addConnectionCallbacks(this)
                .addOnConnectionFailedListener(this)
                .build();
        googleApiClient.connect();
    }

    private void disconnectFromPlayAPI() {
        if (googleApiClient != null && googleApiClient.isConnected()) {
            googleApiClient.disconnect();
        }
    }

    private void attachRecorder() {
        if (googleApiClient == null) {
            connectToPlayAPI();
        } else {
            googleApiClient.connect();
        }
    }

    @Override
    public void onConnected(Bundle connectionHint) {
        logger.debug("Connected to Google Play Services");
        if (this.isStarted) {
            attachRecorder();
        }
    }

    @Override
    public void onConnectionSuspended(int cause) {
        // googleApiClient.connect();
        Log.e(TAG, "Connection to Google Play Services suspended: " + cause);
    }

    @Override
    public void onConnectionFailed(ConnectionResult connectionResult) {
        Log.e(TAG, "Connection to Google Play Services failed " + connectionResult);
    }

    /**
     * Translates a number representing desired accuracy of Geolocation system from set [0, 10, 100, 1000].
     * 0:  most aggressive, most accurate, worst battery drain
     * 1000:  least aggressive, least accurate, best for battery.
     */
    private Integer translateDesiredAccuracy(Integer accuracy) {
        if (accuracy >= 10000) {
            return LocationRequest.PRIORITY_NO_POWER;
        }
        if (accuracy >= 1000) {
            return LocationRequest.PRIORITY_LOW_POWER;
        }
        if (accuracy >= 100) {
            return LocationRequest.PRIORITY_BALANCED_POWER_ACCURACY;
        }
        if (accuracy >= 10) {
            return LocationRequest.PRIORITY_HIGH_ACCURACY;
        }
        if (accuracy >= 0) {
            return LocationRequest.PRIORITY_HIGH_ACCURACY;
        }

        return LocationRequest.PRIORITY_BALANCED_POWER_ACCURACY;
    }

    @Override
    public void onDestroy() {
        logger.info("Destroying ActivityRecognitionLocationProvider");
        onStop();
        disconnectFromPlayAPI();
        super.onDestroy();
    }
}
