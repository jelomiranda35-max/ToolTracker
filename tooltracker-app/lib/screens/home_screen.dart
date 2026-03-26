import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:provider/provider.dart';
import '../services/sync_service.dart';
import '../database/db_helper.dart';
import '../services/api_service.dart';
import '../models/instrument.dart';
import '../models/dispatch.dart';
import 'scanner_screen.dart';
import 'login_screen.dart';
import 'return_scanner_screen.dart';
import 'dart:async';
import 'dispatch_export_screen.dart';
import 'dart:io';
import 'dart:math' as math;
import 'instruments_tab.dart';
import 'student_borrow_screen.dart';
import '../theme/app_theme.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late TabController _tabController;
  final GlobalKey<InstrumentsTabState> _instrumentsTabKey =
      GlobalKey<InstrumentsTabState>();

  String _userName = '';
  String _userRole = '';
  String _username = '';
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _isSyncing = false;
  int _totalNotifCount = 0;
  bool _isConnected = false;

  List<Dispatch> _activeDispatches = [];
  Map<String, List<dynamic>> _activeDispatchItems = {};
  int _totalInstruments = 0;
  int _availableCount = 0;
  int _inUseCount = 0;
  List<Map<String, dynamic>> _unreadMessages = [];
  List<Map<String, dynamic>> _unshownAlerts = [];
  int _currentTabIndex = 0;

  // ── Collapsible top panel ──
  bool _topPanelCollapsed = false;
  late AnimationController _collapseAnimController;
  late Animation<double> _collapseAnimation;

  // ── Logo Z-flip (theme switcher) ──────────────────────────────────────────
  late AnimationController _flipController;
  bool _hasSwitchedTheme = false;
  late Animation<double> _flipAnimation;
  bool _isFlipping = false;
  // Frozen snapshot of the icon to show during this flip — captured BEFORE
  // the animation starts so it never changes mid-spin when the theme switches.
  IconData _pendingModeIcon = Icons.light_mode;

  // ── Easter egg ──
  int _logoTapCount = 0;
  bool _easterEggActive = false;
  Offset _logoPosition = Offset.zero;
  Offset _logoVelocity = Offset.zero;
  StreamSubscription? _accelSub;
  Timer? _physicsTimer;
  bool _snapping = false;
  bool _showCredit = false;
  double _creditOpacity = 0.0;
  late AnimationController _snapAnimController;
  late Animation<Offset> _snapAnimation;
  static const double _logoSize = 88.0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) return;
      if (_tabController.index == 1) {
        _instrumentsTabKey.currentState?.reload();
      }
      if (_tabController.index == 2) {
        setState(() {});
      }
    });
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) return;
      setState(() => _currentTabIndex = _tabController.index);
    });

    _loadUser();
    _loadDashboard();
    WidgetsBinding.instance.addObserver(this);

    _collapseAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _collapseAnimation = CurvedAnimation(
      parent: _collapseAnimController,
      curve: Curves.easeInOut,
    );

// ── Flip animation controller — full 360° coin spin ──────────────────────
_flipController = AnimationController(
  vsync: this,
  duration: const Duration(milliseconds: 1400),
);
// Maps 0→1 to 0→2π (full circle)
_flipAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
  CurvedAnimation(parent: _flipController, curve: Curves.easeInOut),
);

