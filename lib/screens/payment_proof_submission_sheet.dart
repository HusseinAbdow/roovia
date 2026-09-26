import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/payment_proof.dart';
import '../services/expense_service.dart';

class PaymentProofSubmissionSheet extends StatefulWidget {
  final String expenseId;
  final String participantId;
  final String expenseTitle;

  const PaymentProofSubmissionSheet({
    super.key,
    required this.expenseId,
    required this.participantId,
    required this.expenseTitle,
  });

  @override
  State<PaymentProofSubmissionSheet> createState() => _PaymentProofSubmissionSheetState();
}

class _PaymentProofSubmissionSheetState extends State<PaymentProofSubmissionSheet> {
  static const int _maxAttachmentCount = 3;
  static const int _maxAttachmentBytes = 12 * 1024 * 1024;

  final ExpenseService _expenseService = ExpenseService();
  final TextEditingController _noteController = TextEditingController();
  final List<PaymentProofInput> _attachments = <PaymentProofInput>[];

  bool _submitting = false;
  double _uploadProgress = 0;
  String? _errorText;

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  String _humanSize(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '$bytes B';
  }

  String _fileKindLabel() {
    return 'PDF receipt';
  }

  Uint8List _emptyBytes() => Uint8List(0);

  Uint8List _buildTestPdfBytes() {
    final objects = <String>[
      '1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n',
      '2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n',
      '3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 200] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>\nendobj\n',
      '4 0 obj\n<< /Length 46 >>\nstream\nBT /F1 16 Tf 24 100 Td (Roovia test payment proof) Tj ET\nendstream\nendobj\n',
      '5 0 obj\n<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>\nendobj\n',
    ];

    final bytes = <int>[];
    void write(String value) {
      bytes.addAll(ascii.encode(value));
    }

    write('%PDF-1.4\n');

    final offsets = <int>[];
    for (final object in objects) {
      offsets.add(bytes.length);
      write(object);
    }

    final xrefStart = bytes.length;
    write('xref\n');
    write('0 ${objects.length + 1}\n');
    write('0000000000 65535 f \n');
    for (final offset in offsets) {
      final padded = offset.toString().padLeft(10, '0');
      write('$padded 00000 n \n');
    }

    write('trailer\n');
    write('<< /Size ${objects.length + 1} /Root 1 0 R >>\n');
    write('startxref\n');
    write('$xrefStart\n');
    write('%%EOF\n');

    return Uint8List.fromList(bytes);
  }

  void _addTestPdf() {
    if (_submitting) {
      return;
    }
    if (_attachments.length >= _maxAttachmentCount) {
      setState(() => _errorText = 'You can attach at most $_maxAttachmentCount files.');
      return;
    }

    final bytes = _buildTestPdfBytes();
    setState(() {
      _attachments.add(
        PaymentProofInput(
          bytes: bytes,
          fileName: 'roovia-test-proof.pdf',
          mimeType: 'application/pdf',
          kind: 'pdf',
          sizeBytes: bytes.length,
        ),
      );
      _errorText = null;
    });
  }

  Future<void> _pickPdf() async {
    if (_submitting) {
      return;
    }

    if (_attachments.length >= _maxAttachmentCount) {
      setState(() => _errorText = 'You can attach at most $_maxAttachmentCount files.');
      return;
    }

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      withData: true,
    );

    if (result == null || result.files.isEmpty) {
      return;
    }

    final file = result.files.first;
    final bytes = file.bytes ?? _emptyBytes();
    if (bytes.isEmpty) {
      setState(() => _errorText = 'The selected PDF could not be read.');
      return;
    }
    if (bytes.length > _maxAttachmentBytes) {
      setState(() => _errorText = 'Please choose a PDF smaller than 12 MB.');
      return;
    }

