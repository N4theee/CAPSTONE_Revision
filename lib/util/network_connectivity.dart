import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Shown when the device has no usable network for Supabase auth/API calls.
const String kNoInternetMessage = 'No internet connection';

/// Returns false when Wi‑Fi/mobile data appear unavailable.
Future<bool> hasNetworkConnection() async {
  if (kIsWeb) {
    return true;
  }
  try {
    final results = await Connectivity().checkConnectivity();
    if (results.isEmpty) return false;
    return results.any((r) => r != ConnectivityResult.none);
  } catch (_) {
    return true;
  }
}

bool isNetworkError(Object e) {
  final s = e.toString().toLowerCase();
  return s.contains('socketexception') ||
      s.contains('clientexception') ||
      s.contains('failed host lookup') ||
      s.contains('network is unreachable') ||
      s.contains('connection refused') ||
      s.contains('connection timed out') ||
      s.contains('connection reset') ||
      s.contains('no address associated with hostname') ||
      s.contains('network error') ||
      s.contains('authretryablefetchexception');
}

String? networkErrorMessage(Object e) {
  if (isNetworkError(e)) return kNoInternetMessage;
  return null;
}
