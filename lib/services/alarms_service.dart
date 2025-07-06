
import 'dart:isolate';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive/hive.dart';
import 'package:nothing_clock/models/alarm.dart';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';

/// Service for managing alarms, including scheduling, saving,
/// and retrieving alarm data. This class leverages Hive for local
/// data storage and Android Alarm Manager for scheduling.
class AlarmsService {

  /// A cached list of alarms loaded from the local Hive box.
  List<Alarm>? _cachedAlarms;

  static const MethodChannel _channel = MethodChannel('exactAlarmChannel');

  static const Map<String, int> dayStringToWeekday = {
      "SUN": DateTime.sunday,
      "MON": DateTime.monday,
      "TUE": DateTime.tuesday,
      "WED": DateTime.wednesday,
      "THU": DateTime.thursday,
      "FRI": DateTime.friday,
      "SAT": DateTime.saturday,
    };

  /// Checks whether the device can schedule exact alarms.
  ///
  /// Returns `true` if exact alarms can be scheduled, otherwise `false`.
  /// In case of a platform exception, logs the error and returns `false`.
  Future<bool> canScheduleExactAlarms() async {
    try {
      final bool? result = await _channel.invokeMethod("canScheduleExactAlarms");
      return result ?? false;
    } on PlatformException catch (e) {
      debugPrint("Error checking if exact alarms can be scheduled: $e");
      return false;
    }
  } 

  /// Opens the device settings where the user can allow exact alarm scheduling.
  ///
  /// If an error occurs during invocation, the error is logged.
  static Future<void> openExactAlarmSettings() async {
    try {
      await _channel.invokeMethod("openExactAlarmSettings");
    } on PlatformException catch (e) {
      debugPrint("Error opening exact alarm settings: $e");
    }
  }


  /// Saves an [alarm] to the Hive box and updates the cached list of alarms.
  ///
  /// After adding the alarm to the box, the method appends it to [_cachedAlarms]
  /// if it exists, and then triggers a reload of alarms.
  Future<void> saveAlarmData(Alarm alarm) async {
    final box = await Hive.openBox<Alarm>('alarms');
    await box.add(alarm); 

    _cachedAlarms?.add(alarm);
    loadAlarms();
  }


  /// Returns the number of alarms currently cached.
  ///
  /// If no alarms are cached, returns 0.
  int getNumberOfAlarms() {
    return _cachedAlarms?.length ?? 0;
  }

  /// Loads alarms from the Hive box.
  ///
  /// If the alarms are already cached in [_cachedAlarms], returns the cached list.
  /// Otherwise, opens the Hive box, caches the values, and returns the list.
  Future<List<Alarm>> loadAlarms() async {
    if(_cachedAlarms != null) {
      return _cachedAlarms!;
    }

    final box = await Hive.openBox<Alarm>('alarms');
    _cachedAlarms = box.values.toList();
    return _cachedAlarms!;
  }


  /// Callback that is invoked when an alarm triggers.
  ///
  /// Currently, this method only logs a message, but you can extend it
  /// to perform more complex operations when an alarm fires.
  @pragma('vm:entry-point')
  static void alarmCallback() {
    // This code will run when the alarm triggers.
    debugPrint("Alarm triggered!");
    final SendPort? sendPort = IsolateNameServer.lookupPortByName("alarmPort");
    sendPort?.send("showNotification");
  }

  /// Schedules an alarm to trigger at a specific [alarm.time].
  ///
  /// Uses the Android Alarm Manager to schedule the alarm with the given [Alarm]
  /// object. The alarm is set as exact and will wake up the device if necessary.
  Future<void> scheduleAlarmAt(Alarm alarm) async {
    alarm.days.forEach((dayKey, isActive) async {
      if(isActive) {
        final targetWeekday = dayStringToWeekday[dayKey];
        if(targetWeekday != null) {
          final nextOccourance = _getNextOccurrence(alarm.time, targetWeekday);
          final int truncatedAlarmId = alarm.id & ((1 << 28) - 1);
          final int id = (((truncatedAlarmId << 3) | (targetWeekday & 0x7)) & 0x7FFFFFFF);

          await AndroidAlarmManager.oneShotAt(nextOccourance, id, alarmCallback, exact: true, wakeup: true);
          debugPrint("Scheduled alarm for ${alarm.time} on ${nextOccourance.weekday}");
        }
      }
    });
  }

  Future<void> cancelAlarm(Alarm alarm) async {
    alarm.days.forEach((dayKey, isActive) async {
      if(isActive) {
        final targetWeekday = dayStringToWeekday[dayKey];
        if(targetWeekday != null) {
          final int truncatedAlarmId = alarm.id & ((1 << 28) - 1);
          final int id = (((truncatedAlarmId << 3) | (targetWeekday & 0x7)) & 0xFFFFFFFF);

          await AndroidAlarmManager.cancel(id);
          debugPrint("Canceled alarm for ${alarm.time} on ${targetWeekday}");
        }
      }
    });
  }

  DateTime _getNextOccurrence(DateTime alarmTime, int targetDay) {
    final now = DateTime.now();

    DateTime scheduled = DateTime(now.year, now.month, now.day, alarmTime.hour, alarmTime.minute);
    int daysToAdd = (targetDay - scheduled.weekday) % 7;

    if(daysToAdd == 0 && scheduled.isBefore(now)) {
      daysToAdd = 7;
    } else if(daysToAdd < 0) {
      daysToAdd += 7;
    }

    return scheduled.add(Duration(days: daysToAdd));
  }
}