// Switch theme at exactly the 50% midpoint — logo is edge-on and invisible
_flipController.addListener(() {
  if (!_hasSwitchedTheme && _flipController.value >= 0.5) {
    _hasSwitchedTheme = true;
    Provider.of<ThemeNotifier>(context, listen: false).nextMode();
  }
});

    _snapAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _snapAnimation =
        Tween<Offset>(begin: Offset.zero, end: Offset.zero).animate(
      CurvedAnimation(
          parent: _snapAnimController, curve: Curves.elasticOut),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      checkOverdueAlerts(
        context,
        onViewOverdue: () {
          _tabController.animateTo(1);
          _instrumentsTabKey.currentState?.activateOverdueFilter();
        },
        onViewUpcoming: () {
          _tabController.animateTo(1);
          _instrumentsTabKey.currentState?.activateUpcomingFilter();
        },
      );
    });
  }

  bool _cameraActive = false;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _cameraActive = true;
    }
    if (state == AppLifecycleState.resumed && !_cameraActive) {
      _loadDashboard();
    }
    if (state == AppLifecycleState.resumed) {
      _cameraActive = false;
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _collapseAnimController.dispose();
    _flipController.dispose();
    _accelSub?.cancel();
    _physicsTimer?.cancel();
    _snapAnimController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // ── Logo Z-axis flip → cycle theme ───────────────────────────────────────

  void _onLogoFlip() async {
    if (_easterEggActive || _isFlipping) return;

    _logoTapCount++;
    if (_logoTapCount >= 11) {
      _logoTapCount = 0;
      _activateEasterEgg();
      return;
    }

    final themeNotifier = Provider.of<ThemeNotifier>(context, listen: false);

    // ── Snapshot the icon for the mode we're switching TO right now,
    //    BEFORE the animation starts. This freezes the icon for the entire
    //    spin so it never flickers when nextMode() fires at the midpoint.
    _pendingModeIcon = _getNextModeIcon(context);

    _isFlipping = true;
    _hasSwitchedTheme = false;
    _flipController.reset();
    await _flipController.forward();
    if (!mounted) return;

    // Show mode name as fading overlay text instead of snackbar
    _showThemeToast('${themeNotifier.modeName} mode');

    _isFlipping = false;
  }

  void _showThemeToast(String message) {
    final overlay = Overlay.of(context);
    late OverlayEntry entry;
    entry = OverlayEntry(builder: (_) => _ThemeToast(
      message: message,
      onDone: () => entry.remove(),
    ));
    overlay.insert(entry);
  }

  // ── Collapse / expand top panel ───────────────────────────────────────────

  void _toggleTopPanel() {
    setState(() => _topPanelCollapsed = !_topPanelCollapsed);
    if (_topPanelCollapsed) {
      _collapseAnimController.forward();
    } else {
      _collapseAnimController.reverse();
    }
  }

  // ─── Easter egg ─────────────────────────────────────────────────────────────

  void _activateEasterEgg() {
    setState(() {
      _easterEggActive = true;
      _logoPosition = Offset.zero;
      _logoVelocity = Offset.zero;
      _snapping = false;
    });
    _startPhysics();
  }

  void _startPhysics() {
    _accelSub?.cancel();
    _physicsTimer?.cancel();

    _physicsTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (!mounted || !_easterEggActive || _snapping) return;
      final size = MediaQuery.of(context).size;
      final maxX = size.width / 2 - _logoSize / 2 - 8;
      final maxY = size.height / 2 - _logoSize / 2 - 80;
      setState(() {
        _logoPosition = Offset(
          _logoPosition.dx + _logoVelocity.dx,
          _logoPosition.dy + _logoVelocity.dy,
        );
        if (_logoPosition.dx.abs() > maxX) {
          _logoPosition =
              Offset(_logoPosition.dx.sign * maxX, _logoPosition.dy);
          _logoVelocity =
              Offset(-_logoVelocity.dx * 0.6, _logoVelocity.dy);
        }
        if (_logoPosition.dy.abs() > maxY) {
          _logoPosition =
              Offset(_logoPosition.dx, _logoPosition.dy.sign * maxY);
          _logoVelocity =
              Offset(_logoVelocity.dx, -_logoVelocity.dy * 0.6);
        }
        _logoVelocity = _logoVelocity * 0.97;
      });
    });

    _accelSub = accelerometerEventStream().listen((event) {
      if (!_easterEggActive || _snapping) return;
      final mag =
          event.x * event.x + event.y * event.y + event.z * event.z;
      if (mag > 400) {
        _resetEasterEgg();
        return;
      }
      setState(() {
        _logoVelocity = Offset(
          (_logoVelocity.dx + (-event.x * 0.18)).clamp(-14.0, 14.0),
          (_logoVelocity.dy + (event.y * 0.18)).clamp(-14.0, 14.0),
        );
      });
    });
  }

  void _resetEasterEgg() {
    if (_snapping) return;
    _accelSub?.cancel();
    _physicsTimer?.cancel();
    setState(() => _snapping = true);

    _snapAnimation = Tween<Offset>(
      begin: _logoPosition,
      end: Offset.zero,
    ).animate(CurvedAnimation(
        parent: _snapAnimController, curve: Curves.elasticOut));

    _snapAnimController.forward(from: 0).then((_) {
      if (!mounted) return;
      setState(() {
        _easterEggActive = false;
        _snapping = false;
        _logoPosition = Offset.zero;
        _logoVelocity = Offset.zero;
        _showCredit = true;
        _creditOpacity = 0.0;
      });
      _animateCredit();
    });
  }

  Future<void> _animateCredit() async {
    for (double v = 0; v <= 1.0; v += 0.05) {
      await Future.delayed(const Duration(milliseconds: 25));
      if (!mounted) return;
      setState(() => _creditOpacity = v.clamp(0.0, 1.0));
    }
    await Future.delayed(const Duration(seconds: 3));
    for (double v = 1.0; v >= 0; v -= 0.05) {
      await Future.delayed(const Duration(milliseconds: 25));
      if (!mounted) return;
      setState(() => _creditOpacity = v.clamp(0.0, 1.0));
    }
    if (mounted) setState(() => _showCredit = false);
  }

  // ─── Dashboard ───────────────────────────────────────────────────────────────

  Future<void> _loadUser() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _userName = prefs.getString('user_name') ?? 'User';
      _userRole = prefs.getString('user_role') ?? 'staff';
      _username = prefs.getString('username') ?? '';
    });
  }

  Future<void> _loadDashboard() async {
    final connected = await SyncService.isConnected();

    if (connected) {
      try {
        await SyncService.instance
            .syncAll()
            .timeout(const Duration(seconds: 15));
      } catch (_) {}
    }

    // Fetch unread messages from server and store locally
    if (connected) {
      try {
        final msgs = await ApiService.getUnreadMessages();
        if (msgs != null) {
          await DBHelper.instance.insertMessages(
              msgs.map((m) => Map<String, dynamic>.from(m)).toList());
        }
      } catch (_) {}
    }

    // Load unread messages and unshown alerts from local DB
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt('user_id') ?? 0;
    final unread = await DBHelper.instance.getUnreadMessages(userId);
    final alerts = await DBHelper.instance.getUnshownInstrumentAlerts();
    if (mounted && unread.isNotEmpty) {
      setState(() => _unreadMessages = unread);
      WidgetsBinding.instance.addPostFrameCallback(
          (_) => _showMessageFlash());
    }
    if (mounted && alerts.isNotEmpty) {
      setState(() => _unshownAlerts = alerts);
      WidgetsBinding.instance.addPostFrameCallback(
          (_) => _showNewInstrumentAlerts());
    }

    final instruments = await DBHelper.instance.getAllInstruments();
    final dispatches = await DBHelper.instance.getAllDispatches();

    final List<Dispatch> activeDispatches = [];
    final Map<String, List<dynamic>> activeDispatchItems = {};

    for (final d in dispatches) {
      if (d.dateIn == null && !d.isStudent) {
        activeDispatches.add(d);
        if (d.id != null) {
          final items = await DBHelper.instance.getDispatchItems(d.id!);
          activeDispatchItems[d.dispatchNo] = items;
        }
      }
    }

    if (mounted) {
      setState(() {
        _isConnected = connected;
        _totalInstruments = instruments.length;
        _availableCount =
            instruments.where((i) => i.status == 'Available').length;
        _inUseCount =
            instruments.where((i) => i.status == 'In Use').length;
        _activeDispatches = activeDispatches;
        _activeDispatchItems = activeDispatchItems;
        _isSyncing = false;
      });
    }
    final condemnCount = await DBHelper.instance.getPendingCondemnCount();
    final allInstruments = await DBHelper.instance.getAllInstruments();
    final allDispatches = await DBHelper.instance.getAllDispatches();
    final overdueCount = allInstruments.where((i) => i.isOverdue).length;
    final repairCount = allInstruments.where((i) => i.currentCondition == 'For Repair').length;
    final condemnCount2 = allInstruments.where((i) => i.currentCondition == 'Condemning').length;
    final calibrationOverdueCount = allInstruments.where((i) => i.isCalibrationOverdue).length;
    final overdueDispCount = allDispatches.where((d) => d.dateIn == null && !d.isStudent).length;
    final unreadCount = _unreadMessages.length;
    final total = condemnCount + overdueCount + repairCount + condemnCount2 + calibrationOverdueCount + overdueDispCount + unreadCount;
    if (mounted) setState(() {
      _totalNotifCount = total;
    });
  }

  bool _messageFlashShown = false;

  void _showMessageFlash() async {
    if (_unreadMessages.isEmpty) return;
    if (!mounted) return;
    if (_messageFlashShown) return;
    _messageFlashShown = true;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A3A5C),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFF5A623).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.message, color: Color(0xFFF5A623), size: 22),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${_unreadMessages.length} New Message${_unreadMessages.length > 1 ? 's' : ''} from Admin',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.bold),
            ),
          ),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: _unreadMessages.take(3).map((msg) => Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF0D1B2A),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: const Color(0xFFF5A623).withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(msg['from_admin_name'] ?? 'Admin',
                    style: const TextStyle(
                        color: Color(0xFFF5A623),
                        fontSize: 11,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(msg['message'] ?? '',
                    style: const TextStyle(
                        color: Colors.white, fontSize: 13),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          )).toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Later',
                style: TextStyle(color: Colors.white38)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _showMessageInbox();
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF5A623),
                foregroundColor: Colors.black),
            child: const Text('READ NOW',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showNewInstrumentAlerts() async {
    if (_unshownAlerts.isEmpty) return;
    final alert = _unshownAlerts.first;
    if (!mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A3A5C),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.add_box, color: Colors.green, size: 22),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text('New Instrument Added',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.bold)),
          ),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(alert['instrument_name'] ?? '',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15)),
                  const SizedBox(height: 4),
                  Text('Code: ${alert['instrument_code'] ?? ''}',
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 12)),
                  if ((alert['serial_number'] ?? '').toString().isNotEmpty)
                    Text('S/N: ${alert['serial_number']}',
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(height: 10),
            const Text('This instrument is now available in the system.',
                style: TextStyle(color: Colors.white54, fontSize: 12)),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () async {
              await DBHelper.instance
                  .markInstrumentAlertShown(alert['id'] as int);
              if (!mounted) return;
              Navigator.pop(context);
              setState(() => _unshownAlerts.removeAt(0));
              if (_unshownAlerts.isNotEmpty) _showNewInstrumentAlerts();
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  void _showMessageInbox() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt('user_id') ?? 0;
    // Load ALL messages (read + unread) for full history
    final allMessages = await DBHelper.instance.getAllMessages(userId);
    final unread = await DBHelper.instance.getUnreadMessages(userId);
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A3A5C),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      isScrollControlled: true,
      builder: (_) => _MessageInboxSheet(
        allMessages: allMessages,
        unreadMessages: unread,
        onMarkRead: (serverId) async {
          await ApiService.markMessageRead(serverId);
          await DBHelper.instance.markMessageRead(serverId);
          if (mounted) {
            final userId2 = prefs.getInt('user_id') ?? 0;
            final updated = await DBHelper.instance.getUnreadMessages(userId2);
            setState(() {
              _unreadMessages = updated;
              _messageFlashShown = false;
            });
          }
        },
      ),
    );
  }
          

  void _showMyActivity() async {
    final history = await ApiService.getUserHistory(_userName, limit: 200);
    if (!mounted) return;

    // Group events by time period
    final Map<String, List<dynamic>> grouped = {};
    for (final e in (history ?? [])) {
      String groupKey = 'Unknown';
      try {
        final d = DateTime.parse(e['timestamp'] ?? '');
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final entryDay = DateTime(d.year, d.month, d.day);
        if (entryDay == today) {
          groupKey = 'Today';
        } else if (today.difference(entryDay).inDays < 7) {
          groupKey = 'This Week';
        } else if (d.year == now.year && d.month == now.month) {
          groupKey = 'This Month';
        } else {
          const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
          groupKey = d.year == now.year
              ? months[d.month - 1]
              : '${months[d.month - 1]} ${d.year}';
        }
      } catch (_) {}
      grouped.putIfAbsent(groupKey, () => []).add(e);
    }

    // Order: This Week, This Month, then chronological desc
    final orderedKeys = <String>[];
    if (grouped.containsKey('Today')) orderedKeys.add('Today');
    if (grouped.containsKey('This Week')) orderedKeys.add('This Week');
    if (grouped.containsKey('This Month')) orderedKeys.add('This Month');
    for (final k in grouped.keys) {
      if (k != 'This Week' && k != 'This Month') orderedKeys.add(k);
    }

    final colors = context.read<ThemeNotifier>().colors;
    showModalBottomSheet(
      context: context,
      backgroundColor: colors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.65,
        maxChildSize: 0.92,
        builder: (_, sc) => Column(
          children: [
            Container(
              width: 40, height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                  color: Colors.white24, borderRadius: BorderRadius.circular(99)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: Row(children: [
                Icon(Icons.history, color: colors.accent, size: 16),
                const SizedBox(width: 8),
                Text('MY ACTIVITY',
                    style: TextStyle(
                        color: colors.accent,
                        fontSize: 10,
                        letterSpacing: 3,
                        fontWeight: FontWeight.bold)),
                const Spacer(),
                Text('${(history ?? []).length} events',
                    style: TextStyle(color: colors.textHint, fontSize: 11)),
              ]),
            ),
            const SizedBox(height: 8),
            if (history == null || history.isEmpty)
              Expanded(
                child: Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.inbox, color: colors.textHint, size: 40),
                    const SizedBox(height: 10),
                    Text('No activity recorded',
                        style: TextStyle(color: colors.textHint)),
                  ]),
                ),
              )
            else
              Expanded(
                child: _StaffActivityGrouped(
                  history: history,
                  controller: sc,
                  colors: colors,
                ),
              ),
                        ],
        ),
      ),
    );
  }


  void _showUserManual() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A3A5C),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.92,
        builder: (_, sc) => SingleChildScrollView(
          controller: sc,
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40, height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(99)),
                ),
              ),
              const Text('USER MANUAL',
                  style: TextStyle(
                      color: Color(0xFFF5A623),
                      fontSize: 10,
                      letterSpacing: 3,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              ...[
                ('Logging In', 'Enter your username and password on the login screen. If you see "Invalid username or password", contact your admin to verify your account.'),
                ('Dashboard', 'The home screen shows total instruments, active dispatches, borrow count, and overdue items. Tap any count card to navigate to the relevant tab. Pull down anywhere to sync with the server.'),
                ('Your Name Button (Top Left)', 'Tap your name in the header to open the side panel. This gives you access to Notifications, Messages, My Activity, and the User Manual. A red badge on your name means you have unread notifications or messages.'),
                ('Sync Button (Top Right)', 'The circular arrows icon syncs your data with the server. It turns orange when syncing. Use this after making changes offline to push them to the server.'),
                ('Instruments Tab — All Sub-tab', 'Browse the full instrument inventory. Use the search bar to find by name or code. Filter chips (Overdue, For Repair, Condemned, Upcoming) narrow the list. The Export button lets you export Condition History, Upcoming, Overdue, and Currently Out instruments to an Excel file in your Downloads folder.'),
                ('Instruments Tab — Editing an Instrument', 'Tap the pencil/edit icon on any instrument card to open the edit sheet. Here you can: change the condition, set a scheduled repair or condemn date, add notes, and manage calibration. Changes are saved locally and synced to the server when connected.'),
                ('Condition: For Repair', 'Set the condition to For Repair when an instrument needs maintenance. You must provide a reason and a target repair date. This appears in the Upcoming tab and in admin notifications.'),
                ('Condition: Condemning', 'Set to Condemning when an instrument is beyond repair and should be retired. You must provide a reason and date. The admin must Approve & Delete it from the Condemn tab. You can also request to revert it back — the admin will approve or deny.'),
                ('Condition: For Calibration', 'Marks the instrument as needing calibration. It will appear in the Upcoming tab. Once calibrated, the condition reverts to Functioning automatically.'),
                ('Calibration Feature', 'Inside the edit sheet, tap the calibration status bar to open the Calibrate dialog. Enter calibration notes and optionally set the next calibration due date. The instrument will appear in the Upcoming tab when the due date is approaching (within 7 days) or overdue.'),
                ('Instruments Tab — Upcoming Sub-tab', 'Lists instruments that have scheduled repair, condemn, or calibration dates coming within 30 days, plus any overdue items. Sorted by nearest date first.'),
                ('Dispatch Records Tab', 'Shows all dispatch records. Use the All/Out/Returned filter chips to narrow results. The Export button opens a dialog to choose a start date and Active/Returned filters before exporting to Excel.'),
                ('Borrow Instruments Tab — New Borrow', 'Step 1: Scan or manually add instruments. Step 2: Fill in borrower info (name, ID, contact, purpose). The Transaction No. is auto-generated in IBF-YYYY-NNNN format. Step 3: Take a photo of the borrow form. Step 4: Review and submit. The Export button works the same as dispatch export.'),
                ('Notifications', 'Tap your name → Notifications to see: overdue instruments, instruments for repair, condemned instruments needing admin action, overdue dispatches, and calibration alerts. Each section is collapsible. Tap items to jump to the relevant screen.'),
                ('Messages', 'Tap your name → Messages to see all messages from the admin. Unread messages are highlighted. Tap Mark as Read on each message to confirm receipt. The full message history is grouped by Today, This Week, and older.'),
                ('My Activity', 'Tap your name → My Activity to see your own action history grouped by time period. This includes logins, condition changes, dispatches, borrows, and calibrations you performed.'),
              ].map((entry) {
                final (title, desc) = entry;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(
                              color: Color(0xFFF5A623),
                              fontWeight: FontWeight.bold,
                              fontSize: 13)),
                      const SizedBox(height: 4),
                      Text(desc,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 12, height: 1.5)),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  void _showNotifications() async {
    final instruments = await DBHelper.instance.getAllInstruments();
    final dispatches = await DBHelper.instance.getAllDispatches();

    final overdueInstruments = instruments.where((i) => i.isOverdue).toList();
    final forRepair = instruments.where((i) => i.currentCondition == 'For Repair').toList();
    final forCondemn = instruments.where((i) => i.currentCondition == 'Condemning').toList();
    final calibOverdue = instruments.where((i) => i.isCalibrationOverdue).toList();
    final calibDueSoon = instruments.where((i) => i.calibrationDueSoon && !i.isCalibrationOverdue).toList();
    final inUse = instruments.where((i) => i.status == 'In Use').toList();
    final overdueDispatches = dispatches
        .where((d) => d.dateIn == null && !d.isStudent)
        .toList();
    final total = overdueInstruments.length + forRepair.length +
        forCondemn.length + overdueDispatches.length;

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A3A5C),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.5,
        maxChildSize: 0.85,
        builder: (_, ctrl) => Column(
          children: [
            Container(
              width: 40, height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(99)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Text('NOTIFICATIONS',
                      style: TextStyle(
                          color: Color(0xFFF5A623),
                          fontSize: 10,
                          letterSpacing: 3,
                          fontWeight: FontWeight.bold)),
                  const Spacer(),
                  if (_unreadMessages.isNotEmpty)
                    GestureDetector(
                      onTap: () {
                        Navigator.pop(context);
                        _showMessageInbox();
                      },
                      child: Container(
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF5A623).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(99),
                          border: Border.all(
                              color:
                                  const Color(0xFFF5A623).withValues(alpha: 0.5)),
                        ),
                        child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.message,
                                  color: Color(0xFFF5A623), size: 11),
                              const SizedBox(width: 4),
                              Text('${_unreadMessages.length} msg',
                                  style: const TextStyle(
                                      color: Color(0xFFF5A623),
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold)),
                            ]),
                      ),
                    ),
                  if (total > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text('$total total',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold)),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                controller: ctrl,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  if (total == 0)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(
                        child: Column(
                          children: [
                            Icon(Icons.check_circle_outline,
                                color: Colors.green, size: 40),
                            SizedBox(height: 10),
                            Text('All clear — no notifications',
                                style: TextStyle(color: Colors.white54)),
                          ],
                        ),
                      ),
                    ),
                  if (overdueDispatches.isNotEmpty)
                    _notifSection(
                      'OVERDUE DISPATCHES',
                      Colors.red,
                      Icons.outbox,
                      overdueDispatches.map((d) =>
                          '${d.dispatchNo} — ${d.testEngineer}').toList(),
                      onTap: () {
                        Navigator.pop(context);
                        _tabController.animateTo(2); // Dispatch Records
                      },
                    ),
                  if (overdueInstruments.isNotEmpty)
                    _notifSection(
                      'OVERDUE INSTRUMENTS',
                      Colors.orange,
                      Icons.warning_amber,
                      overdueInstruments.map((i) =>
                          '${i.instrumentCode} — ${i.instrumentName}').toList(),
                      onTap: () {
                        Navigator.pop(context);
                        _tabController.animateTo(1); // Instruments
                      },
                    ),
                  if (forRepair.isNotEmpty)
                    _notifSection(
                      'FOR REPAIR',
                      Colors.amber,
                      Icons.build_circle,
                      forRepair.map((i) =>
                          '${i.instrumentCode} — ${i.instrumentName}').toList(),
                      onTap: () {
                        Navigator.pop(context);
                        _tabController.animateTo(1); // Instruments
                      },
                    ),
                  if (forCondemn.isNotEmpty)
                    _notifSection(
                      'PENDING CONDEMNATION',
                      Colors.red,
                      Icons.gavel,
                      forCondemn.map((i) =>
                          '${i.instrumentCode} — ${i.instrumentName}').toList(),
                      onTap: () {
                        Navigator.pop(context);
                        _tabController.animateTo(1);
                      },
                    ),
                  if (calibOverdue.isNotEmpty)
                    _notifSection(
                      'CALIBRATION OVERDUE',
                      Colors.blue,
                      Icons.science,
                      calibOverdue.map((i) =>
                          '${i.instrumentCode} — ${i.instrumentName}').toList(),
                      onTap: () {
                        Navigator.pop(context);
                        _tabController.animateTo(1);
                      },
                    ),
                  if (calibDueSoon.isNotEmpty)
                    _notifSection(
                      'CALIBRATION DUE SOON',
                      Colors.lightBlue,
                      Icons.science_outlined,
                      calibDueSoon.map((i) =>
                          '${i.instrumentCode} — due in ${i.daysUntilCalibrationDue} days').toList(),
                      onTap: () {
                        Navigator.pop(context);
                        _tabController.animateTo(1);
                      },
                    ),
                  if (inUse.isNotEmpty)
                    _notifSection(
                      'INSTRUMENTS CURRENTLY OUT',
                      Colors.blue,
                      Icons.sensors,
                      inUse.map((i) =>
                          '${i.instrumentCode} — ${i.instrumentName}').toList(),
                      onTap: () {
                        Navigator.pop(context);
                        _tabController.animateTo(1); // Instruments
                      },
                    ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _notifSection(String label, Color color, IconData icon,
      List<String> items, {VoidCallback? onTap}) {
    return _CollapsibleNotifSection(
      label: label, color: color, icon: icon,
      items: items, onTap: onTap,
    );
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A3A5C),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Log Out',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: const Text('Are you sure you want to log out?',
            style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white38)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            child: const Text('Log Out', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (mounted) {
      Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const LoginScreen()));
    }
  }

  Future<void> _downloadInstruments() async {
    setState(() => _isSyncing = true);
    final instruments = await ApiService.getInstruments();
    if (instruments != null) {
      for (final i in instruments) {
        await DBHelper.instance.insertInstrument(Instrument.fromMap(i));
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Instruments synced successfully'),
              backgroundColor: Colors.green),
        );
      }
    }
    await _loadDashboard();
  }

  // ─── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final themeNotifier = context.watch<ThemeNotifier>();
    final colors = themeNotifier.colors;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: colors.background,
      drawer: _buildProfileDrawer(colors),
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                _buildHeader(colors),
                SizeTransition(
                  sizeFactor: ReverseAnimation(_collapseAnimation),
                  axisAlignment: -1,
                  child: _buildTopPanel(colors),
                ),
                _buildTabBar(colors),
                Expanded(child: _buildTabViews(colors)),
              ],
            ),

            // Easter egg overlays
            if (_easterEggActive)
              Positioned.fill(
                child: GestureDetector(
                  onTap: () {},
                  behavior: HitTestBehavior.translucent,
                  child: Container(color: Colors.transparent),
                ),
              ),

            if (_easterEggActive)
              AnimatedBuilder(
                animation: _snapAnimController,
                builder: (_, __) {
                  final pos =
                      _snapping ? _snapAnimation.value : _logoPosition;
                  final cx = MediaQuery.of(context).size.width / 2;
                  final cy = MediaQuery.of(context).size.height / 2;
                  return Positioned(
                    left: cx + pos.dx - _logoSize / 2,
                    top: cy + pos.dy - _logoSize / 2,
                    child: GestureDetector(
                      onTap: _resetEasterEgg,
                      child: Container(
                        width: _logoSize,
                        height: _logoSize,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: colors.background,
                          border: Border.all(
                              color: colors.accent, width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: colors.accent.withValues(alpha: 0.45),
                              blurRadius: 20,
                              spreadRadius: 3,
                            ),
                          ],
                        ),
                        child: ClipOval(
                          child: Image.asset(
                            'assets/amtec_logo.png',
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => Icon(
                              Icons.construction,
                              color: colors.accent,
                              size: 36,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),

            if (_easterEggActive && !_snapping)
              Positioned(
                bottom: 32,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      '📳  Shake to reset',
                      style:
                          TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ),
                ),
              ),

            if (_showCredit)
              Positioned(
                top: 56,
                left: 24,
                right: 24,
                child: Opacity(
                  opacity: _creditOpacity,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A3A5C),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color:
                              const Color(0xFFF5A623).withValues(alpha: 0.6)),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFF5A623).withValues(alpha: 0.2),
                          blurRadius: 24,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('✨  Developed by',
                            style: TextStyle(
                                color: Colors.white54, fontSize: 11)),
                        SizedBox(height: 6),
                        Text(
                          'Jin Lowell Miranda',
                          style: TextStyle(
                            color: Color(0xFFF5A623),
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileDrawer(AppColors colors) {
    // Always use dark background for drawer so white text is visible in all themes
    const drawerBg = Color(0xFF111827);
    return Drawer(
      backgroundColor: drawerBg,
      child: SafeArea(
        child: Column(
          children: [
            // ── Profile header ──
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [colors.headerBg, const Color(0xFF1E3A5C)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: colors.accent.withValues(alpha: 0.15),
                      border: Border.all(color: colors.accent, width: 2),
                    ),
                    child: Center(
                      child: Text(
                        _userName.isNotEmpty
                            ? _userName[0].toUpperCase()
                            : 'U',
                        style: TextStyle(
                            color: colors.accent,
                            fontSize: 24,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(_userName,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Text('@$_username',
                      style: TextStyle(
                          color: colors.textSecondary, fontSize: 13)),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: colors.accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(
                          color: colors.accent.withValues(alpha: 0.4)),
                    ),
                    child: Text(
                      _userRole.toUpperCase(),
                      style: TextStyle(
                          color: colors.accent,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(color: Colors.white12, height: 1),
            const SizedBox(height: 8),
            // ── Notifications ──
            ListTile(
              leading: Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(
                    _totalNotifCount > 0
                        ? Icons.notifications
                        : Icons.notifications_outlined,
                    color: _totalNotifCount > 0
                        ? colors.accent
                        : colors.textHint,
                  ),
                  if (_totalNotifCount > 0)
                    Positioned(
                      right: -4,
                      top: -4,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: const BoxDecoration(
                            color: Colors.red, shape: BoxShape.circle),
                        child: Text('$_totalNotifCount',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 8,
                                fontWeight: FontWeight.bold)),
                      ),
                    ),
                ],
              ),
              title: const Text('Notifications',
                  style: TextStyle(color: Colors.white, fontSize: 14)),
              onTap: () {
                Navigator.pop(context);
                _showNotifications();
              },
            ),
            // ── Messages ──
            ListTile(
              leading: Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(
                    Icons.message,
                    color: _unreadMessages.isNotEmpty
                        ? colors.accent
                        : colors.textHint,
                  ),
                  if (_unreadMessages.isNotEmpty)
                    Positioned(
                      right: -4,
                      top: -4,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: const BoxDecoration(
                            color: Colors.red, shape: BoxShape.circle),
                        child: Text('${_unreadMessages.length}',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 8,
                                fontWeight: FontWeight.bold)),
                      ),
                    ),
                ],
              ),
              title: const Text('Messages',
                  style: TextStyle(color: Colors.white, fontSize: 14)),
              onTap: () {
                Navigator.pop(context);
                _showMessageInbox();
              },
            ),
            const Divider(color: Colors.white12, height: 1),
            // ── Account Activity ──
            ListTile(
              leading: Icon(Icons.history, color: colors.textHint),
              title: const Text('My Activity',
                  style: TextStyle(color: Colors.white, fontSize: 14)),
              onTap: () {
                Navigator.pop(context);
                _showMyActivity();
              },
            ),
            // ── About ──
            ListTile(
              leading: Icon(Icons.info_outline, color: colors.textHint),
              title: const Text('About',
                  style: TextStyle(color: Colors.white, fontSize: 14)),
              subtitle: const Text('AMTEC Tool Tracker v1.0',
                  style: TextStyle(color: Colors.white38, fontSize: 11)),
              onTap: () {
                Navigator.pop(context);
                showAboutDialog(
                  context: context,
                  applicationName: 'AMTEC Tool Tracker',
                  applicationVersion: '1.0.0',
                  applicationLegalese:
                      '© 2026 Agricultural Machinery Testing\nand Evaluation Center, UPLB',
                );
              },
            ),
            // ── Manual ──
            ListTile(
              leading: Icon(Icons.menu_book_outlined, color: colors.textHint),
              title: const Text('User Manual',
                  style: TextStyle(color: Colors.white, fontSize: 14)),
              onTap: () {
                Navigator.pop(context);
                _showUserManual();
              },
            ),
            const Divider(color: Colors.white12, height: 1),
            // ── Log Out ──
            const Spacer(),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.redAccent),
              title: const Text('Log Out',
                  style: TextStyle(color: Colors.redAccent, fontSize: 14)),
              onTap: () {
                Navigator.pop(context);
                _logout();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(AppColors colors) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: colors.headerBg,
      child: Row(
        children: [
          const SizedBox(width: 4),
          // ── Left: tappable title/name (opens drawer) ──
          Expanded(
            child: GestureDetector(
              onTap: () => _scaffoldKey.currentState?.openDrawer(),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('AMTEC',
                          style: TextStyle(
                              color: colors.accent,
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                              letterSpacing: 3)),
                      Row(children: [
                        Text('Welcome, $_userName',
                            style: TextStyle(
                                color: colors.textSecondary, fontSize: 12)),
                        const SizedBox(width: 4),
                        Icon(Icons.arrow_forward_ios,
                            color: colors.textSecondary.withValues(alpha: 0.5),
                            size: 10),
                      ]),
                    ],
                  ),
                  // ── Total notification badge on name ──
                  if (_totalNotifCount > 0)
                    Positioned(
                      top: -4,
                      right: -4,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                            color: Colors.red, shape: BoxShape.circle),
                        child: Text(
                          _totalNotifCount > 99 ? '99+' : '$_totalNotifCount',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 8,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          // ── Right: connectivity + sync + message + notif ──
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Connectivity pill
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: (_isConnected ? Colors.green : Colors.red)
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(
                      color: _isConnected ? Colors.green : Colors.red,
                      width: 0.8),
                ),
                child: Row(children: [
                  Icon(
                    _isConnected ? Icons.wifi : Icons.wifi_off,
                    color: _isConnected ? Colors.green : Colors.red,
                    size: 12,
                  ),
                  const SizedBox(width: 3),
                  Text(
                    _isConnected ? 'Online' : 'Offline',
                    style: TextStyle(
                        color: _isConnected ? Colors.green : Colors.red,
                        fontSize: 10,
                        fontWeight: FontWeight.bold),
                  ),
                ]),
              ),
              const SizedBox(width: 8),
              // Sync button
              GestureDetector(
                onTap: () async {
                  setState(() => _isSyncing = true);
                  await _downloadInstruments();
                  final result = await SyncService.instance.syncPending();
                  await _loadDashboard();
                  if (mounted) {
                    final msg = result.failed > 0
                        ? '${result.synced} synced, ${result.failed} failed'
                        : result.pulled > 0
                            ? '↓ ${result.pulled} pulled, ↑ ${result.synced} pushed'
                            : result.synced > 0
                                ? '${result.synced} records synced'
                                : 'Up to date';
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(msg),
                      backgroundColor:
                          result.failed > 0 ? Colors.orange : Colors.green,
                      duration: const Duration(seconds: 2),
                    ));
                  }
                },
                child: _isSyncing
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: colors.accent))
                    : Icon(Icons.sync, color: colors.accent, size: 20),
              ),

            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTopPanel(AppColors colors) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [colors.surface, colors.background],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _buildLogoRing(colors),
                const SizedBox(width: 20),
                Expanded(child: _buildStats(colors)),
              ],
            ),
          ),
          if (_activeDispatches.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(left: 16, bottom: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('ACTIVE DISPATCHES',
                    style: TextStyle(
                        color: colors.accent,
                        fontSize: 10,
                        letterSpacing: 3,
                        fontWeight: FontWeight.bold)),
              ),
            ),
            SizedBox(
              height: 130,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.only(
                    left: 16, right: 8, bottom: 16),
                itemCount: _activeDispatches.length,
                itemBuilder: (_, i) {
                  final dispatch = _activeDispatches[i];
                  final items =
                      _activeDispatchItems[dispatch.dispatchNo] ?? [];
                  return _buildActiveDispatchCard(dispatch, items, colors);
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Logo with full 360° coin-flip animation ──────────────────────────────
  Widget _buildLogoRing(AppColors colors) {
    return GestureDetector(
      onTap: _onLogoFlip,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 110,
            height: 110,
            child: CircularProgressIndicator(
              value: _totalInstruments == 0
                  ? 0
                  : _inUseCount / _totalInstruments,
              strokeWidth: 7,
              backgroundColor: colors.logoRingBg,
              color: colors.accent,
            ),
          ),
          AnimatedBuilder(
            animation: _flipAnimation,
            builder: (context, child) {
              // Full 360° — map 0..1 → 0..2π
              final angle = _flipAnimation.value * 2 * math.pi;

              // Show icon in the middle arc: 90°–270° (π/2 to 3π/2)
              final showIcon = angle > math.pi / 2 && angle < 3 * math.pi / 2;

              // When showing the icon face, un-mirror it so text/icons read correctly
              final faceTransform = Matrix4.identity()
                ..setEntry(3, 2, 0.001)
                ..rotateY(angle);

              // The icon face needs a counter-rotation to stay readable
              final iconCounterTransform = Matrix4.identity()
                ..rotateY(-angle); // cancel the parent rotation for readability

              if (_easterEggActive) {
                return Transform(
                  alignment: Alignment.center,
                  transform: faceTransform,
                  child: Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: colors.background,
                      border: Border.all(
                          color: colors.accent.withValues(alpha: 0.15), width: 1),
                    ),
                    child: Icon(Icons.question_mark,
                        color: colors.accent, size: 28),
                  ),
                );
              }

              return Transform(
                alignment: Alignment.center,
                transform: faceTransform,
                child: showIcon
                    // ── Back face: show next-mode icon ──────────────────
                    ? Transform(
                        alignment: Alignment.center,
                        transform: iconCounterTransform,
                        child: Container(
                          width: 88,
                          height: 88,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: colors.accent,
                            border: Border.all(color: colors.accent, width: 1),
                          ),
                          child: Icon(
                            _pendingModeIcon,
                            color: colors.accentText,
                            size: 36,
                          ),
                        ),
                      )
                    // ── Front/back face: show logo ───────────────────────
                    : Container(
                        width: 88,
                        height: 88,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: colors.background,
                          border: Border.all(
                              color: colors.accent.withValues(alpha: 0.3), width: 1),
                        ),
                        child: ClipOval(
                          child: Image.asset(
                            'assets/amtec_logo.png',
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => Icon(
                              Icons.construction,
                              color: colors.accent,
                              size: 36,
                            ),
                          ),
                        ),
                      ),
              );
            },
          ),
          Positioned(
            bottom: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: colors.accent,
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                '$_inUseCount / $_totalInstruments',
                style: TextStyle(
                    color: colors.accentText,
                    fontSize: 10,
                    fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Returns the icon for the mode we are switching TO (current mode → next)
  IconData _getNextModeIcon(BuildContext context) {
    final current = context.read<ThemeNotifier>().mode;
    switch (current) {
      case AppThemeMode.amtec: return Icons.light_mode;      // going to light → sun
      case AppThemeMode.light: return Icons.dark_mode;       // going to dark  → moon
      case AppThemeMode.dark:  return Icons.auto_awesome;    // going to amtec → star
    }
  }

  Widget _buildStats(AppColors colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _activeDispatches.isEmpty
              ? 'NO ACTIVE DISPATCH'
              : '${_activeDispatches.length} ACTIVE DISPATCH${_activeDispatches.length > 1 ? 'ES' : ''}',
          style: TextStyle(
              color: _activeDispatches.isEmpty
                  ? colors.accent
                  : Colors.orange,
              fontWeight: FontWeight.bold,
              fontSize: 13,
              letterSpacing: 1),
        ),
        const SizedBox(height: 8),
        _statRow('Available', '$_availableCount instruments',
            Colors.green, colors),
        _statRow(
            'In Use', '$_inUseCount instruments', Colors.orange, colors),
        _statRow(
            'Total', '$_totalInstruments instruments', colors.textSecondary, colors),
      ],
    );
  }

  Widget _buildActiveDispatchCard(
      Dispatch dispatch, List<dynamic> items, AppColors colors) {
    return Container(
      width: 220,
      margin: const EdgeInsets.only(right: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: Colors.orange.withValues(alpha: 0.5), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.orange.withValues(alpha: 0.06),
            blurRadius: 8,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.circle, color: Colors.orange, size: 7),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                dispatch.dispatchNo,
                style: TextStyle(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 13),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ]),
          const SizedBox(height: 4),
          Text(dispatch.testEngineer,
              style: TextStyle(
                  color: colors.textHint, fontSize: 11),
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 6),
          Divider(color: colors.border, height: 1),
          const SizedBox(height: 6),
          Expanded(
            child: items.isEmpty
                ? Text('No instruments',
                    style: TextStyle(
                        color: colors.textHint, fontSize: 10))
                : SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: items
                          .map((item) => Padding(
                                padding:
                                    const EdgeInsets.only(bottom: 3),
                                child: Row(children: [
                                  const Icon(Icons.arrow_outward,
                                      color: Colors.orange, size: 10),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      item.instrumentName,
                                      style: TextStyle(
                                          color: colors.textSecondary,
                                          fontSize: 10),
                                      overflow:
                                          TextOverflow.ellipsis,
                                    ),
                                  ),
                                ]),
                              ))
                          .toList(),
                    ),
                  ),
          ),
          const SizedBox(height: 4),
          Text(
              '${items.length} instrument${items.length != 1 ? 's' : ''} out',
              style: const TextStyle(
                  color: Colors.orange,
                  fontSize: 10,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _statRow(String label, String value, Color valueColor, AppColors colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text('$label:',
                style: TextStyle(
                    color: colors.textHint, fontSize: 12)),
          ),
          Expanded(
            child: Text(value,
                style: TextStyle(
                    color: valueColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }



  Widget _buildTabBar(AppColors colors) {
    return Container(
      color: colors.tabBg,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TabBar(
            controller: _tabController,
            indicatorColor: colors.accent,
            indicatorWeight: 3,
            labelColor: colors.accent,
            unselectedLabelColor: colors.textHint,
            labelStyle: const TextStyle(
                fontWeight: FontWeight.bold, fontSize: 12),
            tabs: const [
              Tab(text: 'New Dispatch'),
              Tab(text: 'Instruments'),
              Tab(text: 'Dispatch Records'),
              Tab(text: 'Borrow Instrument'),
            ],
          ),
          GestureDetector(
            onTap: _toggleTopPanel,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 4),
              decoration: BoxDecoration(
                color: _topPanelCollapsed
                    ? colors.accent.withValues(alpha: 0.08)
                    : Colors.transparent,
                border: Border(
                  top: BorderSide(
                    color: colors.border.withValues(alpha: 0.6),
                    width: 0.5,
                  ),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AnimatedRotation(
                    turns: _topPanelCollapsed ? 0.5 : 0.0,
                    duration: const Duration(milliseconds: 280),
                    child: Icon(
                      Icons.keyboard_arrow_up,
                      color: colors.textHint,
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _topPanelCollapsed
                        ? 'Show dashboard'
                        : 'Hide dashboard',
                    style: TextStyle(
                        color: colors.textHint, fontSize: 10),
                  ),
                  const SizedBox(width: 4),
                  AnimatedRotation(
                    turns: _topPanelCollapsed ? 0.5 : 0.0,
                    duration: const Duration(milliseconds: 280),
                    child: Icon(
                      Icons.keyboard_arrow_up,
                      color: colors.textHint,
                      size: 16,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabViews(AppColors colors) {
    return TabBarView(
      controller: _tabController,
      children: [
        _NewDispatchTab(onDispatchCreated: _loadDashboard),
        InstrumentsTab(
          key: _instrumentsTabKey,
          onRefresh: _loadDashboard,
          isActive: _currentTabIndex == 1,
        ),
        _DispatchRecordsTab(onRefresh: _loadDashboard),
        StudentBorrowTab(onDispatchCreated: _loadDashboard),
      ],
    );
  }
}

// ══════════════════════════════════════════════
// TAB 1 — NEW DISPATCH
// ══════════════════════════════════════════════
class _NewDispatchTab extends StatefulWidget {
  final VoidCallback onDispatchCreated;
  const _NewDispatchTab({required this.onDispatchCreated});

  @override
  State<_NewDispatchTab> createState() => _NewDispatchTabState();
}

class _NewDispatchTabState extends State<_NewDispatchTab> {
  final _dispatchNoController = TextEditingController();
  final _engineerController = TextEditingController();
  final _processedByController = TextEditingController();
  final _remarksController = TextEditingController();
  List<DispatchItem> _scannedItems = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _prefillProcessedBy();
  }

  Future<void> _prefillProcessedBy() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString('user_name') ?? '';
    if (mounted) setState(() => _processedByController.text = name);
  }

  void _openScanner() async {
    final instrument = await Navigator.push<Instrument>(
      context,
      MaterialPageRoute(
          builder: (_) =>
              const ScannerScreen(mode: ScannerMode.borrow)),
    );
    if (instrument == null) return;
    if (!mounted) return;

    if (_scannedItems
        .any((i) => i.instrumentCode == instrument.instrumentCode)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Already added'),
          backgroundColor: Colors.orange));
      return;
    }

    setState(() {
      _scannedItems.add(DispatchItem(
        instrumentCode: instrument.instrumentCode,
        instrumentName: instrument.instrumentName,
        currentCondition: 'Functioning',
      ));
    });
  }

  Future<void> _submit() async {
    if (_dispatchNoController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Please enter a Dispatch No.'),
          backgroundColor: Colors.red));
      return;
    }
    if (_engineerController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Please enter the Test Engineer name.'),
          backgroundColor: Colors.red));
      return;
    }
    if (_processedByController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:
              Text('Please enter who is processing this dispatch.'),
          backgroundColor: Colors.red));
      return;
    }
    if (_scannedItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Please scan at least one instrument.'),
          backgroundColor: Colors.red));
      return;
    }

    setState(() => _loading = true);
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt('user_id') ?? 1;

    try {
      final dispatch = Dispatch(
        dispatchNo: _dispatchNoController.text.trim(),
        testEngineer: _engineerController.text.trim(),
        processedById: userId,
        processedByName: _processedByController.text.trim(),
        dateOut: DateTime.now().toIso8601String(),
        remarks: _remarksController.text.trim(),
      );

      await DBHelper.instance.insertDispatch(dispatch, _scannedItems);
      await DBHelper.instance.logActivity(
        eventType: 'dispatch_created',
        eventDetail: 'Dispatch ${dispatch.dispatchNo} — ${_scannedItems.length} instrument(s)',
        actor: _processedByController.text.trim(),
      );

      setState(() {
        _loading = false;
        _dispatchNoController.clear();
        _engineerController.clear();
        _remarksController.clear();
        _scannedItems = [];
      });

      widget.onDispatchCreated();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Dispatch created successfully'),
            backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) {
        String msg = 'Failed to create dispatch.';
        if (e.toString().contains('UNIQUE') ||
            e.toString().contains('unique')) {
          msg =
              'Dispatch No. already exists. Use a different number.';
        }
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(msg), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.watch<ThemeNotifier>().colors;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label('STAFF DISPATCH', colors),
          const SizedBox(height: 10),
          _field(_dispatchNoController, 'Dispatch No.', Icons.tag, colors),
          const SizedBox(height: 10),
          _field(_engineerController, 'Test Engineer',
              Icons.engineering, colors),
          const SizedBox(height: 10),
          _field(_processedByController, 'Processed By', Icons.person, colors),
          const SizedBox(height: 10),
          _field(
              _remarksController, 'Remarks (optional)', Icons.notes, colors),
          const SizedBox(height: 16),
          _label('INSTRUMENTS', colors),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _openScanner,
              icon: Icon(Icons.qr_code_scanner,
                  color: colors.accent),
              label: Text('Scan Instrument',
                  style: TextStyle(color: colors.accent)),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                side: BorderSide(color: colors.accent),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
          const SizedBox(height: 10),
          if (_scannedItems.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text('No instruments scanned yet',
                    style: TextStyle(color: colors.textHint)),
              ),
            )
          else
            ..._scannedItems.map((item) => Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colors.cardBg,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: colors.accent.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle,
                          color: colors.accent, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item.instrumentName,
                                style: TextStyle(
                                    color: colors.textPrimary,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13)),
                            Text('${item.instrumentCode}',
                                style: TextStyle(
                                    color: colors.textHint,
                                    fontSize: 11)),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.remove_circle,
                            color: Colors.red, size: 18),
                        onPressed: () => setState(
                            () => _scannedItems.remove(item)),
                      )
                    ],
                  ),
                )),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _loading ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.accent,
                foregroundColor: colors.accentText,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              child: _loading
                  ? CircularProgressIndicator(color: colors.accentText)
                  : const Text('CREATE DISPATCH',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(String text, AppColors colors) => Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Text(text,
            style: TextStyle(
                color: colors.accent,
                fontSize: 10,
                letterSpacing: 3,
                fontWeight: FontWeight.bold)),
      );

  Widget _field(TextEditingController c, String label, IconData icon, AppColors colors) =>
      TextField(
        controller: c,
        style: TextStyle(color: colors.textPrimary),
        decoration: _inputDeco(label, icon, colors),
      );

  InputDecoration _inputDeco(String label, IconData icon, AppColors colors) =>
      InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: colors.textHint),
        prefixIcon: Icon(icon, color: colors.accent),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: colors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: colors.accent),
        ),
        filled: true,
        fillColor: colors.inputFill,
      );
}

