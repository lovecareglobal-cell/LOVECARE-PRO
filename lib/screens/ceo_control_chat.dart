import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import '../services/language_service.dart';
import '../services/translations.dart';

class CEOControlChatScreen extends StatefulWidget {
  const CEOControlChatScreen({super.key});
  @override
  State<CEOControlChatScreen> createState() => _CEOControlChatScreenState();
}

// Aliases - so main.dart + old files still work
class CEOControlChatPage extends CEOControlChatScreen {
  const CEOControlChatPage({super.key});
}
class CeoControlChatScreen extends CEOControlChatScreen {
  const CeoControlChatScreen({super.key});
}

class _CEOControlChatScreenState extends State<CEOControlChatScreen> {
  final DatabaseReference _db = FirebaseDatabase.instance.ref();
  final TextEditingController _input = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  final ScrollController _scroll = ScrollController();
  final FocusNode _inputFocus = FocusNode();

  // CEO - same as HTML me={id:'CEO_ASABERE', name:'Asabere Peter — CEO'}
  final String ceoId = 'CEO_ASABERE';
  final String ceoName = 'Asabere Peter — CEO';
  final String ceoPhoto = 'https://ui-avatars.com/api/?name=Asabere+Peter&background=facc15&color=000';

  String dest = 'nurses'; // nurses | index
  List<Map<String, dynamic>> messages = [];

  // Home settings - same as HTML
  Color textColor = Colors.white;
  Color bgColor = const Color(0xFF191531);
  String displayType = 'marquee_slow'; // marquee_slow | marquee_fast | static | photo_full
  String speed = 'slow'; // slow | medium | fast

  // Collapse settings so small phone fit scroll
  bool showSettings = true;

  // Pending files - same as HTML imgs / vids / docs / aBlob / vBlob
  List<Map<String, dynamic>> pendingImages = [];
  List<Map<String, dynamic>> pendingVideos = []; // {name, data(base64 or ''), bytes, size, isBig}
  List<Map<String, dynamic>> pendingDocs = [];
  String? pendingVoiceUrl; // base64 or storage url
  String? pendingVideoMsgUrl;

  bool showEmoji = false;
  bool isSending = false;
  double uploadProgress = 0;
  String statusText = '';

  final List<String> emojis = ['😊','😂','❤️','👍','👏','🙏','💪','😍','🥰','😘','😅','🤣','😎','🤩','😭','🥺','😮','😱','🤔','👌','✌️','🤝','💯','🔥','⭐','🌟','💖','💜','👩‍⚕️','👑','📢','🎉'];

