import 'package:flutter/material.dart';
import '../models/choice_item.dart';
import '../services/reference_data_service.dart';

/// Resolves a project-aware choices.json list name: when [project] is
/// 'simandou' and a '<base>_simandou' list exists, that list is used
/// instead of the default (WCAG/SMB) '<base>' list. Falls back to [base]
/// otherwise (including when no SIMANDOU-specific variant was defined,
/// e.g. lists that are identical across projects such as materiaux_mur,
/// etat_structure, type_propriete, type_ressource, ressource, unite).
String projectListName(String base, String? project) {
  if (project == 'simandou') {
    final suffixed = '${base}_simandou';
    if (ReferenceDataService.instance.choices(suffixed).isNotEmpty) {
      return suffixed;
    }
  }
  return base;
}

/// select_one style dropdown backed by a choices.json list, with optional
/// choice_filter equivalent (filterType).
class ChoiceDropdown extends StatelessWidget {
  final String listName;
  final String label;
  final String? value;
  final String? filterType;
  final bool required;
  final ValueChanged<String?> onChanged;
  final String? Function(String?)? validator;

  const ChoiceDropdown({
    super.key,
    required this.listName,
    required this.label,
    required this.value,
    required this.onChanged,
    this.filterType,
    this.required = false,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    final items = ReferenceDataService.instance.choicesFiltered(
      listName,
      filterType,
    );
    final validValue = items.any((c) => c.name == value) ? value : null;
    return DropdownButtonFormField<String>(
      initialValue: validValue,
      isExpanded: true,
      decoration: InputDecoration(label: Text(required ? '$label *' : label)),
      items: items
          .map(
            (c) => DropdownMenuItem(
              value: c.name,
              child: Text(c.label, overflow: TextOverflow.ellipsis),
            ),
          )
          .toList(),
      onChanged: onChanged,
      validator:
          validator ??
          (required
              ? (v) => (v == null || v.isEmpty) ? 'Champ requis' : null
              : null),
    );
  }
}

/// Generic labeled text field.
class LabeledTextField extends StatelessWidget {
  final String label;
  final String? initialValue;
  final TextEditingController? controller;
  final bool required;
  final TextInputType keyboardType;
  final int maxLines;
  final ValueChanged<String>? onChanged;
  final String? Function(String?)? validator;
  final bool readOnly;

  const LabeledTextField({
    super.key,
    required this.label,
    this.initialValue,
    this.controller,
    this.required = false,
    this.keyboardType = TextInputType.text,
    this.maxLines = 1,
    this.onChanged,
    this.validator,
    this.readOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      initialValue: controller == null ? initialValue : null,
      keyboardType: keyboardType,
      maxLines: maxLines,
      readOnly: readOnly,
      decoration: InputDecoration(
        label: Text(required ? '$label *' : label),
        filled: readOnly,
        fillColor: readOnly ? Colors.grey.shade100 : null,
      ),
      onChanged: onChanged,
      validator:
          validator ??
          (required
              ? (v) => (v == null || v.isEmpty) ? 'Champ requis' : null
              : null),
    );
  }
}

/// Date picker field.
class DateField extends StatelessWidget {
  final String label;
  final DateTime? value;
  final bool required;
  final ValueChanged<DateTime?> onChanged;

  const DateField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.required = false,
  });

  @override
  Widget build(BuildContext context) {
    final text = value == null
        ? ''
        : '${value!.day.toString().padLeft(2, '0')}/${value!.month.toString().padLeft(2, '0')}/${value!.year}';
    return TextFormField(
      readOnly: true,
      controller: TextEditingController(text: text),
      decoration: InputDecoration(
        label: Text(required ? '$label *' : label),
        suffixIcon: const Icon(Icons.calendar_today, size: 18),
      ),
      validator: required
          ? (v) => (value == null) ? 'Champ requis' : null
          : null,
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: value ?? DateTime.now(),
          firstDate: DateTime(1900),
          lastDate: DateTime.now(),
        );
        if (picked != null) onChanged(picked);
      },
    );
  }
}

/// Section header used throughout survey forms.
class SectionHeader extends StatelessWidget {
  final String title;
  final IconData? icon;
  const SectionHeader({super.key, required this.title, this.icon});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 10),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, color: Theme.of(context).colorScheme.primary, size: 20),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Yes/No select_one convenience (oui_non list).
class OuiNonField extends StatelessWidget {
  final String label;
  final String? value;
  final ValueChanged<String?> onChanged;
  final bool required;

  const OuiNonField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.required = true,
  });

  @override
  Widget build(BuildContext context) {
    return ChoiceDropdown(
      listName: 'oui_non',
      label: label,
      value: value,
      onChanged: onChanged,
      required: required,
    );
  }
}

class ChoiceItemList {
  static List<ChoiceItem> of(String listName) =>
      ReferenceDataService.instance.choices(listName);
}
