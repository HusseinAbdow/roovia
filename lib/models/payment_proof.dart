import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';

class PaymentProofInput {
  final Uint8List bytes;
  final String fileName;
  final String mimeType;
  final String kind;
  final int sizeBytes;

  const PaymentProofInput({
    required this.bytes,
    required this.fileName,
    required this.mimeType,
    required this.kind,
    required this.sizeBytes,
  });

  bool get isImage => kind == 'image';

  bool get isPdf => kind == 'pdf';
}

class PaymentProofAttachment {
  final String fileName;
  final String downloadUrl;
  final String storagePath;
  final String mimeType;
  final String kind;
  final int sizeBytes;
  final DateTime? uploadedAt;

  const PaymentProofAttachment({
    required this.fileName,
    required this.downloadUrl,
    required this.storagePath,
    required this.mimeType,
    required this.kind,
    required this.sizeBytes,
    required this.uploadedAt,
  });

  bool get isImage => kind == 'image';

  bool get isPdf => kind == 'pdf';

  factory PaymentProofAttachment.fromMap(Map<String, dynamic> map) {
    final uploadedAtValue = map['uploadedAt'];
    return PaymentProofAttachment(
      fileName: (map['fileName'] as String?) ?? 'proof',
      downloadUrl: (map['downloadUrl'] as String?) ?? '',
      storagePath: (map['storagePath'] as String?) ?? '',
      mimeType: (map['mimeType'] as String?) ?? '',
      kind: (map['kind'] as String?) ?? 'image',
      sizeBytes: (map['sizeBytes'] as num?)?.toInt() ?? 0,
      uploadedAt: uploadedAtValue is Timestamp
          ? uploadedAtValue.toDate()
          : uploadedAtValue is DateTime
          ? uploadedAtValue
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'fileName': fileName,
      'downloadUrl': downloadUrl,
      'storagePath': storagePath,
      'mimeType': mimeType,
      'kind': kind,
      'sizeBytes': sizeBytes,
      'uploadedAt': uploadedAt,
    };
  }
}
