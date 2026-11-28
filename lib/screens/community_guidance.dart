import 'package:flutter/material.dart';
import '../services/language_service.dart';
import '../services/translations.dart';

class CommunityGuidelinesPage extends StatelessWidget {
  const CommunityGuidelinesPage({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFCE4EC),
      appBar: AppBar(backgroundColor: const Color(0xFF880E4F), foregroundColor: Colors.white, title: Text(tr('cgTitle')), actions: [DropdownButtonHideUnderline(child: DropdownButton<String>(value: LanguageService.instance.locale.languageCode, dropdownColor: const Color(0xFF880E4F), icon: const Icon(Icons.language, color: Colors.white, size: 24), items: LanguageService.languageNames.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, style: const TextStyle(color: Colors.black)))).toList(), onChanged: (v) { if (v != null) LanguageService.instance.setLanguage(v); }))]),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _header('💜 ${tr('cgHeaderTitle')}\n${tr('cgLastUpdated')}'),
            _section('1. ${tr('cgS1Title')}'),
            _card(tr('cgS1Body')),
            _section('2. ${tr('cgS2Title')}'),
            _card(tr('cgS2Body')),
            _section('3. ${tr('cgS3Title')}'),
            _card(tr('cgS3Body')),
            _section('4. ${tr('cgS4Title')}'),
            _card(tr('cgS4Body')),
            _section('5. ${tr('cgS5Title')}'),
            _card(tr('cgS5Body')),
            _section('6. ${tr('cgS6Title')}'),
            _card(tr('cgS6Body')),
            _section('7. ${tr('cgS7Title')}'),
            _card(tr('cgS7Body')),
            _section('8. ${tr('cgS8Title')}'),
            _card(tr('cgS8Body')),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
  static Widget _header(String t) => Container(width: double.infinity, padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)), child: Text(t, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF880E4F))));
  static Widget _section(String t) => Padding(padding: const EdgeInsets.only(top: 16, bottom: 6), child: Align(alignment: Alignment.centerLeft, child: Text(t, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF880E4F)))));
  static Widget _card(String t) => Container(width: double.infinity, padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)), child: Text(t, style: const TextStyle(fontSize: 13, height: 1.5, color: Color(0xFF333333))));
}
