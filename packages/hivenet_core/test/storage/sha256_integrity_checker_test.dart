import 'dart:convert';
import 'dart:io';

import 'package:hivenet_core/hivenet_core.dart';
import 'package:test/test.dart';

void main() {
  const checker = Sha256IntegrityChecker();
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('hn_integrity'));
  tearDown(() => tmp.deleteSync(recursive: true));

  // Published SHA-256 test vectors.
  const emptyHash =
      'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';
  const abcHash =
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad';

  test('hashes bytes against known vectors', () async {
    expect(await checker.sha256OfBytes(const []), emptyHash);
    expect(await checker.sha256OfBytes(utf8.encode('abc')), abcHash);
  });

  test('hashes files, including empty ones', () async {
    final empty = File('${tmp.path}/empty')..writeAsBytesSync([]);
    final abc = File('${tmp.path}/abc')..writeAsStringSync('abc');
    expect(await checker.sha256OfFile(empty.path), emptyHash);
    expect(await checker.sha256OfFile(abc.path), abcHash);
  });

  test('a multi-megabyte file matches the in-memory hash', () async {
    final bytes = List<int>.generate(3 * 1024 * 1024 + 17, (i) => i % 253);
    final file = File('${tmp.path}/big')..writeAsBytesSync(bytes);
    expect(await checker.sha256OfFile(file.path),
        await checker.sha256OfBytes(bytes));
  });

  test('verifyFile accepts the right hash in any case and rejects others',
      () async {
    final abc = File('${tmp.path}/abc')..writeAsStringSync('abc');
    expect(await checker.verifyFile(abc.path, abcHash), isTrue);
    expect(await checker.verifyFile(abc.path, abcHash.toUpperCase()), isTrue);
    expect(await checker.verifyFile(abc.path, emptyHash), isFalse);
  });

  test('a missing file throws instead of reporting a match', () {
    expect(checker.sha256OfFile('${tmp.path}/nope'),
        throwsA(isA<FileSystemException>()));
  });
}
