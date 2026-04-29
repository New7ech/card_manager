import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';

import '../core/services/file_service.dart';
import '../core/services/hash_service.dart';
import '../core/services/pdf_service.dart';

class MainMenuScreen extends StatefulWidget {
  const MainMenuScreen({super.key});

  @override
  State<MainMenuScreen> createState() => _MainMenuScreenState();
}

class _MainMenuScreenState extends State<MainMenuScreen> {
  final ImagePicker _picker = ImagePicker();
  bool _isLoading = false;
  String _progressMessage = '';

  void _setLoading(bool value, [String message = '']) {
    if (!mounted) return;
    setState(() {
      _isLoading = value;
      _progressMessage = message;
    });
  }

  // Affiche un bottom sheet pour choisir galerie ou dossier,
  // puis retourne la liste de fichiers sélectionnés.
  Future<List<File>?> _pickImages({bool singleOnly = false}) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _SourceSheet(singleOnly: singleOnly),
    );
    if (choice == null) return null;

    if (choice == 'gallery') {
      if (singleOnly) {
        final image = await _picker.pickImage(source: ImageSource.gallery);
        return image == null ? null : [File(image.path)];
      } else {
        final images = await _picker.pickMultiImage();
        return images.isEmpty ? null : images.map((x) => File(x.path)).toList();
      }
    } else {
      try {
        final files = await FileService.pickImagesFromFolder();
        if (files == null) return null; // annulation
        if (files.isEmpty) {
          _showSnackBar(
              'Aucune image trouvée dans ce dossier (jpg, png, webp…).');
          return null;
        }
        _showSnackBar('${files.length} image(s) trouvée(s) dans le dossier.');
        if (singleOnly) return [files.first];
        return files;
      } catch (e) {
        _showSnackBar(_friendlyError(e));
        return null;
      }
    }
  }

  Future<void> _handleClasser() async {
    final files = await _pickImages();
    if (files == null) return;
    try {
      _setLoading(true, 'Analyse des doublons...');
      final result = await HashService.processDuplicates(
        files,
        onProgress: (d, t) => _setLoading(true, 'Hash : $d / $t images...'),
      );

      if (result.uniqueFiles.isEmpty) {
        _setLoading(false);
        _showSnackBar('Aucune image valide à traiter.');
        return;
      }

      _setLoading(true, 'Génération du PDF...');
      final dir = await getApplicationDocumentsDirectory();
      final pdfPath =
          '${dir.path}/cartes_classees_${DateTime.now().millisecondsSinceEpoch}.pdf';
      final pdfFile =
          await PdfService.generateCardGridPdf(result.uniqueFiles, pdfPath);

      _setLoading(false);
      if (!mounted) return;
      _showCompletionDialog(
        title: 'Classement terminé',
        content:
            'Fichiers uniques : ${result.uniqueFiles.length}\nDoublons ignorés : ${result.duplicates.length}',
        fileToShare: pdfFile,
      );
    } catch (e) {
      _setLoading(false);
      _showSnackBar(_friendlyError(e));
    }
  }

  Future<void> _handleDoublons() async {
    // Sur Android : demander MANAGE_EXTERNAL_STORAGE pour accéder aux vrais chemins.
    bool hasFullAccess = false;
    if (Platform.isAndroid) {
      var status = await Permission.manageExternalStorage.status;
      if (!status.isGranted) {
        status = await Permission.manageExternalStorage.request();
      }
      if (!status.isGranted) {
        if (!mounted) return;
        // Proposer de continuer en mode limité ou d'ouvrir les paramètres.
        final goToSettings = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Permission requise'),
            content: const Text(
              'L\'autorisation "Accès à tous les fichiers" est nécessaire '
              'pour supprimer automatiquement les doublons.\n\n'
              'Sans cette permission, les doublons seront seulement copiés '
              'dans un dossier visible, sans suppression des originaux.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Continuer sans'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Ouvrir Paramètres'),
              ),
            ],
          ),
        );
        if (goToSettings == true) {
          await openAppSettings();
          return;
        }
      } else {
        hasFullAccess = true;
      }
    }

    // Sélection du dossier — retourne aussi le chemin racine pour y créer le dossier doublons.
    FolderSelection? selection;
    try {
      selection = await FileService.pickFolder(hasFullAccess: hasFullAccess);
    } catch (e) {
      _showErrorDialog('Erreur d\'accès au dossier', e.toString());
      return;
    }
    if (selection == null) return; // annulation

    if (selection.files.isEmpty) {
      final extFound = selection.foundExtensions.isEmpty
          ? 'aucune'
          : selection.foundExtensions.join(', ');
      _showErrorDialog(
        'Aucun fichier supporté',
        'Dossier : ${selection.root.path}\n'
        'Fichiers trouvés : ${selection.totalScanned}\n'
        'Extensions détectées : $extFound\n\n'
        'Extensions acceptées : jpg, jpeg, png, webp, bmp, gif, '
        'tiff, heic, heif, pdf.',
      );
      return;
    }

    try {
      _setLoading(
        true,
        'Analyse de ${selection.files.length} fichier(s)…',
      );
      final result = await HashService.processDuplicates(
        selection.files,
        onProgress: (d, t) =>
            _setLoading(true, 'Empreintes : $d / $t fichiers…'),
      );

      if (result.duplicates.isEmpty) {
        _setLoading(false);
        if (!mounted) return;
        _showInfoDialog(
          'Aucun doublon',
          '${selection.files.length} fichier(s) analysé(s)\n'
          'Aucun doublon détecté.',
        );
        return;
      }

      _setLoading(
        true,
        'Déplacement de ${result.duplicates.length} doublon(s)…',
      );

      // Avec MANAGE_EXTERNAL_STORAGE : selection.root est le vrai dossier,
      // on y crée le sous-dossier doublons et on supprime les originaux.
      // Sans la permission : on copie vers le stockage externe visible.
      Directory targetParent = selection.root;
      if (Platform.isAndroid && !hasFullAccess) {
        final extDir = await getExternalStorageDirectory();
        if (extDir != null) targetParent = extDir;
      }

      final moveResult = await FileService.moveDuplicatesToFolder(
        result.duplicates,
        targetParent: targetParent,
      );

      _setLoading(false);
      if (!mounted) return;

      final ok = moveResult.errors.isEmpty;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          title: Text(ok
              ? (hasFullAccess ? 'Doublons supprimés' : 'Doublons sauvegardés')
              : 'Opération partielle'),
          content: SingleChildScrollView(
            child: Text(
              'Fichiers analysés : ${selection!.files.length}\n'
              'Uniques conservés : ${result.uniqueFiles.length}\n'
              'Doublons ${hasFullAccess ? 'supprimés' : 'copiés'} : '
              '${moveResult.moved} / ${result.duplicates.length}\n'
              '\nDossier créé :\n${moveResult.folderPath}'
              '${!hasFullAccess ? '\n\nLes fichiers originaux sont toujours dans votre galerie. Supprimez-les manuellement si souhaité.' : ''}'
              '${ok ? '' : '\n\nEchecs :\n${moveResult.errors.join('\n')}'}',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } catch (e) {
      _setLoading(false);
      if (!mounted) return;
      _showErrorDialog('Erreur', e.toString());
    }
  }

  void _showInfoDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK')),
        ],
      ),
    );
  }

  void _showErrorDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(child: Text(message)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK')),
        ],
      ),
    );
  }

  Future<void> _handleDupliquer() async {
    final int? count = await _askCopyCount();
    if (count == null) return;

    final files = await _pickImages(singleOnly: true);
    if (files == null) return;
    try {
      _setLoading(true, 'Génération du PDF ($count copies)...');
      final duplicatedList = List.generate(count, (_) => files.first);

      final dir = await getApplicationDocumentsDirectory();
      final pdfPath =
          '${dir.path}/carte_visite_${count}x_${DateTime.now().millisecondsSinceEpoch}.pdf';
      final pdfFile =
          await PdfService.generateCardGridPdf(duplicatedList, pdfPath);

      _setLoading(false);
      if (!mounted) return;
      _showCompletionDialog(
        title: 'Duplication terminée',
        content: 'Un PDF avec $count copies de votre carte a été généré.',
        fileToShare: pdfFile,
      );
    } catch (e) {
      _setLoading(false);
      _showSnackBar(_friendlyError(e));
    }
  }

  Future<int?> _askCopyCount() {
    int selectedCount = 10;
    return showDialog<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('Nombre de copies'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$selectedCount copies',
                style: const TextStyle(
                    fontSize: 26, fontWeight: FontWeight.bold),
              ),
              Slider(
                value: selectedCount.toDouble(),
                min: 1,
                max: 30,
                divisions: 29,
                label: '$selectedCount',
                onChanged: (v) => set(() => selectedCount = v.round()),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Annuler')),
            ElevatedButton(
                onPressed: () => Navigator.pop(ctx, selectedCount),
                child: const Text('Valider')),
          ],
        ),
      ),
    );
  }

  void _showCompletionDialog({
    required String title,
    required String content,
    required File fileToShare,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Fermer')),
          ElevatedButton.icon(
            icon: const Icon(Icons.share),
            label: const Text('Partager le PDF'),
            onPressed: () {
              SharePlus.instance.share(ShareParams(
                files: [XFile(fileToShare.path)],
                text: 'Voici mon PDF généré !',
              ));
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }

  void _showSnackBar(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  String _friendlyError(Object e) {
    final msg = e.toString();
    if (msg.contains('permission') || msg.contains('Permission')) {
      return 'Accès refusé — vérifiez les permissions de l\'application.';
    }
    if (msg.contains('storage') || msg.contains('disk')) {
      return 'Espace disque insuffisant.';
    }
    if (msg.contains('FileSystemException')) {
      return 'Erreur de lecture du fichier image.';
    }
    return 'Une erreur est survenue. Réessayez.';
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: const Color(0xFFF2F4F8),
      body: Stack(
        children: [
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(),
                  const SizedBox(height: 32),
                  _sectionLabel('Actions'),
                  const SizedBox(height: 12),
                  _buildActionCard(
                    title: 'Classer',
                    subtitle:
                        'Supprime les doublons et génère un PDF A4 en grille.',
                    icon: Icons.grid_view_rounded,
                    color: Colors.blue.shade600,
                    onTap: _handleClasser,
                  ),
                  const SizedBox(height: 12),
                  _buildActionCard(
                    title: 'Nettoyer les doublons',
                    subtitle:
                        'Analyse un dossier (images + PDF) et déplace les doublons.',
                    icon: Icons.cleaning_services_rounded,
                    color: Colors.green.shade600,
                    onTap: _handleDoublons,
                  ),
                  const SizedBox(height: 12),
                  _buildActionCard(
                    title: 'Dupliquer une carte',
                    subtitle:
                        'Génère un PDF avec 1 à 30 copies d\'une seule carte.',
                    icon: Icons.copy_all_rounded,
                    color: Colors.orange.shade700,
                    onTap: _handleDupliquer,
                  ),
                  const SizedBox(height: 28),
                  _buildInfoBanner(),
                ],
              ),
            ),
          ),
          if (_isLoading) _buildLoadingOverlay(primary),
        ],
      ),
    );
  }

  // ── Widgets de construction ──────────────────────────────────────────────

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue.shade800, Colors.blue.shade500],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.shade200,
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.credit_card_rounded,
                size: 38, color: Colors.white),
          ),
          const SizedBox(width: 18),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Card Manager HQ',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.3,
                  ),
                ),
                SizedBox(height: 5),
                Text(
                  'Gérez et imprimez vos cartes de visite',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String label) {
    return Text(
      label.toUpperCase(),
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: Colors.grey.shade500,
        letterSpacing: 1.2,
      ),
    );
  }

  Widget _buildActionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    final disabled = _isLoading;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      elevation: 0,
      child: InkWell(
        onTap: disabled ? null : onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: disabled ? 0.05 : 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  icon,
                  size: 28,
                  color: disabled ? Colors.grey.shade400 : color,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: disabled
                            ? Colors.grey.shade400
                            : Colors.grey.shade900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                          fontSize: 13, color: Colors.grey.shade500),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: disabled
                    ? Colors.grey.shade200
                    : Colors.grey.shade400,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.blue.shade100),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded,
              size: 18, color: Colors.blue.shade400),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Chaque action propose de choisir entre la galerie ou un dossier entier.',
              style:
                  TextStyle(fontSize: 13, color: Colors.blue.shade700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingOverlay(Color primary) {
    return Container(
      color: Colors.black38,
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 48),
          padding:
              const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: primary),
              if (_progressMessage.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  _progressMessage,
                  style: const TextStyle(fontSize: 14),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Bottom sheet de sélection de source ─────────────────────────────────────

class _SourceSheet extends StatelessWidget {
  final bool singleOnly;

  const _SourceSheet({required this.singleOnly});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 36),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 22),
          const Text(
            'Source des images',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(
            singleOnly
                ? 'Choisissez où importer la carte.'
                : 'Choisissez où importer les images.',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
          ),
          const SizedBox(height: 20),
          _SourceTile(
            icon: Icons.photo_library_rounded,
            color: Colors.blue.shade600,
            title: 'Depuis la galerie',
            subtitle: singleOnly
                ? 'Sélectionner 1 image'
                : 'Sélectionner plusieurs images',
            value: 'gallery',
          ),
          const SizedBox(height: 12),
          _SourceTile(
            icon: Icons.folder_rounded,
            color: Colors.orange.shade700,
            title: 'Depuis un dossier',
            subtitle: 'Importer toutes les images d\'un dossier',
            value: 'folder',
          ),
        ],
      ),
    );
  }
}

class _SourceTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final String value;

  const _SourceTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => Navigator.pop(context, value),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.18)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 15)),
                  const SizedBox(height: 3),
                  Text(subtitle,
                      style: TextStyle(
                          color: Colors.grey.shade500, fontSize: 13)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                color: color.withValues(alpha: 0.5)),
          ],
        ),
      ),
    );
  }
}
