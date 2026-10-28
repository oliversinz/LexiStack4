import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app/controller.dart';
import 'app/storage.dart';
import 'core/content.dart';
import 'ui/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    final text = await rootBundle.loadString('assets/fonts/LICENSE-Roboto.txt');
    yield LicenseEntryWithLineBreaks(['Roboto', 'Roboto Condensed'], text);
  });
  final catalog = await loadCatalog(rootBundle);
  final controller = AppController(
    catalog: catalog,
    store: SharedPrefsProgressStore(),
  );
  await controller.load();
  runApp(LexiStackApp(controller: controller));
}

/// Loads the manifest and every listed pack from the bundled assets.
Future<Catalog> loadCatalog(AssetBundle bundle) async {
  const dir = 'assets/levels';
  final manifest = await bundle.loadString('$dir/manifest.json', cache: false);
  final issues = <ContentIssue>[];
  final files = <String, String>{};
  for (final f
      in parseManifest(manifest, issues)?.allFiles ?? const <String>[]) {
    files[f] = await bundle.loadString('$dir/$f', cache: false);
  }
  return parseCatalog(manifest, files);
}
