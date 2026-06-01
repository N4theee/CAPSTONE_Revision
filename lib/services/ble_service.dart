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

/// Latest proximity sample from an active BLE scan (attendance + exam).
class ProximityUpdate {
  const ProximityUpdate({required this.inRange, this.rssi});

  final bool inRange;
  final int? rssi;
}

enum _BleScanMode { none, attendance, exam }

class BleService {
  static final BleService _i = BleService._();
  factory BleService() => _i;
  BleService._();

  final _proximityCtrl = StreamController<bool>.broadcast();
  final _proximityDetailCtrl = StreamController<ProximityUpdate>.broadcast();
  Stream<bool> get proximityStream => _proximityCtrl.stream;
  Stream<ProximityUpdate> get proximityDetailStream =>
      _proximityDetailCtrl.stream;

  ProximityUpdate _lastProximity =
      const ProximityUpdate(inRange: false, rssi: null);
  ProximityUpdate get lastProximity => _lastProximity;

  StreamSubscription? _resultSub;
  Timer? _restartTimer;
  _BleScanMode _scanMode = _BleScanMode.none;

  String? _targetBeaconUuid;
  String? _targetBeaconName;
  int _rssiThreshold = AppConfig.rssiThreshold;

  // Exam grace-period (same scan path as attendance; different callbacks).
  bool _examMonitoring = false;
  int _examGracePeriodSeconds = 30;
  DateTime? _examOutOfRangeSince;
  bool _examOutOfRangeNotified = false;
  bool _examAutoEndTriggered = false;
  void Function(int rssi, bool isInRange)? _examOnReading;
  void Function()? _examOnOutOfRange;
  void Function()? _examOnReturnedInRange;
  void Function()? _examOnAutoEndRequired;

  final FlutterBlePeripheral _peripheral = FlutterBlePeripheral();
  static const _deviceUuidKey = 'attendance_device_uuid';
  static const Uuid _uuid = Uuid();

  bool get isExamProximityMonitoring => _examMonitoring;
  bool get _isScanning => _scanMode != _BleScanMode.none;

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

    final results = await [
      Permission.bluetooth,
      Permission.locationWhenInUse,
    ].request();

