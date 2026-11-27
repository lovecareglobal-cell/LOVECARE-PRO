import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/language_service.dart';
import '../services/translations.dart';

/// Client Dashboard - CLIENT ONLY
/// - NEW 20/80 RULE: Client pays ONLY 20% CEO fee in app to book.
///   Nurse cash 80% is paid CASH by client to nurse AFTER work. CEO never sends money to nurse.
/// - 50% DELETED: 'Book Nurse 50%' button + '/book-nurse-50' route DELETED.
/// - 'Increase Payment / Top up booking' DELETED (that was old 50% balance top-up).
///   Replaced with 'Confirm Cash Paid' -> /my-bookings (80% cash to nurse).
/// - Terms banner: Nurse rejects = full 20% refund. Client cancels before start = CEO keeps 20%.
///   Client cancels after start = CEO keeps 20% + client pays nurse cash for days worked.
/// - My Job Offer removed - na for NURSES only (kept).

class ClientDashboardScreen extends StatefulWidget {
  const ClientDashboardScreen({super.key});
  @override
  State<ClientDashboardScreen> createState() => _ClientDashboardScreenState();
}

class _ClientDashboardScreenState extends State<ClientDashboardScreen> {
  String clientName = 'Client';
  String clientPhone = '';
  int myBookingsCount = 0;
  int liveNursesCount = 0;
  DateTime ghanaNow = DateTime.now().toUtc();
  bool _disposed = false;

  StreamSubscription<DatabaseEvent>? _bookingsSub;
  StreamSubscription<DatabaseEvent>? _liveSub;
  Timer? _clockTimer;

  @override
  void initState() {
    super.initState();
    _loadClient();
    _listenBookingsCountLive();
    _loadLiveNursesCount();
    _startClock();
  }