    setState(() {
      _attachments.add(
        PaymentProofInput(
          bytes: bytes,
          fileName: file.name.isNotEmpty ? file.name : 'payment-proof.pdf',
          mimeType: 'application/pdf',
          kind: 'pdf',
          sizeBytes: bytes.length,
        ),
      );
      _errorText = null;
    });
  }

  void _removeAttachment(int index) {
    if (_submitting) {
      return;
    }

    setState(() {
      _attachments.removeAt(index);
      _errorText = null;
    });
  }

  Future<void> _submit() async {
    if (_submitting) {
      return;
    }

    if (_attachments.isEmpty) {
      setState(() {
        _errorText = 'Please select at least one PDF receipt before submitting.';
      });
      return;
    }

    setState(() {
      _submitting = true;
      _uploadProgress = 0;
      _errorText = null;
    });

    try {
      await _expenseService.markAsPaid(
        widget.expenseId,
        widget.participantId,
        attachments: _attachments,
        note: _noteController.text,
        onUploadProgress: (completed, total) {
          if (!mounted) {
            return;
          }
          setState(() {
            _uploadProgress = total == 0 ? 1 : completed / total;
          });
        },
      );

      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) {
        return;
      }
      final raw = error.toString();
      final normalized = raw.toLowerCase();
      final displayMessage =
          normalized.contains('permission-denied') || normalized.contains('unauthorized')
          ? 'Upload is blocked by Storage rules for this user/action. Please verify the latest storage rules are deployed.'
          : raw;
      setState(() {
        _errorText = displayMessage;
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(left: 16, right: 16, top: 12, bottom: 16 + bottomInset),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Submit payment proof',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                widget.expenseTitle,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.grey.shade700,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F8F5),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2EAE5)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Attachments',
                      style: Theme.of(
                        context,
                      ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Upload PDF receipts or invoices only. Please select at least one PDF before submitting.',
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: Colors.grey.shade700),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _submitting ? null : _pickPdf,
                          icon: const Icon(Icons.picture_as_pdf_outlined),
                          label: const Text('Add PDF'),
                        ),
                        if (kDebugMode)
                          OutlinedButton.icon(
                            onPressed: _submitting ? null : _addTestPdf,
                            icon: const Icon(Icons.science_outlined),
                            label: const Text('Use Test PDF'),
                          ),
                        TextButton.icon(
                          onPressed: _submitting || _attachments.isEmpty
                              ? null
                              : () {
                                  setState(() {
                                    _attachments.clear();
                                    _errorText = null;
                                  });
                                },
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('Clear'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    if (_attachments.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Text(
                          'No files selected yet. Please add at least one PDF to submit.',
                          style: Theme.of(
                            context,
                          ).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600),
                        ),
                      )
                    else
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          for (var index = 0; index < _attachments.length; index += 1)
                            _AttachmentPreviewCard(
                              input: _attachments[index],
                              index: index,
                              humanSize: _humanSize(_attachments[index].sizeBytes),
                              kindLabel: _fileKindLabel(),
                              onRemove: _submitting ? null : () => _removeAttachment(index),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _noteController,
                enabled: !_submitting,
                maxLines: 4,
                minLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Optional note',
                  hintText: 'Add a short message for the owner',
                  alignLabelWithHint: true,
                  prefixIcon: Icon(Icons.note_alt_outlined),
                ),
              ),
              const SizedBox(height: 16),
              if (_submitting) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: _attachments.isEmpty ? null : _uploadProgress,
                    minHeight: 8,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _attachments.isEmpty
                      ? 'Submitting payment proof...'
                      : 'Uploading ${(_uploadProgress * _attachments.length).ceil().clamp(1, _attachments.length)} / ${_attachments.length} files',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: Colors.grey.shade700),
                ),
                const SizedBox(height: 16),
              ],
              if (_errorText != null) ...[
                Text(
                  _errorText!,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.red.shade700,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
              ],
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _submitting || _attachments.isEmpty ? null : _submit,
                  child: _submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Submit payment'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AttachmentPreviewCard extends StatelessWidget {
  final PaymentProofInput input;
  final int index;
  final String humanSize;
  final String kindLabel;
  final VoidCallback? onRemove;

  const _AttachmentPreviewCard({
    required this.input,
    required this.index,
    required this.humanSize,
    required this.kindLabel,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 140,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE1E7E3)),
        boxShadow: const [
          BoxShadow(color: Color(0x0C000000), blurRadius: 10, offset: Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Container(
              height: 76,
              width: double.infinity,
              color: const Color(0xFFFDF4EA),
              child: const Center(
                child: Icon(Icons.picture_as_pdf_rounded, size: 36, color: Color(0xFFC2410C)),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            kindLabel,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            input.fileName,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            humanSize,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
          ),
          if (onRemove != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                onPressed: onRemove,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close_rounded),
                tooltip: 'Remove attachment',
              ),
            ),
          ],
        ],
      ),
    );
  }
}
