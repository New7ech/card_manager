import 'dart:io';
import 'package:crypto/crypto.dart';

class HashService {
  static Future<String> calculateMD5(File file) async {
    final bytes = await file.readAsBytes();
    return md5.convert(bytes).toString();
  }

  /// Hash tous les fichiers en parallèle et retourne uniques + doublons.
  /// [onProgress] est appelé après chaque hash complété.
  static Future<HashResult> processDuplicates(
    List<File> files, {
    void Function(int done, int total)? onProgress,
  }) async {
    int done = 0;
    final total = files.length;

    final hashes = await Future.wait(
      files.map((file) async {
        final hash = await calculateMD5(file);
        done++;
        onProgress?.call(done, total);
        return (file: file, hash: hash);
      }),
    );

    final Map<String, File> seen = {};
    final List<File> uniqueFiles = [];
    final List<File> duplicates = [];

    for (final entry in hashes) {
      if (seen.containsKey(entry.hash)) {
        duplicates.add(entry.file);
      } else {
        seen[entry.hash] = entry.file;
        uniqueFiles.add(entry.file);
      }
    }

    return HashResult(uniqueFiles: uniqueFiles, duplicates: duplicates);
  }
}

class HashResult {
  final List<File> uniqueFiles;
  final List<File> duplicates;

  HashResult({required this.uniqueFiles, required this.duplicates});
}
