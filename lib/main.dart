import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  runApp(LedgerApp(prefs: prefs));
}

enum LedgerType { sales, purchase }

enum TransactionType { credit, debit }

enum Screen { welcome, home, companies, addCompany, newEntry }

class Transaction {
  Transaction({
    required this.id,
    required this.title,
    required this.amount,
    required this.type,
    required this.category,
    required this.currency,
    required this.paymentMode,
    required this.date,
    required this.isCleared,
    required this.ledgerType,
    this.companyId,
  });

  final int id;
  final String title;
  final double amount;
  final TransactionType type;
  final String category;
  final String currency;
  final String paymentMode;
  final DateTime date;
  final bool isCleared;
  final LedgerType ledgerType;
  final int? companyId;

  double get signedAmount => type == TransactionType.credit ? amount : -amount;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'amount': amount,
    'type': type.name,
    'category': category,
    'currency': currency,
    'paymentMode': paymentMode,
    'date': date.toIso8601String(),
    'isCleared': isCleared,
    'ledgerType': ledgerType.name,
    'companyId': companyId,
  };

  factory Transaction.fromJson(Map<String, dynamic> map) {
    final savedCategory = map['category'] as String? ?? 'Sales';
    return Transaction(
      id: map['id'] as int? ?? 0,
      title: map['title'] as String? ?? 'Untitled',
      amount: (map['amount'] as num?)?.toDouble() ?? 0.0,
      type: TransactionType.values.firstWhere(
        (value) => value.name == (map['type'] ?? 'debit'),
        orElse: () => TransactionType.debit,
      ),
      category: savedCategory == 'Sales' || savedCategory == 'Purchase'
          ? savedCategory
          : 'Sales',
      currency: 'INR',
      paymentMode: map['paymentMode'] as String? ?? 'Cash',
      date: DateTime.tryParse((map['date'] as String?) ?? '') ?? DateTime.now(),
      isCleared: map['isCleared'] as bool? ?? false,
      ledgerType: LedgerType.values.firstWhere(
        (value) => value.name == (map['ledgerType'] ?? 'sales'),
        orElse: () => LedgerType.sales,
      ),
      companyId: map['companyId'] as int?,
    );
  }
}

class Company {
  Company({
    required this.id,
    required this.name,
    required this.address,
    required this.mobile,
    this.gstin,
  });

  final int id;
  final String name;
  final String address;
  final String mobile;
  final String? gstin;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'address': address,
    'mobile': mobile,
    'gstin': gstin,
  };

  factory Company.fromJson(Map<String, dynamic> map) {
    return Company(
      id: map['id'] as int? ?? 0,
      name: map['name'] as String? ?? '',
      address: map['address'] as String? ?? '',
      mobile: map['mobile'] as String? ?? '',
      gstin: map['gstin'] as String?,
    );
  }
}

class LedgerApp extends StatefulWidget {
  const LedgerApp({super.key, required this.prefs});

  final SharedPreferences prefs;

  @override
  State<LedgerApp> createState() => _LedgerAppState();
}

class _LedgerAppState extends State<LedgerApp> {
  final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  final List<String> currencyOptions = ['INR'];
  final List<String> paymentModes = ['NEFT', 'UPI', 'Netbanking', 'Cash'];
  final List<String> baseCategories = ['Sales', 'Purchase'];
  final List<String> statusFilters = [
    'All',
    'Credit',
    'Debit',
    'Cleared',
    'Pending',
  ];

  final TextEditingController titleController = TextEditingController();
  final TextEditingController amountController = TextEditingController();
  final TextEditingController categoryController = TextEditingController();
  final TextEditingController companyNameController = TextEditingController();
  final TextEditingController companyAddressController =
      TextEditingController();
  final TextEditingController companyMobileController = TextEditingController();
  final TextEditingController companyGstinController = TextEditingController();
  final TextEditingController entryDateController = TextEditingController();

