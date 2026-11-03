import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Keeps the app process alive (Android foreground service, type location) while a run is recorded.
/// GPS fixes are collected by the main isolate; this service only holds the process and the notification.
abstract class RunService {
  Future<void> start();
  Future<void> updateText(String text);
  Future<void> stop();
}

/// Call once from main() before runApp.
void initForegroundTask() {
  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: 'looprun_recording',
      channelName: 'Run recording',
      channelDescription: 'Shown while Looprun records a run.',
      channelImportance: NotificationChannelImportance.LOW,
      priority: NotificationPriority.LOW,
    ),
    iosNotificationOptions: const IOSNotificationOptions(
      showNotification: false,
      playSound: false,
    ),
    foregroundTaskOptions: ForegroundTaskOptions(
      eventAction: ForegroundTaskEventAction.nothing(),
      autoRunOnBoot: false,
      allowWakeLock: true,
      allowWifiLock: false,
    ),
  );
}

/// Entry point of the service isolate. Must stay top level.
@pragma('vm:entry-point')
void looprunServiceCallback() {
  FlutterForegroundTask.setTaskHandler(LooprunTaskHandler());
}

/// Does no work: location is read in the main isolate. It exists because the plugin requires a handler.
class LooprunTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp) async {}
}

class AndroidRunService implements RunService {
  @override
  Future<void> start() async {
    if (await FlutterForegroundTask.isRunningService) return;
    await FlutterForegroundTask.startService(
      serviceId: 4711,
      notificationTitle: 'Looprun',
      notificationText: 'Recording your run',
      callback: looprunServiceCallback,
    );
  }

  @override
  Future<void> updateText(String text) async {
    if (!await FlutterForegroundTask.isRunningService) return;
    await FlutterForegroundTask.updateService(
      notificationTitle: 'Looprun',
      notificationText: text,
    );
  }

  @override
  Future<void> stop() async {
    await FlutterForegroundTask.stopService();
  }
}
