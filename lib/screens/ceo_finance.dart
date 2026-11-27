import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/language_service.dart';
import '../services/translations.dart';

/// CEO Finance - Flutter version of ceo-finance.html
/// - Loads: clientsCache from clients + users + customers (by key) — same as HTML loadClientsCache()
///   Payments from bookings + paidBookings + payments + transactions + ceoBookings + acceptedBookings + finance + ceoFinance, dedupe by key (first wins), only paid: paid==true || isPaid==true || paymentStatus paid || status paid || (totalGHS||amount)>0, only amountGHS>0 — same as HTML loadFinance()
/// - NEW 20/80 RULE: Client pays ONLY 20% CEO fee in app to book. Nurse cash 80% is paid CASH by client to nurse AFTER work.
///   CEO NEVER pays nurse. CEO keeps ONLY 20%. 50% DELETED - no 50% Payment anywhere.
/// - normalizePayment: totalGHS (totalAmount || total || ceoFee*5 || amount), ceoFeeGHS (ceoFee || total*0.20), nurseCashGHS (nurseCash || total*0.80),
///   amountGHS = CEO KEPT (ceoFee) - this is CEO earnings, NOT total. amountUSD = ceoFee/15.5.
///   refundDueGHS = (status rejected_by_nurse + refundCeoFee==true + refund not yet paid) ? ceoFee : 0
/// - Stats: CEO Kept Total (sum ceoFee), Total Booking Value (sum total), Nurse Cash To Collect (sum nurseCash), Refund Due Total, Success count, unique clients, top client.
/// - Table: Time, client + CEO Kept + Total + Nurse Cash, phone + email + location, nurse + service, badge 20% CEO Fee + Paid + REFUND DUE if any, id + transactionId, View Full Details
/// - Details: FULL CLIENT DETAILS + MONEY BREAKDOWN: Total / CEO 20% / Nurse 80% Cash / Refund Due + Mark Refund Paid button
/// - Filter: All / Today / This Month / Refund Due
/// - Export CSV: includes Total, CEO 20%, Nurse 80%, Refund Due
/// - Refresh every 15s
/// - NO alert buttons — only Sound Settings.

class CEOFinanceScreen extends StatefulWidget {
  const CEOFinanceScreen({super.key});
  @override
  State<CEOFinanceScreen> createState() => _CEOFinanceScreenState();
}

