import 'package:supabase_flutter/supabase_flutter.dart';
import 'admin_data_service.dart';

const deviceResetReasons = [
  'Lost phone',
  'Broken phone',
  'Replacement phone',
  'Device reassignment',
  'Other',
];

class DeviceManagementService {
  final _db = Supabase.instance.client;

  Future<List<AdminRow>> devices(String studentId) async =>
      (await _db
              .from('student_devices')
              .select(
                'id,device_uuid,device_name,registered_at,last_seen_at,is_primary,approval_status',
              )
              .eq('student_id', studentId)
              .eq('is_active', true)
              .eq('is_revoked', false)
              .order('last_seen_at', ascending: false))
          .map((r) => AdminRow.from(r))
          .toList();

  Future<AdminRow> command({
    required String username,
    required String password,
    required String action,
    String? studentId,
    String? deviceUuid,
    String? reason,
    String details = '',
    int page = 0,
  }) async => AdminRow.from(
    await _db.rpc(
          'admin_device_management',
          params: {
            'p_username': username.trim(),
            'p_password': password,
            'p_action': action,
            'p_student_id': studentId,
            'p_device_uuid': deviceUuid,
            'p_reason': reason,
            'p_details': details.trim(),
            'p_page': page,
          },
        )
        as Map,
  );

  Future<bool> sessionValid(String studentId, String deviceUuid) async =>
      await _db.rpc(
            'student_device_session_valid',
            params: {'p_student_id': studentId, 'p_device_uuid': deviceUuid},
          )
          as bool;
}