// ══════════════════════════════════════════════
// TAB 3 — DISPATCH RECORDS  (staff only)
// ══════════════════════════════════════════════
class _DispatchRecordsTab extends StatefulWidget {
  final VoidCallback onRefresh;
  const _DispatchRecordsTab({required this.onRefresh});

  @override
  State<_DispatchRecordsTab> createState() => _DispatchRecordsTabState();
}

class _DispatchRecordsTabState extends State<_DispatchRecordsTab> {
  List<Dispatch> _dispatches = [];
  List<Dispatch> _filtered = [];
  bool _loading = true;

  String _statusFilter = 'all';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);

    try {
      if (await SyncService.isConnected()) {
        await SyncService.instance
            .syncAll()
            .timeout(const Duration(seconds: 15));
      }
    } catch (_) {}

    try {
      final all = await DBHelper.instance.getAllDispatches();
      if (mounted) {
        setState(() {
          _dispatches = all.where((d) => !d.isStudent).toList();
          _applyFilter();
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _applyFilter() {
    switch (_statusFilter) {
      case 'out':
        _filtered = _dispatches.where((d) => d.dateIn == null).toList();
        break;
      case 'returned':
        _filtered = _dispatches.where((d) => d.dateIn != null).toList();
        break;
      default:
        _filtered = List.from(_dispatches);
    }
  }

  void _setFilter(String f) {
    setState(() {
      _statusFilter = f;
      _applyFilter();
    });
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return '—';
    try {
      return DateFormat('MMM dd, yyyy  hh:mm a')
          .format(DateTime.parse(dateStr));
    } catch (_) {
      return dateStr;
    }
  }

  Future<void> _showExportDialog(AppColors colors) async {
    bool exportOut = true;
    bool exportReturned = true;
    DateTime? fromDate;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: colors.cardBg,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: EdgeInsets.only(
            left: 24, right: 24, top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 32,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('EXPORT DISPATCH RECORDS',
                  style: TextStyle(
                      color: colors.accent,
                      fontSize: 10,
                      letterSpacing: 3,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              const Text('DATE RANGE',
                  style: TextStyle(
                      color: Color(0xFFF5A623),
                      fontSize: 10,
                      letterSpacing: 3,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              StatefulBuilder(builder: (ctx2, setDate) => GestureDetector(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: ctx2,
                    initialDate: fromDate ?? DateTime.now().subtract(const Duration(days: 30)),
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now(),
                    builder: (c, child) => Theme(
                      data: ThemeData.dark().copyWith(
                          colorScheme: const ColorScheme.dark(
                              primary: Color(0xFFF5A623),
                              onPrimary: Colors.black,
                              surface: Color(0xFF1A3A5C))),
                      child: child!,
                    ),
                  );
                  if (picked != null) setModalState(() => fromDate = picked);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: fromDate != null
                        ? const Color(0xFFF5A623).withValues(alpha: 0.08)
                        : const Color(0xFF0D1B2A),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: fromDate != null
                            ? const Color(0xFFF5A623)
                            : const Color(0xFF1E3A5F)),
                  ),
                  child: Row(children: [
                    Icon(Icons.calendar_today,
                        color: fromDate != null ? const Color(0xFFF5A623) : Colors.white38,
                        size: 16),
                    const SizedBox(width: 10),
                    Text(
                      fromDate != null
                          ? 'From: ${fromDate!.day}/${fromDate!.month}/${fromDate!.year}  →  Today'
                          : 'Tap to set start date (defaults to all time)',
                      style: TextStyle(
                          color: fromDate != null ? const Color(0xFFF5A623) : Colors.white38,
                          fontSize: 13),
                    ),
                    if (fromDate != null) ...[
                      const Spacer(),
                      GestureDetector(
                        onTap: () => setModalState(() => fromDate = null),
                        child: const Icon(Icons.close, color: Colors.white38, size: 16),
                      ),
                    ],
                  ]),
                ),
              )),
              const SizedBox(height: 12),
              const Text('INCLUDE RECORDS',
                  style: TextStyle(
                      color: Color(0xFFF5A623),
                      fontSize: 10,
                      letterSpacing: 3,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text('Select which records to include in the export.',
                  style: TextStyle(color: colors.textHint, fontSize: 12)),
              const SizedBox(height: 20),
              _exportCheckTile(
                colors: colors,
                value: exportOut,
                color: Colors.orange,
                icon: Icons.outbox,
                title: 'Currently Out',
                subtitle: 'Dispatches that have not been returned yet',
                onChanged: (v) => setModalState(() => exportOut = v!),
              ),
              const SizedBox(height: 10),
              _exportCheckTile(
                colors: colors,
                value: exportReturned,
                color: Colors.green,
                icon: Icons.assignment_turned_in,
                title: 'Returned',
                subtitle: 'Dispatches that have been returned',
                onChanged: (v) => setModalState(() => exportReturned = v!),
              ),
              const SizedBox(height: 6),
              if (!exportOut && !exportReturned)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('Select at least one option.',
                      style: TextStyle(color: Colors.red.shade300, fontSize: 11)),
                ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: (!exportOut && !exportReturned)
                      ? null
                      : () {
                          Navigator.pop(ctx);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => DispatchExportScreen(
                                exportOut: exportOut,
                                exportReturned: exportReturned,
                                dispatchFromDate: fromDate,
                              ),
                            ),
                          );
                        },
                  icon: const Icon(Icons.download, color: Colors.black),
                  label: const Text('EXPORT TO EXCEL',
                      style: TextStyle(
                          color: Colors.black, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colors.accent,
                    disabledBackgroundColor: Colors.white12,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _exportCheckTile({
    required AppColors colors,
    required bool value,
    required Color color,
    required IconData icon,
    required String title,
    required String subtitle,
    required ValueChanged<bool?> onChanged,
  }) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: value ? color.withValues(alpha: 0.1) : colors.background,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: value ? color.withValues(alpha: 0.6) : colors.border,
              width: value ? 1.5 : 1),
        ),
        child: Row(children: [
          Icon(icon, color: value ? color : colors.textHint, size: 20),
          const SizedBox(width: 12),
          Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style: TextStyle(
                    color: value ? color : colors.textSecondary,
                    fontWeight: FontWeight.bold,
                    fontSize: 13)),
            Text(subtitle,
                style: TextStyle(color: colors.textHint, fontSize: 11)),
          ])),
          Checkbox(
            value: value,
            onChanged: onChanged,
            activeColor: color,
            side: BorderSide(color: value ? color : colors.textHint),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          ),
        ]),
      ),
    );
  }

  void _showDetail(Dispatch dispatch, AppColors colors) async {
    final items =
        await DBHelper.instance.getDispatchItems(dispatch.id!);
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: colors.cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.65,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, sc) => SingleChildScrollView(
          controller: sc,
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: colors.textHint,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              Row(children: [
                Expanded(
                  child: Text(dispatch.dispatchNo,
                      style: TextStyle(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: 20)),
                ),
                _badge(dispatch.dateIn == null ? 'Out' : 'Returned'),
              ]),
              const SizedBox(height: 16),
              _dRow(Icons.person, 'Test Engineer',
                  dispatch.testEngineer, colors),
              if (dispatch.processedByName != null &&
                  dispatch.processedByName!.isNotEmpty)
                _dRow(Icons.badge, 'Processed By',
                    dispatch.processedByName!, colors),
              _dRow(Icons.logout, 'Date Out',
                  _formatDate(dispatch.dateOut), colors),
              _dRow(Icons.login, 'Date In',
                  _formatDate(dispatch.dateIn), colors),
              if (dispatch.remarks != null &&
                  dispatch.remarks!.isNotEmpty)
                _dRow(Icons.notes, 'Remarks', dispatch.remarks!, colors),
              const SizedBox(height: 20),
              if (dispatch.dateIn == null)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      final dispatchItems = await DBHelper.instance
                          .getDispatchItems(dispatch.id!);
                      if (!mounted) return;
                      Navigator.pop(context);
                      final returned =
                          await Navigator.push<bool>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ReturnScannerScreen(
                            dispatch: dispatch,
                            items: dispatchItems,
                          ),
                        ),
                      );
                      if (returned == true) {
                        _load();
                        widget.onRefresh();
                      }
                    },
                    icon: const Icon(Icons.qr_code_scanner),
                    label: const Text('RETURN INSTRUMENTS'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.black,
                      padding:
                          const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
              const SizedBox(height: 20),
              Text('INSTRUMENTS',
                  style: TextStyle(
                      color: colors.accent,
                      fontSize: 11,
                      letterSpacing: 3,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              if (items.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'Instrument data syncing — pull down to refresh.',
                    style: TextStyle(
                        color: colors.textHint, fontSize: 12),
                  ),
                )
              else
                ...items.map((item) => Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colors.background,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: colors.border),
                    ),
                    child: Row(children: [
                      Icon(Icons.build,
                          color: colors.accent, size: 16),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Text(item.instrumentName,
                                style: TextStyle(
                                    color: colors.textPrimary,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13)),
                            Text(
                                '${item.instrumentCode} · Dispatched: ${item.currentCondition}',
                                style: TextStyle(
                                    color: colors.textHint,
                                    fontSize: 11)),
                            if (item.returnCondition != null &&
                                item.returnCondition!.isNotEmpty)
                              Row(children: [
                                Icon(
                                  item.returnCondition == 'Functioning'
                                      ? Icons.check_circle
                                      : item.returnCondition == 'For Repair'
                                          ? Icons.build
                                          : Icons.cancel,
                                  color: item.returnCondition == 'Functioning'
                                      ? Colors.green
                                      : item.returnCondition == 'For Repair'
                                          ? Colors.orange
                                          : Colors.red,
                                  size: 12,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Returned: ${item.returnCondition}',
                                  style: TextStyle(
                                    color: item.returnCondition == 'Functioning'
                                        ? Colors.green
                                        : item.returnCondition == 'For Repair'
                                            ? Colors.orange
                                            : Colors.red,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ]),
                          ],
                        ),
                      ),
                    ]))),
              if (dispatch.returnPhotoPaths.isNotEmpty) ...[
                const SizedBox(height: 20),
                Text('RETURN PHOTOS',
                    style: TextStyle(
                        color: colors.accent,
                        fontSize: 11,
                        letterSpacing: 3,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: dispatch.returnPhotoPaths.map((path) {
                    return GestureDetector(
                      onTap: () => _viewPhoto(path),
                      child: Container(
                        width: 90,
                        height: 90,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: colors.accent.withValues(alpha: 0.4)),
                          image: DecorationImage(
                            image: FileImage(File(path)),
                            fit: BoxFit.cover,
                          ),
                        ),
                        child: Align(
                          alignment: Alignment.topRight,
                          child: Container(
                            margin: const EdgeInsets.all(4),
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Icon(Icons.zoom_in,
                                color: Colors.white, size: 12),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _viewPhoto(String path) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(12),
        child: Stack(
          children: [
            InteractiveViewer(
              child: Image.file(File(path),
                  fit: BoxFit.contain, width: double.infinity),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: const Icon(Icons.close,
                      color: Colors.white, size: 20),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _badge(String status) {
    final isOut = status == 'Out';
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isOut
            ? Colors.orange.withValues(alpha: 0.15)
            : Colors.green.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(99),
        border:
            Border.all(color: isOut ? Colors.orange : Colors.green),
      ),
      child: Text(status,
          style: TextStyle(
              color: isOut ? Colors.orange : Colors.green,
              fontSize: 11,
              fontWeight: FontWeight.bold)),
    );
  }

  Widget _dRow(IconData icon, String label, String value, AppColors colors) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: colors.accent, size: 15),
            const SizedBox(width: 8),
            SizedBox(
              width: 100,
              child: Text('$label:',
                  style: TextStyle(
                      color: colors.textSecondary, fontSize: 13)),
            ),
            Expanded(
              child: Text(value,
                  style: TextStyle(
                      color: colors.textPrimary, fontSize: 13)),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final colors = context.watch<ThemeNotifier>().colors;

    final outCount = _dispatches.where((d) => d.dateIn == null).length;
    final returnedCount = _dispatches.where((d) => d.dateIn != null).length;

    return _loading
        ? const Center(child: CircularProgressIndicator())
        : Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _filterChip('All', _dispatches.length, 'all', colors.accent, colors),
                            const SizedBox(width: 8),
                            _filterChip('Out', outCount, 'out', Colors.orange, colors),
                            const SizedBox(width: 8),
                            _filterChip('Returned', returnedCount, 'returned', Colors.green, colors),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      height: 36,
                      child: OutlinedButton.icon(
                        onPressed: () => _showExportDialog(colors),
                        icon: Icon(Icons.file_download,
                            color: colors.accent, size: 16),
                        label: Text('Export',
                            style: TextStyle(
                                color: colors.accent,
                                fontWeight: FontWeight.bold,
                                fontSize: 12)),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          side: BorderSide(color: colors.accent),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${_filtered.length} record${_filtered.length != 1 ? 's' : ''}',
                    style: TextStyle(color: colors.textHint, fontSize: 11),
                  ),
                ),
              ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _load,
                  child: _filtered.isEmpty
                      ? Center(
                          child: Text(
                            _statusFilter == 'all'
                                ? 'No dispatch records yet'
                                : 'No ${_statusFilter == 'out' ? 'active' : 'returned'} dispatches',
                            style: TextStyle(color: colors.textHint),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: _filtered.length,
                          itemBuilder: (_, i) {
                            final d = _filtered[i];
                            final isOut = d.dateIn == null;
                            return GestureDetector(
                              onTap: () => _showDetail(d, colors),
                              child: Container(
                                margin: const EdgeInsets.only(
                                    bottom: 10),
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: colors.cardBg,
                                  borderRadius:
                                      BorderRadius.circular(10),
                                  border: Border.all(
                                    color: isOut
                                        ? Colors.orange
                                            .withValues(alpha: 0.35)
                                        : colors.border,
                                  ),
                                ),
                                child: Row(children: [
                                  Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      color: isOut
                                          ? Colors.orange
                                              .withValues(alpha: 0.12)
                                          : Colors.green
                                              .withValues(alpha: 0.12),
                                      borderRadius:
                                          BorderRadius.circular(8),
                                    ),
                                    child: Icon(
                                      isOut
                                          ? Icons.outbox
                                          : Icons.assignment_turned_in,
                                      color: isOut
                                          ? Colors.orange
                                          : Colors.green,
                                      size: 22,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(d.dispatchNo,
                                            style: TextStyle(
                                                color: colors.textPrimary,
                                                fontWeight:
                                                    FontWeight.bold,
                                                fontSize: 15)),
                                        Text(
                                          d.testEngineer,
                                          style: TextStyle(
                                              color: colors.textHint,
                                              fontSize: 12),
                                        ),
                                        Text(_formatDate(d.dateOut),
                                            style: TextStyle(
                                                color: colors.textHint,
                                                fontSize: 11)),
                                      ],
                                    ),
                                  ),
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.end,
                                    children: [
                                      _badge(isOut ? 'Out' : 'Returned'),
                                      const SizedBox(height: 6),
                                      Text('Tap to view',
                                          style: TextStyle(
                                              color: colors.textHint,
                                              fontSize: 10)),
                                    ],
                                  ),
                                ]),
                              ),
                            );
                          },
                        ),
                ),
              ),
            ],
          );
  }

  Widget _filterChip(String label, int count, String filter, Color activeColor, AppColors colors) {
    final selected = _statusFilter == filter;
    return GestureDetector(
      onTap: () => _setFilter(filter),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? activeColor.withValues(alpha: 0.15) : colors.surface,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(
            color: selected ? activeColor : colors.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: TextStyle(
                    color: selected ? activeColor : colors.textSecondary,
                    fontSize: 11,
                    fontWeight: selected ? FontWeight.bold : FontWeight.normal)),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: selected ? activeColor.withValues(alpha: 0.25) : colors.border,
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text('$count',
                  style: TextStyle(
                      color: selected ? activeColor : colors.textHint,
                      fontSize: 10,
                      fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════
// TAB 4 — STUDENT BORROW (wrapper)
// ══════════════════════════════════════════════
class StudentBorrowTab extends StatelessWidget {
  final VoidCallback onDispatchCreated;
  const StudentBorrowTab(
      {super.key, required this.onDispatchCreated});

  @override
  Widget build(BuildContext context) {
    return StudentBorrowScreen(onDispatchCreated: onDispatchCreated);
  }
}

// ── Stateful message inbox sheet ─────────────────────────────────────────────
// ── Collapsible notification section ─────────────────────────────────────────
class _CollapsibleNotifSection extends StatefulWidget {
  final String label;
  final Color color;
  final IconData icon;
  final List<String> items;
  final VoidCallback? onTap;
  const _CollapsibleNotifSection({
    required this.label, required this.color, required this.icon,
    required this.items, this.onTap,
  });
  @override
  State<_CollapsibleNotifSection> createState() =>
      _CollapsibleNotifSectionState();
}

class _CollapsibleNotifSectionState
    extends State<_CollapsibleNotifSection> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 10),
      GestureDetector(
        onTap: () => setState(() => _expanded = !_expanded),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: widget.color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: widget.color.withValues(alpha: 0.35)),
          ),
          child: Row(children: [
            Icon(widget.icon, color: widget.color, size: 15),
            const SizedBox(width: 8),
            Expanded(child: Text(widget.label,
                style: TextStyle(color: widget.color, fontSize: 10,
                    letterSpacing: 2, fontWeight: FontWeight.bold))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: widget.color.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text('${widget.items.length}',
                  style: TextStyle(color: widget.color, fontSize: 10,
                      fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 6),
            Icon(_expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                color: widget.color, size: 18),
          ]),
        ),
      ),
      if (_expanded) ...[
        const SizedBox(height: 4),
        ...widget.items.map((s) => GestureDetector(
          onTap: widget.onTap,
          child: Container(
            margin: const EdgeInsets.only(bottom: 4, left: 4),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: widget.color.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: widget.color.withValues(alpha: 0.2)),
            ),
            child: Row(children: [
              Expanded(child: Text(s,
                  style: const TextStyle(color: Colors.white70, fontSize: 12))),
              if (widget.onTap != null)
                Icon(Icons.chevron_right,
                    color: widget.color.withValues(alpha: 0.5), size: 14),
            ]),
          ),
        )),
      ],
    ]);
  }
}


