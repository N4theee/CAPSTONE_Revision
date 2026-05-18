import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/ble_service.dart';
import '../services/device_identity_service.dart';
import '../services/local_session_service.dart';
import '../services/supabase_service.dart';
import '../ui/landing_auth_ui.dart';
import '../ui/responsive.dart';
import '../util/network_connectivity.dart';
import 'student_dashboard_screen.dart';
import 'teacher_dashboard_screen.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, required this.initialRole});

  final String initialRole;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _db = SupabaseService();
  final _ble = BleService();
  final _identity = DeviceIdentityService();
  final _localSession = LocalSessionService();
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _studentIdCtrl = TextEditingController();
  final _fullNameCtrl = TextEditingController();
  bool _loading = false;
  bool _isRegister = false;
  bool _rememberMe = false;
  bool _obscurePassword = true;

  late String _role;
  static const _rememberRoleKey = 'remember_role';
  static const _rememberUserKey = 'remember_username';
  static const _rememberPassKey = 'remember_password';

  @override
  void initState() {
    super.initState();
    _role = widget.initialRole == 'professor' ? 'teacher' : widget.initialRole;
    _isRegister = _role == 'student';
    _loadRemembered();
  }

  @override
  void dispose() {
    _userCtrl.dispose();
    _passCtrl.dispose();
    _studentIdCtrl.dispose();
    _fullNameCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadRemembered() async {
    final prefs = await SharedPreferences.getInstance();
    var savedRole = prefs.getString(_rememberRoleKey);
    if (savedRole == 'professor') savedRole = 'teacher';
    if (savedRole != _role) return;
    if (!mounted) return;
    setState(() {
      _rememberMe = true;
      _userCtrl.text = prefs.getString(_rememberUserKey) ?? '';
      _passCtrl.text = prefs.getString(_rememberPassKey) ?? '';
    });
  }

  Future<void> _saveRemembered() async {
    final prefs = await SharedPreferences.getInstance();
    if (_rememberMe) {
      await prefs.setString(_rememberRoleKey, _role);
      await prefs.setString(_rememberUserKey, _userCtrl.text.trim());
      await prefs.setString(_rememberPassKey, _passCtrl.text.trim());
      return;
    }
    await prefs.remove(_rememberRoleKey);
    await prefs.remove(_rememberUserKey);
    await prefs.remove(_rememberPassKey);
  }

  String? _studentDeviceLoginMessage(Object e) {
    final raw = e is PostgrestException ? e.message : e.toString();
    if (raw.contains('already signed in on another device')) {
      return 'Cannot sign in. This student account is already signed in on another device.';
    }
    if (raw.contains('already registered to another student')) {
      return 'Cannot sign in. This device is already registered to another student.';
    }
    if (raw.contains('not your registered device')) {
      return 'Cannot sign in. This is not your registered device.';
    }
    if (e is PostgrestException && e.code == 'PGRST202') {
      return 'Server is missing student device login. Run supabase/anti_proxy_device_security.sql.';
    }
    return null;
  }

  void _showMessage(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }

  Future<void> _submit() async {
    if (!await hasNetworkConnection()) {
      _showMessage(kNoInternetMessage);
      return;
    }

    setState(() => _loading = true);
    try {
      if (_role == 'student' && _isRegister) {
        final deviceInfo = await _ble.getAttendanceDeviceInfo();
        await _db.registerStudent(
          studentId: _studentIdCtrl.text,
          fullName: _fullNameCtrl.text,
          username: _userCtrl.text,
          password: _passCtrl.text,
          deviceUuid: deviceInfo.deviceUuid,
          deviceName: deviceInfo.deviceName,
        );
      }

      late final AppUser user;
      if (_role == 'student') {
        final identity = await _identity.getDeviceIdentity();
        final u = await _db.loginStudentWithDevice(
          username: _userCtrl.text,
          password: _passCtrl.text,
          identity: identity,
        );
        if (u == null) {
          throw Exception('Invalid credentials');
        }
        user = u;
        await _localSession.saveUserSession(user, identity);
      } else {
        final u = await _db.login(
          username: _userCtrl.text,
          password: _passCtrl.text,
          role: _role,
        );
        if (u == null) {
          throw Exception('Invalid credentials');
        }
        user = u;
      }

      await _saveRemembered();

      if (!mounted) return;
      if (_role == 'student') {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => StudentDashboardScreen(user: user)),
        );
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => TeacherDashboardScreen(user: user),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      final offline = networkErrorMessage(e);
      final mapped = offline ??
          (_role == 'student' ? _studentDeviceLoginMessage(e) : null);
      _showMessage(mapped ?? 'Auth failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String get _screenTitle {
    if (_role == 'teacher') return 'Teacher Login';
    return _isRegister ? 'Student Register' : 'Student Login';
  }

  @override
  Widget build(BuildContext context) {
    final pad = AppBreakpoints.horizontalPadding(context);
    final w = AppBreakpoints.width(context);
    final maxForm = math.min(440.0, w - pad * 2);
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    final themed = LandingAuthUi.authThemeOverlay(Theme.of(context));

    return Theme(
      data: themed,
      child: Scaffold(
        extendBodyBehindAppBar: true,
        resizeToAvoidBottomInset: false,
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text(_screenTitle),
        ),
        body: Stack(
          fit: StackFit.expand,
          children: [
            const CustomPaint(
              painter: _AuthBackdropPainter(),
              child: SizedBox.expand(),
            ),
            SafeArea(
              child: AnimatedPadding(
                duration: const Duration(milliseconds: 120),
                curve: Curves.easeOut,
                padding: EdgeInsets.only(bottom: inset),
                child: LayoutBuilder(
                  builder: (context, c) {
                    return SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(pad, 8, pad, 24),
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: maxForm),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const SizedBox(height: 8),
                              _RoleSegmentBar(
                                role: _role,
                                onChanged: (r) {
                                  setState(() {
                                    _role = r;
                                    if (_role == 'teacher') {
                                      _isRegister = false;
                                    }
                                  });
                                },
                              ),
                              const SizedBox(height: 20),
                              if (_role == 'student') ...[
                                _RegisterModeRow(
                                  value: _isRegister,
                                  onChanged: (v) =>
                                      setState(() => _isRegister = v),
                                ),
                                const SizedBox(height: 16),
                              ],
                              if (_role == 'student' && _isRegister) ...[
                                TextField(
                                  controller: _studentIdCtrl,
                                  textInputAction: TextInputAction.next,
                                  autofillHints: const [],
                                  enableSuggestions: false,
                                  decoration: const InputDecoration(
                                    labelText: 'Student ID',
                                    hintText: 'Enter student ID',
                                    prefixIcon: Icon(
                                      Icons.badge_outlined,
                                      color: LandingAuthUi.inputIconMuted,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                TextField(
                                  controller: _fullNameCtrl,
                                  textInputAction: TextInputAction.next,
                                  autofillHints: const [],
                                  enableSuggestions: false,
                                  decoration: const InputDecoration(
                                    labelText: 'Full Name',
                                    hintText: 'Enter full name',
                                    prefixIcon: Icon(
                                      Icons.person_outline_rounded,
                                      color: LandingAuthUi.inputIconMuted,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                              ],
                              TextField(
                                controller: _userCtrl,
                                textInputAction: TextInputAction.next,
                                autocorrect: false,
                                autofillHints: const [],
                                enableSuggestions: false,
                                decoration: const InputDecoration(
                                  labelText: 'Username',
                                  hintText: 'Enter username',
                                  prefixIcon: Icon(
                                    Icons.person_outline_rounded,
                                    color: LandingAuthUi.inputIconMuted,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: _passCtrl,
                                obscureText: _obscurePassword,
                                textInputAction: TextInputAction.done,
                                autofillHints: const [],
                                enableSuggestions: false,
                                onSubmitted: (_) {
                                  if (!_loading) _submit();
                                },
                                decoration: InputDecoration(
                                  labelText: 'Password',
                                  hintText: 'Enter password',
                                  prefixIcon: const Icon(
                                    Icons.lock_outline_rounded,
                                    color: LandingAuthUi.inputIconMuted,
                                  ),
                                  suffixIcon: IconButton(
                                    tooltip: _obscurePassword
                                        ? 'Show password'
                                        : 'Hide password',
                                    onPressed: () => setState(
                                      () => _obscurePassword = !_obscurePassword,
                                    ),
                                    icon: Icon(
                                      _obscurePassword
                                          ? Icons.visibility_outlined
                                          : Icons.visibility_off_outlined,
                                      color: LandingAuthUi.inputIconMuted,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              CheckboxListTile(
                                contentPadding: EdgeInsets.zero,
                                value: _rememberMe,
                                onChanged: (v) =>
                                    setState(() => _rememberMe = v ?? false),
                                title: const Text('Remember me'),
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                              ),
                              SizedBox(height: math.max(16.0, c.maxHeight * 0.02)),
                              _GradientCtaButton(
                                loading: _loading,
                                label: _isRegister
                                    ? 'Register & Login'
                                    : 'Login',
                                icon: _isRegister
                                    ? Icons.app_registration_rounded
                                    : Icons.login_rounded,
                                onPressed: _loading ? null : _submit,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoleSegmentBar extends StatelessWidget {
  const _RoleSegmentBar({
    required this.role,
    required this.onChanged,
  });

  final String role;
  final void Function(String role) onChanged;

  @override
  Widget build(BuildContext context) {
    final isStudent = role == 'student';
    return Row(
      children: [
        Expanded(
          child: _SegmentChip(
            label: 'Student',
            selected: isStudent,
            onTap: () => onChanged('student'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _SegmentChip(
            label: 'Teacher',
            selected: !isStudent,
            onTap: () => onChanged('teacher'),
          ),
        ),
      ],
    );
  }
}

class _SegmentChip extends StatelessWidget {
  const _SegmentChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: selected ? LandingAuthUi.segmentSelected : null,
            color: selected ? null : LandingAuthUi.surfaceMuted,
            border: Border.all(
              color: selected
                  ? Colors.transparent
                  : LandingAuthUi.borderSubtle,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: selected ? Colors.white : LandingAuthUi.textSecondary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RegisterModeRow extends StatelessWidget {
  const _RegisterModeRow({
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            'New student account',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.92),
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          thumbColor: const WidgetStatePropertyAll(Colors.white),
          trackColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return LandingAuthUi.teal.withValues(alpha: 0.55);
            }
            return LandingAuthUi.borderSubtle;
          }),
        ),
      ],
    );
  }
}

class _GradientCtaButton extends StatelessWidget {
  const _GradientCtaButton({
    required this.loading,
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final bool loading;
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null;
    return Opacity(
      opacity: disabled ? 0.55 : 1,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LandingAuthUi.primaryCta,
          boxShadow: [
            BoxShadow(
              color: LandingAuthUi.purple.withValues(alpha: 0.35),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (loading)
                    const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  else
                    Icon(icon, color: Colors.white, size: 22),
                  const SizedBox(width: 10),
                  Text(
                    loading ? 'Please wait…' : label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AuthBackdropPainter extends CustomPainter {
  const _AuthBackdropPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    final bg = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          LandingAuthUi.background,
          LandingAuthUi.backgroundMid,
          LandingAuthUi.background,
        ],
        stops: [0, 0.5, 1],
      ).createShader(r);
    canvas.drawRect(r, bg);

    final p = Paint()
      ..color = LandingAuthUi.purple.withValues(alpha: 0.06)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    for (var i = 0; i < 5; i++) {
      final path = Path();
      final y = size.height * (0.12 + i * 0.07);
      path.moveTo(0, y);
      for (double x = 0; x <= size.width; x += 8) {
        path.lineTo(
          x,
          y + math.sin(x / 48 + i) * 6,
        );
      }
      canvas.drawPath(path, p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
