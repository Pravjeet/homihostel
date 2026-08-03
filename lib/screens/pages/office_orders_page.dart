import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/permissions.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../models/office_order.dart';
import '../../services/auth_service.dart';
import '../../services/office_order_service.dart';
import 'publish_office_order_view.dart';

/// Office orders: the register of orders issued by the institute.
///
/// Everyone with `officeOrders.view` can search and open them; staff with
/// `officeOrders.manage` can publish new ones. Two searches are offered
/// because they answer different questions — "find order SLIET/HM/2024/17"
/// and "what was issued on 12 March".
class OfficeOrdersPage extends StatefulWidget {
  const OfficeOrdersPage({super.key});

  @override
  State<OfficeOrdersPage> createState() => _OfficeOrdersPageState();
}

class _OfficeOrdersPageState extends State<OfficeOrdersPage> {
  bool _publishing = false;
  String _query = '';
  DateTime? _onDate;

  Future<void> _open(String url) async {
    final messenger = ScaffoldMessenger.of(context);
    final uri = Uri.tryParse(url);
    if (uri == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('That order has no usable link')),
      );
      return;
    }
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not open that link')),
      );
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _onDate ?? now,
      firstDate: DateTime(now.year - 15),
      lastDate: DateTime(now.year + 1, 12, 31),
    );
    if (picked == null) return;
    setState(() => _onDate = picked);
  }

  Future<void> _confirmDelete(String collegeId, OfficeOrder order) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete this office order?'),
        content: Text(
          '${order.orderNo.isEmpty ? order.title : order.orderNo} will be '
          'removed from the register. The PDF itself is not affected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Keep it'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await OfficeOrderService.instance.delete(
        collegeId: collegeId,
        orderId: order.id,
      );
      messenger.showSnackBar(
        const SnackBar(content: Text('Office order deleted')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(AuthService.describeError(e))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = Session.of(context);
    final collegeId = session.user.collegeId;
    final canManage = session.can(Perm.officeOrdersManage);

    if (_publishing) {
      return PublishOfficeOrderView(
        onBack: () => setState(() => _publishing = false),
        onDone: () => setState(() => _publishing = false),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionHeader(
                'Office Orders',
                trailing: canManage
                    ? ElevatedButton.icon(
                        onPressed: () => setState(() => _publishing = true),
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('Add office order'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 14,
                          ),
                        ),
                      )
                    : null,
              ),
              const SizedBox(height: 4),
              const Text(
                'Orders issued by the institute. Search by order number or '
                'by the date printed on the order.',
                style: TextStyle(fontSize: 13, color: AppColors.textMuted),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      onChanged: (v) => setState(() => _query = v),
                      decoration: const InputDecoration(
                        hintText: 'Search by office order number or title',
                        prefixIcon: Icon(Icons.search_rounded),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  OutlinedButton.icon(
                    onPressed: _pickDate,
                    icon: const Icon(Icons.calendar_today_rounded, size: 16),
                    label: Text(
                      _onDate == null
                          ? 'Any date'
                          : _labelFor(_onDate!),
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 16,
                      ),
                    ),
                  ),
                  if (_onDate != null) ...[
                    const SizedBox(width: 6),
                    IconButton(
                      onPressed: () => setState(() => _onDate = null),
                      icon: const Icon(Icons.close_rounded, size: 18),
                      tooltip: 'Clear date filter',
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        StreamBuilder<List<OfficeOrder>>(
          stream: OfficeOrderService.instance.watchAll(collegeId),
          builder: (context, snap) {
            if (snap.hasError) {
              return AppCard(
                child: Text(AuthService.describeError(snap.error!)),
              );
            }
            if (!snap.hasData) {
              return const Padding(
                padding: EdgeInsets.all(60),
                child: Center(child: CircularProgressIndicator()),
              );
            }

            final shown = snap.data!
                .where((o) => o.matches(_query))
                .where((o) => _onDate == null || o.isOn(_onDate!))
                .toList();

            if (shown.isEmpty) {
              return AppCard(
                padding: const EdgeInsets.symmetric(vertical: 54),
                child: Center(
                  child: Text(
                    (_query.isEmpty && _onDate == null)
                        ? 'No office orders have been added yet.'
                        : 'Nothing matches that search.',
                    style: const TextStyle(color: AppColors.textMuted),
                  ),
                ),
              );
            }

            return AppCard(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                children: [
                  for (var i = 0; i < shown.length; i++) ...[
                    _OrderRow(
                      order: shown[i],
                      canDelete:
                          session.user.isSuperAdmin ||
                          (canManage &&
                              shown[i].postedByUid == session.user.uid),
                      onOpen: () => _open(shown[i].pdfUrl),
                      onDelete: () => _confirmDelete(collegeId, shown[i]),
                    ),
                    if (i != shown.length - 1)
                      const Divider(
                        height: 1,
                        indent: 20,
                        endIndent: 20,
                        color: AppColors.border,
                      ),
                  ],
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

String _labelFor(DateTime d) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${d.day} ${months[d.month - 1]} ${d.year}';
}

class _OrderRow extends StatelessWidget {
  final OfficeOrder order;
  final bool canDelete;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  const _OrderRow({
    required this.order,
    required this.canDelete,
    required this.onOpen,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Container(
              height: 42,
              width: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.primarySoft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.picture_as_pdf_rounded,
                size: 20,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    order.title.isEmpty ? order.orderNo : order.title,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    [
                      if (order.orderNo.isNotEmpty) order.orderNo,
                      if (order.dateLabel != null) order.dateLabel!,
                      order.postedByName,
                    ].join(' · '),
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.textMuted,
                    ),
                  ),
                  if (order.description != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      order.description!,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textStrong,
                        height: 1.45,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            TextButton.icon(
              onPressed: onOpen,
              icon: const Icon(Icons.open_in_new_rounded, size: 16),
              label: const Text('Open'),
            ),
            if (canDelete)
              PopupMenuButton<String>(
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(
                          Icons.delete_outline_rounded,
                          size: 18,
                          color: AppColors.danger,
                        ),
                        SizedBox(width: 10),
                        Text(
                          'Delete',
                          style: TextStyle(color: AppColors.danger),
                        ),
                      ],
                    ),
                  ),
                ],
                onSelected: (v) {
                  if (v == 'delete') onDelete();
                },
                child: const Icon(Icons.more_vert_rounded, size: 20),
              ),
          ],
        ),
      ),
    );
  }
}
