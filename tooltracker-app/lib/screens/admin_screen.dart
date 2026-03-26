import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../services/sync_service.dart';
import '../database/db_helper.dart';
import '../models/dispatch.dart';
import 'login_screen.dart';
import 'dispatch_export_screen.dart';
import '../models/instrument.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;
  String _adminName = '';
  String _adminUsername = '';
  bool _isSyncing = false;
  bool _isConnected = false;
  int _totalNotifCount = 0;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  

  void _showNotifications() async {
    final instruments = await DBHelper.instance.getAllInstruments();
    final dispatches = await DBHelper.instance.getAllDispatches();
    final overdueInstruments = instruments.where((i) => i.isOverdue).toList();
    final forRepair = instruments.where((i) => i.currentCondition == 'For Repair').toList();
    final forCondemn = instruments.where((i) => i.currentCondition == 'Condemning').toList();
    final calibOverdue = instruments.where((i) => i.isCalibrationOverdue).toList();
    final calibDueSoon = instruments.where((i) => i.calibrationDueSoon && !i.isCalibrationOverdue).toList();
    final overdueDispatches = dispatches.where((d) => d.dateIn == null).toList();
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
        builder: (_, ctrl) => Column(children: [
          Container(
            width: 40, height: 4,
            margin: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
                color: Colors.white24, borderRadius: BorderRadius.circular(99)),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('NOTIFICATIONS',
                  style: TextStyle(
                      color: Color(0xFFF5A623), fontSize: 10,
                      letterSpacing: 3, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView(
              controller: ctrl,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                if (overdueDispatches.isEmpty && overdueInstruments.isEmpty &&
                    forRepair.isEmpty && forCondemn.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: Text('No notifications',
                        style: TextStyle(color: Colors.white38))),
                  ),
                if (overdueDispatches.isNotEmpty)
                  _adminNotifSection('ACTIVE DISPATCHES', Colors.blue,
                      Icons.outbox,
                      overdueDispatches.map((d) => '${d.dispatchNo} — ${d.testEngineer}').toList(),
                      onTap: () { Navigator.pop(context); _tabController.animateTo(1); }),
                if (overdueInstruments.isNotEmpty)
                  _adminNotifSection('OVERDUE INSTRUMENTS', Colors.orange,
                      Icons.build,
                      overdueInstruments.map((i) => '${i.instrumentCode} — ${i.instrumentName}').toList(),
                      onTap: () { Navigator.pop(context); _tabController.animateTo(3); }),
                if (forRepair.isNotEmpty)
                  _adminNotifSection('SET FOR REPAIR', Colors.amber,
                      Icons.build_circle,
                      forRepair.map((i) => '${i.instrumentCode} — ${i.instrumentName}').toList(),
                      onTap: () { Navigator.pop(context); _tabController.animateTo(3); }),
                if (forCondemn.isNotEmpty)
                  _adminNotifSection('PENDING CONDEMNATION', Colors.red,
                      Icons.gavel,
                      forCondemn.map((i) => '${i.instrumentCode} — ${i.instrumentName}').toList(),
                      onTap: () { Navigator.pop(context); _tabController.animateTo(4); }),
                if (calibOverdue.isNotEmpty)
                  _adminNotifSection('CALIBRATION OVERDUE', Colors.blue,
                      Icons.science,
                      calibOverdue.map((i) => '${i.instrumentCode} — ${i.instrumentName}').toList(),
                      onTap: () { Navigator.pop(context); _tabController.animateTo(3); }),
                if (calibDueSoon.isNotEmpty)
                  _adminNotifSection('CALIBRATION DUE SOON', Colors.lightBlue,
                      Icons.science_outlined,
                      calibDueSoon.map((i) => '${i.instrumentCode} — due in ${i.daysUntilCalibrationDue} days').toList(),
                      onTap: () { Navigator.pop(context); _tabController.animateTo(3); }),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  Widget _adminNotifSection(String label, Color color, IconData icon,
      List<String> items, {VoidCallback? onTap}) {
    return _CollapsibleNotifSection(
      label: label, color: color, icon: icon,
      items: items, onTap: onTap,
    );
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _loadAdminName();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAdminName() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
      _adminName = prefs.getString('user_name') ?? 'Admin';
      _adminUsername = prefs.getString('username') ?? '';
    });
    // Count total notifications for badge
    try {
      final instruments = await DBHelper.instance.getAllInstruments();
      final dispatches = await DBHelper.instance.getAllDispatches();
      final condemnCount = instruments.where((i) => i.currentCondition == 'Condemning').length;
      final repairCount = instruments.where((i) => i.currentCondition == 'For Repair').length;
      final overdueCount = instruments.where((i) => i.isOverdue).length;
      final calibOverdueCount = instruments.where((i) => i.isCalibrationOverdue).length;
      final overdueDispCount = dispatches.where((d) => d.dateIn == null && !d.isStudent).length;
      if (mounted) setState(() {
        _totalNotifCount = condemnCount + repairCount + overdueCount + calibOverdueCount + overdueDispCount;
      });
    } catch (_) {}
    }
    // Poll connectivity
    _updateConnectivity();
  }

  Future<void> _updateConnectivity() async {
    final connected = await SyncService.isConnected();
    if (mounted) setState(() => _isConnected = connected);
    Future.delayed(const Duration(seconds: 10), () {
      if (mounted) _updateConnectivity();
    });
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
          context, MaterialPageRoute(builder: (_) => const LoginScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFF0D1B2A),
      drawer: _buildAdminDrawer(),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildTabBar(),
            Expanded(child: _buildTabViews()),
          ],
        ),
      ),
    );
  }

  Widget _buildAdminDrawer() {
    return Drawer(
      backgroundColor: const Color(0xFF111827),
      child: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF1A1A2E), Color(0xFF111827)],
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
                      color: const Color(0xFFF5A623).withValues(alpha: 0.15),
                      border: Border.all(
                          color: const Color(0xFFF5A623), width: 2),
                    ),
                    child: Center(
                      child: Text(
                        _adminName.isNotEmpty
                            ? _adminName[0].toUpperCase()
                            : 'A',
                        style: const TextStyle(
                            color: Color(0xFFF5A623),
                            fontSize: 24,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(_adminName,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Text('@$_adminUsername',
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 13)),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5A623).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(
                          color:
                              const Color(0xFFF5A623).withValues(alpha: 0.4)),
                    ),
                    child: const Text(
                      'ADMIN',
                      style: TextStyle(
                          color: Color(0xFFF5A623),
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
            ListTile(
              leading: const Icon(Icons.notifications_outlined,
                  color: Colors.white54),
              title: const Text('Notifications',
                  style: TextStyle(color: Colors.white, fontSize: 14)),
              onTap: () {
                Navigator.pop(context);
                _showNotifications();
              },
            ),
            ListTile(
              leading: const Icon(Icons.history, color: Colors.white54),
              title: const Text('Admin Activity',
                  style: TextStyle(color: Colors.white, fontSize: 14)),
              onTap: () {
                Navigator.pop(context);
                _showAdminActivity();
              },
            ),
            ListTile(
              leading: const Icon(Icons.message_outlined, color: Colors.white54),
              title: const Text('Message History',
                  style: TextStyle(color: Colors.white, fontSize: 14)),
              onTap: () {
                Navigator.pop(context);
                _showAdminMessageHistory();
              },
            ),
            ListTile(
              leading: const Icon(Icons.info_outline, color: Colors.white54),
              title: const Text('About',
                  style: TextStyle(color: Colors.white, fontSize: 14)),
              onTap: () {
                Navigator.pop(context);
                _showAbout();
              },
            ),
            ListTile(
              leading: const Icon(Icons.person_outline, color: Colors.white54),
              title: const Text('My Profile',
                  style: TextStyle(color: Colors.white, fontSize: 14)),
              onTap: () {
                Navigator.pop(context);
                _showAdminProfile();
              },
            ),
            ListTile(
              leading: const Icon(Icons.menu_book_outlined, color: Colors.white54),
              title: const Text('User Manual',
                  style: TextStyle(color: Colors.white, fontSize: 14)),
              onTap: () {
                Navigator.pop(context);
                _showUserManual();
              },
            ),
            const Divider(color: Colors.white12, height: 1),
            const Spacer(),
            ListTile(
              leading:
                  const Icon(Icons.logout, color: Colors.redAccent),
              title: const Text('Log Out',
                  style:
                      TextStyle(color: Colors.redAccent, fontSize: 14)),
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

  void _showAdminActivity() async {
    final logs = await DBHelper.instance.getActivityLog(limit: 200);
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A3A5C),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        builder: (_, sc) => Column(children: [
          Container(width: 40, height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(color: Colors.white24,
                  borderRadius: BorderRadius.circular(99))),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Align(alignment: Alignment.centerLeft,
              child: Text('ADMIN ACTIVITY LOG',
                  style: TextStyle(color: Color(0xFFF5A623),
                      fontSize: 10, letterSpacing: 3, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: logs.isEmpty
                ? const Center(child: Text('No activity recorded yet',
                    style: TextStyle(color: Colors.white38)))
                : _UserHistoryGrouped(history: logs, controller: sc),
          ),
        ]),
      ),
    );
  }

  void _showAdminMessageHistory() async {
    final messages = await ApiService.getMessageStatus();
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A3A5C),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        builder: (_, sc) => Column(children: [
          Container(width: 40, height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(color: Colors.white24,
                  borderRadius: BorderRadius.circular(99))),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Align(alignment: Alignment.centerLeft,
              child: Text('MESSAGE HISTORY',
                  style: TextStyle(color: Color(0xFFF5A623),
                      fontSize: 10, letterSpacing: 3, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: messages == null || messages.isEmpty
                ? const Center(child: Text('No messages sent',
                    style: TextStyle(color: Colors.white38)))
                : _AdminMessageHistoryList(messages: messages, controller: sc),
          ),
        ]),
      ),
    );
  }

  void _showAbout() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A3A5C),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Row(children: [
          Icon(Icons.construction, color: Color(0xFFF5A623), size: 20),
          SizedBox(width: 8),
          Text('AMTEC Tool Tracker',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ]),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Version 4.8', style: TextStyle(color: Color(0xFFF5A623),
                fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            Text('Agricultural Machinery Testing and Evaluation Center\nUniversity of the Philippines Los Baños',
                style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.5)),
            SizedBox(height: 12),
            Text('Tracks, manages, and monitors AMTEC instruments including dispatches, calibration schedules, and condition history.',
                style: TextStyle(color: Colors.white54, fontSize: 12, height: 1.5)),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF5A623),
                foregroundColor: Colors.black),
            child: const Text('OK', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showAdminProfile() {
    final passwordCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    final hintCtrl = TextEditingController();
    bool obscure = true;
    bool obscureConfirm = true;
    bool editing = false;
    bool saving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF111827),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSt) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.55,
          maxChildSize: 0.85,
          builder: (_, sc) => ListView(
            controller: sc,
            padding: const EdgeInsets.all(20),
            children: [
              Center(child: Container(width: 40, height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(color: Colors.white24,
                      borderRadius: BorderRadius.circular(99)))),
              const Text('MY PROFILE', style: TextStyle(
                  color: Color(0xFFF5A623), fontSize: 10,
                  letterSpacing: 3, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              // Avatar
              Center(
                child: Container(
                  width: 72, height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFF5A623).withValues(alpha: 0.15),
                    border: Border.all(color: const Color(0xFFF5A623), width: 2),
                  ),
                  child: Center(child: Text(
                    _adminName.isNotEmpty ? _adminName[0].toUpperCase() : 'A',
                    style: const TextStyle(color: Color(0xFFF5A623),
                        fontSize: 28, fontWeight: FontWeight.bold),
                  )),
                ),
              ),
              const SizedBox(height: 16),
              _profileRow('Full Name', _adminName, Icons.person),
              _profileRow('Username', '@$_adminUsername', Icons.alternate_email),
              _profileRow('Role', 'Administrator', Icons.admin_panel_settings),
              _profileRow('Department', 'Agricultural Machinery Testing and Evaluation Center', Icons.business),
              _profileRow('Institution', 'University of the Philippines Los Baños', Icons.school),
              const SizedBox(height: 16),
              const Divider(color: Colors.white12),
              const SizedBox(height: 12),
              const Text('CHANGE PASSWORD', style: TextStyle(
                  color: Color(0xFFF5A623), fontSize: 10,
                  letterSpacing: 3, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              if (!editing)
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => setSt(() => editing = true),
                    icon: const Icon(Icons.lock_outline, size: 16),
                    label: const Text('Change Password'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFF5A623),
                      side: const BorderSide(color: Color(0xFFF5A623)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                )
              else ...[
                _pwField('New Password', passwordCtrl, obscure,
                    () => setSt(() => obscure = !obscure)),
                const SizedBox(height: 8),
                _pwField('Confirm Password', confirmCtrl, obscureConfirm,
                    () => setSt(() => obscureConfirm = !obscureConfirm)),
                const SizedBox(height: 8),
                TextField(
                  controller: hintCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Password Hint (optional)',
                    labelStyle: const TextStyle(color: Colors.white38),
                    hintText: 'e.g. My favorite color + year',
                    hintStyle: const TextStyle(color: Colors.white24, fontSize: 11),
                    prefixIcon: const Icon(Icons.lightbulb_outline, color: Color(0xFFF5A623)),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Color(0xFF1E3A5F))),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Color(0xFFF5A623))),
                    filled: true, fillColor: const Color(0xFF0D1B2A),
                  ),
                ),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => setSt(() {
                        editing = false;
                        passwordCtrl.clear();
                        confirmCtrl.clear();
                        hintCtrl.clear();
                      }),
                      style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white54,
                          side: const BorderSide(color: Colors.white24),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: saving ? null : () async {
                        final newPwd = passwordCtrl.text.trim();
                        final confirmPwd = confirmCtrl.text.trim();
                        if (newPwd.length < 4) {
                          ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                              content: Text('Password must be at least 4 characters'),
                              backgroundColor: Colors.red));
                          return;
                        }
                        if (newPwd != confirmPwd) {
                          ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                              content: Text('Passwords do not match'),
                              backgroundColor: Colors.red));
                          return;
                        }
                        setSt(() => saving = true);
                        final prefs = await SharedPreferences.getInstance();
                        final userId = prefs.getInt('user_id') ?? 0;
                        final ok = await ApiService.changePassword(userId, newPwd);
                        setSt(() => saving = false);
                        if (!ctx.mounted) return;
                        Navigator.pop(ctx);
                        if (ok) {
                          ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                              content: Text('Password changed successfully'),
                              backgroundColor: Colors.green));
                        } else {
                          ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                              content: Text('Failed to change password'),
                              backgroundColor: Colors.red));
                        }
                      },
                      style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFF5A623),
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                      child: saving
                          ? const SizedBox(width: 18, height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                          : const Text('Save', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ]),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _pwField(String label, TextEditingController ctrl, bool obscure, VoidCallback toggle) {
    return TextField(
      controller: ctrl,
      obscureText: obscure,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white38),
        prefixIcon: const Icon(Icons.lock, color: Color(0xFFF5A623)),
        suffixIcon: IconButton(
          icon: Icon(obscure ? Icons.visibility_off : Icons.visibility, color: Colors.white38),
          onPressed: toggle,
        ),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFF1E3A5F))),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFF5A623))),
        filled: true, fillColor: const Color(0xFF0D1B2A),
      ),
    );
  }

  Widget _profileRow(String label, String value, IconData icon) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A3A5C),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF1E3A5F)),
      ),
      child: Row(children: [
        Icon(icon, color: const Color(0xFFF5A623), size: 16),
        const SizedBox(width: 12),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: Colors.white38, fontSize: 10)),
            Text(value, style: const TextStyle(color: Colors.white, fontSize: 13,
                fontWeight: FontWeight.w500)),
          ],
        )),
      ]),
    );
  }

  void _showUserManual() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A3A5C),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        builder: (_, sc) => ListView(
          controller: sc,
          padding: const EdgeInsets.all(20),
          children: [
            Center(child: Container(width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(color: Colors.white24,
                    borderRadius: BorderRadius.circular(99)))),
            const Text('USER MANUAL', style: TextStyle(color: Color(0xFFF5A623),
                fontSize: 10, letterSpacing: 3, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            _manualSection('Getting Started', Icons.play_circle_outline, [
              'Log in with your admin username and password',
              'Tap your name in the top-left to open the side panel',
              'Use the sync button (top-right) to pull latest data from the server',
              'The app works offline — all changes sync automatically when connected',
            ]),
            _manualSection('Dashboard Tab', Icons.dashboard, [
              'Shows a summary: total instruments, active dispatches, borrow count, and overdue items',
              'Scroll down to see the live Activity Log grouped by Today, This Week, This Month, and older',
              'Tap the EXPORT DATA button to export dispatch reports, borrow history, condition history, upcoming schedules, and overdue instruments',
              'Pull down anywhere on the dashboard to manually refresh',
            ]),
            _manualSection('Export Data', Icons.file_download, [
              'Dispatch Report: tick the checkbox, set a FROM date, choose Active and/or Returned — then press Export',
              'Borrow History: same format as Dispatch — tick, set date, choose filters',
              'Instrument Condition History: choose By Date Range (shows records from the selected date) or Select Instruments (tick individual instruments from the inline list)',
              'Upcoming Schedule, Overdue, and Currently Out: tick the checkboxes and export directly — no extra config needed',
              'Multiple types can be selected at once — each becomes a separate sheet in one Excel file',
            ]),
            _manualSection('Users Tab', Icons.people, [
              'Lists all staff and admin accounts currently registered',
              'Tap the + button to create a new account — provide name, username, password, and role',
              'Tap the trash icon to delete a staff account (cannot delete admin accounts)',
              'Tap the history icon (clock) on any user to open their full activity log and sent messages',
              'From the history panel, tap SEND MESSAGE to send a notification to that staff member',
              'Activity history is grouped by Today, This Week, This Month, and older periods',
            ]),
            _manualSection('Instruments Tab (Admin)', Icons.construction, [
              'Browse all instruments with search and filter (All, Overdue, For Repair, Condemned, Upcoming)',
              'Tap any instrument card to open its full history — all condition changes, dispatches, borrows, and calibrations',
              'Use the + button to register a new instrument with code, name, serial number, and location',
              'Tap the edit (pencil) icon to change condition, set repair/condemn dates, add notes, and manage calibration',
              'Condition changes are logged automatically with the actor\'s name and timestamp',
            ]),
            _manualSection('Condemn Tab', Icons.gavel, [
              'Lists all instruments currently marked as Condemning by any staff member',
              'Each card shows the instrument code, name, condition, and the date it was flagged',
              'Tap APPROVE & DELETE to permanently remove the instrument from the system — this cannot be undone',
              'Tap DENY to reject the condemnation — the instrument reverts to For Repair status',
              'Revert Requests also appear here: when a staff member requests to change a condemned instrument back to Functioning or For Repair, the admin sees it here and can APPROVE or DENY',
              'After acting on all items, the notification badge on your name will clear',
            ]),
            _manualSection('Dispatch & Borrow Records', Icons.list_alt, [
              'View all dispatch records sorted by most recent',
              'Filter by All, Out (active), or Returned using the chips at the top',
              'Tap any record to expand its details: instruments included, test engineer, dates, and return conditions',
              'Borrow records (student transactions) are in a separate tab with the same layout',
            ]),
            _manualSection('Notifications & Messages', Icons.notifications, [
              'Tap your name to open the side panel — the red badge shows total pending notifications',
              'Notifications lists: overdue instruments, instruments for repair, condemned instruments, overdue dispatches, and calibration alerts',
              'Message History in the side panel shows all messages sent to staff, including read status',
              'Sending a message: go to Users tab → tap history icon → tap Send Message',
            ]),
            _manualSection('My Profile', Icons.person, [
              'Access via the side panel → My Profile',
              'Shows your full name, username, role, department, and institution',
              'Use Change Password to update your admin password — minimum 4 characters',
            ]),
            _manualSection('Sync & Connectivity', Icons.sync, [
              'The connectivity indicator (top-right) shows green when online',
              'Tap the sync icon to manually push all pending changes and pull latest server data',
              'Changes made offline are queued and automatically pushed on reconnection',
              'Instrument edits, dispatch creations, and condition changes all sync automatically',
            ]),
          ],
        ),
      ),
    );
  }

  Widget _manualSection(String title, IconData icon, List<String> items) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1B2A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF1E3A5F)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, color: const Color(0xFFF5A623), size: 16),
          const SizedBox(width: 8),
          Text(title, style: const TextStyle(color: Colors.white,
              fontWeight: FontWeight.bold, fontSize: 13)),
        ]),
        const SizedBox(height: 8),
        ...items.map((s) => Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('• ', style: TextStyle(color: Color(0xFFF5A623))),
            Expanded(child: Text(s, style: const TextStyle(
                color: Colors.white70, fontSize: 12))),
          ]),
        )),
      ]),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF1A1A2E), Color(0xFF0D1B2A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFF5A623).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFFF5A623).withValues(alpha: 0.5)),
            ),
            child: const Row(children: [
              Icon(Icons.admin_panel_settings,
                  color: Color(0xFFF5A623), size: 14),
              SizedBox(width: 4),
              Text('ADMIN',
                  style: TextStyle(
                      color: Color(0xFFF5A623),
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2)),
            ]),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Expanded(
            child: GestureDetector(
              onTap: () => _scaffoldKey.currentState?.openDrawer(),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('AMTEC: Tool Tracker',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15)),
                  Row(children: [
                    Text('Welcome, $_adminName',
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 11)),
                    const SizedBox(width: 4),
                    const Icon(Icons.arrow_forward_ios,
                        color: Colors.white24, size: 9),
                  ]),
                ],
              ),
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
    ),
          const SizedBox(width: 12),
          // ── Connectivity pill ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: (_isConnected ? Colors.green : Colors.red)
                  .withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(99),
              border: Border.all(
                  color: _isConnected ? Colors.green : Colors.red,
                  width: 0.8),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(
                _isConnected ? Icons.wifi : Icons.wifi_off,
                color: _isConnected ? Colors.green : Colors.red,
                size: 11,
              ),
              const SizedBox(width: 3),
              Text(
                _isConnected ? 'Online' : 'Offline',
                style: TextStyle(
                    color: _isConnected ? Colors.green : Colors.red,
                    fontSize: 9,
                    fontWeight: FontWeight.bold),
              ),
            ]),
          ),
          const SizedBox(width: 8),
          // ── Sync button ──
          GestureDetector(
            onTap: () async {
              setState(() => _isSyncing = true);
              final result = await SyncService.instance.syncAll();
              if (mounted) {
                setState(() => _isSyncing = false);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(result.synced > 0
                      ? '${result.synced} synced'
                      : 'Up to date'),
                  backgroundColor: Colors.green,
                  duration: const Duration(seconds: 2),
                ));
              }
            },
            child: _isSyncing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Color(0xFFF5A623)))
                : const Icon(Icons.sync,
                    color: Color(0xFFF5A623), size: 22),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      color: const Color(0xFF111827),
      child: TabBar(
        controller: _tabController,
        indicatorColor: const Color(0xFFF5A623),
        indicatorWeight: 3,
        labelColor: const Color(0xFFF5A623),
        unselectedLabelColor: Colors.white38,
        labelStyle:
            const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
        tabs: const [
          Tab(icon: Icon(Icons.dashboard, size: 18), text: 'Dashboard'),
          Tab(icon: Icon(Icons.list_alt, size: 18), text: 'Dispatches'),
          Tab(icon: Icon(Icons.people, size: 18), text: 'Users'),
          Tab(icon: Icon(Icons.construction, size: 18), text: 'Instruments'),
          Tab(icon: Icon(Icons.gavel, size: 18), text: 'Condemn'),
        ], 
      ),
    );
  }

  Widget _buildTabViews() {
    return TabBarView(
      controller: _tabController,
      children: [
        const _AdminDashboardTab(),
        _AdminDispatchesTab(),
        _AdminUsersTab(),
        _AdminInstrumentsTab(),
        _AdminCondemnTab(),
      ],
    );
  }
}

