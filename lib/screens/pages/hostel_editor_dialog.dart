import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../models/hostel.dart';
import '../../services/auth_service.dart';
import '../../services/hostel_service.dart';
import '../../widgets/selectable_chips.dart';

/// Create or edit a hostel.
///
/// On create it also collects the room-generation plan (floors x rooms per
/// floor) and writes every room. On edit that section is hidden, because the
/// rooms already exist — use "Add floor" or the room editor to change them.
class HostelEditorDialog extends StatefulWidget {
  final String collegeId;

  /// Null when creating. When editing, the room generator is hidden — rooms
  /// already exist and are managed from the hostel's own page.
  final Hostel? hostel;

  const HostelEditorDialog({super.key, required this.collegeId, this.hostel});

  @override
  State<HostelEditorDialog> createState() => HostelEditorDialogState();
}

class HostelEditorDialogState extends State<HostelEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _code;
  late final TextEditingController _address;

  /// One row per [RoomBlock] — a span of floors sharing a room count and
  /// capacity. Starts as a single block matching the old defaults, so a
  /// uniform hostel is still just one row; a mixed building (different
  /// capacities, or a floor laid out differently) is more rows.
  final List<_BlockDraft> _blocks = [];

  late HostelGender _gender;
  late Set<String> _amenities;
  Set<String> _roomFeatures = {'Ceiling Fan', 'Study Table'};

  bool _busy = false;
  String? _error;

  bool get _isEditing => widget.hostel != null;

  @override
  void initState() {
    super.initState();
    final h = widget.hostel;
    _name = TextEditingController(text: h?.name ?? '');
    _code = TextEditingController(text: h?.code ?? '');
    _address = TextEditingController(text: h?.address ?? '');
    _gender = h?.gender ?? HostelGender.boys;
    _amenities = {...?h?.amenities};
    if (!_isEditing) {
      _blocks.add(
        _BlockDraft(fromFloor: 1, toFloor: 4, roomsPerFloor: 25, capacity: 2),
      );
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _code, _address]) {
      c.dispose();
    }
    for (final b in _blocks) {
      b.dispose();
    }
    super.dispose();
  }

  void _addBlock() => setState(() {
    final lastTo = _blocks.isEmpty
        ? 0
        : (int.tryParse(_blocks.last.toFloor.text) ?? 0);
    _blocks.add(
      _BlockDraft(
        fromFloor: lastTo + 1,
        toFloor: lastTo + 1,
        roomsPerFloor: 25,
        capacity: 2,
      ),
    );
  });

  void _removeBlock(int i) => setState(() {
    _blocks.removeAt(i).dispose();
  });

  RoomPlan get _plan => RoomPlan(
    blocks: _blocks
        .map(
          (d) => RoomBlock(
            fromFloor: int.tryParse(d.fromFloor.text) ?? 0,
            toFloor: int.tryParse(d.toFloor.text) ?? 0,
            roomsPerFloor: int.tryParse(d.roomsPerFloor.text) ?? 0,
            capacity: d.capacity,
            features: _roomFeatures.toList(),
          ),
        )
        .toList(),
  );

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final plan = _plan;
    if (!_isEditing && plan.totalRooms > 2000) {
      setState(
        () => _error =
            'That would create ${plan.totalRooms} rooms. Cap it at 2000 — '
            'split very large blocks into separate hostels instead.',
      );
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    final messenger = ScaffoldMessenger.of(context);
    try {
      if (_isEditing) {
        await HostelService.instance.updateHostel(
          widget.collegeId,
          widget.hostel!.copyWith(
            name: _name.text.trim(),
            code: _code.text.trim().toUpperCase(),
            gender: _gender,
            amenities: _amenities.toList(),
            address: _address.text.trim(),
          ),
        );
      } else {
        await HostelService.instance.createHostel(
          collegeId: widget.collegeId,
          hostel: Hostel(
            id: '',
            name: _name.text.trim(),
            code: _code.text.trim().toUpperCase(),
            gender: _gender,
            floors: plan.floors,
            amenities: _amenities.toList(),
            address: _address.text.trim(),
          ),
          plan: plan,
        );
      }
      if (mounted) Navigator.pop(context);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            _isEditing
                ? 'Hostel updated'
                : 'Created ${_name.text.trim()} with ${plan.totalRooms} rooms',
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _error = AuthService.describeError(e));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final plan = _plan;

    return AlertDialog(
      title: Text(_isEditing ? 'Edit ${widget.hostel!.name}' : 'Add a hostel'),
      content: SizedBox(
        width: 660,
        height: 620,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_error != null) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.dangerSoft,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: AppColors.danger,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextFormField(
                        controller: _name,
                        enabled: !_busy,
                        decoration: const InputDecoration(
                          labelText: 'Hostel name',
                          hintText: 'e.g. Aryabhatta Hostel / Block A',
                        ),
                        validator: (v) => (v == null || v.trim().length < 2)
                            ? 'Name is required'
                            : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _code,
                        enabled: !_busy,
                        textCapitalization: TextCapitalization.characters,
                        maxLength: 12,
                        decoration: const InputDecoration(
                          labelText: 'Code',
                          hintText: 'BH-01',
                          helperText: 'Used by the CSV importer to match rows',
                          counterText: '',
                        ),
                        validator: (v) {
                          final s = v?.trim() ?? '';
                          if (s.isEmpty) return 'Required';
                          if (s.length > 12) return 'Keep it under 12 chars';
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                DropdownButtonFormField<HostelGender>(
                  initialValue: _gender,
                  decoration: const InputDecoration(labelText: 'Accommodates'),
                  items: HostelGender.values
                      .map(
                        (g) => DropdownMenuItem(
                          value: g,
                          child: Text(g.label),
                        ),
                      )
                      .toList(),
                  onChanged: _busy
                      ? null
                      : (v) => setState(
                          () => _gender = v ?? HostelGender.coed,
                        ),
                ),
                const SizedBox(height: 14),

                TextFormField(
                  controller: _address,
                  enabled: !_busy,
                  decoration: const InputDecoration(
                    labelText: 'Location / address (optional)',
                  ),
                ),
                const SizedBox(height: 22),

                const Text(
                  'Things provided in this hostel',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                SelectableChips(
                  options: kHostelAmenities,
                  selected: _amenities,
                  enabled: !_busy,
                  onChanged: (v) => setState(() => _amenities = v),
                ),

                if (!_isEditing) ...[
                  const SizedBox(height: 24),
                  const Divider(),
                  const SizedBox(height: 14),
                  const Text(
                    'Rooms',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Each row is a span of floors sharing the same room count '
                    'and capacity. Add another row for a floor laid out '
                    'differently, or to mix room sizes in the same building — '
                    'e.g. 60 three-seaters and 61 singles.',
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12.5,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 14),
                  for (var i = 0; i < _blocks.length; i++) ...[
                    _RoomBlockRow(
                      draft: _blocks[i],
                      enabled: !_busy,
                      canRemove: _blocks.length > 1,
                      onChanged: () => setState(() {}),
                      onRemove: () => _removeBlock(i),
                    ),
                    const SizedBox(height: 10),
                  ],
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _busy ? null : _addBlock,
                      icon: const Icon(Icons.add_rounded, size: 17),
                      label: const Text('Add a row for another floor layout'),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Default room features',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SelectableChips(
                    options: kRoomFeatures,
                    selected: _roomFeatures,
                    enabled: !_busy,
                    onChanged: (v) => setState(() => _roomFeatures = v),
                  ),
                  const SizedBox(height: 18),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.primarySoft,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Will create ${plan.totalRooms} rooms · '
                          '${plan.totalBeds} beds',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13.5,
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Numbered ${plan.rangeSummary}',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: _busy
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: Colors.white,
                  ),
                )
              : Text(_isEditing ? 'Save changes' : 'Create hostel'),
        ),
      ],
    );
  }
}

