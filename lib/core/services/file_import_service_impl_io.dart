import 'dart:io';

import 'file_import_service.dart';

class IoFileImportService implements FileImportService {
  @override
  bool get supportsNativePicker => false;

  @override
  Future<ImportedTextFile?> pickTextFile({
    required List<String> allowedExtensions,
    String? dialogTitle,
  }) async {
    return null;
  }

  @override
  Future<ImportedTextFile?> readTextFileFromPath(String path) async {
    final trimmed = path.trim();
    if (trimmed.isEmpty) return null;

    final file = File(trimmed);
    if (!await file.exists()) return null;

    final content = await file.readAsString();
    final fileName =
        file.uri.pathSegments.isEmpty ? trimmed : file.uri.pathSegments.last;
    return ImportedTextFile(fileName: fileName, content: content);
  }
}

FileImportService createFileImportServiceImpl() => IoFileImportService();
