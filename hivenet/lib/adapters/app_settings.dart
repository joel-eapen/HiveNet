import 'dart:convert';
import 'dart:io';

/// Small non-secret settings kept in a JSON file next to the database.
/// Secrets (keys) never go here; they live in the platform secure store.
class AppSettings {
  AppSettings._(this._file, this.deviceName, this.onboardingComplete);

  final File _file;
  String deviceName;
  bool onboardingComplete;

  static Future<AppSettings> load(String directory) async {
    final file = File('$directory/settings.json');
    var name = 'My phone';
    var onboarded = false;
    try {
      if (await file.exists()) {
        final j = jsonDecode(await file.readAsString());
        if (j is Map) {
          name = (j['deviceName'] as String?)?.trim().isNotEmpty == true
              ? j['deviceName'] as String
              : name;
          onboarded = j['onboardingComplete'] == true;
        }
      }
    } catch (_) {
      // A corrupt settings file must not stop the app: start from defaults.
    }
    return AppSettings._(file, name, onboarded);
  }

  Future<void> _tail = Future.value();

  /// Saves the current values. Calls are queued, so two quick changes (name and
  /// onboarding flag) never race each other on the same temp file.
  Future<void> save() {
    final done = _tail.then((_) => _write());
    _tail = done.then((_) {}, onError: (_) {});
    return done;
  }

  Future<void> _write() async {
    await _file.parent.create(recursive: true);
    // Write to a temp file and rename so a crash cannot leave half a file.
    final tmp = File('${_file.path}.tmp');
    await tmp.writeAsString(jsonEncode({
      'deviceName': deviceName,
      'onboardingComplete': onboardingComplete,
    }), flush: true);
    await tmp.rename(_file.path);
  }
}
