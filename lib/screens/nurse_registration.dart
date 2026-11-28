import 'dart:convert';
import 'dart:io' show File;
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:http/http.dart' as http;

import '../models/id_catalog.dart';
import '../services/language_service.dart';
import '../services/translations.dart';

class NurseRegistrationPage extends StatefulWidget {
  const NurseRegistrationPage({super.key});
  @override
  State<NurseRegistrationPage> createState() => _NurseRegistrationPageState();
}

class _NurseRegistrationPageState extends State<NurseRegistrationPage> {
  final _formKey = GlobalKey<FormState>();
  static const primary = Color(0xFF880E4F);
  static const primaryLight = Color(0xFFFDE7F0);
  static const greenStrong = Color(0xFF2E9E4A);

  final _fullNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _pinNumberController = TextEditingController();
  final _idNumberController = TextEditingController();
  final _licenceNumberController = TextEditingController();
  final _locationController = TextEditingController();
  double? _gpsLat;
  double? _gpsLng;
  bool _locating = false;

  String? _selectedCountry;
  IdTypeOption? _selectedIdType;
  String? _selectedSpecialty;
  String? _selectedExperience;
  bool _obscurePassword = true;

  String? _photoName; Uint8List? _photoBytes;
  String? _videoName; Uint8List? _videoBytes;
  String? _cvName; Uint8List? _cvBytes;
  String? _pinCardName; Uint8List? _pinCardBytes;
  String? _idFrontName; Uint8List? _idFrontBytes;
  String? _idBackName; Uint8List? _idBackBytes;
  String? _certificateName; Uint8List? _certificateBytes;
  String? _licenceName; Uint8List? _licenceBytes;

  final ImagePicker _picker = ImagePicker();
  String? _uploadStatus;

  bool _idCheckAttempted = false;
  bool _idCheckPassed = false;
  String? _idCheckMessage;
  List<String> _idCheckDetails = [];
  bool _isCheckingId = false;
  bool _isSubmitting = false;

  List<IdTypeOption> get _idTypesForCountry => IdCatalog.forCountry(_selectedCountry);

  int get _passwordStrength {
    final p = _passwordController.text;
    int score = 0;
    if (p.length >= 8) score++;
    if (RegExp(r'[A-Z]').hasMatch(p)) score++;
    if (RegExp(r'[a-z]').hasMatch(p)) score++;
    if (RegExp(r'[0-9]').hasMatch(p)) score++;
    if (RegExp(r'[!@#$%^&*(),.?":{}|<>]').hasMatch(p)) score++;
    return score;
  }