// ══════════════════════════════════════════════
// TAB 1 — DASHBOARD
// ══════════════════════════════════════════════
class _AdminDashboardTab extends StatefulWidget {
  const _AdminDashboardTab();

  @override
  State<_AdminDashboardTab> createState() => _AdminDashboardTabState();
}

class _AdminDashboardTabState extends State<_AdminDashboardTab> {
  List<Dispatch> _activeDispatches = [];
  Map<String, List<DispatchItem>> _activeItems = {};
  List<dynamic> _logs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      if (await SyncService.isConnected()) {
        try {
          await SyncService.instance
              .syncAll()
              .timeout(const Duration(seconds: 15));
        } catch (_) {}
      }
    } catch (_) {}

    try {
      final dispatches = await DBHelper.instance.getAllDispatches();
      final active = dispatches.where((d) => d.dateIn == null).toList();
      final Map<String, List<DispatchItem>> itemMap = {};
      for (final d in active) {
        if (d.id != null) {
          final items = await DBHelper.instance.getDispatchItems(d.id!);
          itemMap[d.dispatchNo] = items;
        }
      }
      List<dynamic> logs = [];
      try {
        logs = await DBHelper.instance.getActivityLog(limit: 80);
      } catch (_) {}
      if (logs.isEmpty) {
        try {
          logs = await ApiService.getActivityLog(limit: 80) ?? [];
        } catch (_) {}
      }
      if (mounted) {
        setState(() {
          _activeDispatches = active;
          _activeItems = itemMap;
          _logs = logs;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }


  void _showExportMenu() {
    bool expDispatch = false;
    bool expBorrow = false;
    bool expCondHistory = false;
    bool expUpcoming = false;
    bool expOverdue = false;
    bool expInstrumentsOut = false;
    // Dispatch sub-options
    DateTime dispFromDate = DateTime(DateTime.now().year, DateTime.now().month, 1);
    bool dispActive = true;
    bool dispReturned = true;
    // Borrow sub-options
    DateTime borrowFromDate = DateTime(DateTime.now().year, DateTime.now().month, 1);
    bool borrowActive = true;
    bool borrowReturned = true;
    // Condition history sub-options
    bool condByDate = true;
    DateTime condFromDate = DateTime(DateTime.now().year, DateTime.now().month, 1);
    List<String> condAllCodes = [];
    List<String> condSelectedCodes = [];
    String condSearch = '';
    // Load instrument codes for inline selection
    DBHelper.instance.getAllInstruments().then((list) {
      condAllCodes = list.map((i) => i.instrumentCode).toList()..sort();
      condSelectedCodes = List.from(condAllCodes);
    });


    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A3A5C),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheet) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          maxChildSize: 0.92,
          builder: (_, sc) => SingleChildScrollView(
            controller: sc,
            padding: const EdgeInsets.all(20),
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
                const Text('EXPORT OPTIONS',
                    style: TextStyle(
                        color: Color(0xFFF5A623),
                        fontSize: 10,
                        letterSpacing: 3,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                const Text('Select the data to include, configure options, then export.',
                    style: TextStyle(color: Colors.white38, fontSize: 12)),
                const SizedBox(height: 12),

                // ── Dispatch checkbox + sub-options ──
                _exportCheckbox('Dispatch Report', Icons.receipt_long,
                    Colors.blue, expDispatch,
                    (v) => setSheet(() => expDispatch = v)),
                if (expDispatch) ...[
                  Container(
                    margin: const EdgeInsets.only(left: 12, bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('DATE RANGE',
                            style: TextStyle(color: Colors.blue, fontSize: 9,
                                letterSpacing: 2, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        Row(children: [
                          const Text('From:', style: TextStyle(color: Colors.white54, fontSize: 11)),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () async {
                              final picked = await showDatePicker(
                                context: ctx,
                                initialDate: dispFromDate,
                                firstDate: DateTime(2020),
                                lastDate: DateTime.now(),
                                builder: (c, child) => Theme(
                                  data: ThemeData.dark().copyWith(
                                    colorScheme: const ColorScheme.dark(
                                        primary: Color(0xFFF5A623),
                                        surface: Color(0xFF1A3A5C)),
                                  ),
                                  child: child!,
                                ),
                              );
                              if (picked != null) setSheet(() => dispFromDate = picked);
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0D1B2A),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: Colors.blue.withValues(alpha: 0.5)),
                              ),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                Text(
                                  '${dispFromDate.day}/${dispFromDate.month}/${dispFromDate.year}',
                                  style: const TextStyle(color: Colors.white,
                                      fontSize: 11, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(width: 4),
                                const Icon(Icons.edit_calendar, color: Color(0xFFF5A623), size: 12),
                              ]),
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Text('To: Today', style: TextStyle(color: Colors.white38, fontSize: 11)),
                        ]),
                        const SizedBox(height: 10),
                        const Text('INCLUDE', style: TextStyle(color: Colors.blue, fontSize: 9,
                            letterSpacing: 2, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 6),
                        Row(children: [
                          _miniCheckbox('Active (Out)', dispActive, (v) => setSheet(() => dispActive = v)),
                          const SizedBox(width: 12),
                          _miniCheckbox('Returned', dispReturned, (v) => setSheet(() => dispReturned = v)),
                        ]),
                      ],
                    ),
                  ),
                ],

                _exportCheckbox('Borrow History', Icons.school,
                    Colors.purple, expBorrow,
                    (v) => setSheet(() => expBorrow = v)),
                if (expBorrow) ...[
                  Container(
                    margin: const EdgeInsets.only(left: 12, bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.purple.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.purple.withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('DATE RANGE', style: TextStyle(color: Colors.purple,
                            fontSize: 9, letterSpacing: 2, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        Row(children: [
                          const Text('From:', style: TextStyle(color: Colors.white54, fontSize: 11)),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () async {
                              final picked = await showDatePicker(
                                context: ctx,
                                initialDate: borrowFromDate,
                                firstDate: DateTime(2020),
                                lastDate: DateTime.now(),
                                builder: (c, child) => Theme(
                                  data: ThemeData.dark().copyWith(
                                    colorScheme: const ColorScheme.dark(
                                        primary: Color(0xFFF5A623),
                                        surface: Color(0xFF1A3A5C)),
                                  ),
                                  child: child!,
                                ),
                              );
                              if (picked != null) setSheet(() => borrowFromDate = picked);
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0D1B2A),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: Colors.purple.withValues(alpha: 0.5)),
                              ),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                Text(
                                  '${borrowFromDate.day}/${borrowFromDate.month}/${borrowFromDate.year}',
                                  style: const TextStyle(color: Colors.white,
                                      fontSize: 11, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(width: 4),
                                const Icon(Icons.edit_calendar, color: Color(0xFFF5A623), size: 12),
                              ]),
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Text('To: Today', style: TextStyle(color: Colors.white38, fontSize: 11)),
                        ]),
                        const SizedBox(height: 10),
                        const Text('INCLUDE', style: TextStyle(color: Colors.purple, fontSize: 9,
                            letterSpacing: 2, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 6),
                        Row(children: [
                          _miniCheckbox('Active (Out)', borrowActive, (v) => setSheet(() => borrowActive = v)),
                          const SizedBox(width: 12),
                          _miniCheckbox('Returned', borrowReturned, (v) => setSheet(() => borrowReturned = v)),
                        ]),
                      ],
                    ),
                  ),
                ],

                // ── Condition History checkbox + sub-options ──
                _exportCheckbox('Instrument Condition History', Icons.history,
                    Colors.teal, expCondHistory,
                    (v) => setSheet(() => expCondHistory = v)),
                if (expCondHistory) ...[
                  Container(
                    margin: const EdgeInsets.only(left: 12, bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.teal.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.teal.withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('FILTER BY',
                            style: TextStyle(
                                color: Colors.teal,
                                fontSize: 9,
                                letterSpacing: 2,
                                fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        Row(children: [
                          _radioOption('By Date Range', condByDate,
                              () => setSheet(() => condByDate = true)),
                          const SizedBox(width: 16),
                          _radioOption('Select Instruments', !condByDate,
                              () => setSheet(() => condByDate = false)),
                        ]),
                        const SizedBox(height: 8),
                        if (condByDate) ...[
                          Row(children: [
                            const Text('From:',
                                style: TextStyle(
                                    color: Colors.white54, fontSize: 11)),
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: () async {
                                final picked = await showDatePicker(
                                  context: ctx,
                                  initialDate: condFromDate,
                                  firstDate: DateTime(2020),
                                  lastDate: DateTime.now(),
                                  builder: (c, child) => Theme(
                                    data: ThemeData.dark().copyWith(
                                      colorScheme: const ColorScheme.dark(
                                          primary: Color(0xFFF5A623),
                                          surface: Color(0xFF1A3A5C)),
                                    ),
                                    child: child!,
                                  ),
                                );
                                if (picked != null) {
                                  setSheet(() => condFromDate = picked);
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0D1B2A),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                      color: Colors.teal.withValues(alpha: 0.5)),
                                ),
                                child: Row(mainAxisSize: MainAxisSize.min, children: [
                                  Text(
                                    '${condFromDate.day}/${condFromDate.month}/${condFromDate.year}',
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(width: 4),
                                  const Icon(Icons.edit_calendar,
                                      color: Color(0xFFF5A623), size: 12),
                                ]),
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Text('To: Today',
                                style:
                                    TextStyle(color: Colors.white38, fontSize: 11)),
                          ]),
                        ] else ...[
                          StatefulBuilder(builder: (ctx2, setInst) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                TextField(
                                  style: const TextStyle(color: Colors.white, fontSize: 12),
                                  decoration: InputDecoration(
                                    hintText: 'Search instrument code...',
                                    hintStyle: const TextStyle(color: Colors.white38, fontSize: 11),
                                    prefixIcon: const Icon(Icons.search, color: Colors.white38, size: 16),
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                                    enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(6),
                                        borderSide: BorderSide(color: Colors.teal.withValues(alpha: 0.4))),
                                    focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(6),
                                        borderSide: const BorderSide(color: Color(0xFFF5A623))),
                                    filled: true,
                                    fillColor: const Color(0xFF0D1B2A),
                                  ),
                                  onChanged: (v) => setSheet(() => condSearch = v.toLowerCase()),
                                ),
                                const SizedBox(height: 6),
                                Row(children: [
                                  TextButton(
                                    onPressed: () => setSheet(() => condSelectedCodes = List.from(condAllCodes)),
                                    style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero),
                                    child: const Text('All', style: TextStyle(color: Color(0xFFF5A623), fontSize: 11)),
                                  ),
                                  const SizedBox(width: 8),
                                  TextButton(
                                    onPressed: () => setSheet(() => condSelectedCodes = []),
                                    style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero),
                                    child: const Text('None', style: TextStyle(color: Colors.white38, fontSize: 11)),
                                  ),
                                  const Spacer(),
                                  Text('${condSelectedCodes.length} selected',
                                      style: const TextStyle(color: Colors.white38, fontSize: 10)),
                                ]),
                                Container(
                                  height: 160,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF0D1B2A),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: Colors.teal.withValues(alpha: 0.3)),
                                  ),
                                  child: condAllCodes.isEmpty
                                      ? const Center(child: CircularProgressIndicator(color: Color(0xFFF5A623), strokeWidth: 2))
                                      : ListView(
                                          padding: EdgeInsets.zero,
                                          children: condAllCodes
                                              .where((c) => condSearch.isEmpty || c.toLowerCase().contains(condSearch))
                                              .map((code) => CheckboxListTile(
                                                    dense: true,
                                                    value: condSelectedCodes.contains(code),
                                                    activeColor: const Color(0xFFF5A623),
                                                    checkColor: Colors.black,
                                                    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                                                    title: Text(code, style: const TextStyle(color: Colors.white, fontSize: 12)),
                                                    onChanged: (v) => setSheet(() {
                                                      if (v == true) condSelectedCodes.add(code);
                                                      else condSelectedCodes.remove(code);
                                                    }),
                                                  ))
                                              .toList(),
                                        ),
                                ),
                              ],
                            );
                          }),
                        ],
                      ],
                    ),
                  ),
                ],

                _exportCheckbox('Upcoming Schedule', Icons.schedule,
                    Colors.orange, expUpcoming,
                    (v) => setSheet(() => expUpcoming = v)),
                _exportCheckbox('Overdue Instruments', Icons.warning_amber,
                    Colors.red, expOverdue,
                    (v) => setSheet(() => expOverdue = v)),
                _exportCheckbox('Instruments Currently Out', Icons.outbox,
                    Colors.purple, expInstrumentsOut,
                    (v) => setSheet(() => expInstrumentsOut = v)),

                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: (expDispatch || expBorrow || expCondHistory || expUpcoming ||
                            expOverdue || expInstrumentsOut)
                        ? () {
                            Navigator.pop(ctx);
                            final types = <ExportType>[];
                            if (expDispatch) types.add(ExportType.dispatch);
                            if (expBorrow) types.add(ExportType.borrow);
                            if (expCondHistory)
                              types.add(ExportType.conditionHistory);
                            if (expUpcoming) types.add(ExportType.upcoming);
                            if (expOverdue) types.add(ExportType.overdue);
                            if (expInstrumentsOut)
                              types.add(ExportType.instrumentsOut);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => DispatchExportScreen(
                                  exportType: types.first,
                                  multiExportTypes:
                                      types.length > 1 ? types : null,
                                  dispatchFromDate:
                                      expDispatch ? dispFromDate : (expBorrow ? borrowFromDate : null),
                                  dispatchActiveOnly: expDispatch
                                      ? (dispActive && !dispReturned ? true : null)
                                      : expBorrow
                                          ? (borrowActive && !borrowReturned ? true : null)
                                          : null,
                                  dispatchReturnedOnly: expDispatch
                                      ? (!dispActive && dispReturned ? true : null)
                                      : expBorrow
                                          ? (!borrowActive && borrowReturned ? true : null)
                                          : null,
                                  condHistoryFromDate:
                                      expCondHistory ? condFromDate : null,
                                  condHistoryByDate:
                                      expCondHistory ? condByDate : null,
                                ),
                              ),
                            );
                          }
                        : null,
                    icon: const Icon(Icons.file_download, size: 18),
                    label: const Text('EXPORT',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFF5A623),
                      foregroundColor: Colors.black,
                      disabledBackgroundColor: Colors.white12,
                      disabledForegroundColor: Colors.white24,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _miniCheckbox(String label, bool value, ValueChanged<bool> onChanged) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(
          value ? Icons.check_box : Icons.check_box_outline_blank,
          color: value ? const Color(0xFFF5A623) : Colors.white38,
          size: 18,
        ),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(
                color: value ? Colors.white : Colors.white54, fontSize: 12)),
      ]),
    );
  }

  Widget _radioOption(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(
          selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
          color: selected ? const Color(0xFFF5A623) : Colors.white38,
          size: 18,
        ),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(
                color: selected ? Colors.white : Colors.white54,
                fontSize: 12)),
      ]),
    );
  }

  Widget _exportCheckbox(String label, IconData icon, Color color, bool value, ValueChanged<bool> onChanged) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: value ? color.withValues(alpha: 0.12) : const Color(0xFF0D1B2A),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: value ? color : const Color(0xFF1E3A5F)),
        ),
        child: Row(children: [
          Icon(value ? Icons.check_box : Icons.check_box_outline_blank,
              color: value ? color : Colors.white38, size: 20),
          const SizedBox(width: 10),
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label,
                style: TextStyle(
                    color: value ? Colors.white : Colors.white54,
                    fontWeight: value ? FontWeight.bold : FontWeight.normal,
                    fontSize: 13)),
          ),
        ]),
      ),
    );
  }

  

  




  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: Color(0xFFF5A623)));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Export button ─────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _showExportMenu,
                icon: const Icon(Icons.file_download, size: 18),
                label: const Text('EXPORT DATA',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF5A623),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // ── Active dispatches ─────────────────────────────────────
            const Text('ACTIVE DISPATCHES',
                style: TextStyle(
                    color: Color(0xFFF5A623),
                    fontSize: 10,
                    letterSpacing: 3,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            if (_activeDispatches.isEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A3A5C),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Center(
                  child: Text('No active dispatches',
                      style:
                          TextStyle(color: Colors.white38, fontSize: 13)),
                ),
              )
            else
              SizedBox(
                height: 130,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _activeDispatches.length,
                  itemBuilder: (_, i) {
                    final d = _activeDispatches[i];
                    final items = _activeItems[d.dispatchNo] ?? [];
                    return Container(
                      width: 220,
                      margin: const EdgeInsets.only(right: 10),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A3A5C),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: Colors.orange.withValues(alpha: 0.5),
                            width: 1.5),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            const Icon(Icons.circle,
                                color: Colors.orange, size: 7),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Text(d.dispatchNo,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13),
                                  overflow: TextOverflow.ellipsis),
                            ),
                          ]),
                          const SizedBox(height: 4),
                          Text(d.testEngineer,
                              style: const TextStyle(
                                  color: Colors.white54, fontSize: 11),
                              overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 6),
                          const Divider(
                              color: Color(0xFF1E3A5F), height: 1),
                          const SizedBox(height: 6),
                          Expanded(
                            child: items.isEmpty
                                ? const Text('No instruments',
                                    style: TextStyle(
                                        color: Colors.white38,
                                        fontSize: 10))
                                : SingleChildScrollView(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: items
                                          .map((item) => Padding(
                                                padding:
                                                    const EdgeInsets.only(
                                                        bottom: 3),
                                                child: Row(children: [
                                                  const Icon(
                                                      Icons.arrow_outward,
                                                      color: Colors.orange,
                                                      size: 10),
                                                  const SizedBox(width: 4),
                                                  Expanded(
                                                    child: Text(
                                                      item.instrumentName,
                                                      style: const TextStyle(
                                                          color: Colors
                                                              .white70,
                                                          fontSize: 10),
                                                      overflow: TextOverflow
                                                          .ellipsis,
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
                  },
                ),
              ),

            const SizedBox(height: 24),

            // ── Activity log ──────────────────────────────────────────
            const Text('ACTIVITY LOG',
                style: TextStyle(
                    color: Color(0xFFF5A623),
                    fontSize: 10,
                    letterSpacing: 3,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            if (_logs.isEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A3A5C),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Center(
                  child: Text('No activity recorded yet',
                      style:
                          TextStyle(color: Colors.white38, fontSize: 13)),
                ),
              )
            else
              _ActivityLogGrouped(logs: _logs),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════
// TAB 2 — ALL DISPATCHES
// ══════════════════════════════════════════════
class _AdminDispatchesTab extends StatefulWidget {
  const _AdminDispatchesTab();

  @override
  State<_AdminDispatchesTab> createState() => _AdminDispatchesTabState();
}

class _AdminDispatchesTabState extends State<_AdminDispatchesTab> {
  List<Dispatch> _dispatches = [];
  List<Dispatch> _filtered = [];
  bool _loading = true;
  final _searchController = TextEditingController();
  String _filterStatus = 'All'; // 'All', 'Out', 'Returned'
  DateTime _fromDate = DateTime(DateTime.now().year, DateTime.now().month, 1);
  final Set<String> _expandedMonths = {DateFormat('MMMM yyyy').format(DateTime.now())};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);

    // Pull dispatches only — avoid full sync on every tab load
    try {
      if (await SyncService.isConnected()) {
        final serverDispatches = await ApiService.getDispatches()
            .timeout(const Duration(seconds: 10));
        if (serverDispatches != null) {
          for (final d in serverDispatches) {
            try {
              await DBHelper.instance.upsertDispatchFromServer(
                  Map<String, dynamic>.from(d));
            } catch (_) {}
          }
        }
      }
    } catch (_) {}

    try {
      final dispatches = await DBHelper.instance.getAllDispatches();
      if (mounted) {
        setState(() {
          _dispatches = dispatches;
          _filtered = dispatches;
          _loading = false;
        });
        _applyFilter();
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _applyFilter() {
    final q = _searchController.text.toLowerCase();
    final now = DateTime.now();
    final toDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
    setState(() {
      _filtered = _dispatches.where((d) {
        final matchSearch = q.isEmpty ||
            d.dispatchNo.toLowerCase().contains(q) ||
            d.testEngineer.toLowerCase().contains(q) ||
            (d.processedByName?.toLowerCase().contains(q) ?? false);
        final matchStatus = _filterStatus == 'All' ||
            (_filterStatus == 'Out' && d.dateIn == null) ||
            (_filterStatus == 'Returned' && d.dateIn != null);
        bool matchDate = true;
        try {
          final dateOut = DateTime.parse(d.dateOut);
          matchDate = !dateOut.isBefore(_fromDate) && !dateOut.isAfter(toDate);
        } catch (_) {}
        return matchSearch && matchStatus && matchDate;
      }).toList()
        ..sort((a, b) {
          try { return DateTime.parse(b.dateOut).compareTo(DateTime.parse(a.dateOut)); } catch (_) { return 0; }
        });
    });
  }

  Map<String, List<Dispatch>> _groupByMonth(List<Dispatch> dispatches) {
    final Map<String, List<Dispatch>> groups = {};
    for (final d in dispatches) {
      String key;
      try {
        final date = DateTime.parse(d.dateOut);
        key = DateFormat('MMMM yyyy').format(date);
      } catch (_) {
        key = 'Unknown Date';
      }
      groups.putIfAbsent(key, () => []).add(d);
    }
    return groups;
  }

  Future<void> _pickFromDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _fromDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFFF5A623),
            surface: Color(0xFF1A3A5C),
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() => _fromDate = picked);
      _applyFilter();
    }
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return '—';
    try {
      final date = DateTime.parse(dateStr);
      return DateFormat('MMM dd, yyyy  hh:mm a').format(date);
    } catch (_) {
      return dateStr;
    }
  }

  void _showDetail(Dispatch dispatch) async {
    final items = await DBHelper.instance.getDispatchItems(dispatch.id!);
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A3A5C),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.7,
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
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              Row(children: [
                if (dispatch.isStudent) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.purple.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.purple),
                    ),
                    child: const Text('STUDENT',
                        style: TextStyle(
                            color: Colors.purple,
                            fontSize: 10,
                            fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(dispatch.dispatchNo,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 20)),
                ),
                _statusBadge(dispatch.dateIn == null ? 'Out' : 'Returned'),
              ]),
              const SizedBox(height: 16),
              _dRow(Icons.person, 'Test Engineer', dispatch.testEngineer),
              if (dispatch.isStudent) ...[
                _dRow(Icons.school, 'Student Name', dispatch.studentName ?? '—'),
                _dRow(Icons.badge_outlined, 'Student ID', dispatch.studentId ?? '—'),
              ],
              if (dispatch.processedByName != null &&
                  dispatch.processedByName!.isNotEmpty)
                _dRow(Icons.badge, 'Processed By', dispatch.processedByName!),
              _dRow(Icons.logout, 'Date Out', _formatDate(dispatch.dateOut)),
              _dRow(Icons.login, 'Date In', _formatDate(dispatch.dateIn)),
              if (dispatch.remarks != null && dispatch.remarks!.isNotEmpty)
                _dRow(Icons.notes, 'Remarks', dispatch.remarks!),
              const SizedBox(height: 20),
              const Text('INSTRUMENTS',
                  style: TextStyle(
                      color: Color(0xFFF5A623),
                      fontSize: 11,
                      letterSpacing: 3,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              if (items.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'Instrument data syncing — pull down to refresh.',
                    style: TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                )
              else
                ...items.map((item) => Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0D1B2A),
                      borderRadius: BorderRadius.circular(8),
                      border:
                          Border.all(color: const Color(0xFF1E3A5F)),
                    ),
                    child: Row(children: [
                      const Icon(Icons.build,
                          color: Color(0xFFF5A623), size: 16),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item.instrumentName,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13)),
                            Text(
                                '${item.instrumentCode} · ${item.currentCondition}',
                                style: const TextStyle(
                                    color: Colors.white54,
                                    fontSize: 11)),
                            if (item.returnCondition != null)
                              Text('Returned: ${item.returnCondition}',
                                  style: TextStyle(
                                      color: item.returnCondition ==
                                              'Functioning'
                                          ? Colors.green
                                          : item.returnCondition ==
                                                  'For Repair'
                                              ? Colors.orange
                                              : Colors.red,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ]),
                  )),
              // Photos
              if (dispatch.returnPhotoPaths.isNotEmpty) ...[
                const SizedBox(height: 20),
                const Text('RETURN PHOTOS',
                    style: TextStyle(
                        color: Color(0xFFF5A623),
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
                              color: const Color(0xFFF5A623)
                                  .withValues(alpha: 0.4)),
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

  Widget _statusBadge(String status) {
    final isOut = status == 'Out';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isOut
            ? Colors.orange.withValues(alpha: 0.15)
            : Colors.green.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: isOut ? Colors.orange : Colors.green),
      ),
      child: Text(status,
          style: TextStyle(
              color: isOut ? Colors.orange : Colors.green,
              fontSize: 11,
              fontWeight: FontWeight.bold)),
    );
  }

  Widget _dRow(IconData icon, String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: const Color(0xFFF5A623), size: 15),
            const SizedBox(width: 8),
            SizedBox(
              width: 100,
              child: Text('$label:',
                  style: const TextStyle(
                      color: Colors.white54, fontSize: 13)),
            ),
            Expanded(
              child: Text(value,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 13)),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final groups = _groupByMonth(_filtered);
    final groupKeys = groups.keys.toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
          child: TextField(
            controller: _searchController,
            onChanged: (_) => _applyFilter(),
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Search by dispatch no, engineer, processed by...',
              hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
              prefixIcon:
                  const Icon(Icons.search, color: Color(0xFFF5A623)),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFF1E3A5F)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFFF5A623)),
              ),
              filled: true,
              fillColor: const Color(0xFF1A3A5C),
            ),
          ),
        ),
        // ── From-date picker ──
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            children: [
              const Icon(Icons.date_range, color: Color(0xFFF5A623), size: 14),
              const SizedBox(width: 6),
              const Text('From:', style: TextStyle(color: Colors.white54, fontSize: 11)),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: _pickFromDate,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D1B2A),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFF1E3A5F)),
                  ),
                  child: Row(children: [
                    Text(DateFormat('MMM dd, yyyy').format(_fromDate),
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 4),
                    const Icon(Icons.edit_calendar, color: Color(0xFFF5A623), size: 12),
                  ]),
                ),
              ),
              const SizedBox(width: 10),
              const Text('To:', style: TextStyle(color: Colors.white54, fontSize: 11)),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D1B2A),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFF1E3A5F)),
                ),
                child: Text(DateFormat('MMM dd, yyyy').format(DateTime.now()),
                    style: const TextStyle(color: Colors.white54, fontSize: 11)),
              ),
            ],
          ),
        ),
        // Filter chips
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            children: ['All', 'Out', 'Returned'].map((f) {
              final selected = _filterStatus == f;
              return GestureDetector(
                onTap: () {
                  setState(() => _filterStatus = f);
                  _applyFilter();
                },
                child: Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: selected
                        ? const Color(0xFFF5A623)
                        : const Color(0xFF1A3A5C),
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(
                        color: selected
                            ? const Color(0xFFF5A623)
                            : const Color(0xFF1E3A5F)),
                  ),
                  child: Text(f,
                      style: TextStyle(
                          color: selected ? Colors.black : Colors.white54,
                          fontSize: 11,
                          fontWeight: selected
                              ? FontWeight.bold
                              : FontWeight.normal)),
                ),
              );
            }).toList(),
          ),
        ),
        Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('${_filtered.length} records · ${groupKeys.length} month${groupKeys.length != 1 ? 's' : ''}',
                style: const TextStyle(
                    color: Colors.white38, fontSize: 11)),
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(
                      color: Color(0xFFF5A623)))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _filtered.isEmpty
                      ? const Center(
                          child: Text('No dispatches found',
                              style: TextStyle(color: Colors.grey)))
                      : ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: groupKeys.length,
                          itemBuilder: (_, gi) {
                            final monthKey = groupKeys[gi];
                            final monthDispatches = groups[monthKey]!;
                            final isExpanded = _expandedMonths.contains(monthKey);
                            final outCount = monthDispatches.where((d) => d.dateIn == null).length;
                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1A3A5C),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: const Color(0xFF1E3A5F)),
                              ),
                              child: Column(
                                children: [
                                  InkWell(
                                    borderRadius: BorderRadius.circular(10),
                                    onTap: () {
                                      setState(() {
                                        if (isExpanded) { _expandedMonths.remove(monthKey); }
                                        else { _expandedMonths.add(monthKey); }
                                      });
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                      child: Row(
                                        children: [
                                          const Icon(Icons.folder_outlined, color: Color(0xFFF5A623), size: 18),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Text(monthKey,
                                                style: const TextStyle(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 14)),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFF5A623).withValues(alpha: 0.12),
                                              borderRadius: BorderRadius.circular(99),
                                            ),
                                            child: Text('${monthDispatches.length}',
                                                style: const TextStyle(color: Color(0xFFF5A623), fontSize: 11, fontWeight: FontWeight.bold)),
                                          ),
                                          if (outCount > 0) ...[
                                            const SizedBox(width: 6),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: Colors.orange.withValues(alpha: 0.12),
                                                borderRadius: BorderRadius.circular(99),
                                              ),
                                              child: Text('$outCount out',
                                                  style: const TextStyle(color: Colors.orange, fontSize: 11, fontWeight: FontWeight.bold)),
                                            ),
                                          ],
                                          const SizedBox(width: 8),
                                          Icon(isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                                              color: const Color(0xFFF5A623)),
                                        ],
                                      ),
                                    ),
                                  ),
                                  if (isExpanded) ...[
                                    const Divider(color: Color(0xFF1E3A5F), height: 1),
                                    ...monthDispatches.map((d) {
                                      final isOut = d.dateIn == null;
                                      return GestureDetector(
                                        onTap: () => _showDetail(d),
                                        child: Container(
                                          padding: const EdgeInsets.all(14),
                                          decoration: const BoxDecoration(
                                            border: Border(bottom: BorderSide(color: Color(0xFF1E3A5F), width: 0.5)),
                                          ),
                                          child: Row(children: [
                                            Container(
                                              width: 44,
                                              height: 44,
                                              decoration: BoxDecoration(
                                                color: isOut
                                                    ? Colors.orange.withValues(alpha: 0.12)
                                                    : Colors.green.withValues(alpha: 0.12),
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                              child: Icon(
                                                isOut ? Icons.outbox : Icons.assignment_turned_in,
                                                color: isOut ? Colors.orange : Colors.green,
                                                size: 22,
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Row(children: [
                                                    Expanded(
                                                      child: Text(d.dispatchNo,
                                                          style: const TextStyle(
                                                              color: Colors.white,
                                                              fontWeight: FontWeight.bold,
                                                              fontSize: 14)),
                                                    ),
                                                    if (d.isStudent)
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                        decoration: BoxDecoration(
                                                          color: Colors.purple.withValues(alpha: 0.15),
                                                          borderRadius: BorderRadius.circular(4),
                                                          border: Border.all(color: Colors.purple.withValues(alpha: 0.5)),
                                                        ),
                                                        child: const Text('STUDENT',
                                                            style: TextStyle(color: Colors.purple, fontSize: 9, fontWeight: FontWeight.bold)),
                                                      ),
                                                  ]),
                                                  Text(
                                                    d.isStudent ? (d.studentName ?? d.testEngineer) : d.testEngineer,
                                                    style: const TextStyle(color: Colors.white54, fontSize: 11),
                                                  ),
                                                  if (d.processedByName != null)
                                                    Text('By: ${d.processedByName}',
                                                        style: const TextStyle(color: Colors.white38, fontSize: 10)),
                                                ],
                                              ),
                                            ),
                                            _statusBadge(isOut ? 'Out' : 'Returned'),
                                          ]),
                                        ),
                                      );
                                    }),
                                  ],
                                ],
                              ),
                            );
                          },
                        ),
                ),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════
