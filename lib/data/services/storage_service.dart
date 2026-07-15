import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:firebase_storage/firebase_storage.dart';

class StorageUploadResult {
  const StorageUploadResult({
    required this.url,
    required this.fullPath,
    required this.fileName,
    required this.fileType,
    required this.fileSize,
  });

  final String url;
  final String fullPath;
  final String fileName;
  final String fileType;
  final int fileSize;
}

class StorageService {
  final FirebaseStorage _storage = FirebaseStorage.instance;

  Future<StorageUploadResult> uploadReceipt({
    required File file,
    required String memberId,
    required String organizationId,
    required String receiptId,
    required Function(double progress) onProgress,
  }) async {
    final originalName = file.path.split(Platform.pathSeparator).last;
    final fileName = originalName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final extension = fileName.split('.').last.toLowerCase();
    final fileType = switch (extension) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'webp' => 'image/webp',
      'pdf' => 'application/pdf',
      _ => throw const FormatException('Unsupported receipt file type.'),
    };
    final fileSize = await file.length();
    if (fileSize <= 0 || fileSize > 10 * 1024 * 1024) {
      throw const FormatException('Invalid receipt file size.');
    }
    final ref = _storage.ref(
      'organizations/$organizationId/members/$memberId/receipts/$receiptId/$fileName',
    );
    debugPrint('[Receipts] upload path=${ref.fullPath}');

    final task = ref.putFile(
      file,
      SettableMetadata(
        contentType: fileType,
        customMetadata: {
          'temporaryUpload': 'true',
          'receiptId': receiptId,
          'uploaderUid': memberId,
          'organizationId': organizationId,
          'uploadedAt': DateTime.now().toUtc().toIso8601String(),
        },
      ),
    );

    task.snapshotEvents.listen((snapshot) {
      final progress = snapshot.bytesTransferred / snapshot.totalBytes;
      onProgress(progress);
    });

    await task;
    return StorageUploadResult(
      url: await ref.getDownloadURL(),
      fullPath: ref.fullPath,
      fileName: fileName,
      fileType: fileType,
      fileSize: fileSize,
    );
  }

  Future<void> deleteReceipt(String url) async {
    final ref = _storage.refFromURL(url);
    await ref.delete();
  }

  Future<String> uploadProfilePhoto({
    required File file,
    required String userId,
  }) async {
    final length = await file.length();
    if (length <= 0 || length > 5 * 1024 * 1024) {
      throw const FormatException('Invalid profile image size.');
    }
    final extension = file.path.split('.').last.toLowerCase();
    final contentType = switch (extension) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'webp' => 'image/webp',
      _ => throw const FormatException('Unsupported profile image type.'),
    };
    final reference = _storage.ref('users/$userId/profile/profile_photo.jpg');
    await reference.putFile(
      file,
      SettableMetadata(
        contentType: contentType,
        cacheControl: 'public,max-age=3600',
      ),
    );
    return reference.getDownloadURL();
  }
}
