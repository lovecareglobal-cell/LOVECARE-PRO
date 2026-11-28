import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/language_service.dart';
import '../services/translations.dart';

/// Increase Payment - Flutter version of increase-payment.html
/// Nurse rejected your offer -> Add EXTRA money to convince nurse to accept SAME booking
/// You only pay the EXTRA now via Paystack - NOT full amount again
/// Paystack Key: pk_live_f17ae09bf855010825cbfccdda8e724553ab747b (same as HTML)
/// On success: bookings/{key} -> amount=newTotal, status=pending, rejected fields cleared
/// + paymentIncreases/{key}.push(...) + clientPayments/{clientKey} totalPaid += extra

class IncreasePaymentScreen extends StatefulWidget {
  final String? bookingKey;
  const IncreasePaymentScreen({super.key, this.bookingKey});
  @override
  State<IncreasePaymentScreen> createState() => _IncreasePaymentScreenState();
}

class _IncreasePaymentScreenState extends State<IncreasePaymentScreen> {
  Map? booking;
  double currentAmount = 0;
  double alreadyPaid = 0;
  double extra = 0;
  final _extraCtrl = TextEditingController();
  bool isPaying = false;
  String statusMsg = '';
  static const paystackKey = 'pk_live_f17ae09bf855010825cbfccdda8e724553ab747b';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Booking key from route args if not passed in constructor
    final args = ModalRoute.of(context)?.settings.arguments;
    String? key = widget.bookingKey;
    if (key == null && args is Map && args['bookingKey'] != null) key = args['bookingKey'].toString();
    if (key == null && args is String) key = args;
    if (key != null && booking == null) _loadBooking(key);
  }

  String money(double v) => 'GHS ${v.toStringAsFixed(2)}';

  Future<void> _loadBooking(String bookingKey) async {
    try {
      final snap = await FirebaseDatabase.instance.ref('bookings/$bookingKey').get();
      if (!snap.exists) {
        setState(() => statusMsg = '${tr('ipBookingNotFound1')} $bookingKey ${tr('ipBookingNotFound2')}');
        return;
      }
      final b = Map<String, dynamic>.from(snap.value as Map);
      b['id'] = bookingKey;
      setState(() {
        booking = b;
        currentAmount = double.tryParse(b['amount'].toString()) ?? 0;
        alreadyPaid = double.tryParse((b['totalPaid'] ?? b['totalPayments'] ?? b['amountPaid'] ?? b['amount'] ?? 0).toString()) ?? 0;
      });
    } catch (e) {
      setState(() => statusMsg = '${tr('ipLoadFailed')}: $e');
    }
  }

  void _setExtra(double v) {
    setState(() {
      extra = v;
      _extraCtrl.text = v.toInt().toString();
    });
  }

  double get newTotal => currentAmount + extra;
  double get totalPaid => alreadyPaid + extra;
  double get nurseShare => (newTotal * 0.8).roundToDouble();
  double get ceoShare => (newTotal * 0.2).roundToDouble();

  Future<void> _payExtra() async {
    if (booking == null) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('ipBookingNotLoaded')))); return; }
    if (extra <= 0) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('ipEnterExtra')))); return; }
    final bookingKey = booking!['id'];
    final prefs = await SharedPreferences.getInstance();
    final email = booking!['clientEmail'] ?? booking!['email'] ?? prefs.getString('clientEmail') ?? prefs.getString('email') ?? 'client@lovecareglobal.com';
    setState(() => isPaying = true);
    try {
      // TODO: Replace with flutter_paystack_plus using paystackKey, email, amount = extra*100, ref = LCG-INC-bookingKey-timestamp
      // For now: confirm dialog simulates Paystack callback
      final confirmed = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
        title: Text(tr('ipPaystackPayExtra')),
        content: Text('${tr('ipPayExtraQ')} ${money(extra)} ${tr('ipViaPaystackQ')}\n${tr('ipEmailLabel')}: $email\n${tr('ipRefLabel')}: LCG-INC-$bookingKey-${DateTime.now().millisecondsSinceEpoch}\n${tr('ipNewTotalLabel')}: ${money(newTotal)}'),
        actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('ipCancel'))), ElevatedButton(onPressed: () => Navigator.pop(context, true), child: Text(tr('ipPayNow')))],
      ));
      if (confirmed != true) { setState(() => isPaying = false); return; }
      final ref = 'LCG-INC-$bookingKey-${DateTime.now().millisecondsSinceEpoch}';
      await _onPaymentSuccess(ref);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${tr('ipPaymentSucceededButUpdateFailed')}: $e - ${tr('ipShowRefToCeo')}')));
    } finally {
      if (mounted) setState(() => isPaying = false);
    }
  }

  Future<void> _onPaymentSuccess(String ref) async {
    final bookingKey = booking!['id'];
    final now = DateTime.now().millisecondsSinceEpoch;
    final nowStr = DateTime.now().toString();
    final prefs = await SharedPreferences.getInstance();
    final clientKey = (booking!['clientId'] ?? booking!['clientUid'] ?? booking!['clientPhone'] ?? prefs.getString('lcg_client_uid') ?? prefs.getString('clientPhone') ?? '').toString();
    final updates = {
      'previousAmount': currentAmount,
      'amount': newTotal,
      'totalPaid': totalPaid,
      'totalPayments': totalPaid,
      'amountPaid': totalPaid,
      'extraPaid': extra,
      'lastExtraPaid': extra,
      'lastIncreaseRef': ref,
      'paymentIncreased': true,
      'increasedAt': now,
      'increasedAtStr': nowStr,
      'status': 'pending',
      'rejectedAt': null,
      'rejectedBy': null,
      'rejectedByNurseName': null,
      'rejectedByNurseId': null,
      'nurse80': nurseShare.round(),
      'ceo20': ceoShare.round(),
    };
    await FirebaseDatabase.instance.ref('bookings/$bookingKey').update(updates);
    await FirebaseDatabase.instance.ref('paymentIncreases/$bookingKey').push().set({
      'bookingId': booking!['bookingId'] ?? bookingKey, 'bookingKey': bookingKey,
      'previousAmount': currentAmount, 'extraPaid': extra, 'newTotal': newTotal, 'totalPaid': totalPaid,
      'paystackRef': ref, 'clientName': booking!['clientName'] ?? '', 'nurseName': booking!['nurseName'] ?? '',
      'createdAt': now, 'createdAtStr': nowStr,
    });
    await FirebaseDatabase.instance.ref('ceoBookingsProgress/$bookingKey').remove().catchError((_) {});
    if (clientKey.isNotEmpty) {
      final csnap = await FirebaseDatabase.instance.ref('clientPayments/$clientKey').get();
      final cur = csnap.exists ? (double.tryParse((csnap.value as Map)['totalPaid'].toString()) ?? 0) : 0;
      await FirebaseDatabase.instance.ref('clientPayments/$clientKey').update({'totalPaid': cur + extra, 'lastBookingId': booking!['bookingId'] ?? bookingKey, 'lastIncrease': extra, 'updatedAt': now, 'updatedAtStr': nowStr});
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${tr('ipSuccessExtra')} ${money(extra)} ${tr('ipSuccessPaid')} ${money(newTotal)} - ${tr('ipSuccessBackToPending')}')));
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) Navigator.pushNamed(context, '/my-bookings', arguments: {'increased': bookingKey});
    });
  }

  @override
  Widget build(BuildContext context) {
    final bookingKey = booking?['id'] ?? widget.bookingKey ?? '-';
    return Scaffold(
      backgroundColor: const Color(0xFF0E0A1C),
      appBar: AppBar(title: Text(tr('ipTitle')), backgroundColor: const Color(0xFF1A1633), actions: [DropdownButtonHideUnderline(child: DropdownButton<String>(value: LanguageService.instance.locale.languageCode, dropdownColor: const Color(0xFF0C0A1E), icon: const Icon(Icons.language, color: Colors.white, size: 24), items: LanguageService.languageNames.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, style: const TextStyle(color: Colors.black)))).toList(), onChanged: (v) { if (v != null) LanguageService.instance.setLanguage(v); })), TextButton(onPressed: () => Navigator.pushNamed(context, '/my-bookings'), child: Text(tr('ipBack'), style: TextStyle(color: Color(0xFFD8B4FE))))]),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(children: [
          Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: Colors.red.withOpacity(0.1), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.red.withOpacity(0.3))), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(tr('ipNurseRejected'), style: TextStyle(color: Color(0xFFFCA5A5), fontWeight: FontWeight.bold)), SizedBox(height: 4), Text(tr('ipAddExtraBody'), style: TextStyle(fontSize: 12))])),
          const SizedBox(height: 12),
          Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: const Color(0xFF1C1238), borderRadius: BorderRadius.circular(20)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr('ipBookingDetails'), style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (booking == null) Text(statusMsg.isNotEmpty ? statusMsg : tr('ipLoadingBooking')),
            if (booking != null) ...[
              Text('${tr('ipBookingId')} ${booking!['bookingId'] ?? bookingKey}', style: const TextStyle(fontWeight: FontWeight.bold)),
              Text('${tr('ipNurseLabel')}: ${booking!['rejectedByNurseName'] ?? booking!['nurseName'] ?? tr('ipAnyNurse')} - ${booking!['nursePhone'] ?? ''}'),
              Text('${tr('ipServiceLabel')}: ${booking!['serviceType'] ?? ''}'),
              Text('${tr('ipLocationLabel')}: ${booking!['location'] ?? ''}'),
              Text('${tr('ipStatusLabel')}: ${booking!['status'] ?? ''}'),
              Text('${tr('ipAlreadyPaid')}: ${money(alreadyPaid)}'),
            ],
          ])),
          const SizedBox(height: 12),
          Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: const Color(0xFF1C1238), borderRadius: BorderRadius.circular(20)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr('ipExtraAmountTitle'), style: TextStyle(color: Color(0xFFD8B4FE), fontSize: 11, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextField(controller: _extraCtrl, keyboardType: TextInputType.number, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold), decoration: InputDecoration(hintText: tr('ipExtraHint'), border: OutlineInputBorder()), onChanged: (v) => setState(() => extra = double.tryParse(v) ?? 0)),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [10, 20, 50, 100].map((v) => ChoiceChip(label: Text('+ GHS $v'), selected: extra == v.toDouble(), onSelected: (_) => _setExtra(v.toDouble()), selectedColor: const Color(0xFFFACC15), labelStyle: TextStyle(color: extra == v.toDouble() ? Colors.black : Colors.white))).toList()),
            const SizedBox(height: 8),
            Text(tr('ipMustBeMore'), style: TextStyle(color: Color(0xFFFCA5A5), fontSize: 11)),
          ])),
          const SizedBox(height: 12),
          Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: const Color(0xFF1C1238), borderRadius: BorderRadius.circular(20)), child: Column(children: [
            Text(tr('ipSummary'), style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            _row(tr('ipCurrentAmount'), money(currentAmount)),
            _row(tr('ipExtraYouWillPay'), money(extra), color: const Color(0xFFFACC15)),
            _row(tr('ipNewTotalBooking'), money(newTotal), color: const Color(0xFF86EFAC)),
            _row(tr('ipNurseGets'), money(nurseShare)),
            _row(tr('ipCeoGets'), money(ceoShare)),
            _row(tr('ipTotalYouHavePaid'), money(totalPaid)),
          ])),
          const SizedBox(height: 12),
          SizedBox(width: double.infinity, child: ElevatedButton(onPressed: isPaying ? null : _payExtra, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2563EB), padding: const EdgeInsets.symmetric(vertical: 14)), child: Text(isPaying ? tr('ipOpeningPaystack') : '${tr('ipPayExtraBtn')} ${money(extra)} ${tr('ipViaPaystackBtn')}', style: const TextStyle(fontWeight: FontWeight.bold)))),
          const SizedBox(height: 10),
          SizedBox(width: double.infinity, child: OutlinedButton(onPressed: () => Navigator.pushNamed(context, '/my-bookings'), child: Text(tr('ipCancelGoBack')))),
          const SizedBox(height: 10),
          Text('${tr('ipSecurePayment')} ${tr('ipBookingId')}: $bookingKey', style: const TextStyle(color: Color(0xFFD8B4FE), fontSize: 11)),
        ]),
      ),
    );
  }

  Widget _row(String label, String value, {Color? color}) => Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(label, style: const TextStyle(fontSize: 13)), Text(value, style: TextStyle(fontWeight: FontWeight.bold, color: color ?? Colors.white))]));
}