// TAB 3 — USERS
// ══════════════════════════════════════════════
class _AdminUsersTab extends StatefulWidget {
  const _AdminUsersTab();

  @override
  State<_AdminUsersTab> createState() => _AdminUsersTabState();
}

class _AdminUsersTabState extends State<_AdminUsersTab> {
  List<Map<String, dynamic>> _users = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final users = await ApiService.getUsers();
      setState(() {
        _users = users ?? [];
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showCreateUserDialog() {
    final nameCtrl = TextEditingController();
    final usernameCtrl = TextEditingController();
    final passwordCtrl = TextEditingController();
    String role = 'staff';
    bool creating = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1A3A5C),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: const Text('Create User Account',
              style: TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _dialogField(nameCtrl, 'Full Name', Icons.person),
              const SizedBox(height: 10),
              _dialogField(usernameCtrl, 'Username', Icons.alternate_email),
              const SizedBox(height: 10),
              _dialogField(passwordCtrl, 'Password', Icons.lock,
                  obscure: true),
              const SizedBox(height: 14),
              // Role selector
              Row(children: [
                const Text('Role:',
                    style:
                        TextStyle(color: Colors.white54, fontSize: 13)),
                const SizedBox(width: 12),
                ...[('staff', 'Staff')]
                    .map((entry) {
                  final (val, label) = entry;
                  final selected = role == val;
                  return GestureDetector(
                    onTap: () => setDialogState(() => role = val),
                    child: Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: selected
                            ? const Color(0xFFF5A623).withValues(alpha: 0.2)
                            : const Color(0xFF0D1B2A),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: selected
                                ? const Color(0xFFF5A623)
                                : const Color(0xFF1E3A5F)),
                      ),
                      child: Text(label,
                          style: TextStyle(
                              color: selected
                                  ? const Color(0xFFF5A623)
                                  : Colors.white54,
                              fontWeight: selected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              fontSize: 13)),
                    ),
                  );
                }),
              ]),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel',
                  style: TextStyle(color: Colors.white38)),
            ),
            ElevatedButton(
              onPressed: creating
                  ? null
                  : () async {
                      if (nameCtrl.text.trim().isEmpty ||
                          usernameCtrl.text.trim().isEmpty ||
                          passwordCtrl.text.trim().isEmpty) {
                        return;
                      }
                      setDialogState(() => creating = true);
                      final success = await ApiService.createUser(
                        name: nameCtrl.text.trim(),
                        username: usernameCtrl.text.trim(),
                        password: passwordCtrl.text.trim(),
                        role: role,
                      );
                      if (!ctx.mounted) return;
                      Navigator.pop(ctx);
                      if (success) {
                        _load();
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(
                              content: Text('User created successfully'),
                              backgroundColor: Colors.green),
                        );
                      } else {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(
                              content: Text(
                                  'Failed — username may already exist'),
                              backgroundColor: Colors.red),
                        );
                      }
                    },
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF5A623),
                  foregroundColor: Colors.black),
              child: creating
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.black))
                  : const Text('CREATE',
                      style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(Map<String, dynamic> user) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A3A5C),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Delete User',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text(
            'Are you sure you want to delete "${user['name']}" (@${user['username']})?\n\nThis cannot be undone.',
            style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel',
                style: TextStyle(color: Colors.white38)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              final success =
                  await ApiService.deleteUser(user['id'] as int);
              if (success) {
                _load();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('User deleted'),
                        backgroundColor: Colors.green),
                  );
                }
              } else {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Failed to delete user'),
                        backgroundColor: Colors.red),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white),
            child: const Text('DELETE',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showSendMessageDialog(Map<String, dynamic> user) {
    final msgCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          bool sending = false;
          return AlertDialog(
            backgroundColor: const Color(0xFF1A3A5C),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            title: Row(children: [
              const Icon(Icons.message, color: Color(0xFFF5A623), size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Message ${user['name']}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15)),
              ),
            ]),
            content: TextField(
              controller: msgCtrl,
              style: const TextStyle(color: Colors.white),
              maxLines: 4,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Type your message...',
                hintStyle: const TextStyle(color: Colors.white38),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFF1E3A5F))),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFFF5A623))),
                filled: true,
                fillColor: const Color(0xFF0D1B2A),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel',
                    style: TextStyle(color: Colors.white38)),
              ),
              StatefulBuilder(
                builder: (ctx2, setBtn) => ElevatedButton(
                  onPressed: sending
                      ? null
                      : () async {
                          if (msgCtrl.text.trim().isEmpty) return;
                          setBtn(() => sending = true);
                          final ok = await ApiService.sendMessage(
                            toUserId: user['id'] as int,
                            toUserName: user['name'] as String,
                            message: msgCtrl.text.trim(),
                          );
                          if (!ctx.mounted) return;
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                            content: Text(ok
                                ? 'Message sent to ${user['name']}'
                                : 'Failed to send message'),
                            backgroundColor:
                                ok ? Colors.green : Colors.red,
                          ));
                        },
                        style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFF5A623),
                            foregroundColor: Colors.black),
                          child: sending
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.black))
                      : const Text('SEND',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showUserHistory(Map<String, dynamic> user) {
    final name = user['name'] as String;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A3A5C),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.92,
        expand: false,
        builder: (_, sc) => FutureBuilder<List<List<dynamic>?>>(
          future: Future.wait([
            ApiService.getUserHistory(name),
            ApiService.getMessageStatus(),
          ]),
          builder: (ctx, snap) {
            final history = snap.data?[0];
            final allMessages = snap.data?[1];
            // Filter messages sent to this specific user
            final userMessages = allMessages
                ?.where((m) => m['to_user_name'] == name)
                .toList() ?? [];
            return Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: Text('HISTORY — $name',
                          style: const TextStyle(
                              color: Color(0xFFF5A623),
                              fontSize: 10,
                              letterSpacing: 3,
                              fontWeight: FontWeight.bold)),
                    ),
                    Row(children: [
                    if (user['role'] != 'admin')
                      TextButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          _showSendMessageDialog(user);
                        },
                        icon: const Icon(Icons.message,
                            size: 14, color: Color(0xFFF5A623)),
                        label: const Text('Send Message',
                            style: TextStyle(
                                color: Color(0xFFF5A623), fontSize: 11)),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    TextButton.icon(
                      onPressed: () => _showUserProfileInfo(user),
                      icon: const Icon(Icons.person_outline,
                          size: 14, color: Colors.white54),
                      label: const Text('View Profile',
                          style: TextStyle(color: Colors.white54, fontSize: 11)),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                    ]),
                  ],
                ),
                const SizedBox(height: 12),
                // ── Message status section ──────────────────────────────
                if (userMessages.isNotEmpty) ...[
                  const Text('SENT MESSAGES',
                      style: TextStyle(
                          color: Color(0xFFF5A623),
                          fontSize: 10,
                          letterSpacing: 2,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  _AdminMessageHistoryList(
                      messages: userMessages, controller: sc),
                  const Divider(color: Colors.white12),
                  const SizedBox(height: 4),
                ],
                if (snap.connectionState == ConnectionState.waiting)
                  const Center(
                      child: CircularProgressIndicator(
                          color: Color(0xFFF5A623)))
                else if (history == null || history.isEmpty)
                  const Text('No history found',
                      style: TextStyle(color: Colors.white38))
                else
                  Expanded(
                    child: _UserHistoryGrouped(
                        history: history, controller: sc),
                  ),
              ],
            ),
          );},
        ),
      ),
    );
  }

  Widget _dialogField(
          TextEditingController c, String label, IconData icon,
          {bool obscure = false}) =>
      TextField(
        controller: c,
        obscureText: obscure,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white38),
          prefixIcon: Icon(icon, color: const Color(0xFFF5A623)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFF1E3A5F)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFF5A623)),
          ),
          filled: true,
          fillColor: const Color(0xFF0D1B2A),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _showCreateUserDialog,
              icon: const Icon(Icons.person_add, size: 18),
              label: const Text('Create New User Account',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF5A623),
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(
                      color: Color(0xFFF5A623)))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _users.isEmpty
                      ? const Center(
                          child: Text('No users found',
                              style: TextStyle(color: Colors.grey)))
                      : ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: _users.length,
                          itemBuilder: (_, i) {
                            final u = _users[i];
                            final isAdmin = u['role'] == 'admin';
                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1A3A5C),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                    color: isAdmin
                                        ? const Color(0xFFF5A623)
                                            .withValues(alpha: 0.3)
                                        : const Color(0xFF1E3A5F)),
                              ),
                              child: Row(children: [
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: isAdmin
                                        ? const Color(0xFFF5A623)
                                            .withValues(alpha: 0.15)
                                        : Colors.blue.withValues(alpha: 0.15),
                                    borderRadius:
                                        BorderRadius.circular(8),
                                  ),
                                  child: Icon(
                                    isAdmin
                                        ? Icons.admin_panel_settings
                                        : Icons.person,
                                    color: isAdmin
                                        ? const Color(0xFFF5A623)
                                        : Colors.blue,
                                    size: 22,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(u['name'],
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14)),
                                      Text('@${u['username']}',
                                          style: const TextStyle(
                                              color: Colors.white38,
                                              fontSize: 11)),
                                      Text(
                                          isAdmin ? 'Administrator' : 'Staff',
                                          style: TextStyle(
                                              color: isAdmin
                                                  ? const Color(0xFFF5A623)
                                                  : Colors.blue,
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold)),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.history,
                                      color: Colors.white38, size: 22),
                                  onPressed: () => _showUserHistory(u),
                                ),
                                if (!isAdmin)
                                  IconButton(
                                    icon: Icon(Icons.delete_outline,
                                        color: Colors.red.withValues(alpha: 0.54),
                                        size: 22),
                                    onPressed: () => _confirmDelete(u),
                                  ),
                              ]),
                            );
                          },
                        ),
                ),
        ),
      ],
    );
  }

  void _showUserProfileInfo(Map<String, dynamic> user) {
    bool showPwd = false;
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF111827),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSt) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: Container(width: 40, height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(color: Colors.white24,
                      borderRadius: BorderRadius.circular(99)))),
              const Text('USER PROFILE', style: TextStyle(
                  color: Color(0xFFF5A623), fontSize: 10,
                  letterSpacing: 3, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              Center(child: Container(
                width: 56, height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFF5A623).withValues(alpha: 0.15),
                  border: Border.all(color: const Color(0xFFF5A623), width: 2),
                ),
                child: Center(child: Text(
                  (user['name'] as String? ?? 'U')[0].toUpperCase(),
                  style: const TextStyle(color: Color(0xFFF5A623),
                      fontSize: 22, fontWeight: FontWeight.bold),
                )),
              )),
              const SizedBox(height: 16),
              _userProfileRow('Full Name', user['name'] ?? '—', Icons.person),
              _userProfileRow('Username', '@${user['username'] ?? ''}', Icons.alternate_email),
              _userProfileRow('Role', (user['role'] ?? 'staff').toString().toUpperCase(), Icons.badge),
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A3A5C),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF1E3A5F)),
                ),
                child: Row(children: [
                  const Icon(Icons.lock, color: Color(0xFFF5A623), size: 16),
                  const SizedBox(width: 12),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Password Hash',
                          style: TextStyle(color: Colors.white38, fontSize: 10)),
                      Text(
                        showPwd ? (user['password_hash'] ?? '—') : '••••••••••••',
                        style: const TextStyle(color: Colors.white, fontSize: 12,
                            fontWeight: FontWeight.w500),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 2,
                      ),
                    ],
                  )),
                  GestureDetector(
                    onTap: () => setSt(() => showPwd = !showPwd),
                    child: Icon(showPwd ? Icons.visibility_off : Icons.visibility,
                        color: Colors.white38, size: 18),
                  ),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _userProfileRow(String label, String value, IconData icon) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A3A5C),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF1E3A5F)),
      ),
      child: Row(children: [
        Icon(icon, color: const Color(0xFFF5A623), size: 16),
        const SizedBox(width: 12),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: Colors.white38, fontSize: 10)),
            Text(value, style: const TextStyle(color: Colors.white, fontSize: 13,
                fontWeight: FontWeight.w500)),
          ],
        )),
      ]),
    );
  }
}
// ══════════════════════════════════════════════
// TAB 4 — INSTRUMENTS
// ══════════════════════════════════════════════
class _AdminInstrumentsTab extends StatefulWidget {
  const _AdminInstrumentsTab();

