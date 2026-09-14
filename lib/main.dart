import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models/ledger_models.dart';
import 'services/ledger_storage.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  runApp(LedgerApp(prefs: prefs));
}

class LedgerApp extends StatefulWidget {
  const LedgerApp({super.key, required this.prefs});

  final SharedPreferences prefs;

  @override
  State<LedgerApp> createState() => _LedgerAppState();
}

class _LedgerAppState extends State<LedgerApp> {
  late final LedgerStorage storage;

  final List<String> currencyOptions = [
    'INR',
    'USD',
    'EUR',
    'GBP',
    'AED',
    'JPY',
  ];
  final List<String> paymentModes = ['Cash', 'Bank', 'UPI', 'Card', 'Credit'];
  final List<String> baseCategories = [
    'General',
    'Food',
    'Rent',
    'Travel',
    'Sales',
    'Purchase',
    'Salary',
    'Utilities',
    'Bank',
    'Other',
  ];

  final TextEditingController titleController = TextEditingController();
  final TextEditingController amountController = TextEditingController();
  final TextEditingController categoryController = TextEditingController();
  final TextEditingController companyNameController = TextEditingController();
  final TextEditingController companyAddressController =
      TextEditingController();
  final TextEditingController companyMobileController = TextEditingController();
  final TextEditingController companyGstinController = TextEditingController();

  LedgerType ledgerType = LedgerType.sales;
  ThemeMode themeMode = ThemeMode.light;
  String selectedCurrency = 'INR';
  String searchText = '';
  String categoryFilter = 'All';
  DateTime? startDate;
  DateTime? endDate;
  Screen screen = Screen.welcome;
  TransactionType selectedType = TransactionType.debit;
  String selectedPaymentMode = 'Cash';

  List<Transaction> transactions = [];
  List<Company> companies = [];
  List<String> customCategories = [];
  int nextTransactionId = 1;
  int nextCompanyId = 1;

  @override
  void initState() {
    super.initState();
    storage = LedgerStorage(widget.prefs);
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
    super.dispose();
  }

  List<String> get allCategories => [...baseCategories, ...customCategories];

