import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/survey_icons.dart';
import '../../services/reference_data_service.dart';
import '../../services/survey_data_provider.dart';
import '../../theme/app_theme.dart';
import 'patrimoine_culturel_report_screen.dart';
import 'survey_list_screen.dart';

/// Module landing screen listing the forms belonging to one module
/// ('BIODIVERSITE' -> 8 forms, 'SOCIAL' -> 3 forms). Tapping a form opens
/// its generic [SurveyListScreen].
class SurveyModuleScreen extends StatelessWidget {
  final String module; // 'BIODIVERSITE' | 'SOCIAL'
  final String moduleTitle;

  const SurveyModuleScreen({
    super.key,
    required this.module,
    required this.moduleTitle,
  });

  @override
  Widget build(BuildContext context) {
    final schemas = ReferenceDataService.instance.surveySchemasForModule(
      module,
    );
    final provider = context.watch<SurveyDataProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Text(moduleTitle),
        actions: [
          if (module == 'SOCIAL')
            IconButton(
              icon: const Icon(Icons.temple_buddhist),
              tooltip: 'Annuaire Patrimoine culturel',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const PatrimoineCulturelReportScreen(),
                  ),
                );
              },
            ),
        ],
      ),
      body: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: MediaQuery.of(context).size.width > 700 ? 3 : 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.05,
        ),
        itemCount: schemas.length,
        itemBuilder: (context, i) {
          final schema = schemas[i];
          final count = provider.countFor(schema.key);
          return Card(
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => SurveyListScreen(schema: schema),
                  ),
                );
              },
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    CircleAvatar(
                      backgroundColor: module == 'BIODIVERSITE'
                          ? OkapiColors.secondary.withValues(alpha: 0.15)
                          : OkapiColors.primary.withValues(alpha: 0.15),
                      child: Icon(
                        surveyIconFor(schema.icon),
                        color: module == 'BIODIVERSITE'
                            ? OkapiColors.secondary
                            : OkapiColors.primary,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      schema.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$count fiche(s)',
                      style: const TextStyle(
                        color: OkapiColors.textLight,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
