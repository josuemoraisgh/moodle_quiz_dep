import 'file_import_service.dart';

class StubFileImportService implements FileImportService {
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
    return null;
  }
}

FileImportService createFileImportServiceImpl() => StubFileImportService();
