// Standalone LexiStack content validator.
//
//   dart run tool/validate_levels.dart              strict final validation
//   dart run tool/validate_levels.dart --partial    validate files present so far
//   dart run tool/validate_levels.dart pack.json    check a candidate pack against
//                                                   the installed catalog
//
// Exits 0 when there are no errors, 1 on errors, 2 on bad usage.

import 'dart:io';

import 'package:lexistack/core/validator.dart';

const levelsDir = 'assets/levels';

void main(List<String> args) {
  final partial = args.contains('--partial');
  final positional = args.where((a) => !a.startsWith('--')).toList();
  final unknown = args.where((a) => a.startsWith('--') && a != '--partial');
  if (unknown.isNotEmpty ||
      positional.length > 1 ||
      (partial && positional.isNotEmpty)) {
    stderr.writeln(
      'Usage: dart run tool/validate_levels.dart [--partial | candidate.json]',
    );
    exitCode = 2;
    return;
  }

  final manifestFile = File('$levelsDir/manifest.json');
  final manifestSource = manifestFile.existsSync()
      ? manifestFile.readAsStringSync()
      : null;
  final files = <String, String?>{};
  for (final entity
      in Directory(levelsDir).existsSync()
          ? Directory(levelsDir).listSync()
          : const <FileSystemEntity>[]) {
    if (entity is File && entity.path.endsWith('.json')) {
      final name = entity.uri.pathSegments.last;
      if (name != 'manifest.json') files[name] = entity.readAsStringSync();
    }
  }

  ValidationReport report;
  if (positional.isNotEmpty) {
    final candidate = File(positional.single);
    if (!candidate.existsSync()) {
      stderr.writeln('Candidate file not found: ${candidate.path}');
      exitCode = 2;
      return;
    }
    report = validateCatalog(
      manifestSource: manifestSource,
      files: files,
      mode: ValidationMode.candidate,
      candidateName: candidate.uri.pathSegments.last,
      candidateSource: candidate.readAsStringSync(),
    );
  } else {
    report = validateCatalog(
      manifestSource: manifestSource,
      files: files,
      mode: partial ? ValidationMode.partial : ValidationMode.strict,
    );
  }
  stdout.write(formatReport(report));
  exitCode = report.ok ? 0 : 1;
}
