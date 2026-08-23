import 'package:flutter/material.dart';
import '../models/survey_field.dart';
import '../services/reference_data_service.dart';
import '../services/survey_expression_evaluator.dart';
import 'common_fields.dart';
import 'location_picker.dart';
import 'repeat_section.dart';
import 'survey_photo_field.dart';

/// Generic, JSON-schema-driven form renderer for the 11 BIODIVERSITE/SOCIAL
/// survey forms. Walks a [SurveySchema.fields] tree and, for each
/// [SurveyNode], renders the appropriate EXISTING app widget:
///  - select_one/select_multiple -> ChoiceDropdown / checkbox list
///  - text/integer/decimal       -> LabeledTextField
///  - date                       -> DateField
///  - time                       -> simple time picker field
///  - geopoint                   -> latitude/longitude text fields
///  - image                      -> SurveyPhotoField
///  - region/prefecture/sous_prefecture -> LocationPickerField (guinea_admin.json)
///  - group  -> SectionHeader + nested fields (always visible together)
///  - repeat -> RepeatSection<Map<String,dynamic>> + showFormDialog editor
///
/// `relevant` visibility, `choiceFilter` cascading and `calculation`
/// auto-fill are evaluated live via [SurveyExpressionEvaluator] against the
/// CURRENT group/repeat-instance's value map.
class SurveyFormRenderer extends StatefulWidget {
  final SurveySchema schema;
  final Map<String, dynamic> values;
  final Map<String, List<Map<String, dynamic>>> repeats;
  final VoidCallback? onChanged;

  const SurveyFormRenderer({
    super.key,
    required this.schema,
    required this.values,
    required this.repeats,
    this.onChanged,
  });

  @override
  State<SurveyFormRenderer> createState() => _SurveyFormRendererState();
}

