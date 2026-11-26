import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'staff_login.dart';
import '../services/language_service.dart';
import '../services/translations.dart';

/// Create Access - converted from ceo-create-access.html
/// CEO creates staff who can login to CEO Dashboard.
/// Staff get a USERNAME + STAFF PASSWORD. CEO sees Recent Staff Visits.
/// NEW: Staff Password field. This is the password the staff uses in CEO Login.
///
/// How to use (CEO only):
///   1. Enter staff Full Name + Phone + Email + Staff Password.
///   2. Tap Create. Staff is saved to:
///        ceoAllowedUsers/<phoneNorm>, ceoAccessList/<phoneNorm>,
///        ceoDashboardAccess/<phoneNorm>, allowedCEOs (push)
///   3. Give the staff their phone + name + staff password. They login in CEO Login.
///   4. To remove a staff: tap Delete next to their name. They can no longer login.
///      Deleting here removes them from ceoAllowedUsers / ceoAccessList /
///      ceoDashboardAccess. It does NOT delete their Firebase Auth account
///      (they never had one - login is phone + name + staff password, not Auth).
///
/// ⚠️ Security note: this stores the staff password in RTDB in plain text,
/// exactly like the HTML stored phone/name. Use STAFF-ONLY passwords -
/// never your personal email / bank / CEO password. If a staff leaves,
/// Delete them here AND change any password they knew.
///
/// NEVER BLANK: always shows form + list. Errors show in status box.
/// NO pushNamed for Go to Login: goes to CEOLoginPage directly.

class CEOCreateAccessPage extends StatefulWidget {
  const CEOCreateAccessPage({super.key});
  @override
  State<CEOCreateAccessPage> createState() => _CEOCreateAccessPageState();
}

class _CEOCreateAccessPageState extends State<CEOCreateAccessPage> {
  final _nameCtrl = TextEditingController();
  final _userCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _busy = false;
  bool _showPass = false;
  String? _status;
  bool _statusOk = false;
  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _visits = [];
  bool _loading = true;

  static FirebaseDatabase? _cachedDb;
  FirebaseDatabase get _db {
    _cachedDb ??= FirebaseDatabase.instance;
    return _cachedDb!;
  }

  @override
  void initState() {
    super.initState();
    _loadAccess();
    _loadVisits();
  }

  String _normPhone(String p) {
    final digits = p.replaceAll(RegExp(r'[^0-9]'), '');
    return digits.length > 10 ? digits.substring(digits.length - 10) : digits;
  }

  Future<void> _ensureAuth() async {
    try {
      if (FirebaseAuth.instance.currentUser == null) {
        await FirebaseAuth.instance.signInAnonymously();
      }
    } catch (_) {}
  }

  void _setStatus(String msg, bool ok) {
    if (!mounted) return;
    setState(() {
      _status = msg;
      _statusOk = ok;
    });
  }

