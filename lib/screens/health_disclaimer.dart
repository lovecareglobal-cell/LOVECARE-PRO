import 'package:flutter/material.dart';
import '../services/language_service.dart';
import '../services/translations.dart';

class HealthDisclaimerPage extends StatelessWidget {
  const HealthDisclaimerPage({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFCE4EC),
      appBar: AppBar(backgroundColor: const Color(0xFF880E4F), foregroundColor: Colors.white, title: Text(tr('hdTitle')), actions: [DropdownButtonHideUnderline(child: DropdownButton<String>(value: LanguageService.instance.locale.languageCode, dropdownColor: const Color(0xFF880E4F), icon: const Icon(Icons.language, color: Colors.white, size: 24), items: LanguageService.languageNames.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, style: const TextStyle(color: Colors.black)))).toList(), onChanged: (v) { if (v != null) LanguageService.instance.setLanguage(v); }))]),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _header('⚠️ ${tr('hdHeaderTitle')}\n${tr('hdLastUpdated')}'),
            _section(tr('hdS1Title')),
            _card(tr('hdS1Body')),
            _section(tr('hdS2Title')),
            _card(tr('hdS2Body')),
            _section(tr('hdS3Title')),
            _card(tr('hdS3Body')),
            _section(tr('hdS4Title')),
            _card(tr('hdS4Body')),
            _section(tr('hdS5Title')),
            _card(tr('hdS5Body')),
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
