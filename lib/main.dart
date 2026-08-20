import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'theme/app_theme.dart';
import 'services/reference_data_service.dart';
import 'services/storage_service.dart';
import 'services/app_data_provider.dart';
import 'screens/auth/auth_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await StorageService.instance.init();
  await ReferenceDataService.instance.load();

  final appData = AppDataProvider();
  await appData.loadAll();

  runApp(OkapiSurveyApp(appData: appData));
}

class OkapiSurveyApp extends StatelessWidget {
  final AppDataProvider appData;
  const OkapiSurveyApp({super.key, required this.appData});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<AppDataProvider>.value(
      value: appData,
      child: MaterialApp(
        title: 'Okapi Survey',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        home: const AuthGate(),
      ),
    );
  }
}