  Future<void> _createAccess() async {
    final name = _nameCtrl.text.trim();
    final username = _userCtrl.text.trim().toLowerCase().replaceAll(' ', '.');
    final phone = _phoneCtrl.text.trim();
    final email = _emailCtrl.text.trim().toLowerCase();
    final pass = _passCtrl.text;
    if (username.isEmpty) {
      _setStatus(tr('enterUsernameStaff'), false);
      return;
    }
    if (name.isEmpty || phone.isEmpty) {
      _setStatus(tr('enterNamePhone'), false);
      return;
    }
    final phoneNorm = _normPhone(phone);
    if (phoneNorm.length < 9) {
      _setStatus(tr('enterValidPhone'), false);
      return;
    }
    if (pass.isEmpty) {
      _setStatus(tr('enterStaffPassword'), false);
      return;
    }
    if (pass.length < 4) {
      _setStatus(tr('staffPassMin4'), false);
      return;
    }
    setState(() => _busy = true);
    try {
      await _ensureAuth();
      // Username must be unique - two staffs cannot share one username
      final dup = await _db.ref('ceoAllowedUsers').get();
      if (dup.exists && dup.value is Map) {
        for (final v in (dup.value as Map).values) {
          if (v is Map && (v['username'] ?? '').toString().toLowerCase() == username) {
            _setStatus('${tr('usernameTaken1')} "$username" ${tr('usernameTaken2')}', false);
            if (mounted) setState(() => _busy = false);
            return;
          }
        }
      }
      final data = <String, Object?>{
        'username': username,
        'name': name,
        'fullName': name,
        'phone': phone,
        'phoneNorm': phoneNorm,
        'phoneNumber': phone,
        'email': email,
        // Staff password - the password staff uses to login to CEO Dashboard
        'password': pass,
        'staffPassword': pass,
        'role': 'staff',
        'createdAt': DateTime.now().millisecondsSinceEpoch,
        'isAllowed': true,
        'canAccessDashboard': true,
      };
      await _db.ref('ceoAllowedUsers/$phoneNorm').set(data);
      await _db.ref('ceoAccessList/$phoneNorm').set(data);
      await _db.ref('ceoDashboardAccess/$phoneNorm').set(data);
      await _db.ref('allowedCEOs').push().set(data);
      _setStatus('${tr('createdLabel')} - $name (${tr('usernameLabel')}: $username) ${tr('canNowLoginStaffPass')}', true);
      _nameCtrl.clear();
      _userCtrl.clear();
      _phoneCtrl.clear();
      _emailCtrl.clear();
      _passCtrl.clear();
      await _loadAccess();
    } catch (e) {
      _setStatus('${tr('createFailed')}: $e', false);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadVisits() async {
    try {
      await _ensureAuth();
      _db.ref('staffVisits').orderByChild('timestamp').limitToLast(20).onValue.listen((e) {
        final list = <Map<String, dynamic>>[];
        if (e.snapshot.exists && e.snapshot.value is Map) {
          (e.snapshot.value as Map).forEach((k, v) {
            if (v is Map) list.add({'id': k.toString(), ...Map<String, dynamic>.from(v)});
          });
        }
        list.sort((a, b) => ((b['timestamp'] ?? 0) as num).compareTo((a['timestamp'] ?? 0) as num));
        if (mounted) setState(() => _visits = list);
      });
    } catch (_) {}
  }

  Future<void> _loadAccess() async {
    if (mounted) setState(() => _loading = true);
    try {
      await _ensureAuth();
      final snap = await _db.ref('ceoAllowedUsers').get();
      final list = <Map<String, dynamic>>[];
      if (snap.exists && snap.value is Map) {
        (snap.value as Map).forEach((k, v) {
          if (v is Map) list.add({'id': k.toString(), ...Map<String, dynamic>.from(v)});
        });
      }
      list.sort((a, b) => ((b['createdAt'] ?? 0) as num).compareTo((a['createdAt'] ?? 0) as num));
      if (mounted) setState(() { _users = list; _loading = false; });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
      _setStatus('${tr('loadFailed')}: $e', false);
    }
  }

  Future<void> _deleteAccess(Map user) async {
    final name = user['name'] ?? '';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(tr('deleteStaffAccessQ')),
        content: Text('${tr('deleteStaffQ1')} $name?\n\n${tr('deleteStaffQ2')}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('cancel'))),
          ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(context, true), child: Text(tr('delete'))),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _ensureAuth();
      final id = user['id'].toString();
      await _db.ref('ceoAllowedUsers/$id').remove();
      await _db.ref('ceoAccessList/$id').remove();
      await _db.ref('ceoDashboardAccess/$id').remove();
      // allowedCEOs is a push-list (no phone key), so also remove any entry with same phone
      final snap = await _db.ref('allowedCEOs').get();
      if (snap.exists && snap.value is Map) {
        for (final e in (snap.value as Map).entries) {
          if (e.value is Map && _normPhone((e.value as Map)['phone']?.toString() ?? '') == _normPhone(user['phone']?.toString() ?? '')) {
            await _db.ref('allowedCEOs/${e.key}').remove();
          }
        }
      }
      _setStatus('${tr('deletedLabel')} $name - ${tr('canNoLongerLogin')}', true);
      await _loadAccess();
    } catch (e) {
      _setStatus('${tr('deleteFailed')}: $e', false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0C0A1E),
      appBar: AppBar(backgroundColor: const Color(0xFF0C0A1E), actions: [DropdownButtonHideUnderline(child: DropdownButton<String>(value: LanguageService.instance.locale.languageCode, dropdownColor: const Color(0xFF0C0A1E), icon: const Icon(Icons.language, color: Colors.white, size: 20), items: LanguageService.languageNames.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, style: const TextStyle(color: Colors.white)))).toList(), onChanged: (v) { if (v != null) LanguageService.instance.setLanguage(v); }))], title: Text(tr('createAccessTitle'), style: TextStyle(fontWeight: FontWeight.w800))),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: const Color(0xFF1A1633), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white.withOpacity(0.08))),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _field(tr('fullName'), _nameCtrl, 'Kwaku Osei', TextInputType.name),
                      const SizedBox(height: 12),
                      _field(tr('usernameLabel'), _userCtrl, tr('usernameHint'), TextInputType.text),
                      const SizedBox(height: 4),
                      Text(tr('noSpacesUsernameNote'), style: TextStyle(fontSize: 10, color: Color(0xFF9A95B8))),
                      const SizedBox(height: 12),
                      _field(tr('phoneNumber'), _phoneCtrl, '0544121814', TextInputType.phone),
                      const SizedBox(height: 12),
                      _field(tr('emailLabel'), _emailCtrl, 'ceo@lovecareglobal.com', TextInputType.emailAddress),
                      const SizedBox(height: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(tr('staffPassword'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _passCtrl,
                            obscureText: !_showPass,
                            decoration: InputDecoration(
                              hintText: tr('createPassForStaffHint'),
                              filled: true,
                              fillColor: const Color(0xFF0C0A1E),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              suffixIcon: IconButton(
                                icon: Icon(_showPass ? Icons.visibility_off : Icons.visibility),
                                onPressed: () => setState(() => _showPass = !_showPass),
                              ),
                            ),
                            style: const TextStyle(color: Colors.white),
                          ),
                          const SizedBox(height: 4),
                          Text(tr('staffPassNote'), style: TextStyle(fontSize: 10, color: Color(0xFF9A95B8))),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (_status != null)
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(color: _statusOk ? Colors.green.withOpacity(0.12) : Colors.red.withOpacity(0.12), borderRadius: BorderRadius.circular(10), border: Border.all(color: _statusOk ? Colors.green.withOpacity(0.3) : Colors.red.withOpacity(0.3))),
                          child: Text(_status!, textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: _statusOk ? const Color(0xFF86EFAC) : const Color(0xFFFCA5A5))),
                        ),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: _busy ? null : _createAccess,
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFACC15), padding: const EdgeInsets.all(12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999))),
                        child: _busy ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black)) : Text(tr('createBtn'), style: TextStyle(color: Colors.black, fontWeight: FontWeight.w800)),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => StaffLoginPage())),
                        child: Text(tr('goToLogin'),
                      ),
                      const SizedBox(height: 16),
                      Text(tr('allowedUsers'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: const Color(0xFF0C0A1E), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white.withOpacity(0.08))),
                        child: _loading
                            ? const Padding(padding: EdgeInsets.all(20), child: Center(child: Text(tr('loadingLabel'), style: TextStyle(color: Color(0xFF6B6788), fontSize: 11))))
                            : _users.isEmpty
                                ? const Padding(padding: EdgeInsets.all(20), child: Center(child: Text(tr('noUsers'), style: TextStyle(color: Color(0xFF6B6788), fontSize: 11))))
                                : Column(
                                    children: _users.map((u) => Container(
                                      margin: const EdgeInsets.only(bottom: 8),
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(color: const Color(0xFF1A1633), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white.withOpacity(0.08))),
                                      child: Row(
                                        children: [
                                          CircleAvatar(backgroundColor: const Color(0xFFFACC15), child: Text(((u['name'] ?? 'C').toString().isNotEmpty ? (u['name'] as String)[0].toUpperCase() : 'C'), style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w900))),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text('${u['name'] ?? ''}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                                Text('${tr('usernameLabel')}: ${u['username'] ?? tr('notSetOldUser')}', style: const TextStyle(fontSize: 10, color: Color(0xFFFACC15), fontWeight: FontWeight.bold)),
                                                Text('${u['phone'] ?? ''} • ${u['email'] ?? ''}', style: const TextStyle(fontSize: 10, color: Color(0xFF9A95B8))),
                                                Text('${tr('passwordLabel')}: ${((u['password'] ?? u['staffPassword'] ?? '') as Object).toString().isEmpty ? tr('notSetOldUser') : tr('setStaffUsesLogin')}', style: const TextStyle(fontSize: 10, color: Color(0xFF9A95B8))),
                                              ],
                                            ),
                                          ),
                                          TextButton(
                                            onPressed: () => _deleteAccess(u),
                                            child: Text(tr('delete'), style: TextStyle(color: Color(0xFFFCA5A5), fontSize: 10)),
                                          ),
                                        ],
                                      ),
                                    )).toList(),
                                  ),
                      ),
                      const SizedBox(height: 16),
                      Text(tr('recentStaffVisits'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: const Color(0xFF0C0A1E), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white.withOpacity(0.08))),
                        child: _visits.isEmpty
                            ? const Padding(padding: EdgeInsets.all(20), child: Center(child: Text(tr('noStaffVisitsYet'), style: TextStyle(color: Color(0xFF6B6788), fontSize: 11))))
                            : Column(
                                children: _visits.map((v) => Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.visibility, size: 16, color: Color(0xFFFACC15)),
                                      const SizedBox(width: 8),
                                      Expanded(child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text('${v['name'] ?? ''} (${v['username'] ?? ''}) ${tr('visitedCeoDashboard')}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                          Text('${v['loginTime'] ?? ''}', style: const TextStyle(fontSize: 10, color: Color(0xFF9A95B8))),
                                        ],
                                      )),
                                    ],
                                  ),
                                )).toList(),
                              ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(String label, TextEditingController ctrl, String hint, TextInputType type) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        TextField(
          controller: ctrl,
          keyboardType: type,
          decoration: InputDecoration(hintText: hint, filled: true, fillColor: const Color(0xFF0C0A1E), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
          style: const TextStyle(color: Colors.white),
        ),
      ],
    );
  }
}

// Aliases
typedef CreateAccessPage = CEOCreateAccessPage;
typedef CEOCreateAccessScreen = CEOCreateAccessPage;
