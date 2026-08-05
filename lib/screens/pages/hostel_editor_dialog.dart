import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../models/hostel.dart';
import '../../services/auth_service.dart';
import '../../services/hostel_service.dart';
import '../../widgets/selectable_chips.dart';

/// Create or edit a hostel.
///
/// On create it also collects the room-generation plan (floors x rooms per
/// floor, plus optional extra seater types) and writes every room. On edit
/// that section is hidden, because the rooms already exist — use "Add floor"
/// or the room editor to change them.
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

  // The main room type: floors x rooms/floor x capacity, exactly as before.
  final _floors = TextEditingController(text: '4');
  final _roomsPerFloor = TextEditingController(text: '25');
  int _capacity = 2;

  /// Extra seater types beyond the main one — e.g. a hostel that's mostly
  /// 2-seaters but has a block of singles too. Each gets its own whole
  /// floors, picking up right after the previous type's floors, so the
  /// building comes out divided by seater type without anyone having to
  /// plan floor numbers by hand.
  final List<_ExtraTypeDraft> _extraTypes = [];

  late HostelGender _gender;
  late Set<String> _amenities;
  Set<String> _roomFeatures = {'Ceiling Fan', 'Study Table'};

  bool _busy = false;
  String? _error;

  /// When editing, the room-plan fields are hidden behind this — set once
  /// the admin explicitly opts into replacing the existing room layout.
  bool _regenerateRooms = false;

  bool get _isEditing => widget.hostel != null;

  /// Whether the room-plan fields below should currently be shown and
  /// included in [_save].
  bool get _showRoomPlan => !_isEditing || _regenerateRooms;

  @override
  void initState() {
    super.initState();
    final h = widget.hostel;
    _name = TextEditingController(text: h?.name ?? '');
    _code = TextEditingController(text: h?.code ?? '');
    _address = TextEditingController(text: h?.address ?? '');
    _gender = h?.gender ?? HostelGender.boys;
    _amenities = {...?h?.amenities};
  }

  @override
  void dispose() {
    for (final c in [_name, _code, _address, _floors, _roomsPerFloor]) {
      c.dispose();
    }
    for (final t in _extraTypes) {
      t.dispose();
    }
    super.dispose();
  }

  /// Room types = the main one plus every extra row.
  int get _roomTypeCount => 1 + _extraTypes.length;

  void _setRoomTypeCount(int n) => setState(() {
    final target = n.clamp(1, 6);
    while (_extraTypes.length + 1 < target) {
      // Pick a capacity not already used, so the new row isn't a duplicate
      // of one already on screen — the whole point of adding a type.
      final used = {_capacity, ..._extraTypes.map((t) => t.capacity)};
      final next = [1, 2, 3, 4, 5, 6].firstWhere(
        (c) => !used.contains(c),
        orElse: () => 1,
      );
      _extraTypes.add(
        _ExtraTypeDraft(totalRooms: '25', capacity: next),
      );
    }
    while (_extraTypes.length + 1 > target) {
      _extraTypes.removeLast().dispose();
    }
  });

  RoomPlan get _plan {
    final perFloor = int.tryParse(_roomsPerFloor.text) ?? 0;
    final floors = int.tryParse(_floors.text) ?? 0;
    final features = _roomFeatures.toList();
    return RoomPlan(
      blocks: [
        RoomBlock(
          capacity: _capacity,
          totalRooms: floors * perFloor,
          roomsPerFloor: perFloor,
          features: features,
        ),
        for (final t in _extraTypes)
          RoomBlock(
            capacity: t.capacity,
            totalRooms: int.tryParse(t.totalRooms.text) ?? 0,
            roomsPerFloor: perFloor,
            features: features,
          ),
      ],
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final plan = _plan;
    if (_showRoomPlan && plan.totalRooms > 2000) {
      setState(
        () => _error =
            'That would create ${plan.totalRooms} rooms. Cap it at 2000 — '
            'split very large blocks into separate hostels instead.',
      );
      return;
    }

    final messenger = ScaffoldMessenger.of(context);

    if (_regenerateRooms) {
      final confirmed = await _confirmRegenerate(context, plan);
      if (confirmed != true || !mounted) return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

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
        if (_regenerateRooms) {
          await HostelService.instance.regenerateRooms(
            collegeId: widget.collegeId,
            hostelId: widget.hostel!.id,
            plan: plan,
          );
        }
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
            _regenerateRooms
                ? 'Hostel updated and rooms regenerated '
                      '(${plan.totalRooms} rooms)'
                : _isEditing
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

  Future<bool?> _confirmRegenerate(BuildContext context, RoomPlan plan) {
    return showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Replace all rooms?'),
        content: Text(
          'Every existing room in ${widget.hostel!.name} will be deleted '
          'and replaced with ${plan.totalRooms} new rooms (${plan.rangeSummary}). '
          'This cannot be undone. Rooms that currently have a student in '
          'them will block this instead of being deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Replace rooms'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final plan = _plan;

    return AlertDialog(
      title: Text(_isEditing ? 'Edit ${widget.hostel!.name}' : 'Add a hostel'),
      content: SizedBox(
        width: 600,
        height: 600,
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

                const SizedBox(height: 24),
                const Divider(),
                const SizedBox(height: 14),
                const Text(
                  'Rooms',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),

                if (_isEditing && !_regenerateRooms) ...[
                  Text(
                    'Rooms already exist for this hostel — use "Add room", '
                    '"Add floor" or tap a room to edit it individually. If '
                    'the whole layout was wrong from the start, you can '
                    'replace every room here instead of deleting the hostel.',
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12.5,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _busy
                        ? null
                        : () => setState(() => _regenerateRooms = true),
                    icon: const Icon(Icons.restart_alt_rounded, size: 17),
                    label: const Text('Regenerate rooms…'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.danger,
                      side: BorderSide(color: AppColors.danger),
                    ),
                  ),
                ],

                if (_showRoomPlan) ...[
                  if (_isEditing) ...[
                    const SizedBox(height: 4),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.dangerSoft,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.warning_amber_rounded,
                            size: 18,
                            color: AppColors.danger,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'This deletes every existing room in this '
                              'hostel and creates new ones from the layout '
                              'below. Blocked if any room currently has a '
                              'student in it.',
                              style: TextStyle(
                                color: AppColors.danger,
                                fontSize: 12.5,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: _busy
                            ? null
                            : () => setState(() => _regenerateRooms = false),
                        child: const Text('Cancel — keep existing rooms'),
                      ),
                    ),
                  ] else
                    Text(
                      'Describe the layout and every room is created for '
                      'you. You can add, edit or remove individual rooms '
                      'afterwards.',
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12.5,
                        height: 1.4,
                      ),
                    ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _floors,
                          enabled: !_busy,
                          keyboardType: TextInputType.number,
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(
                            labelText: 'Floors',
                          ),
                          validator: (v) {
                            final n = int.tryParse(v ?? '');
                            if (n == null || n < 1) return 'Min 1';
                            if (n > 20) return 'Max 20';
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _roomsPerFloor,
                          enabled: !_busy,
                          keyboardType: TextInputType.number,
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(
                            labelText: 'Rooms per floor',
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
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          initialValue: _capacity,
                          decoration: const InputDecoration(
                            labelText: 'Capacity',
                          ),
                          items: const [1, 2, 3, 4, 5, 6]
                              .map(
                                (n) => DropdownMenuItem(
                                  value: n,
                                  child: Text(
                                    n == 1 ? 'Single' : '$n seater',
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: _busy
                              ? null
                              : (v) => setState(() => _capacity = v ?? 2),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),

                  // Most hostels have one room type and stop here. This is
                  // for the building that doesn't — a wing of 3-seaters and
                  // a wing of singles, say.
                  Row(
                    children: [
                      Text(
                        'Room types',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 10),
                      IconButton(
                        onPressed: (_busy || _roomTypeCount <= 1)
                            ? null
                            : () => _setRoomTypeCount(_roomTypeCount - 1),
                        icon: const Icon(Icons.remove_circle_outline, size: 20),
                        visualDensity: VisualDensity.compact,
                      ),
                      Text(
                        '$_roomTypeCount',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      IconButton(
                        onPressed: (_busy || _roomTypeCount >= 6)
                            ? null
                            : () => _setRoomTypeCount(_roomTypeCount + 1),
                        icon: const Icon(Icons.add_circle_outline, size: 20),
                        visualDensity: VisualDensity.compact,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          'More than one if this building has different '
                          'seater types — each gets its own floors.',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                  for (var i = 0; i < _extraTypes.length; i++) ...[
                    const SizedBox(height: 10),
                    _ExtraTypeRow(
                      draft: _extraTypes[i],
                      enabled: !_busy,
                      onChanged: () => setState(() {}),
                    ),
                  ],

                  const SizedBox(height: 18),
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
                          plan.rangeSummary,
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

/// Editing state for one extra room type: how many rooms, and what capacity.
/// Rooms per floor is shared with the main type above, so this row is just
/// two fields.
class _ExtraTypeDraft {
  final TextEditingController totalRooms;
  int capacity;

  _ExtraTypeDraft({required String totalRooms, required this.capacity})
    : totalRooms = TextEditingController(text: totalRooms);

  void dispose() => totalRooms.dispose();
}

class _ExtraTypeRow extends StatelessWidget {
  final _ExtraTypeDraft draft;
  final bool enabled;
  final VoidCallback onChanged;

  const _ExtraTypeRow({
    required this.draft,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: TextFormField(
          controller: draft.totalRooms,
          enabled: enabled,
          keyboardType: TextInputType.number,
          onChanged: (_) => onChanged(),
          decoration: const InputDecoration(
            labelText: 'Number of rooms',
            isDense: true,
          ),
          validator: (v) {
            final n = int.tryParse(v ?? '');
            if (n == null || n < 1) return 'Min 1';
            if (n > 999) return 'Max 999';
            return null;
          },
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
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
    ],
  );
}