  @override
  State<_AdminInstrumentsTab> createState() => _AdminInstrumentsTabState();
}

class _AdminInstrumentsTabState extends State<_AdminInstrumentsTab> {
  List<Instrument> _instruments = [];
  List<Instrument> _filtered = [];
  bool _loading = true;
  final _searchController = TextEditingController();
  int _borrowCount = 0;
  int _dispatchCount = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    final list = await DBHelper.instance.getAllInstruments();
    final allDispatches = await DBHelper.instance.getAllDispatches();
    final activeDispatches = allDispatches.where((d) => d.dateIn == null).toList();
    int borrowCount = 0;
    int dispatchCount = 0;
    for (final d in activeDispatches) {
      if (d.id != null) {
        final items = await DBHelper.instance.getDispatchItems(d.id!);
        if (d.isStudent) {
          borrowCount += items.length;
        } else {
          dispatchCount += items.length;
        }
      }
    }
    if (mounted) {
      setState(() {
        _instruments = list;
        _filtered = list;
        _borrowCount = borrowCount;
        _dispatchCount = dispatchCount;
        _loading = false;
      });
    }
  }

  void _search(String q) {
    setState(() {
      _filtered = _instruments
          .where((i) =>
              i.instrumentName.toLowerCase().contains(q.toLowerCase()) ||
              i.instrumentCode.toLowerCase().contains(q.toLowerCase()))
          .toList();
    });
  }

  void _showAddDialog() {
    final codeCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final typeCtrl = TextEditingController();
    final brandCtrl = TextEditingController();
    final modelCtrl = TextEditingController();
    bool adding = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          backgroundColor: const Color(0xFF1A3A5C),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: const Text('Add New Instrument',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _dField(codeCtrl, 'Barcode / Instrument Code', Icons.qr_code),
              const SizedBox(height: 10),
              _dField(nameCtrl, 'Instrument Name', Icons.build),
              const SizedBox(height: 10),
              _dField(typeCtrl, 'Type', Icons.category),
              const SizedBox(height: 10),
              _dField(brandCtrl, 'Brand', Icons.business),
              const SizedBox(height: 10),
              _dField(modelCtrl, 'Model', Icons.straighten),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: Colors.white38)),
            ),
            ElevatedButton(
              onPressed: adding
                  ? null
                  : () async {
                      if (codeCtrl.text.trim().isEmpty || nameCtrl.text.trim().isEmpty) return;
                      setS(() => adding = true);
                      final nameFull = [
                        if (brandCtrl.text.trim().isNotEmpty) brandCtrl.text.trim(),
                        nameCtrl.text.trim(),
                        if (modelCtrl.text.trim().isNotEmpty) modelCtrl.text.trim(),
                      ].join(' ');
                      final data = {
                        'instrument_code': codeCtrl.text.trim(),
                        'instrument_name': nameFull,
                        if (typeCtrl.text.trim().isNotEmpty)
                          'notes': 'Type: ${typeCtrl.text.trim()}',
                        'current_condition': 'Functioning',
                        'location': 'AMTEC UPLB',
                      };
                      final ok = await ApiService.createInstrument(data);
                      if (!ctx.mounted) return;
                      Navigator.pop(ctx);
                      if (ok) {
                        await DBHelper.instance.insertInstrument(Instrument(
                          instrumentCode: codeCtrl.text.trim(),
                          instrumentName: nameFull,
                        ));
                        final prefs2 = await SharedPreferences.getInstance();
                        final adminName = prefs2.getString('user_name') ?? 'Admin';
                        await DBHelper.instance.logActivity(
                          eventType: 'instrument_added',
                          eventDetail: 'Added instrument: $nameFull (${codeCtrl.text.trim()})',
                          actor: adminName,
                        );
                        _load();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                              content: Text('Instrument added'),
                              backgroundColor: Colors.green));
                        }
                      } else {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                              content: Text('Failed — code may already exist'),
                              backgroundColor: Colors.red));
                        }
                      }
                    },
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF5A623),
                  foregroundColor: Colors.black),
              child: adding
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                  : const Text('ADD', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _countCard(String label, int value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF1A3A5C),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          Text('$value',
              style: TextStyle(
                  color: color,
                  fontSize: 20,
                  fontWeight: FontWeight.bold)),
          Text(label,
              style:
                  const TextStyle(color: Colors.white54, fontSize: 10)),
        ]),
      ),
    );
  }

  Widget _dField(TextEditingController c, String label, IconData icon) => TextField(
        controller: c,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white38),
          prefixIcon: Icon(icon, color: const Color(0xFFF5A623)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFF1E3A5F))),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFF5A623))),
          filled: true,
          fillColor: const Color(0xFF0D1B2A),
        ),
      );

  Color _conditionColor(String c) {
    switch (c) {
      case 'Functioning': return Colors.green;
      case 'For Repair': return Colors.orange;
      case 'Condemning': return Colors.red;
      default: return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final available = _instruments.where((i) => i.status == 'Available').length;
    final forRepair = _instruments
        .where((i) => i.currentCondition == 'For Repair').length;
    final forCondemn = _instruments
        .where((i) => i.currentCondition == 'Condemning').length;

    return Column(
      children: [
        // Count cards
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Column(
            children: [
              Row(children: [
                _countCard('Available', available, Colors.green),
                const SizedBox(width: 8),
                _countCard('Out (Dispatch)', _dispatchCount, Colors.orange),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                _countCard('Out (Borrow)', _borrowCount, Colors.blue),
                const SizedBox(width: 8),
                _countCard('For Repair', forRepair, Colors.amber),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                _countCard('For Condemn', forCondemn, Colors.red),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        vertical: 10, horizontal: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A3A5C),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: const Color(0xFFF5A623).withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${_instruments.length}',
                            style: const TextStyle(
                                color: Color(0xFFF5A623),
                                fontSize: 20,
                                fontWeight: FontWeight.bold)),
                        const Text('Total',
                            style: TextStyle(
                                color: Colors.white54, fontSize: 10)),
                      ],
                    ),
                  ),
                ),
              ]),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _searchController,
                onChanged: _search,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Search instruments...',
                  hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                  prefixIcon: const Icon(Icons.search, color: Color(0xFFF5A623)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFF1E3A5F))),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFFF5A623))),
                  filled: true,
                  fillColor: const Color(0xFF1A3A5C),
                ),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: _showAddDialog,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add', style: TextStyle(fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF5A623),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('${_filtered.length} instruments',
                style: const TextStyle(color: Colors.white38, fontSize: 11)),
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: Color(0xFFF5A623)))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _filtered.isEmpty
                      ? const Center(
                          child: Text('No instruments', style: TextStyle(color: Colors.grey)))
                      : ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: _filtered.length,
                          itemBuilder: (_, i) {
                            final inst = _filtered[i];
                            final condColor = _conditionColor(inst.currentCondition);
                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1A3A5C),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: const Color(0xFF1E3A5F)),
                              ),
                              child: Row(children: [
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: condColor.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(Icons.build, color: condColor, size: 22),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(inst.instrumentName,
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13)),
                                      Text(inst.instrumentCode,
                                          style: const TextStyle(
                                              color: Colors.white54, fontSize: 11)),
                                      if (inst.serialNumber != null)
                                        Text('S/N: ${inst.serialNumber}',
                                            style: const TextStyle(
                                                color: Colors.white38, fontSize: 10)),
                                    ],
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: condColor.withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(99),
                                        border: Border.all(color: condColor),
                                      ),
                                      child: Text(inst.currentCondition,
                                          style: TextStyle(
                                              color: condColor,
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold)),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(inst.status,
                                        style: const TextStyle(
                                            color: Colors.white38, fontSize: 10)),
                                  ],
                                ),
                                const SizedBox(width: 4),
                                GestureDetector(
                                  onTap: () {
                                    showModalBottomSheet(
                                      context: context,
                                      isScrollControlled: true,
                                      backgroundColor: const Color(0xFF1A3A5C),
                                      shape: const RoundedRectangleBorder(
                                          borderRadius: BorderRadius.vertical(
                                              top: Radius.circular(16))),
                                      builder: (_) => DraggableScrollableSheet(
                                        expand: false,
                                        initialChildSize: 0.6,
                                        maxChildSize: 0.92,
                                        builder: (_, sc) => FutureBuilder<List<dynamic>?>(
                                          future: ApiService.getUserHistory(
                                              inst.instrumentCode),
                                          builder: (ctx, snap) => Padding(
                                            padding: const EdgeInsets.all(20),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Center(
                                                  child: Container(
                                                    width: 40, height: 4,
                                                    margin: const EdgeInsets.only(
                                                        bottom: 16),
                                                    decoration: BoxDecoration(
                                                        color: Colors.white24,
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                                99)),
                                                  ),
                                                ),
                                                Text(
                                                  'HISTORY — ${inst.instrumentCode}',
                                                  style: const TextStyle(
                                                      color: Color(0xFFF5A623),
                                                      fontSize: 10,
                                                      letterSpacing: 3,
                                                      fontWeight:
                                                          FontWeight.bold),
                                                ),
                                                Text(inst.instrumentName,
                                                    style: const TextStyle(
                                                        color: Colors.white54,
                                                        fontSize: 12)),
                                                const SizedBox(height: 12),
                                                if (snap.connectionState ==
                                                    ConnectionState.waiting)
                                                  const Center(
                                                      child:
                                                          CircularProgressIndicator(
                                                              color: Color(
                                                                  0xFFF5A623)))
                                                else if (!snap.hasData ||
                                                    snap.data!.isEmpty)
                                                  const Text('No history found',
                                                      style: TextStyle(
                                                          color: Colors.white38))
                                                else
                                                  Expanded(
                                                    child: ListView.builder(
                                                      controller: sc,
                                                      itemCount:
                                                          snap.data!.length,
                                                      itemBuilder: (_, i) {
                                                        final e = snap.data![i];
                                                        String ts = '';
                                                        try {
                                                          final d =
                                                              DateTime.parse(
                                                                  e['timestamp'] ??
                                                                      '');
                                                          ts =
                                                              '${d.day}/${d.month}/${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
                                                        } catch (_) {}
                                                        return Container(
                                                          margin:
                                                              const EdgeInsets
                                                                  .only(
                                                                  bottom: 6),
                                                          padding:
                                                              const EdgeInsets
                                                                  .all(10),
                                                          decoration: BoxDecoration(
                                                            color: const Color(
                                                                0xFF0D1B2A),
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(8),
                                                            border: Border.all(
                                                                color: const Color(
                                                                    0xFF1E3A5F)),
                                                          ),
                                                          child: Row(children: [
                                                            const Icon(
                                                                Icons.circle,
                                                                color: Color(
                                                                    0xFFF5A623),
                                                                size: 6),
                                                            const SizedBox(
                                                                width: 10),
                                                            Expanded(
                                                              child: Column(
                                                                crossAxisAlignment:
                                                                    CrossAxisAlignment
                                                                        .start,
                                                                children: [
                                                                  Text(
                                                                    e['event_detail'] ??
                                                                        e['event_type'] ??
                                                                        '',
                                                                    style: const TextStyle(
                                                                        color: Colors
                                                                            .white,
                                                                        fontSize:
                                                                            12),
                                                                  ),
                                                                  Text(
                                                                      e['actor'] ??
                                                                          '',
                                                                      style: const TextStyle(
                                                                          color: Colors
                                                                              .white38,
                                                                          fontSize:
                                                                              10)),
                                                                ],
                                                              ),
                                                            ),
                                                            Text(ts,
                                                                style: const TextStyle(
                                                                    color: Colors
                                                                        .white38,
                                                                    fontSize:
                                                                        10)),
                                                          ]),
                                                        );
                                                      },
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                  child: const Padding(
                                    padding: EdgeInsets.all(8),
                                    child: Icon(Icons.history,
                                        color: Colors.white38, size: 20),
                                  ),
                                ),
                              ]),
                            );
                          },
                        ),
                ),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════