class _SurveyFormRendererState extends State<SurveyFormRenderer> {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: _buildNodes(widget.schema.fields, widget.values),
    );
  }

  void _touch() {
    setState(() {});
    widget.onChanged?.call();
  }

  List<Widget> _buildNodes(List<SurveyNode> nodes, Map<String, dynamic> ctx) {
    final evaluator = SurveyExpressionEvaluator(ctx);
    final widgets = <Widget>[];
    for (final node in nodes) {
      if (!evaluator.evaluateRelevant(node.relevant)) continue;

      // Auto-compute calculation fields live, before rendering.
      if (node.isField && node.calculation != null) {
        final computed = evaluator.evaluateCalculation(node.calculation);
        if (ctx[node.name] != computed) {
          ctx[node.name] = computed;
        }
      }

      if (node.isGroup) {
        widgets.add(SectionHeader(title: node.label ?? node.name));
        widgets.addAll(_buildNodes(node.children, ctx));
        widgets.add(const SizedBox(height: 8));
        continue;
      }

      if (node.isRepeat) {
        widgets.add(_buildRepeat(node, ctx));
        widgets.add(const SizedBox(height: 8));
        continue;
      }

      widgets.add(_buildField(node, ctx, evaluator));
      widgets.add(const SizedBox(height: 12));
    }
    return widgets;
  }

  Widget _buildField(
    SurveyNode node,
    Map<String, dynamic> ctx,
    SurveyExpressionEvaluator evaluator,
  ) {
    // Admin division: region / prefecture / sous_prefecture — routed to the
    // canonical guinea_admin.json via the existing LocationPickerField.
    if (node.name == 'region') {
      final data = LocationPickerData(
        region: ctx['region']?.toString(),
        prefecture: ctx['prefecture']?.toString(),
        sousPrefecture: ctx['sous_prefecture']?.toString(),
      );
      return LocationPickerField(
        data: data,
        onChanged: (d) {
          ctx['region'] = d.region;
          ctx['prefecture'] = d.prefecture;
          ctx['sous_prefecture'] = d.sousPrefecture;
          _touch();
        },
      );
    }
    // These are rendered as part of the LocationPickerField above.
    if (node.name == 'prefecture' || node.name == 'sous_prefecture') {
      return const SizedBox.shrink();
    }

    switch (node.type) {
      case 'select_one':
        final filterType = evaluator.filterValueFor(node.choiceFilter);
        return ChoiceDropdown(
          listName: node.listName ?? '',
          label: node.label ?? node.name,
          value: ctx[node.name]?.toString(),
          filterType: filterType,
          required: node.required,
          onChanged: (v) {
            ctx[node.name] = v;
            _touch();
          },
        );

      case 'select_multiple':
        return _MultiSelectField(
          listName: node.listName ?? '',
          label: node.label ?? node.name,
          selected:
              (ctx[node.name] as List?)?.map((e) => e.toString()).toList() ??
              const [],
          onChanged: (v) {
            ctx[node.name] = v;
            _touch();
          },
        );

      case 'date':
        DateTime? dv;
        final raw = ctx[node.name];
        if (raw is DateTime) {
          dv = raw;
        } else if (raw is String && raw.isNotEmpty) {
          dv = DateTime.tryParse(raw);
        }
        return DateField(
          label: node.label ?? node.name,
          value: dv,
          required: node.required,
          onChanged: (d) {
            ctx[node.name] = d?.toIso8601String();
            _touch();
          },
        );

      case 'time':
        return _TimeField(
          label: node.label ?? node.name,
          value: ctx[node.name]?.toString(),
          required: node.required,
          onChanged: (v) {
            ctx[node.name] = v;
            _touch();
          },
        );

      case 'integer':
        return LabeledTextField(
          label: node.label ?? node.name,
          initialValue: ctx[node.name]?.toString(),
          required: node.required,
          readOnly: node.readOnly,
          keyboardType: TextInputType.number,
          onChanged: (v) {
            ctx[node.name] = v;
          },
          validator: (v) => _constraintValidator(node, evaluator, v),
        );

      case 'decimal':
        return LabeledTextField(
          label: node.label ?? node.name,
          initialValue: ctx[node.name]?.toString(),
          required: node.required,
          readOnly: node.readOnly,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (v) {
            ctx[node.name] = v;
          },
          validator: (v) => _constraintValidator(node, evaluator, v),
        );

      case 'geopoint':
        return _GeopointField(
          label: node.label ?? node.name,
          value: ctx[node.name]?.toString(),
          onChanged: (v) {
            ctx[node.name] = v;
          },
        );

      case 'image':
        return SurveyPhotoField(
          label: node.label ?? node.name,
          base64Data: ctx[node.name]?.toString(),
          required: node.required,
          onChanged: (v) {
            ctx[node.name] = v;
            _touch();
          },
        );

      case 'text':
      default:
        return LabeledTextField(
          label: node.label ?? node.name,
          initialValue: ctx[node.name]?.toString(),
          required: node.required,
          readOnly: node.readOnly,
          maxLines: node.appearance == 'multiline' ? 3 : 1,
          onChanged: (v) {
            ctx[node.name] = v;
          },
        );
    }
  }

  String? _constraintValidator(
    SurveyNode node,
    SurveyExpressionEvaluator evaluator,
    String? v,
  ) {
    if (node.required && (v == null || v.isEmpty)) return 'Champ requis';
    if (node.constraint != null && v != null && v.isNotEmpty) {
      final ok = evaluator.evaluateConstraint(node.constraint, v);
      if (!ok) return 'Valeur invalide (${node.constraint})';
    }
    return null;
  }

  Widget _buildRepeat(SurveyNode node, Map<String, dynamic> ctx) {
    final list = widget.repeats.putIfAbsent(node.name, () => []);
    return RepeatSection<Map<String, dynamic>>(
      title: node.label ?? node.name,
      icon: Icons.list_alt,
      items: list,
      itemTitle: (item, i) => '${node.label ?? node.name} #${i + 1}',
      itemSubtitle: (item, i) {
        final firstFieldNode = node.children.firstWhere(
          (c) => c.isField,
          orElse: () => SurveyNode(kind: 'field', name: ''),
        );
        if (firstFieldNode.name.isEmpty) return '';
        return item[firstFieldNode.name]?.toString() ?? '';
      },
      onAdd: () async {
        final entry = <String, dynamic>{};
        // Pre-seed nested repeat lists so children can add their own
        // entries within this instance (supports 2-level nesting, e.g.
        // Chimpanzés Recce's "observation" repeat containing "Indice").
        for (final child in node.children) {
          if (child.isRepeat) entry[child.name] = <Map<String, dynamic>>[];
        }
        final saved = await showFormDialog<Map<String, dynamic>>(
          context: context,
          title: 'Ajouter — ${node.label ?? node.name}',
          contentBuilder: (ctx2) =>
              _RepeatInstanceEditor(children: node.children, entry: entry),
          onSave: () => entry,
        );
        if (saved != null) {
          setState(() => list.add(saved));
          widget.onChanged?.call();
        }
      },
      onEdit: (i) async {
        final entry = Map<String, dynamic>.from(list[i]);
        for (final child in node.children) {
          if (child.isRepeat && entry[child.name] == null) {
            entry[child.name] = <Map<String, dynamic>>[];
          }
        }
        final saved = await showFormDialog<Map<String, dynamic>>(
          context: context,
          title: 'Modifier — ${node.label ?? node.name}',
          contentBuilder: (ctx2) =>
              _RepeatInstanceEditor(children: node.children, entry: entry),
          onSave: () => entry,
        );
        if (saved != null) {
          setState(() => list[i] = saved);
          widget.onChanged?.call();
        }
      },
      onDelete: (i) {
        setState(() => list.removeAt(i));
        widget.onChanged?.call();
      },
    );
  }
}

/// Editor content for one repeat-instance dialog (used inside
/// showFormDialog). Wraps the same node-rendering logic in a nested
/// StatefulBuilder so nested repeats (e.g. "Indice" inside "observation")
/// work too.
class _RepeatInstanceEditor extends StatefulWidget {
  final List<SurveyNode> children;
  final Map<String, dynamic> entry;

  const _RepeatInstanceEditor({required this.children, required this.entry});

  @override
  State<_RepeatInstanceEditor> createState() => _RepeatInstanceEditorState();
}

