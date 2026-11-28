import 'package:flutter/material.dart';
import '../services/language_service.dart';
import '../services/translations.dart';

class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('ppTitle')),
        backgroundColor: const Color(0xFF880E4F),
        foregroundColor: Colors.white,
        actions: [DropdownButtonHideUnderline(child: DropdownButton<String>(value: LanguageService.instance.locale.languageCode, dropdownColor: const Color(0xFF0C0A1E), icon: const Icon(Icons.language, color: Colors.white, size: 24), items: LanguageService.languageNames.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, style: const TextStyle(color: Colors.black)))).toList(), onChanged: (v) { if (v != null) LanguageService.instance.setLanguage(v); }))],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(20),
        child: Text(
          tr('ppBody'),
          style: TextStyle(fontSize: 16, height: 1.5),
        ),
      ),
    );
  }
}