  LedgerType ledgerType = LedgerType.sales;
  ThemeMode themeMode = ThemeMode.light;
  String selectedCurrency = 'INR';
  String searchText = '';
  String categoryFilter = 'All';
  String statusFilter = 'All';
  DateTime? startDate;
  DateTime? endDate;
  Screen screen = Screen.welcome;
  TransactionType selectedType = TransactionType.debit;
  String selectedPaymentMode = 'Cash';
  DateTime selectedEntryDate = DateTime.now();
  bool entryIsCleared = false;
  int? selectedCompanyId;
  Transaction? editingTransaction;

  List<Transaction> transactions = [];
  List<Company> companies = [];
  int nextTransactionId = 1;
  int nextCompanyId = 1;

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  @override
  void dispose() {
    titleController.dispose();
    amountController.dispose();
    categoryController.dispose();
    companyNameController.dispose();
    companyAddressController.dispose();
    companyMobileController.dispose();
    companyGstinController.dispose();
    entryDateController.dispose();
    super.dispose();
  }

  List<String> get allCategories => baseCategories;

  Company? get selectedCompany {
    for (final company in companies) {
      if (company.id == selectedCompanyId) return company;
    }
    return null;
  }

  List<Transaction> get filteredTransactions {
    final query = searchText.trim().toLowerCase();

    return transactions.where((transaction) {
      final matchesLedger = transaction.ledgerType == ledgerType;
      final matchesCompany =
          selectedCompanyId != null &&
          transaction.companyId == selectedCompanyId;
      final matchesSearch =
          query.isEmpty ||
          transaction.title.toLowerCase().contains(query) ||
          transaction.category.toLowerCase().contains(query) ||
          transaction.paymentMode.toLowerCase().contains(query);
      final matchesCategory =
          categoryFilter == 'All' || transaction.category == categoryFilter;
      final matchesStatus =
          statusFilter == 'All' ||
          (statusFilter == 'Credit' &&
              transaction.type == TransactionType.credit) ||
          (statusFilter == 'Debit' &&
              transaction.type == TransactionType.debit) ||
          (statusFilter == 'Cleared' && transaction.isCleared) ||
          (statusFilter == 'Pending' && !transaction.isCleared);
      final matchesStart =
          startDate == null || !transaction.date.isBefore(startDate!);
      final matchesEnd = endDate == null || !transaction.date.isAfter(endDate!);

      return matchesLedger &&
          matchesCompany &&
          matchesSearch &&
          matchesCategory &&
          matchesStatus &&
          matchesStart &&
          matchesEnd;
    }).toList()..sort((a, b) => b.date.compareTo(a.date));
  }

  double get totalBalance => filteredTransactions.fold(
    0.0,
    (total, item) => total + item.signedAmount,
  );

  double get totalCredit => filteredTransactions
      .where((item) => item.type == TransactionType.credit)
      .fold(0.0, (sum, item) => sum + item.amount);

  double get totalDebit => filteredTransactions
      .where((item) => item.type == TransactionType.debit)
      .fold(0.0, (sum, item) => sum + item.amount);

