import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'device_identity_service.dart';
import 'supabase_service.dart';

/// Persists the last successful student login for cold-start routing.
/// Isolated from BLE "remember me" credentials in [AuthScreen].
class LocalSessionService {
  LocalSessionService._();
  static final LocalSessionService _i = LocalSessionService._();
  factory LocalSessionService() => _i;

  static const _payloadKey = 'local_student_session_v1';
  int _revision = 0;
  int get revision => _revision;

  Future<void> saveUserSession(AppUser user, DeviceIdentity identity) async {
    if (user.role != 'student') return;
    _revision++;
    final prefs = await SharedPreferences.getInstance();
    final map = {
      'role': user.role,
      'linkedId': user.linkedId,
      'fullName': user.fullName,
      'username': user.username,
      'deviceUuid': identity.deviceUuid,
    };
    await prefs.setString(_payloadKey, jsonEncode(map));
  }

  Future<SavedStudentSession?> getSavedUserSession() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_payloadKey);
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      if ((map['role'] as String?) != 'student') return null;
      final linkedId = map['linkedId'] as String?;
      final deviceUuid = map['deviceUuid'] as String?;
      if (linkedId == null ||
          linkedId.isEmpty ||
          deviceUuid == null ||
          deviceUuid.isEmpty) {
        return null;
      }
      return SavedStudentSession(
        user: AppUser(
          role: 'student',
          linkedId: linkedId,
          fullName: (map['fullName'] as String?) ?? 'Student',
          username: (map['username'] as String?) ?? '',
        ),
        deviceUuid: deviceUuid,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> clearUserSession() async {
    _revision++;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_payloadKey);
  }

  Future<bool> hasSavedStudentSession() async {
    final s = await getSavedUserSession();
    return s != null;
  }
}

class SavedStudentSession {
  const SavedStudentSession({required this.user, required this.deviceUuid});

  final AppUser user;
  final String deviceUuid;
}
