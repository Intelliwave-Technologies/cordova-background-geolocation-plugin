package com.marianhello.bgloc;

import android.Manifest;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;

import androidx.core.app.ActivityCompat;
import androidx.core.app.NotificationCompat;
import androidx.core.app.NotificationManagerCompat;

import com.marianhello.bgloc.sync.NotificationHelper;

public class AppStoppedAlarmReceiver extends BroadcastReceiver {
	@Override
	public void onReceive(Context context, Intent intent) {
		NotificationCompat.Builder builder = new NotificationCompat.Builder(context, NotificationHelper.SERVICE_CHANNEL_ID)
			.setSmallIcon(android.R.drawable.ic_dialog_alert)
			.setContentTitle("SiteSense - Background Geolocation Notification")
			.setContentText("App has been terminated due to out of memory or closed by user. Background BLE scanning is not active or active with restricted performance. Tap here to wake up the app and resume normal scanning.")
			.setPriority(NotificationCompat.PRIORITY_DEFAULT);

		NotificationManagerCompat notificationManager = NotificationManagerCompat.from(context);

		if (ActivityCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
			return;
		}

		notificationManager.notify(100, builder.build());
	}
}
