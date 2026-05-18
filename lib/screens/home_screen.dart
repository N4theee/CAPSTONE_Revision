import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/supabase_service.dart';
import '../ui/landing_auth_ui.dart';
import '../ui/responsive.dart';
import '../util/network_connectivity.dart';
import 'admin_web_panel_screen.dart';
import 'auth_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _db = SupabaseService();
  final _adminUserCtrl = TextEditingController();
  final _adminPassCtrl = TextEditingController();

  @override
  void dispose() {
    _adminUserCtrl.dispose();
    _adminPassCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pad = AppBreakpoints.horizontalPadding(context);
    final w = AppBreakpoints.width(context);
    final maxContent = math.min(480.0, w - pad * 2);

    return Scaffold(
      backgroundColor: LandingAuthUi.background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const Positioned.fill(
            child: CustomPaint(painter: _LandingBackdropPainter()),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, c) {
                return SingleChildScrollView(
                  padding: EdgeInsets.symmetric(horizontal: pad, vertical: 12),
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: maxContent),
                      child: Column(
                        children: [
                          SizedBox(height: c.maxHeight * 0.04),
                          const _AttendximityHeroIcon(),
                          const SizedBox(height: 22),
                          const Text(
                            'Attendximity',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Proximity-based smart attendance system',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: LandingAuthUi.textSecondary.withValues(
                                alpha: 0.95,
                              ),
                              fontSize: 14,
                              height: 1.35,
                            ),
                          ),
                          SizedBox(height: math.max(28.0, c.maxHeight * 0.05)),
                          _GradientBorderRoleCard(
                            gradient: LandingAuthUi.teacherBorder,
                            icon: Icons.school_rounded,
                            title: 'I am a Teacher',
                            subtitle: 'Login and start attendance sessions',
                            onTap: () => _openAuth(role: 'teacher'),
                          ),
                          const SizedBox(height: 14),
                          _GradientBorderRoleCard(
                            gradient: LandingAuthUi.studentBorder,
                            icon: Icons.person_rounded,
                            title: 'I am a Student',
                            subtitle: 'Register/Login and mark attendance',
                            onTap: () => _openAuth(role: 'student'),
                          ),
                          if (kIsWeb) ...[
                            const SizedBox(height: 14),
                            _GradientBorderRoleCard(
                              gradient: const LinearGradient(
                                colors: [
                                  Color(0xFF8B5CF6),
                                  Color(0xFF6B21A8),
                                ],
                              ),
                              icon: Icons.admin_panel_settings_rounded,
                              title: 'Admin Panel (Web)',
                              subtitle: 'Create teacher accounts',
                              onTap: _openAdminLogin,
                            ),
                          ],
                          const SizedBox(height: 32),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _openAuth({required String role}) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AuthScreen(initialRole: role)),
    );
  }

  Future<void> _openAdminLogin() async {
    final themed = LandingAuthUi.authThemeOverlay(Theme.of(context));
    final ok = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      backgroundColor: LandingAuthUi.surface,
      builder: (ctx) => Theme(
        data: themed,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Admin Login',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _adminUserCtrl,
                decoration: const InputDecoration(labelText: 'Username'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _adminPassCtrl,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Password'),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () async {
                  if (!await hasNetworkConnection()) {
                    if (!ctx.mounted) return;
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(content: Text(kNoInternetMessage)),
                    );
                    return;
                  }
                  try {
                    final user = await _db.login(
                      username: _adminUserCtrl.text.trim(),
                      password: _adminPassCtrl.text.trim(),
                      role: 'admin',
                    );
                    if (!ctx.mounted) return;
                    Navigator.pop(ctx, user != null && user.role == 'admin');
                  } catch (e) {
                    if (!ctx.mounted) return;
                    final msg = networkErrorMessage(e);
                    if (msg != null) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        SnackBar(content: Text(msg)),
                      );
                    } else {
                      Navigator.pop(ctx, false);
                    }
                  }
                },
                child: const Text('Login'),
              ),
            ],
          ),
        ),
      ),
    );

    if (!mounted) return;
    if (ok != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid admin credentials.')),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AdminWebPanelScreen()),
    );
  }
}

