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

/// Live debug snapshot while scanning for teacher beacon during exam join.
class JoinProximityDebug {
  const JoinProximityDebug({
    this.scanning = false,
    this.expectedUuid,
    this.expectedBeaconName,
    this.currentThreshold,
    this.detectedBeaconName,
    this.detectedServiceUuid,
    this.foundServiceUuids = const [],
    this.rssi,
    this.uuidMatched = false,
    this.nameMatched = false,
    this.finalInRange = false,
    this.lastSeenAt,
    this.elapsed = Duration.zero,
  });

  final bool scanning;
  final String? expectedUuid;
  final String? expectedBeaconName;
  final int? currentThreshold;
  final String? detectedBeaconName;
  final String? detectedServiceUuid;
  final List<String> foundServiceUuids;
  final int? rssi;
  final bool uuidMatched;
  final bool nameMatched;
  final bool finalInRange;
  final DateTime? lastSeenAt;
  final Duration elapsed;

  JoinProximityDebug copyWith({
    bool? scanning,
    String? expectedUuid,
    String? expectedBeaconName,
    int? currentThreshold,
    String? detectedBeaconName,
    String? detectedServiceUuid,
    List<String>? foundServiceUuids,
    int? rssi,
    bool? uuidMatched,
    bool? nameMatched,
    bool? finalInRange,
    DateTime? lastSeenAt,
    Duration? elapsed,
  }) {
    return JoinProximityDebug(
      scanning: scanning ?? this.scanning,
      expectedUuid: expectedUuid ?? this.expectedUuid,
      expectedBeaconName: expectedBeaconName ?? this.expectedBeaconName,
      currentThreshold: currentThreshold ?? this.currentThreshold,
      detectedBeaconName: detectedBeaconName ?? this.detectedBeaconName,
      detectedServiceUuid:
          detectedServiceUuid ?? this.detectedServiceUuid,
      foundServiceUuids: foundServiceUuids ?? this.foundServiceUuids,
      rssi: rssi ?? this.rssi,
      uuidMatched: uuidMatched ?? this.uuidMatched,
      nameMatched: nameMatched ?? this.nameMatched,
      finalInRange: finalInRange ?? this.finalInRange,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      elapsed: elapsed ?? this.elapsed,
    );
  }
}

/// Exam-only beacon match (UUID and/or advertised name).
class ExamBeaconMatch {
  const ExamBeaconMatch({
    required this.rssi,
    required this.uuidMatched,
    required this.nameMatched,
    required this.beaconMatched,
    this.beaconName,
    this.matchedServiceUuid,
    this.foundServiceUuids = const [],
  });

  final int rssi;
  final bool uuidMatched;
  final bool nameMatched;
  final bool beaconMatched;
  final String? beaconName;
  final String? matchedServiceUuid;
  final List<String> foundServiceUuids;
}

class JoinProximityResult {
  const JoinProximityResult({
    required this.success,
    required this.debug,
  });

  final bool success;
  final JoinProximityDebug debug;
}

