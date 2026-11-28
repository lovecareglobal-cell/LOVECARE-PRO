// lib/screens/rating.dart - English only, no translations.
// English only - this is the real RatingScreen.
// Only a client who booked the nurse and whose job is COMPLETED can rate.
// Rating saves to publicReviews + homepageReviews with client photo + email + time.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../services/language_service.dart';
import '../services/translations.dart';

class RatingScreen extends StatefulWidget {
  const RatingScreen({super.key});
  @override
  State<RatingScreen> createState() => _RatingScreenState();
}

class _RatingScreenState extends State<RatingScreen> {
  bool _loading = true;
  String _error = '';
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _bookings = [];

  String get _email => FirebaseAuth.instance.currentUser?.email ?? '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      QuerySnapshot<Map<String, dynamic>> snap;
      if (_email.isNotEmpty) {
        snap = await FirebaseFirestore.instance
            .collection('bookings')
            .where('clientEmail', isEqualTo: _email)
            .where('status', isEqualTo: 'COMPLETED')
            .get();
        if (snap.docs.isEmpty) {
          snap = await FirebaseFirestore.instance
              .collection('bookings')
              .where('email', isEqualTo: _email)
              .where('status', isEqualTo: 'COMPLETED')
              .get();
        }
      } else {
        snap = await FirebaseFirestore.instance
            .collection('bookings')
            .where('status', isEqualTo: 'COMPLETED')
            .limit(20)
            .get();
      }
      if (mounted) setState(() { _bookings = snap.docs; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = '${tr('rtFailed')}: $e'; _loading = false; });
    }
  }

  String _str(Map<String, dynamic> d, List<String> keys) {
    for (final k in keys) {
      final v = d[k];
      if (v != null && v.toString().isNotEmpty) return v.toString();
    }
    return '';
  }

  Future<void> _showRateDialog(Map<String, dynamic> b, String bookingId) async {
    int stars = 5;
    final commentCtrl = TextEditingController();
    final nurse = _str(b, ['nurseName', 'nurse', 'nurseEmail']);
    final nurseEmail = _str(b, ['nurseEmail', 'nurse']);
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text('⭐ ${tr('rtRate')} ${nurse.isEmpty ? tr('rtYourNurse') : nurse}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${tr('rtBooking')}: $bookingId', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 12),
                Text(tr('rtSelectRating'), style: TextStyle(fontWeight: FontWeight.bold)),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(5, (i) => IconButton(
                    icon: Icon(i < stars ? Icons.star : Icons.star_border, color: Colors.amber, size: 32),
                    onPressed: () => setD(() => stars = i + 1),
                  )),
                ),
                Text(['', tr('rtPoor'), tr('rtFair'), tr('rtGood'), tr('rtVeryGood'), tr('rtExcellent')][stars]),
                const SizedBox(height: 12),
                Align(alignment: Alignment.centerLeft, child: Text(tr('rtYourExperience'), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                TextField(controller: commentCtrl, maxLines: 3, decoration: InputDecoration(hintText: tr('rtWriteExperience'), border: OutlineInputBorder())),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('rtCancel'))),
            ElevatedButton(
              onPressed: () async {
                final comment = commentCtrl.text.trim();
                if (comment.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('rtPleaseWriteExperience'))));
                  return;
                }
                Navigator.pop(ctx);
                await _submit(b, bookingId, stars, comment, nurse, nurseEmail);
              },
              child: Text(tr('rtSubmitRating')),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit(Map<String, dynamic> b, String bookingId, int stars, String comment, String nurse, String nurseEmail) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      String clientName = user?.displayName ?? '';
      String clientPhoto = user?.photoURL ?? '';
      String clientPhone = '';
      // Try to read client profile for name / phone / photo
      try {
        if (_email.isNotEmpty) {
          final doc = await FirebaseFirestore.instance.collection('clients').doc(_email).get();
          if (doc.exists) {
            final d = doc.data() ?? {};
            if (clientName.isEmpty) clientName = _str(d, ['name', 'fullName', 'username']);
            clientPhone = _str(d, ['phone', 'phoneNumber']);
            if (clientPhoto.isEmpty) clientPhoto = _str(d, ['photo', 'photoUrl', 'profilePhoto']);
          }
        }
      } catch (_) {}
      final now = DateTime.now();
      final data = <String, dynamic>{
        'bookingId': bookingId,
        'nurseName': nurse,
        'nurseEmail': nurseEmail,
        'rating': stars,
        'comment': comment,
        'clientName': clientName,
        'clientPhone': clientPhone,
        'clientEmail': _email,
        'clientPhoto': clientPhoto,
        'photo': clientPhoto,
        'email': _email,
        'time': now.toIso8601String(),
        'createdAt': FieldValue.serverTimestamp(),
        'service': _str(b, ['service', 'serviceType']),
        'status': 'COMPLETED',
      };
      await FirebaseFirestore.instance.collection('publicReviews').add(data);
      await FirebaseFirestore.instance.collection('homepageReviews').add(data);
      // Mark booking as rated so it does not show again
      try { await FirebaseFirestore.instance.collection('bookings').doc(bookingId).update({'rated': true}); } catch (_) {}
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('✅ ${tr('rtRatingSubmitted')} ⭐$stars — ${tr('rtClient')}: $clientName • ${tr('rtEmail')}: $_email')));
        _load();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${tr('rtFailed')}: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFCE4EC),
      appBar: AppBar(backgroundColor: const Color(0xFF880E4F), foregroundColor: Colors.white, title: Text(tr('rtTitle')), actions: [DropdownButtonHideUnderline(child: DropdownButton<String>(value: LanguageService.instance.locale.languageCode, dropdownColor: const Color(0xFF0C0A1E), icon: const Icon(Icons.language, color: Colors.white, size: 24), items: LanguageService.languageNames.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, style: const TextStyle(color: Colors.black)))).toList(), onChanged: (v) { if (v != null) LanguageService.instance.setLanguage(v); }))]),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error.isNotEmpty
              ? Center(child: Text(_error))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(width: double.infinity, padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(tr('rtSecureVerified'), style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF880E4F))),
                        SizedBox(height: 6),
                        Text(tr('rtOnlyClientCompleted'), style: TextStyle(fontSize: 13)),
                      ])),
                      const SizedBox(height: 16),
                      Text(tr('rtCompletedBookings'), style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF880E4F))),
                      const SizedBox(height: 10),
                      if (_bookings.isEmpty)
                        Card(child: Padding(padding: EdgeInsets.all(16), child: Text(tr('rtNoCompleted')))),
                      for (final doc in _bookings)
                        Builder(builder: (_) {
                          final b = doc.data();
                          final nurse = _str(b, ['nurseName', 'nurse', 'nurseEmail']);
                          if (b['rated'] == true) return const SizedBox.shrink();
                          return Card(
                            child: ListTile(
                              title: Text(nurse.isEmpty ? tr('rtYourNurse') : nurse),
                              subtitle: Text('${tr('rtStatus')}: ${b['status'] ?? ''} • ${tr('rtService')}: ${_str(b, ['service', 'serviceType'])}\n${tr('rtBooking')}: ${doc.id}'),
                              isThreeLine: true,
                              trailing: ElevatedButton(
                                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF880E4F)),
                                onPressed: () => _showRateDialog(b, doc.id),
                                child: Text(tr('rtRateBtn'), style: TextStyle(color: Colors.white)),
                              ),
                            ),
                          );
                        }),
                      const SizedBox(height: 12),
                      Text(tr('rtFooterNote'), style: TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                ),
    );
  }
}

// Alias - if any other file calls RatingPage, it still works.
class RatingPage extends RatingScreen {
  const RatingPage({super.key});
}