  List<Transaction> get filteredTransactions {
    final query = searchText.trim().toLowerCase();

    return transactions.where((transaction) {
      final matchesLedger = transaction.ledgerType == ledgerType;
      final matchesSearch =
          query.isEmpty ||
          transaction.title.toLowerCase().contains(query) ||
          transaction.category.toLowerCase().contains(query) ||
          transaction.paymentMode.toLowerCase().contains(query);
      final matchesCategory =
          categoryFilter == 'All' || transaction.category == categoryFilter;
      final matchesStart =
          startDate == null || !transaction.date.isBefore(startDate!);
      final matchesEnd = endDate == null || !transaction.date.isAfter(endDate!);

      return matchesLedger &&
          matchesSearch &&
          matchesCategory &&
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

  List<Map<String, dynamic>> get monthlyReport {
    final monthlyMap = <String, double>{};

    for (final transaction in filteredTransactions) {
      final key = DateFormat('MMM yyyy').format(transaction.date);
      monthlyMap[key] = (monthlyMap[key] ?? 0.0) + transaction.signedAmount;
    }

    return monthlyMap.entries
        .map((entry) => {'month': entry.key, 'value': entry.value})
        .toList();
  }

  void _loadState() {
    final loadedTransactions = storage.loadTransactions();
    final loadedCompanies = storage.loadCompanies();
    final loadedCategories = storage.loadCategories();
    final loadedLedgerType = storage.loadLedgerType();
    final loadedTheme = storage.loadTheme();

    setState(() {
      transactions = loadedTransactions;
      companies = loadedCompanies;
      customCategories = loadedCategories;
      selectedCurrency = storage.loadCurrency();
      ledgerType = loadedLedgerType;
      themeMode = loadedTheme == ThemePreference.dark
          ? ThemeMode.dark
          : ThemeMode.light;
      nextTransactionId = transactions.isEmpty
          ? 1
          : transactions.map((e) => e.id).reduce((a, b) => a > b ? a : b) + 1;
      nextCompanyId = companies.isEmpty
          ? 1
          : companies.map((e) => e.id).reduce((a, b) => a > b ? a : b) + 1;
    });
  }

  void _saveState() {
    storage.save(
      transactions: transactions,
      companies: companies,
      categories: allCategories,
      currency: selectedCurrency,
      ledgerType: ledgerType,
      theme: themeMode == ThemeMode.dark
          ? ThemePreference.dark
          : ThemePreference.light,
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  void _clearForm() {
    titleController.clear();
    amountController.clear();
    categoryController.clear();
    selectedType = TransactionType.debit;
    selectedPaymentMode = 'Cash';
    selectedCurrency = 'INR';
  }

  void _addTransaction({Transaction? editing}) {
    final title = titleController.text.trim();
    final amountText = amountController.text.trim();
    final selectedCategory = categoryController.text.trim();

    if (title.isEmpty || amountText.isEmpty) {
      _showMessage('Please enter title and amount.');
      return;
    }

    final parsedAmount = double.tryParse(amountText);
    if (parsedAmount == null || parsedAmount <= 0) {
      _showMessage('Amount must be greater than zero.');
      return;
    }

    final finalCategory = selectedCategory.isEmpty
        ? 'General'
        : selectedCategory;
    if (!allCategories.contains(finalCategory)) {
      customCategories.add(finalCategory);
    }

    final newTransaction = Transaction(
      id: editing?.id ?? nextTransactionId++,
      title: title,
      amount: parsedAmount,
      type: selectedType,
      category: finalCategory,
      currency: selectedCurrency,
      paymentMode: selectedPaymentMode,
      date: editing?.date ?? DateTime.now(),
      isCleared: editing?.isCleared ?? false,
      ledgerType: ledgerType,
    );

    setState(() {
      if (editing != null) {
        final index = transactions.indexWhere((item) => item.id == editing.id);
        if (index >= 0) {
          transactions[index] = newTransaction;
        }
      } else {
        transactions.insert(0, newTransaction);
      }
    });

    _saveState();
    _clearForm();
    Navigator.of(context).pop();
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
        );
      }
    });
    _saveState();
  }

  void _showAddTransactionDialog({Transaction? editing}) {
    if (editing != null) {
      titleController.text = editing.title;
      amountController.text = editing.amount.toString();
      categoryController.text = editing.category;
      selectedType = editing.type;
      selectedCurrency = editing.currency;
      selectedPaymentMode = editing.paymentMode;
    } else {
      _clearForm();
    }

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
                        initialValue: selectedCurrency,
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
                        initialValue: categoryController.text.trim().isEmpty
                            ? 'General'
                            : categoryController.text.trim(),
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
                      const SizedBox(height: 12),
                      TextField(
                        controller: categoryController,
                        decoration: const InputDecoration(
                          labelText: 'Or add custom category',
                        ),
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
  }

  void _addCompany() {
    final name = companyNameController.text.trim();
    final address = companyAddressController.text.trim();
    final mobile = companyMobileController.text.trim();
    final gstin = companyGstinController.text.trim();

    if (name.isEmpty || address.isEmpty || mobile.isEmpty) {
      _showMessage('Company name, address and mobile number are required.');
      return;
    }

    setState(() {
      companies.add(
        Company(
          id: nextCompanyId++,
          name: name,
          address: address,
          mobile: mobile,
          gstin: gstin.isEmpty ? null : gstin,
        ),
      );
    });

    _saveState();
    companyNameController.clear();
    companyAddressController.clear();
    companyMobileController.clear();
    companyGstinController.clear();
    Navigator.of(context).pop();
  }

  void _showCompanyDialog() {
    showDialog(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: const Text('Add company'),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 350,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: companyNameController,
                    decoration: const InputDecoration(
                      labelText: 'Company name',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: companyAddressController,
                    decoration: const InputDecoration(labelText: 'Address'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: companyMobileController,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Mobile number',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: companyGstinController,
                    decoration: const InputDecoration(
                      labelText: 'GSTIN (optional)',
                    ),
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
            FilledButton(onPressed: _addCompany, child: const Text('Save')),
          ],
        );
      },
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
      appBar: AppBar(
        title: const Text('Ledger Studio'),
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Choose your ledger',
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Select the ledger you want to manage before adding your transactions.',
                    style: TextStyle(fontSize: 15, color: Colors.grey),
                  ),
                  const SizedBox(height: 26),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            setState(() {
                              ledgerType = LedgerType.sales;
                              screen = Screen.home;
                            });
                            _saveState();
                          },
                          icon: const Icon(Icons.trending_up),
                          label: const Text('Sales Ledger'),
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size.fromHeight(56),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            setState(() {
                              ledgerType = LedgerType.purchase;
                              screen = Screen.home;
                            });
                            _saveState();
                          },
                          icon: const Icon(Icons.trending_down),
                          label: const Text('Purchase Ledger'),
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size.fromHeight(56),
                            backgroundColor: Colors.deepPurple,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHomePage() {
    final availableCategories = ['All', ...allCategories];
    final chart = monthlyReport;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => setState(() => screen = Screen.welcome),
        ),
        title: Text(
          ledgerType == LedgerType.sales ? 'Sales Ledger' : 'Purchase Ledger',
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.home_outlined),
            onPressed: () => setState(() => screen = Screen.home),
          ),
          IconButton(
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
                    child: DropdownButtonFormField<String>(
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
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: InkWell(
                      onTap: () async {
                        final pickedStart = await showDatePicker(
                          context: context,
                          initialDate: DateTime.now(),
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2100),
                        );
                        if (pickedStart != null) {
                          setState(() => startDate = pickedStart);
                        }
                      },
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'From date',
                        ),
                        child: Text(
                          startDate == null
                              ? 'Any date'
                              : DateFormat('dd MMM yyyy').format(startDate!),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              InkWell(
                onTap: () async {
                  final pickedEnd = await showDatePicker(
                    context: context,
                    initialDate: DateTime.now(),
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100),
                  );
                  if (pickedEnd != null) {
                    setState(() => endDate = pickedEnd);
                  }
                },
                child: InputDecorator(
                  decoration: const InputDecoration(labelText: 'To date'),
                  child: Text(
                    endDate == null
                        ? 'Any date'
                        : DateFormat('dd MMM yyyy').format(endDate!),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              if (chart.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Monthly report',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        height: 180,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: chart.map((item) {
                            final maxValue = chart
                                .map(
                                  (entry) => (entry['value'] as double).abs(),
                                )
                                .fold<double>(
                                  0.0,
                                  (sum, value) => value > sum ? value : sum,
                                );
                            final value = (item['value'] as double).abs();
                            final barHeight = maxValue == 0
                                ? 0.0
                                : (value / maxValue) * 120;
                            return Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    Container(
                                      height: barHeight,
                                      width: double.infinity,
                                      decoration: BoxDecoration(
                                        color: (item['value'] as double) >= 0
                                            ? Colors.green
                                            : Colors.red,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      (item['month'] as String).split(' ')[0],
                                      style: const TextStyle(fontSize: 10),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Transactions',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  FilledButton.icon(
                    onPressed: () => _showAddTransactionDialog(),
                    icon: const Icon(Icons.add),
                    label: const Text('Add'),
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
                              '${transaction.category} • ${transaction.paymentMode}',
                            ),
                            Text(
                              DateFormat('dd MMM yyyy')
                                  .format(transaction.date),
                            ),
                          ],
                        ),
                        trailing: SizedBox(
                          width: 120,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${isCredit ? '+' : '-'}${transaction.currency} ${transaction.amount.toStringAsFixed(2)}',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: isCredit ? Colors.green : Colors.red,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    tooltip: 'Edit',
                                    onPressed: () => _showAddTransactionDialog(
                                      editing: transaction,
                                    ),
                                    icon: const Icon(Icons.edit, size: 18),
                                  ),
                                  IconButton(
                                    tooltip: 'Delete',
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
                                    onPressed: () =>
                                        _toggleCleared(transaction),
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
        onPressed: () => _showAddTransactionDialog(),
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
          onPressed: () => setState(() => screen = Screen.home),
        ),
        title: const Text('Companies'),
        actions: [
          IconButton(
            icon: const Icon(Icons.home_outlined),
            onPressed: () => setState(() => screen = Screen.home),
          ),
        ],
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
                          margin: const EdgeInsets.only(bottom: 12),
                          child: ListTile(
                            title: Text(company.name),
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
        onPressed: _showCompanyDialog,
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
      theme: appTheme,
      darkTheme: appTheme.copyWith(brightness: Brightness.dark),
      themeMode: themeMode,
      home: screen == Screen.welcome
          ? _buildWelcomePage()
          : screen == Screen.companies
          ? _buildCompanyPage()
          : _buildHomePage(),
    );
  }
}