class _AttendximityHeroIcon extends StatelessWidget {
  const _AttendximityHeroIcon();

  @override
  Widget build(BuildContext context) {
    final sz = (AppBreakpoints.width(context) * 0.22).clamp(72.0, 108.0);
    return SizedBox(
      width: sz + 32,
      height: sz + 32,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: sz + 28,
            height: sz + 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: LandingAuthUi.purple.withValues(alpha: 0.35),
                width: 2,
              ),
            ),
          ),
          Container(
            width: sz + 8,
            height: sz + 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: LandingAuthUi.teal.withValues(alpha: 0.45),
                width: 2,
              ),
            ),
          ),
          Container(
            width: sz * 0.55,
            height: sz * 0.55,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  LandingAuthUi.teal.withValues(alpha: 0.35),
                  LandingAuthUi.purple.withValues(alpha: 0.2),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: LandingAuthUi.teal.withValues(alpha: 0.35),
                  blurRadius: 18,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Icon(
              Icons.wifi_tethering_rounded,
              color: Colors.white.withValues(alpha: 0.95),
              size: sz * 0.28,
            ),
          ),
        ],
      ),
    );
  }
}

class _GradientBorderRoleCard extends StatelessWidget {
  const _GradientBorderRoleCard({
    required this.gradient,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final LinearGradient gradient;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: gradient,
            boxShadow: [
              BoxShadow(
                color: LandingAuthUi.teal.withValues(alpha: 0.12),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(1.6),
            child: Ink(
              decoration: BoxDecoration(
                color: LandingAuthUi.surface.withValues(alpha: 0.88),
                borderRadius: BorderRadius.circular(16.4),
              ),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: LandingAuthUi.surfaceMuted,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: LandingAuthUi.borderSubtle,
                        ),
                      ),
                      child: Icon(icon, color: Colors.white, size: 26),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            subtitle,
                            style: TextStyle(
                              fontSize: 12,
                              color: LandingAuthUi.textSecondary
                                  .withValues(alpha: 0.95),
                              height: 1.3,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: LandingAuthUi.textSecondary,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LandingBackdropPainter extends CustomPainter {
  const _LandingBackdropPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final bg = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          LandingAuthUi.background,
          LandingAuthUi.backgroundMid,
          LandingAuthUi.background,
        ],
        stops: [0, 0.45, 1],
      ).createShader(rect);
    canvas.drawRect(rect, bg);

    final wavePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    for (var i = 0; i < 4; i++) {
      final t = i / 3;
      wavePaint.shader = LinearGradient(
        colors: [
          LandingAuthUi.teal.withValues(alpha: 0.15 + t * 0.12),
          LandingAuthUi.purple.withValues(alpha: 0.12 + t * 0.1),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height * 0.45));

      final path = Path();
      final yBase = size.height * (0.08 + i * 0.045);
      path.moveTo(0, yBase);
      for (double x = 0; x <= size.width; x += 6) {
        final y = yBase +
            math.sin((x / size.width) * math.pi * 3 + i * 0.8) * (10 + i * 3);
        path.lineTo(x, y);
      }
      canvas.drawPath(path, wavePaint);
    }

    final dotPaint = Paint()
      ..color = LandingAuthUi.teal.withValues(alpha: 0.08)
      ..style = PaintingStyle.fill;
    const step = 18.0;
    final startY = size.height * 0.62;
    for (double y = startY; y < size.height; y += step) {
      for (double x = 0; x < size.width; x += step) {
        if (((x ~/ step) + (y ~/ step)) % 2 == 0) {
          canvas.drawCircle(Offset(x, y), 1.2, dotPaint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
