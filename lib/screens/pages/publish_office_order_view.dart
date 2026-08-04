import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/session.dart';
import '../../core/theme.dart';
import '../../services/auth_service.dart';
import '../../services/office_order_service.dart';

/// Largest photo accepted, in bytes. Base64 adds ~33% on top of this, and a
/// Firestore document tops out around 1 MB, so this leaves headroom for the
/// other fields on the order.
const int _maxImageBytes = 700 * 1024;

/// Form for staff to add an office order to the register.
///
/// The photo is stored inline in the document — see [OfficeOrder].
class PublishOfficeOrderView extends StatefulWidget {
  final VoidCallback onBack;
  final VoidCallback onDone;

  const PublishOfficeOrderView({
    super.key,
    required this.onBack,
    required this.onDone,
  });

  @override
  State<PublishOfficeOrderView> createState() =>
      _PublishOfficeOrderViewState();
}

class _PublishOfficeOrderViewState extends State<PublishOfficeOrderView> {
  final _formKey = GlobalKey<FormState>();
  final _orderNo = TextEditingController();
  final _title = TextEditingController();
  final _description = TextEditingController();

  DateTime _orderDate = DateTime.now();
  bool _busy = false;
  String? _error;

  Uint8List? _imageBytes;
  String? _imageMimeType;
  String? _imageName;

  @override
  void dispose() {
    _orderNo.dispose();
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  static const _mimeByExt = {
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'webp': 'image/webp',
  };

  Future<void> _pickImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
      withData: true,
    );
    final file = result?.files.single;
    if (file == null || file.bytes == null) return;

    if (file.bytes!.lengthInBytes > _maxImageBytes) {
      setState(() {
        _error = 'That photo is too large '
            '(${(file.bytes!.lengthInBytes / 1024).round()} KB). Please '
            'keep it under ${_maxImageBytes ~/ 1024} KB — a phone camera '
            'shot usually compresses well below that.';
      });
      return;
    }

    final ext = file.extension?.toLowerCase() ?? '';
    setState(() {
      _error = null;
      _imageBytes = file.bytes;
      _imageMimeType = _mimeByExt[ext] ?? 'image/jpeg';
      _imageName = file.name;
    });
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _orderDate,
      firstDate: DateTime(now.year - 15),
      lastDate: DateTime(now.year + 1, 12, 31),
    );
    if (picked == null) return;
    setState(() => _orderDate = picked);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_imageBytes == null) {
      setState(() => _error = 'Add a photo of the order before submitting');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    final session = Session.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await OfficeOrderService.instance.publish(
        collegeId: session.user.collegeId,
        author: session.user,
        orderNo: _orderNo.text,
        title: _title.text,
        imageBytes: _imageBytes!,
        imageMimeType: _imageMimeType!,
        description: _description.text,
        orderDate: _orderDate,
      );
      messenger.showSnackBar(
        const SnackBar(content: Text('Office order added')),
      );
      widget.onDone();
    } catch (e) {
      if (mounted) setState(() => _error = AuthService.describeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 760),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppCard(
              child: Row(
                children: [
                  IconButton(
                    onPressed: _busy ? null : widget.onBack,
                    icon: const Icon(Icons.arrow_back_rounded),
                    tooltip: 'Back to office orders',
                  ),
                  const SizedBox(width: 4),
                  const Expanded(
                    child: Text(
                      'Add an office order',
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            if (_error != null) ...[
              AppCard(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Icon(
                      Icons.error_outline_rounded,
                      color: AppColors.danger,
                      size: 19,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: AppColors.danger,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
            ],
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _orderNo,
                          enabled: !_busy,
                          decoration: const InputDecoration(
                            labelText: 'Office order number',
                            hintText: 'SLIET/HM/2026/17',
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Order number is required'
                              : null,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: InkWell(
                          onTap: _busy ? null : _pickDate,
                          borderRadius: BorderRadius.circular(10),
                          child: InputDecorator(
                            decoration: const InputDecoration(
                              labelText: 'Order date',
                              suffixIcon: Icon(
                                Icons.calendar_today_rounded,
                                size: 17,
                              ),
                            ),
                            child: Text(
                              '${_orderDate.day} '
                              '${months[_orderDate.month - 1]} '
                              '${_orderDate.year}',
                              style: const TextStyle(fontSize: 14),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  TextFormField(
                    controller: _title,
                    enabled: !_busy,
                    decoration: const InputDecoration(
                      labelText: 'Subject',
                      hintText: 'e.g., Revised mess timings for winter session',
                    ),
                    validator: (v) => (v == null || v.trim().length < 3)
                        ? 'Subject is required (at least 3 characters)'
                        : null,
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Photo of the order',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_imageBytes != null)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.memory(
                            _imageBytes!,
                            height: 120,
                            width: 120,
                            fit: BoxFit.cover,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _imageName ?? 'Photo selected',
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                '${(_imageBytes!.lengthInBytes / 1024).round()} KB',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: AppColors.textMuted,
                                ),
                              ),
                              const SizedBox(height: 8),
                              OutlinedButton.icon(
                                onPressed: _busy ? null : _pickImage,
                                icon: const Icon(
                                  Icons.image_outlined,
                                  size: 16,
                                ),
                                label: const Text('Choose a different photo'),
                              ),
                            ],
                          ),
                        ),
                      ],
                    )
                  else
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _pickImage,
                      icon: const Icon(Icons.add_photo_alternate_outlined),
                      label: const Text('Choose a photo (JPG/PNG, under 700 KB)'),
                    ),
                  const SizedBox(height: 18),
                  TextFormField(
                    controller: _description,
                    enabled: !_busy,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Summary (optional)',
                      alignLabelWithHint: true,
                      hintText: 'A line or two on what the order says, so '
                          'people can find it without opening the PDF.',
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: _busy ? null : widget.onBack,
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: _busy ? null : _submit,
                        child: _busy
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('Add order'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
