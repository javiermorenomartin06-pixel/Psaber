import 'package:flutter/services.dart';
import 'package:logging/logging.dart';

/// Interfaz con el puente nativo Android Storage Access Framework (SAF)
/// para leer, escribir, renombrar y borrar archivos en URIs 'content://'
/// (como las carpetas de bóvedas de Obsidian seleccionadas por el usuario).
abstract class SafStorageService {
  static final log = Logger('SafStorageService');
  static const _channel = MethodChannel('com.adilhanney.saber/saf_storage');

  /// Determina si una ruta es una URI de SAF ('content://')
  static bool isContentUri(String? path) {
    if (path == null) return false;
    return path.startsWith('content://');
  }

  /// Reclama permisos persistentes sobre el árbol SAF para que la app
  /// mantenga acceso tras reiniciar la tablet o cerrar la app.
  static Future<bool> takePersistablePermission(String uri) async {
    try {
      final result = await _channel.invokeMethod<bool>('takePersistablePermission', {
        'uri': uri,
      });
      return result ?? false;
    } catch (e, st) {
      log.warning('Error al reclamar permisos persistentes SAF para $uri: $e', e, st);
      return false;
    }
  }

  /// Verifica si la URI sigue siendo accesible con permisos de escritura.
  static Future<bool> isUriAccessible(String uri) async {
    try {
      final result = await _channel.invokeMethod<bool>('isUriAccessible', {
        'uri': uri,
      });
      return result ?? false;
    } catch (e, st) {
      log.warning('Error al verificar accesibilidad de URI SAF $uri: $e', e, st);
      return false;
    }
  }

  /// Escribe un archivo (creándolo o sobrescribiéndolo en modo truncado)
  /// dentro del árbol SAF especificado por [treeUri].
  static Future<bool> writeFile({
    required String treeUri,
    required String relativePath,
    required Uint8List bytes,
    String mimeType = 'application/pdf',
  }) async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>('writeFile', {
        'treeUri': treeUri,
        'relativePath': relativePath,
        'bytes': bytes,
        'mimeType': mimeType,
      });
      return result != null;
    } catch (e, st) {
      log.warning('Error al escribir archivo SAF ($relativePath): $e', e, st);
      return false;
    }
  }

  /// Renombra un archivo dentro del árbol SAF.
  static Future<bool> renameFile({
    required String treeUri,
    required String oldRelativePath,
    required String newRelativePath,
  }) async {
    try {
      final result = await _channel.invokeMethod<bool>('renameFile', {
        'treeUri': treeUri,
        'oldRelativePath': oldRelativePath,
        'newRelativePath': newRelativePath,
      });
      return result ?? false;
    } catch (e, st) {
      log.warning('Error al renombrar archivo SAF ($oldRelativePath -> $newRelativePath): $e', e, st);
      return false;
    }
  }

  /// Elimina un archivo dentro del árbol SAF.
  static Future<bool> deleteFile({
    required String treeUri,
    required String relativePath,
  }) async {
    try {
      final result = await _channel.invokeMethod<bool>('deleteFile', {
        'treeUri': treeUri,
        'relativePath': relativePath,
      });
      return result ?? false;
    } catch (e, st) {
      log.warning('Error al borrar archivo SAF ($relativePath): $e', e, st);
      return false;
    }
  }

  /// Formatea una URI de SAF técnica a una ruta amigable y legible para el usuario.
  /// Ej: content://com.android.externalstorage.documents/tree/primary%3AObsidiana%2FObsidiana%2FURJC%20javi
  /// -> "Obsidiana/Obsidiana/URJC javi"
  static String formatDisplayPath(String? path) {
    if (path == null || path.isEmpty) return 'No seleccionada';
    if (!isContentUri(path)) return path;

    try {
      final decoded = Uri.decodeFull(path);
      if (decoded.contains('primary:')) {
        final afterPrimary = decoded.split('primary:').last;
        return afterPrimary.isEmpty ? 'Almacenamiento principal' : afterPrimary;
      }
      if (decoded.contains('/tree/')) {
        final afterTree = decoded.split('/tree/').last;
        return afterTree;
      }
      return decoded;
    } catch (_) {
      return path;
    }
  }
}
