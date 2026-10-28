import 'package:shared_preferences/shared_preferences.dart';

/// Minimal persistence boundary so tests can use memory instead of disk.
abstract class ProgressStore {
  Future<String?> read();
  Future<void> write(String data);
}

class SharedPrefsProgressStore implements ProgressStore {
  static const key = 'lexistack.progress';

  @override
  Future<String?> read() async =>
      (await SharedPreferences.getInstance()).getString(key);

  @override
  Future<void> write(String data) async {
    final ok = await (await SharedPreferences.getInstance()).setString(
      key,
      data,
    );
    if (!ok) throw StateError('shared_preferences rejected the write');
  }
}

class MemoryProgressStore implements ProgressStore {
  MemoryProgressStore([this.data]);

  String? data;
  int writes = 0;
  bool failWrites = false;

  @override
  Future<String?> read() async => data;

  @override
  Future<void> write(String data) async {
    if (failWrites) throw StateError('simulated storage failure');
    writes++;
    this.data = data;
  }
}