class _RepeatInstanceEditorState extends State<_RepeatInstanceEditor> {
  @override
  Widget build(BuildContext context) {
    return SurveyFormRenderer(
      schema: SurveySchema(
        key: '_repeat',
        module: '',
        title: '',
        icon: '',
        fields: widget.children,
      ),
      values: widget.entry,
      repeats: widget.entry.map(
        (k, v) => MapEntry(
          k,
          v is List
              ? List<Map<String, dynamic>>.from(
                  v.map((e) => Map<String, dynamic>.from(e as Map)),
                )
              : <Map<String, dynamic>>[],
        ),
      )..removeWhere((k, v) => widget.entry[k] is! List),
      onChanged: () => setState(() {}),
    );
  }
}

/// Simple text-based time entry (HH:mm), matching the app's minimal-widget
/// philosophy (no extra time-picker dependency needed beyond Material's
/// built-in showTimePicker).
class _TimeField extends StatelessWidget {
  final String label;
  final String? value;
  final bool required;
  final ValueChanged<String?> onChanged;

  const _TimeField({
    required this.label,
    required this.value,
    required this.onChanged,
    this.required = false,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      readOnly: true,
      controller: TextEditingController(text: value ?? ''),
      decoration: InputDecoration(
        label: Text(required ? '$label *' : label),
        suffixIcon: const Icon(Icons.access_time, size: 18),
      ),
      validator: required
          ? (v) => (value == null || value!.isEmpty) ? 'Champ requis' : null
          : null,
      onTap: () async {
        final initial = _parseTime(value) ?? TimeOfDay.now();
        final picked = await showTimePicker(
          context: context,
          initialTime: initial,
        );
        if (picked != null) {
          final text =
              '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
          onChanged(text);
        }
      },
    );
  }

  TimeOfDay? _parseTime(String? v) {
    if (v == null || !v.contains(':')) return null;
    final parts = v.split(':');
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts.length > 1 ? parts[1] : '0');
    if (h == null || m == null) return null;
    return TimeOfDay(hour: h, minute: m);
  }
}

/// Manual lat/lon entry for `geopoint` fields, stored as "lat lon" text
/// (ODK geopoint convention: "lat lon alt accuracy"), matching the
/// existing app's convention of manual lat/lon text entry (structure_dialogs).
class _GeopointField extends StatefulWidget {
  final String label;
  final String? value;
  final ValueChanged<String?> onChanged;

  const _GeopointField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  State<_GeopointField> createState() => _GeopointFieldState();
}

class _GeopointFieldState extends State<_GeopointField> {
  late TextEditingController _latCtrl;
  late TextEditingController _lonCtrl;

  @override
  void initState() {
    super.initState();
    final parts = (widget.value ?? '').trim().split(RegExp(r'\s+'));
    _latCtrl = TextEditingController(
      text: parts.isNotEmpty && parts[0].isNotEmpty ? parts[0] : '',
    );
    _lonCtrl = TextEditingController(text: parts.length > 1 ? parts[1] : '');
  }

  @override
  void dispose() {
    _latCtrl.dispose();
    _lonCtrl.dispose();
    super.dispose();
  }

  void _emit() {
    final lat = _latCtrl.text.trim();
    final lon = _lonCtrl.text.trim();
    if (lat.isEmpty && lon.isEmpty) {
      widget.onChanged(null);
    } else {
      widget.onChanged('$lat $lon');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _latCtrl,
                decoration: const InputDecoration(labelText: 'Latitude'),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
                onChanged: (_) => _emit(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: _lonCtrl,
                decoration: const InputDecoration(labelText: 'Longitude'),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
                onChanged: (_) => _emit(),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// select_multiple rendering: a wrap of checkbox tiles backed by
/// ReferenceDataService's choice list, storing the answer as
/// List<String> (matching SurveyRecord's Map<String,dynamic> values shape).
class _MultiSelectField extends StatefulWidget {
  final String listName;
  final String label;
  final List<String> selected;
  final ValueChanged<List<String>> onChanged;

  const _MultiSelectField({
    required this.listName,
    required this.label,
    required this.selected,
    required this.onChanged,
  });

  @override
  State<_MultiSelectField> createState() => _MultiSelectFieldState();
}

class _MultiSelectFieldState extends State<_MultiSelectField> {
  late List<String> _selected;

  @override
  void initState() {
    super.initState();
    _selected = List<String>.from(widget.selected);
  }

  @override
  Widget build(BuildContext context) {
    final items = ReferenceDataService.instance.choices(widget.listName);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(8),
          ),
          constraints: const BoxConstraints(maxHeight: 220),
          child: SingleChildScrollView(
            child: Column(
              children: items.map((c) {
                final checked = _selected.contains(c.name);
                return CheckboxListTile(
                  dense: true,
                  value: checked,
                  title: Text(c.label, style: const TextStyle(fontSize: 13)),
                  onChanged: (v) {
                    setState(() {
                      if (v == true) {
                        _selected.add(c.name);
                      } else {
                        _selected.remove(c.name);
                      }
                    });
                    widget.onChanged(_selected);
                  },
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }
}
