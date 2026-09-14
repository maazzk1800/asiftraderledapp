import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/ledger_models.dart';

class LedgerStorage {
  const LedgerStorage(this.preferences);

  final SharedPreferences preferences;

  List<Transaction> loadTransactions() {
    final values =
        preferences.getStringList('ledger_transactions') ?? <String>[];
    return values
        .map(
          (value) =>
              Transaction.fromJson(jsonDecode(value) as Map<String, dynamic>),
        )
        .toList();
  }

  List<Company> loadCompanies() {
    final values = preferences.getStringList('ledger_companies') ?? <String>[];
    return values
        .map(
          (value) =>
              Company.fromJson(jsonDecode(value) as Map<String, dynamic>),
        )
        .toList();
  }

  List<String> loadCategories() {
    return preferences.getStringList('ledger_categories') ?? <String>[];
  }

  String loadCurrency() => preferences.getString('ledger_currency') ?? 'INR';

  LedgerType loadLedgerType() {
    final savedValue = preferences.getString('ledger_type') ?? 'sales';
    return LedgerType.values.firstWhere(
      (value) => value.name == savedValue,
      orElse: () => LedgerType.sales,
    );
  }

  ThemePreference loadTheme() {
    final savedValue = preferences.getString('ledger_theme') ?? 'light';
    return savedValue == 'dark' ? ThemePreference.dark : ThemePreference.light;
  }

  Future<void> save({
    required List<Transaction> transactions,
    required List<Company> companies,
    required List<String> categories,
    required String currency,
    required LedgerType ledgerType,
    required ThemePreference theme,
  }) async {
    await preferences.setStringList(
      'ledger_transactions',
      transactions
          .map((transaction) => jsonEncode(transaction.toJson()))
          .toList(),
    );
    await preferences.setStringList(
      'ledger_companies',
      companies.map((company) => jsonEncode(company.toJson())).toList(),
    );
    await preferences.setStringList('ledger_categories', categories);
    await preferences.setString('ledger_currency', currency);
    await preferences.setString('ledger_type', ledgerType.name);
    await preferences.setString(
      'ledger_theme',
      theme == ThemePreference.dark ? 'dark' : 'light',
    );
  }
}

enum ThemePreference { light, dark }
