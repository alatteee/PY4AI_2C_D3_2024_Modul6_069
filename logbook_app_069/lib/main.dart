import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:camera/camera.dart';

import 'package:logbook_app_069/features/logbook/models/log_model.dart';
import 'package:logbook_app_069/features/onboarding/onboarding_view.dart';
import 'package:logbook_app_069/helpers/log_helper.dart';
import 'package:logbook_app_069/services/mongo_service.dart';
import 'package:logbook_app_069/services/preferences_service.dart';

List<CameraDescription> cameras = [];

Future<void> _bootstrapBackground() async {
  try {
    await dotenv.load(fileName: '.env');

    Intl.defaultLocale = 'id_ID';
    await initializeDateFormatting('id_ID', null);

    await MongoService().connect();
    await LogHelper.writeLog(
      'Berhasil terhubung ke MongoDB',
      source: 'main.dart',
      level: 2,
    );
  } catch (e) {
    await LogHelper.writeLog(
      'Bootstrap background gagal (app tetap jalan offline): $e',
      source: 'main.dart',
      level: 1,
    );
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    cameras = await availableCameras();
  } on CameraException catch (e) {
    print('Error: ${e.code}\nError Message: ${e.description}');
  }

  await Hive.initFlutter();
  if (!Hive.isAdapterRegistered(0)) {
    Hive.registerAdapter(LogModelAdapter());
  }

  try {
    if (!Hive.isBoxOpen('offline_logs')) {
      await Hive.openBox<LogModel>('offline_logs');
    }
  } catch (e) {
    try {
      await Hive.deleteBoxFromDisk('offline_logs');
      await Hive.openBox<LogModel>('offline_logs');
    } catch (deleteError) {
      print('Hive initialization failed: $deleteError');
    }
  }

  await PreferencesService.initialize();

  runApp(const MyApp());

  _bootstrapBackground();
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LogBook App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const OnboardingView(),
    );
  }
}
