import 'dart:async';

import 'package:flutter/widgets.dart';

import '../config.dart';
import 'ble_service.dart';
import 'supabase_service.dart';

/// Owns the teacher beacon independently of navigation routes.
class ExamBeaconService with WidgetsBindingObserver {
  static final ExamBeaconService _instance = ExamBeaconService._();
  factory ExamBeaconService() => _instance;
  ExamBeaconService._();

  @visibleForTesting
  ExamBeaconService.forTesting({
    required Future<void> Function(ExamSession, SubjectOffering) prepare,
    required Future<void> Function() stopAdvertising,
    required Future<ExamSession?> Function(String) loadSession,
  }) : _prepare = prepare,
       _stopAdvertising = stopAdvertising,
       _loadSession = loadSession;

  Future<void> Function(ExamSession, SubjectOffering)? _prepare;
  Future<void> Function()? _stopAdvertising;
  Future<ExamSession?> Function(String)? _loadSession;
  bool _reconciling = false;

  bool isReadyFor(String sessionId) => _session?.id == sessionId && ready.value;

  final ready = ValueNotifier<bool>(false);
  final error = ValueNotifier<String?>(null);
  final _ble = BleService();
  ExamSession? _session;
  SubjectOffering? _offering;
  Timer? _timer;
  Future<void> _queue = Future<void>.value();
  bool _observing = false;

  Future<void> _serialize(Future<void> Function() action) {
    final result = _queue.then((_) => action());
    _queue = result.catchError((Object _) {});
    return result;
  }

  Future<void> ensure(ExamSession session, SubjectOffering offering) =>
      _serialize(() async {
        if (_session != null && _session!.id != session.id) {
          throw Exception(
            'Another exam beacon is already running. End that exam first.',
          );
        }
        _session = session;
        _offering = offering;
        await _advertise();
        if (!_observing) {
          WidgetsBinding.instance.addObserver(this);
          _observing = true;
        }
        _timer ??= Timer.periodic(const Duration(seconds: 15), (_) {
          if (WidgetsBinding.instance.lifecycleState ==
              AppLifecycleState.resumed) {
            unawaited(_reconcile());
          }
        });
      });

  Future<void> _advertise() async {
    final session = _session;
    final offering = _offering;
    if (session == null || offering == null) return;
    try {
      if (_prepare != null) {
        await _prepare!(session, offering);
        ready.value = true;
        error.value = null;
        return;
      }
      final issue = await _ble.examBlePermissionIssue();
      if (issue != null) throw Exception(issue);
      if (!await _ble.isBluetoothOn()) {
        throw Exception('Turn on Bluetooth to let students join.');
      }
      final uuid = ExamService.resolveBeaconUuid(
        session: session,
        offeringBeaconUuid: offering.beaconUuid,
      );
      if (uuid.isEmpty) throw Exception('This class has no beacon UUID.');
      final name = offering.beaconName.trim().isNotEmpty
          ? offering.beaconName.trim()
          : offering.subjectCode.trim().isNotEmpty
          ? offering.subjectCode.trim()
          : AppConfig.defaultBeaconName;
      await _ble.startExamBeaconAdvertising(bleUuid: uuid, beaconName: name);
      if (!await _ble.isTeacherBeaconAdvertising()) {
        throw Exception(
          'Bluetooth advertising did not start. Retry on the professor phone.',
        );
      }
      ready.value = true;
      error.value = null;
    } catch (e) {
      ready.value = false;
      error.value = e.toString();
      rethrow;
    }
  }

  Future<void> _reconcile() async {
    if (_reconciling) return;
    _reconciling = true;
    try {
      await _serialize(() async {
        if (_session == null) return;
        try {
          final fresh =
              await (_loadSession?.call(_session!.id) ??
                  ExamService().getExamSessionById(_session!.id));
          if (fresh == null ||
              fresh.isTerminal ||
              (fresh.endsAt != null &&
                  !fresh.endsAt!.isAfter(DateTime.now()))) {
            await _stop();
            return;
          }
          _session = fresh;
          await _advertise();
        } catch (e) {
          ready.value = false;
          error.value = 'Could not verify exam beacon: $e';
        }
      });
    } finally {
      _reconciling = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_reconcile());
    if (state == AppLifecycleState.paused) ready.value = false;
  }

  Future<void> stop({String? sessionId}) => _serialize(() async {
    if (sessionId != null && _session?.id != sessionId) return;
    await _stop();
  });

  Future<void> _stop() async {
    _timer?.cancel();
    _timer = null;
    _session = null;
    _offering = null;
    ready.value = false;
    error.value = null;
    if (_observing) WidgetsBinding.instance.removeObserver(this);
    _observing = false;
    await (_stopAdvertising?.call() ?? _ble.stopExamBeaconAdvertising());
  }
}
