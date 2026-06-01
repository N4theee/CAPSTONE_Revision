import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/device_identity_service.dart';
import '../services/local_session_service.dart';
import '../services/supabase_service.dart';
import '../ui/responsive.dart';
import '../ui/student_attendance_ui.dart';
import '../widgets/course_dashboard_card.dart';
import 'home_screen.dart';
import 'student_history_screen.dart';
import 'student_subject_details_screen.dart';

class StudentDashboardScreen extends StatefulWidget {
  const StudentDashboardScreen({super.key, required this.user});

  final AppUser user;

  @override
  State<StudentDashboardScreen> createState() => _StudentDashboardScreenState();
}

class _StudentDashboardScreenState extends State<StudentDashboardScreen>
    with WidgetsBindingObserver {
  final _db = SupabaseService();
  final _identity = DeviceIdentityService();
  final _local = LocalSessionService();
  bool _loading = true;
  List<SubjectOffering> _offerings = [];
  Map<String, int> _enrollmentByOffering = {};
  StreamSubscription<List<SessionNotificationItem>>? _notificationSub;
  final List<SessionNotificationItem> _notifications = [];
  late String _displayName;
  StudentActiveSessionStatus? _sessionGate;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _displayName = widget.user.fullName;
    _load();
    _listenForRealtimeNotifications();
    _refreshSessionGate();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshSessionGate());
    }
  }

  Future<void> _refreshSessionGate() async {
    try {
      final s = await _db.getStudentActiveSessionStatus(widget.user.linkedId);
      if (mounted) setState(() => _sessionGate = s);
    } catch (_) {
      if (mounted) setState(() => _sessionGate = null);
    }
  }

  bool get _logoutBlocked => _sessionGate?.hasActiveSession == true;

  Future<void> _load() async {
    final rows = await _db.getStudentOfferings(widget.user.linkedId);
    final counts = await _db.getEnrollmentCountsForOfferings(
      rows.map((e) => e.id).toList(),
    );
    if (mounted) {
      setState(() {
        _offerings = rows;
        _enrollmentByOffering = counts;
        _loading = false;
      });
    }
  }

  void _listenForRealtimeNotifications() {
    _notificationSub = _db
        .watchStudentSessionNotifications(widget.user.linkedId)
        .listen((items) {
          if (!mounted || items.isEmpty) return;

          final existingIds = _notifications.map((n) => n.sessionId).toSet();
          final newlyAdded = <SessionNotificationItem>[];

          for (final item in items) {
            if (existingIds.contains(item.sessionId)) continue;
            _notifications.insert(0, item);
            newlyAdded.add(item);
          }

          if (newlyAdded.isEmpty || !mounted) return;

          setState(() {});

          // Show a lightweight in-app popup for the most recent new session.
          final latest = newlyAdded.first;
          final subjectLabel =
              '${latest.subjectCode} - ${latest.subjectTitle} (Section ${latest.section})';

          // Delay slightly to avoid ScaffoldMessenger lookup issues during build.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(
                SnackBar(
                  behavior: SnackBarBehavior.floating,
                  backgroundColor: const Color(0xFF0F766E),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'New attendance session started',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subjectLabel,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Teacher ${latest.teacherName}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                  duration: const Duration(seconds: 6),
                  action: SnackBarAction(
                    label: 'VIEW',
                    textColor: Colors.white,
                    onPressed: _openNotifications,
                  ),
                ),
              );
          });
        });
  }

  void _openNotifications() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        if (_notifications.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: SizedBox(
              height: 80,
              child: Center(child: Text('No notifications yet.')),
            ),
          );
        }
        final h = MediaQuery.sizeOf(ctx).height * 0.55;
        return SizedBox(
          height: h,
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemBuilder: (_, i) {
              final n = _notifications[i];
              final hh = n.startedAt.hour.toString().padLeft(2, '0');
              final mm = n.startedAt.minute.toString().padLeft(2, '0');
              return ListTile(
                leading: const Icon(Icons.campaign_outlined),
                title: Text('${n.subjectCode} - ${n.subjectTitle}'),
                subtitle: Text('Section ${n.section} • ${n.teacherName}'),
                trailing: Text('$hh:$mm'),
              );
            },
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemCount: _notifications.length,
          ),
        );
      },
    );
  }

  Future<void> _editName() async {
    final ctrl = TextEditingController(text: _displayName);
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Student Name'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(labelText: 'Full Name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (value == null || value.isEmpty || value == _displayName) return;
    await _db.updateDisplayName(
      role: 'student',
      linkedId: widget.user.linkedId,
      fullName: value,
    );
    if (!mounted) return;
    setState(() => _displayName = value);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Name updated.')));
  }

  Future<void> _signOut() async {
    if (_logoutBlocked) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Session is active, cannot logout.')),
      );
      return;
    }

    try {
      final identity = await _identity.getDeviceIdentity();
      await _db.signOutStudentDevice(
        studentId: widget.user.linkedId,
        identity: identity,
      );
    } on PostgrestException catch (e) {
      if (!mounted) return;
      if (e.message.contains('Session is active')) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Session is active, cannot logout.')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sign out failed: ${e.message}')),
        );
      }
      return;
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sign out failed: $e')),
      );
      return;
    }

    await _local.clearUserSession();
    _identity.clearCache();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const HomeScreen()),
      (_) => false,
    );
  }

  void _openHistory() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StudentHistoryScreen(studentId: widget.user.linkedId),
      ),
    );
  }

  Widget _buildHeader() {
    final iconColor = Colors.white.withValues(alpha: 0.95);
    final compact = AppBreakpoints.useCompactDashboardActions(context);

    final brand = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.wifi_tethering, color: iconColor, size: 26),
        const SizedBox(width: 8),
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: const Text(
              'Attendximity',
              maxLines: 1,
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 20,
                letterSpacing: -0.5,
              ),
            ),
          ),
        ),
      ],
    );

    if (compact) {
      return Row(
        children: [
          Expanded(child: brand),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert_rounded, color: iconColor),
            color: const Color.fromARGB(255, 82, 189, 182),
            onSelected: (v) {
              if (v == 'notifications') {
                _openNotifications();
              } else if (v == 'edit') {
                _editName();
              } else if (v == 'refresh' && !_loading) {
                _load();
              } else if (v == 'history') {
                _openHistory();
              } else if (v == 'logout') {
                if (_logoutBlocked) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Session is active, cannot logout.'),
                    ),
                  );
                } else {
                  _signOut();
                }
              }
            },
            itemBuilder: (ctx) => [
              PopupMenuItem(
                value: 'notifications',
                child: Text(
                  _notifications.isEmpty
                      ? 'Notifications'
                      : 'Notifications (${_notifications.length})',
                ),
              ),
              const PopupMenuItem(value: 'edit', child: Text('Edit name')),
              PopupMenuItem(
                value: 'refresh',
                enabled: !_loading,
                child: const Text('Refresh'),
              ),
              const PopupMenuItem(
                value: 'history',
                child: Text('Attendance history'),
              ),
              PopupMenuItem(
                value: 'logout',
                child: Text(
                  _logoutBlocked ? 'Sign out (session active)' : 'Sign out',
                ),
              ),
            ],
          ),
        ],
      );
    }

    return Row(
      children: [
        Expanded(child: brand),
        IconButton(
          tooltip: 'Notifications',
          onPressed: _openNotifications,
          icon: Badge(
            isLabelVisible: _notifications.isNotEmpty,
            label: Text('${_notifications.length}'),
            child: Icon(Icons.notifications_none_rounded, color: iconColor),
          ),
        ),
        IconButton(
          tooltip: 'Edit Name',
          onPressed: _editName,
          icon: Icon(Icons.edit_outlined, color: iconColor),
        ),
        IconButton(
          tooltip: 'Refresh',
          onPressed: _loading ? null : _load,
          icon: Icon(Icons.refresh_rounded, color: iconColor),
        ),
        IconButton(
          tooltip: 'Attendance History',
          onPressed: _openHistory,
          icon: Icon(Icons.history_rounded, color: iconColor),
        ),
        IconButton(
          tooltip: 'Sign out',
          onPressed: _logoutBlocked ? () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Session is active, cannot logout.')),
            );
          } : _signOut,
          icon: Icon(
            Icons.logout_rounded,
            color: _logoutBlocked ? Colors.white38 : iconColor,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final pad = AppBreakpoints.horizontalPadding(context);
    final cols = AppBreakpoints.courseGridColumns(context);
    final aspect = AppBreakpoints.courseGridChildAspectRatio(context, cols);
    final w = AppBreakpoints.width(context);
    final markSize = (w * 0.28).clamp(72.0, 120.0);

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              StudentAttendanceUi.dashboardGradientTop,
              StudentAttendanceUi.dashboardGradientBottom,
            ],
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              Positioned(
                left: 0,
                right: 0,
                bottom: -20,
                child: IgnorePointer(
                  child: Text(
                    'ATX',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Sceageus',
                      fontSize: markSize,
                      fontWeight: FontWeight.w900,
                      height: 0.85,
                      color: Colors.white.withValues(alpha: 0.07),
                    ),
                  ),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: pad, vertical: 8),
                    child: _buildHeader(),
                  ),
                  Expanded(
                    child: _loading
                        ? const Center(
                            child: CircularProgressIndicator(
                              color: StudentAttendanceUi.mint,
                            ),
                          )
                        : RefreshIndicator(
                            color: StudentAttendanceUi.dashboardGradientTop,
                            onRefresh: _load,
                            child: _offerings.isEmpty
                                ? ListView(
                                    physics:
                                        const AlwaysScrollableScrollPhysics(),
                                    children: const [
                                      SizedBox(height: 120),
                                      Center(
                                        child: Text(
                                          'No enrolled courses yet.',
                                          style: TextStyle(
                                            color: Colors.white70,
                                            fontSize: 16,
                                          ),
                                        ),
                                      ),
                                    ],
                                  )
                                : GridView.builder(
                                    padding: EdgeInsets.fromLTRB(
                                      pad,
                                      8,
                                      pad,
                                      32,
                                    ),
                                    physics:
                                        const AlwaysScrollableScrollPhysics(),
                                    gridDelegate:
                                        SliverGridDelegateWithFixedCrossAxisCount(
                                          crossAxisCount: cols,
                                          mainAxisSpacing: 14,
                                          crossAxisSpacing: 14,
                                          childAspectRatio: aspect,
                                        ),
                                    itemCount: _offerings.length,
                                    itemBuilder: (_, i) {
                                      final o = _offerings[i];
                                      final n =
                                          _enrollmentByOffering[o.id] ?? 0;
                                      return CourseDashboardCard(
                                        title:
                                            '${o.subjectCode} - ${o.subjectTitle}',
                                        sectionLine: 'Section ${o.section}',
                                        footerLine:
                                            '$n ${n == 1 ? 'student' : 'students'}',
                                        cardTop: StudentAttendanceUi.dashboardCardTop,
                                        cardTopBorder:
                                            StudentAttendanceUi.dashboardCardBorder,
                                        footerBar:
                                            StudentAttendanceUi.dashboardFooterBar,
                                        footerText: Colors.white,
                                        chevron: Colors.white,
                                        onTap: () async {
                                          await Navigator.push<void>(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  StudentSubjectDetailsScreen(
                                                studentId: widget.user.linkedId,
                                                studentName: _displayName,
                                                offering: o,
                                              ),
                                            ),
                                          );
                                          if (mounted) await _refreshSessionGate();
                                        },
                                      );
                                    },
                                  ),
                          ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _notificationSub?.cancel();
    super.dispose();
  }
}
