import 'dart:async';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Something the user did in the foreground notification.
enum ForegroundAction { stop }

/// Keeps the app process alive (Android foreground service, type location) while a run is recorded.
/// GPS fixes are collected by the main isolate; this service only holds the process and the notification.
abstract class ForegroundService {
  Future<void> start();
  Future<void> updateText(String text);
  Future<void> stop();

  /// Stops a service left over from a previous process, if one is running.
  Future<void> stopIfRunning();

  /// Taps on the notification's buttons (currently only Stop).
  Stream<ForegroundAction> get actions;
}

const String _stopButtonId = 'looprun_stop';
const String _stopMessage = 'looprun_stop';

const List<NotificationButton> _buttons = [
  NotificationButton(id: _stopButtonId, text: 'Stop'),
];

/// Call once from main() before runApp.
void initForegroundTask() {
  // Lets the service isolate send data (the Stop button) to the main isolate.
  FlutterForegroundTask.initCommunicationPort();
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
      // The recorder lives in the main isolate, so a restarted empty service would be useless.
      allowAutoRestart: false,
      stopWithTask: true,
    ),
  );
}

/// Entry point of the service isolate. Must stay top level.
@pragma('vm:entry-point')
void looprunServiceCallback() {
  FlutterForegroundTask.setTaskHandler(LooprunTaskHandler());
}

/// Does no recording: location is read in the main isolate. It only forwards the Stop button press.
class LooprunTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}

  @override
  void onNotificationButtonPressed(String id) {
    if (id == _stopButtonId) {
      FlutterForegroundTask.sendDataToMain(_stopMessage);
    }
  }
}

class AndroidForegroundService implements ForegroundService {
  final StreamController<ForegroundAction> _actions =
      StreamController<ForegroundAction>.broadcast();
  bool _listening = false;

  void _onTaskData(Object data) {
    if (data == _stopMessage) _actions.add(ForegroundAction.stop);
  }

  @override
  Stream<ForegroundAction> get actions {
    if (!_listening) {
      _listening = true;
      FlutterForegroundTask.addTaskDataCallback(_onTaskData);
    }
    return _actions.stream;
  }

  @override
  Future<void> start() async {
    if (await FlutterForegroundTask.isRunningService) return;
    final result = await FlutterForegroundTask.startService(
      serviceId: 4711,
      serviceTypes: [ForegroundServiceTypes.location],
      notificationTitle: 'Looprun',
      notificationText: 'Recording your run',
      notificationButtons: _buttons,
      callback: looprunServiceCallback,
    );
    if (result is ServiceRequestFailure) {
      throw StateError('Could not start the recording service: ${result.error}');
    }
  }

  @override
  Future<void> updateText(String text) async {
    if (!await FlutterForegroundTask.isRunningService) return;
    await FlutterForegroundTask.updateService(
      notificationTitle: 'Looprun',
      notificationText: text,
      notificationButtons: _buttons,
    );
  }

  @override
  Future<void> stop() async {
    await FlutterForegroundTask.stopService();
  }

  @override
  Future<void> stopIfRunning() async {
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
    }
  }
}
