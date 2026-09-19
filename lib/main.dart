import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:image/image.dart' as image;
import 'package:intl/intl.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';

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
    required this.receivedAmount,
    required this.ledgerType,
    this.companyId,
    this.attachmentPath,
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
  final double receivedAmount;
  final LedgerType ledgerType;
  final int? companyId;
  final String? attachmentPath;

  double get pendingAmount => (amount - receivedAmount).clamp(0, amount);

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
    'receivedAmount': receivedAmount,
    'ledgerType': ledgerType.name,
    'companyId': companyId,
    'attachmentPath': attachmentPath,
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
        receivedAmount: (map['receivedAmount'] as num?)?.toDouble() ??
          ((map['isCleared'] as bool? ?? false)
            ? ((map['amount'] as num?)?.toDouble() ?? 0.0)
            : 0.0),
      ledgerType: LedgerType.values.firstWhere(
        (value) => value.name == (map['ledgerType'] ?? 'sales'),
        orElse: () => LedgerType.sales,
      ),
      companyId: map['companyId'] as int?,
      attachmentPath: map['attachmentPath'] as String?,
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
  final List<String> paymentModes = [
    'NEFT',
    'UPI',
    'Netbanking',
    'Cash',
    'Cheque',
  ];
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
  final TextEditingController receivedAmountController =
      TextEditingController();
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
  String? attachmentPath;
  DateTime selectedEntryDate = DateTime.now();
  bool entryIsCleared = false;
  int? selectedCompanyId;
  Transaction? editingTransaction;
  Timer? searchDebounce;
  bool showStartupLogo = true;

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
    receivedAmountController.dispose();
    categoryController.dispose();
    companyNameController.dispose();
    companyAddressController.dispose();
    companyMobileController.dispose();
    companyGstinController.dispose();
    entryDateController.dispose();
    searchDebounce?.cancel();
    super.dispose();
  }

  void _updateSearch(String value) {
    searchDebounce?.cancel();
    searchDebounce = Timer(const Duration(milliseconds: 180), () {
      if (mounted) setState(() => searchText = value);
    });
  }

  void _proceedFromStartup() {
    if (!showStartupLogo || !mounted) return;
    setState(() => showStartupLogo = false);
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
            receivedAmount: transaction.receivedAmount,
            ledgerType: transaction.ledgerType,
            companyId: legacyCompanyId,
            attachmentPath: transaction.attachmentPath,
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

  Future<void> _pickAttachment() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'jpg', 'jpeg'],
      );
      if (result != null && result.files.single.path != null && mounted) {
        setState(() => attachmentPath = result.files.single.path);
      }
    } catch (_) {
      _showMessage('The file could not be attached. Please choose a PDF or JPG.');
    }
  }

  String _companyDetails(Company company) {
    final gstin = company.gstin == null || company.gstin!.isEmpty
        ? ''
        : '\nGSTIN: ${company.gstin}';
    return '${company.name}\n${company.address}\n${company.mobile}$gstin';
  }

  String _shareText(Transaction transaction, {required bool includeTransaction}) {
    final company = companies.cast<Company?>().firstWhere(
      (item) => item?.id == transaction.companyId,
      orElse: () => null,
    );
    final companyText = company == null ? '' : _companyDetails(company);
    if (!includeTransaction) return companyText;
    return 'Transaction: ${transaction.title}\n'
        'Total: ${transaction.currency} ${transaction.amount.toStringAsFixed(2)}\n'
        'Received: ${transaction.currency} ${transaction.receivedAmount.toStringAsFixed(2)}\n'
        'Pending: ${transaction.currency} ${transaction.pendingAmount.toStringAsFixed(2)}\n'
        'Type: ${transaction.type.name}\n'
        'Payment mode: ${transaction.paymentMode}\n'
        'Date: ${DateFormat('dd/MM/yy').format(transaction.date)}\n\n'
        'Company\n$companyText';
  }

  Future<void> _shareContent({
    required String text,
    required String fileName,
    required String format,
  }) async {
    try {
      Uint8List bytes;
      String mimeType;
      String extension;
      if (format == 'PDF') {
        final document = pw.Document();
        document.addPage(
          pw.MultiPage(
            build: (_) => [
              pw.Padding(
                padding: const pw.EdgeInsets.all(32),
                child: pw.Text(text),
              ),
            ],
          ),
        );
        bytes = Uint8List.fromList(await document.save());
        mimeType = 'application/pdf';
        extension = 'pdf';
      } else {
        final lineCount = text.split('\n').length;
        final canvas = image.Image(
          width: 1600,
          height: (lineCount * 34 + 80).clamp(900, 12000),
        );
        image.drawString(
          canvas,
          text.replaceAll('•', '-'),
          font: image.arial24,
          x: 40,
          y: 40,
        );
        bytes = Uint8List.fromList(image.encodeJpg(canvas, quality: 90));
        mimeType = 'image/jpeg';
        extension = 'jpg';
      }
      final temporaryDirectory = await getTemporaryDirectory();
      final safeFileName = fileName.replaceAll(RegExp(r'[^a-zA-Z0-9_-]+'), '_');
      final outputFile = File(
        '${temporaryDirectory.path}${Platform.pathSeparator}$safeFileName.$extension',
      );
      await outputFile.writeAsBytes(bytes, flush: true);
      final result = await SharePlus.instance.share(
        ShareParams(
          text: text,
          files: [
            XFile(outputFile.path, mimeType: mimeType),
          ],
        ),
      );
      if (result.status == ShareResultStatus.unavailable) {
        _showMessage('Sharing is not available on this device.');
      }
    } catch (error) {
      debugPrint('Share failed: $error');
      if (mounted) {
        _showMessage('Could not create or share this file on the device.');
      }
    }
  }

  Future<void> _shareTransaction(
    Transaction transaction, {
    required bool includeTransaction,
    required String format,
  }) async {
    await _shareContent(
      text: _shareText(transaction, includeTransaction: includeTransaction),
      fileName: includeTransaction ? 'transaction' : 'company',
      format: format,
    );
  }

  String _companyBillText(Company company, List<Transaction> entries) {
    final lines = <String>[
      'COMPANY TRANSACTION BILL',
      '',
      _companyDetails(company),
      '',
      'Transactions',
    ];
    for (final transaction in entries) {
      lines.add(
        '${DateFormat('dd/MM/yy').format(transaction.date)} | '
        '${transaction.title} | ${transaction.paymentMode} | '
        'Total ${transaction.currency} ${transaction.amount.toStringAsFixed(2)} | '
        'Received ${transaction.currency} ${transaction.receivedAmount.toStringAsFixed(2)} | '
        'Pending ${transaction.currency} ${transaction.pendingAmount.toStringAsFixed(2)}',
      );
    }
    final total = entries.fold(0.0, (sum, item) => sum + item.amount);
    final received = entries.fold(0.0, (sum, item) => sum + item.receivedAmount);
    final pending = entries.fold(0.0, (sum, item) => sum + item.pendingAmount);
    lines.add('');
    lines.add('Grand total: INR ${total.toStringAsFixed(2)}');
    lines.add('Total received: INR ${received.toStringAsFixed(2)}');
    lines.add('Total pending: INR ${pending.toStringAsFixed(2)}');
    return lines.join('\n');
  }

  Future<void> _saveCompanyBill(Company company, List<Transaction> entries) async {
    try {
      final document = pw.Document();
      document.addPage(
        pw.MultiPage(
          build: (_) => [
            pw.Padding(
              padding: const pw.EdgeInsets.all(32),
              child: pw.Text(_companyBillText(company, entries)),
            ),
          ],
        ),
      );
      final bytes = await document.save();
      final safeCompanyName = company.name.replaceAll(
        RegExp(r'[^a-zA-Z0-9_-]+'),
        '_',
      );
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final suggestedName = '${safeCompanyName}_bill_$timestamp.pdf';
      final selectedPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save company bill',
        fileName: suggestedName,
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );
      if (selectedPath == null || selectedPath.isEmpty) return;
      final outputFile = File(selectedPath.toLowerCase().endsWith('.pdf')
          ? selectedPath
          : '$selectedPath.pdf');
      await outputFile.writeAsBytes(bytes, flush: true);
      if (mounted) {
        _showMessage('Bill saved as PDF.');
      }
    } catch (error) {
      debugPrint('Bill creation failed: $error');
      if (mounted) {
        _showMessage('The bill could not be saved. Please try again.');
      }
    }
  }

  Future<void> _showCompanyBillDialog() async {
    final company = selectedCompany;
    if (company == null) {
      _showMessage('Choose a company before creating a bill.');
      return;
    }
    final entries = transactions
        .where(
          (transaction) =>
              transaction.companyId == company.id &&
              transaction.ledgerType == ledgerType,
        )
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    if (entries.isEmpty) {
      _showMessage('Add a transaction before creating a company bill.');
      return;
    }
    final shouldCreate = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Create company bill'),
        content: Text(
          '${entries.length} transactions will be included in the PDF bill.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Create PDF'),
          ),
        ],
      ),
    );
    if (shouldCreate == true && mounted) {
      await _saveCompanyBill(company, entries);
    }
  }

  Future<void> _showShareDialog(Transaction transaction) async {
    final includeTransaction = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('What should be shared?'),
        content: const Text('Choose the details to include in the file.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Company only'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Transaction + company'),
          ),
        ],
      ),
    );
    if (includeTransaction == null || !mounted) return;
    final format = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Choose file format'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 'JPG'),
            child: const Text('JPG image'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, 'PDF'),
            child: const Text('PDF document'),
          ),
        ],
      ),
    );
    if (format != null && mounted) {
      await _shareTransaction(
        transaction,
        includeTransaction: includeTransaction,
        format: format,
      );
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
    receivedAmountController.clear();
    categoryController.clear();
    selectedType = TransactionType.debit;
    selectedPaymentMode = 'Cash';
    selectedCurrency = 'INR';
    selectedEntryDate = DateTime.now();
    entryDateController.text = DateFormat('dd/MM/yy').format(selectedEntryDate);
    entryIsCleared = false;
    attachmentPath = null;
  }

  void _addTransaction({Transaction? editing}) {
    final activeEditing = editing ?? editingTransaction;
    final title = titleController.text.trim();
    final amountText = amountController.text.trim();
    final receivedText = receivedAmountController.text.trim();
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

    final parsedReceived = receivedText.isEmpty
        ? 0.0
        : double.tryParse(receivedText);
    if (parsedReceived == null || parsedReceived < 0 || parsedReceived > parsedAmount) {
      _showMessage('Received amount must be between zero and the total amount.');
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
      isCleared: parsedReceived >= parsedAmount,
      receivedAmount: parsedReceived,
      ledgerType: ledgerType,
      companyId: selectedCompanyId,
      attachmentPath: attachmentPath,
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
          receivedAmount: transaction.isCleared ? 0 : transaction.amount,
          ledgerType: transaction.ledgerType,
          companyId: transaction.companyId,
          attachmentPath: transaction.attachmentPath,
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
      receivedAmountController.text = editing.receivedAmount.toString();
      categoryController.text = baseCategories.contains(editing.category)
          ? editing.category
          : 'Sales';
      selectedType = editing.type;
      selectedCurrency = editing.currency;
      selectedPaymentMode = editing.paymentMode;
      selectedEntryDate = editing.date;
      entryDateController.text = DateFormat('dd/MM/yy').format(editing.date);
      entryIsCleared = editing.isCleared;
      attachmentPath = editing.attachmentPath;
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      maxLines: maxLines,
      style: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w800,
        color: isDark ? Colors.white : null,
        letterSpacing: -0.2,
      ),
      decoration: InputDecoration(
        labelText: label,
        hintText: required ? null : 'Optional',
        prefixText: prefixText,
        filled: true,
        fillColor: isDark ? const Color(0xFF2A3342) : null,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 18,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(
            color: isDark ? const Color(0xFF3A4759) : Colors.grey.shade300,
            width: 1.3,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(
            color: isDark
                ? Colors.white
                : Theme.of(context).colorScheme.primary,
            width: 1.6,
          ),
        ),
        labelStyle: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: isDark ? Colors.white70 : null,
        ),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final optionTextColor = isDark ? Colors.white : Colors.black;

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
                  _formField(
                    receivedAmountController,
                    'Received amount',
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    required: false,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Leave this at zero for a pending balance. You can update it later.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<TransactionType>(
                    initialValue: selectedType,
                    dropdownColor:
                        Theme.of(context).brightness == Brightness.dark
                        ? const Color(0xFF2A3342)
                        : null,
                    decoration: InputDecoration(
                      labelText: 'Type',
                      filled: true,
                      fillColor: Theme.of(context).brightness == Brightness.dark
                          ? const Color(0xFF2A3342)
                          : null,
                      labelStyle: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.white70
                            : null,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide(
                          color: Theme.of(context).brightness == Brightness.dark
                              ? const Color(0xFF3A4759)
                              : Colors.grey.shade300,
                          width: 1.3,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide(
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.white
                              : Theme.of(context).colorScheme.primary,
                          width: 1.6,
                        ),
                      ),
                    ),
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.white
                          : null,
                    ),
                    items: [
                      DropdownMenuItem(
                        value: TransactionType.credit,
                        child: Text(
                          'Credit',
                          style: TextStyle(color: optionTextColor),
                        ),
                      ),
                      DropdownMenuItem(
                        value: TransactionType.debit,
                        child: Text(
                          'Debit',
                          style: TextStyle(color: optionTextColor),
                        ),
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
                    dropdownColor:
                        Theme.of(context).brightness == Brightness.dark
                        ? const Color(0xFF2A3342)
                        : null,
                    decoration: InputDecoration(
                      labelText: 'Category',
                      filled: true,
                      fillColor: Theme.of(context).brightness == Brightness.dark
                          ? const Color(0xFF2A3342)
                          : null,
                      labelStyle: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.white70
                            : null,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide(
                          color: Theme.of(context).brightness == Brightness.dark
                              ? const Color(0xFF3A4759)
                              : Colors.grey.shade300,
                          width: 1.3,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide(
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.white
                              : Theme.of(context).colorScheme.primary,
                          width: 1.6,
                        ),
                      ),
                    ),
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.white
                          : null,
                    ),
                    items: baseCategories
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(
                              value,
                              style: TextStyle(color: optionTextColor),
                            ),
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
                    dropdownColor:
                        Theme.of(context).brightness == Brightness.dark
                        ? const Color(0xFF2A3342)
                        : null,
                    decoration: InputDecoration(
                      labelText: 'Currency',
                      filled: true,
                      fillColor: Theme.of(context).brightness == Brightness.dark
                          ? const Color(0xFF2A3342)
                          : null,
                      labelStyle: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.white70
                            : null,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide(
                          color: Theme.of(context).brightness == Brightness.dark
                              ? const Color(0xFF3A4759)
                              : Colors.grey.shade300,
                          width: 1.3,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide(
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.white
                              : Theme.of(context).colorScheme.primary,
                          width: 1.6,
                        ),
                      ),
                    ),
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.white
                          : null,
                    ),
                    items: currencyOptions
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(
                              value,
                              style: TextStyle(color: optionTextColor),
                            ),
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
                    dropdownColor:
                        Theme.of(context).brightness == Brightness.dark
                        ? const Color(0xFF2A3342)
                        : null,
                    decoration: InputDecoration(
                      labelText: 'Payment mode',
                      filled: true,
                      fillColor: Theme.of(context).brightness == Brightness.dark
                          ? const Color(0xFF2A3342)
                          : null,
                      labelStyle: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.white70
                            : null,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide(
                          color: Theme.of(context).brightness == Brightness.dark
                              ? const Color(0xFF3A4759)
                              : Colors.grey.shade300,
                          width: 1.3,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide(
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.white
                              : Theme.of(context).colorScheme.primary,
                          width: 1.6,
                        ),
                      ),
                    ),
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.white
                          : null,
                    ),
                    items: paymentModes
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(
                              value,
                              style: TextStyle(color: optionTextColor),
                            ),
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
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.white
                            : null,
                        letterSpacing: -0.2,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Date',
                        hintText: 'DD/MM/YY',
                        helperText: 'Use DD/MM/YY or choose from the calendar',
                        filled: true,
                        fillColor:
                            Theme.of(context).brightness == Brightness.dark
                            ? const Color(0xFF2A3342)
                            : null,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 18,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: BorderSide(
                            color:
                                Theme.of(context).brightness == Brightness.dark
                                ? const Color(0xFF3A4759)
                                : Colors.grey.shade300,
                            width: 1.3,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: BorderSide(
                            color:
                                Theme.of(context).brightness == Brightness.dark
                                ? Colors.white
                                : Theme.of(context).colorScheme.primary,
                            width: 1.6,
                          ),
                        ),
                        labelStyle: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.white70
                              : null,
                        ),
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
                      onPressed: _pickAttachment,
                      icon: const Icon(Icons.picture_as_pdf_outlined),
                      label: Text(
                        attachmentPath == null
                            ? 'Attach PDF or JPG'
                            : 'File attached: ${attachmentPath!.split(RegExp(r'[\\/]')).last}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        final total = double.tryParse(amountController.text) ?? 0;
                        setState(() {
                          entryIsCleared = !entryIsCleared;
                          receivedAmountController.text = entryIsCleared
                              ? total.toString()
                              : '0';
                        });
                      },
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
    final primary = ledgerType == LedgerType.sales
        ? const Color(0xFF10B981)
        : const Color(0xFF8B5CF6);
    final accent = ledgerType == LedgerType.sales
        ? const Color(0xFF6EE7B7)
        : const Color(0xFFC4B5FD);

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Theme.of(context).colorScheme.surface,
              Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
              Theme.of(context).colorScheme.secondary.withValues(alpha: 0.12),
            ],
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              top: 12,
              right: 16,
              child: IconButton(
                tooltip: themeMode == ThemeMode.dark
                    ? 'Switch to light mode'
                    : 'Switch to dark mode',
                icon: Icon(
                  themeMode == ThemeMode.dark
                      ? Icons.light_mode
                      : Icons.dark_mode,
                  color: themeMode == ThemeMode.dark
                      ? const Color(0xFFF8FAFC)
                      : const Color(0xFF334155),
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
            ),
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 620),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [primary, accent],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: primary.withValues(alpha: 0.28),
                          blurRadius: 18,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.account_balance_wallet_rounded,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    'Start your ledger',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.8,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Choose your ledger',
                    style: TextStyle(
                      color: themeMode == ThemeMode.dark
                          ? const Color(0xFFF8FAFC)
                          : const Color(0xFF334155),
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.1,
                    ),
                  ),
                  const SizedBox(height: 28),
                  _ledgerChoiceCard(
                    title: 'Sales ledger',
                    subtitle: 'Track customer invoices, receipts, and credits.',
                    icon: Icons.trending_up_rounded,
                    color: const Color(0xFFE7FFF5),
                    borderColor: const Color(0xFF10B981),
                    onTap: () {
                      setState(() {
                        ledgerType = LedgerType.sales;
                        screen = Screen.companies;
                      });
                      _saveState();
                    },
                  ),
                  const SizedBox(height: 16),
                  _ledgerChoiceCard(
                    title: 'Purchase ledger',
                    subtitle: 'Track supplier bills, payments, and debits.',
                    icon: Icons.shopping_bag_rounded,
                    color: const Color(0xFFF2ECFF),
                    borderColor: const Color(0xFF8B5CF6),
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
          ],
        ),
      ),
    );
  }

  Widget _ledgerChoiceCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required Color borderColor,
    required VoidCallback onTap,
  }) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            border: Border.all(
              color: borderColor.withValues(alpha: 0.45),
              width: 1.2,
            ),
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: borderColor.withValues(alpha: 0.12),
                blurRadius: 18,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [borderColor, borderColor.withValues(alpha: 0.72)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: Colors.white, size: 26),
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
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF172033),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: const Color(0xFF334155),
                        fontWeight: FontWeight.w600,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_rounded, size: 22, color: borderColor),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHomePage() {
    final visibleTransactions = filteredTransactions;
    final visibleBalance = visibleTransactions.fold(
      0.0,
      (total, item) => total + item.signedAmount,
    );
    final visibleCredit = visibleTransactions
        .where((item) => item.type == TransactionType.credit)
        .fold(0.0, (sum, item) => sum + item.amount);
    final visibleDebit = visibleTransactions
        .where((item) => item.type == TransactionType.debit)
        .fold(0.0, (sum, item) => sum + item.amount);
    final availableCategories = ['All', ...allCategories];
    final activeCompany = selectedCompany;
    final accentPrimary = ledgerType == LedgerType.sales
        ? const Color(0xFF10B981)
        : const Color(0xFF8B5CF6);
    final accentSecondary = ledgerType == LedgerType.sales
        ? const Color(0xFF6EE7B7)
        : const Color(0xFFC4B5FD);

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
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
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [accentPrimary, accentSecondary],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(26),
                  boxShadow: [
                    BoxShadow(
                      color: accentPrimary.withValues(alpha: 0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 12),
                    ),
                  ],
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
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            selectedCurrency,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '$selectedCurrency ${visibleBalance.toStringAsFixed(2)}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: _summaryCard('Credit', visibleCredit, Colors.green),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _summaryCard('Debit', visibleDebit, Colors.red),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              TextField(
                onChanged: _updateSearch,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search_rounded),
                  hintText: 'Search transaction or category',
                  filled: true,
                  fillColor: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: BorderSide(color: accentPrimary, width: 1.4),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: statusFilters.map((filter) {
                        final isSelected = statusFilter == filter;
                        final isDarkFilter = themeMode == ThemeMode.dark;

                        return ChoiceChip(
                          label: Text(filter),
                          selected: isSelected,
                          showCheckmark: false,
                          selectedColor: isDarkFilter
                              ? Colors.white.withValues(alpha: 0.96)
                              : accentPrimary.withValues(alpha: 0.15),
                          backgroundColor: isDarkFilter
                              ? const Color(0xFF2A3342)
                              : null,
                          labelStyle: TextStyle(
                            color: isSelected
                                ? (isDarkFilter
                                      ? Colors.black87
                                      : accentPrimary)
                                : (isDarkFilter
                                      ? Colors.white
                                      : Theme.of(context)
                                            .colorScheme
                                            .onSurface),
                            fontWeight: FontWeight.w700,
                          ),
                          side: BorderSide(
                            color: isDarkFilter
                                ? Colors.transparent
                                : accentPrimary.withValues(alpha: 0.2),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          onSelected: (_) =>
                              setState(() => statusFilter = filter),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Material(
                    color: themeMode == ThemeMode.dark
                        ? const Color(0xFF172235)
                        : Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(18),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: () async {
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
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 12,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.tune_rounded,
                              size: 20,
                              color: themeMode == ThemeMode.dark
                                  ? Colors.white
                                  : null,
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'Filter',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: categoryFilter,
                decoration: InputDecoration(
                  labelText: 'Category',
                  filled: true,
                  fillColor: themeMode == ThemeMode.dark
                      ? const Color(0xFF172235)
                      : Theme.of(context).colorScheme.surfaceContainerHighest,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: BorderSide.none,
                  ),
                ),
                style: TextStyle(
                  color: themeMode == ThemeMode.dark ? Colors.white : null,
                  fontWeight: FontWeight.w600,
                ),
                dropdownColor: themeMode == ThemeMode.dark
                    ? const Color(0xFF1D2A3D)
                    : null,
                items: availableCategories
                    .map(
                      (category) => DropdownMenuItem(
                        value: category,
                        child: Text(
                          category,
                          style: TextStyle(
                            color: themeMode == ThemeMode.dark
                                ? Colors.white
                                : null,
                          ),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) =>
                    setState(() => categoryFilter = value ?? 'All'),
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Transactions',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  OutlinedButton.icon(
                    onPressed: _showCompanyBillDialog,
                    icon: const Icon(Icons.receipt_long_outlined, size: 18),
                    label: const Text('Make bill'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (visibleTransactions.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 28),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: const Center(
                    child: Text('No transactions found. Add one to begin.'),
                  ),
                )
              else
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: visibleTransactions.length,
                  itemBuilder: (context, index) {
                    final transaction = visibleTransactions[index];
                    final isCredit = transaction.type == TransactionType.credit;
                    final accentColor = transaction.isCleared
                      ? Colors.green
                      : Colors.orange;
                    final cardColor = transaction.isCleared
                      ? Colors.green.withValues(alpha: 0.08)
                      : Colors.orange.withValues(alpha: 0.08);

                    return RepaintBoundary(
                      child: Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: cardColor,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: accentColor.withValues(alpha: 0.2),
                          width: 1,
                        ),
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
                                ? Icons.arrow_downward_rounded
                                : Icons.arrow_upward_rounded,
                            color: accentColor,
                          ),
                        ),
                        title: Row(
                          children: [
                            Expanded(child: Text(transaction.title)),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: accentColor.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                '${transaction.type.name[0].toUpperCase()}${transaction.type.name.substring(1)}',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 11,
                                  color: accentColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 4),
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
                              'Received: ${transaction.currency} ${transaction.receivedAmount.toStringAsFixed(2)}  •  Pending: ${transaction.currency} ${transaction.pendingAmount.toStringAsFixed(2)}',
                              style: TextStyle(
                                color: transaction.isCleared
                                    ? Colors.green
                                    : Colors.orange.shade800,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              DateFormat('dd/MM/yy').format(transaction.date),
                            ),
                          ],
                        ),
                        trailing: SizedBox(
                          width: 116,
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
                                icon: const Icon(Icons.edit_rounded, size: 17),
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
                                  Icons.delete_outline_rounded,
                                  size: 18,
                                ),
                              ),
                              IconButton(
                                tooltip: 'Share',
                                constraints: const BoxConstraints.tightFor(
                                  width: 28,
                                  height: 28,
                                ),
                                padding: EdgeInsets.zero,
                                onPressed: () => _showShareDialog(transaction),
                                icon: const Icon(Icons.share_outlined, size: 17),
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
        icon: const Icon(Icons.add_rounded),
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
    final primary = ledgerType == LedgerType.sales
        ? const Color(0xFF10B981)
        : const Color(0xFF8B5CF6);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
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
              onChanged: _updateSearch,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search_rounded),
                hintText: 'Search company name',
                filled: true,
                fillColor: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide.none,
                ),
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
                        final isSelected = company.id == selectedCompanyId;

                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? primary.withValues(alpha: 0.08)
                                : Theme.of(context)
                                      .colorScheme
                                      .surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: isSelected
                                  ? primary.withValues(alpha: 0.4)
                                  : Colors.transparent,
                              width: 1.1,
                            ),
                          ),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: primary.withValues(alpha: 0.13),
                              child: Text(
                                company.name.substring(0, 1).toUpperCase(),
                                style: TextStyle(
                                  color: primary,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            title: Text(company.name),
                            trailing: Icon(
                              Icons.arrow_forward_rounded,
                              color: primary,
                            ),
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
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('Add company'),
      ),
    );
  }

  Widget _buildCurrentScreen() {
    final page = switch (screen) {
      Screen.welcome => _buildWelcomePage(),
      Screen.home => _buildHomePage(),
      Screen.companies => _buildCompanyPage(),
      Screen.addCompany => _buildAddCompanyPage(),
      Screen.newEntry => _buildNewEntryPage(),
    };

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      reverseDuration: const Duration(milliseconds: 160),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        final slide = Tween<Offset>(
          begin: const Offset(0.025, 0),
          end: Offset.zero,
        ).animate(animation);
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(position: slide, child: child),
        );
      },
      child: KeyedSubtree(key: ValueKey<Screen>(screen), child: page),
    );
  }

  Widget _buildStartupLogo() {
    return Positioned.fill(
      child: RepaintBoundary(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _proceedFromStartup,
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFFEDE9FF),
                  Color(0xFFF5F7FF),
                  Color(0xFFE1FFF4),
                ],
              ),
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 360,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(32),
                      child: SvgPicture.asset(
                        'assets/asif_traders_logo.svg',
                        fit: BoxFit.contain,
                      ),
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

  @override
  Widget build(BuildContext context) {
    final seedColor = ledgerType == LedgerType.sales
        ? const Color(0xFF10B981)
        : const Color(0xFF8B5CF6);
    final isDark = themeMode == ThemeMode.dark;
    final baseBrightness = isDark ? Brightness.dark : Brightness.light;
    final textPrimary = isDark
        ? const Color(0xFFF8FAFC)
        : const Color(0xFF111827);
    final textSecondary = isDark
        ? const Color(0xFFB8C4D8)
        : const Color(0xFF475569);
    final panelDark = isDark
        ? const Color(0xFF0B1220)
        : const Color(0xFFF5F7FB);
    final panelSoft = isDark
        ? const Color(0xFF172235)
        : const Color(0xFFE2E8F0);
    final panelRaised = isDark
        ? const Color(0xFF1D2A3D)
        : const Color(0xFFFFFFFF);

    final appTheme = ThemeData(
      useMaterial3: true,
      brightness: baseBrightness,
      colorScheme:
          ColorScheme.fromSeed(
            seedColor: seedColor,
            brightness: baseBrightness,
          ).copyWith(
            surface: panelDark,
            onSurface: textPrimary,
            onSurfaceVariant: textSecondary,
            surfaceContainerHighest: panelSoft,
            primaryContainer: isDark ? const Color(0xFF153B36) : null,
            secondaryContainer: isDark ? const Color(0xFF302755) : null,
          ),
      scaffoldBackgroundColor: panelDark,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: panelRaised,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: panelSoft,
        hintStyle: TextStyle(
          color: isDark ? const Color(0xFF9EADC2) : textSecondary,
          fontWeight: FontWeight.w600,
        ),
        labelStyle: TextStyle(
          color: isDark ? const Color(0xFFD5DEEC) : textPrimary,
          fontWeight: FontWeight.w700,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: seedColor,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      textTheme: ThemeData(brightness: baseBrightness).textTheme
          .apply(bodyColor: textPrimary, displayColor: textPrimary)
          .copyWith(
            headlineMedium: const TextStyle(
              fontWeight: FontWeight.w800,
              letterSpacing: -0.6,
            ),
            titleLarge: const TextStyle(fontWeight: FontWeight.w800),
            titleMedium: const TextStyle(fontWeight: FontWeight.w700),
            bodyLarge: const TextStyle(fontWeight: FontWeight.w700),
            bodyMedium: const TextStyle(fontWeight: FontWeight.w600),
          ),
      iconTheme: IconThemeData(color: textPrimary),
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Asif Traders ledger app',
      navigatorKey: navigatorKey,
      scaffoldMessengerKey: scaffoldMessengerKey,
      themeAnimationDuration: Duration.zero,
      theme: appTheme,
      darkTheme: appTheme.copyWith(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0B1220),
      ),
      themeMode: themeMode,
      home: Stack(
        children: [
          _buildCurrentScreen(),
          if (showStartupLogo) _buildStartupLogo(),
        ],
      ),
    );
  }
}
