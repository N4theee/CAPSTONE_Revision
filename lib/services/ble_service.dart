import 'dart:async';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../config.dart';

class AttendanceDeviceInfo {
  const AttendanceDeviceInfo({
    required this.deviceName,
    required this.deviceUuid,
    required this.deviceFingerprint,
    this.deviceMac,
  });

  final String deviceName;
  final String deviceUuid;
  final String deviceFingerprint;
  final String? deviceMac;
}

class BleService {
  static final BleService _i = BleService._();
  factory BleService() => _i;
  BleService._();

  final _proximityCtrl = StreamController<bool>.broadcast();
  Stream<bool> get proximityStream => _proximityCtrl.stream;

  StreamSubscription? _scanSub;
  StreamSubscription? _resultSub;
  Timer? _restartTimer;
  bool _scanning = false;
  String? _targetBeaconUuid;
  String? _targetBeaconName;
  int _rssiThreshold = AppConfig.rssiThreshold;
  final FlutterBlePeripheral _peripheral = FlutterBlePeripheral();
  static const _deviceUuidKey = 'attendance_device_uuid';
  static const Uuid _uuid = Uuid();

  Future<String> getOrCreateDeviceUuid() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_deviceUuidKey)?.trim();
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }
    final generated = _uuid.v4();
    await prefs.setString(_deviceUuidKey, generated);
    return generated;
  }

  // ── PERMISSIONS ──────────────────────────────────────────────────────
  Future<bool> requestPermissions() async {
    if (kIsWeb) return true;

    if (defaultTargetPlatform != TargetPlatform.android) {
      final r = await [
        Permission.bluetooth,
        Permission.locationWhenInUse,
      ].request();
      return r.values.every((s) => s == PermissionStatus.granted);
    }

    final sdk = (await DeviceInfoPlugin().androidInfo).version.sdkInt;
    debugPrint('[BLE] Android SDK version: $sdk');

    // Android 12+ (SDK 31+)
    if (sdk >= 31) {
      final results = await [
        Permission.bluetoothScan,
        Permission.bluetoothAdvertise,
        Permission.bluetoothConnect,
        Permission.locationWhenInUse,
      ].request();

      debugPrint('[BLE] Permission results:');
      for (final e in results.entries) {
        debugPrint('  ${e.key}: ${e.value}');
      }

      // Check if any are permanently denied
      for (final e in results.entries) {
        if (e.value == PermissionStatus.permanentlyDenied) {
          debugPrint('[BLE] ❌ Permanently denied: ${e.key}');
          debugPrint('[BLE] User must enable in Settings manually');
        }
      }

      return results.values.every(
        (s) => s == PermissionStatus.granted || s == PermissionStatus.limited,
      );
    }

    // Android 11 and below
    final results = await [
      Permission.bluetooth,
      Permission.locationWhenInUse,
    ].request();

    return results.values.every(
      (s) => s == PermissionStatus.granted || s == PermissionStatus.limited,
    );
  }

  // ── CHECK if BT adapter is on ─────────────────────────────────────────
  Future<bool> isBluetoothOn() async {
    final state = await FlutterBluePlus.adapterState.first;
    debugPrint('[BLE] Adapter state: $state');
    return state == BluetoothAdapterState.on;
  }

  Future<AttendanceDeviceInfo> getAttendanceDeviceInfo() async {
    final deviceUuid = await getOrCreateDeviceUuid();
    if (kIsWeb) {
      return AttendanceDeviceInfo(
        deviceName: 'Web Browser',
        deviceUuid: deviceUuid,
        deviceFingerprint: 'web-browser',
      );
    }

    final info = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      final android = await info.androidInfo;
      final model = android.model.trim().isEmpty ? 'Android Device' : android.model.trim();
      final manufacturer = android.manufacturer.trim();
      final hardwareKey = android.id.trim().isNotEmpty
          ? android.id.trim()
          : '${android.brand}-${android.device}-${android.product}';
      final fingerprint =
          'android:${manufacturer.toLowerCase()}:${model.toLowerCase()}:$hardwareKey';
      final name = manufacturer.isNotEmpty ? '$manufacturer $model' : model;
      return AttendanceDeviceInfo(
        deviceName: name,
        deviceUuid: deviceUuid,
        deviceFingerprint: fingerprint,
      );
    }

    if (Platform.isIOS) {
      final ios = await info.iosInfo;
      final model = ios.utsname.machine.trim().isEmpty
          ? 'iOS Device'
          : ios.utsname.machine.trim();
      final name = ios.name.trim().isEmpty ? model : ios.name.trim();
      final fingerprint = 'ios:${ios.identifierForVendor ?? model}:$model';
      return AttendanceDeviceInfo(
        deviceName: name,
        deviceUuid: deviceUuid,
        deviceFingerprint: fingerprint,
      );
    }

    final fallback = await info.deviceInfo;
    final data = fallback.data;
    final machine = (data['model'] ?? data['machine'] ?? 'device').toString();
    final os = (data['systemName'] ?? Platform.operatingSystem).toString();
    final fingerprint = '$os:$machine';
    return AttendanceDeviceInfo(
      deviceName: machine,
      deviceUuid: deviceUuid,
      deviceFingerprint: fingerprint,
    );
  }

  // ── SCAN ALL NEARBY (setup helper) ────────────────────────────────────
  Future<Map<String, int>> scanAllDevices({int seconds = 8}) async {
    final found = <String, int>{};

    debugPrint('[BLE] === FULL SCAN STARTED ($seconds sec) ===');

    // Make sure BT is on
    final btOn = await isBluetoothOn();
    if (!btOn) {
      debugPrint('[BLE] ❌ Bluetooth is OFF');
      return {'ERROR: Bluetooth is off': 0};
    }

    // Stop any existing scan first
    await FlutterBluePlus.stopScan();
    await Future.delayed(const Duration(milliseconds: 300));

    final sub = FlutterBluePlus.onScanResults.listen((results) {
      for (final r in results) {
        final name = r.device.platformName.trim();
        final mac  = r.device.remoteId.str;
        final rssi = r.rssi;

        // Show everything — named and unnamed
        final key = name.isEmpty ? '(unnamed) $mac' : name;
        found[key] = rssi;
        debugPrint('[BLE] Scan found: "$key" RSSI=$rssi');
      }
    });

    try {
      await FlutterBluePlus.startScan(
        timeout: Duration(seconds: seconds),
        continuousUpdates: true,
        androidUsesFineLocation: true,
      );
      debugPrint('[BLE] Scan started successfully');
    } catch (e) {
      debugPrint('[BLE] ❌ startScan failed: $e');
      found['ERROR: $e'] = 0;
    }

    await Future.delayed(Duration(seconds: seconds + 1));
    await sub.cancel();
    await FlutterBluePlus.stopScan();

    debugPrint('[BLE] === SCAN COMPLETE — found ${found.length} devices ===');
    return found;
  }

  // ── START PROXIMITY SCANNING ──────────────────────────────────────────
  Future<void> startProximityScanning(
    String beaconUuid, {
    String? beaconName,
    /// When null, uses [AppConfig.rssiThreshold] (session row can override per class).
    int? rssiThreshold,
  }) async {
    if (_scanning) stopProximityScanning();

    final btOn = await isBluetoothOn();
    if (!btOn) {
      debugPrint('[BLE] ❌ Cannot scan — Bluetooth is off');
      return;
    }

    _scanning   = true;
    _targetBeaconUuid = beaconUuid.trim().toLowerCase();
    _targetBeaconName = beaconName?.trim().toLowerCase();
    _rssiThreshold = rssiThreshold ?? AppConfig.rssiThreshold;
    debugPrint('[BLE] Starting proximity scan for UUID: "$_targetBeaconUuid" RSSI>=$_rssiThreshold');

    _runScan();

    // Restart scan every N seconds — Android kills long-running scans
    _restartTimer = Timer.periodic(
      Duration(seconds: AppConfig.scanRestartSeconds),
      (_) {
        if (_scanning) {
          debugPrint('[BLE] ♻️  Restarting scan cycle...');
          FlutterBluePlus.stopScan();
          Future.delayed(const Duration(milliseconds: 500), _runScan);
        }
      },
    );
  }

  void _runScan() {
    _resultSub?.cancel();

    _resultSub = FlutterBluePlus.onScanResults.listen((results) {
      debugPrint('[BLE] Tick: ${results.length} devices in range');

      bool found = false;
      for (final r in results) {
        final name = r.device.platformName.trim().toLowerCase();
        final advName = r.advertisementData.advName.trim().toLowerCase();
        final rssi = r.rssi;
        final serviceUuids = r.advertisementData.serviceUuids
            .map((uuid) => uuid.str.toLowerCase())
            .toList();
        final nameMatch = _targetBeaconName != null &&
            (name == _targetBeaconName || advName == _targetBeaconName);
        final uuidMatch = serviceUuids.contains(_targetBeaconUuid);
        debugPrint('[BLE]   → "$name" / "$advName" | RSSI: $rssi');

        if ((uuidMatch || nameMatch) && rssi >= _rssiThreshold) {
          found = true;
          debugPrint(
              '[BLE] ✅ TEACHER BEACON IN RANGE! UUID=$_targetBeaconUuid NAME=$_targetBeaconName RSSI=$rssi');
          break;
        }
      }

      if (!_proximityCtrl.isClosed) _proximityCtrl.add(found);
    },
    onError: (e) => debugPrint('[BLE] Scan result error: $e'));

    FlutterBluePlus.startScan(
      continuousUpdates: true,
      androidUsesFineLocation: true,
      timeout: Duration(seconds: AppConfig.scanRestartSeconds - 1),
    ).catchError((e) => debugPrint('[BLE] startScan error: $e'));
  }

  void stopProximityScanning() {
    debugPrint('[BLE] Stopping proximity scan');
    _scanning = false;
    _restartTimer?.cancel();
    _resultSub?.cancel();
    _scanSub?.cancel();
    FlutterBluePlus.stopScan();
    if (!_proximityCtrl.isClosed) _proximityCtrl.add(false);
  }

  void dispose() {
    stopProximityScanning();
    _proximityCtrl.close();
  }

  // ── TEACHER BEACON ADVERTISING ──────────────────────────────────────
  Future<void> startTeacherBeacon({
    required String beaconUuid,
    required String localName,
  }) async {
    if (kIsWeb) {
      throw Exception(
          'BLE advertising is not supported on Web. Start teacher session from Android/iOS phone.');
    }

    bool supported;
    try {
      supported = await _peripheral.isSupported;
    } on MissingPluginException {
      throw Exception(
          'BLE peripheral plugin is unavailable on this platform. Use Android/iOS mobile app for teacher sessions.');
    }
    if (!supported) {
      throw Exception('BLE advertising is not supported on this phone');
    }

    if (await _peripheral.isAdvertising) {
      await _peripheral.stop();
    }

    final compactName =
        localName.trim().isEmpty ? AppConfig.defaultBeaconName : localName.trim();
    final shortName =
        compactName.length > 8 ? compactName.substring(0, 8) : compactName;
    final settings = AdvertiseSettings(
      advertiseSet: false, // avoids StartAdvertisingSet issues on some devices
      timeout: 0, // keep advertising running until we stop session
    );

    // Preferred payload: UUID + very short local name.
    final preferredAd = AdvertiseData(
      serviceUuid: beaconUuid,
      localName: shortName,
      includeDeviceName: false,
    );

    try {
      await _peripheral.start(
        advertiseData: preferredAd,
        advertiseSettings: settings,
      );
      debugPrint('[BLE] Teacher beacon started. UUID=$beaconUuid');
      return;
    } catch (e) {
      debugPrint('[BLE] Preferred advertising failed: $e');
    }

    // Fallback payload: UUID only (smallest payload).
    final fallbackAd = AdvertiseData(
      serviceUuid: beaconUuid,
      includeDeviceName: false,
    );
    await _peripheral.start(
      advertiseData: fallbackAd,
      advertiseSettings: settings,
    );
    debugPrint('[BLE] Teacher beacon started with fallback payload.');
  }

  Future<void> stopTeacherBeacon() async {
    try {
      await _peripheral.stop();
    } on MissingPluginException {
      // Ignore on unsupported platforms where plugin is not loaded.
    }
    debugPrint('[BLE] Teacher beacon stopped');
  }
}