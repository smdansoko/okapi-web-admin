class ChoiceItem {
  final String name;
  final String label;
  final String? type; // used for filtering (choice_filter equivalent)

  ChoiceItem({required this.name, required this.label, this.type});

  factory ChoiceItem.fromJson(Map<String, dynamic> json) {
    return ChoiceItem(
      name: json['name'] as String? ?? '',
      label:
          (json['label'] as String?)?.trim() ?? (json['name'] as String? ?? ''),
      type: json['type'] as String?,
    );
  }

  @override
  String toString() => label;

  @override
  bool operator ==(Object other) => other is ChoiceItem && other.name == name;

  @override
  int get hashCode => name.hashCode;
}
