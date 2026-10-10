import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:saber/components/theming/adaptive_alert_dialog.dart';
import 'package:saber/components/theming/adaptive_circular_progress_indicator.dart';
import 'package:saber/data/editor/editor_core_info.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/file_manager/pdf_auto_exporter.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/pages/editor/editor.dart';

class TogglePdfSyncButton extends StatefulWidget {
  const new({
    super.key,
    required this.selectedFiles,
    required this.unselectNotes,
  });

  final List<String> selectedFiles;
  final VoidCallback unselectNotes;

  @override
  State<TogglePdfSyncButton> createState() => _TogglePdfSyncButtonState();
}

class _TogglePdfSyncButtonState extends State<TogglePdfSyncButton> {
  var _isLoading = false;

  Future<void> _setPdfSync(bool enable) async {
    setState(() => _isLoading = true);

    int count = 0;
    for (final filePath in widget.selectedFiles) {
      try {
        final coreInfo = await EditorCoreInfo.loadFromFilePath(filePath);
        if (coreInfo.autoExportPdf != enable) {
          coreInfo.autoExportPdf = enable;
          final (bson, _) = coreInfo.saveToBinary(currentPageIndex: null);
          await FileManager.writeFile(
            filePath + Editor.extension,
            bson,
            awaitWrite: true,
          );
          if (enable &&
              stows.autoExportPdf.value &&
              stows.obsidianVaultPath.value != null &&
              mounted) {
            await PdfAutoExporter.autoExportToObsidian(
              coreInfo: coreInfo,
              context: context,
            );
          }
          count++;
        }
      } catch (e) {
        // Skip files that fail to parse
      }
    }

    if (mounted) {
      setState(() => _isLoading = false);
      widget.unselectNotes();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            enable
                ? 'Sincronización PDF activada para $count nota(s)'
                : 'Sincronización PDF desactivada para $count nota(s)',
          ),
        ),
      );
    }
  }

  void _showOptionsDialog() {
    showDialog(
      context: context,
      builder: (dialogContext) => AdaptiveAlertDialog(
        title: const Text('Sincronización PDF (Obsidian)'),
        content: Text(
          '¿Deseas activar o desactivar la exportación automática a PDF para las ${widget.selectedFiles.length} nota(s) seleccionada(s)?',
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _setPdfSync(false);
            },
            child: const Text('Desactivar'),
          ),
          CupertinoDialogAction(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _setPdfSync(true);
            },
            child: const Text('Activar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return AdaptiveCircularProgressIndicator.textStyled();
    }

    return IconButton(
      tooltip: 'Configurar sincronización PDF',
      icon: const Icon(Icons.picture_as_pdf),
      onPressed: _showOptionsDialog,
    );
  }
}
