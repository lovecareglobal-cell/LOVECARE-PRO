import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import '../services/language_service.dart';
import '../services/translations.dart';

/// Nurse Complaint - Flutter version of nurse-complaint.html
/// - Params: bookingId, clientName, clientId, nurseName, nurseId, service, amount (route args, same as URL ?bookingId=... in HTML)
/// - Complaint Type: abuse / non_payment / unsafe / harassment / false_accusation / overwork / other
/// - Text min 20 chars, confirm dialog, ID NURSE-COMP-{bookingId}-{now}
/// - Evidence: Files (base64) + Audio (base64) + Video (base64) via file_picker — HTML used MediaRecorder, Flutter uses file_picker for audio/video files
/// - Saves to: nurseComplaints/{id} + allComplaints/{id} + ceoComplaints/{id} + complaintsByBooking/{bookingId}/{id}
///   Data: complaintId, bookingId, clientId, clientName, nurseId, nurseName, service, amount, complaintType, complaintText, status pending, createdAt, time, evidenceCount, evidenceFiles, hasAudio, hasVideo, type nurse_complaint, from nurse, to client, reflectsOnCEO true
/// - After: toast + dialog + navigate to /my-job-offers (HTML: my-job-offer.html after 1.5s)
/// - My Work Ethics Notices (Punishment System): searches userNotices / ceoNotices / nurseNotices / notices / noticesByEmail / noticesByPhone for ALL nurse IDs + allNotices where victimType==nurse && victimEmail/phone/id matches
///   + live listener userNotices/{uid} child_added within 60s + unread -> confirm dialog -> open notice
/// - Notice actions: Mark Read (userNotices/{uid}/{id} isRead), Appeal (noticeAppeals/{id} {noticeId, userId, reason, createdAt, status pending})

class NurseComplaintScreen extends StatefulWidget {
  final Map<String, dynamic>? params;
  const NurseComplaintScreen({super.key, this.params});
  @override
  State<NurseComplaintScreen> createState() => _NurseComplaintScreenState();
}

class _NurseComplaintScreenState extends State<NurseComplaintScreen> {
  String bookingId = 'LCG-DEMO', clientName = 'Client', clientId = 'client_demo', nurseName = 'Nurse', nurseId = 'nurse_demo', service = 'Nursing Care', amount = '0';
  String complaintType = '';
  final _textCtrl = TextEditingController();
  List<Map> evidenceFiles = [];
  String? audioBase64, videoBase64;
  List<Map> notices = [];
  bool showNotices = false;
  String checkedIds = '';

  List<Map<String, String>> get types => [
    {'v': 'abuse', 'l': tr('ncTypeAbuse')},
    {'v': 'non_payment', 'l': tr('ncTypeNonPayment')},
    {'v': 'unsafe', 'l': tr('ncTypeUnsafe')},
    {'v': 'harassment', 'l': tr('ncTypeHarassment')},
    {'v': 'false_accusation', 'l': tr('ncTypeFalseAccusation')},
    {'v': 'overwork', 'l': tr('ncTypeOverwork')},
    {'v': 'other', 'l': tr('ncTypeOther')},
  ];

