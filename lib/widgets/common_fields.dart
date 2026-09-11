import 'package:flutter/material.dart';
import '../models/choice_item.dart';
import '../services/reference_data_service.dart';

/// Wraps a bare input widget (dropdown, date picker, etc.) with the
/// standard survey-form field presentation: the field's **label** shown as
/// a bold "box title" above the input, and — when present — its **hint**
/// shown right below as a smaller explanatory caption of what to fill in.
/// The technical ODK `name` is intentionally never passed to this widget by
/// callers, so it never reaches the UI.
///
/// Used by [ChoiceDropdown]/[LabeledTextField]/[DateField] so every survey
/// field (all 11 BIODIVERSITE/SOCIAL forms) gets this consistent
/// title-then-explanation layout automatically.
class FieldWithHint extends StatelessWidget {
  final String label;
  final String? hint;
  final bool required;
  final Widget child;

  const FieldWithHint({
    super.key,
    required this.label,
    required this.child,
    this.hint,
    this.required = false,
  });

  @override
  Widget build(BuildContext context) {
    final trimmedHint = hint?.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RichText(
          text: TextSpan(
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
              color: Colors.black87,
            ),
            children: [
              TextSpan(text: label),
              if (required)
                const TextSpan(
                  text: ' *',
                  style: TextStyle(color: Colors.red),
                ),
            ],
          ),
        ),
        if (trimmedHint != null && trimmedHint.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            trimmedHint,
            style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
          ),
        ],
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}

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
  final String? hint;
  final String? value;
  final String? filterType;
  final bool required;
  final bool readOnly;
  final ValueChanged<String?> onChanged;
  final String? Function(String?)? validator;

  const ChoiceDropdown({
    super.key,
    required this.listName,
    required this.label,
    required this.value,
    required this.onChanged,
    this.hint,
    this.filterType,
    this.required = false,
    this.readOnly = false,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    final items = ReferenceDataService.instance.choicesFiltered(
      listName,
      filterType,
    );
    final validValue = items.any((c) => c.name == value) ? value : null;
    // A read-only select field (e.g. "Numéro de la tablette", auto-filled
    // from the logged-in user's account) is shown as a plain disabled
    // dropdown — the value is still visible but cannot be changed.
    if (readOnly) {
      final displayLabel = validValue != null
          ? (items.firstWhere((c) => c.name == validValue).label)
          : '';
      return FieldWithHint(
        label: label,
        hint: hint,
        required: false,
        child: InputDecorator(
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            filled: true,
            fillColor: Color(0xFFF0F0F0),
          ),
          child: Text(
            displayLabel.isNotEmpty ? displayLabel : '—',
            style: const TextStyle(color: Colors.black87),
          ),
        ),
      );
    }
    return FieldWithHint(
      label: label,
      hint: hint,
      required: required,
      child: DropdownButtonFormField<String>(
        initialValue: validValue,
        isExpanded: true,
        decoration: const InputDecoration(border: OutlineInputBorder()),
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
      ),
    );
  }
}

/// Generic labeled text field.
class LabeledTextField extends StatelessWidget {
  final String label;
  final String? hint;
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
    this.hint,
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
    return FieldWithHint(
      label: label,
      hint: hint,
      required: required,
      child: TextFormField(
        controller: controller,
        initialValue: controller == null ? initialValue : null,
        keyboardType: keyboardType,
        maxLines: maxLines,
        readOnly: readOnly,
        decoration: InputDecoration(
          border: const OutlineInputBorder(),
          filled: readOnly,
          fillColor: readOnly ? Colors.grey.shade100 : null,
        ),
        onChanged: onChanged,
        validator:
            validator ??
            (required
                ? (v) => (v == null || v.isEmpty) ? 'Champ requis' : null
                : null),
      ),
    );
  }
}

/// Date picker field.
class DateField extends StatelessWidget {
  final String label;
  final String? hint;
  final DateTime? value;
  final bool required;
  final ValueChanged<DateTime?> onChanged;

  const DateField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.hint,
    this.required = false,
  });

  @override
  Widget build(BuildContext context) {
    final text = value == null
        ? ''
        : '${value!.day.toString().padLeft(2, '0')}/${value!.month.toString().padLeft(2, '0')}/${value!.year}';
    return FieldWithHint(
      label: label,
      hint: hint,
      required: required,
      child: TextFormField(
        readOnly: true,
        controller: TextEditingController(text: text),
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
          suffixIcon: Icon(Icons.calendar_today, size: 18),
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
      ),
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
