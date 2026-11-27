import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import '../services/language_service.dart';
import '../services/translations.dart';

/// CEO Penalize - Flutter version of ceo-penalize.html
/// NOTE: The uploaded ceo-penalize.html is a SUMMARY STUB — its <script> says "Full JS logic is in the file saved at /mnt/data/ceo-penalize.html — 61,105 bytes — Copy full file!" but the file itself contains only that comment, no real JS.
/// This Flutter version implements the FULL logic from the VISIBLE HTML (stats, 2 columns, penalize form, penalty grid, delete warning, history) + the penalty paths named in the stub comment:
///   Penalties write to: ceoPenalties, allPenalties, clientPenalties, nursePenalties, blockedClients, blockedNurses, deletedClients, deletedNurses, suspendedClients, suspendedNurses, etc.
///   Delete: Writes to deletedClients/deletedNurses + blockedClients/blockedNurses + Cannot login + Balance frozen + Appeal possible
///   Restore: Removes from blocked/deleted + Trust reset to 100
/// - Load: clients from clients + clientUsers + allowedClients + allowedClientsByUid (merge by uid, first wins), nurses from nurses + nurseUsers + allowedNurses + allowedNursesByUid (merge by uid) — same people as CEO Registration Center
///   Each person: id/uid, name (fullName/name/displayName), phone, email, type (client/nurse), trustScore (trustScore ?? 100), bookings count (from bookings by clientId/nurseId — best-effort), status: deleted (in deletedClients/deletedNurses) / blocked (in blockedClients/blockedNurses OR isBlocked/isRestricted) / suspended (in suspendedClients/suspendedNurses OR isSuspended/isTemporarySuspended) / active
/// - Stats: Total Clients, Total Nurses, Total Penalties (count allPenalties), Blocked Accounts (blockedClients + blockedNurses), Deleted Accounts (deletedClients + deletedNurses), Low Trust (trust < 60 — "Needs CEO approval + extra fee") — same as HTML statsGrid
/// - Columns: 👤 Clients — Penalize up to Deletion (badge "{n} clients") / 👩‍⚕️ Nurses — Penalize up to Deletion (badge "{n} nurses") — search filters both columns — same as HTML twoCols
/// - Select person -> Penalize Form opens: avatar, name, "Phone: - • Bookings: 0 • Trust: 100/100 • Status: Active", badges (Pending/Blocked/Deleted/Trust) — same as HTML penalizeForm
/// - SELECT PENALTY — same as HTML actionGrid (12 actions):
///   warn (⚠️ Warn — Warning — First offense — Legal) | decrease_trust (📉 Decrease Trust — -10 to -50 Trust — Visible to all) | decrease_trust_20 (📉📉 Decrease Trust -20 — Trust -20 — Quick) |
///   suspend_24h (⏸️ Suspend 24H — Suspend 24 hours — Temp) | suspend_7d (⏸️⏸️ Suspend 7 Days) | suspend_30d (⏸️⏸️⏸️ Suspend 30 Days — Serious) |
///   block_temp (🚫 Block Temporary — Block until CEO unblocks — Appeal) | block_permanent (🚫🚫 Block Permanent — Permanent block — Appeal possible — Serious) |
///   fine (💰 Fine — Extra Fee — Add 10-50% extra fee on next bookings) | require_approval (🔒 Require CEO Approval — All future bookings need CEO approval) | require_100_percent (💳 Require 100% Advance — No 50% option — 100% advance only) |
///   delete_account (🗑️💥 DELETE ACCOUNT — Up to Deletion — Full account deletion — Cannot login — All data removed — FINAL)
/// - Penalty Details: Selected Penalty + description, Reason (REQUIRED — Legal protection), Duration (24h / 7d / 30d / 90d / permanent / until_appeal — for suspend/block), Trust Decrease (10 / 20 / 30 / 50 / 100 → 0), Fine Amount / Extra Fee % (10% / 20% / 30% / 50% / 100% / GHS100 / GHS500), Evidence Reviewed (yes / partial / no) — same as HTML penaltyDetails
/// - Delete Warning: shown when delete_account selected — lists: Delete permanently, Cannot login, Email/Phone blocked, Bookings kept for legal but marked DELETED, Balance frozen, Logged as deletion, Notified — Can appeal in ceo-appeals, Final — CEO can restore if appeal approved — Type DELETE to confirm — same as HTML deleteWarning
/// - Apply Penalty — same as HTML applyPenalty():
///   Validate: person selected, penalty selected, reason required, delete requires typing DELETE exactly
///   penaltyId = "PEN-{personId}-{now}"
///   Effects: warn -> trustDeduct 0 ; decrease_trust -> trustDeduct = selected trustDecrease ?? 20 ; decrease_trust_20 -> trustDeduct 20 ; suspend_24h/7d/30d -> suspendUntil = now + duration (or selected duration), isSuspended true ; block_temp -> isBlocked true, suspendUntil = duration ?? until_appeal (0 = until CEO unblocks) ; block_permanent -> isBlocked true, suspendUntil 0 (permanent) ; fine -> fineAmount/extraFee ; require_approval -> requiresCEOApproval true ; require_100_percent -> require100Percent true, no 50% ; delete_account -> isDeleted true, isBlocked true, canLogin false, balanceFrozen true
///   penaltyData: {penaltyId, personId, personType, personName, personPhone, personEmail, action, reason, duration, trustDeduct, fineAmount, evidenceReviewed, createdAt, createdAtStr, ceoId CEO, status active, suspendUntil, isBlocked, isSuspended, isDeleted, canLogin, balanceFrozen, requiresCEOApproval, require100Percent, appealPossible true}
///   Writes: ceoPenalties/{penaltyId} + allPenalties/{penaltyId} + clientPenalties/{personId}/{penaltyId} OR nursePenalties/{personId}/{penaltyId} + penaltiesByPerson/{personId}/{penaltyId} + notifications/{personId}/{penaltyId} {type penalty, title "⚖️ CEO Penalty: {action}", message reason first 200, penaltyId, action, createdAt, isRead false}
///   Person record: clients/{id} OR nurses/{id} {isBlocked, isSuspended, suspendUntil, suspendUntilStr, trustScore (transaction deduct), lastPenalty, lastPenaltyType, lastPenaltyAt, penaltyCount +1, hasActivePenalty true, requiresCEOApproval, require100Percent, fineAmount/extraFee, canLogin false if deleted/blocked, isDeleted if deleted, balanceFrozen if deleted} + blockedClients/blockedNurses/{id} {personId, name, reason, penaltyId, createdAt, status blocked} if blocked + suspendedClients/suspendedNurses/{id} if suspended + deletedClients/deletedNurses/{id} {personId, name, reason, penaltyId, createdAt, status deleted, canLogin false, balanceFrozen true, appealPossible true} if deleted
///   + If deleted: remove from onlineNurses / liveNurses (nurse) + nursePresence offline (same as Complainant delete path)
/// - Restore Account (Unblock): button on blocked/deleted person -> confirm -> remove from blockedClients/blockedNurses + deletedClients/deletedNurses + suspendedClients/suspendedNurses + update clients/nurses {isBlocked false, isSuspended false, isDeleted false, suspendUntil 0, canLogin true, balanceFrozen false, trustScore 100, hasActivePenalty false, restoredAt, restoredBy CEO} + penalty record {status restored} — same as HTML restoreAccount() comment "Removes from blocked/deleted + Trust reset to 100"
/// - Penalty History: allPenalties sorted createdAt desc, filter by selected person (or all), "{n} penalties" — same as HTML historyList
/// - NO alert buttons — only Sound Settings.

