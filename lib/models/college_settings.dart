import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'fine.dart';

/// Everything an admin can configure about their workspace.
///
/// One document — `colleges/{collegeId}/settings/config` — rather than a
/// collection, because there is exactly one of each of these at any time.
/// Same reasoning as the mess module's `menu` and `config` docs.
///
/// Every field has a working default, so a workspace that has never opened
/// this screen behaves identically to one that has.
class CollegeSettings {
  final InstitutionProfile institution;
  final AppTheming theming;
  final AcademicSession session;

  /// Overrides [kFineCategories]. Empty means "use the built-in list".
  final List<FineCategory> fineCategories;

  final DateTime? updatedAt;
  final String? updatedByName;

  const CollegeSettings({
    this.institution = const InstitutionProfile(),
    this.theming = const AppTheming(),
    this.session = const AcademicSession(),
    this.fineCategories = const [],
    this.updatedAt,
    this.updatedByName,
  });

  factory CollegeSettings.fromMap(Map<String, dynamic> m) => CollegeSettings(
    institution: InstitutionProfile.fromMap(
      (m['institution'] as Map?)?.cast<String, dynamic>() ?? const {},
    ),
    theming: AppTheming.fromMap(
      (m['theming'] as Map?)?.cast<String, dynamic>() ?? const {},
    ),
    session: AcademicSession.fromMap(
      (m['session'] as Map?)?.cast<String, dynamic>() ?? const {},
    ),
    fineCategories: ((m['fineCategories'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => FineCategory.fromMap(e.cast<String, dynamic>()))
        .toList(),
    updatedAt: (m['updatedAt'] as Timestamp?)?.toDate(),
    updatedByName: m['updatedByName'] as String?,
  );

  Map<String, dynamic> toMap() => {
    'institution': institution.toMap(),
    'theming': theming.toMap(),
    'session': session.toMap(),
    'fineCategories': fineCategories.map((c) => c.toMap()).toList(),
  };

  /// The category names the impose-fine form should offer. Falls back to the
  /// built-in list so the form is never empty.
  List<String> get categoryNames => fineCategories.isEmpty
      ? kFineCategories
      : fineCategories.map((c) => c.name).toList();

  num? defaultAmountFor(String category) {
    for (final c in fineCategories) {
      if (c.name == category) return c.defaultAmount;
    }
    return null;
  }

  CollegeSettings copyWith({
    InstitutionProfile? institution,
    AppTheming? theming,
    AcademicSession? session,
    List<FineCategory>? fineCategories,
  }) => CollegeSettings(
    institution: institution ?? this.institution,
    theming: theming ?? this.theming,
    session: session ?? this.session,
    fineCategories: fineCategories ?? this.fineCategories,
    updatedAt: updatedAt,
    updatedByName: updatedByName,
  );
}

// =====================================================================
// Institution
// =====================================================================

class InstitutionProfile {
  final String? shortName;
  final String? address;
  final String? contactEmail;
  final String? contactPhone;
  final String? website;

  /// Line printed under the title on the fines dashboard and reports.
  final String? tagline;

  const InstitutionProfile({
    this.shortName,
    this.address,
    this.contactEmail,
    this.contactPhone,
    this.website,
    this.tagline,
  });

  factory InstitutionProfile.fromMap(Map<String, dynamic> m) =>
      InstitutionProfile(
        shortName: m['shortName'] as String?,
        address: m['address'] as String?,
        contactEmail: m['contactEmail'] as String?,
        contactPhone: m['contactPhone'] as String?,
        website: m['website'] as String?,
        tagline: m['tagline'] as String?,
      );

  Map<String, dynamic> toMap() => {
    'shortName': shortName,
    'address': address,
    'contactEmail': contactEmail,
    'contactPhone': contactPhone,
    'website': website,
    'tagline': tagline,
  };
}

// =====================================================================
// Theming
// =====================================================================

/// A named accent colour.
///
/// Presets rather than a free colour picker on purpose: an arbitrary hex lets
/// someone choose a yellow that makes white button text unreadable. Each of
/// these is dark enough to carry white text at the contrast ratio the rest of
/// the app assumes.
class ThemePreset {
  final String id;
  final String label;
  final Color color;
  const ThemePreset(this.id, this.label, this.color);
}

const List<ThemePreset> kThemePresets = [
  ThemePreset('indigo', 'Indigo', Color(0xFF4F46E5)),
  ThemePreset('violet', 'Violet', Color(0xFF7C3AED)),
  ThemePreset('blue', 'Blue', Color(0xFF2563EB)),
  ThemePreset('teal', 'Teal', Color(0xFF0D9488)),
  ThemePreset('emerald', 'Emerald', Color(0xFF059669)),
  ThemePreset('rose', 'Rose', Color(0xFFE11D48)),
  ThemePreset('amber', 'Amber', Color(0xFFB45309)),
  ThemePreset('slate', 'Slate', Color(0xFF334155)),
];

/// Light, dark, or follow the device.
enum AppBrightness { light, dark, system }

extension AppBrightnessX on AppBrightness {
  String get label => switch (this) {
    AppBrightness.light => 'Light',
    AppBrightness.dark => 'Dark',
    AppBrightness.system => 'Match device',
  };

  IconData get icon => switch (this) {
    AppBrightness.light => Icons.light_mode_rounded,
    AppBrightness.dark => Icons.dark_mode_rounded,
    AppBrightness.system => Icons.brightness_auto_rounded,
  };

  static AppBrightness parse(String? raw) => switch (raw) {
    'dark' => AppBrightness.dark,
    'system' => AppBrightness.system,
    _ => AppBrightness.light,
  };

  /// Resolves [AppBrightness.system] against what the device reports.
  bool isDark(Brightness platform) => switch (this) {
    AppBrightness.light => false,
    AppBrightness.dark => true,
    AppBrightness.system => platform == Brightness.dark,
  };
}

class AppTheming {
  /// One of [kThemePresets]. Unknown ids fall back to the first preset.
  final String presetId;

  final AppBrightness brightness;

  const AppTheming({
    this.presetId = 'indigo',
    this.brightness = AppBrightness.light,
  });

  factory AppTheming.fromMap(Map<String, dynamic> m) => AppTheming(
    presetId: m['presetId'] as String? ?? 'indigo',
    brightness: AppBrightnessX.parse(m['brightness'] as String?),
  );

  Map<String, dynamic> toMap() => {
    'presetId': presetId,
    'brightness': brightness.name,
  };

  ThemePreset get preset => kThemePresets.firstWhere(
    (p) => p.id == presetId,
    orElse: () => kThemePresets.first,
  );

  Color get seed => preset.color;

  AppTheming copyWith({String? presetId, AppBrightness? brightness}) =>
      AppTheming(
        presetId: presetId ?? this.presetId,
        brightness: brightness ?? this.brightness,
      );
}

// =====================================================================
// Academic session
// =====================================================================

class AcademicSession {
  /// "2026-27".
  final String? current;

  /// Which half of the year is running. Drives the default Sem filter.
  final bool oddSemester;

  const AcademicSession({this.current, this.oddSemester = true});

  factory AcademicSession.fromMap(Map<String, dynamic> m) => AcademicSession(
    current: m['current'] as String?,
    oddSemester: m['oddSemester'] as bool? ?? true,
  );

  Map<String, dynamic> toMap() => {
    'current': current,
    'oddSemester': oddSemester,
  };

  /// Semesters running in this half of the year — 1,3,5,7 or 2,4,6,8.
  List<int> get activeSems =>
      oddSemester ? const [1, 3, 5, 7] : const [2, 4, 6, 8];

  String get label => current == null
      ? (oddSemester ? 'Odd semester' : 'Even semester')
      : '$current · ${oddSemester ? 'Odd' : 'Even'} semester';
}

// =====================================================================
// Fine categories
// =====================================================================

class FineCategory {
  final String name;

  /// Pre-filled on the impose form. Null means "type it every time".
  final num? defaultAmount;

  const FineCategory({required this.name, this.defaultAmount});

  factory FineCategory.fromMap(Map<String, dynamic> m) => FineCategory(
    name: m['name'] as String? ?? '',
    defaultAmount: m['defaultAmount'] as num?,
  );

  Map<String, dynamic> toMap() => {
    'name': name,
    'defaultAmount': defaultAmount,
  };

  /// The built-in list, as editable rows to start from.
  static List<FineCategory> get defaults =>
      kFineCategories.map((c) => FineCategory(name: c)).toList();
}
