import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audioplayers/audioplayers.dart';
import '../services/language_service.dart';
import '../services/translations.dart';

/// My Job Offer - Flutter version of my-job-offer.html
/// - Loads from: bookings + allBookings + ceoBookings + bookingsByFull + clientBookings/myBookings/bookingsByClient (by uid/emailKey) + bookingsByPhone/{phone9} + SharedPreferences myBookings
///   Dedupe by bookingId (same as HTML loadAll map)
/// - Matching: matchesBooking(v, myIds) — phone last 9 + email + UID from ALL prefs keys (same as HTML getAllIdentities)
///   If 0 matched but bookings exist -> show recent 5 so nurse can see pending + Claim (same as HTML)
///   showMode recent -> recent 10 non-terminal non-history
/// - Terminal / History: isTerminal + isHistory filtered out (completed/paid/cancelled etc are in History)
/// - Actions (same as HTML, each sends sound trigger to client):
///   Accept: bookings/{id} status accepted, lastChangedBy nurse, acceptedAt, acceptedAtStr, trigger client {status accepted, title Nurse accepted}
///   Reject: status rejected_by_nurse, rejectedAt, rejectedByNurseName, trigger client {rejected_by_nurse}
///   On Way: status on_the_way, lastChangedUid/Phone, trigger client
///   Close: status close, trigger client {title Nurse is close}
///   Completed: status completed, trigger client {title Nurse completed} — 'Completed - Collect CASH from client'
///   Confirm Done (client side in HTML, kept here): nurseBookingHistory/{key}/{id} {status client_confirmed_finished, clientConfirmed, clientConfirmedAt} + bookings/{id} status client_confirmed_finished, then remove bookings/{id} after 800ms
///   Cancel: bookings/{id} status cancelled_by_client
///   Claim: save nursePhone / nurseEmail to prefs, reload
/// - History: nurseBookingHistory/{key} for uid/phone/email keys, sorted by clientConfirmedAt desc, Delete / Delete All, View Receipt
/// - Receiver-only sound: same as nurse-dashboard (bookings child_changed shouldRing + soundTriggers)
/// - NEW 20/80 RULE (Nov 2026): Nurse sees ONLY her cash (80%). NEVER total, NEVER CEO fee (20%).
///   _nurseCash(b) = nurseCash / nurseCashAmount / amountYouWillCollectCash / 80% of total (fallback).
///   Accept: nurse stays Busy/Locked. Reject: nurse -> Available, booking rejected_by_nurse, client gets FULL 20% refund.
///   Completed: nurse collects CASH from client, confirms cash received, then nurse -> Available. CEO NEVER pays nurse.

class MyJobOfferScreen extends StatefulWidget {
  const MyJobOfferScreen({super.key});
  @override
  State<MyJobOfferScreen> createState() => _MyJobOfferScreenState();
}

class _MyJobOfferScreenState extends State<MyJobOfferScreen> {
  List<Map> all = [];
  List<Map> historyData = [];
  List<String> myPhones = [], myEmails = [], myUids = [];
  String showMode = 'mine'; // mine | recent
  bool showHistory = false;
  final AudioPlayer _player = AudioPlayer();

  @override
  void initState() {
    super.initState();
    _loadAll();
    _loadHistory();
    _startSound();
  }