enum _BleScanMode { none, attendance, exam, join }

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

  // Exam-only state (does not affect attendance scanning).
  bool _examMonitoring = false;
  int _examGracePeriodSeconds = 30;
  int _examProximitySmoothingSeconds = AppConfig.examProximitySmoothingSeconds;
  DateTime? _examLastSeenInRangeAt;
  ExamBeaconMatch? _lastExamBeaconMatch;
  int? _examLastDetectedRssi;
  DateTime? _examOutOfRangeSince;

  ExamBeaconMatch? get lastExamBeaconMatch => _lastExamBeaconMatch;
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

  static String _normStr(String? value) => value?.trim().toLowerCase() ?? '';

  static String _normUuid(String value) =>
      _normStr(value).replaceAll('-', '');

  static bool _uuidEquals(String a, String b) =>
      _normUuid(a).isNotEmpty && _normUuid(a) == _normUuid(b);

  /// Returns null when permissions are OK; otherwise a user-visible message.
  Future<String?> examBlePermissionIssue() async {
    if (kIsWeb) {
      return 'BLE is not supported in the browser. Use the Android or iOS app.';
    }
    if (defaultTargetPlatform != TargetPlatform.android) {
      final r = await [
        Permission.bluetooth,
        Permission.locationWhenInUse,
      ].request();
      final ok = r.values.every((s) => s == PermissionStatus.granted);
      return ok ? null : 'Bluetooth and location permissions are required.';
    }

    final sdk = (await DeviceInfoPlugin().androidInfo).version.sdkInt;
    if (sdk >= 31) {
      final statuses = await [
        Permission.bluetoothScan,
        Permission.bluetoothAdvertise,
        Permission.bluetoothConnect,
        Permission.locationWhenInUse,
      ].request();
      for (final e in statuses.entries) {
        if (e.value == PermissionStatus.permanentlyDenied) {
          return 'Enable ${e.key.toString().split('.').last} in Settings, then retry.';
        }
      }
      final ok = statuses.values.every(
        (s) => s == PermissionStatus.granted || s == PermissionStatus.limited,
      );
      return ok
          ? null
          : 'Bluetooth scan, connect, advertise, and location are required.';
    }

    final results = await [
      Permission.bluetooth,
      Permission.locationWhenInUse,
    ].request();
    final ok = results.values.every(
      (s) => s == PermissionStatus.granted || s == PermissionStatus.limited,
    );
    return ok ? null : 'Bluetooth and location permissions are required.';
  }

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

  /// Evaluates scan results for attendance (unchanged) or exam (smoothed).
  ProximityUpdate _evaluateScanResults(List<ScanResult> results) {
    if (_scanMode == _BleScanMode.exam) {
      return _evaluateExamProximityResults(results);
    }

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

  ProximityUpdate _evaluateExamProximityResults(List<ScanResult> results) {
    var signalInRange = false;
    int? bestRssi;

    for (final r in results) {
      final match = _examBeaconMatchFromResult(r);
      if (match == null || !match.beaconMatched) continue;

      _lastExamBeaconMatch = match;
      if (bestRssi == null || match.rssi > bestRssi) {
        bestRssi = match.rssi;
      }

      final detectedRssi = match.rssi;
      final rssiThreshold = _rssiThreshold;
      final inRangeNow = detectedRssi >= rssiThreshold;
      debugPrint('[EXAM BLE] session threshold: $rssiThreshold');
      debugPrint('[EXAM BLE] detected RSSI: $detectedRssi');
      debugPrint('[EXAM BLE] in range: $inRangeNow');

      if (inRangeNow) {
        signalInRange = true;
      }
    }

    if (signalInRange) {
      _examLastSeenInRangeAt = DateTime.now();
    }
    if (bestRssi != null) {
      _examLastDetectedRssi = bestRssi;
    }

    final isInRange = signalInRange ||
        (_examLastSeenInRangeAt != null &&
            DateTime.now().difference(_examLastSeenInRangeAt!).inSeconds <
                _examProximitySmoothingSeconds);

    return ProximityUpdate(
      inRange: isInRange,
      rssi: bestRssi ?? _examLastDetectedRssi,
    );
  }

  /// Exam join + monitor: UUID match OR beacon name fallback (Android).
  ExamBeaconMatch? _examBeaconMatchFromResult(ScanResult r) {
    final expectedUuid = _targetBeaconUuid;
    if (expectedUuid == null || expectedUuid.isEmpty) return null;

    final platformName = _normStr(r.device.platformName);
    final advName = _normStr(r.advertisementData.advName);
    final displayName = platformName.isNotEmpty
        ? platformName
        : (advName.isNotEmpty ? advName : null);

    final foundUuids = r.advertisementData.serviceUuids
        .map((id) => id.str.trim().toLowerCase())
        .toList();

    final uuidMatched = foundUuids.any((u) => _uuidEquals(u, expectedUuid));

    final beaconName = _targetBeaconName;
    final shortBeaconName = beaconName != null && beaconName.length > 8
        ? beaconName.substring(0, 8)
        : beaconName;
    final nameMatched = beaconName != null &&
        beaconName.isNotEmpty &&
        (platformName == beaconName ||
            advName == beaconName ||
            (shortBeaconName != null &&
                (platformName == shortBeaconName ||
                    advName == shortBeaconName)));

    final beaconMatched = uuidMatched || nameMatched;
    if (!beaconMatched) return null;

    String? matchedUuid;
    if (uuidMatched) {
      matchedUuid = foundUuids.firstWhere((u) => _uuidEquals(u, expectedUuid));
    }

    return ExamBeaconMatch(
      rssi: r.rssi,
      uuidMatched: uuidMatched,
      nameMatched: nameMatched,
      beaconMatched: true,
      beaconName: displayName,
      matchedServiceUuid: matchedUuid,
      foundServiceUuids: foundUuids,
    );
  }

  /// Returns RSSI if this advertisement matches target UUID or name (attendance only).
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

  // ── EXAM BLE (join scan, monitor, teacher beacon) ─────────────────────────

  Timer? _joinScanTimer;
  Completer<JoinProximityResult>? _joinScanCompleter;

  void _cleanupJoinScan({bool completeAsFailure = false}) {
    _joinScanTimer?.cancel();
    _joinScanTimer = null;
    if (completeAsFailure &&
        _joinScanCompleter != null &&
        !_joinScanCompleter!.isCompleted) {
      _joinScanCompleter!.complete(
        JoinProximityResult(
          success: false,
          debug: _lastJoinDebug.copyWith(scanning: false),
        ),
      );
    }
    _joinScanCompleter = null;
    if (_scanMode == _BleScanMode.join) {
      _scanMode = _BleScanMode.none;
    }
    _resultSub?.cancel();
    _resultSub = null;
    FlutterBluePlus.stopScan();
    _lastProximity = const ProximityUpdate(inRange: false, rssi: null);
  }

  void stopJoinProximityScan() {
    if (_scanMode != _BleScanMode.join && _joinScanCompleter == null) return;
    debugPrint('[BLE] Stopping exam join proximity scan');
    _cleanupJoinScan(completeAsFailure: true);
  }

  /// Stops exam join scan, continuous exam monitor, and exam beacon advertising.
  Future<void> stopExamBle() async {
    stopJoinProximityScan();
    stopExamProximityMonitoring();
    await stopExamBeaconAdvertising();
  }

  JoinProximityDebug _lastJoinDebug = const JoinProximityDebug();

  Future<JoinProximityResult> scanForExamBeacon({
    required String expectedBeaconUuid,
    String? beaconName,
    required int rssiThreshold,
    Duration timeout = const Duration(seconds: AppConfig.examJoinScanTimeoutSeconds),
    void Function(JoinProximityDebug debug)? onProgress,
  }) =>
      checkTeacherProximityWithTimeout(
        expectedBeaconUuid: expectedBeaconUuid,
        beaconName: beaconName,
        rssiThreshold: rssiThreshold,
        timeout: timeout,
        onProgress: onProgress,
      );

  /// Scans up to [timeout] for teacher exam beacon (UUID or name) + RSSI.
  Future<JoinProximityResult> checkTeacherProximityWithTimeout({
    required String expectedBeaconUuid,
    String? beaconName,
    required int rssiThreshold,
    Duration timeout = const Duration(seconds: AppConfig.examJoinScanTimeoutSeconds),
    void Function(JoinProximityDebug debug)? onProgress,
  }) async {
    stopJoinProximityScan();
    if (_examMonitoring) stopExamProximityMonitoring();
    if (_scanMode == _BleScanMode.attendance) stopProximityScanning();

    final btOn = await isBluetoothOn();
    if (!btOn) {
      const debug = JoinProximityDebug(scanning: false);
      return const JoinProximityResult(success: false, debug: debug);
    }

    final targetUuid = expectedBeaconUuid.trim().toLowerCase();
    if (targetUuid.isEmpty) {
      return const JoinProximityResult(
        success: false,
        debug: JoinProximityDebug(scanning: false),
      );
    }

    _scanMode = _BleScanMode.join;
    _targetBeaconUuid = targetUuid;
    _targetBeaconName = beaconName?.trim().toLowerCase();
    _rssiThreshold = rssiThreshold;

    final expectedName = _targetBeaconName;
    debugPrint('[STUDENT EXAM BLE] expected uuid: $targetUuid');
    debugPrint('[STUDENT EXAM BLE] expected beacon name: $expectedName');

    final stopwatch = Stopwatch()..start();
    _lastJoinDebug = JoinProximityDebug(
      scanning: true,
      expectedUuid: targetUuid,
      expectedBeaconName: expectedName,
      currentThreshold: rssiThreshold,
    );
    onProgress?.call(_lastJoinDebug);

    _joinScanCompleter = Completer<JoinProximityResult>();
    final resultFuture = _joinScanCompleter!.future;

    void emitProgress(JoinProximityDebug d) {
      _lastJoinDebug = d;
      onProgress?.call(d);
    }

    void finish(bool success) {
      final completer = _joinScanCompleter;
      if (completer == null || completer.isCompleted) return;
      emitProgress(
        _lastJoinDebug.copyWith(
          scanning: false,
          elapsed: stopwatch.elapsed,
        ),
      );
      completer.complete(
        JoinProximityResult(success: success, debug: _lastJoinDebug),
      );
      _cleanupJoinScan();
    }

    _resultSub?.cancel();
    _resultSub = FlutterBluePlus.onScanResults.listen(
      (results) {
        if (_scanMode != _BleScanMode.join) return;

        for (final r in results) {
          final match = _examBeaconMatchFromResult(r);
          if (match == null) continue;

          final detectedRssi = match.rssi;
          final inRangeNow = detectedRssi >= _rssiThreshold;
          debugPrint(
            '[STUDENT EXAM BLE] found service UUIDs: ${match.foundServiceUuids}',
          );
          debugPrint('[STUDENT EXAM BLE] uuid matched: ${match.uuidMatched}');
          debugPrint('[STUDENT EXAM BLE] name matched: ${match.nameMatched}');
          debugPrint('[EXAM BLE] session threshold: $_rssiThreshold');
          debugPrint('[EXAM BLE] detected RSSI: $detectedRssi');
          debugPrint('[EXAM BLE] in range: $inRangeNow');

          emitProgress(
            JoinProximityDebug(
              scanning: true,
              expectedUuid: targetUuid,
              expectedBeaconName: expectedName,
              currentThreshold: _rssiThreshold,
              detectedBeaconName: match.beaconName,
              detectedServiceUuid: match.matchedServiceUuid,
              foundServiceUuids: match.foundServiceUuids,
              rssi: detectedRssi,
              uuidMatched: match.uuidMatched,
              nameMatched: match.nameMatched,
              finalInRange: inRangeNow,
              lastSeenAt: inRangeNow ? DateTime.now() : _lastJoinDebug.lastSeenAt,
              elapsed: stopwatch.elapsed,
            ),
          );

          if (match.beaconMatched && inRangeNow) {
            debugPrint(
              '[BLE] ✅ Join proximity OK RSSI=$detectedRssi UUID=$targetUuid',
            );
            finish(true);
            return;
          }
        }
      },
      onError: (e) => debugPrint('[BLE] Join scan error: $e'),
    );

    try {
      await FlutterBluePlus.stopScan();
      await Future.delayed(const Duration(milliseconds: 200));
      await FlutterBluePlus.startScan(
        timeout: timeout,
        continuousUpdates: true,
        androidUsesFineLocation: true,
      );
      debugPrint('[BLE] Join scan started (${timeout.inSeconds}s max)');
    } catch (e) {
      debugPrint('[BLE] Join startScan failed: $e');
      finish(false);
    }

    _joinScanTimer = Timer(timeout, () {
      debugPrint('[BLE] Join scan timed out after ${timeout.inSeconds}s');
      finish(false);
    });

    return resultFuture;
  }

  // ── EXAM PROXIMITY (continuous scan + 5s smoothing + grace auto-end) ─────

  Future<void> monitorExamProximity({
    required String expectedBleUuid,
    int? rssiThreshold,
    int? gracePeriodSeconds,
    int? smoothingSeconds,
    String? beaconName,
    required void Function(int rssi, bool isInRange) onReading,
    required void Function() onOutOfRange,
    required void Function() onReturnedInRange,
    required void Function() onAutoEndRequired,
  }) =>
      startExamProximityMonitoring(
        expectedBleUuid: expectedBleUuid,
        rssiThreshold: rssiThreshold,
        gracePeriodSeconds: gracePeriodSeconds,
        smoothingSeconds: smoothingSeconds,
        beaconName: beaconName,
        onReading: onReading,
        onOutOfRange: onOutOfRange,
        onReturnedInRange: onReturnedInRange,
        onAutoEndRequired: onAutoEndRequired,
      );

  Future<void> startExamProximityMonitoring({
    required String expectedBleUuid,
    int? rssiThreshold,
    int? gracePeriodSeconds,
    int? smoothingSeconds,
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
    _examProximitySmoothingSeconds =
        smoothingSeconds ?? AppConfig.examProximitySmoothingSeconds;
    _examLastSeenInRangeAt = null;
    _examLastDetectedRssi = null;
    _lastExamBeaconMatch = null;
    _examOnReading = onReading;
    _examOnOutOfRange = onOutOfRange;
    _examOnReturnedInRange = onReturnedInRange;
    _examOnAutoEndRequired = onAutoEndRequired;
    _examOutOfRangeSince = null;
    _examOutOfRangeNotified = false;
    _examAutoEndTriggered = false;

    final threshold = rssiThreshold ?? AppConfig.rssiThreshold;
    debugPrint('[STUDENT EXAM BLE] expected uuid: ${expectedBleUuid.trim().toLowerCase()}');
    debugPrint('[STUDENT EXAM BLE] expected beacon name: ${beaconName?.trim().toLowerCase()}');
    debugPrint('[EXAM BLE] session threshold: $threshold');

    await _startContinuousProximityScan(
      mode: _BleScanMode.exam,
      beaconUuid: expectedBleUuid,
      beaconName: beaconName,
      rssiThreshold: threshold,
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
    _examLastSeenInRangeAt = null;
    _examLastDetectedRssi = null;
    _lastExamBeaconMatch = null;
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
    stopJoinProximityScan();
    stopExamProximityMonitoring();
    stopProximityScanning();
    _proximityCtrl.close();
    _proximityDetailCtrl.close();
  }

  // ── TEACHER BEACON ADVERTISING (attendance + exam) ────────────────────

  Future<void> startExamBeaconAdvertising({
    required String bleUuid,
    required String beaconName,
  }) async {
    debugPrint('[TEACHER EXAM BLE] advertising uuid: $bleUuid');
    debugPrint('[TEACHER EXAM BLE] beacon name: $beaconName');
    await startTeacherBeacon(beaconUuid: bleUuid, localName: beaconName);
  }

  Future<void> stopExamBeaconAdvertising() => stopTeacherBeacon();

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