  @override
  void dispose() {
    _disposed = true;
    _bookingsSub?.cancel();
    _liveSub?.cancel();
    _clockTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadClient() async {
    final prefs = await SharedPreferences.getInstance();
    final auth = FirebaseAuth.instance.currentUser;
    if (!mounted) return;
    setState(() {
      clientName = prefs.getString('clientName') ?? prefs.getString('fullName') ?? auth?.displayName ?? 'Client';
      clientPhone = prefs.getString('clientPhone') ?? prefs.getString('phone') ?? auth?.phoneNumber ?? '';
    });
  }

  String normPhone(String? p) {
    if (p == null) return '';
    var d = p.replaceAll(RegExp(r'[^0-9]'), '');
    if (d.startsWith('233')) d = '0${d.substring(3)}';
    if (d.length > 10) d = d.substring(d.length - 10);
    return d;
  }

  void _listenBookingsCountLive() {
    _bookingsSub?.cancel();
    _bookingsSub = FirebaseDatabase.instance.ref('bookings').onValue.listen((e) {
      if (_disposed || !mounted) return;
      if (!e.snapshot.exists || e.snapshot.value == null) {
        setState(() => myBookingsCount = 0);
        return;
      }
      final val = e.snapshot.value;
      int count = 0;
      if (val is Map) {
        val.forEach((k, v) {
          if (v is Map) {
            final s = '${v['status'] ?? ''}'.toLowerCase();
            if (s.contains('complete') || s.contains('cancel') || s.contains('reject')) return;
            final p = normPhone('${v['clientPhone'] ?? v['phone'] ?? ''}');
            final u = '${v['clientId'] ?? v['userId'] ?? v['uid'] ?? ''}';
            final myP = normPhone(clientPhone);
            final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';
            if ((myP.isEmpty && myUid.isEmpty) || p == myP || (u.isNotEmpty && u == myUid)) count++;
          }
        });
      }
      setState(() => myBookingsCount = count);
    }, onError: (_) {});
  }

  void _loadLiveNursesCount() {
    _liveSub?.cancel();
    _liveSub = FirebaseDatabase.instance.ref('onlineNurses').onValue.listen((e) {
      if (_disposed || !mounted) return;
      int count = 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      if (e.snapshot.exists && e.snapshot.value is Map) {
        (e.snapshot.value as Map).forEach((k, v) {
          if (v is Map) {
            final isOnline = v['isOnline'] == true || v['online'] == true;
            final lastSeen = int.tryParse('${v['lastSeen'] ?? v['timestamp'] ?? 0}') ?? 0;
            if (isOnline) {
              if (lastSeen == 0 || now - lastSeen < 2 * 60 * 1000) count++;
            } else if (lastSeen != 0 && now - lastSeen < 2 * 60 * 1000 && !v.containsKey('isOnline')) {
              count++;
            }
          } else if (v == true) count++;
        });
      }
      setState(() => liveNursesCount = count);
    });
  }

  void _startClock() {
    _clockTimer?.cancel();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_disposed || !mounted) return;
      setState(() => ghanaNow = DateTime.now().toUtc());
    });
  }

  String get ghanaTime => DateFormat('EEE • MMM d, y • hh:mm:ss a').format(ghanaNow);

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    try { await FirebaseAuth.instance.signOut(); } catch (_) {}
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/home', (r) => false);
  }

  @override
  Widget build(BuildContext context) {
    const pink = Color(0xFFE91E63);
    const darkPink = Color(0xFF880E4F);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: pink,
        elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => Navigator.pop(context)),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${tr('dashHi')}, $clientName', style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
            Text('$liveNursesCount ${tr('dashOnline')} • $ghanaTime', style: const TextStyle(color: Colors.white, fontSize: 12)),
          ],
        ),
        actions: [
          DropdownButtonHideUnderline(child: DropdownButton<String>(value: LanguageService.instance.locale.languageCode, dropdownColor: pink, icon: const Icon(Icons.language, color: Colors.white, size: 22), items: LanguageService.languageNames.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, style: const TextStyle(color: Colors.black)))).toList(), onChanged: (v) { if (v != null) LanguageService.instance.setLanguage(v); })),
          IconButton(icon: const Icon(Icons.notifications, color: Colors.white, size: 28), onPressed: () => Navigator.pushNamed(context, '/client-settings')),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: pink, borderRadius: BorderRadius.circular(20)),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 34,
                    backgroundColor: Colors.white,
                    child: Text(clientName.isNotEmpty ? clientName[0].toUpperCase() : 'C', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: pink)),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(clientName, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 2),
                        // FIXED: Phone no go break into 2 lines again
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(clientPhone, maxLines: 1, style: const TextStyle(color: Colors.white70, fontSize: 16)),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(30)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(width: 10, height: 10, decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle)),
                        const SizedBox(width: 6),
                        Text('$liveNursesCount ${tr('dashOnline')}', style: const TextStyle(color: darkPink, fontSize: 12, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // NEW 20/80 BANNER - so client no go confuse again
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFF22C55E).withOpacity(0.12), borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFF22C55E).withOpacity(0.4))),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tr('dash2080Line1'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 4),
                  Text(tr('dash2080Line2'), style: const TextStyle(fontSize: 11, color: Colors.black54)),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ===== CLIENT DASHBOARD - ONLY BUTTONS - NO MY JOB OFFER =====
            // My Job Offer removed - na for NURSES only
            Row(children: [
              Expanded(child: _button(tr('dashBookNurse'), Icons.local_hospital, liveNursesCount > 0 ? '$liveNursesCount ${tr('dashNurseOnline')}' : tr('dashNoNurseOnline'), pink, () => Navigator.pushNamed(context, '/book-nurse'))),
              const SizedBox(width: 12),
              Expanded(child: _button(tr('dashMyBookings'), Icons.calendar_today, '$myBookingsCount ${tr('dashBookingsWord')}', pink, () => Navigator.pushNamed(context, '/my-bookings'))),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              // 50% DELETED - replaced with 20% to Book (same /book-nurse page)
              Expanded(child: _button(tr('dashBook20'), Icons.discount, tr('dashBook20Sub'), pink, () => Navigator.pushNamed(context, '/book-nurse'))),
              const SizedBox(width: 12),
              Expanded(child: _button(tr('dashSos'), Icons.sos, tr('dashSosSub'), Colors.red, () => Navigator.pushNamed(context, '/sos'))),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _button(tr('dashComplaint'), Icons.report_problem, tr('dashComplaintSub'), pink, () => Navigator.pushNamed(context, '/client-complaint'))),
              const SizedBox(width: 12),
              Expanded(child: _button(tr('dashRateNurse'), Icons.star, tr('dashRateNurseSub'), pink, () => Navigator.pushNamed(context, '/rating'))),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _button(tr('dashRefundQuery'), Icons.money_off, tr('dashRefundQuerySub'), pink, () => Navigator.pushNamed(context, '/refund-query'))),
              const SizedBox(width: 12),
              // Increase Payment (old 50% top-up) DELETED - replaced with Confirm Cash Paid
              Expanded(child: _button(tr('dashConfirmCash'), Icons.money, tr('dashConfirmCashSub'), pink, () => Navigator.pushNamed(context, '/my-bookings'))),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _button(tr('dashSettings'), Icons.settings, tr('dashSettingsSub'), pink, () => Navigator.pushNamed(context, '/client-settings'))),
              const SizedBox(width: 12),
              Expanded(child: _button(tr('dashLogout'), Icons.logout, tr('dashLogoutSub'), darkPink, _logout)),
            ]),
            const SizedBox(height: 16),

            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
              child: Row(children: [const Icon(Icons.access_time, color: Colors.grey, size: 22), const SizedBox(width: 10), Expanded(child: Text(ghanaTime, style: const TextStyle(color: Colors.black, fontSize: 14, fontWeight: FontWeight.bold)))]),
            ),
            const SizedBox(height: 20),
            Text(tr('dashFooter'), style: TextStyle(color: Colors.grey, fontSize: 11)),
          ],
        ),
      ),
    );
  }

  Widget _button(String title, IconData icon, String subtitle, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 30),
            const SizedBox(height: 14),
            Text(title, style: const TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(subtitle, style: const TextStyle(color: Colors.grey, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
