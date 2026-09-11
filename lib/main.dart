import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'theme/app_theme.dart';
import 'services/reference_data_service.dart';
import 'services/storage_service.dart';
import 'services/app_data_provider.dart';
import 'services/survey_data_provider.dart';
import 'screens/auth/auth_gate.dart';

/// All 11 BIODIVERSITE/SOCIAL survey form keys (see lib/data/survey_schema.json),
/// used to bulk-load SurveyDataProvider at startup.
const List<String> kAllSurveyFormKeys = [
  ...kBiodiversiteFormKeys,
  ...kSocialFormKeys,
];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await StorageService.instance.init();
  await ReferenceDataService.instance.load();

  final appData = AppDataProvider();
  await appData.loadAll();

  final surveyData = SurveyDataProvider();
  await surveyData.loadAll(kAllSurveyFormKeys);

  runApp(OkapiSurveyApp(appData: appData, surveyData: surveyData));
}

class OkapiSurveyApp extends StatelessWidget {
  final AppDataProvider appData;
  final SurveyDataProvider surveyData;
  const OkapiSurveyApp({
    super.key,
    required this.appData,
    required this.surveyData,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AppDataProvider>.value(value: appData),
        ChangeNotifierProvider<SurveyDataProvider>.value(value: surveyData),
      ],
      child: MaterialApp(
        title: 'Okapi Survey',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        home: const AuthGate(),
      ),
    );
  }
}
