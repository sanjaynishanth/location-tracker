import 'package:flutter/services.dart';

/// Thin wrapper over the native Device Admin MethodChannel (Android only).
class DeviceAdmin {
  static const _ch = MethodChannel('field_tracker/device_admin');

  static Future<bool> isActive() async {
    try {
      return (await _ch.invokeMethod<bool>('isActive')) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> request() async {
    try {
      await _ch.invokeMethod('request');
    } catch (_) {}
  }

  static Future<void> remove() async {
    try {
      await _ch.invokeMethod('remove');
    } catch (_) {}
  }
}
