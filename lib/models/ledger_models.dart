enum LedgerType { sales, purchase }

enum TransactionType { credit, debit }

enum Screen { welcome, home, companies }

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
  };

  factory Transaction.fromJson(Map<String, dynamic> map) {
    return Transaction(
      id: map['id'] as int? ?? 0,
      title: map['title'] as String? ?? 'Untitled',
      amount: (map['amount'] as num?)?.toDouble() ?? 0.0,
      type: TransactionType.values.firstWhere(
        (value) => value.name == (map['type'] ?? 'debit'),
        orElse: () => TransactionType.debit,
      ),
      category: map['category'] as String? ?? 'General',
      currency: map['currency'] as String? ?? 'INR',
      paymentMode: map['paymentMode'] as String? ?? 'Cash',
      date: DateTime.tryParse((map['date'] as String?) ?? '') ?? DateTime.now(),
      isCleared: map['isCleared'] as bool? ?? false,
      ledgerType: LedgerType.values.firstWhere(
        (value) => value.name == (map['ledgerType'] ?? 'sales'),
        orElse: () => LedgerType.sales,
      ),
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