    return results.values.every(
      (s) => s == PermissionStatus.granted || s == PermissionStatus.limited,
    );
  }

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
      final model =
          android.model.trim().isEmpty ? 'Android Device' : android.model.trim();
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

  Future<Map<String, int>> scanAllDevices({int seconds = 8}) async {
    final found = <String, int>{};

    debugPrint('[BLE] === FULL SCAN STARTED ($seconds sec) ===');

    final btOn = await isBluetoothOn();
    if (!btOn) {
      debugPrint('[BLE] ❌ Bluetooth is OFF');
      return {'ERROR: Bluetooth is off': 0};
    }

    await FlutterBluePlus.stopScan();
    await Future.delayed(const Duration(milliseconds: 300));

    final sub = FlutterBluePlus.onScanResults.listen((results) {
      for (final r in results) {
        final name = r.device.platformName.trim();
        final mac = r.device.remoteId.str;
        final rssi = r.rssi;
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

  // ── Shared continuous proximity scan (attendance + exam) ─────────────────

  /// Same engine as attendance: continuous scan + periodic restart on Android.
  Future<void> _startContinuousProximityScan({
    required _BleScanMode mode,
    required String beaconUuid,
    String? beaconName,
    int? rssiThreshold,
  }) async {
    _stopContinuousProximityScan();

    final btOn = await isBluetoothOn();
    if (!btOn) {
      debugPrint('[BLE] ❌ Cannot scan — Bluetooth is off');
      return;
    }

    _scanMode = mode;
    _targetBeaconUuid = beaconUuid.trim().toLowerCase();
    _targetBeaconName = beaconName?.trim().toLowerCase();
    _rssiThreshold = rssiThreshold ?? AppConfig.rssiThreshold;

    debugPrint(
      '[BLE] Continuous scan (${mode.name}) UUID="$_targetBeaconUuid" '
      'NAME="$_targetBeaconName" RSSI>=$_rssiThreshold '
      'restart=${AppConfig.scanRestartSeconds}s',
    );

    _runContinuousScan();

    _restartTimer = Timer.periodic(
      Duration(seconds: AppConfig.scanRestartSeconds),
      (_) {
        if (_isScanning) {
          debugPrint('[BLE] ♻️  Restarting scan cycle (${_scanMode.name})...');
          FlutterBluePlus.stopScan();
          Future.delayed(const Duration(milliseconds: 500), _runContinuousScan);
        }
      },
    );
  }

  void _stopContinuousProximityScan() {
    if (!_isScanning) return;
    debugPrint('[BLE] Stopping continuous scan (${_scanMode.name})');
    _scanMode = _BleScanMode.none;
    _restartTimer?.cancel();
    _restartTimer = null;
    _resultSub?.cancel();
    _resultSub = null;
    FlutterBluePlus.stopScan();
    _lastProximity = const ProximityUpdate(inRange: false, rssi: null);
    if (!_proximityCtrl.isClosed) _proximityCtrl.add(false);
    if (!_proximityDetailCtrl.isClosed) {
      _proximityDetailCtrl.add(_lastProximity);
    }
  }

  /// Evaluates scan results — identical rules for attendance and exam.
  ProximityUpdate _evaluateScanResults(List<ScanResult> results) {
    var found = false;
    int? bestRssi;

    for (final r in results) {
      final sample = _beaconSampleFromResult(r);
      if (sample == null) continue;

      if (sample.rssi >= _rssiThreshold) {
        found = true;
        if (bestRssi == null || sample.rssi > bestRssi) {
          bestRssi = sample.rssi;
        }
        debugPrint(
          '[BLE] ✅ BEACON IN RANGE (${_scanMode.name}) RSSI=${sample.rssi} '
          'UUID=$_targetBeaconUuid',
        );
      }
    }

    return ProximityUpdate(inRange: found, rssi: bestRssi);
  }

  /// Returns RSSI if this advertisement matches target UUID or name.
  ({int rssi})? _beaconSampleFromResult(ScanResult r) {
    final uuid = _targetBeaconUuid;
    if (uuid == null || uuid.isEmpty) return null;

    final name = r.device.platformName.trim().toLowerCase();
    final advName = r.advertisementData.advName.trim().toLowerCase();
    final rssi = r.rssi;
    final serviceUuids = r.advertisementData.serviceUuids
        .map((id) => id.str.toLowerCase())
        .toList();

    final beaconName = _targetBeaconName;
    final nameMatch = beaconName != null &&
        beaconName.isNotEmpty &&
        (name == beaconName || advName == beaconName);
    final uuidMatch = serviceUuids.contains(uuid);

    if (!uuidMatch && !nameMatch) return null;
    return (rssi: rssi);
  }

  void _runContinuousScan() {
    _resultSub?.cancel();

    _resultSub = FlutterBluePlus.onScanResults.listen(
      (results) {
        if (!_isScanning) return;

        final update = _evaluateScanResults(results);
        _emitProximityUpdate(update);
      },
      onError: (e) => debugPrint('[BLE] Scan result error: $e'),
    );

    FlutterBluePlus.startScan(
      continuousUpdates: true,
      androidUsesFineLocation: true,
      timeout: Duration(seconds: AppConfig.scanRestartSeconds - 1),
    ).catchError((e) => debugPrint('[BLE] startScan error: $e'));
  }

  void _emitProximityUpdate(ProximityUpdate update) {
    _lastProximity = update;
    if (!_proximityCtrl.isClosed) _proximityCtrl.add(update.inRange);
    if (!_proximityDetailCtrl.isClosed) {
      _proximityDetailCtrl.add(update);
    }

    if (_scanMode == _BleScanMode.exam && _examMonitoring) {
      final rssiForCallback = update.rssi ?? (_rssiThreshold - 1);
      _examOnReading?.call(rssiForCallback, update.inRange);
      _handleExamGracePeriod(update.inRange);
    }
  }

  // ── ATTENDANCE PROXIMITY ───────────────────────────────────────────────────

  Future<void> startProximityScanning(
    String beaconUuid, {
    String? beaconName,
    int? rssiThreshold,
  }) async {
    if (_examMonitoring) stopExamProximityMonitoring();
    await _startContinuousProximityScan(
      mode: _BleScanMode.attendance,
      beaconUuid: beaconUuid,
      beaconName: beaconName,
      rssiThreshold: rssiThreshold,
    );
  }

  void stopProximityScanning() {
    if (_scanMode != _BleScanMode.attendance) return;
    _stopContinuousProximityScan();
  }

  // ── EXAM PROXIMITY (same scan; grace-period on out-of-range) ─────────────

  Future<void> startExamProximityMonitoring({
    required String expectedBleUuid,
    int? rssiThreshold,
    int? gracePeriodSeconds,
    String? beaconName,
    required void Function(int rssi, bool isInRange) onReading,
    required void Function() onOutOfRange,
    required void Function() onReturnedInRange,
    required void Function() onAutoEndRequired,
  }) async {
    stopExamProximityMonitoring();
    if (_scanMode == _BleScanMode.attendance) stopProximityScanning();

    final btOn = await isBluetoothOn();
    if (!btOn) {
      debugPrint('[BLE] ❌ Exam monitor — Bluetooth is off');
      return;
    }

    _examMonitoring = true;
    _examGracePeriodSeconds = gracePeriodSeconds ?? 30;
    _examOnReading = onReading;
    _examOnOutOfRange = onOutOfRange;
    _examOnReturnedInRange = onReturnedInRange;
    _examOnAutoEndRequired = onAutoEndRequired;
    _examOutOfRangeSince = null;
    _examOutOfRangeNotified = false;
    _examAutoEndTriggered = false;

    await _startContinuousProximityScan(
      mode: _BleScanMode.exam,
      beaconUuid: expectedBleUuid,
      beaconName: beaconName,
      rssiThreshold: rssiThreshold,
    );

    // Emit current state immediately (same as attendance stream consumers expect).
    if (_lastProximity.inRange) {
      final rssi = _lastProximity.rssi ?? (_rssiThreshold - 1);
      _examOnReading?.call(rssi, true);
    }
  }

  void stopExamProximityMonitoring() {
    if (!_examMonitoring) return;
    debugPrint('[BLE] Stopping exam proximity monitor');
    _examMonitoring = false;
    _examOutOfRangeSince = null;
    _examOutOfRangeNotified = false;
    _examAutoEndTriggered = false;
    _examOnReading = null;
    _examOnOutOfRange = null;
    _examOnReturnedInRange = null;
    _examOnAutoEndRequired = null;
    if (_scanMode == _BleScanMode.exam) {
      _stopContinuousProximityScan();
    }
  }

  /// Out-of-range grace timer only — in-range detection matches attendance scan ticks.
  void _handleExamGracePeriod(bool inRange) {
    if (!_examMonitoring || _examAutoEndTriggered) return;

    if (inRange) {
      if (_examOutOfRangeSince != null) {
        debugPrint('[BLE] Exam: back in range (continuous scan) — grace cleared');
        _examOutOfRangeSince = null;
        _examOutOfRangeNotified = false;
        _examOnReturnedInRange?.call();
      }
      return;
    }

    _examOutOfRangeSince ??= DateTime.now();

    if (!_examOutOfRangeNotified) {
      _examOutOfRangeNotified = true;
      debugPrint('[BLE] Exam: out of range (continuous scan) — grace started');
      _examOnOutOfRange?.call();
    }

    final elapsed = DateTime.now().difference(_examOutOfRangeSince!);
    if (elapsed.inSeconds >= _examGracePeriodSeconds && !_examAutoEndTriggered) {
      _examAutoEndTriggered = true;
      debugPrint(
        '[BLE] Exam: grace (${_examGracePeriodSeconds}s) exceeded — auto-end',
      );
      _examOnAutoEndRequired?.call();
    }
  }

  void dispose() {
    stopExamProximityMonitoring();
    stopProximityScanning();
    _proximityCtrl.close();
    _proximityDetailCtrl.close();
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
      advertiseSet: false,
      timeout: 0,
    );

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
