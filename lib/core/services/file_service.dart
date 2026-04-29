import 'dart:io';
import 'package:file_picker/file_picker.dart';

class FileService {
  static const _supportedExtensions = {
    '.jpg', '.jpeg', '.png', '.webp', '.bmp', '.gif',
    '.tiff', '.tif', '.heic', '.heif', '.pdf',
  };

  /// Sélectionne un dossier et retourne tous les fichiers supportés qu'il contient.
  /// [hasFullAccess] : sur Android, true si MANAGE_EXTERNAL_STORAGE est accordé —
  /// dans ce cas on utilise un sélecteur de dossier réel (chemins vrais, suppressions possibles).
  static Future<FolderSelection?> pickFolder({bool hasFullAccess = false}) async {
    if (Platform.isAndroid || Platform.isIOS) {
      return hasFullAccess ? _pickFolderDesktop() : _pickFolderMobile();
    }
    return _pickFolderDesktop();
  }

  // ── Desktop ──────────────────────────────────────────────────────────────

  static Future<FolderSelection?> _pickFolderDesktop() async {
    final dirPath = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Choisir un dossier à analyser',
    );
    if (dirPath == null) return null; // annulation

    final root = Directory(dirPath);
    if (!root.existsSync()) {
      throw FileSystemException('Dossier introuvable', dirPath);
    }

    // Tous les fichiers (pour le diagnostic)
    final allFiles = root
        .listSync(recursive: true)
        .whereType<File>()
        .toList();

    // Extensions réellement trouvées dans le dossier
    final foundExtensions = allFiles
        .map((f) {
          final name = _basename(f.path).toLowerCase();
          final dot = name.lastIndexOf('.');
          return dot >= 0 ? name.substring(dot) : '(sans extension)';
        })
        .toSet()
        .toList()
      ..sort();

    // Uniquement les fichiers avec une extension supportée
    final supported = allFiles
        .where((f) => _isSupported(f.path))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

    return FolderSelection(
      root: root,
      files: supported,
      totalScanned: allFiles.length,
      foundExtensions: foundExtensions,
    );
  }

  // ── Mobile ───────────────────────────────────────────────────────────────

  static Future<FolderSelection?> _pickFolderMobile() async {
    final extensions =
        _supportedExtensions.map((e) => e.substring(1)).toList();

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: extensions,
      allowMultiple: true,
    );
    if (result == null) return null; // annulation

    final total = result.files.length;

    // Sur Android (SAF / scoped storage), certains fichiers ont un chemin null.
    final withPath = result.files.where((f) => f.path != null).toList();

    if (withPath.isEmpty && total > 0) {
      // Le picker a retourné des fichiers mais sans chemins accessibles.
      throw Exception(
        '$total fichier(s) sélectionné(s) mais leurs chemins sont inaccessibles '
        '(restriction Android scoped storage).\n\n'
        'Essayez d\'activer l\'autorisation "Accès à tous les fichiers" '
        'dans les paramètres de l\'application.',
      );
    }

    final files = withPath.map((f) => File(f.path!)).toList();

    // Dossier racine = parent du premier fichier sélectionné.
    final root = files.isNotEmpty
        ? files.first.parent
        : Directory(Platform.isAndroid
            ? '/storage/emulated/0'
            : Directory.current.path);

    return FolderSelection(
      root: root,
      files: files,
      totalScanned: total,
    );
  }

  // ── Méthode historique conservée (Classer / Dupliquer) ──────────────────

  static Future<List<File>?> pickImagesFromFolder() async {
    final sel = await pickFolder();
    return sel?.files;
  }

  // ── Déplacement des doublons ─────────────────────────────────────────────

  /// Crée un sous-dossier "doublons_HORODATAGE" dans [targetParent]
  /// et y déplace chaque fichier de [duplicates].
  static Future<MoveResult> moveDuplicatesToFolder(
    List<File> duplicates, {
    required Directory targetParent,
  }) async {
    final now = DateTime.now();
    final ts = '${now.year}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}'
        '_${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}'
        '${now.second.toString().padLeft(2, '0')}';

    final sep = Platform.pathSeparator;
    final destDir = Directory('${targetParent.path}${sep}doublons_$ts');
    await destDir.create(recursive: true);

    final usedNames = <String>{};
    final errors = <String>[];
    int moved = 0;

    for (final file in duplicates) {
      if (!file.existsSync()) {
        errors.add('${_basename(file.path)} : fichier introuvable');
        continue;
      }

      final name = _uniqueName(_basename(file.path), usedNames);
      usedNames.add(name);
      final destPath = '${destDir.path}$sep$name';

      try {
        await file.rename(destPath);
        moved++;
      } catch (_) {
        try {
          await file.copy(destPath);
          await file.delete();
          moved++;
        } catch (e) {
          errors.add('$name : $e');
        }
      }
    }

    return MoveResult(
      folderPath: destDir.path,
      moved: moved,
      errors: errors,
    );
  }

  // ── Utilitaires ──────────────────────────────────────────────────────────

  static bool _isSupported(String path) {
    final lower = path.toLowerCase();
    return _supportedExtensions.any((ext) => lower.endsWith(ext));
  }

  static bool isPdf(String path) => path.toLowerCase().endsWith('.pdf');

  static String _basename(String path) {
    final lastBack = path.lastIndexOf('\\');
    final lastFwd = path.lastIndexOf('/');
    final last = lastBack > lastFwd ? lastBack : lastFwd;
    return last >= 0 ? path.substring(last + 1) : path;
  }

  static String _uniqueName(String original, Set<String> used) {
    if (!used.contains(original)) return original;
    final dot = original.lastIndexOf('.');
    final base = dot >= 0 ? original.substring(0, dot) : original;
    final ext = dot >= 0 ? original.substring(dot) : '';
    var i = 1;
    String candidate;
    do {
      candidate = '${base}_$i$ext';
      i++;
    } while (used.contains(candidate));
    return candidate;
  }
}

// ── Data classes ─────────────────────────────────────────────────────────────

class FolderSelection {
  final Directory root;
  final List<File> files;
  final int totalScanned;
  final List<String> foundExtensions;

  FolderSelection({
    required this.root,
    required this.files,
    required this.totalScanned,
    this.foundExtensions = const [],
  });
}

class MoveResult {
  final String folderPath;
  final int moved;
  final List<String> errors;

  MoveResult({
    required this.folderPath,
    required this.moved,
    required this.errors,
  });
}