  Future<void> _getAllIdentities() async {
    final prefs = await SharedPreferences.getInstance();
    myPhones = []; myEmails = []; myUids = [];
    for (final k in prefs.getKeys()) {
      final v = prefs.getString(k) ?? '';
      final kl = k.toLowerCase();
      if (kl.contains('phone')) { final p = v.replaceAll(RegExp(r'[^0-9]'), ''); if (p.length >= 9) myPhones.add(p.substring(p.length - 9)); }
      if (kl.contains('email')) myEmails.add(v.toLowerCase().trim());
      if (kl.contains('uid') || k == 'id') myUids.add(v);
    }
    // Auth is truth - login saves NO prefs, so prefs-only = NONE / 'Login again'.
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        if (user.uid.isNotEmpty) myUids.add(user.uid);
        if (user.email != null && user.email!.isNotEmpty) myEmails.add(_normEmail(user.email!));
        try {
          final doc = await FirebaseFirestore.instance.collection('nurses').doc(user.uid).get();
          if (doc.exists && doc.data() != null) {
            final d = doc.data()!;
            if (d['phone'] != null) { final p = _normPhone(d['phone'].toString()); if (p.isNotEmpty) myPhones.add(p); }
            if (d['email'] != null) myEmails.add(_normEmail(d['email'].toString()));
          }
        } catch (_) {}
      }
    } catch (_) {}
    // Dedupe
    myPhones = myPhones.toSet().toList(); myEmails = myEmails.toSet().toList(); myUids = myUids.toSet().toList();
  }

  String _normPhone(String s) { final p = s.replaceAll(RegExp(r'[^0-9]'), ''); return p.length >= 9 ? p.substring(p.length - 9) : p; }
  String _normEmail(String s) => s.toLowerCase().trim();

  // Time may be num (ms) or String (ISO / digits) - 'as num' crashes on String.
  int _toMillis(dynamic v) {
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? DateTime.tryParse(v)?.millisecondsSinceEpoch ?? 0;
    return 0;
  }

  String _formatTime(dynamic v) {
    final ms = _toMillis(v);
    if (ms <= 0) return '';
    return DateTime.fromMillisecondsSinceEpoch(ms).toString();
  }

  // RTDB KEY, not bookingId. bookingId != key in _loadAll, so updating
  // bookings/<bookingId> created a duplicate node and the real booking never changed.
  String _rtKey(Map b) => (b['id'] ?? b['bookingId'] ?? '').toString();

  // NEW 20/80: Nurse sees ONLY her cash. Never total / CEO fee.
  double _nurseCash(Map b) {
    double v(dynamic x) {
      if (x == null) return 0;
      if (x is num) return x.toDouble();
      return double.tryParse(x.toString()) ?? 0;
    }
    double c = v(b['nurseCash']);
    if (c > 0) return c;
    c = v(b['nurseCashAmount']);
    if (c > 0) return c;
    c = v(b['amountYouWillCollectCash']);
    if (c > 0) return c;
    final total = v(b['totalAmount'] ?? b['total'] ?? b['amount']);
    if (total > 0) return total * 0.80;
    return 0;
  }
  String _nurseCashStr(Map b) {
    final cur = (b['currency'] ?? 'GHS').toString();
    return '$cur ${_nurseCash(b).toStringAsFixed(2)}';
  }
  Future<void> _unlockNurse(Map b) async {
    final nid = (b['nurseId'] ?? '').toString();
    if (nid.isEmpty) return;
    try {
      await FirebaseDatabase.instance.ref('nurses/$nid').update({'isAvailable': true, 'isBooked': false, 'isBusy': false, 'status': 'available', 'currentBookingId': null, 'currentBookingStatus': null});
    } catch (_) {}
    try {
      await FirebaseDatabase.instance.ref('onlineNurses/$nid').update({'isAvailable': true, 'isBooked': false, 'currentBookingId': null});
    } catch (_) {}
  }
  Future<void> _lockNurse(Map b) async {
    final nid = (b['nurseId'] ?? '').toString();
    if (nid.isEmpty) return;
    final bid = (b['bookingId'] ?? b['id'] ?? '').toString();
    try {
      await FirebaseDatabase.instance.ref('nurses/$nid').update({'isAvailable': false, 'isBooked': true, 'isBusy': true, 'status': 'busy', 'currentBookingId': bid, 'currentBookingStatus': 'accepted'});
    } catch (_) {}
  }

  bool _matchesBooking(Map v) {
    if (myPhones.isEmpty && myEmails.isEmpty && myUids.isEmpty) return true;
    final bPhones = [(v['clientPhone'] ?? ''), (v['phone'] ?? ''), (v['nursePhone'] ?? '')].map((e) => _normPhone(e.toString())).toList();
    final bEmails = [(v['clientEmail'] ?? ''), (v['email'] ?? ''), (v['nurseEmail'] ?? '')].map((e) => _normEmail(e.toString())).toList();
    final bUids = [v['clientUid'], v['clientId'], v['uid'], v['nurseId'], v['nurseUid']].map((e) => e?.toString() ?? '').toList();
    if (myPhones.any((p) => bPhones.contains(p))) return true;
    if (myEmails.any((e) => bEmails.contains(e))) return true;
    if (myUids.any((u) => bUids.contains(u))) return true;
    return false;
  }

  bool _isTerminal(Map v) {
    final s = (v['status'] ?? '').toString().toLowerCase();
    return s.contains('cancelled') || s == 'rejected' || s == 'rejected_by_nurse' || s == 'ceo_paid' || s == 'paid' || v['paid'] == true;
  }

  bool _isHistory(Map v) => (v['status'] ?? '').toString().toLowerCase() == 'client_confirmed_finished' || v['clientConfirmed'] == true;

  List<Map> get filtered {
    var arr = List<Map>.from(all);
    if (showMode == 'recent') {
      arr.sort((a, b) => _toMillis(b['time'] ?? b['createdAt']).compareTo(_toMillis(a['time'] ?? a['createdAt'])));
      return arr.where((v) => !_isTerminal(v) && !_isHistory(v)).take(10).toList();
    }
    var f = arr.where((v) => !_isTerminal(v) && !_isHistory(v) && _matchesBooking(v)).toList();
    if (f.isEmpty && arr.isNotEmpty) {
      arr.sort((a, b) => _toMillis(b['time'] ?? b['createdAt']).compareTo(_toMillis(a['time'] ?? a['createdAt'])));
      f = arr.where((v) => !_isTerminal(v) && !_isHistory(v)).take(5).toList();
    }
    f.sort((a, b) => _toMillis(b['time'] ?? b['createdAt']).compareTo(_toMillis(a['time'] ?? a['createdAt'])));
    return f;
  }

  Future<void> _loadAll() async {
    await _getAllIdentities();
    final db = FirebaseDatabase.instance;
    Map<String, Map> map = {};
    for (final p in ['bookings', 'allBookings', 'ceoBookings', 'bookingsByFull']) {
      try {
        final s = await db.ref(p).get();
        if (s.exists) (s.value as Map).forEach((k, v) { final val = Map<String, dynamic>.from(v as Map); final bid = val['bookingId'] ?? k; if (!map.containsKey(bid)) map[bid] = {...val, 'id': k, 'bookingId': bid}; });
      } catch (_) {}
    }
    for (final uk in [...myUids, ...myEmails.map((e) => e.replaceAll(RegExp(r'[.@]'), '_'))]) {
      for (final base in ['clientBookings', 'myBookings', 'bookingsByClient']) {
        try {
          final s = await db.ref('$base/$uk').get();
          if (s.exists) (s.value as Map).forEach((k, v) { final val = Map<String, dynamic>.from(v as Map); final bid = val['bookingId'] ?? k; if (!map.containsKey(bid)) map[bid] = {...val, 'id': k, 'bookingId': bid}; });
        } catch (_) {}
      }
    }
    for (final ph in myPhones) {
      try {
        final s = await db.ref('bookingsByPhone/$ph').get();
        if (s.exists) (s.value as Map).forEach((k, v) { final val = Map<String, dynamic>.from(v as Map); final bid = val['bookingId'] ?? k; if (!map.containsKey(bid)) map[bid] = {...val, 'id': k, 'bookingId': bid}; });
      } catch (_) {}
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final local = prefs.getString('myBookings');
      if (local != null) {
        // myBookings stored as JSON string in prefs (if any) — parse loosely
      }
    } catch (_) {}
    setState(() => all = map.values.toList());
  }

  Future<void> _sendSoundTrigger(String toRole, Map data) async {
    try { await FirebaseDatabase.instance.ref('soundTriggers/$toRole').push().set({'fromRole': 'nurse', 'time': DateTime.now().millisecondsSinceEpoch, ...data}); } catch (_) {}
  }

  Future<void> _updateBooking(String id, Map data, String? triggerTitle, String? triggerStatus) async {
    final b = all.firstWhere((x) => x['id'] == id || x['bookingId'] == id, orElse: () => {});
    await FirebaseDatabase.instance.ref('bookings/$id').update(Map<String, Object?>.from(data));
    if (triggerTitle != null) {
      await _sendSoundTrigger('client', {'bookingId': id, 'status': triggerStatus ?? data['status'], 'title': triggerTitle, 'toPhone': b['clientPhone'], 'toUid': b['clientUid'] ?? b['clientId'], 'toEmail': b['clientEmail']});
    }
    await _loadAll();
  }

  Future<void> _acceptOffer(String id) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final b = all.firstWhere((x) => x['id'] == id || x['bookingId'] == id, orElse: () => {});
    await _updateBooking(id, {'status': 'accepted', 'lastChangedBy': 'nurse', 'lastChangedAt': now, 'acceptedAt': now, 'acceptedAtStr': DateTime.now().toString()}, 'Nurse accepted', 'accepted');
    await _lockNurse(b);
    _toast(tr('mjoAcceptedToast'));
  }

  Future<void> _rejectOffer(String id) async {
    final confirm = await showDialog<bool>(context: context, builder: (_) => AlertDialog(title: Text('${tr('mjoRejectTitle')} $id?'), content: Text(tr('mjoRejectBody')), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('mjoNo'))), ElevatedButton(onPressed: () => Navigator.pop(context, true), child: Text(tr('mjoReject')))]));
    if (confirm != true) return;
    final b = all.firstWhere((x) => x['id'] == id || x['bookingId'] == id, orElse: () => {});
    final now = DateTime.now().millisecondsSinceEpoch;
    await _updateBooking(id, {'status': 'rejected_by_nurse', 'lastChangedBy': 'nurse', 'lastChangedAt': now, 'rejectedAt': now, 'rejectedByNurseName': b['nurseName'], 'refundCeoFee': true, 'refundStatus': 'refund_due_full_20', 'cancelTermsApplied': 'nurse_rejects_refund_full_20'}, 'Nurse rejected your offer', 'rejected_by_nurse');
    await _unlockNurse(b);
    _toast(tr('mjoRejectedToast'));
  }

  Future<void> _markOnWay(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now().millisecondsSinceEpoch;
    await _updateBooking(id, {'status': 'on_the_way', 'lastChangedBy': 'nurse', 'lastChangedAt': now, 'lastChangedUid': prefs.getString('nurseUid') ?? prefs.getString('uid') ?? '', 'lastChangedPhone': prefs.getString('nursePhone') ?? prefs.getString('phone') ?? ''}, 'Nurse is on the way', 'on_the_way');
    _toast(tr('mjoOnWayToast'));
  }

  Future<void> _markClose(String id) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _updateBooking(id, {'status': 'close', 'lastChangedBy': 'nurse', 'lastChangedAt': now}, 'Nurse is close', 'close');
    _toast(tr('mjoCloseToast'));
  }

  Future<void> _confirmCashReceived(String id) async {
    final b = all.firstWhere((x) => x['id'] == id || x['bookingId'] == id, orElse: () => {});
    final confirm = await showDialog<bool>(context: context, builder: (_) => AlertDialog(title: Text(tr('mjoConfirmCashTitle')), content: Text('${tr('mjoConfirmCashBody1')}: ${_nurseCashStr(b)}\n${tr('mjoConfirmCashBody2')}'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('mjoNotYet'))), ElevatedButton(onPressed: () => Navigator.pop(context, true), child: Text(tr('mjoYesCashReceived')))]));
    if (confirm != true) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    await _updateBooking(id, {'status': 'cash_received_by_nurse', 'lastChangedBy': 'nurse', 'lastChangedAt': now, 'cashPaidToNurse': true, 'nurseCashPaid': true, 'cashConfirmedByNurse': true, 'cashConfirmedAt': now}, 'Nurse confirmed cash received', 'cash_received_by_nurse');
    await _unlockNurse(b);
    _toast(tr('mjoCashConfirmedToast'));
  }

  Future<void> _markCompleted(String id) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _updateBooking(id, {'status': 'completed', 'lastChangedBy': 'nurse', 'lastChangedAt': now}, 'Nurse completed', 'completed');
    _toast(tr('mjoCompletedToast'));
  }

  Future<void> _confirmDone(String id) async {
    final confirm = await showDialog<bool>(context: context, builder: (_) => AlertDialog(title: Text('${tr('mjoConfirmDoneTitle')} $id?'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('mjoNo'))), ElevatedButton(onPressed: () => Navigator.pop(context, true), child: Text(tr('mjoConfirm')))]));
    if (confirm != true) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final key = myUids.isNotEmpty ? myUids[0] : (myPhones.isNotEmpty ? myPhones[0] : (myEmails.isNotEmpty ? myEmails[0] : 'unknown'));
    final b = all.firstWhere((x) => x['id'] == id || x['bookingId'] == id, orElse: () => {});
    await FirebaseDatabase.instance.ref('nurseBookingHistory/$key/$id').set({...b, 'status': 'client_confirmed_finished', 'clientConfirmed': true, 'clientConfirmedAt': now, 'clientConfirmedAtStr': DateTime.now().toString(), 'nurseCash': _nurseCash(b)});
    await _unlockNurse(b);
    await FirebaseDatabase.instance.ref('bookings/$id').update({'status': 'client_confirmed_finished', 'clientConfirmed': true, 'clientConfirmedAt': now});
    Future.delayed(const Duration(milliseconds: 800), () async { await FirebaseDatabase.instance.ref('bookings/$id').remove().catchError((_) {}); _toast(tr('mjoConfirmedHistory')); _loadHistory(); _loadAll(); });
  }

  Future<void> _cancelBooking(String id) async {
    final confirm = await showDialog<bool>(context: context, builder: (_) => AlertDialog(title: Text('${tr('mjoCancelTitle')} $id?'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('mjoNo'))), ElevatedButton(onPressed: () => Navigator.pop(context, true), child: Text(tr('mjoCancel')))]));
    if (confirm != true) return;
    await FirebaseDatabase.instance.ref('bookings/$id').update({'status': 'cancelled_by_client', 'cancelledAt': DateTime.now().millisecondsSinceEpoch});
    _toast(tr('mjoCancelled'));
    _loadAll();
  }

  Future<void> _claimBooking(String id) async {
    final phoneCtrl = TextEditingController(text: myPhones.isNotEmpty ? myPhones[0] : '');
    final emailCtrl = TextEditingController(text: myEmails.isNotEmpty ? myEmails[0] : '');
    final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(title: Text(tr('mjoClaimTitle')), content: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: phoneCtrl, decoration: InputDecoration(labelText: tr('mjoYourPhone'))), TextField(controller: emailCtrl, decoration: InputDecoration(labelText: tr('mjoYourEmail')))]), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('mjoCancel'))), ElevatedButton(onPressed: () => Navigator.pop(context, true), child: Text(tr('mjoSave')))]));
    if (ok != true) return;
    final prefs = await SharedPreferences.getInstance();
    if (phoneCtrl.text.isNotEmpty) await prefs.setString('nursePhone', phoneCtrl.text);
    if (emailCtrl.text.isNotEmpty) await prefs.setString('nurseEmail', emailCtrl.text);
    _toast(tr('mjoSavedReloading'));
    _loadAll();
  }

  Future<void> _loadHistory() async {
    List<Map> arr = [];
    for (final k in [...myUids, ...myPhones, ...myEmails]) {
      try {
        final s = await FirebaseDatabase.instance.ref('nurseBookingHistory/$k').get();
        if (s.exists) (s.value as Map).forEach((key, v) { final val = Map<String, dynamic>.from(v as Map); arr.add({...val, 'id': key, 'bookingId': val['bookingId'] ?? key}); });
      } catch (_) {}
    }
    arr.sort((a, b) => _toMillis(b['clientConfirmedAt']).compareTo(_toMillis(a['clientConfirmedAt'])));
    setState(() => historyData = arr);
  }

  Future<void> _deleteHistory(String id) async {
    if (myUids.isEmpty && myPhones.isEmpty && myEmails.isEmpty) { _toast(tr('mjoLoginAgain')); return; }
    final key = myUids.isNotEmpty ? myUids[0] : (myPhones.isNotEmpty ? myPhones[0] : myEmails[0]);
    await FirebaseDatabase.instance.ref('nurseBookingHistory/$key/$id').remove().catchError((_) {});
    _loadHistory();
  }

  Future<void> _deleteAllHistory() async {
    final confirm = await showDialog<bool>(context: context, builder: (_) => AlertDialog(title: Text(tr('mjoDeleteAllTitle')), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('mjoNo'))), ElevatedButton(onPressed: () => Navigator.pop(context, true), child: Text(tr('mjoYes')))]));
    if (confirm != true) return;
    for (final k in [...myUids, ...myPhones, ...myEmails]) await FirebaseDatabase.instance.ref('nurseBookingHistory/$k').remove().catchError((_) {});
    _loadHistory();
  }

  void _startSound() {
    FirebaseDatabase.instance.ref('bookings').onChildChanged.listen((e) {
      if (!e.snapshot.exists) return;
      final v = Map<String, dynamic>.from(e.snapshot.value as Map);
      if (v['lastChangedBy'] == 'nurse') return;
      if (!_matchesBooking(v)) return;
      final t = _toMillis(v['lastChangedAt'] ?? v['time'] ?? v['createdAt']);
      if (DateTime.now().millisecondsSinceEpoch - t > 120000) return;
      _playCustomSound();
      _toast('🔔 ${tr('mjoNewReply')} - ${v['status'] ?? ''}');
    });
  }

  Future<void> _playCustomSound() async {
    final prefs = await SharedPreferences.getInstance();
    final custom = prefs.getString('alert_custom_song') ?? prefs.getString('nurse_custom_song');
    if (custom != null && custom.isNotEmpty) { try { await _player.play(UrlSource(custom)); return; } catch (_) {} }
    try { await _player.play(AssetSource('sounds/default.mp3')); } catch (_) {}
  }

  void _toast(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  void _showDetails(Map b) {
    showDialog(context: context, builder: (_) => AlertDialog(
      title: Text('${tr('mjoBookingId')} ${b['bookingId']}'),
      content: SingleChildScrollView(child: Text('${tr('mjoId')}: ${b['bookingId']}\n${tr('mjoStatus')}: ${b['status'] ?? tr('mjoPending')}\n${tr('mjoClient')}: ${b['clientName'] ?? ''} - ${b['clientPhone'] ?? ''}\n${tr('mjoNurse')}: ${b['nurseName'] ?? ''} - ${b['nursePhone'] ?? ''}\n${tr('mjoCollectCash')}: ${_nurseCashStr(b)}\n${tr('mjoService')}: ${b['serviceType'] ?? b['service'] ?? ''}\n${tr('mjoLocation')}: ${b['location'] ?? ''}\n${tr('mjoTime')}: ${_formatTime(b['time'])}')),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('mjoClose'))), ElevatedButton(onPressed: () { Navigator.pop(context); _claimBooking(_rtKey(b)); }, child: Text(tr('mjoClaimThisBooking')))],
    ));
  }

  @override
  Widget build(BuildContext context) {
    final list = filtered;
    return Scaffold(
      backgroundColor: const Color(0xFF0E0A1C),
      appBar: AppBar(title: Text(tr('mjoTitle'), style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)), backgroundColor: const Color(0xFF1A1633), actions: [DropdownButtonHideUnderline(child: DropdownButton<String>(value: LanguageService.instance.locale.languageCode, dropdownColor: const Color(0xFF0C0A1E), icon: const Icon(Icons.language, color: Colors.white, size: 24), items: LanguageService.languageNames.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, style: const TextStyle(color: Colors.black)))).toList(), onChanged: (v) { if (v != null) LanguageService.instance.setLanguage(v); })), TextButton(onPressed: () async { await _loadHistory(); setState(() => showHistory = !showHistory); }, child: Text(showHistory ? tr('mjoHideHistory') : '${tr('mjoHistory')} (${historyData.length})', style: const TextStyle(color: Colors.white)))]),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(children: [
          Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: const Color(0xFF1C1238), borderRadius: BorderRadius.circular(16)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr('mjoYourIdentity'), style: TextStyle(fontWeight: FontWeight.bold)),
            Text('${tr('mjoPhones')}: ${myPhones.isEmpty ? tr('mjoNoneLogin') : myPhones.join(', ')} | ${tr('mjoEmails')}: ${myEmails.isEmpty ? tr('mjoNone') : myEmails.join(', ')} | ${tr('mjoUids')}: ${myUids.isEmpty ? tr('mjoNone') : myUids.join(', ')}', style: const TextStyle(color: Colors.white60, fontSize: 11)),
            Text(tr('mjoMatchingHint'), style: TextStyle(color: Colors.white60, fontSize: 10)),
            const SizedBox(height: 8),
            Row(children: [
              ChoiceChip(label: Text(tr('mjoMyOffers')), selected: showMode == 'mine', onSelected: (_) { setState(() => showMode = 'mine'); }),
              const SizedBox(width: 8),
              ChoiceChip(label: Text(tr('mjoShowRecent10')), selected: showMode == 'recent', onSelected: (_) { setState(() => showMode = 'recent'); }),
              const Spacer(),
              TextButton(onPressed: _loadAll, child: Text(tr('mjoRefresh'))),
            ]),
          ])),
          const SizedBox(height: 12),
          if (showHistory) ...[
            Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: const Color(0xFF1C1238), borderRadius: BorderRadius.circular(16)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(tr('mjoHistoryTitle'), style: TextStyle(fontWeight: FontWeight.bold)), TextButton(onPressed: _deleteAllHistory, child: Text(tr('mjoDeleteAll'), style: TextStyle(color: Colors.red)))]),
              if (historyData.isEmpty) Text(tr('mjoNoHistory'), style: TextStyle(color: Colors.white60, fontSize: 11)),
              ...historyData.map((b) {
                return Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => _showDetails(b),
                          child: Text(
                            '${tr('mjoBookingId')} ${b['bookingId']} - ${b['paidAtStr'] ?? b['clientConfirmedAtStr'] ?? ''} - ${b['cashPaidToNurse'] == true || b['cashConfirmedByNurse'] == true ? '✅ ${tr('mjoCashCollected')}' : ''} - ${b['status']} - ${tr('mjoCash')}: ${_nurseCashStr(b)}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                      if (b['receipt'] != null)
                        TextButton(
                          onPressed: () => showDialog(
                            context: context,
                            builder: (_) => AlertDialog(
                              title: Text(tr('mjoReceipt')),
                              content: Image.network(b['receipt'].toString()),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: Text(tr('mjoClose')),
                                ),
                              ],
                            ),
                          ),
                          child: Text(tr('mjoReceipt')),
                        ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red, size: 18),
                        onPressed: () => _deleteHistory(_rtKey(b)),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ])),
            const SizedBox(height: 12),
          ],
          if (list.isEmpty) Padding(padding: EdgeInsets.all(20), child: Text(tr('mjoNoOffers'), textAlign: TextAlign.center, style: TextStyle(color: Colors.white60))),
          if (list.isNotEmpty && showMode == 'mine' && all.isNotEmpty && list.length == 5 && all.length > 5) Padding(padding: EdgeInsets.only(bottom: 8), child: Text(tr('mjoZeroMatched'), style: TextStyle(color: Color(0xFFFACC15), fontSize: 11))),
          ...list.map((b) {
            final s = (b['status'] ?? 'pending').toString().toLowerCase();
            return Container(margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: const Color(0xFF1C1238), borderRadius: BorderRadius.circular(16)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Expanded(child: Text('${tr('mjoBookingId')} ${b['bookingId']}', style: const TextStyle(fontWeight: FontWeight.bold))), Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: Colors.orange.withOpacity(0.2), borderRadius: BorderRadius.circular(999)), child: Text(s.toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)))]),
              const SizedBox(height: 6),
              Text('${tr('mjoClient')}: ${b['clientName'] ?? ''} - ${b['clientPhone'] ?? ''}', style: const TextStyle(fontSize: 12)),
              Text('${tr('mjoService')}: ${b['serviceType'] ?? b['service'] ?? ''}', style: const TextStyle(color: Colors.white60, fontSize: 11)),
              Container(margin: const EdgeInsets.only(top: 6), padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: const Color(0xFF22C55E).withOpacity(0.12), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFF22C55E).withOpacity(0.4))), child: Row(children: [const Icon(Icons.money, color: Colors.greenAccent, size: 18), const SizedBox(width: 6), Expanded(child: Text('${tr('mjoCollectCash')}: ${_nurseCashStr(b)}', style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 13)))])),
              Text('${tr('mjoLocation')}: ${b['location'] ?? ''}', style: const TextStyle(color: Colors.white60, fontSize: 11)),
              Text('${tr('mjoTime')}: ${_formatTime(b['time'])}', style: const TextStyle(color: Colors.white60, fontSize: 11)),
              const SizedBox(height: 10),
              Wrap(spacing: 6, runSpacing: 6, children: [
                if (s == 'pending' || s == 'new') ...[
                  ElevatedButton(onPressed: () => _acceptOffer(_rtKey(b)), style: ElevatedButton.styleFrom(backgroundColor: Colors.green), child: Text('✅ ${tr('mjoAccept')}', style: TextStyle(fontSize: 11))),
                  ElevatedButton(onPressed: () => _rejectOffer(_rtKey(b)), style: ElevatedButton.styleFrom(backgroundColor: Colors.red), child: Text('❌ ${tr('mjoReject')}', style: TextStyle(fontSize: 11))),
                ],
                if (s == 'accepted') ...[
                  ElevatedButton(onPressed: () => _markOnWay(_rtKey(b)), child: Text('🚗 ${tr('mjoOnWay')}', style: TextStyle(fontSize: 11))),
                  ElevatedButton(onPressed: () => _markClose(_rtKey(b)), child: Text('📍 ${tr('mjoCloseBtn')}', style: TextStyle(fontSize: 11))),
                  ElevatedButton(onPressed: () => _markCompleted(_rtKey(b)), style: ElevatedButton.styleFrom(backgroundColor: Colors.blue), child: Text('🎉 ${tr('mjoCompleted')}', style: TextStyle(fontSize: 11))),
                  ElevatedButton(onPressed: () => _confirmCashReceived(_rtKey(b)), style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF22C55E)), child: Text('💵 ${tr('mjoConfirmCashReceived')} - ${_nurseCashStr(b)}', style: const TextStyle(fontSize: 11))),
                ],
                if (s == 'on_the_way') ElevatedButton(onPressed: () => _markClose(_rtKey(b)), child: Text('📍 ${tr('mjoCloseBtn')}', style: TextStyle(fontSize: 11))),
                if (s == 'close' || s == 'completed') ElevatedButton(onPressed: () => _markCompleted(_rtKey(b)), style: ElevatedButton.styleFrom(backgroundColor: Colors.blue), child: Text('🎉 ${tr('mjoCompleted')}', style: TextStyle(fontSize: 11))),
                if (s == 'completed' || s == 'close') ElevatedButton(onPressed: () => _confirmCashReceived(_rtKey(b)), style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF22C55E)), child: Text('💵 ${tr('mjoConfirmCashReceived')} - ${_nurseCashStr(b)}', style: const TextStyle(fontSize: 11))),
                ElevatedButton(onPressed: () => _confirmDone(_rtKey(b)), style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF22C55E)), child: Text('✅ ${tr('mjoConfirmDone')}', style: TextStyle(fontSize: 11))),
                OutlinedButton(onPressed: () => _showDetails(b), child: Text(tr('mjoDetails'), style: TextStyle(fontSize: 11))),
                OutlinedButton(onPressed: () => _claimBooking(_rtKey(b)), child: Text(tr('mjoClaim'), style: TextStyle(fontSize: 11))),
                OutlinedButton(onPressed: () => _cancelBooking(_rtKey(b)), style: OutlinedButton.styleFrom(foregroundColor: Colors.red), child: Text(tr('mjoCancel'), style: TextStyle(fontSize: 11))),
                OutlinedButton(onPressed: () => Navigator.pushNamed(context, '/nurse-complaint', arguments: {'bookingId': b['bookingId'], 'id': _rtKey(b), 'clientName': b['clientName'], 'clientId': b['clientUid'] ?? b['clientId'], 'nurseName': b['nurseName'], 'nurseId': b['nurseId'], 'service': b['serviceType'] ?? b['service'], 'amount': _nurseCash(b), 'nurseCash': _nurseCash(b)}), child: Text('😡 ${tr('mjoComplaint')}', style: TextStyle(fontSize: 11))),
              ]),
            ]));
          }),
          const SizedBox(height: 20),
        ]),
      ),
    );
  }
}
