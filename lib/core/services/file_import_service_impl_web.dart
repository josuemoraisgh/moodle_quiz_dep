import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'file_import_service.dart';

class WebFileImportService implements FileImportService {
  @override
  bool get supportsNativePicker => true;

  @override
  Future<ImportedTextFile?> pickTextFile({
    required List<String> allowedExtensions,
    String? dialogTitle,
  }) {
    final input = web.HTMLInputElement()
      ..type = 'file'
      ..accept = allowedExtensions
          .map((ext) => '.${ext.trim().toLowerCase()}')
          .join(',');

    final completer = Completer<ImportedTextFile?>();

    input.onchange = ((web.Event _) {
      final files = input.files;
      if (files == null || files.length == 0) {
        if (!completer.isCompleted) {
          completer.complete(null);
        }
        return;
      }

      final file = files.item(0);
      if (file == null) {
        if (!completer.isCompleted) {
          completer.complete(null);
        }
        return;
      }

      final reader = web.FileReader();
      reader.onload = ((web.ProgressEvent _) {
        final result = reader.result;
        final content = result?.toString() ?? '';
        if (!completer.isCompleted) {
          completer.complete(
            ImportedTextFile(fileName: file.name.toString(), content: content),
          );
        }
      }).toJS;
      reader.onerror = ((web.ProgressEvent _) {
        if (!completer.isCompleted) {
          completer.complete(null);
        }
      }).toJS;
      reader.readAsText(file);
    }).toJS;

    input.click();
    return completer.future.timeout(
      const Duration(minutes: 2),
      onTimeout: () => null,
    );
  }

  @override
  Future<ImportedTextFile?> readTextFileFromPath(String path) async {
    return null;
  }
}

FileImportService createFileImportServiceImpl() => WebFileImportService();
