import 'package:flutter/material.dart';

import '../services/supabase_service.dart';
import '../services/exam_beacon_service.dart';
import '../ui/responsive.dart';
import '../ui/adaptive_layout.dart';
import '../widgets/course_dashboard_card.dart';
import '../widgets/proxamity_mark.dart';
import 'home_screen.dart';
import 'teacher_subject_details_screen.dart';

class TeacherDashboardScreen extends StatefulWidget {
  const TeacherDashboardScreen({super.key, required this.user});

  final AppUser user;

  @override
  State<TeacherDashboardScreen> createState() => _TeacherDashboardScreenState();
}

class _TeacherDashboardScreenState extends State<TeacherDashboardScreen> {
  final _db = SupabaseService();
  bool _loading = true;
  bool _loadFailed = false;
  List<SubjectOffering> _offerings = [];
  Map<String, int> _enrollmentByOffering = {};
  late String _displayName;

  static const _gradientTop = Color(0xFF3B5BDB);
  static const _gradientBottom = Color(0xFF5B21B6);
  static const _cardTop = Color(0xFF7C3AED);
  static const _cardTopBorder = Color(0xFFA78BFA);

  @override
  void initState() {
    super.initState();
    _displayName = widget.user.fullName;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    try {
      final rows = await _db.getTeacherOfferings(widget.user.linkedId);
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
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadFailed = true;
        });
      }
    }
  }

  Future<void> _editName() async {
    final ctrl = TextEditingController(text: _displayName);
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Teacher Name'),
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
      role: 'teacher',
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
    await ExamBeaconService().stop();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const HomeScreen()),
      (_) => false,
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
              'Proxamity',
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
            color: const Color.fromARGB(255, 111, 105, 196),
            onSelected: (v) {
              if (v == 'edit') {
                _editName();
              } else if (v == 'refresh' && !_loading) {
                _load();
              } else if (v == 'logout') {
                _signOut();
              }
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(value: 'edit', child: Text('Edit name')),
              PopupMenuItem(
                value: 'refresh',
                enabled: !_loading,
                child: const Text('Refresh'),
              ),
              const PopupMenuItem(value: 'logout', child: Text('Sign out')),
            ],
          ),
        ],
      );
    }

    return Row(
      children: [
        Expanded(child: brand),
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
          tooltip: 'Sign out',
          onPressed: _signOut,
          icon: Icon(Icons.logout_rounded, color: iconColor),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final pad = AppBreakpoints.horizontalPadding(context);
    final w = AppBreakpoints.width(context);
    final markSize = (w * 0.28).clamp(72.0, 120.0);

    return Scaffold(
      body: ResponsivePage(
        maxWidth: 1200,
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [_gradientTop, _gradientBottom],
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
                    child: Center(
                      child: ProxamityMark(
                        width: markSize * 2,
                        color: Colors.white.withValues(alpha: 0.07),
                      ),
                    ),
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: pad,
                        vertical: 8,
                      ),
                      child: _buildHeader(),
                    ),
                    Expanded(
                      child: _loading
                          ? const Center(
                              child: CircularProgressIndicator(
                                color: Colors.white,
                              ),
                            )
                          : RefreshIndicator(
                              color: _gradientTop,
                              onRefresh: _load,
                              child: _loadFailed
                                  ? LoadError(
                                      message: 'Could not load your courses.',
                                      onRetry: _load,
                                    )
                                  : _offerings.isEmpty
                                  ? ListView(
                                      physics:
                                          const AlwaysScrollableScrollPhysics(),
                                      children: const [
                                        SizedBox(height: 120),
                                        Center(
                                          child: Text(
                                            'No courses yet.',
                                            style: TextStyle(
                                              color: Colors.white70,
                                              fontSize: 16,
                                            ),
                                          ),
                                        ),
                                      ],
                                    )
                                  : ResponsiveCourseGrid(
                                      padding: EdgeInsets.fromLTRB(
                                        pad,
                                        8,
                                        pad,
                                        32,
                                      ),
                                      physics:
                                          const AlwaysScrollableScrollPhysics(),
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
                                          cardTop: _cardTop,
                                          cardTopBorder: _cardTopBorder,
                                          footerBar: Colors.black,
                                          footerText: Colors.white,
                                          chevron: Colors.white,
                                          onTap: () {
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) =>
                                                    TeacherSubjectDetailsScreen(
                                                      teacherName: _displayName,
                                                      offering: o,
                                                    ),
                                              ),
                                            );
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
      ),
    );
  }
}