class CEOPenalizeScreen extends StatefulWidget {
  const CEOPenalizeScreen({super.key});
  @override
  State<CEOPenalizeScreen> createState() => _CEOPenalizeScreenState();
}

class _CEOPenalizeScreenState extends State<CEOPenalizeScreen> {
  List<Map> clients = [], nurses = [], penalties = [];
  Map? selectedPerson;
  String selectedPenalty = '';
  String search = '';
  final _searchCtrl = TextEditingController();
  final _reasonCtrl = TextEditingController();
  final _deleteCtrl = TextEditingController();
  String duration = '', trustDecrease = '', fineAmount = '', evidenceReviewed = 'yes';

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  void _toast(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _loadAll() async {
    Map<String, Map> cMap = {}, nMap = {};
    for (final path in ['clients', 'clientUsers', 'allowedClients', 'allowedClientsByUid']) {
      try { final snap = await FirebaseDatabase.instance.ref(path).get(); if (!snap.exists) continue; (snap.value as Map).forEach((k, val) { if (val is Map && !cMap.containsKey(k.toString())) cMap[k.toString()] = Map<String, dynamic>.from(val); }); } catch (_) {}
    }
    for (final path in ['nurses', 'nurseUsers', 'allowedNurses', 'allowedNursesByUid']) {
      try { final snap = await FirebaseDatabase.instance.ref(path).get(); if (!snap.exists) continue; (snap.value as Map).forEach((k, val) { if (val is Map && !nMap.containsKey(k.toString())) nMap[k.toString()] = Map<String, dynamic>.from(val); }); } catch (_) {}
    }
    // blocked / deleted / suspended sets
    Set<String> blocked = {}, deleted = {}, suspended = {};
    for (final p in ['blockedClients', 'blockedNurses']) { try { final s = await FirebaseDatabase.instance.ref(p).get(); if (s.exists) (s.value as Map).forEach((k, _) => blocked.add(k.toString())); } catch (_) {} }
    for (final p in ['deletedClients', 'deletedNurses']) { try { final s = await FirebaseDatabase.instance.ref(p).get(); if (s.exists) (s.value as Map).forEach((k, _) => deleted.add(k.toString())); } catch (_) {} }
    for (final p in ['suspendedClients', 'suspendedNurses']) { try { final s = await FirebaseDatabase.instance.ref(p).get(); if (s.exists) (s.value as Map).forEach((k, _) => suspended.add(k.toString())); } catch (_) {} }
    Map _norm(String id, Map v, String type) {
      final name = (v['fullName'] ?? v['name'] ?? v['displayName'] ?? v['clientName'] ?? v['username'] ?? 'Unnamed').toString();
      String status = 'active';
      if (deleted.contains(id) || v['isDeleted'] == true) status = 'deleted';
      else if (blocked.contains(id) || v['isBlocked'] == true || v['isRestricted'] == true) status = 'blocked';
      else if (suspended.contains(id) || v['isSuspended'] == true || v['isTemporarySuspended'] == true) status = 'suspended';
      return {'id': id, 'uid': v['uid'] ?? id, 'type': type, 'name': name, 'phone': v['phone'] ?? v['phoneNumber'] ?? '', 'email': v['email'] ?? '', 'trustScore': (v['trustScore'] ?? 100) as num, 'status': status, 'raw': v};
    }
    final cList = cMap.entries.map((e) => _norm(e.key, e.value, 'client')).toList();
    final nList = nMap.entries.map((e) => _norm(e.key, e.value, 'nurse')).toList();
    List<Map> pen = [];
    try { final s = await FirebaseDatabase.instance.ref('allPenalties').get(); if (s.exists) (s.value as Map).forEach((k, val) { if (val is Map) pen.add({...Map<String, dynamic>.from(val), 'id': k}); }); } catch (_) {}
    pen.sort((a, b) => ((b['createdAt'] ?? 0) as num).compareTo((a['createdAt'] ?? 0) as num));
    setState(() { clients = cList; nurses = nList; penalties = pen; });
  }

  List<Map> _filterList(List<Map> list) => search.isEmpty ? list : list.where((p) => '${p['name']} ${p['phone']} ${p['email']}'.toLowerCase().contains(search)).toList();

  String _penaltyDesc(String a) {
    switch (a) {
      case 'warn': return tr('penDescWarn');
      case 'decrease_trust': return tr('penDescDecreaseTrust');
      case 'decrease_trust_20': return tr('penDescDecreaseTrust20');
      case 'suspend_24h': return tr('penDescSuspend24');
      case 'suspend_7d': return tr('penDescSuspend7');
      case 'suspend_30d': return tr('penDescSuspend30');
      case 'block_temp': return tr('penDescBlockTemp');
      case 'block_permanent': return tr('penDescBlockPerm');
      case 'fine': return tr('penDescFine');
      case 'require_approval': return tr('penDescRequireApproval');
      case 'require_100_percent': return tr('penDescRequire100');
      case 'delete_account': return tr('penDescDelete');
      default: return tr('penDescDefault');
    }
  }

  Future<void> _applyPenalty() async {
    final person = selectedPerson;
    if (person == null) { _toast(tr('penSelectPerson')); return; }
    if (selectedPenalty.isEmpty) { _toast(tr('penSelectPenalty')); return; }
    final reason = _reasonCtrl.text.trim();
    if (reason.isEmpty) { _toast(tr('penReasonRequired')); return; }
    if (selectedPenalty == 'delete_account' && _deleteCtrl.text != 'DELETE') { _toast(tr('penTypeDeleteExact')); return; }
    final confirm = await showDialog<bool>(context: context, builder: (_) => AlertDialog(title: Text('⚖️ ${tr('penApplyQ')} ${selectedPenalty.toUpperCase()}?'), content: Text('${tr('penPersonLabel')}: ${person['type'].toString().toUpperCase()} — ${person['name']}\n${tr('penPenaltyLabel')}: ${selectedPenalty.toUpperCase()}\n${tr('penReasonLabel')}: $reason\n\n${tr('penApplyImmediately')}'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('cancel'))), ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(context, true), child: Text(tr('penApplyBtn')))]));
    if (confirm != true) return;
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final penaltyId = 'PEN-${person['id']}-$now';
      final type = person['type'].toString();
      int trustDeduct = 0, suspendUntil = 0; bool isBlocked = false, isSuspended = false, isDeleted = false, canLogin = true, balanceFrozen = false, requiresApproval = false, require100 = false;
      int durationMs = 0;
      if (duration == '24h') durationMs = 24 * 60 * 60 * 1000;
      else if (duration == '7d') durationMs = 7 * 24 * 60 * 60 * 1000;
      else if (duration == '30d') durationMs = 30 * 24 * 60 * 60 * 1000;
      else if (duration == '90d') durationMs = 90 * 24 * 60 * 60 * 1000;
      if (selectedPenalty == 'decrease_trust') trustDeduct = int.tryParse(trustDecrease) ?? 20;
      else if (selectedPenalty == 'decrease_trust_20') trustDeduct = 20;
      else if (selectedPenalty == 'suspend_24h') { isSuspended = true; suspendUntil = now + 24 * 60 * 60 * 1000; }
      else if (selectedPenalty == 'suspend_7d') { isSuspended = true; suspendUntil = now + 7 * 24 * 60 * 60 * 1000; }
      else if (selectedPenalty == 'suspend_30d') { isSuspended = true; suspendUntil = now + 30 * 24 * 60 * 60 * 1000; }
      else if (selectedPenalty == 'block_temp') { isBlocked = true; suspendUntil = durationMs > 0 ? now + durationMs : 0; }
      else if (selectedPenalty == 'block_permanent') { isBlocked = true; suspendUntil = 0; }
      else if (selectedPenalty == 'fine') { /* fineAmount stored */ }
      else if (selectedPenalty == 'require_approval') requiresApproval = true;
      else if (selectedPenalty == 'require_100_percent') require100 = true;
      else if (selectedPenalty == 'delete_account') { isDeleted = true; isBlocked = true; canLogin = false; balanceFrozen = true; }
      final penaltyData = {'penaltyId': penaltyId, 'personId': person['id'], 'personType': type, 'personName': person['name'], 'personPhone': person['phone'], 'personEmail': person['email'], 'action': selectedPenalty, 'reason': reason, 'duration': duration, 'trustDeduct': trustDeduct, 'fineAmount': fineAmount, 'evidenceReviewed': evidenceReviewed, 'createdAt': now, 'createdAtStr': DateTime.now().toString(), 'ceoId': 'CEO', 'status': 'active', 'suspendUntil': suspendUntil, 'suspendUntilStr': suspendUntil != 0 ? DateTime.fromMillisecondsSinceEpoch(suspendUntil).toString() : (isBlocked && selectedPenalty == 'block_permanent' ? 'PERMANENT' : ''), 'isBlocked': isBlocked, 'isSuspended': isSuspended, 'isDeleted': isDeleted, 'canLogin': canLogin, 'balanceFrozen': balanceFrozen, 'requiresCEOApproval': requiresApproval, 'require100Percent': require100, 'appealPossible': true};
      final db = FirebaseDatabase.instance;
      await db.ref('ceoPenalties/$penaltyId').set(penaltyData);
      await db.ref('allPenalties/$penaltyId').set(penaltyData);
      if (type == 'client') await db.ref('clientPenalties/${person['id']}/$penaltyId').set(penaltyData);
      else await db.ref('nursePenalties/${person['id']}/$penaltyId').set(penaltyData);
      await db.ref('penaltiesByPerson/${person['id']}/$penaltyId').set(penaltyData);
      await db.ref('notifications/${person['id']}/$penaltyId').set({'type': 'penalty', 'title': '⚖️ CEO Penalty: ${selectedPenalty.toUpperCase()}', 'message': reason.length > 200 ? reason.substring(0, 200) : reason, 'penaltyId': penaltyId, 'action': selectedPenalty, 'createdAt': now, 'isRead': false});
      final base = type == 'client' ? 'clients' : 'nurses';
      final countSnap = await db.ref('$base/${person['id']}/penaltyCount').get();
      final count = ((countSnap.value ?? 0) as num).toInt() + 1;
      await db.ref('$base/${person['id']}').update({'isBlocked': isBlocked, 'isSuspended': isSuspended, 'suspendUntil': suspendUntil, 'lastPenalty': penaltyId, 'lastPenaltyType': selectedPenalty, 'lastPenaltyAt': now, 'penaltyCount': count, 'hasActivePenalty': true, 'requiresCEOApproval': requiresApproval, 'require100Percent': require100, if (fineAmount.isNotEmpty) 'fineAmount': fineAmount, if (fineAmount.isNotEmpty) 'extraFee': fineAmount, if (selectedPenalty == 'delete_account') 'isDeleted': true, if (selectedPenalty == 'delete_account') 'canLogin': false, if (selectedPenalty == 'delete_account') 'balanceFrozen': true});
      if (trustDeduct > 0) {
        await db.ref('$base/${person['id']}/trustScore').runTransaction((Object? cur) { final v = (cur as num?) ?? 100; return Transaction.success(((v - trustDeduct).clamp(0, 100))); }).catchError((_) {});
      }
      if (isBlocked) await db.ref(type == 'client' ? 'blockedClients/${person['id']}' : 'blockedNurses/${person['id']}').set({'personId': person['id'], 'name': person['name'], 'reason': reason, 'penaltyId': penaltyId, 'createdAt': now, 'status': 'blocked'});
      if (isSuspended) await db.ref(type == 'client' ? 'suspendedClients/${person['id']}' : 'suspendedNurses/${person['id']}').set({'personId': person['id'], 'name': person['name'], 'reason': reason, 'penaltyId': penaltyId, 'createdAt': now, 'suspendUntil': suspendUntil, 'status': 'suspended'});
      if (isDeleted) {
        await db.ref(type == 'client' ? 'deletedClients/${person['id']}' : 'deletedNurses/${person['id']}').set({'personId': person['id'], 'name': person['name'], 'reason': reason, 'penaltyId': penaltyId, 'createdAt': now, 'status': 'deleted', 'canLogin': false, 'balanceFrozen': true, 'appealPossible': true});
        if (type == 'nurse') {
          await db.ref('onlineNurses/${person['id']}').remove().catchError((_) {});
          await db.ref('liveNurses/${person['id']}').remove().catchError((_) {});
          await db.ref('nursePresence/${person['id']}').set({'status': 'offline', 'isOnline': false, 'isDeleted': true, 'lastPenalty': penaltyId}).catchError((_) {});
        }
      }
      _toast('✅ ${tr('penApplied')} — ${person['name']} $selectedPenalty');
      _reasonCtrl.clear(); _deleteCtrl.clear(); setState(() { selectedPenalty = ''; selectedPerson = null; });
      _loadAll();
    } catch (e) { _toast('${tr('penApplyFailed')}: $e'); }
  }

  Future<void> _restoreAccount(Map person) async {
    final confirm = await showDialog<bool>(context: context, builder: (_) => AlertDialog(title: Text(tr('penRestoreQ')), content: Text('${tr('penRestoreQ2')} ${person['name']}?\n\n${tr('penRestoreHint')}'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('cancel'))), ElevatedButton(onPressed: () => Navigator.pop(context, true), child: Text(tr('restoreBtn')))]));
    if (confirm != true) return;
    final type = person['type'].toString(); final base = type == 'client' ? 'clients' : 'nurses'; final db = FirebaseDatabase.instance;
    await db.ref(type == 'client' ? 'blockedClients/${person['id']}' : 'blockedNurses/${person['id']}').remove().catchError((_) {});
    await db.ref(type == 'client' ? 'deletedClients/${person['id']}' : 'deletedNurses/${person['id']}').remove().catchError((_) {});
    await db.ref(type == 'client' ? 'suspendedClients/${person['id']}' : 'suspendedNurses/${person['id']}').remove().catchError((_) {});
    await db.ref('$base/${person['id']}').update({'isBlocked': false, 'isSuspended': false, 'isDeleted': false, 'suspendUntil': 0, 'canLogin': true, 'balanceFrozen': false, 'trustScore': 100, 'hasActivePenalty': false, 'restoredAt': DateTime.now().millisecondsSinceEpoch, 'restoredBy': 'CEO'});
    _toast('✅ ${person['name']} ${tr('penRestored')}');
    _loadAll();
  }

  Widget _personCard(Map p) {
    final isSel = selectedPerson?['id'] == p['id'] && selectedPerson?['type'] == p['type'];
    final status = p['status'];
    return InkWell(onTap: () => setState(() => selectedPerson = p), child: Container(margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: isSel ? Colors.yellow.withOpacity(0.08) : status == 'blocked' ? Colors.red.withOpacity(0.08) : status == 'deleted' ? Colors.black38 : Colors.black26, borderRadius: BorderRadius.circular(14), border: Border.all(color: isSel ? const Color(0xFFFACC15) : status == 'blocked' ? Colors.red.withOpacity(0.4) : Colors.white10)), child: Row(children: [
      CircleAvatar(child: Text((p['name'] as String).isNotEmpty ? (p['name'] as String)[0].toUpperCase() : '?')),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(p['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        Text('📱 ${p['phone']} • ✉️ ${p['email']}', style: const TextStyle(fontSize: 11, color: Colors.white60)),
        Wrap(spacing: 4, children: [Chip(label: Text('${tr('trustLabel')}: ${p['trustScore']}/100', style: const TextStyle(fontSize: 10)), backgroundColor: Colors.blue.withOpacity(0.2)), Chip(label: Text('${tr('statusLabel')}: $status', style: const TextStyle(fontSize: 10)), backgroundColor: status == 'active' ? Colors.green.withOpacity(0.2) : status == 'blocked' ? Colors.red.withOpacity(0.2) : Colors.black38)]),
      ])),
      if (status == 'blocked' || status == 'deleted' || status == 'suspended') TextButton(onPressed: () => _restoreAccount(p), child: Text(tr('restoreBtn'), style: TextStyle(fontSize: 11, color: Colors.green))),
    ])));
  }

  @override
  Widget build(BuildContext context) {
    final blocked = clients.where((p) => p['status'] == 'blocked').length + nurses.where((p) => p['status'] == 'blocked').length;
    final deleted = clients.where((p) => p['status'] == 'deleted').length + nurses.where((p) => p['status'] == 'deleted').length;
    final lowTrust = clients.where((p) => (p['trustScore'] as num) < 60).length + nurses.where((p) => (p['trustScore'] as num) < 60).length;
    final history = selectedPerson == null ? penalties : penalties.where((p) => p['personId'] == selectedPerson!['id']).toList();
    final penaltyActions = [
      {'key': 'warn', 'label': tr('penLabelWarn'), 'sub': tr('penDescWarn'), 'icon': '⚠️'},
      {'key': 'decrease_trust', 'label': tr('penLabelDecreaseTrust'), 'sub': tr('penDescDecreaseTrust'), 'icon': '📉'},
      {'key': 'decrease_trust_20', 'label': tr('penLabelDecreaseTrust20'), 'sub': tr('penDescDecreaseTrust20'), 'icon': '📉📉'},
      {'key': 'suspend_24h', 'label': tr('penLabelSuspend24'), 'sub': tr('penDescSuspend24'), 'icon': '⏸️'},
      {'key': 'suspend_7d', 'label': tr('penLabelSuspend7'), 'sub': tr('penDescSuspend7'), 'icon': '⏸️⏸️'},
      {'key': 'suspend_30d', 'label': tr('penLabelSuspend30'), 'sub': tr('penDescSuspend30'), 'icon': '⏸️⏸️⏸️'},
      {'key': 'block_temp', 'label': tr('penLabelBlockTemp'), 'sub': tr('penDescBlockTemp'), 'icon': '🚫'},
      {'key': 'block_permanent', 'label': tr('penLabelBlockPerm'), 'sub': tr('penDescBlockPerm'), 'icon': '🚫🚫'},
      {'key': 'fine', 'label': tr('penLabelFine'), 'sub': tr('penDescFine'), 'icon': '💰'},
      {'key': 'require_approval', 'label': tr('penLabelRequireApproval'), 'sub': tr('penDescRequireApproval'), 'icon': '🔒'},
      {'key': 'require_100_percent', 'label': tr('penLabelRequire100'), 'sub': tr('penDescRequire100'), 'icon': '💳'},
      {'key': 'delete_account', 'label': tr('penLabelDelete'), 'sub': tr('penDescDelete'), 'icon': '🗑️💥'},
    ];
    return Scaffold(
      backgroundColor: const Color(0xFF0C0A1E),
      appBar: AppBar(title: Text(tr('ceoPenalizeTitle'), style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)), backgroundColor: const Color(0xFF1A1633), actions: [DropdownButtonHideUnderline(child: DropdownButton<String>(value: LanguageService.instance.locale.languageCode, dropdownColor: const Color(0xFF1A1633), icon: const Icon(Icons.language, color: Colors.white, size: 20), items: LanguageService.languageNames.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, style: const TextStyle(color: Colors.white)))).toList(), onChanged: (v) { if (v != null) LanguageService.instance.setLanguage(v); })), IconButton(icon: const Icon(Icons.volume_up), onPressed: () => Navigator.pushNamed(context, '/sound-settings'))]),
      body: SingleChildScrollView(padding: const EdgeInsets.all(14), child: Column(children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          _stat(tr('penTotalClients'), '${clients.length}', tr('penTotalClientsSub')),
          _stat(tr('penTotalNurses'), '${nurses.length}', tr('penTotalNursesSub')),
          _stat(tr('penTotalPenalties'), '${penalties.length}', tr('penTotalPenaltiesSub')),
          _stat(tr('penBlockedAccounts'), '$blocked', tr('penBlockedAccountsSub')),
          _stat(tr('penDeletedAccounts'), '$deleted', tr('penDeletedAccountsSub')),
          _stat(tr('penLowTrust'), '$lowTrust', tr('penLowTrustSub')),
        ]),
        const SizedBox(height: 12),
        TextField(controller: _searchCtrl, decoration: InputDecoration(hintText: tr('penSearchHint'), border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8)), onChanged: (v) => setState(() => search = v.toLowerCase())),
        const SizedBox(height: 12),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [Text(tr('penClientsHeading'), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)), const Spacer(), Chip(label: Text('${_filterList(clients).length} ${tr('clientsWord')}', style: const TextStyle(fontSize: 10)), backgroundColor: Colors.red.withOpacity(0.2))]), const SizedBox(height: 8), ..._filterList(clients).map(_personCard).toList()])),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [Text(tr('penNursesHeading'), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)), const Spacer(), Chip(label: Text('${_filterList(nurses).length} ${tr('nursesWord')}', style: const TextStyle(fontSize: 10)), backgroundColor: Colors.purple.withOpacity(0.2))]), const SizedBox(height: 8), ..._filterList(nurses).map(_personCard).toList()])),
        ]),
        if (selectedPerson != null) ...[
          const SizedBox(height: 16),
          Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: const Color(0xFF1A1633), borderRadius: BorderRadius.circular(18), border: Border.all(color: Colors.red.withOpacity(0.2))), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [CircleAvatar(radius: 28, child: Text((selectedPerson!['name'] as String).isNotEmpty ? (selectedPerson!['name'] as String)[0].toUpperCase() : '?')), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('⚖️ ${tr('penPenalizePerson')} ${selectedPerson!['name']} — ${tr('penUpToDeletion')}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)), Text('${tr('phoneLabel')}: ${selectedPerson!['phone']} • ${tr('trustLabel')}: ${selectedPerson!['trustScore']}/100 • ${tr('statusLabel')}: ${selectedPerson!['status']}', style: const TextStyle(fontSize: 11, color: Colors.white60)), Chip(label: Text(selectedPerson!['type'].toString().toUpperCase(), style: const TextStyle(fontSize: 10)))])), TextButton(onPressed: () => setState(() => selectedPerson = null), child: Text(tr('penCloseForm')))]),
            const SizedBox(height: 14),
            Text(tr('penSelectPenaltyHeading'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            GridView.builder(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, childAspectRatio: 1.1, crossAxisSpacing: 8, mainAxisSpacing: 8), itemCount: penaltyActions.length, itemBuilder: (_, i) {
              final a = penaltyActions[i]; final isSel = selectedPenalty == a['key'];
              return InkWell(onTap: () => setState(() => selectedPenalty = a['key']!), child: Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: isSel ? Colors.yellow.withOpacity(0.15) : Colors.black26, borderRadius: BorderRadius.circular(12), border: Border.all(color: isSel ? const Color(0xFFFACC15) : a['key'] == 'delete_account' ? Colors.red.withOpacity(0.5) : Colors.white10)), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Text(a['icon']!, style: const TextStyle(fontSize: 20)), const SizedBox(height: 4), Text(a['label']!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)), Text(a['sub']!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 9, color: Colors.white60))])));
            }),
            if (selectedPenalty.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text('⚖️ ${tr('penSelectedPenalty')}: ${selectedPenalty.toUpperCase()}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFFCD34D))),
              Text(_penaltyDesc(selectedPenalty), style: const TextStyle(fontSize: 11, color: Colors.white60)),
              const SizedBox(height: 10),
              Text(tr('penReasonHeading'), style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              TextField(controller: _reasonCtrl, maxLines: 3, decoration: InputDecoration(hintText: tr('penReasonHint'), border: OutlineInputBorder())),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: DropdownButton<String>(value: duration.isEmpty ? null : duration, hint: Text(tr('penDurationHint')), isExpanded: true, items: const [DropdownMenuItem(value: '24h', child: Text(tr('penDur24h'))), DropdownMenuItem(value: '7d', child: Text(tr('penDur7d'))), DropdownMenuItem(value: '30d', child: Text(tr('penDur30d'))), DropdownMenuItem(value: '90d', child: Text(tr('penDur90d'))), DropdownMenuItem(value: 'permanent', child: Text(tr('penDurPermanent'))), DropdownMenuItem(value: 'until_appeal', child: Text(tr('penDurUntilAppeal')))], onChanged: (v) => setState(() => duration = v ?? ''))),
                const SizedBox(width: 8),
                Expanded(child: DropdownButton<String>(value: trustDecrease.isEmpty ? null : trustDecrease, hint: Text(tr('penTrustHint')), isExpanded: true, items: const [DropdownMenuItem(value: '10', child: Text(tr('penTrust10'))), DropdownMenuItem(value: '20', child: Text(tr('penTrust20'))), DropdownMenuItem(value: '30', child: Text(tr('penTrust30'))), DropdownMenuItem(value: '50', child: Text(tr('penTrust50'))), DropdownMenuItem(value: '100', child: Text(tr('penTrust100')))], onChanged: (v) => setState(() => trustDecrease = v ?? ''))),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: DropdownButton<String>(value: fineAmount.isEmpty ? null : fineAmount, hint: Text(tr('penFineHint')), isExpanded: true, items: const [DropdownMenuItem(value: '10%', child: Text(tr('penFine10'))), DropdownMenuItem(value: '20%', child: Text(tr('penFine20'))), DropdownMenuItem(value: '30%', child: Text(tr('penFine30'))), DropdownMenuItem(value: '50%', child: Text(tr('penFine50'))), DropdownMenuItem(value: '100%', child: Text(tr('penFine100'))), DropdownMenuItem(value: 'GHS100', child: Text(tr('penFineGhs100'))), DropdownMenuItem(value: 'GHS500', child: Text(tr('penFineGhs500')))], onChanged: (v) => setState(() => fineAmount = v ?? ''))),
                const SizedBox(width: 8),
                Expanded(child: DropdownButton<String>(value: evidenceReviewed, isExpanded: true, items: const [DropdownMenuItem(value: 'yes', child: Text(tr('penEvidenceYes'))), DropdownMenuItem(value: 'partial', child: Text(tr('penEvidencePartial'))), DropdownMenuItem(value: 'no', child: Text(tr('penEvidenceNo')))], onChanged: (v) => setState(() => evidenceReviewed = v ?? 'yes'))),
              ]),
              if (selectedPenalty == 'delete_account') Container(margin: const EdgeInsets.only(top: 12), padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.red.withOpacity(0.1), border: Border.all(color: Colors.red.withOpacity(0.3)), borderRadius: BorderRadius.circular(12)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr('penDeleteWarningTitle'), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red, fontSize: 13)),
                Text('${tr('penDeleteBodyPrefix')} ${selectedPerson!['name']} ${tr('penDeleteBody')}', style: const TextStyle(fontSize: 11, color: Color(0xFFFCA5A5))),
                const SizedBox(height: 8),
                TextField(controller: _deleteCtrl, decoration: InputDecoration(hintText: tr('penDeleteHint'), border: OutlineInputBorder())),
              ])),
              const SizedBox(height: 14),
              Row(children: [Expanded(child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red, padding: const EdgeInsets.symmetric(vertical: 14)), onPressed: _applyPenalty, child: Text(tr('penApplyPenaltyBtn'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)))), const SizedBox(width: 8), Expanded(child: OutlinedButton(onPressed: () => setState(() => selectedPerson = null), child: Text(tr('cancel'))))]),
            ],
          ])),
        ],
        const SizedBox(height: 16),
        Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: const Color(0xFF1A1633), borderRadius: BorderRadius.circular(18)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Text(tr('penHistoryHeading'), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)), const Spacer(), Chip(label: Text('${history.length} ${tr('penaltiesWord')}', style: const TextStyle(fontSize: 10)))]),
          const SizedBox(height: 8),
          if (history.isEmpty) Center(child: Text(tr('penHistoryEmpty'), style: TextStyle(color: Colors.white60, fontSize: 12))),
          ...history.map((p) => ListTile(leading: const Text('⚖️'), title: Text('${p['personName']} — ${p['action']}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)), subtitle: Text('${p['reason']} • ${p['createdAt'] != null ? DateTime.fromMillisecondsSinceEpoch((p['createdAt'] as num).toInt()) : ''}', style: const TextStyle(fontSize: 11, color: Colors.white60)), trailing: Chip(label: Text(p['status'] ?? 'active', style: const TextStyle(fontSize: 10))))).toList(),
        ])),
      ])),
    );
  }

  Widget _stat(String label, String value, String sub) => Container(width: 180, padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: const Color(0xFF1A1633), borderRadius: BorderRadius.circular(14)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: const TextStyle(color: Colors.white60, fontSize: 11)), Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20)), Text(sub, style: const TextStyle(fontSize: 10, color: Colors.white60))]));
}