/// Mutable editing state for one [RoomBlock] row. A plain holder rather than
/// an immutable value so each row keeps its own [TextEditingController]s —
/// rebuilding them on every keystroke would drop focus and cursor position.
class _BlockDraft {
  final TextEditingController fromFloor;
  final TextEditingController toFloor;
  final TextEditingController roomsPerFloor;
  int capacity;

  _BlockDraft({
    required int fromFloor,
    required int toFloor,
    required int roomsPerFloor,
    required this.capacity,
  }) : fromFloor = TextEditingController(text: '$fromFloor'),
       toFloor = TextEditingController(text: '$toFloor'),
       roomsPerFloor = TextEditingController(text: '$roomsPerFloor');

  void dispose() {
    fromFloor.dispose();
    toFloor.dispose();
    roomsPerFloor.dispose();
  }
}

class _RoomBlockRow extends StatelessWidget {
  final _BlockDraft draft;
  final bool enabled;
  final bool canRemove;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  const _RoomBlockRow({
    required this.draft,
    required this.enabled,
    required this.canRemove,
    required this.onChanged,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppColors.canvas,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: AppColors.border),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 70,
          child: TextFormField(
            controller: draft.fromFloor,
            enabled: enabled,
            keyboardType: TextInputType.number,
            onChanged: (_) => onChanged(),
            decoration: const InputDecoration(
              labelText: 'From floor',
              isDense: true,
            ),
            validator: (v) {
              final n = int.tryParse(v ?? '');
              if (n == null || n < 1) return 'Min 1';
              if (n > 20) return 'Max 20';
              return null;
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 16, left: 8, right: 8),
          child: Text('to', style: TextStyle(color: AppColors.textMuted)),
        ),
        SizedBox(
          width: 70,
          child: TextFormField(
            controller: draft.toFloor,
            enabled: enabled,
            keyboardType: TextInputType.number,
            onChanged: (_) => onChanged(),
            decoration: const InputDecoration(
              labelText: 'To floor',
              isDense: true,
            ),
            validator: (v) {
              final n = int.tryParse(v ?? '');
              final from = int.tryParse(draft.fromFloor.text);
              if (n == null || n < 1) return 'Min 1';
              if (n > 20) return 'Max 20';
              if (from != null && n < from) return '< from';
              return null;
            },
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 110,
          child: TextFormField(
            controller: draft.roomsPerFloor,
            enabled: enabled,
            keyboardType: TextInputType.number,
            onChanged: (_) => onChanged(),
            decoration: const InputDecoration(
              labelText: 'Rooms / floor',
              isDense: true,
            ),
            validator: (v) {
              final n = int.tryParse(v ?? '');
              if (n == null || n < 1) return 'Min 1';
              if (n > 99) return 'Max 99';
              return null;
            },
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 120,
          child: DropdownButtonFormField<int>(
            initialValue: draft.capacity,
            decoration: const InputDecoration(
              labelText: 'Capacity',
              isDense: true,
            ),
            items: const [1, 2, 3, 4, 5, 6]
                .map(
                  (n) => DropdownMenuItem(
                    value: n,
                    child: Text(n == 1 ? 'Single' : '$n seater'),
                  ),
                )
                .toList(),
            onChanged: enabled
                ? (v) {
                    draft.capacity = v ?? draft.capacity;
                    onChanged();
                  }
                : null,
          ),
        ),
        const Spacer(),
        IconButton(
          onPressed: enabled && canRemove ? onRemove : null,
          icon: const Icon(Icons.close_rounded, size: 18),
          tooltip: 'Remove this row',
        ),
      ],
    ),
  );
}