  void _loadState() {
    final rawTransactions =
        widget.prefs.getStringList('ledger_transactions') ?? <String>[];
    final rawCompanies =
        widget.prefs.getStringList('ledger_companies') ?? <String>[];
    final savedLedgerType = widget.prefs.getString('ledger_type') ?? 'sales';
    final savedTheme = widget.prefs.getString('ledger_theme') ?? 'light';

    setState(() {
      transactions = rawTransactions
          .map(
            (value) =>
                Transaction.fromJson(jsonDecode(value) as Map<String, dynamic>),
          )
          .toList();
      companies = rawCompanies
          .map(
            (value) =>
                Company.fromJson(jsonDecode(value) as Map<String, dynamic>),
          )
          .toList();
      if (companies.isNotEmpty) {
        final legacyCompanyId = companies.first.id;
        transactions = transactions.map((transaction) {
          if (transaction.companyId != null) return transaction;
          return Transaction(
            id: transaction.id,
            title: transaction.title,
            amount: transaction.amount,
            type: transaction.type,
            category: transaction.category,
            currency: transaction.currency,
            paymentMode: transaction.paymentMode,
            date: transaction.date,
            isCleared: transaction.isCleared,
            ledgerType: transaction.ledgerType,
            companyId: legacyCompanyId,
          );
        }).toList();
      }
      selectedCurrency = 'INR';
      ledgerType = LedgerType.values.firstWhere(
        (element) => element.name == savedLedgerType,
        orElse: () => LedgerType.sales,
      );
      themeMode = savedTheme == 'dark' ? ThemeMode.dark : ThemeMode.light;
      nextTransactionId = transactions.isEmpty
          ? 1
          : transactions.map((e) => e.id).reduce((a, b) => a > b ? a : b) + 1;
      nextCompanyId = companies.isEmpty
          ? 1
          : companies.map((e) => e.id).reduce((a, b) => a > b ? a : b) + 1;
      selectedCompanyId = companies.isEmpty ? null : companies.first.id;
    });
    _saveState();
  }

  void _saveState() {
    widget.prefs.setStringList(
      'ledger_transactions',
      transactions
          .map((transaction) => jsonEncode(transaction.toJson()))
          .toList(),
    );
    widget.prefs.setStringList(
      'ledger_companies',
      companies.map((company) => jsonEncode(company.toJson())).toList(),
    );
    widget.prefs.setStringList('ledger_categories', allCategories);
    widget.prefs.setString('ledger_currency', selectedCurrency);
    widget.prefs.setString('ledger_type', ledgerType.name);
    widget.prefs.setString(
      'ledger_theme',
      themeMode == ThemeMode.dark ? 'dark' : 'light',
    );
  }