class _MessageInboxSheet extends StatefulWidget {
  final List<Map<String, dynamic>> allMessages;
  final List<Map<String, dynamic>> unreadMessages;
  final Future<void> Function(int serverId) onMarkRead;

  const _MessageInboxSheet({
    required this.allMessages,
    required this.unreadMessages,
    required this.onMarkRead,
  });

  @override
  State<_MessageInboxSheet> createState() => _MessageInboxSheetState();
}

class _MessageInboxSheetState extends State<_MessageInboxSheet> {
  late List<Map<String, dynamic>> _all;
  late List<Map<String, dynamic>> _unread;
  final Set<int> _marking = {};

  @override
  void initState() {
    super.initState();
    _all = List.from(widget.allMessages);
    _unread = List.from(widget.unreadMessages);
  }

  /// Group messages by time period (This Week / This Month / Month Year)
  Map<String, List<Map<String, dynamic>>> _group(
      List<Map<String, dynamic>> msgs) {
    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (final msg in msgs) {
      String key = 'Unknown';
      try {
        final d = DateTime.parse(msg['created_at'] ?? '');
        final now = DateTime.now();
        final diff = now.difference(d).inDays;
        if (diff < 7) {
          key = 'This Week';
        } else if (d.year == now.year && d.month == now.month) {
          key = 'This Month';
        } else {
          const months = [
            'Jan','Feb','Mar','Apr','May','Jun',
            'Jul','Aug','Sep','Oct','Nov','Dec'
          ];
          key = d.year == now.year
              ? months[d.month - 1]
              : '${months[d.month - 1]} ${d.year}';
        }
      } catch (_) {}
      grouped.putIfAbsent(key, () => []).add(msg);
    }
    return grouped;
  }

