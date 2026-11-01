// THROWAWAY Milestone 0 spike code.
import 'package:flutter/foundation.dart';

/// `partial` means it worked on this device only (for example loopback), so it
/// still needs a second physical device to count.
enum CheckStatus { pending, partial, pass, fail }

class SpikeCheck {
  SpikeCheck(this.id, this.title, this.how);

  final String id;
  final String title;

  /// What to do on the phones to settle this check.
  final String how;
  CheckStatus status = CheckStatus.pending;
  String detail = '';
}

/// The eight PRD section 10.6 checks, plus a rolling log.
class SpikeReport extends ChangeNotifier {
  final Map<String, SpikeCheck> checks = {
    for (final c in [
      SpikeCheck('permission', '1. Local-network permission handled',
          'Start discovery. On iOS the system prompt must appear and denial must be handled.'),
      SpikeCheck('discovery', '2. Two devices discover each other (mDNS)',
          'Start discovery on both phones. Each must list the other.'),
      SpikeCheck('transfer', '3. Framed TCP file transfer in chunks',
          'Send the 5 MiB test file to the other phone.'),
      SpikeCheck('resume', '4. Interruption detected and transfer resumes',
          'Run the interrupted transfer to the other phone.'),
      SpikeCheck('import', '5. JPEG and HEIC import behaviour known',
          'Pick a JPEG, then an iPhone HEIC photo, and read the result.'),
      SpikeCheck('crossdecode', '6. Compressed image decodes and hash-verifies on the other platform',
          'Send a compressed image from Android to iPhone and back.'),
      SpikeCheck('keys', '7. Device key survives app restart',
          'Open this screen, fully close the app, open it again.'),
      SpikeCheck('background', '8. Backgrounded peer is marked unavailable',
          'Link both phones, then background one for 30 seconds.'),
    ])
      c.id: c,
  };

  final List<String> logLines = [];

  void setCheck(String id, CheckStatus status, String detail) {
    final c = checks[id]!;
    // Never downgrade a real pass because a weaker run happened later.
    if (c.status == CheckStatus.pass && status != CheckStatus.fail) return;
    c.status = status;
    c.detail = detail;
    notifyListeners();
  }

  void log(String line) {
    final t = DateTime.now().toIso8601String().substring(11, 19);
    logLines.add('$t $line');
    if (logLines.length > 200) logLines.removeAt(0);
    notifyListeners();
  }
}