// TAB 5 — CONDEMN APPROVAL
// ══════════════════════════════════════════════
class _AdminCondemnTab extends StatefulWidget {
  const _AdminCondemnTab();

  @override
  State<_AdminCondemnTab> createState() => _AdminCondemnTabState();
}

class _AdminCondemnTabState extends State<_AdminCondemnTab> {
  List<Instrument> _condemning = [];
  List<Map<String, dynamic>> _revertRequests = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      if (await SyncService.isConnected()) {
        // Lightweight pull — only fetch instrument conditions, no full sync
        try {
          final serverInstruments = await ApiService.getInstruments()
              .timeout(const Duration(seconds: 8));
          if (serverInstruments != null) {
            final db = await DBHelper.instance.database;
            for (final i in serverInstruments) {
              try {
                final code = i['instrument_code'] as String? ?? '';
                if (code.isEmpty) continue;
                final serverCondition =
                    i['current_condition'] as String? ?? 'Functioning';
                final localRows = await db.query('instruments',
                    where: 'instrument_code = ?', whereArgs: [code]);
                final localCondition = localRows.isNotEmpty
                    ? localRows.first['current_condition'] as String?
                    : null;
                if (serverCondition == 'Condemning' ||
                    localCondition != 'Condemning') {
                  await db.update(
                    'instruments',
                    {'current_condition': serverCondition,
                     'condition_edited_locally': 0},
                    where: 'instrument_code = ?',
                    whereArgs: [code],
                  );
                }
              } catch (_) {}
            }
          }
        } catch (_) {}
      }
    } catch (_) {}
    try {
      final all = await DBHelper.instance.getAllInstruments();
      final list = all
          .where((i) => i.currentCondition == 'Condemning')
          .toList()
        ..sort((a, b) {
          final aDate = a.scheduledCondemnDate;
          final bDate = b.scheduledCondemnDate;
          if (aDate != null && bDate == null) return -1;
          if (aDate == null && bDate != null) return 1;
          if (aDate != null && bDate != null) return aDate.compareTo(bDate);
          return 0;
        });
      final reverts = await DBHelper.instance.getPendingRevertRequests();
      if (mounted) setState(() { _condemning = list; _revertRequests = reverts; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _approve(Instrument inst) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: const Color(0xFF1A3A5C),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Approve Condemn',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text(
            'Permanently delete "${inst.instrumentName}" (${inst.instrumentCode})?\n\nThis removes it from local storage and the server.',
            style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancel', style: TextStyle(color: Colors.white38)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(dialogCtx);
              // Always delete locally first so UI updates immediately
              await DBHelper.instance.approveCondemnRequest(inst.instrumentCode);
              // Then try server delete with one retry
              bool deleted = false;
              try {
                deleted = await ApiService.deleteInstrument(inst.instrumentCode);
                if (!deleted) {
                  await Future.delayed(const Duration(milliseconds: 500));
                  deleted = await ApiService.deleteInstrument(inst.instrumentCode);
                }
              } catch (_) {}
              final prefs2 = await SharedPreferences.getInstance();
              final adminName = prefs2.getString('user_name') ?? 'Admin';
              await DBHelper.instance.logActivity(
                eventType: 'condemn_approved',
                eventDetail: 'Approved condemnation/deletion of ${inst.instrumentCode} (${inst.instrumentName})',
                actor: adminName,
              );
              if (!mounted) return;
              _load();
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(deleted
                      ? 'Instrument condemned and deleted'
                      : 'Deleted locally — will sync when server is available'),
                  backgroundColor: Colors.red));
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('APPROVE & DELETE',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _deny(Instrument inst) {
    final reasonCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A3A5C),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Deny Condemnation',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                'Deny condemnation of "${inst.instrumentName}"?\n\nCondition will be reset to For Repair.',
                style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 14),
            const Text('Reason for denial:',
                style: TextStyle(color: Colors.white54, fontSize: 12)),
            const SizedBox(height: 8),
            TextField(
              controller: reasonCtrl,
              style: const TextStyle(color: Colors.white),
              maxLines: 2,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Enter reason...',
                hintStyle: const TextStyle(color: Colors.white38),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFF1E3A5F))),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFFF5A623))),
                filled: true,
                fillColor: const Color(0xFF0D1B2A),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.white38)),
          ),
          ElevatedButton(
            onPressed: () async {
              if (reasonCtrl.text.trim().isEmpty) return;
              Navigator.pop(context);
              await DBHelper.instance.denyCondemnRequest(inst.instrumentCode);
              try {
                await ApiService.patchInstrument(inst.instrumentCode, {
                  'current_condition': 'For Repair',
                  'scheduled_condemn_date': null,
                  'notes': 'Condemnation denied: ${reasonCtrl.text.trim()}',
                });
              } catch (_) {}
              final prefs2 = await SharedPreferences.getInstance();
              final adminName = prefs2.getString('user_name') ?? 'Admin';
              await DBHelper.instance.logActivity(
                eventType: 'condemn_denied',
                eventDetail: 'Denied condemnation of ${inst.instrumentCode} (${inst.instrumentName}). Reason: ${reasonCtrl.text.trim()}',
                actor: adminName,
              );
              _load();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Condemnation denied — reset to For Repair'),
                    backgroundColor: Colors.orange));
              }
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange, foregroundColor: Colors.white),
            child: const Text('DENY', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(children: [
            const Icon(Icons.gavel, color: Color(0xFFF5A623), size: 16),
            const SizedBox(width: 8),
            const Expanded(
              child: Text('PENDING CONDEMN REQUESTS',
                  style: TextStyle(
                      color: Color(0xFFF5A623),
                      fontSize: 11,
                      letterSpacing: 2,
                      fontWeight: FontWeight.bold)),
            ),
            Text('${_condemning.length} instruments',
                style: const TextStyle(color: Colors.white38, fontSize: 11)),
          ]),
        ),
        if (_revertRequests.isNotEmpty) ...[
          Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.deepOrange.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.deepOrange.withValues(alpha: 0.5)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.undo, color: Colors.deepOrange, size: 14),
                  const SizedBox(width: 6),
                  Text('${_revertRequests.length} REVERT REQUEST${_revertRequests.length > 1 ? 'S' : ''} — PENDING APPROVAL',
                      style: const TextStyle(color: Colors.deepOrange, fontSize: 10,
                          letterSpacing: 1.5, fontWeight: FontWeight.bold)),
                ]),
                const SizedBox(height: 8),
                ..._revertRequests.map((req) {
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0D1B2A),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.deepOrange.withValues(alpha: 0.3)),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(req['instrument_name'] ?? req['instrument_code'] ?? '—',
                          style: const TextStyle(color: Colors.white,
                              fontWeight: FontWeight.bold, fontSize: 13)),
                      Text(req['instrument_code'] ?? '—',
                          style: const TextStyle(color: Colors.white54, fontSize: 11)),
                      const SizedBox(height: 4),
                      Text('Requested by: ${req['requested_by'] ?? '—'}',
                          style: const TextStyle(color: Colors.white38, fontSize: 11)),
                      Text('Wants to revert to: ${req['requested_condition'] ?? '—'}',
                          style: const TextStyle(color: Colors.deepOrange, fontSize: 11,
                              fontWeight: FontWeight.w600)),
                      Text('Reason: ${req['reason'] ?? '—'}',
                          style: const TextStyle(color: Colors.white54, fontSize: 11)),
                      const SizedBox(height: 10),
                      Row(children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () async {
                              await DBHelper.instance.denyRevertRequest(
                                  req['instrument_code'] as String);
                              try {
                                await ApiService.respondRevertRequest(
                                    req['instrument_code'] as String, 'denied');
                              } catch (_) {}
                              _load();
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Revert request denied'),
                                        backgroundColor: Colors.orange));
                              }
                            },
                            style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.orange,
                                side: const BorderSide(color: Colors.orange),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8))),
                            child: const Text('DENY', style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () async {
                              await DBHelper.instance.approveRevertRequest(
                                req['instrument_code'] as String,
                                req['requested_condition'] as String,
                              );
                              _load();
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text('Revert approved — condition updated'),
                                        backgroundColor: Colors.green));
                              }
                            },
                            style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8))),
                            child: const Text('APPROVE', style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ]),
                    ]),
                  );
                }),
              ],
            ),
          ),
        ],
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: Color(0xFFF5A623)))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _condemning.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.check_circle_outline,
                                  color: Colors.green.withValues(alpha: 0.6), size: 56),
                              const SizedBox(height: 12),
                              const Text('No instruments set for condemnation',
                                  style: TextStyle(color: Colors.white54)),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: _condemning.length,
                          itemBuilder: (_, i) {
                            final inst = _condemning[i];
                            final dateStr = inst.scheduledCondemnDate;
                            int? daysLeft;
                            if (dateStr != null) {
                              try {
                                final due = DateTime.parse(dateStr);
                                daysLeft = due.difference(DateTime.now()).inDays;
                              } catch (_) {}
                            }
                            final String daysLabel = daysLeft == null
                                ? 'No date set'
                                : daysLeft < 0
                                    ? '${daysLeft.abs()} days OVERDUE'
                                    : daysLeft == 0
                                        ? 'Due TODAY'
                                        : 'In $daysLeft days';
                            final Color daysColor = daysLeft == null
                                ? Colors.white38
                                : daysLeft <= 0
                                    ? Colors.red
                                    : daysLeft <= 7
                                        ? Colors.orange
                                        : Colors.white54;
                            return Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1A3A5C),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.red.withValues(alpha: 0.4)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(children: [
                                    Container(
                                      width: 40,
                                      height: 40,
                                      decoration: BoxDecoration(
                                        color: Colors.red.withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Icon(Icons.gavel, color: Colors.red, size: 20),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(inst.instrumentName,
                                              style: const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 14)),
                                          Text(inst.instrumentCode,
                                              style: const TextStyle(
                                                  color: Colors.white54, fontSize: 12)),
                                        ],
                                      ),
                                    ),
                                    Text(daysLabel,
                                        style: TextStyle(
                                            color: daysColor,
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold)),
                                  ]),
                                  const SizedBox(height: 8),
                                  if (dateStr != null)
                                    Text('Scheduled: $dateStr',
                                        style: const TextStyle(color: Colors.white38, fontSize: 11)),
                                  if (inst.notes != null && inst.notes!.isNotEmpty)
                                    Text('Notes: ${inst.notes}',
                                        style: const TextStyle(color: Colors.white38, fontSize: 11)),
                                  // Show condemn reason from condemn_requests table
                                  FutureBuilder<List<Map<String, dynamic>>>(
                                    future: DBHelper.instance.getAllCondemnRequests(),
                                    builder: (_, snap) {
                                      final req = (snap.data ?? []).firstWhere(
                                        (r) => r['instrument_code'] == inst.instrumentCode,
                                        orElse: () => {},
                                      );
                                      final reason = req['reason'] as String?;
                                      if (reason == null || reason.isEmpty) return const SizedBox.shrink();
                                      return Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Row(children: [
                                          const Icon(Icons.info_outline, color: Colors.orange, size: 12),
                                          const SizedBox(width: 4),
                                          Expanded(child: Text('Reason: $reason',
                                              style: const TextStyle(color: Colors.orange, fontSize: 11))),
                                        ]),
                                      );
                                    },
                                  ),
                                  const SizedBox(height: 12),
                                  Row(children: [
                                    Expanded(
                                      child: OutlinedButton(
                                        onPressed: () => _deny(inst),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: Colors.orange,
                                          side: const BorderSide(color: Colors.orange),
                                          shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(8)),
                                        ),
                                        child: const Text('DENY',
                                            style: TextStyle(fontWeight: FontWeight.bold)),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: ElevatedButton(
                                        onPressed: () => _approve(inst),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.red,
                                          foregroundColor: Colors.white,
                                          shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(8)),
                                        ),
                                        child: const Text('APPROVE & DELETE',
                                            style: TextStyle(fontWeight: FontWeight.bold)),
                                      ),
                                    ),
                                  ]),
                                ],
                              ),
                            );
                          },
                        ),
                ),
        ),
      ],
    );
  }
}
class _UserHistoryGrouped extends StatefulWidget {
  final List<dynamic> history;
  final ScrollController controller;
  const _UserHistoryGrouped(
      {required this.history, required this.controller});
  @override
  State<_UserHistoryGrouped> createState() => _UserHistoryGroupedState();
}

