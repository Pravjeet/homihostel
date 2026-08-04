import 'package:flutter/material.dart';

import '../../core/session.dart';
import '../../core/theme.dart';
import '../../services/auth_service.dart';
import '../../services/office_order_service.dart';

/// Form for staff to add an office order to the register.
///
/// The PDF is referenced by link rather than uploaded — see [OfficeOrder].
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
  final _pdfUrl = TextEditingController();
  final _description = TextEditingController();

  DateTime _orderDate = DateTime.now();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _orderNo.dispose();
    _title.dispose();
    _pdfUrl.dispose();
    _description.dispose();
    super.dispose();
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
        pdfUrl: _pdfUrl.text,
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
                  TextFormField(
                    controller: _pdfUrl,
                    enabled: !_busy,
                    decoration: const InputDecoration(
                      labelText: 'PDF link',
                      hintText: 'https://…',
                      helperText: 'Paste the shareable link to the signed PDF',
                    ),
                    validator: (v) {
                      final t = v?.trim() ?? '';
                      if (t.isEmpty) return 'A link to the PDF is required';
                      final uri = Uri.tryParse(t);
                      if (uri == null ||
                          !uri.hasScheme ||
                          !(uri.isScheme('http') || uri.isScheme('https'))) {
                        return 'Enter a full link starting with https://';
                      }
                      return null;
                    },
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
