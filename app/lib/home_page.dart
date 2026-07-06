import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth.dart';
import 'device_admin.dart';
import 'login_page.dart';
import 'task_handler.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  final _urlCtrl = TextEditingController();

  SharedPreferences? _prefs;
  String _name = 'Staff';
  bool _tracking = false;
  int _intervalSec = 60;
  String _lastStatus = '-';
  bool _showAdvanced = false;

  bool _permLocationAlways = false;
  bool _permNotification = false;
  bool _permBattery = false;
  bool _permDeviceAdmin = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    FlutterForegroundTask.addTaskDataCallback(_onTaskData);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    FlutterForegroundTask.removeTaskDataCallback(_onTaskData);
    _urlCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkAdminRemoved();
      _refreshPermissions();
    }
  }

  void _onTaskData(Object data) {
    if (data is Map && mounted) {
      setState(() => _lastStatus = (data['lastStatus'] ?? _lastStatus).toString());
    }
  }

  Future<void> _load() async {
    _prefs = await SharedPreferences.getInstance();
    _name = _prefs!.getString(PrefKeys.name) ?? 'Staff';
    _urlCtrl.text = _prefs!.getString(PrefKeys.serverUrl) ?? defaultServerUrl;
    _intervalSec = _prefs!.getInt(PrefKeys.intervalSec) ?? 60;
    _tracking = await FlutterForegroundTask.isRunningService;
    await _checkAdminRemoved();
    await _refreshPermissions();
    if (mounted) setState(() {});
  }

  /// The native admin receiver flags this when protection was removed.
  Future<void> _checkAdminRemoved() async {
    await _prefs?.reload();
    if (_prefs?.getBool(PrefKeys.adminRemovedFlag) == true) {
      await _prefs?.setBool(PrefKeys.adminRemovedFlag, false);
      Auth.sendEvent('admin_removed', detail: 'Device admin protection was removed');
    }
  }

  Future<void> _refreshPermissions() async {
    final loc = await Geolocator.checkPermission();
    _permLocationAlways = loc == LocationPermission.always;
    _permNotification =
        await FlutterForegroundTask.checkNotificationPermission() == NotificationPermission.granted;
    _permBattery = await FlutterForegroundTask.isIgnoringBatteryOptimizations;
    _permDeviceAdmin = await DeviceAdmin.isActive();
    if (mounted) setState(() {});
  }

  Future<void> _requestLocation() async {
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
    if (p == LocationPermission.deniedForever) {
      await Geolocator.openAppSettings();
    } else if (p == LocationPermission.whileInUse) {
      _snack('In settings, open Permissions > Location > "Allow all the time"');
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

  Future<void> _requestDeviceAdmin() async {
    await DeviceAdmin.request();
    // The system screen returns via lifecycle resume; refresh happens there too.
    await _refreshPermissions();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 4)));
  }

  Future<void> _onToggle(bool on) async {
    if (on) {
      await _startTracking();
    } else {
      await _promptStop();
    }
  }

  Future<void> _startTracking() async {
    await _prefs!.setInt(PrefKeys.intervalSec, _intervalSec);
    await _prefs!.setString(
        PrefKeys.serverUrl, _urlCtrl.text.trim().isEmpty ? defaultServerUrl : _urlCtrl.text.trim());
    await _refreshPermissions();
    if (!_permLocationAlways) {
      _snack('Turn on Location "Allow all the time" first');
      return;
    }
    if (!await Geolocator.isLocationServiceEnabled()) {
      _snack('Turn ON Location (GPS) in your phone settings, then try again');
      await Geolocator.openLocationSettings();
      return;
    }

    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'location_tracking',
        channelName: 'Location tracking',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.MIN,
      ),
      iosNotificationOptions: const IOSNotificationOptions(showNotification: true, playSound: false),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(_intervalSec * 1000),
        autoRunOnBoot: true,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );

    final result = await FlutterForegroundTask.startService(
      serviceId: 300,
      notificationTitle: 'Tracking ON - $_name',
      notificationText: 'Starting...',
      callback: startCallback,
    );
    if (result is ServiceRequestSuccess) {
      Auth.sendEvent('tracking_on');
      setState(() => _tracking = true);
    } else {
      _snack('Could not start tracking: $result');
    }
  }

  Future<void> _promptStop() async {
    final ctrl = TextEditingController();
    String? err;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Turn tracking off?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Enter your account password to stop tracking.'),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'Password',
                  border: const OutlineInputBorder(),
                  errorText: err,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                final nav = Navigator.of(ctx);
                final ok = await Auth.checkLocalPassword(ctrl.text);
                if (ok) {
                  nav.pop(true);
                } else {
                  setLocal(() => err = 'Wrong password');
                }
              },
              child: const Text('Turn off'),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true) {
      await Auth.sendEvent('tracking_off', detail: 'Turned off in app');
      await FlutterForegroundTask.stopService();
      if (mounted) setState(() => _tracking = false);
    }
  }

  Future<void> _signOut() async {
    if (_tracking) {
      _snack('Turn tracking off before signing out');
      return;
    }
    await Auth.logout();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const LoginPage()));
  }

  @override
  Widget build(BuildContext context) {
    final allCore = _permLocationAlways && _permNotification && _permBattery;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Field Tracker'),
        actions: [
          IconButton(
            onPressed: _signOut,
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Signed in as $_name',
              style: TextStyle(color: Theme.of(context).hintColor, fontSize: 13)),
          const SizedBox(height: 10),

          Card(
            color: _tracking
                ? Colors.green.shade50
                : Theme.of(context).colorScheme.surfaceContainerHighest,
            child: SwitchListTile(
              title: Text(_tracking ? 'Tracking is ON' : 'Tracking is OFF',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              subtitle: Text(_tracking ? _lastStatus : 'Your location is not shared'),
              value: _tracking,
              onChanged: _onToggle,
            ),
          ),
          const SizedBox(height: 20),

          Text('Permissions (one-time setup)', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          _permTile(
            ok: _permLocationAlways,
            title: 'Location - "Allow all the time"',
            subtitle: 'Also turn ON "Use precise location"',
            onFix: _requestLocation,
          ),
          _permTile(ok: _permNotification, title: 'Notifications', onFix: _requestNotification),
          _permTile(ok: _permBattery, title: 'Battery - no restrictions', onFix: _requestBattery),
          _permTile(
            ok: _permDeviceAdmin,
            title: 'Uninstall protection',
            subtitle: 'Stops the app being removed without your password',
            onFix: _requestDeviceAdmin,
          ),
          if (!allCore)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'On Xiaomi / Oppo / Vivo / Realme phones also enable "Autostart" for this app '
                'in phone settings, or the phone will kill tracking in the background.',
                style: TextStyle(fontSize: 12, color: Colors.orange),
              ),
            ),

          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Settings', style: Theme.of(context).textTheme.titleMedium),
              TextButton(
                onPressed: () => setState(() => _showAdvanced = !_showAdvanced),
                child: Text(_showAdvanced ? 'Hide' : 'Advanced'),
              ),
            ],
          ),
          DropdownButtonFormField<int>(
            initialValue: _intervalSec,
            decoration:
                const InputDecoration(labelText: 'Update every', border: OutlineInputBorder()),
            items: const [
              DropdownMenuItem(value: 30, child: Text('30 seconds')),
              DropdownMenuItem(value: 60, child: Text('1 minute')),
              DropdownMenuItem(value: 120, child: Text('2 minutes')),
              DropdownMenuItem(value: 300, child: Text('5 minutes')),
            ],
            onChanged: _tracking ? null : (v) => setState(() => _intervalSec = v ?? 60),
          ),
          if (_showAdvanced) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _urlCtrl,
              enabled: !_tracking,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                  labelText: 'Server URL', border: OutlineInputBorder()),
            ),
          ],
        ],
      ),
    );
  }

  Widget _permTile({
    required bool ok,
    required String title,
    String? subtitle,
    required VoidCallback onFix,
  }) {
    return Card(
      child: ListTile(
        leading: Icon(ok ? Icons.check_circle : Icons.error_outline,
            color: ok ? Colors.green : Colors.orange),
        title: Text(title, style: const TextStyle(fontSize: 14)),
        subtitle: subtitle == null ? null : Text(subtitle, style: const TextStyle(fontSize: 12)),
        trailing: ok ? null : TextButton(onPressed: onFix, child: const Text('Fix')),
      ),
    );
  }
}
