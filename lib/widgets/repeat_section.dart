import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Generic "repeat group" card list used for ODK-style begin_repeat sections
/// (membres du ménage, parcelles, champs, arbres, ressources, structures...).
class RepeatSection<T> extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<T> items;
  final String Function(T item, int index) itemTitle;
  final String Function(T item, int index)? itemSubtitle;
  final VoidCallback onAdd;
  final void Function(int index) onEdit;
  final void Function(int index) onDelete;
  final String addLabel;
  final Widget Function(T item, int index)? trailingBuilder;

  const RepeatSection({
    super.key,
    required this.title,
    required this.icon,
    required this.items,
    required this.itemTitle,
    this.itemSubtitle,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
    this.addLabel = 'Ajouter',
    this.trailingBuilder,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: OkapiColors.primary, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: onAdd,
                  icon: const Icon(Icons.add_circle_outline, size: 18),
                  label: Text(addLabel),
                ),
              ],
            ),
            if (items.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Aucun élément ajouté.',
                  style: TextStyle(color: OkapiColors.textLight),
                ),
              )
            else
              ...List.generate(items.length, (i) {
                final item = items[i];
                return Container(
                  margin: const EdgeInsets.only(top: 6),
                  decoration: BoxDecoration(
                    color: OkapiColors.background,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: ListTile(
                    dense: true,
                    title: Text(
                      itemTitle(item, i),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: itemSubtitle != null
                        ? Text(itemSubtitle!(item, i))
                        : null,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (trailingBuilder != null) trailingBuilder!(item, i),
                        IconButton(
                          icon: const Icon(
                            Icons.edit,
                            size: 18,
                            color: OkapiColors.info,
                          ),
                          onPressed: () => onEdit(i),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.delete_outline,
                            size: 18,
                            color: OkapiColors.error,
                          ),
                          onPressed: () => onDelete(i),
                        ),
                      ],
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}

/// Utility to show a scrollable form dialog and return the (possibly edited) item.
Future<T?> showFormDialog<T>({
  required BuildContext context,
  required String title,
  required Widget Function(BuildContext context) contentBuilder,
  required T? Function() onSave,
}) async {
  final formKey = GlobalKey<FormState>();
  return showDialog<T>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      return AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 480,
          child: Form(
            key: formKey,
            child: SingleChildScrollView(child: contentBuilder(ctx)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? true) {
                final result = onSave();
                Navigator.of(ctx).pop(result);
              }
            },
            child: const Text('Enregistrer'),
          ),
        ],
      );
    },
  );
}