class _CEOFinanceScreenState extends State<CEOFinanceScreen> {
  List<Map> allPayments = [];
  Map<String, Map> clientsCache = {};
  String search = '';
  String filter = 'all'; // all / today / this_month / refund_due
  Timer? _timer;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadFinance();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => _loadFinance());
  }

  @override
  void dispose() { _timer?.cancel(); super.dispose(); }

  void _toast(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  String _fmtGHS(dynamic v) => 'GH₵ ${(double.tryParse(v.toString()) ?? 0).toStringAsFixed(2)}';
  String _fmtUSD(dynamic v) => '\$${(double.tryParse(v.toString()) ?? 0).toStringAsFixed(2)}';
  String _fmtTime(dynamic t) {
    if (t == null) return '';
    try { return DateTime.fromMillisecondsSinceEpoch((t as num).toInt()).toString(); } catch (_) { return t.toString(); }
  }
  bool _isToday(dynamic t) { if (t == null) return false; try { final d = DateTime.fromMillisecondsSinceEpoch((t as num).toInt()); final n = DateTime.now(); return d.year == n.year && d.month == n.month && d.day == n.day; } catch (_) { return false; } }
  bool _isThisMonth(dynamic t) { if (t == null) return false; try { final d = DateTime.fromMillisecondsSinceEpoch((t as num).toInt()); final n = DateTime.now(); return d.year == n.year && d.month == n.month; } catch (_) { return false; } }
  double _num(dynamic v) => double.tryParse(v.toString()) ?? 0;

  Map _normalize(String id, Map v, Map ce) {
    // ---- NEW 20/80 MATH ----
    // New bookings: ceoFee + totalAmount + nurseCash all saved by book_nurse.dart
    // Old bookings: only amount / totalGHS (full total) saved -> derive 20/80
    final double ceoRaw = _num(v['ceoFee'] ?? v['ceoFeeGHS'] ?? v['amountPaidNow'] ?? v['payNow'] ?? 0);
    final double nurseRaw = _num(v['nurseCash'] ?? v['nurseCashAmount'] ?? v['amountYouWillCollectCash'] ?? 0);
    final double totalRaw = _num(v['totalAmount'] ?? v['total'] ?? v['totalGHS'] ?? v['amountGHS'] ?? v['amount'] ?? 0);
    double totalGHS = totalRaw;
    double ceoFeeGHS = ceoRaw;
    double nurseCashGHS = nurseRaw;
    if (totalGHS <= 0 && ceoFeeGHS > 0) totalGHS = ceoFeeGHS * 5;
    if (totalGHS <= 0 && nurseCashGHS > 0) totalGHS = nurseCashGHS / 0.80;
    if (ceoFeeGHS <= 0 && totalGHS > 0) ceoFeeGHS = totalGHS * 0.20;
    if (nurseCashGHS <= 0 && totalGHS > 0) nurseCashGHS = totalGHS * 0.80;
    // amountGHS in this screen = CEO KEPT (20%), NOT total. Keep amountGHS name so old stats code still works, but value is CEO kept.
    final amountGHS = ceoFeeGHS;
    final amountUSD = _num(v['totalUSD'] ?? v['amountUSD'] ?? (amountGHS / 15.5));
    // 50% DELETED - every booking is now 20% CEO Fee
    const bookingType = '20% CEO Fee';
    final rawStatus = (v['paymentStatus'] ?? v['status'] ?? 'paid').toString().toLowerCase();
    final status = rawStatus.contains('paid') || amountGHS > 0 || rawStatus.contains('reject') || rawStatus.contains('cancel') ? 'paid' : 'pending';
    final isRejected = rawStatus.contains('reject');
    final refundPaid = v['refundPaid'] == true || v['refundStatus'] == 'refund_paid' || v['refundStatus'] == 'refunded';
    final refundDueGHS = (isRejected && (v['refundCeoFee'] == true || v['refundStatus'] == 'refund_due_full_20') && !refundPaid) ? ceoFeeGHS : 0.0;
    return {'id': id, 'transactionId': v['transactionId'] ?? v['paymentId'] ?? id, 'clientName': v['clientName'] ?? ce['fullName'] ?? 'Client', 'clientPhone': v['clientPhone'] ?? ce['phone'] ?? '', 'clientEmail': v['clientEmail'] ?? ce['email'] ?? '', 'clientLocation': v['clientLocation'] ?? ce['location'] ?? 'Accra, Ghana', 'clientAddress': v['clientAddress'] ?? ce['address'] ?? v['clientLocation'] ?? '', 'clientPhoto': v['clientPhoto'] ?? ce['photo'] ?? '', 'clientId': v['clientId'] ?? ce['id'] ?? '', 'nurseName': v['nurseName'] ?? 'Nurse', 'nursePhone': v['nursePhone'] ?? '', 'nurseId': v['nurseId'] ?? '', 'amountGHS': amountGHS, 'ceoFeeGHS': ceoFeeGHS, 'totalGHS': totalGHS, 'nurseCashGHS': nurseCashGHS, 'refundDueGHS': refundDueGHS, 'refundPaid': refundPaid, 'rawStatus': rawStatus, 'amountUSD': amountUSD, 'service': v['service'] ?? v['serviceType'] ?? 'Nursing Care', 'hours': v['hours'] ?? '8', 'bookingType': bookingType, 'status': status, 'paymentMethod': v['paymentMethod'] ?? 'Paystack / Mobile Money', 'paidAt': v['paidAt'] ?? v['createdAt'] ?? v['time'] ?? DateTime.now().millisecondsSinceEpoch, 'raw': v};
  }

  Future<void> _loadFinance() async {
    for (final path in ['clients', 'users', 'customers']) {
      try { final snap = await FirebaseDatabase.instance.ref(path).get(); if (snap.exists) (snap.value as Map).forEach((k, val) { if (val is Map) clientsCache[k.toString()] = Map<String, dynamic>.from(val); }); } catch (_) {}
    }
    Map<String, Map> paymentMap = {};
    for (final path in ['bookings', 'paidBookings', 'payments', 'transactions', 'ceoBookings', 'acceptedBookings', 'finance', 'ceoFinance']) {
      try {
        final snap = await FirebaseDatabase.instance.ref(path).get();
        if (!snap.exists) continue;
        (snap.value as Map).forEach((k, val) {
          if (val is! Map) return;
          final v = Map<String, dynamic>.from(val);
          final hasAmount = _num(v['totalGHS'] ?? v['totalAmount'] ?? v['ceoFee'] ?? v['amount'] ?? 0) > 0;
          final isPaid = v['paid'] == true || v['isPaid'] == true || v['paymentStatus'] == 'paid' || v['status'] == 'paid' || hasAmount || '${v['status']}'.contains('reject') || '${v['status']}'.contains('cancel');
          if (!isPaid && !hasAmount) return;
          if (!paymentMap.containsKey(k)) paymentMap[k.toString()] = v;
        });
      } catch (_) {}
    }
    final list = paymentMap.entries.map((e) => _normalize(e.key, e.value, clientsCache[e.value['clientId']?.toString() ?? ''] ?? {})).where((p) => (p['ceoFeeGHS'] as double) > 0 || (p['totalGHS'] as double) > 0).toList();
    list.sort((a, b) => ((b['paidAt'] ?? 0) as num).compareTo((a['paidAt'] ?? 0) as num));
    setState(() => allPayments = list);
    final ceoTotal = list.fold<double>(0, (s, p) => s + (p['ceoFeeGHS'] as double));
    final refundTotal = list.fold<double>(0, (s, p) => s + (p['refundDueGHS'] as double));
    _toast("${tr('ceoFinance')}: ${list.length} ${tr('bookingsWord')} — ${tr('ceoKept20')} ${_fmtGHS(ceoTotal)} — ${tr('refundDue')} ${_fmtGHS(refundTotal)}");
  }

  List<Map> get filtered {
    var list = List<Map>.from(allPayments);
    if (filter == 'today') list = list.where((p) => _isToday(p['paidAt'])).toList();
    if (filter == 'this_month') list = list.where((p) => _isThisMonth(p['paidAt'])).toList();
    if (filter == 'refund_due') list = list.where((p) => (p['refundDueGHS'] as double) > 0).toList();
    if (search.isNotEmpty) list = list.where((p) => '${p['clientName']} ${p['clientPhone']} ${p['clientEmail']} ${p['clientLocation']} ${p['nurseName']} ${p['id']} ${p['service']} ${p['ceoFeeGHS']} ${p['totalGHS']}'.toLowerCase().contains(search)).toList();
    return list;
  }

  Future<void> _markRefundPaid(Map p) async {
    final confirm = await showDialog<bool>(context: context, builder: (_) => AlertDialog(title: Text(tr('markRefundPaidQ')), content: Text('${tr('confirmRefunded')} ${p['clientName']} ${tr('full20')} ${_fmtGHS(p['refundDueGHS'])} ${tr('viaPaystackMoMo')}'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('notYet'))), ElevatedButton(onPressed: () => Navigator.pop(context, true), child: Text(tr('yesRefunded')))]));
    if (confirm != true) return;
    final id = p['id'].toString();
    final now = DateTime.now().millisecondsSinceEpoch;
    try {
      await FirebaseDatabase.instance.ref('bookings/$id').update({'refundPaid': true, 'refundStatus': 'refund_paid', 'refundPaidAt': now, 'refundAmount': p['refundDueGHS']});
    } catch (_) {}
    _toast('${tr('refundMarkedPaid')} ${_fmtGHS(p['refundDueGHS'])}');
    _loadFinance();
  }

  void _viewClientDetails(Map p) {
    final refundDue = (p['refundDueGHS'] as double) > 0;
    showDialog(context: context, builder: (_) => AlertDialog(
      title: Text('👤 ${p['clientName']} — ${tr('clientWhoPaid')}'),
      content: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${tr('paidLabel')} ${_fmtGHS(p['ceoFeeGHS'])} ${tr('onLabel')} ${_fmtTime(p['paidAt'])} • ${p['bookingType']}', style: const TextStyle(fontSize: 12, color: Colors.white60)),
        const SizedBox(height: 8),
        Chip(label: Text('✅ ${tr('paidSuccessCeoKept')} ${_fmtGHS(p['ceoFeeGHS'])}', style: const TextStyle(fontSize: 11)), backgroundColor: Colors.green.withOpacity(0.2)),
        if (refundDue) Padding(padding: const EdgeInsets.only(top: 8), child: Chip(label: Text('🔴 ${tr('refundDueLabel')} — ${_fmtGHS(p['refundDueGHS'])} (${tr('nurseRejected')})', style: const TextStyle(fontSize: 11, color: Colors.white)), backgroundColor: Colors.red)),
        const SizedBox(height: 12),
        Text(tr('moneyBreakdown2080'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFFFACC15))),
        const SizedBox(height: 8),
        _detail(tr('totalBookingValue'), _fmtGHS(p['totalGHS'])),
        _detail(tr('ceoKept20YourMoney'), _fmtGHS(p['ceoFeeGHS'])),
        _detail(tr('nurseCash80ClientPays'), _fmtGHS(p['nurseCashGHS'])),
        _detail(tr('refundDueToClient'), refundDue ? _fmtGHS(p['refundDueGHS']) : tr('noRefund')),
        _detail(tr('amountPaidCeoFeeOnly'), '${_fmtGHS(p['ceoFeeGHS'])} / ${_fmtUSD(p['amountUSD'])}\n✅ ${tr('clientPaidSuccessfully')} ${p['transactionId']}'),
        const SizedBox(height: 12),
        Text(tr('fullClientDetails')), style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFFFACC15))),
        const SizedBox(height: 8),
        _detail(tr('clientFullNameWhoPaid'), p['clientName']),
        _detail(tr('clientIdLabel'), p['clientId'].toString().isEmpty ? p['id'] : p['clientId']),
        _detail(tr('phoneClientContact'), p['clientPhone'].toString().isEmpty ? tr('noPhone') : p['clientPhone']),
        _detail(tr('emailClientEmail'), p['clientEmail'].toString().isEmpty ? tr('noEmail') : p['clientEmail']),
        _detail(tr('locationWhereClientLives'), p['clientLocation']),
        _detail(tr('fullAddress'), p['clientAddress']),
        const SizedBox(height: 12),
        Text(tr('nurseServiceHeading')), style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFFA78BFA))),
        _detail(tr('nurseAssigned'), p['nurseName']),
        _detail(tr('serviceLabel'), '${p['service']} • ${p['hours']}h'),
      ])),
      actions: [
        if (refundDue) ElevatedButton(onPressed: () { Navigator.pop(context); _markRefundPaid(p); }, style: ElevatedButton.styleFrom(backgroundColor: Colors.red), child: Text(tr('markRefundPaid'))),
        if (p['clientPhone'].toString().isNotEmpty) TextButton(onPressed: () => launchUrl(Uri.parse('tel:${p['clientPhone']}')), child: Text(tr('callClient'))),
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('close'))),
      ],
    ));
  }

  Widget _detail(String label, String value) => Padding(padding: const EdgeInsets.only(bottom: 8), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: const TextStyle(fontSize: 10, color: Colors.white60)), Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold))]));

  void _exportCSV() {
    final list = filtered;
    if (list.isEmpty) { _toast(tr('noClientsToExport')); return; }
    var csv = 'Date Paid,Client Name,Client Phone,Client Email,Client Location,Client Address,Nurse Name,Total Booking GHS,CEO Kept 20% GHS,Nurse Cash 80% GHS,Refund Due GHS,Amount USD,Type,Service,Hours,Status,Booking ID,Transaction ID\n';
    for (final p in list) csv += '"${_fmtTime(p['paidAt'])}","${p['clientName']}","${p['clientPhone']}","${p['clientEmail']}","${p['clientLocation']}","${p['clientAddress']}","${p['nurseName']}",${p['totalGHS']},${p['ceoFeeGHS']},${p['nurseCashGHS']},${p['refundDueGHS']},${p['amountUSD']},"${p['bookingType']}","${p['service']}","${p['hours']}","${p['status']}","${p['id']}","${p['transactionId']}"\n';
    showDialog(context: context, builder: (_) => AlertDialog(
      title: Text('📊 ${tr('exportedClients')} ${list.length} ${tr('clientsWithDetails')}'),
      content: SingleChildScrollView(child: Text('${tr('filenameLabel')}: ceo-finance-client-details-${DateTime.now().toIso8601String().substring(0, 10)}.csv\n\n$csv', style: const TextStyle(fontSize: 10))),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('close')))],
    ));
    _toast('📊 ${tr('exportedClients')} ${list.length} ${tr('clientsWithDetails')}');
  }

  @override
  Widget build(BuildContext context) {
    final ceoTotal = allPayments.fold<double>(0, (s, p) => s + (p['ceoFeeGHS'] as double));
    final totalBookingValue = allPayments.fold<double>(0, (s, p) => s + (p['totalGHS'] as double));
    final nurseCashTotal = allPayments.fold<double>(0, (s, p) => s + (p['nurseCashGHS'] as double));
    final refundDueTotal = allPayments.fold<double>(0, (s, p) => s + (p['refundDueGHS'] as double));
    final refundCount = allPayments.where((p) => (p['refundDueGHS'] as double) > 0).length;
    final totalUSD = allPayments.fold<double>(0, (s, p) => s + (p['amountUSD'] as double));
    final successCount = allPayments.where((p) => p['status'] == 'paid').length;
    final uniqueClients = allPayments.map((p) => p['clientName']).toSet().length;
    Map<String, Map> clientTotals = {};
    for (final p in allPayments) {
      clientTotals.putIfAbsent(p['clientName'], () => {'total': 0.0, 'count': 0, 'phone': p['clientPhone'], 'email': p['clientEmail']});
      clientTotals[p['clientName']]!['total'] = (clientTotals[p['clientName']]!['total'] as double) + (p['ceoFeeGHS'] as double);
      clientTotals[p['clientName']]!['count'] = (clientTotals[p['clientName']]!['count'] as int) + 1;
    }
    final topClient = clientTotals.entries.isNotEmpty ? (clientTotals.entries.toList()..sort((a, b) => (b.value['total'] as double).compareTo(a.value['total'] as double))).first : null;
    final list = filtered;
    final totalFilteredCeo = list.fold<double>(0, (s, p) => s + (p['ceoFeeGHS'] as double));
    final recent = allPayments.take(10).toList();
    return Scaffold(
      backgroundColor: const Color(0xFF0C0A1E),
      appBar: AppBar(title: Text(tr('ceoFinance'), style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)), backgroundColor: const Color(0xFF1A1633), actions: [Center(child: Padding(padding: const EdgeInsets.only(right: 8), child: Text('${allPayments.length} ${tr('bookingsWordCap')} | ${tr('ceoKept20')} ${_fmtGHS(ceoTotal)} | ${tr('refundDue')} ${_fmtGHS(refundDueTotal)}', style: const TextStyle(fontSize: 10, color: Colors.white60)))), DropdownButtonHideUnderline(child: DropdownButton<String>(value: LanguageService.instance.locale.languageCode, dropdownColor: const Color(0xFF1A1633), icon: const Icon(Icons.language, color: Colors.white, size: 20), items: LanguageService.languageNames.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, style: const TextStyle(color: Colors.white)))).toList(), onChanged: (v) { if (v != null) LanguageService.instance.setLanguage(v); })),
          IconButton(icon: const Icon(Icons.volume_up), onPressed: () => Navigator.pushNamed(context, '/sound-settings'))]),
      body: Column(children: [
        // NEW 20/80 BANNER
        Container(width: double.infinity, margin: const EdgeInsets.fromLTRB(12, 12, 12, 0), padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: const Color(0xFF22C55E).withOpacity(0.12), borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFF22C55E).withOpacity(0.4))), child: Text(tr('financeBanner2080'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
        Padding(padding: const EdgeInsets.all(12), child: Wrap(spacing: 8, runSpacing: 8, children: [
          _stat(tr('statCeoKept'), _fmtGHS(ceoTotal), '$successCount ${tr('bookingsPaid')} • ${allPayments.length} ${tr('transactions')} • $uniqueClients ${tr('uniqueClients')} • LIVE'),
          _stat(tr('statTotalBookingValue'), _fmtGHS(totalBookingValue), tr('statTotalBookingSub')),
          _stat(tr('statNurseCash'), _fmtGHS(nurseCashTotal), tr('statNurseCashSub')),
          _stat(tr('statRefundDue'), _fmtGHS(refundDueTotal), '$refundCount ${tr('refundsDueTapBooking')}'),
          _stat(tr('statTotalUsd'), _fmtUSD(totalUSD), tr('statTotalUsdSub')),
          if (topClient != null) _stat(tr('statTopClient'), '${topClient.key} — ${_fmtGHS(topClient.value['total'])}', '${tr('topClientByCeoFee')} • ${topClient.value['count']} ${tr('payments')} • ${tr('phoneLabel')}: ${topClient.value['phone'] ?? ''} • ${tr('fullDetailsLive')}'),
        ])),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Row(children: [
          Expanded(child: TextField(controller: _searchCtrl, decoration: InputDecoration(hintText: tr('searchFinanceHint'), border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8)), onChanged: (v) => setState(() => search = v.toLowerCase().trim()))),
          const SizedBox(width: 8),
          ElevatedButton(onPressed: _exportCSV, child: Text(tr('exportCsv'))),
        ])),
        Padding(padding: const EdgeInsets.all(12), child: Row(children: [
          _filterChip('all', tr('all')), _filterChip('today', tr('today')), _filterChip('this_month', tr('thisMonth')), _filterChip('refund_due', '${tr('refundDue')} ($refundCount)'),
          const Spacer(),
          Text('${list.length} ${tr('bookingsWord')} • ${tr('ceoKept20')} ${_fmtGHS(totalFilteredCeo)}', style: const TextStyle(fontSize: 11, color: Colors.white60)),
        ])),
        Expanded(child: list.isEmpty ? Center(child: Text(tr('noClientsWhoPaid'), style: TextStyle(color: Colors.white60))) : ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 12), itemCount: list.length, itemBuilder: (_, i) {
          final p = list[i];
          final refundDue = (p['refundDueGHS'] as double) > 0;
          return InkWell(onTap: () => _viewClientDetails(p), child: Container(margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: const Color(0xFF1A1633), borderRadius: BorderRadius.circular(14), border: refundDue ? Border.all(color: Colors.red, width: 1.5) : null), child: Row(children: [
            CircleAvatar(child: Text((p['clientName'] as String).isNotEmpty ? (p['clientName'] as String)[0].toUpperCase() : 'C')),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_fmtTime(p['paidAt']), style: const TextStyle(fontSize: 11, color: Colors.white60)),
              Text('👤 ${p['clientName']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              Text('💰 ${tr('ceoKept20')} ${_fmtGHS(p['ceoFeeGHS'])} • ${tr('totalLabel')} ${_fmtGHS(p['totalGHS'])} • ${tr('nurseCashLabel')} ${_fmtGHS(p['nurseCashGHS'])}', style: const TextStyle(fontSize: 10, color: Color(0xFFFACC15))),
              if (refundDue) Text('🔴 ${tr('refundDueLabel')}: ${_fmtGHS(p['refundDueGHS'])} - ${tr('nurseRejected')}', style: const TextStyle(fontSize: 11, color: Colors.red, fontWeight: FontWeight.bold)),
              Text('📱 ${p['clientPhone'].toString().isEmpty ? tr('noPhone') : p['clientPhone']} • ✉️ ${p['clientEmail'].toString().isEmpty ? tr('noEmail') : p['clientEmail']} • 📍 ${p['clientLocation']}', style: const TextStyle(fontSize: 11, color: Colors.white60)),
              Text('👩‍⚕️ ${p['nurseName']} • ${p['service']} • ${p['hours']}h • ${p['paymentMethod']}', style: const TextStyle(fontSize: 11, color: Colors.white60)),
            ])),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(_fmtGHS(p['ceoFeeGHS']), style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFFACC15))),
              Text(_fmtUSD(p['amountUSD']), style: const TextStyle(fontSize: 10, color: Colors.white60)),
              Chip(label: Text(tr('ceoFee20'), style: TextStyle(fontSize: 10)), backgroundColor: Colors.green.withOpacity(0.2)),
              Chip(label: Text('✅ ${tr('paidLabel')}', style: TextStyle(fontSize: 10)), backgroundColor: Colors.green),
              if (refundDue) Chip(label: Text(tr('refundDueLabel'), style: TextStyle(fontSize: 10, color: Colors.white)), backgroundColor: Colors.red),
              Text('📋 ${(p['id'] as String).length > 10 ? (p['id'] as String).substring(0, 10) : p['id']}', style: const TextStyle(fontSize: 10, color: Colors.white60)),
            ]),
          ])));
        })),
        Container(width: double.infinity, padding: const EdgeInsets.all(12), decoration: const BoxDecoration(color: Color(0xFF1A1633)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('🕐 ${tr('recentLabel')} — ${recent.length} ${tr('recentClients')}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
          const SizedBox(height: 6),
          ...recent.map((p) => InkWell(onTap: () => _viewClientDetails(p), child: Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('👤 ${p['clientName']} — ${tr('ceoKept20')} ${_fmtGHS(p['ceoFeeGHS'])} • ${tr('totalLabel')} ${_fmtGHS(p['totalGHS'])} • ${_fmtTime(p['paidAt'])}', style: const TextStyle(fontSize: 11, color: Colors.white60))))).toList(),
        ])),
      ]),
    );
  }

  Widget _stat(String label, String value, String sub) => Container(width: 200, padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: const Color(0xFF1A1633), borderRadius: BorderRadius.circular(14)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: const TextStyle(color: Colors.white60, fontSize: 11)), Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)), Text(sub, style: const TextStyle(fontSize: 10, color: Colors.white60))]));
  Widget _filterChip(String key, String label) => Padding(padding: const EdgeInsets.only(right: 6), child: ChoiceChip(label: Text(label, style: const TextStyle(fontSize: 11)), selected: filter == key, onSelected: (_) => setState(() => filter = key)));
}