class _UserHistoryGroupedState extends State<_UserHistoryGrouped> {
  final Set<String> _expanded = {};

  /// Returns "This Week", "This Month", "March", or "March 2024"
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
      final key = _periodKey(e);
      grouped.putIfAbsent(key, () => []).add(e);
    }
    final keys = _orderedKeys(grouped);

    return ListView.builder(
      controller: widget.controller,
      padding: const EdgeInsets.only(bottom: 32),
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
                margin: const EdgeInsets.only(bottom: 4, top: 4),
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E3A5F),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(children: [
                  Icon(isOpen
                      ? Icons.keyboard_arrow_down
                      : Icons.keyboard_arrow_right,
                      color: const Color(0xFFF5A623), size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(key,
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12)),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5A623).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text('${items.length}',
                        style: const TextStyle(
                            color: Color(0xFFF5A623),
                            fontSize: 10,
                            fontWeight: FontWeight.bold)),
                  ),
                ]),
              ),
            ),
            if (isOpen)
              ...items.map((e) => Container(
                margin: const EdgeInsets.only(bottom: 4, left: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D1B2A),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF1E3A5F)),
                ),
                child: Row(children: [
                  const Icon(Icons.circle,
                      color: Color(0xFFF5A623), size: 6),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(e['event_detail'] ?? e['event_type'] ?? '',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 12)),
                        if ((e['instrument_code'] ?? '').isNotEmpty)
                          Text(e['instrument_code'] ?? '',
                              style: const TextStyle(
                                  color: Colors.white38, fontSize: 10)),
                      ],
                    ),
                  ),
                  Text(_fmtTime(e),
                      style: const TextStyle(
                          color: Colors.white38, fontSize: 10)),
                ]),
              )),
          ],
        );
      },
    );
  }
  
}
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