  String get _passwordLabel {
    switch (_passwordStrength) {
      case 0:
      case 1:
        return tr('nrWeak');
      case 2:
      case 3:
        return tr('nrMedium');
      case 4:
        return tr('nrStrong');
      default:
        return tr('nrVeryStrong');
    }
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _pinNumberController.dispose();
    _idNumberController.dispose();
    _licenceNumberController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  void _onCountryChanged(String? country) {
    setState(() {
      _selectedCountry = country;
      _selectedIdType = null;
      _idNumberController.clear();
      _idFrontName = null; _idFrontBytes = null;
      _idBackName = null; _idBackBytes = null;
      _idCheckAttempted = false;
      _idCheckPassed = false;
      _idCheckMessage = null;
      _idCheckDetails = [];
    });
  }

  void _onIdTypeChanged(IdTypeOption? type) {
    setState(() {
      _selectedIdType = type;
      _idNumberController.clear();
      _idFrontName = null; _idFrontBytes = null;
      _idBackName = null; _idBackBytes = null;
      _idCheckAttempted = false;
      _idCheckPassed = false;
      _idCheckMessage = null;
      _idCheckDetails = [];
    });
  }

  Future<void> _pickFile(String kind) async {
    try {
      Uint8List? bytes;
      String? name;
      if (kind == 'photo' || kind == 'pin') {
        final XFile? picked = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
        if (picked == null) return;
        bytes = await picked.readAsBytes();
        name = picked.name;
      } else if (kind == 'video') {
        final XFile? picked = await _picker.pickVideo(source: ImageSource.gallery);
        if (picked == null) return;
        bytes = await picked.readAsBytes();
        name = picked.name;
      } else {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png'],
          withData: true,
        );
        if (result == null || result.files.isEmpty) return;
        final file = result.files.first;
        bytes = file.bytes;
        name = file.name;
      }
      if (bytes == null || bytes.isEmpty) {
        _showError(tr('nrCouldNotReadFile'));
        return;
      }
      if (kind == 'video' && bytes.length > 100 * 1024 * 1024) {
        _showError(tr('nrVideoTooLarge'));
        return;
      }
      setState(() {
        switch (kind) {
          case 'photo': _photoName = name; _photoBytes = bytes; break;
          case 'video': _videoName = name; _videoBytes = bytes; break;
          case 'cv': _cvName = name; _cvBytes = bytes; break;
          case 'pin': _pinCardName = name; _pinCardBytes = bytes; break;
          case 'cert': _certificateName = name; _certificateBytes = bytes; break;
          case 'licence': _licenceName = name; _licenceBytes = bytes; break;
        }
        _uploadStatus = null;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$kind ${tr('nrSelectedWord')}: $name')));
      }
    } catch (e) {
      _showError('${tr('nrPickerFailed')}: $e');
    }
  }

  Future<void> _scanId(String side) async {
    if (_selectedCountry == null || _selectedIdType == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('nrPickCountryTypeFirst'))));
      return;
    }
    try {
      final XFile? picked = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      setState(() {
        if (side == 'front') { _idFrontName = picked.name; _idFrontBytes = bytes; }
        else { _idBackName = picked.name; _idBackBytes = bytes; }
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${tr('nrScanned')} $side ${tr('nrOf')} ${_selectedIdType!.label} ($_selectedCountry)')));
      }
    } catch (e) {
      _showError('${tr('nrIdScanFailed')}: $e');
    }
  }

  Future<void> _checkIdAgain() async {
    if (_selectedCountry == null || _selectedIdType == null) return;
    if (_idNumberController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('nrEnterIdNumberFirst'))));
      return;
    }
    if (_idFrontName == null || _idFrontBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('nrScanFrontFirst'))));
      return;
    }
    setState(() { _idCheckAttempted = true; _isCheckingId = true; _idCheckMessage = tr('nrCheckingId'); _idCheckDetails = []; });
    try {
      final pattern = _selectedIdType!.pattern;
      final typed = _idNumberController.text.trim().toUpperCase();
      final formatOk = pattern == null || pattern.hasMatch(typed);
      final ocrText = await _ocrFromBytes(_idFrontBytes!);
      String norm(String s) => s.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
      final typedNorm = norm(typed);
      final ocrNorm = norm(ocrText);
      final typedDigits = typed.replaceAll(RegExp(r'[^0-9]'), '');
      final ocrDigits = ocrText.replaceAll(RegExp(r'[^0-9]'), '');
      final digitsMatch = typedDigits.length >= 6 && (ocrDigits.contains(typedDigits) || _containsMostInOrder(ocrDigits, typedDigits, 0.8));
      final fullMatch = typedNorm.isNotEmpty && ocrNorm.contains(typedNorm);
      setState(() {
        _idCheckPassed = formatOk && (fullMatch || digitsMatch);
        if (_idCheckPassed) {
          _idCheckMessage = tr('nrIdVerified');
          _idCheckDetails = ['✅ ${tr('nrFormatMatches')} ${_selectedIdType!.label} (${_selectedIdType!.example})', '✅ ${tr('nrNumberFoundOnPhoto')}'];
        } else if (!formatOk) {
          _idCheckMessage = _selectedIdType!.patternError ?? tr('nrIdFormatNoMatch');
          _idCheckDetails = ['❌ ${tr('nrFormatCheckFailed')}', '${tr('nrExpected')}: ${_selectedIdType!.example}'];
        } else if (ocrText.trim().isEmpty) {
          _idCheckMessage = tr('nrCouldNotReadIdPhoto');
          _idCheckDetails = ['❌ ${tr('nrNoTextOnPhoto')}', '${tr('nrTip')}: ${tr('nrFillFrameFlash')}'];
        } else {
          _idCheckMessage = tr('nrIdNumberMismatch');
          _idCheckDetails = ['❌ ${tr('nrTyped')}: $typed', '❌ ${tr('nrPhotoReadAs')}: ${ocrText.trim().split(RegExp(r'\s+')).take(12).join(' ')}'];
        }
      });
    } catch (e) {
      setState(() { _idCheckPassed = false; _idCheckMessage = '${tr('nrIdCheckFailed')}: $e. ${tr('nrTryRetakingPhoto')}'; _idCheckDetails = ['❌ ${tr('nrOcrError')}']; });
    } finally { if (mounted) setState(() => _isCheckingId = false); }
  }

  Future<String> _ocrFromBytes(Uint8List bytes) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/id_front_${DateTime.now().millisecondsSinceEpoch}.jpg');
    await file.writeAsBytes(bytes);
    try {
      final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
      try { final result = await recognizer.processImage(InputImage.fromFilePath(file.path)); return result.text; }
      finally { await recognizer.close(); }
    } finally { try { await file.delete(); } catch (_) {} }
  }

  bool _containsMostInOrder(String haystack, String needle, double ratio) {
    int found = 0, pos = 0;
    for (int i = 0; i < needle.length; i++) { final idx = haystack.indexOf(needle[i], pos); if (idx == -1) continue; found++; pos = idx + 1; }
    return needle.isNotEmpty && (found / needle.length) >= ratio;
  }

  String _contentTypeFor(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.mp4') || lower.endsWith('.mov')) return 'video/mp4';
    if (lower.endsWith('.png')) return 'image/png';
    return 'image/jpeg';
  }

  String _safeFileName(String name) => name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');

  Future<String> _uploadFile({required String folder, required String fileName, required Uint8List bytes, required String uid}) async {
    final safe = _safeFileName(fileName);
    final ref = FirebaseStorage.instance.ref('nurses/$uid/$folder/$safe');
    final task = await ref.putData(bytes, SettableMetadata(contentType: _contentTypeFor(safe)));
    return task.ref.getDownloadURL();
  }

  String _placeNameFromPlacemark(Placemark p) {
    final parts = <String>[];
    void add(String? v) {
      final s = (v ?? '').trim();
      if (s.isNotEmpty && !parts.contains(s)) parts.add(s);
    }
    add(p.subLocality);
    add(p.locality);
    add(p.subAdministrativeArea);
    add(p.administrativeArea);
    add(p.country);
    return parts.join(', ');
  }

  Future<String> _placeNameFromWeb(double lat, double lng) async {
    String joinParts(List<String?> values) {
      final parts = <String>[];
      for (final v in values) {
        final s = (v ?? '').trim();
        if (s.isNotEmpty && !parts.contains(s)) parts.add(s);
      }
      return parts.join(', ');
    }
    try {
      final uri = Uri.parse('https://api.bigdatacloud.net/data/reverse-geocode-client?latitude=$lat&longitude=$lng&localityLanguage=en');
      final res = await http.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final j = jsonDecode(res.body) as Map<String, dynamic>;
        final name = joinParts([j['locality']?.toString(), j['city']?.toString(), j['principalSubdivision']?.toString(), j['countryName']?.toString()]);
        if (name.isNotEmpty) return name;
      }
    } catch (_) {}
    try {
      final uri = Uri.parse('https://nominatim.openstreetmap.org/reverse?format=json&lat=$lat&lon=$lng&zoom=18&addressdetails=1');
      final res = await http.get(uri, headers: {'Accept': 'application/json'}).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final j = jsonDecode(res.body) as Map<String, dynamic>;
        final addr = (j['address'] as Map<String, dynamic>?) ?? {};
        final name = joinParts([addr['suburb']?.toString() ?? addr['neighbourhood']?.toString(), addr['city']?.toString() ?? addr['town']?.toString() ?? addr['village']?.toString(), addr['state']?.toString(), addr['country']?.toString()]);
        if (name.isNotEmpty) return name;
        final display = (j['display_name'] ?? '').toString().trim();
        if (display.isNotEmpty) return display;
      }
    } catch (_) {}
    return '';
  }

  Future<void> _pickLiveGps() async {
    if (_locating) return;
    setState(() { _locating = true; });
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showError(tr('nrTurnOnLocationFirst'));
        await Geolocator.openLocationSettings();
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.deniedForever) {
        _showError(tr('nrLocationBlocked'));
        await Geolocator.openAppSettings();
        return;
      }
      if (perm == LocationPermission.denied) {
        _showError(tr('nrLocationDenied'));
        return;
      }
      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high, timeLimit: const Duration(seconds: 20));
      _gpsLat = pos.latitude;
      _gpsLng = pos.longitude;
      String place = '';
      try {
        final marks = await placemarkFromCoordinates(pos.latitude, pos.longitude);
        if (marks.isNotEmpty) place = _placeNameFromPlacemark(marks.first);
      } catch (_) {}
      if (place.isEmpty) { place = await _placeNameFromWeb(pos.latitude, pos.longitude); }
      if (place.isEmpty) { place = 'Lat ${pos.latitude.toStringAsFixed(5)}, Lng ${pos.longitude.toStringAsFixed(5)}'; }
      if (!mounted) return;
      setState(() { _locationController.text = place; });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${tr('nrLocationPicked')}: $place')));
    } catch (e) {
      _showError('${tr('nrCouldNotGetGps')}: $e');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<String?> _checkEmailNotUsedAsClient(String email) async {
    final lower = email.trim().toLowerCase();
    try {
      final q = await FirebaseFirestore.instance.collection('clients').where('email', isEqualTo: lower).limit(1).get();
      if (q.docs.isNotEmpty) return tr('nrEmailIsClient');
      final q2 = await FirebaseFirestore.instance.collection('clients').where('email', isEqualTo: email.trim()).limit(1).get();
      if (q2.docs.isNotEmpty) return tr('nrEmailIsClientShort');
    } catch (_) {}
    return null;
  }

  Future<void> _deleteLeftoverAuthIfNoProfile() async {
    try {
      final u = FirebaseAuth.instance.currentUser;
      if (u == null) return;
      final uid = u.uid;
      final inNurses = await FirebaseFirestore.instance.collection('nurses').doc(uid).get();
      final inPending = await FirebaseFirestore.instance.collection('pending_nurses').doc(uid).get();
      final inClients = await FirebaseFirestore.instance.collection('clients').doc(uid).get();
      if (!inNurses.exists && !inPending.exists && !inClients.exists) {
        await u.delete().catchError((_) async { await FirebaseAuth.instance.signOut(); });
      }
    } catch (_) {}
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      _showError(tr('nrFillAllRequired'));
      return;
    }
    final roleBlock = await _checkEmailNotUsedAsClient(_emailController.text.trim());
    if (roleBlock != null) { _showError(roleBlock); return; }
    if (!_idCheckPassed) {
      _showError(tr('nrTapCheckIdFirst'));
      return;
    }
    if (_photoBytes == null) return _showError(tr('nrPickPhoto'));
    if (_cvBytes == null) return _showError(tr('nrPickCv'));
    if (_pinCardBytes == null) return _showError(tr('nrPickPinCard'));
    if (_idFrontBytes == null || _idBackBytes == null) return _showError(tr('nrScanFrontBack'));
    if (_certificateBytes == null) return _showError(tr('nrPickCertificate'));
    if (_licenceBytes == null) return _showError(tr('nrPickLicence'));
    if (_licenceNumberController.text.trim().isEmpty) return _showError(tr('nrEnterLicenceNumber'));
    if (_pinNumberController.text.trim().isEmpty) return _showError(tr('nrEnterPinNumber'));

    setState(() { _isSubmitting = true; _uploadStatus = tr('nrCreatingAccount'); });
    try {
      User? user = FirebaseAuth.instance.currentUser;
      final lowerEmail = _emailController.text.trim().toLowerCase();
      if (user == null || user.email?.toLowerCase() != lowerEmail) {
        try {
          final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(email: lowerEmail, password: _passwordController.text);
          user = cred.user;
        } on FirebaseAuthException catch (e) {
          if (e.code == 'email-already-in-use') {
            try {
              final signIn = await FirebaseAuth.instance.signInWithEmailAndPassword(email: lowerEmail, password: _passwordController.text);
              final uid2 = signIn.user!.uid;
              final inN = await FirebaseFirestore.instance.collection('nurses').doc(uid2).get();
              final inP = await FirebaseFirestore.instance.collection('pending_nurses').doc(uid2).get();
              final inC = await FirebaseFirestore.instance.collection('clients').doc(uid2).get();
              if (!inN.exists && !inP.exists && !inC.exists) {
                await signIn.user!.delete();
                final cred2 = await FirebaseAuth.instance.createUserWithEmailAndPassword(email: lowerEmail, password: _passwordController.text);
                user = cred2.user;
              } else {
                await FirebaseAuth.instance.signOut();
                _showError(tr('nrEmailAlreadyRegistered'));
                return;
              }
            } catch (_) {
              await FirebaseAuth.instance.signOut();
              _showError(tr('nrEmailAlreadyRegistered'));
              return;
            }
          } else { rethrow; }
        }
      }
      final uid = user!.uid;
      setState(() => _uploadStatus = tr('nrUploadingDocs'));
      final photoUrl = await _uploadFile(folder: 'photo', fileName: _photoName!, bytes: _photoBytes!, uid: uid);
      final cvUrl = await _uploadFile(folder: 'cv', fileName: _cvName!, bytes: _cvBytes!, uid: uid);
      final pinUrl = await _uploadFile(folder: 'pin', fileName: _pinCardName!, bytes: _pinCardBytes!, uid: uid);
      final idFrontUrl = await _uploadFile(folder: 'id_front', fileName: _idFrontName!, bytes: _idFrontBytes!, uid: uid);
      final idBackUrl = await _uploadFile(folder: 'id_back', fileName: _idBackName!, bytes: _idBackBytes!, uid: uid);
      final certUrl = await _uploadFile(folder: 'certificate', fileName: _certificateName!, bytes: _certificateBytes!, uid: uid);
      final licenceUrl = await _uploadFile(folder: 'licence', fileName: _licenceName!, bytes: _licenceBytes!, uid: uid);
      String videoUrl = '';
      if (_videoBytes != null && _videoName != null) {
        videoUrl = await _uploadFile(folder: 'video', fileName: _videoName!, bytes: _videoBytes!, uid: uid);
      }
      setState(() => _uploadStatus = tr('nrSavingRegistration'));
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final data = {
        'uid': uid,
        'fullName': _fullNameController.text.trim(),
        'name': _fullNameController.text.trim(),
        'email': _emailController.text.trim().toLowerCase(),
        'phone': _phoneController.text.trim(),
        'location': _locationController.text.trim(), 'placeName': _locationController.text.trim(), 'address': _locationController.text.trim(),
        'latitude': _gpsLat, 'longitude': _gpsLng, 'gpsLat': _gpsLat, 'gpsLng': _gpsLng, 'locationLat': _gpsLat, 'locationLng': _gpsLng,
        'pinNumber': _pinNumberController.text.trim(),
        'pin': _pinNumberController.text.trim(),
        'country': _selectedCountry,
        'workCountry': _selectedCountry, 'residenceCountry': _selectedCountry,
        'countryCode': IdCatalog.dialCodeFor(_selectedCountry) ?? '', 'dialCode': IdCatalog.dialCodeFor(_selectedCountry) ?? '',
        'idType': _selectedIdType?.label,
        'idNumber': _idNumberController.text.trim(),
        'idNo': _idNumberController.text.trim(),
        'licenceNumber': _licenceNumberController.text.trim(),
        'licenseNumber': _licenceNumberController.text.trim(),
        'licenceNo': _licenceNumberController.text.trim(),
        'licenseNo': _licenceNumberController.text.trim(),
        'specialty': _selectedSpecialty,
        'experience': _selectedExperience,
        'photoUrl': photoUrl, 'photo': photoUrl, 'photoURL': photoUrl, 'profilePhoto': photoUrl,
        'videoUrl': videoUrl, 'video': videoUrl, 'videoURL': videoUrl,
        'cvUrl': cvUrl, 'cv': cvUrl, 'cvURL': cvUrl,
        'pinCardUrl': pinUrl, 'pinUrl': pinUrl, 'pinCard': pinUrl,
        'idFrontUrl': idFrontUrl, 'idBackUrl': idBackUrl,
        'idUrl': idFrontUrl, 'idCardUrl': idFrontUrl, 'idFront': idFrontUrl, 'idBack': idBackUrl,
        'idCardFrontUrl': idFrontUrl, 'idCardBackUrl': idBackUrl,
        'certificateUrl': certUrl, 'certUrl': certUrl, 'certificate': certUrl, 'cert': certUrl,
        'licenceUrl': licenceUrl, 'licenseUrl': licenceUrl, 'licence': licenceUrl, 'license': licenceUrl,
        'idCheckPassed': _idCheckPassed,
        'idVerified': _idCheckPassed,
        'role': 'nurse',
        'type': 'nurse',
        'status': 'pending',
        'approvalStatus': 'pending',
        'approved': false,
        'isApproved': false,
        'canLogin': false,
        'isComplete': true,
        'hasAll4': true,
        'hasPhoto': true,
        'hasVideo': _videoBytes != null,
        'hasPhone': true,
        'hasCv': true,
        'hasPinCard': true,
        'hasPin': true,
        'hasId': true,
        'hasCertificate': true,
        'hasCert': true,
        'hasLicence': true,
        'hasLicense': true,
        'createdAt': FieldValue.serverTimestamp(),
      };
      final rtdbData = Map<String, dynamic>.from(data);
      rtdbData['createdAt'] = nowMs;
      rtdbData['time'] = nowMs;
      rtdbData['timestamp'] = nowMs;
      final db = FirebaseFirestore.instance;
      await db.collection('nurses').doc(uid).set(data, SetOptions(merge: true));
      await db.collection('nurse_registrations').doc(uid).set(data, SetOptions(merge: true));
      await db.collection('ceo_registration').doc(uid).set(data, SetOptions(merge: true));
      await db.collection('pending_nurses').doc(uid).set(data, SetOptions(merge: true));
      try {
        final rtdb = FirebaseDatabase.instance;
        await rtdb.ref('nurses/$uid').set(rtdbData);
        await rtdb.ref('nurse_registrations/$uid').set(rtdbData);
        await rtdb.ref('ceo_registration/$uid').set(rtdbData);
        await rtdb.ref('pending_nurses/$uid').set(rtdbData);
        await rtdb.ref('ceoRegistration/$uid').set(rtdbData);
      } catch (_) {}
      if (!mounted) return;
      setState(() => _uploadStatus = null);
      try { await FirebaseAuth.instance.signOut(); } catch (_) {}
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => PendingApprovalPage(name: _fullNameController.text.trim(), email: _emailController.text.trim())));
    } on FirebaseAuthException catch (e) {
      await _deleteLeftoverAuthIfNoProfile();
      _showError(e.message ?? '${tr('nrSignUpFailed')} (${e.code})');
    } on FirebaseException catch (e) {
      await _deleteLeftoverAuthIfNoProfile();
      _showError('${tr('nrUploadFailed')} (${e.code}): ${e.message}');
      if (kIsWeb) debugPrint('Firebase upload error: $e');
    } catch (e) {
      await _deleteLeftoverAuthIfNoProfile();
      _showError('${tr('nrUploadFailed')}: $e');
    } finally {
      if (mounted) setState(() { _isSubmitting = false; _uploadStatus = null; });
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red, duration: const Duration(seconds: 4)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: primary,
        title: Text(tr('nrTitle')),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)),
        actions: [DropdownButtonHideUnderline(child: DropdownButton<String>(value: LanguageService.instance.locale.languageCode, dropdownColor: const Color(0xFF0C0A1E), icon: const Icon(Icons.language, color: Colors.white, size: 24), items: LanguageService.languageNames.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, style: const TextStyle(color: Colors.black)))).toList(), onChanged: (v) { if (v != null) LanguageService.instance.setLanguage(v); }))],
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionTitle(tr('nrPersonalDetails')),
              _textField(controller: _fullNameController, label: tr('nrFullName'), hint: tr('nrFullNameHint'), validator: (v) => (v == null || v.trim().isEmpty) ? tr('nrEnterFullName') : null),
              _textField(controller: _emailController, label: tr('nrEmail'), hint: tr('nrEmailHint'), keyboardType: TextInputType.emailAddress, validator: (v) { if (v == null || v.isEmpty) return tr('nrEnterEmail'); if (!v.contains('@')) return tr('nrEnterValidEmail'); return null; }),
              _textField(controller: _phoneController, label: tr('nrPhone'), hint: tr('nrPhoneHint'), keyboardType: TextInputType.phone, validator: (v) => (v == null || v.isEmpty) ? tr('nrEnterPhone') : null),
              _sectionTitle(tr('nrYourLocation')),
              TextFormField(controller: _locationController, readOnly: true, decoration: InputDecoration(labelText: tr('nrLocationLiveGps'), hintText: tr('nrLocationHint'), prefixIcon: Icon(Icons.location_on))),
              const SizedBox(height: 8),
              SizedBox(width: double.infinity, child: ElevatedButton.icon(onPressed: _locating ? null : _pickLiveGps, icon: const Icon(Icons.my_location), label: Text(_locating ? tr('nrGettingGps') : tr('nrPickLiveGps')))),
              if (_gpsLat != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text('GPS: ${_gpsLat!.toStringAsFixed(5)}, ${_gpsLng!.toStringAsFixed(5)} - ${tr('nrTapAgainRepick')}', style: TextStyle(fontSize: 12, color: Colors.grey))),
              Padding(padding: EdgeInsets.only(top: 4), child: Text(tr('nrTurnOnGpsNote'), style: TextStyle(fontSize: 12, color: Colors.grey))),
              const SizedBox(height: 8),
              _sectionTitle(tr('nrPassword')),
              TextFormField(controller: _passwordController, obscureText: _obscurePassword, onChanged: (_) => setState(() {}), decoration: InputDecoration(labelText: tr('nrPassword'), suffixIcon: IconButton(icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility), onPressed: () => setState(() => _obscurePassword = !_obscurePassword))), validator: (v) { if (v == null || v.length < 8) return tr('nrPasswordMin8'); return null; }),
              const SizedBox(height: 8),
              Row(children: [Expanded(child: LinearProgressIndicator(value: _passwordStrength / 5, backgroundColor: Colors.grey.shade300, color: _passwordStrength >= 4 ? greenStrong : Colors.orange, minHeight: 6)), const SizedBox(width: 12), Text(_passwordLabel, style: TextStyle(color: _passwordStrength >= 4 ? greenStrong : Colors.orange, fontWeight: FontWeight.bold))]),
              if (_passwordStrength >= 4) Padding(padding: EdgeInsets.only(top: 6), child: Row(children: [Icon(Icons.check_circle, color: greenStrong, size: 18), SizedBox(width: 6), Text(tr('nrStrongPasswordCheck'), style: TextStyle(color: greenStrong))])),
              _sectionTitle(tr('nrDocuments')),
              _fileRow(icon: Icons.photo, label: tr('nrPhoto'), fileName: _photoName, buttonText: tr('nrPickPhotoBtn'), onPick: () => _pickFile('photo')),
              _fileRow(icon: Icons.videocam, label: tr('nrVideo'), fileName: _videoName, buttonText: tr('nrPickVideoBtn'), onPick: () => _pickFile('video')),
              _fileRow(icon: Icons.description, label: tr('nrCv'), fileName: _cvName, buttonText: tr('nrPickCvBtn'), onPick: () => _pickFile('cv')),
              _sectionTitle(tr('nrNursingPin')),
              _textField(controller: _pinNumberController, label: tr('nrNursingPinNumber'), hint: tr('nrNursingPinHint'), validator: (v) => (v == null || v.isEmpty) ? tr('nrEnterPinNumber') : null),
              _fileRow(icon: Icons.badge, label: tr('nrPinCard'), fileName: _pinCardName, buttonText: tr('nrPickPinBtn'), onPick: () => _pickFile('pin')),
              _sectionTitle(tr('nrIdVerification')),
              DropdownButtonFormField<String>(value: _selectedCountry, decoration: InputDecoration(labelText: tr('nrIdCountry')), items: IdCatalog.countries.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(), onChanged: _onCountryChanged, validator: (v) => v == null ? tr('nrSelectIdCountry') : null),
              const SizedBox(height: 16),
              DropdownButtonFormField<IdTypeOption>(value: _selectedIdType, decoration: InputDecoration(labelText: tr('nrIdType'), hintText: _selectedCountry == null ? tr('nrSelectIdCountryFirst') : tr('nrSelectYourId')), items: _idTypesForCountry.map((t) => DropdownMenuItem(value: t, child: Text(t.label))).toList(), onChanged: _selectedCountry == null ? null : _onIdTypeChanged, validator: (v) => v == null ? tr('nrSelectIdType') : null),
              if (_selectedCountry != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text('${tr('nrShowingIdsFor')} $_selectedCountry • ${_idTypesForCountry.length} ${tr('nrOptions')} • ${tr('nrPassportNote')}', style: TextStyle(color: Colors.grey.shade600, fontSize: 12))),
              const SizedBox(height: 16),
              TextFormField(controller: _idNumberController, enabled: _selectedIdType != null, textCapitalization: TextCapitalization.characters, decoration: InputDecoration(labelText: tr('nrIdNumber'), hintText: _selectedIdType?.hint ?? tr('nrPickCountryTypeFirst'), helperText: _selectedIdType != null ? '${tr('nrExample')}: ${_selectedIdType!.example}' : null), validator: (v) { if (v == null || v.trim().isEmpty) return tr('nrEnterIdNumber'); final pattern = _selectedIdType?.pattern; if (pattern != null && !pattern.hasMatch(v.trim())) return _selectedIdType?.patternError ?? '${tr('nrInvalidFormat')} ${tr('nrExample')}: ${_selectedIdType!.example}'; return null; }),
              const SizedBox(height: 8),
              Text(tr('nrIdAutoScanned'), style: TextStyle(color: Colors.grey, fontSize: 12)),
              const SizedBox(height: 16),
              _fileRow(icon: Icons.credit_card, label: tr('nrUploadIdFront'), fileName: _idFrontName, subLabel: _selectedIdType == null ? tr('nrPickCountryTypeFirst') : '${tr('nrFrontOf')} ${_selectedIdType!.label}', buttonText: tr('nrScanFront'), onPick: () => _scanId('front'), buttonEnabled: _selectedIdType != null),
              _fileRow(icon: Icons.credit_card, label: tr('nrUploadIdBack'), fileName: _idBackName, subLabel: _selectedIdType == null ? tr('nrAutoScanBoxFlash') : '${tr('nrBackOf')} ${_selectedIdType!.label} (${tr('nrRequired')})', buttonText: tr('nrScanBack'), onPick: () => _scanId('back'), buttonEnabled: _selectedIdType != null),
              _fileRow(icon: Icons.school, label: tr('nrUploadCertificate'), fileName: _certificateName, buttonText: tr('nrPickCertBtn'), onPick: () => _pickFile('cert')),
              _sectionTitle(tr('nrLicence')),
              _textField(controller: _licenceNumberController, label: tr('nrLicenceNumber'), hint: tr('nrLicenceHint'), validator: (v) => (v == null || v.isEmpty) ? tr('nrEnterLicenceNumber') : null),
              _fileRow(icon: Icons.card_membership, label: tr('nrUploadLicence'), fileName: _licenceName, buttonText: tr('nrPickLicenceBtn'), onPick: () => _pickFile('licence')),
              const SizedBox(height: 8),
              if (_idCheckAttempted && _idCheckMessage != null) Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: _idCheckPassed ? Colors.green.shade50 : Colors.orange.shade50, borderRadius: BorderRadius.circular(8)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(_idCheckPassed ? Icons.check_circle : Icons.close, color: _idCheckPassed ? Colors.green : Colors.orange), const SizedBox(width: 8), Expanded(child: Text(_idCheckMessage!, style: TextStyle(color: _idCheckPassed ? Colors.green.shade900 : Colors.orange.shade900, fontWeight: FontWeight.w600)))]), if (_idCheckDetails.isNotEmpty) ...[const SizedBox(height: 6), ..._idCheckDetails.map((c) => Padding(padding: const EdgeInsets.only(top: 2), child: Text(c, style: const TextStyle(fontSize: 12))))]])),
              const SizedBox(height: 16),
              SizedBox(width: double.infinity, height: 52, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: primary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), onPressed: (_selectedCountry != null && _selectedIdType != null && !_isCheckingId) ? _checkIdAgain : null, child: _isCheckingId ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : Text(tr('nrCheckMyIdAgain'), style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)))),
              _sectionTitle(tr('nrExperience')),
              DropdownButtonFormField<String>(value: _selectedSpecialty, decoration: InputDecoration(labelText: tr('nrSpecialty')), items: const ['General Nursing', 'Midwifery', 'ICU / Critical Care', 'Paediatric Nursing', 'Mental Health', 'Community Health', 'Emergency / A&E', 'Theatre / Surgical'].map((s) => DropdownMenuItem(value: s, child: Text(tr('nrSpec_' + s)))).toList(), onChanged: (v) => setState(() => _selectedSpecialty = v), validator: (v) => v == null ? tr('nrSelectSpecialty') : null),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(value: _selectedExperience, decoration: InputDecoration(labelText: tr('nrYearsExperience')), items: const ['0-1 years', '1-3 years', '3-5 years', '5-10 years', '10+ years'].map((s) => DropdownMenuItem(value: s, child: Text(tr('nrExp_' + s)))).toList(), onChanged: (v) => setState(() => _selectedExperience = v), validator: (v) => v == null ? tr('nrSelectExperience') : null),
              if (_uploadStatus != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: Row(children: [const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)), const SizedBox(width: 10), Expanded(child: Text(_uploadStatus!, style: const TextStyle(fontSize: 13)))])),
              const SizedBox(height: 28),
              SizedBox(width: double.infinity, height: 56, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: primary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))), onPressed: _isSubmitting ? null : _submit, child: _isSubmitting ? const CircularProgressIndicator(color: Colors.white) : Text(tr('nrSubmitRegistration'), style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)))),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(padding: const EdgeInsets.only(top: 20, bottom: 10), child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: primary)));
  }

  Widget _textField({required TextEditingController controller, required String label, required String hint, TextInputType? keyboardType, String? Function(String?)? validator}) {
    return Padding(padding: const EdgeInsets.only(bottom: 12), child: TextFormField(controller: controller, keyboardType: keyboardType, decoration: InputDecoration(labelText: label, hintText: hint), validator: validator));
  }

  Widget _fileRow({required IconData icon, required String label, required String buttonText, required VoidCallback onPick, String? fileName, String? subLabel, bool buttonEnabled = true}) {
    final hasFile = fileName != null;
    return Padding(padding: const EdgeInsets.only(bottom: 12), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(icon, color: primary, size: 28), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: const TextStyle(fontWeight: FontWeight.bold)), const SizedBox(height: 2), Text(hasFile ? fileName! : (subLabel ?? tr('nrNoFileSelected')), style: TextStyle(color: hasFile ? Colors.black87 : Colors.grey, fontSize: 13), maxLines: 2, overflow: TextOverflow.ellipsis)])), const SizedBox(width: 8), ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: primaryLight, foregroundColor: primary, elevation: 0), onPressed: buttonEnabled ? onPick : null, child: Text(buttonText))]));
  }
}

class PendingApprovalPage extends StatelessWidget {
  final String name;
  final String email;
  const PendingApprovalPage({super.key, required this.name, required this.email});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: const Color(0xFF880E4F), title: Text(tr('nrRegistrationSent'))),
      body: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.hourglass_top, size: 80, color: Color(0xFF880E4F)), const SizedBox(height: 20), Text('${tr('nrThankYou')}, $name!', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold), textAlign: TextAlign.center), const SizedBox(height: 12), Text(tr('nrPendingBody'), textAlign: TextAlign.center, style: TextStyle(fontSize: 16)), const SizedBox(height: 12), Text('${tr('nrSubmittedAs')}: $email', style: const TextStyle(color: Colors.grey)), const SizedBox(height: 28), SizedBox(width: double.infinity, height: 52, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF880E4F)), onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst), child: Text(tr('nrBackToLogin'), style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))))])),
    );
  }
}
