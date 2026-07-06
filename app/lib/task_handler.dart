import 'dart:convert';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Keys shared between the UI and the background task (via SharedPreferences).
class PrefKeys {
  static const serverUrl = 'server_url';
  static const apiKey = 'api_key';
  static const staffName = 'staff_name';
  static const deviceId = 'device_id';
  static const intervalSec = 'interval_sec';
  static const pingQueue = 'ping_queue';
}

@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(LocationTaskHandler());
}

class LocationTaskHandler extends TaskHandler {
  SharedPreferences? _prefs;
  final Battery _battery = Battery();

  String _serverUrl = '';
  String _apiKey = '';
  String _staffName = '';
  String _deviceId = '';

  /// Pings not yet accepted by the server (offline buffer).
  List<Map<String, dynamic>> _queue = [];
  static const int _maxQueue = 1000;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    _prefs = await SharedPreferences.getInstance();
    await _prefs!.reload();
    _serverUrl = (_prefs!.getString(PrefKeys.serverUrl) ?? '').trim();
    if (_serverUrl.endsWith('/')) {
      _serverUrl = _serverUrl.substring(0, _serverUrl.length - 1);
    }
    _apiKey = _prefs!.getString(PrefKeys.apiKey) ?? '';
    _staffName = _prefs!.getString(PrefKeys.staffName) ?? 'Unknown';
    _deviceId = _prefs!.getString(PrefKeys.deviceId) ?? 'unknown-device';

    final saved = _prefs!.getString(PrefKeys.pingQueue);
    if (saved != null) {
      try {
        _queue = (jsonDecode(saved) as List).cast<Map<String, dynamic>>();
      } catch (_) {
        _queue = [];
      }
    }
  }

  @override
  void onRepeatEvent(DateTime timestamp) async {
    try {
      final ping = await _capturePing();
      if (ping != null) {
        _queue.add(ping);
        if (_queue.length > _maxQueue) {
          _queue.removeRange(0, _queue.length - _maxQueue);
        }
      }

      final sent = await _flushQueue();
      await _persistQueue();

      final now = DateTime.now();
      final hh = now.hour.toString().padLeft(2, '0');
      final mm = now.minute.toString().padLeft(2, '0');
      final status = sent
          ? 'Last sent $hh:$mm'
          : 'Offline — ${_queue.length} saved, will retry';
      FlutterForegroundTask.updateService(
        notificationTitle: 'Tracking ON — $_staffName',
        notificationText: status,
      );
      FlutterForegroundTask.sendDataToMain({
        'lastStatus': status,
        'queue': _queue.length,
      });
    } catch (e) {
      FlutterForegroundTask.sendDataToMain({'lastStatus': 'Error: $e'});
    }
  }

  Future<Map<String, dynamic>?> _capturePing() async {
    Position? pos;
    try {
      pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 25),
        ),
      );
    } catch (_) {
      pos = await Geolocator.getLastKnownPosition();
    }
    if (pos == null) return null;

    int? batteryLevel;
    try {
      batteryLevel = await _battery.batteryLevel;
    } catch (_) {}

    return {
      'lat': pos.latitude,
      'lng': pos.longitude,
      'accuracy': pos.accuracy,
      'speed': pos.speed,
      'battery': batteryLevel,
      'recorded_at': DateTime.now().toUtc().toIso8601String(),
    };
  }

  /// Sends everything in the queue as one batch. Returns true on success.
  Future<bool> _flushQueue() async {
    if (_queue.isEmpty || _serverUrl.isEmpty) return false;
    try {
      final res = await http
          .post(
            Uri.parse('$_serverUrl/api/v1/pings'),
            headers: {
              'Content-Type': 'application/json',
              'X-API-Key': _apiKey,
            },
            body: jsonEncode({
              'device_id': _deviceId,
              'name': _staffName,
              'pings': _queue,
            }),
          )
          .timeout(const Duration(seconds: 20));
      if (res.statusCode == 200) {
        _queue.clear();
        return true;
      }
    } catch (_) {}
    return false;
  }

  Future<void> _persistQueue() async {
    await _prefs?.setString(PrefKeys.pingQueue, jsonEncode(_queue));
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {
    await _persistQueue();
  }
}