// ── Grouped Activity Log Widget ──────────────────────────────────────────────
class _ActivityLogGrouped extends StatefulWidget {
  final List<dynamic> logs;
  const _ActivityLogGrouped({required this.logs});
  @override
  State<_ActivityLogGrouped> createState() => _ActivityLogGroupedState();
}

class _ActivityLogGroupedState extends State<_ActivityLogGrouped> {
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

  Color _logColor(String? type) {
    switch (type) {
      case 'login': return Colors.green;
      case 'dispatch_created': return Colors.blue;
      case 'condition_changed': return Colors.orange;
      case 'condemn_approved': return Colors.red;
      case 'condemn_denied': return Colors.orange;
      default: return Colors.white38;
    }
  }

  IconData _logIcon(String? type) {
    switch (type) {
      case 'login': return Icons.login;
      case 'dispatch_created': return Icons.outbox;
      case 'condition_changed': return Icons.build;
      case 'condemn_approved': return Icons.delete;
      case 'condemn_denied': return Icons.undo;
      default: return Icons.circle;
    }
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
    for (final e in widget.logs) {
      grouped.putIfAbsent(_periodKey(e), () => []).add(e);
    }
    final keys = _orderedKeys(grouped);
    return Column(
      children: keys.map((key) {
        final items = grouped[key]!;
        final isOpen = _expanded.contains(key);
        return Column(
          children: [
            GestureDetector(
              onTap: () => setState(() {
                if (isOpen) _expanded.remove(key);
                else _expanded.add(key);
              }),
              child: Container(
                margin: const EdgeInsets.only(bottom: 4),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E3A5F),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(children: [
                  Icon(isOpen ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right,
                      color: const Color(0xFFF5A623), size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text(key,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5A623).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text('${items.length}',
                        style: const TextStyle(color: Color(0xFFF5A623), fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                ]),
              ),
            ),
            if (isOpen)
              ...items.map((e) {
                final type = e['event_type'] as String?;
                return Container(
                  margin: const EdgeInsets.only(bottom: 4, left: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A3A5C),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _logColor(type).withValues(alpha: 0.25)),
                  ),
                  child: Row(children: [
                    Icon(_logIcon(type), color: _logColor(type), size: 16),
                    const SizedBox(width: 10),
                    Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(e['event_detail'] ?? type ?? '',
                            style: const TextStyle(color: Colors.white, fontSize: 12)),
                        if (e['actor'] != null)
                          Text(e['actor'], style: const TextStyle(color: Colors.white38, fontSize: 10)),
                      ],
                    )),
                    Text(_fmtTime(e), style: const TextStyle(color: Colors.white38, fontSize: 10)),
                  ]),
                );
              }),
            const SizedBox(height: 4),
          ],
        );
      }).toList(),
    );
  }
}