  @override
  void initState() {
    super.initState();
    _loadParams();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map) _applyParams(Map<String, dynamic>.from(args));
  }

  void _loadParams() {
    if (widget.params != null) _applyParams(widget.params!);
    _loadNotices();
    _listenNewNotices();
  }

  void _applyParams(Map p) {
    setState(() {
      bookingId = (p['bookingId'] ?? p['id'] ?? bookingId).toString();
      clientName = (p['clientName'] ?? clientName).toString();
      clientId = (p['clientId'] ?? p['clientUid'] ?? clientId).toString();
      nurseName = (p['nurseName'] ?? nurseName).toString();
      nurseId = (p['nurseId'] ?? p['nurseUid'] ?? nurseId).toString();
      service = (p['service'] ?? p['serviceType'] ?? service).toString();
      amount = (p['amount'] ?? amount).toString();
    });
  }

  void _toast(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<List<String>> _allIds() async {
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString('nurseEmail') ?? prefs.getString('email') ?? '';
    final phone = prefs.getString('nursePhone') ?? prefs.getString('phone') ?? '';
    final phone9 = phone.replaceAll(RegExp(r'[^0-9]'), '').length >= 9 ? phone.replaceAll(RegExp(r'[^0-9]'), '').substring(phone.replaceAll(RegExp(r'[^0-9]'), '').length - 9) : '';
    final ids = [prefs.getString('lcg_nurse_uid'), prefs.getString('nurseUid'), prefs.getString('nurseId'), prefs.getString('uid'), email, email.isNotEmpty ? email.toLowerCase().replaceAll(RegExp(r'[.#\$@\[\]]'), '_') : '', phone, phone9, prefs.getString('email'), prefs.getString('phone')];
    return ids.whereType<String>().where((e) => e.isNotEmpty).toSet().toList();
  }

  Future<void> _pickFiles() async {
    final res = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (res == null) return;
    for (final f in res.files) {
      if (f.path == null) continue;
      final bytes = await File(f.path!).readAsBytes();
      setState(() => evidenceFiles.add({'id': 'FILE-${evidenceFiles.length}', 'name': f.name, 'type': 'file', 'size': bytes.length, 'url': 'data:application/octet-stream;base64,${base64Encode(bytes)}'}));
    }
  }

  Future<void> _pickAudio() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.audio);
    if (res == null || res.files.single.path == null) return;
    final bytes = await File(res.files.single.path!).readAsBytes();
    setState(() => audioBase64 = 'data:audio/webm;base64,${base64Encode(bytes)}');
    _toast(tr('ncAudioRecorded'));
  }

  Future<void> _pickVideo() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.video);
    if (res == null || res.files.single.path == null) return;
    final bytes = await File(res.files.single.path!).readAsBytes();
    setState(() => videoBase64 = 'data:video/webm;base64,${base64Encode(bytes)}');
    _toast(tr('ncVideoRecorded'));
  }

  Future<void> _submitComplaint() async {
    final text = _textCtrl.text.trim();
    if (complaintType.isEmpty) { _toast(tr('ncSelectType')); return; }
    if (text.length < 20) { _toast(tr('ncMin20')); return; }
    final confirm = await showDialog<bool>(context: context, builder: (_) => AlertDialog(title: Text(tr('ncSubmitTitle')), content: Text('${tr('ncSubmitAbout')} $clientName?'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('ncCancel'))), ElevatedButton(onPressed: () => Navigator.pop(context, true), child: Text(tr('ncSubmit')))]));
    if (confirm != true) return;
    _toast(tr('ncSubmitting'));
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final complaintId = 'NURSE-COMP-$bookingId-$now';
      final evidenceUrls = <Map>[...evidenceFiles];
      if (audioBase64 != null) evidenceUrls.add({'id': 'AUDIO-1', 'name': 'audio_$complaintId.webm', 'type': 'audio/webm', 'url': audioBase64});
      if (videoBase64 != null) evidenceUrls.add({'id': 'VIDEO-1', 'name': 'video_$complaintId.webm', 'type': 'video/webm', 'url': videoBase64});
      final prefs = await SharedPreferences.getInstance();
      final realNurseId = nurseId == 'nurse_demo' ? (prefs.getString('lcg_nurse_uid') ?? prefs.getString('nurseUid') ?? nurseId) : nurseId;
      final realNurseName = nurseName == 'Nurse' ? (prefs.getString('nurseName') ?? prefs.getString('fullName') ?? nurseName) : nurseName;
      final data = {'complaintId': complaintId, 'bookingId': bookingId, 'clientId': clientId, 'clientName': clientName, 'nurseId': realNurseId, 'nurseName': realNurseName, 'service': service, 'amount': amount, 'complaintType': complaintType, 'complaintText': text, 'status': 'pending', 'createdAt': now, 'time': now, 'evidenceCount': evidenceUrls.length, 'evidenceFiles': evidenceUrls, 'hasAudio': audioBase64 != null, 'hasVideo': videoBase64 != null, 'type': 'nurse_complaint', 'from': 'nurse', 'to': 'client', 'reflectsOnCEO': true};
      final db = FirebaseDatabase.instance;
      await db.ref('nurseComplaints/$complaintId').set(data);
      await db.ref('allComplaints/$complaintId').set(data);
      await db.ref('ceoComplaints/$complaintId').set(data);
      await db.ref('complaintsByBooking/$bookingId/$complaintId').set(data);
      _toast(tr('ncSubmittedToast'));
      await showDialog(context: context, builder: (_) => AlertDialog(title: Text(tr('ncSubmittedDialog')), content: Text('${tr('ncId')}: $complaintId\n${tr('ncClient')}: $clientName\n\n${tr('ncCeoSeesLive')}'), actions: [ElevatedButton(onPressed: () => Navigator.pop(context), child: Text(tr('ncOk')))]));
      Future.delayed(const Duration(milliseconds: 1500), () { if (mounted) Navigator.pushNamed(context, '/my-job-offers'); });
    } catch (e) { _toast('${tr('ncError')}: $e'); }
  }

  // ---- Notices / Punishment ----
  Future<void> _loadNotices() async {
    final ids = await _allIds();
    final prefs = await SharedPreferences.getInstance();
    setState(() => checkedIds = ids.join(', ').substring(0, ids.join(', ').length > 120 ? 120 : ids.join(', ').length));
    Map<String, Map> allNotices = {};
    for (final id in ids) {
      for (final path in ['userNotices/$id', 'ceoNotices/$id', 'nurseNotices/$id', 'notices/$id', 'noticesByEmail/$id', 'noticesByPhone/$id']) {
        try {
          final snap = await FirebaseDatabase.instance.ref(path).get();
          if (snap.exists) {
            (snap.value as Map).forEach((_, v) { final p = Map<String, dynamic>.from(v as Map); if (p['noticeId'] != null) allNotices[p['noticeId']] = p; });
          }
        } catch (_) {}
      }
    }
    try {
      final allSnap = await FirebaseDatabase.instance.ref('allNotices').get();
      if (allSnap.exists) {
        final nurseEmail = (prefs.getString('nurseEmail') ?? prefs.getString('email') ?? '').toLowerCase();
        final nursePhone = (prefs.getString('nursePhone') ?? prefs.getString('phone') ?? '').replaceAll(RegExp(r'[^0-9]'), '');
        final nursePhone9 = nursePhone.length >= 9 ? nursePhone.substring(nursePhone.length - 9) : '';
        (allSnap.value as Map).forEach((_, v) {
          final p = Map<String, dynamic>.from(v as Map);
          if (p['victimType'] != 'nurse') return;
          final pEmail = (p['victimEmail'] ?? '').toString().toLowerCase();
          final pPhone = (p['victimPhone'] ?? '').toString().replaceAll(RegExp(r'[^0-9]'), '');
          final pPhone9 = pPhone.length >= 9 ? pPhone.substring(pPhone.length - 9) : '';
          if ((nurseEmail.isNotEmpty && pEmail == nurseEmail) || (nursePhone9.isNotEmpty && pPhone9 == nursePhone9) || ids.contains(p['victimId'])) allNotices[p['noticeId']] = p;
        });
      }
    } catch (_) {}
    final list = allNotices.values.toList()..sort((a, b) => ((b['createdAt'] ?? 0) as num).compareTo((a['createdAt'] ?? 0) as num));
    setState(() => notices = list);
  }

  void _listenNewNotices() async {
    final ids = await _allIds();
    for (final uid in ids) {
      FirebaseDatabase.instance.ref('userNotices/$uid').onChildAdded.listen((e) {
        if (!e.snapshot.exists) return;
        final v = Map<String, dynamic>.from(e.snapshot.value as Map);
        if (v['createdAt'] != null && DateTime.now().millisecondsSinceEpoch - (v['createdAt'] as num) < 60000 && v['isRead'] != true) {
          Future.delayed(const Duration(seconds: 1), () async {
            final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(title: Text(tr('ncNewPunishment')), content: Text('${(v['action'] ?? '').toString().toUpperCase()} — ${tr('ncCeoFeedback')}'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('ncLater'))), ElevatedButton(onPressed: () => Navigator.pop(context, true), child: Text(tr('ncRead')))]));
            if (ok == true) _openNotice(v);
            _loadNotices();
          });
        }
      });
    }
  }

  void _openNotice(Map n) {
    showDialog(context: context, builder: (_) => AlertDialog(
      title: Text('${n['action'] ?? tr('ncNotice')} — ${n['noticeId'] ?? ''}'),
      content: SingleChildScrollView(child: Text('${n['message'] ?? n['reason'] ?? ''}\n\n${tr('ncAction')}: ${n['action'] ?? ''}\n${tr('ncCreated')}: ${n['createdAt'] != null ? DateTime.fromMillisecondsSinceEpoch((n['createdAt'] as num).toInt()) : ''}')),
      actions: [
        TextButton(onPressed: () => _markNoticeRead(n), child: Text(tr('ncMarkRead'))),
        TextButton(onPressed: () => _appealNotice(n), child: Text(tr('ncAppealToCeo'))),
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('ncClose'))),
      ],
    ));
  }

  Future<void> _markNoticeRead(Map n) async {
    final prefs = await SharedPreferences.getInstance();
    final uid = prefs.getString('lcg_nurse_uid') ?? prefs.getString('nurseUid') ?? '';
    await FirebaseDatabase.instance.ref('userNotices/$uid/${n['noticeId']}').update({'isRead': true, 'readAt': DateTime.now().millisecondsSinceEpoch});
    _toast(tr('ncMarkedRead'));
    Navigator.pop(context);
    _loadNotices();
  }

  Future<void> _appealNotice(Map n) async {
    final ctrl = TextEditingController();
    final reason = await showDialog<String>(context: context, builder: (_) => AlertDialog(title: Text(tr('ncAppealToCeo')), content: TextField(controller: ctrl, decoration: InputDecoration(hintText: tr('ncAppealHint'))), actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('ncCancel'))), ElevatedButton(onPressed: () => Navigator.pop(context, ctrl.text), child: Text(tr('ncSend')))]));
    if (reason == null || reason.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final uid = prefs.getString('lcg_nurse_uid') ?? prefs.getString('nurseUid') ?? '';
    await FirebaseDatabase.instance.ref('noticeAppeals/${n['noticeId']}').set({'noticeId': n['noticeId'], 'userId': uid, 'reason': reason, 'createdAt': DateTime.now().millisecondsSinceEpoch, 'status': 'pending'});
    _toast(tr('ncAppealSent'));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final unread = notices.where((n) => n['isRead'] != true).length;
    return Scaffold(
      backgroundColor: const Color(0xFF0E0A1C),
      appBar: AppBar(title: Text(tr('ncTitle'), style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)), backgroundColor: const Color(0xFF1A1633), actions: [DropdownButtonHideUnderline(child: DropdownButton<String>(value: LanguageService.instance.locale.languageCode, dropdownColor: const Color(0xFF0C0A1E), icon: const Icon(Icons.language, color: Colors.white, size: 24), items: LanguageService.languageNames.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, style: const TextStyle(color: Colors.black)))).toList(), onChanged: (v) { if (v != null) LanguageService.instance.setLanguage(v); })), Stack(children: [IconButton(icon: const Icon(Icons.notifications), onPressed: () { setState(() => showNotices = !showNotices); if (showNotices) _loadNotices(); }), if (unread > 0) Positioned(right: 6, top: 6, child: CircleAvatar(radius: 9, backgroundColor: Colors.red, child: Text('$unread', style: const TextStyle(fontSize: 9, color: Colors.white))))])]),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(children: [
          Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: const Color(0xFF1C1238), borderRadius: BorderRadius.circular(20)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr('ncHeader'), style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('${tr('ncBooking')}: $bookingId', style: const TextStyle(color: Colors.white60, fontSize: 11)),
            Text('${tr('ncClient')}: $clientName', style: const TextStyle(fontSize: 13)),
            Text('${tr('ncNurse')}: $nurseName • ${tr('ncService')}: $service • ${tr('ncAmount')}: GHS $amount', style: const TextStyle(color: Colors.white60, fontSize: 11)),
          ])),
          const SizedBox(height: 12),
          Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: const Color(0xFF1C1238), borderRadius: BorderRadius.circular(20)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr('ncTypeTextHeader'), style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(value: complaintType.isEmpty ? null : complaintType, decoration: InputDecoration(labelText: tr('ncComplaintType'), border: OutlineInputBorder()), items: types.map((t) => DropdownMenuItem(value: t['v']!, child: Text(t['l']!))).toList(), onChanged: (v) => setState(() => complaintType = v ?? '')),
            const SizedBox(height: 10),
            TextField(controller: _textCtrl, maxLines: 5, decoration: InputDecoration(labelText: tr('ncComplaintTextLabel'), hintText: tr('ncComplaintHint'), border: OutlineInputBorder())),
          ])),
          const SizedBox(height: 12),
          Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: const Color(0xFF1C1238), borderRadius: BorderRadius.circular(20)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr('ncEvidenceHeader'), style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Row(children: [Expanded(child: ElevatedButton(onPressed: _pickFiles, child: Text(tr('ncPickFiles')))), const SizedBox(width: 6), Expanded(child: ElevatedButton(onPressed: _pickAudio, child: Text(tr('ncPickAudio')))), const SizedBox(width: 6), Expanded(child: ElevatedButton(onPressed: _pickVideo, child: Text(tr('ncPickVideo'))))]),
            if (evidenceFiles.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text('${tr('ncFiles')}: ${evidenceFiles.map((f) => f['name']).join(', ')}', style: const TextStyle(color: Colors.white60, fontSize: 11))),
            if (audioBase64 != null) Padding(padding: EdgeInsets.only(top: 4), child: Text(tr('ncAudioReady'), style: TextStyle(color: Colors.green, fontSize: 11))),
            if (videoBase64 != null) Padding(padding: EdgeInsets.only(top: 4), child: Text(tr('ncVideoReady'), style: TextStyle(color: Colors.green, fontSize: 11))),
          ])),
          const SizedBox(height: 12),
          SizedBox(width: double.infinity, child: ElevatedButton(onPressed: _submitComplaint, style: ElevatedButton.styleFrom(backgroundColor: Colors.red, padding: const EdgeInsets.symmetric(vertical: 14)), child: Text(tr('ncSubmitToCeo'), style: TextStyle(fontWeight: FontWeight.bold)))),
          const SizedBox(height: 12),
          // My Notices
          Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: const Color(0xFF1C1238), borderRadius: BorderRadius.circular(20)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(tr('ncNoticesHeader'), style: TextStyle(fontWeight: FontWeight.bold)), TextButton(onPressed: () { setState(() => showNotices = !showNotices); if (showNotices) _loadNotices(); }, child: Text(showNotices ? tr('ncHide') : tr('ncShow')))]),
            Text('${tr('ncCheckedIds')}: $checkedIds', style: const TextStyle(color: Colors.white60, fontSize: 9)),
            if (showNotices) ...[
              const SizedBox(height: 8),
              if (notices.isEmpty) Text(tr('ncNoNotices'), style: TextStyle(color: Colors.white60)),
              ...notices.map((n) => ListTile(
                leading: CircleAvatar(backgroundColor: n['isRead'] == true ? Colors.grey : Colors.red, child: Text((n['action'] ?? 'N').toString().isNotEmpty ? (n['action'] as String)[0].toUpperCase() : 'N', style: const TextStyle(color: Colors.white))),
                title: Text('${n['action'] ?? tr('ncNotice')} — ${n['noticeId'] ?? ''}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                subtitle: Text((n['message'] ?? n['reason'] ?? '').toString(), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
                trailing: Text(n['isRead'] == true ? tr('ncReadStatus') : tr('ncNew'), style: TextStyle(color: n['isRead'] == true ? Colors.grey : Colors.red, fontSize: 11, fontWeight: FontWeight.bold)),
                onTap: () => _openNotice(n),
              )),
            ],
          ])),
          const SizedBox(height: 20),
        ]),
      ),
    );
  }
}
