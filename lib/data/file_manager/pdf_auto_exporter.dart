import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:saber/data/editor/editor_core_info.dart';
import 'package:saber/data/editor/editor_exporter.dart';
import 'package:saber/data/file_manager/saf_storage_service.dart';
import 'package:saber/data/prefs.dart';

/// Manages automatic PDF export directly into the user's Obsidian Vault
/// or custom PDF directory. Maintains a single PDF per note by overwriting it
/// in-place whenever changes are saved.
abstract class PdfAutoExporter {
  static final log = Logger('PdfAutoExporter');

  /// Exports the given [coreInfo] as a single PDF into the Obsidian vault.
  /// Overwrites the existing PDF so no duplicates are created.
  static Future<String?> autoExportToObsidian({
    required EditorCoreInfo coreInfo,
    required BuildContext context,
  }) async {
    final vaultPath = stows.obsidianVaultPath.value;
    if (vaultPath == null || vaultPath.trim().isEmpty) return null;
    if (!stows.autoExportPdf.value) return null;

    try {
      String relPath = coreInfo.filePath;
      if (relPath.startsWith('/')) {
        relPath = relPath.substring(1);
      }
      final pdfRelPath = '$relPath.pdf';

      if (!context.mounted) return null;
      // Generate the PDF document with vector strokes and rasterized textures
      final pdf = await EditorExporter.generatePdf(coreInfo, context);
      final bytes = await pdf.save();

      if (SafStorageService.isContentUri(vaultPath)) {
        final success = await SafStorageService.writeFile(
          treeUri: vaultPath,
          relativePath: pdfRelPath,
          bytes: bytes,
          mimeType: 'application/pdf',
        );
        if (success) {
          log.info('Auto-exported PDF to Obsidian vault via SAF: $pdfRelPath');
          return pdfRelPath;
        } else {
          log.warning('SAF write returned false for: $pdfRelPath');
          return null;
        }
      } else {
        final targetPdfPath = p.join(vaultPath, pdfRelPath);
        final targetFile = File(targetPdfPath);

        // Ensure directory hierarchy exists inside the Obsidian vault
        await targetFile.parent.create(recursive: true);

        // Write bytes directly, replacing any previous PDF file
        await targetFile.writeAsBytes(bytes, flush: true);
        log.info('Auto-exported PDF to Obsidian vault: $targetPdfPath');
        return targetPdfPath;
      }
    } catch (e, st) {
      log.warning('Failed to auto-export PDF to Obsidian vault: $e', e, st);
      return null;
    }
  }

  /// Synchronizes note renaming with the Obsidian vault PDF file.
  static Future<void> onNoteRenamed({
    required String oldPath,
    required String newPath,
  }) async {
    final vaultPath = stows.obsidianVaultPath.value;
    if (vaultPath == null || vaultPath.trim().isEmpty) return;

    try {
      final oldRel = oldPath.startsWith('/') ? oldPath.substring(1) : oldPath;
      final newRel = newPath.startsWith('/') ? newPath.substring(1) : newPath;
      final oldPdf = '$oldRel.pdf';
      final newPdf = '$newRel.pdf';

      if (SafStorageService.isContentUri(vaultPath)) {
        await SafStorageService.renameFile(
          treeUri: vaultPath,
          oldRelativePath: oldPdf,
          newRelativePath: newPdf,
        );
        log.info('Renamed Obsidian SAF PDF from $oldPdf to $newPdf');
      } else {
        final oldFile = File(p.join(vaultPath, oldPdf));
        final newFile = File(p.join(vaultPath, newPdf));

        if (oldFile.existsSync()) {
          await newFile.parent.create(recursive: true);
          await oldFile.rename(newFile.path);
          log.info('Renamed Obsidian PDF from ${oldFile.path} to ${newFile.path}');
        }
      }
    } catch (e, st) {
      log.warning('Failed to rename Obsidian vault PDF: $e', e, st);
    }
  }

  /// Deletes the corresponding PDF in the Obsidian vault when a note is deleted.
  static Future<void> onNoteDeleted(String filePath) async {
    final vaultPath = stows.obsidianVaultPath.value;
    if (vaultPath == null || vaultPath.trim().isEmpty) return;

    try {
      final rel = filePath.startsWith('/') ? filePath.substring(1) : filePath;
      final pdfRel = '$rel.pdf';

      if (SafStorageService.isContentUri(vaultPath)) {
        await SafStorageService.deleteFile(
          treeUri: vaultPath,
          relativePath: pdfRel,
        );
        log.info('Deleted Obsidian vault SAF PDF: $pdfRel');
      } else {
        final pdfFile = File(p.join(vaultPath, pdfRel));
        if (pdfFile.existsSync()) {
          pdfFile.deleteSync();
          log.info('Deleted Obsidian vault PDF: ${pdfFile.path}');
        }
      }
    } catch (e, st) {
      log.warning('Failed to delete Obsidian vault PDF: $e', e, st);
    }
  }
}
