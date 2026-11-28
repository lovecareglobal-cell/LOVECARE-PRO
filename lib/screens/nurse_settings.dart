import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:geolocator/geolocator.dart';
import 'package:file_picker/file_picker.dart';
import '../services/language_service.dart';
import '../services/translations.dart';

/// Nurse Settings - Flutter version of nurse-settings.html
/// - Photo upload -> Storage nurses/{uid}/photo_... + nurses/{uid} + syncToCEO
/// - Docs: CV 10MB, Video 50MB, Certificate 10MB, License 10MB -> Storage nurses/{uid}/{type}_...
/// - Email change (reauth), Phone+Name, Nurse Info (specialty, country, bio, prices, hours, availability)
/// - GPS Location save, Password change (reauth), Delete Account (deletedNurses)
/// - syncToCEO: nurses, nurse_registrations, pendingNurseRegistrations, nurseUsers, nurseProfiles, ceoNurseUpdates, ceoRegistrationCenter/nurses, ceoBookingReceiverNurses

class NurseSettingsScreen extends StatefulWidget {
  const NurseSettingsScreen({super.key});
  @override
  State<NurseSettingsScreen> createState() => _NurseSettingsScreenState();
}

class _NurseSettingsScreenState extends State<NurseSettingsScreen> {
  User? currentUser;
  Map? nurseData;
  // Controllers
  final _newEmailCtrl = TextEditingController();
  final _emailPassCtrl = TextEditingController();
  final _newPhoneCtrl = TextEditingController();
  final _displayNameCtrl = TextEditingController();
  final _specialtyCtrl = TextEditingController();
  final _countryCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();
  final _priceShortCtrl = TextEditingController();
  final _priceLongCtrl = TextEditingController();
  final _workHoursCtrl = TextEditingController();
  String availability = 'Available';
  final _gpsNameCtrl = TextEditingController();
  final _latCtrl = TextEditingController();
  final _lngCtrl = TextEditingController();
  final _curPassCtrl = TextEditingController();
  final _newPassCtrl = TextEditingController();
  final _confirmPassCtrl = TextEditingController();
  final _deletePassCtrl = TextEditingController();
  final _deleteDetailsCtrl = TextEditingController();
  String deleteReason = '';
  bool confirmCheck = false, confirmData = false;
  Map<String, String> docUrls = {}; // cv, video, certificate, license
  Map<String, double> uploadProgress = {};
  String? photoUrl;

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    final user = FirebaseAuth.instance.currentUser;
    setState(() => currentUser = user);
    if (user == null) return;
    final snap = await FirebaseDatabase.instance.ref('nurses/${user.uid}').get();
    if (snap.exists) {
      final d = Map<String, dynamic>.from(snap.value as Map);
      setState(() {
        nurseData = d;
        photoUrl = d['photo'] ?? d['photoURL'];
        _displayNameCtrl.text = d['name'] ?? user.displayName ?? '';
        _newPhoneCtrl.text = d['phone'] ?? '';
        _specialtyCtrl.text = d['specialty'] ?? '';
        _countryCtrl.text = d['country'] ?? 'Ghana';
        _bioCtrl.text = d['bio'] ?? '';
        _priceShortCtrl.text = d['priceShort']?.toString() ?? '';
        _priceLongCtrl.text = d['priceLong']?.toString() ?? '';
        _workHoursCtrl.text = d['workHours']?.toString() ?? '';
        availability = d['availability'] ?? 'Available';
        _latCtrl.text = d['lat']?.toString() ?? '';
        _lngCtrl.text = d['lng']?.toString() ?? '';
        _gpsNameCtrl.text = d['gpsActualName'] ?? '';
        docUrls = {
          'cv': d['cvUrl'] ?? '', 'video': d['videoUrl'] ?? '',
          'certificate': d['certificateUrl'] ?? '', 'license': d['licenseUrl'] ?? '',
        };
      });
    }
  }

  Future<void> _syncToCEO(String uid, Map<String, dynamic> data) async {
    try {
      final base = {...data, 'updatedAt': DateTime.now().millisecondsSinceEpoch, 'settingsUpdatedAt': DateTime.now().millisecondsSinceEpoch, 'lastUpdate': DateTime.now().millisecondsSinceEpoch, 'profileUpdatedAt': DateTime.now().millisecondsSinceEpoch};
      final db = FirebaseDatabase.instance;
      await db.ref('nurses/$uid').update(base);
      await db.ref('nurse_registrations/$uid').update(base);
      await db.ref('pendingNurseRegistrations/$uid').update(base);
      await db.ref('nurseUsers/$uid').update(base).catchError((_) {});
      await db.ref('nurseProfiles/$uid').update(base).catchError((_) {});
      await db.ref('ceoNurseUpdates/$uid').set({...base, 'updatedBy': 'nurse-settings.dart', 'uid': uid});
      await db.ref('ceoRegistrationCenter/nurses/$uid').set(base);
      await db.ref('ceoBookingReceiverNurses/$uid').set(base);
    } catch (e) { debugPrint('CEO sync failed: $e'); }
  }

  void _toast(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _uploadPhoto() async {
    if (currentUser == null) { _toast(tr('nsLoginRequiredUpload')); return; }
    final res = await FilePicker.platform.pickFiles(type: FileType.image);
    if (res == null || res.files.single.path == null) { _toast(tr('nsSelectPhotoFirst')); return; }
    _toast(tr('nsUploadingPhoto'));
    try {
      final file = File(res.files.single.path!);
      final ref = FirebaseStorage.instance.ref('nurses/${currentUser!.uid}/photo_${DateTime.now().millisecondsSinceEpoch}_${res.files.single.name}');
      await ref.putFile(file);
      final url = await ref.getDownloadURL();
      await currentUser!.updatePhotoURL(url);
      await FirebaseDatabase.instance.ref('nurses/${currentUser!.uid}').update({'photo': url, 'photoUpdatedAt': DateTime.now().millisecondsSinceEpoch});
      await _syncToCEO(currentUser!.uid, {'photo': url, 'photoURL': url, 'photoUpdatedAt': DateTime.now().millisecondsSinceEpoch});
      setState(() => photoUrl = url);
      _toast(tr('nsPhotoUpdated'));
    } catch (e) { _toast('${tr('nsUploadFailed')}: $e'); }
  }

  Future<void> _uploadDoc(String type) async {
    if (currentUser == null) { _toast(tr('nsLoginRequired')); return; }
    final maxMB = type == 'video' ? 50 : 10;
    final fieldUrl = type == 'cv' ? 'cvUrl' : type == 'video' ? 'videoUrl' : type == 'certificate' ? 'certificateUrl' : 'licenseUrl';
    final fieldName = type == 'cv' ? 'cvName' : type == 'video' ? 'videoName' : type == 'certificate' ? 'certificateName' : 'licenseName';
    final res = await FilePicker.platform.pickFiles();
    if (res == null || res.files.single.path == null) { _toast('${tr('nsSelectFileFor')} $type'); return; }
    final file = File(res.files.single.path!);
    if (await file.length() > maxMB * 1024 * 1024) { _toast('${tr('nsFileTooLarge')} >$maxMB MB'); return; }
    try {
      final ref = FirebaseStorage.instance.ref('nurses/${currentUser!.uid}/${type}_${DateTime.now().millisecondsSinceEpoch}_${res.files.single.name}');
      final task = ref.putFile(file);
      task.snapshotEvents.listen((s) {
        final double pct = s.totalBytes > 0 ? (s.bytesTransferred / s.totalBytes).toDouble() : 0.0;
        setState(() => uploadProgress[type] = pct);
      });
      await task;
      final url = await ref.getDownloadURL();
      final updates = {fieldUrl: url, fieldName: res.files.single.name, '${fieldUrl}UpdatedAt': DateTime.now().millisecondsSinceEpoch};
      await FirebaseDatabase.instance.ref('nurses/${currentUser!.uid}').update(updates);
      await _syncToCEO(currentUser!.uid, updates);
      setState(() => docUrls[type] = url);
      _toast('${tr('nsDoc_' + type)} ${tr('nsUploadedCeoLive')}');
    } catch (e) { _toast('${tr('nsUploadFailed')}: $e'); }
  }

  Future<void> _changeEmail() async {
    final newEmail = _newEmailCtrl.text.trim();
    final pass = _emailPassCtrl.text.trim();
    if (newEmail.isEmpty) { _toast(tr('nsEnterNewEmail')); return; }
    if (currentUser == null) { _toast(tr('nsLoginRequired')); return; }
    if (pass.isEmpty) { _toast(tr('nsEnterCurrentPassConfirm')); return; }
    try {
      final cred = EmailAuthProvider.credential(email: currentUser!.email!, password: pass);
      await currentUser!.reauthenticateWithCredential(cred);
      await currentUser!.verifyBeforeUpdateEmail(newEmail);
      await FirebaseDatabase.instance.ref('nurses/${currentUser!.uid}').update({'email': newEmail});
      await _syncToCEO(currentUser!.uid, {'email': newEmail, 'emailUpdatedAt': DateTime.now().millisecondsSinceEpoch});
      _toast(tr('nsEmailUpdated'));
    } catch (e) { _toast('${tr('nsEmailChangeFailed')}: $e'); }
  }

  Future<void> _changePhone() async {
    final newPhone = _newPhoneCtrl.text.trim();
    final name = _displayNameCtrl.text.trim();
    if (currentUser == null) { _toast(tr('nsLoginRequired')); return; }
    if (newPhone.isEmpty && name.isEmpty) { _toast(tr('nsEnterPhoneOrName')); return; }
    try {
      final updates = <String, dynamic>{'updatedAt': DateTime.now().millisecondsSinceEpoch};
      if (newPhone.isNotEmpty) updates['phone'] = newPhone;
      if (name.isNotEmpty) updates['name'] = name;
      await FirebaseDatabase.instance.ref('nurses/${currentUser!.uid}').update(updates);
      await _syncToCEO(currentUser!.uid, updates);
      if (name.isNotEmpty) await currentUser!.updateDisplayName(name);
      _toast(tr('nsPhoneNameUpdated'));
    } catch (e) { _toast('${tr('nsUpdateFailed')}: $e'); }
  }

  Future<void> _saveNurseInfo() async {
    if (currentUser == null) { _toast(tr('nsLoginRequired')); return; }
    final data = {'specialty': _specialtyCtrl.text.trim(), 'country': _countryCtrl.text, 'bio': _bioCtrl.text.trim(), 'priceShort': _priceShortCtrl.text.trim(), 'priceLong': _priceLongCtrl.text.trim(), 'workHours': _workHoursCtrl.text.trim(), 'availability': availability, 'updatedAt': DateTime.now().millisecondsSinceEpoch};
    try {
      await FirebaseDatabase.instance.ref('nurses/${currentUser!.uid}').update(data);
      await _syncToCEO(currentUser!.uid, data);
      _toast(tr('nsNurseInfoSaved'));
    } catch (e) { _toast('${tr('nsSaveFailed')}: $e'); }
  }

  Future<void> _getGPS() async {
    _gpsNameCtrl.text = tr('nsLocating');
    try {
      final perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) { _gpsNameCtrl.text = tr('nsEnableGps'); return; }
      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      setState(() { _latCtrl.text = pos.latitude.toStringAsFixed(6); _lngCtrl.text = pos.longitude.toStringAsFixed(6); _gpsNameCtrl.text = '${pos.latitude.toStringAsFixed(6)}, ${pos.longitude.toStringAsFixed(6)}'; });
    } catch (_) { _gpsNameCtrl.text = tr('nsEnableGps'); }
  }

  Future<void> _saveLocation() async {
    if (currentUser == null) { _toast(tr('nsLoginRequired')); return; }
    final lat = double.tryParse(_latCtrl.text);
    final lng = double.tryParse(_lngCtrl.text);
    if (lat == null || lng == null) { _toast(tr('nsGetGpsFirst')); return; }
    try {
      final data = {'lat': lat, 'lng': lng, 'gpsActualName': _gpsNameCtrl.text, 'updatedAt': DateTime.now().millisecondsSinceEpoch};
      await FirebaseDatabase.instance.ref('nurses/${currentUser!.uid}').update(data);
      await _syncToCEO(currentUser!.uid, data);
      _toast(tr('nsLocationSaved'));
    } catch (e) { _toast('${tr('nsSaveFailed')}: $e'); }
  }

  Future<void> _changePassword() async {
    final cur = _curPassCtrl.text.trim(), np = _newPassCtrl.text.trim(), cp = _confirmPassCtrl.text.trim();
    if (cur.isEmpty || np.isEmpty || cp.isEmpty) { _toast(tr('nsFillAllPassFields')); return; }
    if (np.length < 6) { _toast(tr('nsNewPassMin6')); return; }
    if (np != cp) { _toast(tr('nsPassNoMatch')); return; }
    if (currentUser == null) { _toast(tr('nsLoginRequired')); return; }
    try {
      final cred = EmailAuthProvider.credential(email: currentUser!.email!, password: cur);
      await currentUser!.reauthenticateWithCredential(cred);
      await currentUser!.updatePassword(np);
      _toast(tr('nsPasswordUpdated'));
    } catch (e) { _toast('${tr('nsPassChangeFailed')}: $e'); }
  }

  Future<void> _deleteAccount() async {
    final reason = deleteReason, pass = _deletePassCtrl.text.trim();
    if (reason.isEmpty) { _toast(tr('nsSelectReason')); return; }
    if (!confirmCheck || !confirmData) { _toast(tr('nsCheckBothBoxes')); return; }
    if (pass.isEmpty) { _toast(tr('nsEnterPassword')); return; }
    if (currentUser == null) { _toast(tr('nsLoginRequired')); return; }
    final confirm = await showDialog<bool>(context: context, builder: (_) => AlertDialog(title: Text('${tr('nsDeleteForReason')}: $reason?'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('nsCancel'))), ElevatedButton(onPressed: () => Navigator.pop(context, true), child: Text(tr('nsDelete')))]));
    if (confirm != true) return;
    try {
      final cred = EmailAuthProvider.credential(email: currentUser!.email!, password: pass);
      await currentUser!.reauthenticateWithCredential(cred);
      await FirebaseDatabase.instance.ref('deletedNurses/${currentUser!.uid}').set({'email': currentUser!.email, 'reason': reason, 'details': _deleteDetailsCtrl.text, 'deletedAt': DateTime.now().millisecondsSinceEpoch});
      await FirebaseDatabase.instance.ref('nurses/${currentUser!.uid}').remove().catchError((_) {});
      await currentUser!.delete();
      _toast(tr('nsAccountDeleted'));
      Future.delayed(const Duration(seconds: 2), () { if (mounted) Navigator.pushNamedAndRemoveUntil(context, '/', (_) => false); });
    } catch (e) { _toast('${tr('nsDeleteFailed')}: $e'); }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E0A1C),
      appBar: AppBar(title: Text(tr('nsTitle'), style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)), backgroundColor: const Color(0xFF1A1633), actions: [DropdownButtonHideUnderline(child: DropdownButton<String>(value: LanguageService.instance.locale.languageCode, dropdownColor: const Color(0xFF0C0A1E), icon: const Icon(Icons.language, color: Colors.white, size: 24), items: LanguageService.languageNames.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, style: const TextStyle(color: Colors.black)))).toList(), onChanged: (v) { if (v != null) LanguageService.instance.setLanguage(v); })), TextButton(onPressed: () {}, child: const Text('SOS', style: TextStyle(color: Colors.white)))]),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(children: [
          // Photo
          _card(tr('nsProfilePhoto'), Column(children: [
            CircleAvatar(radius: 40, backgroundImage: photoUrl != null && photoUrl!.isNotEmpty ? NetworkImage(photoUrl!) : null, child: photoUrl == null || photoUrl!.isEmpty ? const Icon(Icons.person, size: 40) : null),
            const SizedBox(height: 10),
            ElevatedButton(onPressed: _uploadPhoto, child: Text(tr('nsUploadNewPhoto'))),
            Text(currentUser == null ? tr('nsNotLoggedIn') : '${tr('nsLoggedInAs')} ${currentUser!.email}', style: const TextStyle(color: Colors.white60, fontSize: 11)),
          ])),
          // Docs
          _card(tr('nsDocuments'), Column(children: [
            for (final type in ['cv','video','certificate','license']) ...[
              ListTile(title: Text(tr('nsDoc_' + type)), subtitle: Text(docUrls[type]?.isNotEmpty == true ? tr('nsUploaded') : tr('nsNotUploadedYet'))),
              if (uploadProgress[type] != null) LinearProgressIndicator(value: uploadProgress[type]),
              ElevatedButton(onPressed: () => _uploadDoc(type), child: Text('${tr('nsUpload')} ${tr('nsDoc_' + type)} ${type == 'video' ? '(max 50MB)' : '(max 10MB)'}')),
              const SizedBox(height: 8),
            ],
          ])),
          // Email
          _card(tr('nsChangeEmail'), Column(children: [
            Text('${tr('nsCurrent')}: ${currentUser?.email ?? ''}', style: const TextStyle(color: Colors.white60, fontSize: 12)),
            TextField(controller: _newEmailCtrl, decoration: InputDecoration(labelText: tr('nsNewEmail'), border: OutlineInputBorder())),
            const SizedBox(height: 8),
            TextField(controller: _emailPassCtrl, obscureText: true, decoration: InputDecoration(labelText: tr('nsCurrentPassConfirm'), border: OutlineInputBorder())),
            const SizedBox(height: 8),
            SizedBox(width: double.infinity, child: ElevatedButton(onPressed: _changeEmail, child: Text(tr('nsChangeEmailBtn')))),
          ])),
          // Phone + Name
          _card(tr('nsPhoneName'), Column(children: [
            TextField(controller: _displayNameCtrl, decoration: InputDecoration(labelText: tr('nsDisplayName'), border: OutlineInputBorder())),
            const SizedBox(height: 8),
            TextField(controller: _newPhoneCtrl, decoration: InputDecoration(labelText: tr('nsNewPhone'), border: OutlineInputBorder())),
            const SizedBox(height: 8),
            SizedBox(width: double.infinity, child: ElevatedButton(onPressed: _changePhone, child: Text(tr('nsUpdatePhoneName')))),
          ])),
          // Nurse Info
          _card(tr('nsNurseInfo'), Column(children: [
            TextField(controller: _specialtyCtrl, decoration: InputDecoration(labelText: tr('nsSpecialty'), border: OutlineInputBorder())),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(value: _countryCtrl.text.isEmpty ? 'Ghana' : _countryCtrl.text, decoration: InputDecoration(labelText: tr('nsCountry'), border: OutlineInputBorder()), items: [DropdownMenuItem(value: 'Ghana', child: Text(tr('nsCountry_Ghana'))), DropdownMenuItem(value: 'USA', child: Text(tr('nsCountry_USA'))), DropdownMenuItem(value: 'UK', child: Text(tr('nsCountry_UK'))), DropdownMenuItem(value: 'Other', child: Text(tr('nsCountry_Other')))], onChanged: (v) => setState(() => _countryCtrl.text = v ?? 'Ghana')),
            const SizedBox(height: 8),
            TextField(controller: _bioCtrl, maxLines: 3, decoration: InputDecoration(labelText: tr('nsBio'), border: OutlineInputBorder())),
            const SizedBox(height: 8),
            Row(children: [Expanded(child: TextField(controller: _priceShortCtrl, decoration: InputDecoration(labelText: tr('nsPriceShort'), border: OutlineInputBorder()))), const SizedBox(width: 8), Expanded(child: TextField(controller: _priceLongCtrl, decoration: InputDecoration(labelText: tr('nsPriceLong'), border: OutlineInputBorder())))]),
            const SizedBox(height: 8),
            TextField(controller: _workHoursCtrl, decoration: InputDecoration(labelText: tr('nsWorkHours'), border: OutlineInputBorder())),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(value: availability, decoration: InputDecoration(labelText: tr('nsAvailability'), border: OutlineInputBorder()), items: [DropdownMenuItem(value: 'Available', child: Text(tr('nsAvail_Available'))), DropdownMenuItem(value: 'Busy', child: Text(tr('nsAvail_Busy'))), DropdownMenuItem(value: 'Offline', child: Text(tr('nsAvail_Offline')))], onChanged: (v) => setState(() => availability = v ?? 'Available')),
            const SizedBox(height: 8),
            SizedBox(width: double.infinity, child: ElevatedButton(onPressed: _saveNurseInfo, child: Text(tr('nsSaveNurseInfo')))),
          ])),
          // Location
          _card(tr('nsGpsLocation'), Column(children: [
            TextField(controller: _gpsNameCtrl, decoration: InputDecoration(labelText: tr('nsGpsLocationName'), border: OutlineInputBorder())),
            const SizedBox(height: 8),
            Row(children: [Expanded(child: TextField(controller: _latCtrl, decoration: InputDecoration(labelText: tr('nsLat'), border: OutlineInputBorder()))), const SizedBox(width: 8), Expanded(child: TextField(controller: _lngCtrl, decoration: InputDecoration(labelText: tr('nsLng'), border: OutlineInputBorder())))]),
            const SizedBox(height: 8),
            Row(children: [Expanded(child: ElevatedButton(onPressed: _getGPS, child: Text(tr('nsGetGps')))), const SizedBox(width: 8), Expanded(child: ElevatedButton(onPressed: _saveLocation, child: Text(tr('nsSaveLocation'))))]),
          ])),
          // Password
          _card(tr('nsChangePassword'), Column(children: [
            TextField(controller: _curPassCtrl, obscureText: true, decoration: InputDecoration(labelText: tr('nsCurrentPassword'), border: OutlineInputBorder())),
            const SizedBox(height: 8),
            TextField(controller: _newPassCtrl, obscureText: true, decoration: InputDecoration(labelText: tr('nsNewPasswordMin6'), border: OutlineInputBorder())),
            const SizedBox(height: 8),
            TextField(controller: _confirmPassCtrl, obscureText: true, decoration: InputDecoration(labelText: tr('nsConfirmNewPassword'), border: OutlineInputBorder())),
            const SizedBox(height: 8),
            SizedBox(width: double.infinity, child: ElevatedButton(onPressed: _changePassword, child: Text(tr('nsChangePasswordBtn')))),
          ])),
          // Delete
          _card(tr('nsDeleteAccount'), Column(children: [
            DropdownButtonFormField<String>(value: deleteReason.isEmpty ? null : deleteReason, decoration: InputDecoration(labelText: tr('nsReason'), border: OutlineInputBorder()), items: [DropdownMenuItem(value: 'Leaving', child: Text(tr('nsReason_Leaving'))), DropdownMenuItem(value: 'Not getting bookings', child: Text(tr('nsReason_Not getting bookings'))), DropdownMenuItem(value: 'Privacy', child: Text(tr('nsReason_Privacy'))), DropdownMenuItem(value: 'Other', child: Text(tr('nsReason_Other')))], onChanged: (v) => setState(() => deleteReason = v ?? '')),
            const SizedBox(height: 8),
            TextField(controller: _deleteDetailsCtrl, decoration: InputDecoration(labelText: tr('nsDetailsOptional'), border: OutlineInputBorder())),
            const SizedBox(height: 8),
            TextField(controller: _deletePassCtrl, obscureText: true, decoration: InputDecoration(labelText: tr('nsPasswordToConfirm'), border: OutlineInputBorder())),
            CheckboxListTile(title: Text(tr('nsUnderstandAccountDeleted'), style: TextStyle(fontSize: 12)), value: confirmCheck, onChanged: (v) => setState(() => confirmCheck = v ?? false)),
            CheckboxListTile(title: Text(tr('nsUnderstandDataRemoved'), style: TextStyle(fontSize: 12)), value: confirmData, onChanged: (v) => setState(() => confirmData = v ?? false)),
            SizedBox(width: double.infinity, child: ElevatedButton(onPressed: _deleteAccount, style: ElevatedButton.styleFrom(backgroundColor: Colors.red), child: Text(tr('nsDeleteAccountBtn')))),
          ])),
          const SizedBox(height: 20),
        ]),
      ),
    );
  }

  Widget _card(String title, Widget child) => Container(margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: const Color(0xFF1C1238), borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFA855F7).withOpacity(0.15))), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)), const SizedBox(height: 10), child]));
}
