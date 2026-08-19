import 'package:flutter/material.dart';
import '../services/reference_data_service.dart';

/// Cascading Region > Préfecture > Sous-préfecture picker for Guinea,
/// plus free-text District and Village fields (enqueteur-entered per spec).
class LocationPickerData {
  String? region;
  String? prefecture;
  String? sousPrefecture;
  String district;
  String village;

  LocationPickerData({
    this.region,
    this.prefecture,
    this.sousPrefecture,
    this.district = '',
    this.village = '',
  });
}

class LocationPickerField extends StatefulWidget {
  final LocationPickerData data;
  final ValueChanged<LocationPickerData> onChanged;

  const LocationPickerField({
    super.key,
    required this.data,
    required this.onChanged,
  });

  @override
  State<LocationPickerField> createState() => _LocationPickerFieldState();
}

class _LocationPickerFieldState extends State<LocationPickerField> {
  final _ref = ReferenceDataService.instance;
  late TextEditingController _districtCtrl;
  late TextEditingController _villageCtrl;

  @override
  void initState() {
    super.initState();
    _districtCtrl = TextEditingController(text: widget.data.district);
    _villageCtrl = TextEditingController(text: widget.data.village);
  }

  @override
  void dispose() {
    _districtCtrl.dispose();
    _villageCtrl.dispose();
    super.dispose();
  }

  void _notify() => widget.onChanged(widget.data);

  @override
  Widget build(BuildContext context) {
    final regions = _ref.regions;
    final prefectures = _ref.prefecturesFor(widget.data.region);
    final sousPrefs = _ref.sousPrefecturesFor(
      widget.data.region,
      widget.data.prefecture,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          initialValue: regions.contains(widget.data.region)
              ? widget.data.region
              : null,
          decoration: const InputDecoration(labelText: 'Région *'),
          items: regions
              .map((r) => DropdownMenuItem(value: r, child: Text(r)))
              .toList(),
          onChanged: (v) {
            setState(() {
              widget.data.region = v;
              widget.data.prefecture = null;
              widget.data.sousPrefecture = null;
            });
            _notify();
          },
          validator: (v) => v == null ? 'Champ requis' : null,
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: prefectures.contains(widget.data.prefecture)
              ? widget.data.prefecture
              : null,
          decoration: const InputDecoration(labelText: 'Préfecture *'),
          items: prefectures
              .map((p) => DropdownMenuItem(value: p, child: Text(p)))
              .toList(),
          onChanged: widget.data.region == null
              ? null
              : (v) {
                  setState(() {
                    widget.data.prefecture = v;
                    widget.data.sousPrefecture = null;
                  });
                  _notify();
                },
          validator: (v) => v == null ? 'Champ requis' : null,
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: sousPrefs.contains(widget.data.sousPrefecture)
              ? widget.data.sousPrefecture
              : null,
          decoration: const InputDecoration(labelText: 'Sous-préfecture *'),
          items: sousPrefs
              .map((s) => DropdownMenuItem(value: s, child: Text(s)))
              .toList(),
          onChanged: widget.data.prefecture == null
              ? null
              : (v) {
                  setState(() => widget.data.sousPrefecture = v);
                  _notify();
                },
          validator: (v) => v == null ? 'Champ requis' : null,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _districtCtrl,
          decoration: const InputDecoration(labelText: 'District *'),
          validator: (v) => (v == null || v.isEmpty) ? 'Champ requis' : null,
          onChanged: (v) {
            widget.data.district = v;
            _notify();
          },
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _villageCtrl,
          decoration: const InputDecoration(labelText: 'Village / Localité *'),
          validator: (v) => (v == null || v.isEmpty) ? 'Champ requis' : null,
          onChanged: (v) {
            widget.data.village = v;
            _notify();
          },
        ),
      ],
    );
  }
}