class _AdminMessageHistoryList extends StatefulWidget {
  final List<dynamic> messages;
  final ScrollController controller;
  const _AdminMessageHistoryList(
      {required this.messages, required this.controller});
  @override
  State<_AdminMessageHistoryList> createState() =>
      _AdminMessageHistoryListState();
}

class _AdminMessageHistoryListState
    extends State<_AdminMessageHistoryList> {
  final Set<String> _expanded = {};

  String _groupKey(dynamic msg) {
    try {
      final d = DateTime.parse(msg['created_at'] ?? '');
      final now = DateTime.now();
      final diff = now.difference(d).inDays;
      if (diff < 7) return 'This Week';
      if (diff < 30) return 'This Month';
      // Group by Month Year for older
      const months = ['Jan','Feb','Mar','Apr','May','Jun',
                      'Jul','Aug','Sep','Oct','Nov','Dec'];
      return '${months[d.month - 1]} ${d.year}';
    } catch (_) {
      return 'Unknown';
    }
  }

  String _fmtTime(dynamic msg) {
    try {
      final d = DateTime.parse(msg['created_at'] ?? '');
      return '${d.day}/${d.month}/${d.year}  '
          '${d.hour.toString().padLeft(2, '0')}:'
          '${d.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final Map<String, List<dynamic>> grouped = {};
    for (final m in widget.messages) {
      final key = _groupKey(m);
      grouped.putIfAbsent(key, () => []).add(m);
    }
    // Sort keys: This Week first, This Month second, then reverse chron
    final keyOrder = ['This Week', 'This Month'];
    final otherKeys = grouped.keys
        .where((k) => !keyOrder.contains(k))
        .toList()
      ..sort((a, b) => b.compareTo(a));
    final keys = [
      ...keyOrder.where((k) => grouped.containsKey(k)),
      ...otherKeys,
    ];

    return ListView.builder(
      controller: widget.controller,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
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
                margin: const EdgeInsets.only(top: 4, bottom: 2),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E3A5F),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(children: [
                  Icon(isOpen
                      ? Icons.keyboard_arrow_down
                      : Icons.keyboard_arrow_right,
                      color: const Color(0xFFF5A623), size: 16),
                  const SizedBox(width: 8),
                  Expanded(child: Text(key,
                      style: const TextStyle(color: Colors.white,
                          fontWeight: FontWeight.bold, fontSize: 12))),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5A623).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text('${items.length}',
                        style: const TextStyle(color: Color(0xFFF5A623),
                            fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                ]),
              ),
            ),
            if (isOpen)
              ...items.map((msg) {
                final isRead = msg['read_at'] != null;
                return Container(
                  margin: const EdgeInsets.only(bottom: 5, left: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D1B2A),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: isRead
                            ? Colors.green.withValues(alpha: 0.4)
                            : const Color(0xFF1E3A5F)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Icon(isRead ? Icons.done_all : Icons.done,
                            color: isRead ? Colors.green : Colors.white38,
                            size: 13),
                        const SizedBox(width: 6),
                        Expanded(child: Text(
                            msg['message'] ?? '',
                            style: const TextStyle(color: Colors.white,
                                fontSize: 12),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis)),
                        const SizedBox(width: 6),
                        Text(isRead ? '✓ Read' : 'Unread',
                            style: TextStyle(
                                color: isRead ? Colors.green : Colors.orange,
                                fontSize: 10,
                                fontWeight: FontWeight.bold)),
                      ]),
                      const SizedBox(height: 3),
                      Text(_fmtTime(msg),
                          style: const TextStyle(
                              color: Colors.white38, fontSize: 10)),
                    ],
                  ),
                );
              }),
          ],
        );
      },
    );
  }
}