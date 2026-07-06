import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'task_handler.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterForegroundTask.initCommunicationPort();
  runApp(const TrackerApp());
}

class TrackerApp extends StatelessWidget {
  const TrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Field Tracker',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF4D8DFF)),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _nameCtrl = TextEditingController();
  final _urlCtrl = TextEditingController();
  final _keyCtrl = TextEditingController();

  SharedPreferences? _prefs;
  bool _tracking = false;
  int _intervalSec = 60;
  String _lastStatus = '—';

  bool _permLocationAlways = false;
  bool _permNotification = false;
  bool _permBattery = false;

  @override
  void initState() {
    super.initState();
    FlutterForegroundTask.addTaskDataCallback(_onTaskData);
    _load();
  }

  @override
  void dispose() {
    FlutterForegroundTask.removeTaskDataCallback(_onTaskData);
    _nameCtrl.dispose();
    _urlCtrl.dispose();
    _keyCtrl.dispose();
    super.dispose();
  }

  void _onTaskData(Object data) {
    if (data is Map && mounted) {
      setState(() {
        _lastStatus = (data['lastStatus'] ?? _lastStatus).toString();
      });
    }
  }

  Future<void> _load() async {
    _prefs = await SharedPreferences.getInstance();

    // First run: generate a permanent device id for this phone.
    if (_prefs!.getString(PrefKeys.deviceId) == null) {
      final r = Random();
      final id = List.generate(12, (_) => r.nextInt(16).toRadixString(16)).join();
      await _prefs!.setString(PrefKeys.deviceId, 'dev-$id');
    }

    _nameCtrl.text = _prefs!.getString(PrefKeys.staffName) ?? '';
    _urlCtrl.text = _prefs!.getString(PrefKeys.serverUrl) ?? '';
    _keyCtrl.text = _prefs!.getString(PrefKeys.apiKey) ?? '';
    _intervalSec = _prefs!.getInt(PrefKeys.intervalSec) ?? 60;
    _tracking = await FlutterForegroundTask.isRunningService;

    await _refreshPermissions();
    if (mounted) setState(() {});
  }

  Future<void> _refreshPermissions() async {
    final loc = await Geolocator.checkPermission();
    _permLocationAlways = loc == LocationPermission.always;
    _permNotification = await FlutterForegroundTask.checkNotificationPermission() ==
        NotificationPermission.granted;
    _permBattery = await FlutterForegroundTask.isIgnoringBatteryOptimizations;
    if (mounted) setState(() {});
  }

  Future<void> _saveSettings() async {
    await _prefs!.setString(PrefKeys.staffName, _nameCtrl.text.trim());
    await _prefs!.setString(PrefKeys.serverUrl, _urlCtrl.text.trim());
    await _prefs!.setString(PrefKeys.apiKey, _keyCtrl.text.trim());
    await _prefs!.setInt(PrefKeys.intervalSec, _intervalSec);
  }

  Future<void> _requestLocation() async {
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) {
      p = await Geolocator.requestPermission();
    }
    if (p == LocationPermission.deniedForever) {
      await Geolocator.openAppSettings();
    } else if (p == LocationPermission.whileInUse) {
      // Android 11+: "Allow all the time" can only be chosen in settings.
      _snack('In settings, open Permissions → Location → "Allow all the time"');
      await Geolocator.openAppSettings();
    }
    await _refreshPermissions();
  }

  Future<void> _requestNotification() async {
    await FlutterForegroundTask.requestNotificationPermission();
    await _refreshPermissions();
  }

  Future<void> _requestBattery() async {
    await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    await _refreshPermissions();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 4)));
  }

  Future<void> _toggleTracking(bool on) async {
    if (!on) {
      await FlutterForegroundTask.stopService();
      setState(() => _tracking = false);
      return;
    }

    if (_nameCtrl.text.trim().isEmpty ||
        _urlCtrl.text.trim().isEmpty ||
        _keyCtrl.text.trim().isEmpty) {
      _snack('Fill in name, server URL and API key first');
      return;
    }
    await _saveSettings();
    await _refreshPermissions();
    if (!_permLocationAlways) {
      _snack('Location must be set to "Allow all the time" first');
      return;
    }

    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'location_tracking',
        channelName: 'Location tracking',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(_intervalSec * 1000),
        autoRunOnBoot: true,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );

    final result = await FlutterForegroundTask.startService(
      serviceId: 300,
      notificationTitle: 'Tracking ON — ${_nameCtrl.text.trim()}',
      notificationText: 'Starting…',
      callback: startCallback,
    );
    if (result is ServiceRequestSuccess) {
      setState(() => _tracking = true);
    } else {
      _snack('Could not start tracking service: $result');
    }
  }

  @override
  Widget build(BuildContext context) {
    final allPermsOk = _permLocationAlways && _permNotification && _permBattery;
    return Scaffold(
      appBar: AppBar(title: const Text('Field Tracker')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ---- big toggle ----
          Card(
            color: _tracking
                ? Colors.green.shade50
                : Theme.of(context).colorScheme.surfaceContainerHighest,
            child: SwitchListTile(
              title: Text(_tracking ? 'Tracking is ON' : 'Tracking is OFF',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(_tracking ? _lastStatus : 'Your location is not shared'),
              value: _tracking,
              onChanged: _toggleTracking,
            ),
          ),
          const SizedBox(height: 20),

          // ---- settings ----
          Text('Settings', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          TextField(
            controller: _nameCtrl,
            enabled: !_tracking,
            decoration: const InputDecoration(
                labelText: 'Your name', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _urlCtrl,
            enabled: !_tracking,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
                labelText: 'Server URL',
                hintText: 'http://192.168.1.10:8090',
                border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _keyCtrl,
            enabled: !_tracking,
            obscureText: true,
            decoration: const InputDecoration(
                labelText: 'API key', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            initialValue: _intervalSec,
            decoration: const InputDecoration(
                labelText: 'Update every', border: OutlineInputBorder()),
            items: const [
              DropdownMenuItem(value: 30, child: Text('30 seconds')),
              DropdownMenuItem(value: 60, child: Text('1 minute')),
              DropdownMenuItem(value: 120, child: Text('2 minutes')),
              DropdownMenuItem(value: 300, child: Text('5 minutes')),
            ],
            onChanged: _tracking ? null : (v) => setState(() => _intervalSec = v ?? 60),
          ),
          const SizedBox(height: 20),

          // ---- permission checklist ----
          Text('Permissions (one-time setup)',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          _permTile(
            ok: _permLocationAlways,
            title: 'Location — "Allow all the time"',
            onFix: _requestLocation,
          ),
          _permTile(
            ok: _permNotification,
            title: 'Notifications',
            onFix: _requestNotification,
          ),
          _permTile(
            ok: _permBattery,
            title: 'Battery — no restrictions',
            onFix: _requestBattery,
          ),
          if (!allPermsOk)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'On Xiaomi / Oppo / Vivo / Realme phones also enable '
                '"Autostart" for this app in phone settings, otherwise the '
                'phone will kill tracking in the background.',
                style: TextStyle(fontSize: 12, color: Colors.orange),
              ),
            ),
        ],
      ),
    );
  }

  Widget _permTile({required bool ok, required String title, required VoidCallback onFix}) {
    return Card(
      child: ListTile(
        leading: Icon(ok ? Icons.check_circle : Icons.error_outline,
            color: ok ? Colors.green : Colors.orange),
        title: Text(title, style: const TextStyle(fontSize: 14)),
        trailing: ok ? null : TextButton(onPressed: onFix, child: const Text('Fix')),
      ),
    );
  }
}
