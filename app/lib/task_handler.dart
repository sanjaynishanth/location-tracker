import 'dart:async';
import 'dart:convert';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Default backend (staff never need to type this).
const String defaultServerUrl = 'https://field-tracker-984u.onrender.com';

/// Keys shared between the UI and the background task via SharedPreferences.
class PrefKeys {
  static const serverUrl = 'server_url';
  static const token = 'auth_token';
  static const email = 'account_email';
  static const name = 'staff_name';
  static const deviceId = 'device_id';
  static const intervalSec = 'interval_sec';
  static const pingQueue = 'ping_queue';
  static const pwSalt = 'pw_salt';
  static const pwHash = 'pw_hash';
  static const adminRemovedFlag = 'admin_removed_flag';
}

@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(LocationTaskHandler());
}

class LocationTaskHandler extends TaskHandler {
  SharedPreferences? _prefs;
  final Battery _battery = Battery();

  String _serverUrl = '';
  String _token = '';
  String _name = '';
  String _deviceId = '';

  // Continuous GPS stream keeps a live fix instead of cold one-shot reads.
  StreamSubscription<Position>? _posSub;
  Position? _latest;
  int _lastBattery = -1;
  int _movedSinceFlush = 0;

  List<Map<String, dynamic>> _queue = [];
  static const int _maxQueue = 2000;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    _prefs = await SharedPreferences.getInstance();
    await _prefs!.reload();
    _serverUrl = (_prefs!.getString(PrefKeys.serverUrl) ?? defaultServerUrl).trim();
    if (_serverUrl.endsWith('/')) {
      _serverUrl = _serverUrl.substring(0, _serverUrl.length - 1);
    }
    _token = _prefs!.getString(PrefKeys.token) ?? '';
    _name = _prefs!.getString(PrefKeys.name) ?? 'Staff';
    _deviceId = _prefs!.getString(PrefKeys.deviceId) ?? 'unknown-device';

    final saved = _prefs!.getString(PrefKeys.pingQueue);
    if (saved != null) {
      try {
        _queue = (jsonDecode(saved) as List).cast<Map<String, dynamic>>();
      } catch (_) {
        _queue = [];
      }
    }

    _startLocationStream();
  }

  void _startLocationStream() {
    _posSub?.cancel();
    try {
      _posSub = Geolocator.getPositionStream(
        // Emit a fresh fix every ~20 m of real movement. This makes the
        // recorded trail hug the road instead of cutting straight lines
        // between sparse once-a-minute points.
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: 20,
        ),
      ).listen(
        (p) {
          _latest = p;
          _enqueuePoint(p);
          _movedSinceFlush++;
        },
        onError: (_) {},
        cancelOnError: false,
      );
    } catch (_) {}
  }

  void _enqueuePoint(Position p) {
    _queue.add({
      'lat': p.latitude,
      'lng': p.longitude,
      'accuracy': p.accuracy,
      'speed': p.speed,
      'battery': _lastBattery >= 0 ? _lastBattery : null,
      'recorded_at': DateTime.now().toUtc().toIso8601String(),
    });
    if (_queue.length > _maxQueue) {
      _queue.removeRange(0, _queue.length - _maxQueue);
    }
  }

  @override
  void onRepeatEvent(DateTime timestamp) async {
    try {
      try {
        _lastBattery = await _battery.batteryLevel;
      } catch (_) {}

      // Make sure the stream is alive.
      if (_posSub == null) _startLocationStream();

      // Seed a fix if the stream hasn't produced one yet.
      if (_latest == null) {
        try {
          _latest = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              timeLimit: Duration(seconds: 20),
            ),
          );
        } catch (_) {}
      }

      // If the phone was stationary (no movement points this interval), record
      // one heartbeat so the dashboard still shows the person online.
      if (_movedSinceFlush == 0 && _latest != null) {
        _enqueuePoint(_latest!);
      }
      _movedSinceFlush = 0;

      final sent = await _flushQueue();
      await _persistQueue();

      final now = DateTime.now();
      final hh = now.hour.toString().padLeft(2, '0');
      final mm = now.minute.toString().padLeft(2, '0');
      final String status;
      if (_latest == null) {
        status = 'No GPS signal - is Location (GPS) ON?';
      } else if (sent) {
        status = 'Last sent $hh:$mm';
      } else {
        status = 'Offline - ${_queue.length} saved, will retry';
      }
      FlutterForegroundTask.updateService(
        notificationTitle: 'Tracking ON - $_name',
        notificationText: status,
      );
      FlutterForegroundTask.sendDataToMain({'lastStatus': status});
    } catch (e) {
      FlutterForegroundTask.sendDataToMain({'lastStatus': 'Error: $e'});
    }
  }

  Future<bool> _flushQueue() async {
    if (_queue.isEmpty || _serverUrl.isEmpty || _token.isEmpty) return false;
    try {
      final res = await http
          .post(
            Uri.parse('$_serverUrl/api/v1/pings'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $_token',
            },
            body: jsonEncode({
              'device_id': _deviceId,
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
    await _posSub?.cancel();
    _posSub = null;
    await _persistQueue();
  }
}
