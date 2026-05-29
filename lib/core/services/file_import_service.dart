import 'file_import_service_impl_stub.dart'
    if (dart.library.js_interop) 'file_import_service_impl_web.dart'
    if (dart.library.io) 'file_import_service_impl_io.dart';

class ImportedTextFile {
  final String fileName;
  final String content;

  const ImportedTextFile({
    required this.fileName,
    required this.content,
  });
}

abstract class FileImportService {
  bool get supportsNativePicker;

  Future<ImportedTextFile?> pickTextFile({
    required List<String> allowedExtensions,
    String? dialogTitle,
  });

  Future<ImportedTextFile?> readTextFileFromPath(String path);
}

FileImportService createFileImportService() => createFileImportServiceImpl();