  @override
  void initState() {
    super.initState();
    statusText = tr('statusReady');
    _loadMsgs();
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  void _toast(String m) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  void _loadMsgs() {
    // Nurses messages - last 30
    _db.child('nurses_group_chat/messages').orderByChild('createdAt').limitToLast(30).onValue.listen((e) {
      if (e.snapshot.value == null || e.snapshot.value is! Map) return;
      final data = Map<String, dynamic>.from(e.snapshot.value as Map);
      for (final entry in data.entries) {
        if (entry.value is! Map) continue;
        final v = Map<String, dynamic>.from(entry.value as Map);
        _addOrUpdate({...v, 'id': entry.key.toString(), 'key': entry.key.toString(), 'type': 'nurses'});
      }
      _sortMsgs();
    });
    // Home announcements - last 20
    _db.child('ceoHomePageAnnouncements').orderByChild('createdAt').limitToLast(20).onValue.listen((e) {
      if (e.snapshot.value == null || e.snapshot.value is! Map) return;
      final data = Map<String, dynamic>.from(e.snapshot.value as Map);
      for (final entry in data.entries) {
        if (entry.value is! Map) continue;
        final v = Map<String, dynamic>.from(entry.value as Map);
        _addOrUpdate({...v, 'id': entry.key.toString(), 'key': entry.key.toString(), 'type': 'home'});
      }
      _sortMsgs();
    });
  }

  void _addOrUpdate(Map<String, dynamic> m) {
    final key = (m['key'] ?? m['id'] ?? m['messageId'] ?? '').toString();
    final idx = messages.indexWhere((x) => (x['key'] ?? x['id'] ?? '').toString() == key);
    if (idx == -1) {
      messages.add(m);
    } else {
      messages[idx] = {...messages[idx], ...m};
    }
  }

  void _sortMsgs() {
    messages.sort((a, b) {
      final ta = int.tryParse('${a['createdAt'] ?? 0}') ?? 0;
      final tb = int.tryParse('${b['createdAt'] ?? 0}') ?? 0;
      return ta.compareTo(tb);
    });
    if (mounted) setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        try {
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        } catch (_) {}
      }
    });
  }

  void _setDest(String d) {
    setState(() {
      dest = d;
      if (d == 'nurses') {
        statusText = tr('statusNurses');
      } else {
        statusText = tr('statusHome');
      }
    });
  }

  // ===== PICKERS =====
  Future<void> _pickImages() async {
    final picked = await _picker.pickMultiImage();
    for (final x in picked) {
      final bytes = await x.readAsBytes();
      if (bytes.length > 10 * 1024 * 1024) { _toast('${tr('photoTooBig')} ${x.name}'); continue; }
      pendingImages.add({'name': x.name, 'data': 'data:image/jpeg;base64,${base64Encode(bytes)}', 'url': 'data:image/jpeg;base64,${base64Encode(bytes)}'});
    }
    setState(() {});
    _toast('${pendingImages.length} ${tr('photosReady')}');
  }

  Future<void> _pickVideos() async {
    final picked = await _picker.pickVideo(source: ImageSource.gallery);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    if (bytes.length > 100 * 1024 * 1024) { _toast(tr('videoTooBig')); return; }
    final isBig = bytes.length > 8 * 1024 * 1024;
    pendingVideos.add({
      'name': picked.name,
      'data': isBig ? '' : 'data:video/mp4;base64,${base64Encode(bytes)}',
      'url': isBig ? '' : 'data:video/mp4;base64,${base64Encode(bytes)}',
      'size': bytes.length,
      'isBig': isBig,
      'bytes': bytes,
    });
    setState(() {});
    _toast('${tr('videoPicked')} ${picked.name} (${(bytes.length / 1024 / 1024).toStringAsFixed(1)}MB) — ${isBig ? tr('willUploadCloud') : tr('readyToSendPress')}');
  }

  Future<void> _pickDocs() async {
    final res = await FilePicker.platform.pickFiles(allowMultiple: true, withData: true, type: FileType.custom, allowedExtensions: ['pdf', 'doc', 'docx', 'txt']);
    if (res == null) return;
    for (final f in res.files) {
      if (f.bytes == null) continue;
      if (f.bytes!.length > 10 * 1024 * 1024) { _toast('${tr('docTooBig')} ${f.name}'); continue; }
      pendingDocs.add({'name': f.name, 'data': 'data:application/octet-stream;base64,${base64Encode(f.bytes!)}', 'url': 'data:application/octet-stream;base64,${base64Encode(f.bytes!)}'});
    }
    setState(() {});
    _toast('${pendingDocs.length} ${tr('docsReady')}');
  }

  Future<void> _pickVoice() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.audio, withData: true);
    if (res == null || res.files.isEmpty || res.files.first.bytes == null) return;
    final bytes = res.files.first.bytes!;
    pendingVoiceUrl = 'data:audio/webm;base64,${base64Encode(bytes)}';
    setState(() {});
    _toast(tr('voiceReadyPress'));
  }

  Future<void> _pickVideoMsg() async {
    final picked = await _picker.pickVideo(source: ImageSource.camera);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    pendingVideoMsgUrl = 'data:video/webm;base64,${base64Encode(bytes)}';
    setState(() {});
    _toast(tr('videoMsgReadyPress'));
  }

  Future<String> _uploadToStorage(Uint8List bytes, String path) async {
    try {
      final ref = FirebaseStorage.instance.ref().child(path);
      final task = ref.putData(bytes);
      task.snapshotEvents.listen((s) {
        if (s.totalBytes > 0) setState(() => uploadProgress = s.bytesTransferred / s.totalBytes * 100);
      });
      await task;
      setState(() => uploadProgress = 0);
      return await ref.getDownloadURL();
    } catch (e) {
      return 'data:video/mp4;base64,${base64Encode(bytes)}';
    }
  }

  String _colorToHex(Color c) => '#${c.value.toRadixString(16).substring(2).toUpperCase()}';

  // ===== SEND - BANNER SYNC TO MAIN.DART =====
  Future<void> _send() async {
    final txt = _input.text.trim();
    if (txt.isEmpty && pendingImages.isEmpty && pendingVideos.isEmpty && pendingDocs.isEmpty && pendingVoiceUrl == null && pendingVideoMsgUrl == null) {
      _toast(tr('typeMsgOrPick'));
      return;
    }
    setState(() { isSending = true; uploadProgress = 10; statusText = tr('uploadingSending'); });
    try {
      final id = 'MSG-${DateTime.now().millisecondsSinceEpoch}-${DateTime.now().microsecondsSinceEpoch.toString().substring(8)}';
      final now = DateTime.now().millisecondsSinceEpoch;
      final base = <String, dynamic>{
        'messageId': id,
        'senderId': ceoId,
        'senderName': ceoName,
        'senderPhoto': ceoPhoto,
        'text': txt,
        'message': txt,
        'title': txt,
        'announcement': txt,
        'createdAt': now,
        'timestamp': now,
        'createdAtStr': DateTime.now().toString(),
        'isCEO': true,
      };
      if (pendingImages.isNotEmpty) base['images'] = pendingImages.map((e) => {'name': e['name'], 'data': e['data'], 'url': e['url']}).toList();

      final finalVideos = <Map<String, dynamic>>[];
      for (var i = 0; i < pendingVideos.length; i++) {
        final v = pendingVideos[i];
        final bytes = v['bytes'] as Uint8List?;
        final size = (v['size'] ?? 0) as int;
        if (size > 8 * 1024 * 1024 && bytes != null) {
          setState(() => statusText = tr('uploadingVideoCloud'));
          _toast('${tr('bigVideoUploading')} (${(size / 1024 / 1024).round()}MB)');
          final url = await _uploadToStorage(bytes, 'ceo_announcements/$id/video_${i}_${v['name']}');
          finalVideos.add({'name': v['name'], 'url': url, 'size': size, 'type': 'video/mp4'});
        } else {
          finalVideos.add({'name': v['name'], 'data': v['data'], 'url': v['url'], 'size': size, 'type': 'video/mp4'});
        }
      }
      if (finalVideos.isNotEmpty) base['videos'] = finalVideos;
      if (pendingDocs.isNotEmpty) base['files'] = pendingDocs;

      if (pendingVoiceUrl != null) base['voice'] = pendingVoiceUrl;
      if (pendingVideoMsgUrl != null) base['videoMessage'] = pendingVideoMsgUrl;

      setState(() => statusText = tr('savingToDb'));

      if (dest == 'nurses') {
        await _db.child('nurses_group_chat/messages/$id').set({...base, 'destination': 'nurses'});
        await _db.child('nurseCommunityChat/messages/$id').set({...base, 'destination': 'nurses'});
        await _db.child('ceoChats/nurseBoard/$id').set({...base, 'destination': 'nurses'});
        _toast(tr('sentToNurses'));
      } else {
        // HOME BANNER - write SAME data to ALL places main.dart listens to
        final home = {
          ...base,
          'announcementId': id,
          'textColor': _colorToHex(textColor),
          'bgColor': _colorToHex(bgColor),
          'displayType': displayType,
          'speed': speed,
          'active': true,
          'isActive': true,
          'destination': 'index',
          'isHomePage': true,
        };
        await _db.child('ceoHomePageAnnouncements/$id').set(home);
        await _db.child('ceoHomePageCurrent').set(home);
        await _db.child('homePageBanner/current').set(home);
        await _db.child('homePageBanner/$id').set(home);
        await _db.child('announcements/current').set(home).catchError((_) {});
        _toast(tr('sentToHome'));
      }

      _input.clear();
      pendingImages = [];
      pendingVideos = [];
      pendingDocs = [];
      pendingVoiceUrl = null;
      pendingVideoMsgUrl = null;
      setState(() { uploadProgress = 0; statusText = tr('sentReadyNext'); });
    } catch (e) {
      _toast('${tr('failedLabel')}: $e');
      setState(() => statusText = '${tr('failedLabel')}: $e');
    }
    setState(() { isSending = false; uploadProgress = 0; });
  }

  Future<void> _editMsg(Map<String, dynamic> m) async {
    final key = (m['key'] ?? m['id'] ?? m['messageId'] ?? '').toString();
    final isHome = (m['type'] ?? '') == 'home';
    final ctrl = TextEditingController(text: (m['text'] ?? '').toString());
    final newText = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(tr('editMessage')),
        content: TextField(controller: ctrl, maxLines: 3),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('cancel'))), ElevatedButton(onPressed: () => Navigator.pop(context, ctrl.text.trim()), child: Text(tr('saveBtn')))],
      ),
    );
    if (newText == null) return;
    final payload = {'text': newText, 'message': newText, 'title': newText, 'announcement': newText, 'edited': true, 'editedAt': DateTime.now().millisecondsSinceEpoch};
    final path = isHome ? 'ceoHomePageAnnouncements/$key' : 'nurses_group_chat/messages/$key';
    await _db.child(path).update(payload);
    // FIX: Edit must update Current too, else Home keeps old text
    if (isHome) {
      await _db.child('ceoHomePageCurrent').update(payload).catchError((_) {});
      await _db.child('homePageBanner/current').update(payload).catchError((_) {});
      await _db.child('announcements/current').update(payload).catchError((_) {});
    }
    _toast(tr('editedLive'));
  }

  Future<void> _delMsg(Map<String, dynamic> m) async {
    final confirm = await showDialog<bool>(context: context, builder: (_) => AlertDialog(title: Text(tr('deleteQ')), content: Text(tr('deleteMsgAllPhonesQ')), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), ElevatedButton(onPressed: () => Navigator.pop(context, true), child: Text(tr('delete')))]));
    if (confirm != true) return;
    final key = (m['key'] ?? m['id'] ?? m['messageId'] ?? '').toString();
    await _db.child('nurses_group_chat/messages/$key').remove().catchError((_) {});
    await _db.child('nurseCommunityChat/messages/$key').remove().catchError((_) {});
    await _db.child('ceoHomePageAnnouncements/$key').remove().catchError((_) {});
    await _db.child('ceoHomePageCurrent').remove().catchError((_) {});
    await _db.child('homePageBanner/current').remove().catchError((_) {});
    await _db.child('homePageBanner/$key').remove().catchError((_) {});
    await _db.child('announcements/current').remove().catchError((_) {});
    setState(() => messages.removeWhere((x) => (x['key'] ?? x['id'] ?? '').toString() == key));
    _toast(tr('deletedAllPhones'));
  }

  @override
  Widget build(BuildContext context) {
    final isHome = dest == 'index';
    final txt = _input.text;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: const Color(0xFF0E0C1E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF141028),
        title: Text(tr('ceoControlTitle'), style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)),
        actions: [
          DropdownButtonHideUnderline(child: DropdownButton<String>(value: LanguageService.instance.locale.languageCode, dropdownColor: const Color(0xFF141028), icon: const Icon(Icons.language, color: Colors.white, size: 20), items: LanguageService.languageNames.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, style: const TextStyle(color: Colors.white)))).toList(), onChanged: (v) { if (v != null) LanguageService.instance.setLanguage(v); })),
          TextButton(onPressed: () => Navigator.pushNamed(context, '/nurse-group-chat'), child: Text(tr('viewNurses'), style: TextStyle(color: Colors.white, fontSize: 11))),
          TextButton(onPressed: () => Navigator.pushNamed(context, '/'), child: Text(tr('viewHome'), style: TextStyle(color: Colors.white, fontSize: 11))),
        ],
      ),
      body: Column(
        children: [
          if (uploadProgress > 0) LinearProgressIndicator(value: uploadProgress / 100, backgroundColor: Colors.white10, color: const Color(0xFFFACC15)),
          // FIX SCROLL: whole middle is ONE scrollable area
          Expanded(
            child: SingleChildScrollView(
              controller: _scroll,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    color: const Color(0xFF191531),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Expanded(child: Text(tr('sendTo'), style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF9A95B8)))),
                            TextButton(
                              onPressed: () => setState(() => showSettings = !showSettings),
                              child: Text(showSettings ? tr('hideSettings') : tr('showSettings'), style: const TextStyle(color: Colors.white70, fontSize: 11)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          children: [
                            ChoiceChip(label: Text(tr('nursesGroupChat')), selected: dest == 'nurses', onSelected: (_) => _setDest('nurses'), selectedColor: const Color(0xFFA78BFA).withOpacity(0.2), labelStyle: TextStyle(color: dest == 'nurses' ? const Color(0xFFC4B5FD) : Colors.white70, fontSize: 12)),
                            ChoiceChip(label: Text(tr('homePageBanner')), selected: dest == 'index', onSelected: (_) => _setDest('index'), selectedColor: const Color(0xFFFACC15).withOpacity(0.2), labelStyle: TextStyle(color: dest == 'index' ? const Color(0xFFFACC15) : Colors.white70, fontSize: 12)),
                          ],
                        ),
                        if (showSettings) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(color: isHome ? const Color(0xFFFACC15).withOpacity(0.08) : const Color(0xFFA78BFA).withOpacity(0.08), borderRadius: BorderRadius.circular(10)),
                            child: Text(isHome ? tr('homeBannerNote') : tr('nursesChatNote'), style: TextStyle(fontSize: 11, color: isHome ? const Color(0xFFFACC15) : const Color(0xFFC4B5FD))),
                          ),
                          if (isHome) ...[
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(child: _colorPicker(tr('textColour'), textColor, (c) => setState(() => textColor = c))),
                                const SizedBox(width: 8),
                                Expanded(child: _colorPicker(tr('backgroundLabel'), bgColor, (c) => setState(() => bgColor = c))),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: DropdownButtonFormField<String>(value: displayType, dropdownColor: const Color(0xFF191531), style: const TextStyle(color: Colors.white, fontSize: 12), decoration: const InputDecoration(labelText: tr('displayType'), labelStyle: TextStyle(color: Colors.white54, fontSize: 10), border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8)), items: const [DropdownMenuItem(value: 'marquee_slow', child: Text(tr('slowMove'))), DropdownMenuItem(value: 'marquee_fast', child: Text(tr('fastMove'))), DropdownMenuItem(value: 'static', child: Text(tr('staticLabel'))), DropdownMenuItem(value: 'photo_full', child: Text(tr('fullPhotoVideo')))], onChanged: (v) => setState(() => displayType = v ?? displayType)),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: DropdownButtonFormField<String>(value: speed, dropdownColor: const Color(0xFF191531), style: const TextStyle(color: Colors.white, fontSize: 12), decoration: const InputDecoration(labelText: tr('speedLabel'), labelStyle: TextStyle(color: Colors.white54, fontSize: 10), border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8)), items: const [DropdownMenuItem(value: 'slow', child: Text(tr('slowLabel'))), DropdownMenuItem(value: 'medium', child: Text(tr('mediumLabel'))), DropdownMenuItem(value: 'fast', child: Text(tr('fastLabel')))], onChanged: (v) => setState(() => speed = v ?? speed)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white10)),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(tr('previewOnHome'), style: TextStyle(fontSize: 10, color: Colors.white54, fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 8),
                                  Text(txt.isEmpty ? tr('typeToPreview') : txt, style: TextStyle(color: textColor, fontSize: 13)),
                                  if (displayType == 'photo_full' && pendingVideos.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text('${tr('videoLabel')}: ${pendingVideos[0]['name']} — ${tr('willPlayFullWidth')}', style: TextStyle(color: textColor, fontSize: 11))),
                                  if (displayType == 'photo_full' && pendingImages.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(tr('photoFullWidth'), style: TextStyle(color: textColor, fontSize: 11))),
                                  Text('$displayType • $speed', style: const TextStyle(color: Colors.white54, fontSize: 10)),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ],
                    ),
                  ),
                  if (messages.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('👑', style: TextStyle(fontSize: 28)),
                          SizedBox(height: 8),
                          Text(tr('ceoControlVideoFixed'), style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                          SizedBox(height: 6),
                          Text(tr('pickVideoGoesLive'), textAlign: TextAlign.center, style: TextStyle(color: Colors.white54, fontSize: 11)),
                        ],
                      ),
                    )
                  else
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(16),
                      itemCount: messages.length,
                      itemBuilder: (context, i) {
                        final m = messages[i];
                        final isHomeMsg = (m['type'] ?? '') == 'home';
                        final time = (m['createdAt'] ?? 0) is int ? DateTime.fromMillisecondsSinceEpoch(m['createdAt'] as int) : DateTime.now();
                        final timeStr = '${time.hour}:${time.minute.toString().padLeft(2, '0')}';
                        final images = m['images'] is List ? (m['images'] as List) : <dynamic>[];
                        final videos = m['videos'] is List ? (m['videos'] as List) : <dynamic>[];
                        String mediaInfo = '';
                        if (images.isNotEmpty) mediaInfo += ' 🖼️${images.length} ${tr('photosShort')}';
                        if (videos.isNotEmpty) mediaInfo += ' 🎥${videos.length} ${tr('videosShort')}';
                        if ((m['voice'] ?? '').toString().isNotEmpty) mediaInfo += ' 🎤 ${tr('voiceShort')}';
                        if ((m['videoMessage'] ?? '').toString().isNotEmpty) mediaInfo += ' 📹 ${tr('videoMsgShort')}';
                        return Align(
                          alignment: Alignment.centerRight,
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(12),
                            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
                            decoration: BoxDecoration(color: isHomeMsg ? const Color(0xFFFACC15) : const Color(0xFFA78BFA), borderRadius: BorderRadius.circular(16)),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('👑 CEO ${isHomeMsg ? tr('homeUpper') : tr('nursesUpper')} ${m['senderName'] ?? 'CEO'} $timeStr$mediaInfo', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: isHomeMsg ? Colors.black87 : Colors.white)),
                                const SizedBox(height: 4),
                                Text((m['text'] ?? '').toString(), style: TextStyle(fontSize: 13, color: isHomeMsg ? Colors.black : Colors.white)),
                                if ((m['displayType'] ?? '').toString().isNotEmpty) Text('${m['displayType']} • ${m['speed'] ?? ''}', style: const TextStyle(fontSize: 10, color: Colors.black54)),
                                Row(children: [TextButton(onPressed: () => _editMsg(m), child: Text(tr('editBtn'), style: TextStyle(fontSize: 10, color: isHomeMsg ? Colors.black : Colors.white))), TextButton(onPressed: () => _delMsg(m), child: Text(tr('delete'), style: TextStyle(fontSize: 10, color: Colors.red)))]),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  if (pendingImages.isNotEmpty || pendingVideos.isNotEmpty || pendingDocs.isNotEmpty || pendingVoiceUrl != null || pendingVideoMsgUrl != null)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      padding: const EdgeInsets.all(10),
                      color: Colors.white.withOpacity(0.05),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ...pendingImages.map<Widget>((f) => Row(children: [Expanded(child: Text('🖼️ ${f['name']} — ${tr('readyLabel')}', style: const TextStyle(color: Colors.white70, fontSize: 11))), TextButton(onPressed: () => setState(() => pendingImages.remove(f)), child: const Text('✕', style: TextStyle(color: Colors.white70)))] )).toList(),
                          ...pendingVideos.map<Widget>((f) => Row(children: [Expanded(child: Text('🎥 ${f['name']} — ${((f['size'] ?? 0) / 1024 / 1024).toStringAsFixed(1)}MB — ${tr('readyToSend')}', style: const TextStyle(color: Colors.white70, fontSize: 11))), TextButton(onPressed: () => setState(() => pendingVideos.remove(f)), child: const Text('✕', style: TextStyle(color: Colors.white70)))] )).toList(),
                          ...pendingDocs.map<Widget>((f) => Row(children: [Expanded(child: Text('📄 ${f['name']} — ${tr('readyLabel')}', style: const TextStyle(color: Colors.white70, fontSize: 11))), TextButton(onPressed: () => setState(() => pendingDocs.remove(f)), child: const Text('✕', style: TextStyle(color: Colors.white70)))] )).toList(),
                          if (pendingVoiceUrl != null) Row(children: [const Expanded(child: Text('🎤 Voice — Ready', style: TextStyle(color: Colors.white70, fontSize: 11))), TextButton(onPressed: () => setState(() => pendingVoiceUrl = null), child: const Text('✕', style: TextStyle(color: Colors.white70)))]),
                          if (pendingVideoMsgUrl != null) Row(children: [const Expanded(child: Text('📹 Video Msg — Ready', style: TextStyle(color: Colors.white70, fontSize: 11))), TextButton(onPressed: () => setState(() => pendingVideoMsgUrl = null), child: const Text('✕', style: TextStyle(color: Colors.white70)))]),
                          Text(tr('filesReadyPress'), textAlign: TextAlign.center, style: TextStyle(color: Colors.white54, fontSize: 10)),
                        ],
                      ),
                    ),
                  if (showEmoji)
                    Container(
                      height: 140,
                      padding: const EdgeInsets.all(10),
                      color: const Color(0xFF191531),
                      child: GridView.builder(
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 6, crossAxisSpacing: 6, mainAxisSpacing: 6),
                        itemCount: emojis.length,
                        itemBuilder: (context, idx) => InkWell(onTap: () { _input.text += emojis[idx]; setState(() => showEmoji = false); }, child: Center(child: Text(emojis[idx], style: const TextStyle(fontSize: 22)))),
                      ),
                    ),
                ],
              ),
            ),
          ),
          // Composer - stays above keyboard
          Padding(
            padding: EdgeInsets.only(bottom: bottomInset),
            child: Container(
              padding: const EdgeInsets.all(12),
              color: const Color(0xFF141028),
              child: Column(
                children: [
                  Wrap(
                    spacing: 6,
                    children: [
                      ActionChip(label: Text(tr('photoChip'), style: TextStyle(fontSize: 11)), onPressed: _pickImages),
                      ActionChip(label: Text(tr('videoChip2'), style: TextStyle(fontSize: 11)), onPressed: _pickVideos),
                      ActionChip(label: Text(tr('docChip'), style: TextStyle(fontSize: 11)), onPressed: _pickDocs),
                      ActionChip(label: Text(tr('voiceChip'), style: TextStyle(fontSize: 11)), onPressed: _pickVoice),
                      ActionChip(label: Text(tr('videoMsgChip'), style: TextStyle(fontSize: 11)), onPressed: _pickVideoMsg),
                      ActionChip(label: Text(tr('emojiChip'), style: TextStyle(fontSize: 11)), onPressed: () => setState(() => showEmoji = !showEmoji)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _input,
                          focusNode: _inputFocus,
                          maxLines: 4,
                          minLines: 1,
                          style: const TextStyle(color: Colors.white, fontSize: 13),
                          decoration: InputDecoration(hintText: isHome ? tr('announcementHomeHint') : tr('messageNursesHint'), hintStyle: const TextStyle(color: Colors.white54, fontSize: 13), filled: true, fillColor: Colors.black.withOpacity(0.2), border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide(color: Colors.white.withOpacity(0.1))), contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12)),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(icon: const Text('😊', style: TextStyle(fontSize: 20)), onPressed: () => setState(() => showEmoji = !showEmoji)),
                      CircleAvatar(
                        backgroundColor: isHome ? const Color(0xFFFACC15) : const Color(0xFFA78BFA),
                        child: IconButton(icon: isSending ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : Text('➤', style: TextStyle(color: isHome ? Colors.black : Colors.white)), onPressed: isSending ? null : _send),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(statusText, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54, fontSize: 10)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _colorPicker(String label, Color current, Function(Color) onPick) {
    final colors = [Colors.white, Colors.black, const Color(0xFF191531), const Color(0xFFFACC15), const Color(0xFFA78BFA), const Color(0xFF34D399), const Color(0xFFEF4444), const Color(0xFF3B82F6)];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          children: colors.map((c) => InkWell(
            onTap: () => onPick(c),
            child: Container(width: 28, height: 28, decoration: BoxDecoration(color: c, shape: BoxShape.circle, border: Border.all(color: current == c ? Colors.white : Colors.white24, width: current == c ? 2 : 1))),
          )).toList(),
        ),
        const SizedBox(height: 4),
        Text(_colorToHex(current), style: const TextStyle(color: Colors.white70, fontSize: 10)),
      ],
    );
  }
}
