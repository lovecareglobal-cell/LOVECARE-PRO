// lib/screens/refund_policy.dart - English only, no translations.
// This file was overwritten with Privacy Policy before - this is the correct Refund Policy.
import 'package:flutter/material.dart';
import '../services/language_service.dart';
import '../services/translations.dart';

class RefundPolicyPage extends StatelessWidget {
  const RefundPolicyPage({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFCE4EC),
      appBar: AppBar(backgroundColor: const Color(0xFF880E4F), foregroundColor: Colors.white, title: Text(tr('rpTitle')), actions: [DropdownButtonHideUnderline(child: DropdownButton<String>(value: LanguageService.instance.locale.languageCode, dropdownColor: const Color(0xFF0C0A1E), icon: const Icon(Icons.language, color: Colors.white, size: 24), items: LanguageService.languageNames.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, style: const TextStyle(color: Colors.black)))).toList(), onChanged: (v) { if (v != null) LanguageService.instance.setLanguage(v); }))]),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _header(tr('rpHeader')),
            _card(tr('rpIntro')),
            _section(tr('rpS1')),
            _card(tr('rpC1')),
            _section(tr('rpS2')),
            _card(tr('rpC2')),
            _section(tr('rpS3')),
            _card(tr('rpC3')),
            _section(tr('rpS4')),
            _card(tr('rpC4')),
            _section(tr('rpS5')),
            _card(tr('rpC5')),
            _section(tr('rpS6')),
            _card(tr('rpC6')),
            _section(tr('rpS7')),
            _card(tr('rpC7')),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
  static Widget _header(String t) => Container(width: double.infinity, padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)), child: Text(t, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF880E4F))));
  static Widget _section(String t) => Padding(padding: const EdgeInsets.only(top: 16, bottom: 6), child: Align(alignment: Alignment.centerLeft, child: Text(t, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF880E4F)))));
  static Widget _card(String t) => Container(width: double.infinity, padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)), child: Text(t, style: const TextStyle(fontSize: 13, height: 1.5, color: Color(0xFF333333))));
}

// Alias - if any other file calls RefundPolicyScreen, it still works.
class RefundPolicyScreen extends RefundPolicyPage {
  const RefundPolicyScreen({super.key});
}