  List<String> _orderedKeys(Map<String, List<dynamic>> grouped) {
    final keys = <String>[];
    if (grouped.containsKey('This Week')) keys.add('This Week');
    if (grouped.containsKey('This Month')) keys.add('This Month');
    for (final k in grouped.keys) {
      if (k != 'This Week' && k != 'This Month') keys.add(k);
    }
    return keys;
  }

  @override
  Widget build(BuildContext context) {
    final unreadCount = _unread.length;
    final grouped = _group(_all);
    final orderedKeys = _orderedKeys(grouped);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.92,
      builder: (_, ctrl) => Column(
        children: [
          Container(
            width: 40, height: 4,
            margin: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(99)),
          ),
          // Header
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(children: [
              const Icon(Icons.message,
                  color: Color(0xFFF5A623), size: 16),
              const SizedBox(width: 8),
              const Text('MESSAGES FROM ADMIN',
                  style: TextStyle(
                      color: Color(0xFFF5A623),
                      fontSize: 10,
                      letterSpacing: 3,
                      fontWeight: FontWeight.bold)),
              const Spacer(),
              if (unreadCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(99)),
                  child: Text('$unreadCount unread',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold)),
                ),
            ]),
          ),
          const SizedBox(height: 8),
          // Body
          Expanded(
            child: _all.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.mark_email_read,
                            color: Colors.white24, size: 40),
                        SizedBox(height: 10),
                        Text('No messages yet',
                            style: TextStyle(color: Colors.white38)),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: ctrl,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: orderedKeys.length,
                    itemBuilder: (_, gi) {
                      final groupKey = orderedKeys[gi];
                      final msgs = grouped[groupKey]!;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Group header
                          Padding(
                            padding: const EdgeInsets.only(
                                top: 14, bottom: 6),
                            child: Row(children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF5A623)
                                      .withValues(alpha: 0.15),
                                  borderRadius:
                                      BorderRadius.circular(99),
                                  border: Border.all(
                                      color: const Color(0xFFF5A623)
                                          .withValues(alpha: 0.4)),
                                ),
                                child: Text(groupKey,
                                    style: const TextStyle(
                                        color: Color(0xFFF5A623),
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 1.5)),
                              ),
                              const SizedBox(width: 8),
                              Text('${msgs.length}',
                                  style: const TextStyle(
                                      color: Colors.white38,
                                      fontSize: 10)),
                            ]),
                          ),
                          // Messages in this group
                          ...msgs.asMap().entries.map((entry) {
                            final msg = entry.value;
                            final serverId =
                                msg['server_id'] as int?;
                            final isRead = msg['read_at'] != null;
                            final isMarking = serverId != null &&
                                _marking.contains(serverId);
                            final dateStr =
                                (msg['created_at']?.toString() ?? '')
                                        .length >=
                                    16
                                    ? msg['created_at']
                                        .toString()
                                        .substring(0, 16)
                                        .replaceAll('T', ' ')
                                    : (msg['created_at']
                                            ?.toString() ??
                                        '');

                          } catch (_) {
                  return Container(
                              margin:
                                  const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: isRead
                                    ? const Color(0xFF0D1B2A)
                                    : const Color(0xFF0D1B2A),
                                borderRadius:
                                    BorderRadius.circular(10),
                                border: Border.all(
                                  color: isRead
                                      ? const Color(0xFF1E3A5F)
                                      : const Color(0xFFF5A623)
                                          .withValues(alpha: 0.4),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Row(children: [
                                    Icon(
                                      Icons.admin_panel_settings,
                                      color: isRead
                                          ? Colors.white38
                                          : const Color(0xFFF5A623),
                                      size: 14,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      msg['from_admin_name'] ??
                                          'Admin',
                                      style: TextStyle(
                                          color: isRead
                                              ? Colors.white54
                                              : const Color(
                                                  0xFFF5A623),
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12),
                                    ),
                                    const Spacer(),
                                    if (isRead)
                                      const Icon(Icons.done_all,
                                          color: Colors.green,
                                          size: 12),
                                    if (!isRead)
                                      Container(
                                        padding:
                                            const EdgeInsets.symmetric(
                                                horizontal: 6,
                                                vertical: 1),
                                        decoration: BoxDecoration(
                                          color: Colors.red,
                                          borderRadius:
                                              BorderRadius.circular(99),
                                        ),
                                        child: const Text('NEW',
                                            style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 8,
                                                fontWeight:
                                                    FontWeight.bold)),
                                      ),
                                    const SizedBox(width: 6),
                                    Text(dateStr,
                                        style: const TextStyle(
                                            color: Colors.white38,
                                            fontSize: 10)),
                                  ]),
                                  const SizedBox(height: 8),
                                  Text(msg['message'] ?? '',
                                      style: TextStyle(
                                          color: isRead
                                              ? Colors.white70
                                              : Colors.white,
                                          fontSize: 13)),
                                  if (!isRead) ...[
                                    const SizedBox(height: 10),
                                    Align(
                                      alignment:
                                          Alignment.centerRight,
                                      child: TextButton.icon(
                                        onPressed: (isMarking ||
                                                serverId == null)
                                            ? null
                                            : () async {
                                                setState(() => _marking
                                                    .add(serverId));
                                                await widget
                                                    .onMarkRead(
                                                        serverId);
                                                if (mounted) {
                                                  setState(() {
                                                    final idx2 = _all
                                                        .indexWhere((m) =>
                                                            m['server_id'] ==
                                                            serverId);
                                                    if (idx2 != -1) {
                                                      _all[idx2] = Map.from(
                                                          _all[idx2])
                                                        ..['read_at'] =
                                                            DateTime.now()
                                                                .toIso8601String();
                                                    }
                                                    _unread.removeWhere(
                                                        (m) =>
                                                            m['server_id'] ==
                                                            serverId);
                                                    _marking.remove(
                                                        serverId);
                                                  });
                                                }
                                              },
                                        icon: isMarking
                                            ? const SizedBox(
                                                width: 14,
                                                height: 14,
                                                child:
                                                    CircularProgressIndicator(
                                                        strokeWidth:
                                                            2,
                                                        color: Colors
                                                            .green))
                                            : const Icon(Icons.check,
                                                size: 14,
                                                color: Colors.green),
                                        label: const Text(
                                            'Mark as Read',
                                            style: TextStyle(
                                                color: Colors.green,
                                                fontSize: 11)),
                                        style: TextButton.styleFrom(
                                          padding:
                                              const EdgeInsets.symmetric(
                                                  horizontal: 10,
                                                  vertical: 4),
                                          minimumSize: Size.zero,
                                          tapTargetSize:
                                              MaterialTapTargetSize
                                                  .shrinkWrap,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            );
                          }),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
  
}

// ── Staff My Activity — collapsible grouped widget ────────────────────────────
class _StaffActivityGrouped extends StatefulWidget {
  final List<dynamic> history;
  final ScrollController controller;
  final AppColors colors;
  const _StaffActivityGrouped({
    required this.history,
    required this.controller,
    required this.colors,
  });
  @override
  State<_StaffActivityGrouped> createState() => _StaffActivityGroupedState();
}

class _StaffActivityGroupedState extends State<_StaffActivityGrouped> {
  final Set<String> _expanded = {'Today'};

  String _periodKey(dynamic e) {
    try {
      final d = DateTime.parse(e['timestamp'] ?? '');
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final entryDay = DateTime(d.year, d.month, d.day);
      if (entryDay == today) return 'Today';
      final diff = today.difference(entryDay).inDays;
      if (diff < 7) return 'This Week';
      if (d.year == now.year && d.month == now.month) return 'This Month';
      const months = ['January','February','March','April','May','June',
                      'July','August','September','October','November','December'];
      return d.year == now.year
          ? months[d.month - 1]
          : '${months[d.month - 1]} ${d.year}';
    } catch (_) { return 'Unknown'; }
  }

  String _fmtTime(dynamic e) {
    try {
      final d = DateTime.parse(e['timestamp'] ?? '');
      return '${d.day}/${d.month}  ${d.hour.toString().padLeft(2,'0')}:${d.minute.toString().padLeft(2,'0')}';
    } catch (_) { return ''; }
  }

  List<String> _orderedKeys(Map<String, List<dynamic>> g) {
    const priority = ['Today', 'This Week', 'This Month'];
    return [
      ...priority.where((k) => g.containsKey(k)),
      ...g.keys.where((k) => !priority.contains(k)).toList(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final Map<String, List<dynamic>> grouped = {};
    for (final e in widget.history) {
      grouped.putIfAbsent(_periodKey(e), () => []).add(e);
    }
    final keys = _orderedKeys(grouped);

    return ListView.builder(
      controller: widget.controller,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      itemCount: keys.length,
      itemBuilder: (_, i) {
        final key = keys[i];
        final items = grouped[key]!;
        final isOpen = _expanded.contains(key);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: () => setState(() {
                if (isOpen) _expanded.remove(key);
                else _expanded.add(key);
              }),
              child: Container(
                margin: const EdgeInsets.only(top: 8, bottom: 4),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: widget.colors.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: widget.colors.border),
                ),
                child: Row(children: [
                  Icon(isOpen ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right,
                      color: widget.colors.accent, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text(key,
                      style: TextStyle(color: widget.colors.textPrimary,
                          fontWeight: FontWeight.bold, fontSize: 12))),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: widget.colors.accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text('${items.length}',
                        style: TextStyle(color: widget.colors.accent,
                            fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                ]),
              ),
            ),
            if (isOpen)
              ...items.map((e) {
                try {
                  final d = DateTime.parse(e['timestamp'] ?? '');
                  final ts = '${d.day}/${d.month} ${d.hour.toString().padLeft(2,'0')}:${d.minute.toString().padLeft(2,'0')}';
                  return Container(
                  margin: const EdgeInsets.only(bottom: 5, left: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: widget.colors.surfaceVariant,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: widget.colors.border),
                  ),
                  child: Row(children: [
                    const Icon(Icons.circle, color: Color(0xFFF5A623), size: 6),
                    const SizedBox(width: 10),
                    Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(e['event_detail'] ?? e['event_type'] ?? '',
                            style: TextStyle(color: widget.colors.textPrimary, fontSize: 12)),
                        if ((e['actor'] ?? '').toString().isNotEmpty)
                          Text(e['actor'].toString(),
                              style: TextStyle(color: widget.colors.textHint, fontSize: 10)),
                      ],
                    )),
                    Text(_fmtTime(e),
                        style: TextStyle(color: widget.colors.textHint, fontSize: 10)),
                  ]),
                );
              }),
          ],
        );
      },
    );
  }
}
// ── Theme toast overlay ───────────────────────────────────────────────────────
class _ThemeToast extends StatefulWidget {
  final String message;
  final VoidCallback onDone;
  const _ThemeToast({required this.message, required this.onDone});
  @override
  State<_ThemeToast> createState() => _ThemeToastState();
}

class _ThemeToastState extends State<_ThemeToast>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this,
        duration: const Duration(milliseconds: 1800));
    _opacity = TweenSequence([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0)
          .chain(CurveTween(curve: Curves.easeIn)), weight: 20),
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0)
          .chain(CurveTween(curve: Curves.easeOut)), weight: 30),
    ]).animate(_ctrl);
    _ctrl.forward().then((_) => widget.onDone());
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 100,
      left: 0, right: 0,
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _opacity,
          builder: (_, __) => Opacity(
            opacity: _opacity.value,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A3A5C).withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Text(widget.message,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        decoration: TextDecoration.none)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}