  void _showMessage(String message) {
    final messenger = scaffoldMessengerKey.currentState;
    if (messenger == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _pickEntryDate() async {
    try {
      final picked = await showDatePicker(
        context: navigatorKey.currentContext!,
        initialDate: selectedEntryDate,
        firstDate: DateTime(2020),
        lastDate: DateTime(2100),
        helpText: 'Select transaction date',
      );
      if (picked != null && mounted) {
        setState(() {
          selectedEntryDate = picked;
          entryDateController.text = DateFormat('dd/MM/yy').format(picked);
        });
      }
    } catch (_) {
      _showMessage('Enter the date as DD/MM/YY or use the calendar.');
    }
  }

  bool _readEntryDate() {
    try {
      selectedEntryDate = DateFormat('dd/MM/yy')
          .parseStrict(entryDateController.text.trim());
      return true;
    } on FormatException {
      return false;
    }
  }

  void _clearForm() {
    titleController.clear();
    amountController.clear();
    categoryController.clear();
    selectedType = TransactionType.debit;
    selectedPaymentMode = 'Cash';
    selectedCurrency = 'INR';
    selectedEntryDate = DateTime.now();
    entryDateController.text = DateFormat('dd/MM/yy').format(selectedEntryDate);
    entryIsCleared = false;
  }

  void _addTransaction({Transaction? editing}) {
    final activeEditing = editing ?? editingTransaction;
    final title = titleController.text.trim();
    final amountText = amountController.text.trim();
    final selectedCategory = categoryController.text.trim();

    if (title.isEmpty || amountText.isEmpty) {
      _showMessage('Please enter title and amount.');
      return;
    }

    if (selectedCompanyId == null) {
      _showMessage('Choose a company before adding an entry.');
      return;
    }

    if (!_readEntryDate()) {
      _showMessage('Enter a valid date as DD/MM/YY.');
      return;
    }

    final parsedAmount = double.tryParse(amountText);
    if (parsedAmount == null || parsedAmount <= 0) {
      _showMessage('Amount must be greater than zero.');
      return;
    }

    final finalCategory = baseCategories.contains(selectedCategory)
        ? selectedCategory
        : 'Sales';
    final newTransaction = Transaction(
      id: activeEditing?.id ?? nextTransactionId++,
      title: title,
      amount: parsedAmount,
      type: selectedType,
      category: finalCategory,
      currency: selectedCurrency,
      paymentMode: selectedPaymentMode,
      date: selectedEntryDate,
      isCleared: entryIsCleared,
      ledgerType: ledgerType,
      companyId: selectedCompanyId,
    );

    setState(() {
      if (activeEditing != null) {
        final index = transactions.indexWhere(
          (item) => item.id == activeEditing.id,
        );
        if (index >= 0) {
          transactions[index] = newTransaction;
        }
      } else {
        transactions.insert(0, newTransaction);
      }
    });

    _saveState();
    _clearForm();
    editingTransaction = null;
    if (screen == Screen.newEntry) {
      setState(() => screen = Screen.home);
    } else {
      Navigator.of(context).pop();
    }
  }

  void _deleteTransaction(int id) {
    setState(() {
      transactions.removeWhere((item) => item.id == id);
    });
    _saveState();
  }

  void _toggleCleared(Transaction transaction) {
    setState(() {
      final index = transactions.indexWhere(
        (item) => item.id == transaction.id,
      );
      if (index >= 0) {
        transactions[index] = Transaction(
          id: transaction.id,
          title: transaction.title,
          amount: transaction.amount,
          type: transaction.type,
          category: transaction.category,
          currency: transaction.currency,
          paymentMode: transaction.paymentMode,
          date: transaction.date,
          isCleared: !transaction.isCleared,
          ledgerType: transaction.ledgerType,
          companyId: transaction.companyId,
        );
      }
    });
    _saveState();
  }

  void _openTransactionEditor({Transaction? editing}) {
    editingTransaction = editing;
    if (editing != null) {
      titleController.text = editing.title;
      amountController.text = editing.amount.toString();
      categoryController.text = baseCategories.contains(editing.category)
          ? editing.category
          : 'Sales';
      selectedType = editing.type;
      selectedCurrency = editing.currency;
      selectedPaymentMode = editing.paymentMode;
      selectedEntryDate = editing.date;
      entryDateController.text = DateFormat('dd/MM/yy').format(editing.date);
      entryIsCleared = editing.isCleared;
    } else {
      _clearForm();
    }

    setState(() => screen = Screen.newEntry);
  }

  void _showAddTransactionDialog({Transaction? editing}) {
    _openTransactionEditor(editing: editing);
    /*
    showDialog(
      context: context,
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(
                editing == null ? 'Add transaction' : 'Edit transaction',
              ),
              content: SingleChildScrollView(
                child: SizedBox(
                  width: 360,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: titleController,
                        decoration: const InputDecoration(labelText: 'Title'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: amountController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(labelText: 'Amount'),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: currencyOptions.contains(selectedCurrency)
                            ? selectedCurrency
                            : 'INR',
                        decoration: const InputDecoration(
                          labelText: 'Currency',
                        ),
                        items: currencyOptions
                            .map(
                              (currency) => DropdownMenuItem(
                                value: currency,
                                child: Text(currency),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setDialogState(() => selectedCurrency = value);
                            setState(() => selectedCurrency = value);
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<TransactionType>(
                        initialValue: selectedType,
                        decoration: const InputDecoration(labelText: 'Type'),
                        items: const [
                          DropdownMenuItem(
                            value: TransactionType.credit,
                            child: Text('Credit'),
                          ),
                          DropdownMenuItem(
                            value: TransactionType.debit,
                            child: Text('Debit'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setDialogState(() => selectedType = value);
                            setState(() => selectedType = value);
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: selectedPaymentMode,
                        decoration: const InputDecoration(
                          labelText: 'Payment mode',
                        ),
                        items: paymentModes
                            .map(
                              (mode) => DropdownMenuItem(
                                value: mode,
                                child: Text(mode),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setDialogState(() => selectedPaymentMode = value);
                            setState(() => selectedPaymentMode = value);
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue:
                            allCategories.contains(
                              categoryController.text.trim(),
                            )
                            ? categoryController.text.trim()
                            : 'Yarn',
                        decoration: const InputDecoration(
                          labelText: 'Category',
                        ),
                        items: allCategories
                            .map(
                              (category) => DropdownMenuItem(
                                value: category,
                                child: Text(category),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value != null) {
                            categoryController.text = value;
                            setDialogState(() {});
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => _addTransaction(editing: editing),
                  child: Text(editing == null ? 'Save' : 'Update'),
                ),
              ],
            );
          },
        );
      },
    );
    */
  }

  void _addCompany() {
    final name = companyNameController.text.trim();
    final address = companyAddressController.text.trim();
    final mobileDigits = companyMobileController.text.replaceAll(
      RegExp(r'\D'),
      '',
    );
    final gstin = companyGstinController.text.trim();

    if (name.isEmpty || address.isEmpty || mobileDigits.length != 10) {
      _showMessage('Company name, address and mobile number are required.');
      return;
    }
    final mobile = '+91$mobileDigits';

    final companyId = nextCompanyId++;
    setState(() {
      companies.add(
        Company(
          id: companyId,
          name: name,
          address: address,
          mobile: mobile,
          gstin: gstin.isEmpty ? null : gstin,
        ),
      );
      selectedCompanyId = companyId;
    });

    _saveState();
    companyNameController.clear();
    companyAddressController.clear();
    companyMobileController.clear();
    companyGstinController.clear();
    if (screen == Screen.addCompany) {
      setState(() => screen = Screen.home);
    } else {
      Navigator.of(context).pop();
    }
  }

  Widget _formField(
    TextEditingController controller,
    String label, {
    TextInputType? keyboardType,
    int maxLines = 1,
    bool required = true,
    List<TextInputFormatter>? inputFormatters,
    String? prefixText,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        hintText: required ? null : 'Optional',
        prefixText: prefixText,
      ),
    );
  }

  Widget _pageHeader(
    String eyebrow,
    String title,
    String subtitle,
    VoidCallback onBack,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        IconButton(onPressed: onBack, icon: const Icon(Icons.arrow_back)),
        const SizedBox(height: 18),
        Text(
          eyebrow.toUpperCase(),
          style: TextStyle(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.4,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          title,
          style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 15,
          ),
        ),
      ],
    );
  }

  Widget _buildAddCompanyPage() {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _pageHeader(
                    'Company profile',
                    'Add a company',
                    'Keep the details close to every transaction.',
                    () => setState(() => screen = Screen.companies),
                  ),
                  const SizedBox(height: 32),
                  _formField(companyNameController, 'Company name'),
                  const SizedBox(height: 16),
                  _formField(companyAddressController, 'Address', maxLines: 3),
                  const SizedBox(height: 16),
                  _formField(
                    companyMobileController,
                    'Mobile number',
                    keyboardType: TextInputType.phone,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(10),
                    ],
                    prefixText: '+91 ',
                  ),
                  const SizedBox(height: 16),
                  _formField(companyGstinController, 'GSTIN', required: false),
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _addCompany,
                      icon: const Icon(Icons.check),
                      label: const Text('Save company'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNewEntryPage() {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _pageHeader(
                    'New transaction',
                    'Add an entry',
                    'Capture the movement once, and keep the ledger clear.',
                    () => setState(() => screen = Screen.home),
                  ),
                  const SizedBox(height: 32),
                  _formField(titleController, 'Title', required: false),
                  const SizedBox(height: 16),
                  _formField(
                    amountController,
                    'Amount',
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<TransactionType>(
                    initialValue: selectedType,
                    decoration: const InputDecoration(labelText: 'Type'),
                    items: const [
                      DropdownMenuItem(
                        value: TransactionType.credit,
                        child: Text('Credit'),
                      ),
                      DropdownMenuItem(
                        value: TransactionType.debit,
                        child: Text('Debit'),
                      ),
                    ],
                    onChanged: (value) => setState(
                      () => selectedType = value ?? TransactionType.debit,
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue:
                        baseCategories.contains(categoryController.text)
                        ? categoryController.text
                        : 'Sales',
                    decoration: const InputDecoration(labelText: 'Category'),
                    items: baseCategories
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(value),
                          ),
                        )
                        .toList(),
                    onChanged: (value) =>
                        categoryController.text = value ?? 'Sales',
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: currencyOptions.contains(selectedCurrency)
                        ? selectedCurrency
                        : 'INR',
                    decoration: const InputDecoration(labelText: 'Currency'),
                    items: currencyOptions
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(value),
                          ),
                        )
                        .toList(),
                    onChanged: (value) =>
                        setState(() => selectedCurrency = value ?? 'INR'),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: paymentModes.contains(selectedPaymentMode)
                        ? selectedPaymentMode
                        : 'Cash',
                    decoration: const InputDecoration(
                      labelText: 'Payment mode',
                    ),
                    items: paymentModes
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(value),
                          ),
                        )
                        .toList(),
                    onChanged: (value) =>
                        setState(() => selectedPaymentMode = value ?? 'Cash'),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: TextField(
                      controller: entryDateController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9/]')),
                        LengthLimitingTextInputFormatter(8),
                      ],
                      textInputAction: TextInputAction.done,
                      decoration: InputDecoration(
                        labelText: 'Date',
                        hintText: 'DD/MM/YY',
                        helperText: 'Use DD/MM/YY or choose from the calendar',
                        suffixIcon: IconButton(
                          tooltip: 'Open calendar',
                          onPressed: _pickEntryDate,
                          icon: const Icon(Icons.calendar_month_outlined),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          setState(() => entryIsCleared = !entryIsCleared),
                      icon: Icon(
                        entryIsCleared
                            ? Icons.check_circle
                            : Icons.radio_button_unchecked,
                      ),
                      label: Text(
                        entryIsCleared
                            ? 'Marked as cleared'
                            : 'Mark as cleared',
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _addTransaction,
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('Save entry'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _summaryCard(String label, double value, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            '$selectedCurrency ${value.toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWelcomePage() {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: const Color(0xff355c4d),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.account_balance_wallet_outlined,
                    color: Colors.white,
                    size: 26,
                  ),
                ),
                const SizedBox(height: 28),
                const Text(
                  'Start your ledger',
                  style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
                Text(
                  'Choose your ledger',
                  style: TextStyle(
                    fontSize: 16,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 28),
                _ledgerChoiceCard(
                  title: 'Sales ledger',
                  subtitle: 'Track customer invoices, receipts, and credits.',
                  icon: Icons.trending_up,
                  color: const Color(0xffd9ebef),
                  onTap: () {
                    setState(() {
                      ledgerType = LedgerType.sales;
                      screen = Screen.companies;
                    });
                    _saveState();
                  },
                ),
                const SizedBox(height: 14),
                _ledgerChoiceCard(
                  title: 'Purchase ledger',
                  subtitle: 'Track supplier bills, payments, and debits.',
                  icon: Icons.shopping_bag_outlined,
                  color: const Color(0xf0f1dedb),
                  onTap: () {
                    setState(() {
                      ledgerType = LedgerType.purchase;
                      screen = Screen.companies;
                    });
                    _saveState();
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _ledgerChoiceCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest
          .withValues(alpha: 0.45),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                child: Icon(icon, color: const Color(0xff355c4d)),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward, size: 22),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHomePage() {
    final availableCategories = ['All', ...allCategories];
    final activeCompany = selectedCompany;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => setState(() => screen = Screen.companies),
        ),
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              ledgerType == LedgerType.sales
                  ? 'Sales Ledger'
                  : 'Purchase Ledger',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            Text(
              activeCompany?.name ?? 'No company selected',
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'Companies',
            icon: const Icon(Icons.business_center_outlined),
            onPressed: () => setState(() => screen = Screen.companies),
          ),
          IconButton(
            icon: Icon(
              themeMode == ThemeMode.dark ? Icons.light_mode : Icons.dark_mode,
            ),
            onPressed: () {
              setState(() {
                themeMode = themeMode == ThemeMode.dark
                    ? ThemeMode.light
                    : ThemeMode.dark;
              });
              _saveState();
            },
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: ledgerType == LedgerType.sales
                        ? [Colors.green.shade700, Colors.green.shade500]
                        : [
                            Colors.deepPurple.shade700,
                            Colors.deepPurple.shade500,
                          ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Total Balance',
                          style: TextStyle(color: Colors.white70, fontSize: 16),
                        ),
                        Text(
                          selectedCurrency,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '$selectedCurrency ${totalBalance.toStringAsFixed(2)}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 30,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: _summaryCard('Credit', totalCredit, Colors.green),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _summaryCard('Debit', totalDebit, Colors.red),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              TextField(
                onChanged: (value) => setState(() => searchText = value),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search transaction or category',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: statusFilters.map((filter) {
                        return ChoiceChip(
                          label: Text(filter),
                          selected: statusFilter == filter,
                          onSelected: (_) =>
                              setState(() => statusFilter = filter),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final pickedStart = await showDatePicker(
                        context: context,
                        initialDate: startDate ?? DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100),
                      );
                      if (pickedStart != null) {
                        setState(() => startDate = pickedStart);
                      }
                    },
                    icon: const Icon(Icons.tune, size: 18),
                    label: const Text('Filter'),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: categoryFilter,
                decoration: const InputDecoration(labelText: 'Category'),
                items: availableCategories
                    .map(
                      (category) => DropdownMenuItem(
                        value: category,
                        child: Text(category),
                      ),
                    )
                    .toList(),
                onChanged: (value) =>
                    setState(() => categoryFilter = value ?? 'All'),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  const Text(
                    'Transactions',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (filteredTransactions.isEmpty)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 28),
                    child: Text('No transactions found. Add one to begin.'),
                  ),
                )
              else
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: filteredTransactions.length,
                  itemBuilder: (context, index) {
                    final transaction = filteredTransactions[index];
                    final isCredit = transaction.type == TransactionType.credit;
                    final accentColor = transaction.isCleared
                        ? Colors.red
                        : Colors.green;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: transaction.isCleared
                            ? Colors.red.withValues(alpha: 0.08)
                            : Colors.green.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: ListTile(
                        dense: true,
                        minVerticalPadding: 8,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 4,
                        ),
                        leading: CircleAvatar(
                          backgroundColor: accentColor.withValues(alpha: 0.15),
                          child: Icon(
                            isCredit
                                ? Icons.arrow_downward
                                : Icons.arrow_upward,
                            color: accentColor,
                          ),
                        ),
                        title: Row(
                          children: [
                            Expanded(child: Text(transaction.title)),
                            Text(
                              '${transaction.type.name[0].toUpperCase()}${transaction.type.name.substring(1)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${isCredit ? '+' : '-'}${transaction.currency} ${transaction.amount.toStringAsFixed(2)}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: isCredit ? Colors.green : Colors.red,
                              ),
                            ),
                            Text(
                              '${transaction.category} • ${transaction.paymentMode}',
                            ),
                            Text(
                              DateFormat('dd/MM/yy').format(transaction.date),
                            ),
                          ],
                        ),
                        trailing: SizedBox(
                          width: 88,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Edit',
                                constraints: const BoxConstraints.tightFor(
                                  width: 28,
                                  height: 28,
                                ),
                                padding: EdgeInsets.zero,
                                onPressed: () => _showAddTransactionDialog(
                                  editing: transaction,
                                ),
                                icon: const Icon(Icons.edit, size: 17),
                              ),
                              IconButton(
                                tooltip: 'Delete',
                                constraints: const BoxConstraints.tightFor(
                                  width: 28,
                                  height: 28,
                                ),
                                padding: EdgeInsets.zero,
                                onPressed: () =>
                                    _deleteTransaction(transaction.id),
                                icon: const Icon(
                                  Icons.delete_outline,
                                  size: 18,
                                ),
                              ),
                              IconButton(
                                tooltip: transaction.isCleared
                                    ? 'Mark pending'
                                    : 'Mark cleared',
                                constraints: const BoxConstraints.tightFor(
                                  width: 28,
                                  height: 28,
                                ),
                                padding: EdgeInsets.zero,
                                onPressed: () => _toggleCleared(transaction),
                                icon: Icon(
                                  transaction.isCleared
                                      ? Icons.cancel_outlined
                                      : Icons.check_circle_outline,
                                  size: 18,
                                  color: accentColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          editingTransaction = null;
          _clearForm();
          setState(() => screen = Screen.newEntry);
        },
        icon: const Icon(Icons.add),
        label: const Text('New entry'),
      ),
    );
  }

  Widget _buildCompanyPage() {
    final filteredCompanies = companies.where((company) {
      final query = searchText.toLowerCase();
      if (query.isEmpty) return true;
      return company.name.toLowerCase().contains(query) ||
          company.address.toLowerCase().contains(query) ||
          company.mobile.contains(query);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => setState(() => screen = Screen.welcome),
        ),
        title: Text(
          ledgerType == LedgerType.sales
              ? 'Choose company for sales'
              : 'Choose company for purchases',
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              onChanged: (value) => setState(() => searchText = value),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search company name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: filteredCompanies.isEmpty
                  ? const Center(child: Text('No companies saved yet.'))
                  : ListView.builder(
                      itemCount: filteredCompanies.length,
                      itemBuilder: (context, index) {
                        final company = filteredCompanies[index];
                        return Card(
                          color: company.id == selectedCompanyId
                              ? Theme.of(context).colorScheme.primaryContainer
                              : null,
                          margin: const EdgeInsets.only(bottom: 12),
                          child: ListTile(
                            leading: CircleAvatar(
                              child: Text(
                                company.name.substring(0, 1).toUpperCase(),
                              ),
                            ),
                            title: Text(company.name),
                            trailing: const Icon(Icons.arrow_forward),
                            onTap: () {
                              setState(() {
                                selectedCompanyId = company.id;
                                screen = Screen.home;
                              });
                            },
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(company.address),
                                Text(company.mobile),
                                if (company.gstin != null &&
                                    company.gstin!.isNotEmpty)
                                  Text('GSTIN: ${company.gstin}'),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => setState(() => screen = Screen.addCompany),
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Add company'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appTheme = ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: ledgerType == LedgerType.sales
            ? Colors.green
            : Colors.deepPurple,
        brightness: themeMode == ThemeMode.dark
            ? Brightness.dark
            : Brightness.light,
      ),
      useMaterial3: true,
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Ledger App',
      navigatorKey: navigatorKey,
      scaffoldMessengerKey: scaffoldMessengerKey,
      theme: appTheme,
      darkTheme: appTheme.copyWith(brightness: Brightness.dark),
      themeMode: themeMode,
      home: screen == Screen.welcome
          ? _buildWelcomePage()
          : screen == Screen.addCompany
          ? _buildAddCompanyPage()
          : screen == Screen.newEntry
          ? _buildNewEntryPage()
          : screen == Screen.companies
          ? _buildCompanyPage()
          : _buildHomePage(),
    );
  }
}
