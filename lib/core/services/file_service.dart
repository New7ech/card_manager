import 'dart:io';
import 'package:file_picker/file_picker.dart';

class FileService {
  // Tous les formats acceptés (images + PDF)
  static const _supportedExtensions = {
    // Images raster
    '.jpg', '.jpeg', '.png', '.webp', '.bmp', '.gif',
    '.tiff', '.tif', '.heic', '.heif',
    // PDF
    '.pdf',
  };

  /// Sur mobile (Android / iOS) : sélection multiple de fichiers via le picker natif.
  /// Sur desktop : sélection d'un dossier entier avec scan récursif.
  static Future<List<File>?> pickImagesFromFolder() async {
    if (Platform.isAndroid || Platform.isIOS) {
      return _pickFilesDirectly();
    }
    return _pickFromDirectory();
  }

  // Desktop : sélection d'un dossier + scan récursif
  static Future<List<File>?> _pickFromDirectory() async {
    final dirPath = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Choisir un dossier',
    );
    if (dirPath == null) return null;

    final dir = Directory(dirPath);
    if (!dir.existsSync()) {
      throw FileSystemException('Dossier introuvable', dirPath);
    }

    final files = dir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => _isSupported(f.path))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

    return files; // liste vide si rien trouvé, null si annulation
  }

  // Mobile : picker natif avec filtre d'extensions
  static Future<List<File>?> _pickFilesDirectly() async {
    final extensions =
        _supportedExtensions.map((e) => e.substring(1)).toList();

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: extensions,
      allowMultiple: true,
    );
    if (result == null) return null;

    return result.files
        .where((f) => f.path != null)
        .map((f) => File(f.path!))
        .toList();
  }

  static bool _isSupported(String path) {
    final lower = path.toLowerCase();
    return _supportedExtensions.any((ext) => lower.endsWith(ext));
  }

  static bool isPdf(String path) => path.toLowerCase().endsWith('.pdf');
}
