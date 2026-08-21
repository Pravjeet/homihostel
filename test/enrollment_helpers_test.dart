import 'package:flutter_test/flutter_test.dart';
import 'package:hostel_app/models/college_settings.dart';
import 'package:hostel_app/utils/enrollment_helpers.dart';

/// Pure batch → year → room-entitlement logic, tested against the real
/// cohorts on this campus (`batch` runs 2022-23 … 2025-26) rather than
/// invented examples, so a passing suite actually means something for this
/// data.
void main() {
  group('startYearOf', () {
    test('reads the start year off a span', () {
      expect(startYearOf('2025-26'), 2025);
      expect(startYearOf('2025-27'), 2025);
    });

    test('null on anything that will not parse', () {
      expect(startYearOf(null), isNull);
      expect(startYearOf(''), isNull);
      expect(startYearOf('garbage'), isNull);
      expect(startYearOf('-27'), isNull);
    });
  });

  group('yearFromBatch', () {
    test('the four live batches against the 2026-27 session', () {
      expect(yearFromBatch('2025-26', '2026-27'), 2);
      expect(yearFromBatch('2024-25', '2026-27'), 3);
      expect(yearFromBatch('2023-24', '2026-27'), 4);
      expect(yearFromBatch('2022-23', '2026-27'), 5);
    });

    test('year 1 in the batch\'s own first session', () {
      expect(yearFromBatch('2025-26', '2025-26'), 1);
    });

    test('a lateral entrant carries the ahead cohort\'s batch, so the same '
        'formula lands them correctly', () {
      // No special case needed: they are simply given batch 2024-25 even
      // though they personally joined later.
      expect(yearFromBatch('2024-25', '2026-27'), 3);
    });

    test('null when either side fails to parse', () {
      expect(yearFromBatch(null, '2026-27'), isNull);
      expect(yearFromBatch('2024-25', null), isNull);
      expect(yearFromBatch('garbage', '2026-27'), isNull);
    });
  });

  group('nextSessionAfter', () {
    test('the ordinary case', () {
      expect(nextSessionAfter('2026-27'), '2027-28');
    });

    test('century rollover', () {
      expect(nextSessionAfter('2099-00'), '2100-01');
    });

    test('null propagates rather than throwing', () {
      expect(nextSessionAfter(null), isNull);
      expect(nextSessionAfter(''), isNull);
    });
  });

  group('hasGraduated', () {
    test('follows the year, not the batch', () {
      expect(hasGraduated(1, 4), isFalse);
      expect(hasGraduated(4, 4), isFalse);
      expect(hasGraduated(5, 4), isTrue);
    });

    test('a repeater still in year 2 has not graduated even on an old batch', () {
      // The point of comparing year rather than recomputing from batch:
      // someone whose batch alone would suggest they are further along.
      expect(hasGraduated(2, 4), isFalse);
    });

    test('the three configured course lengths', () {
      expect(hasGraduated(4, 4), isFalse); // UG, final year
      expect(hasGraduated(5, 4), isTrue); // UG, graduated
      expect(hasGraduated(3, 3), isFalse); // ICD, final year
      expect(hasGraduated(4, 3), isTrue); // ICD, graduated
      expect(hasGraduated(2, 2), isFalse); // PG, final year
      expect(hasGraduated(3, 2), isTrue); // PG, graduated
    });
  });

  group('requiredRoomCapacity', () {
    const ug = CourseRule(
      course: 'UG',
      totalYears: 4,
      seating: CourseSeating.meritSingle,
    );
    const icd = CourseRule(
      course: 'ICD',
      totalYears: 3,
      seating: CourseSeating.alwaysShared,
    );
    const pg = CourseRule(
      course: 'PG',
      totalYears: 2,
      seating: CourseSeating.alwaysSingle,
    );

    test('no rule means no policy, not a default of shared', () {
      expect(
        requiredRoomCapacity(rule: null, year: 1, singleRoomEligible: false),
        isNull,
      );
    });

    group('UG (merit single)', () {
      test('years 1-2 are always shared, eligible or not', () {
        for (final eligible in [false, true]) {
          expect(
            requiredRoomCapacity(
              rule: ug,
              year: 1,
              singleRoomEligible: eligible,
            ),
            3,
          );
          expect(
            requiredRoomCapacity(
              rule: ug,
              year: 2,
              singleRoomEligible: eligible,
            ),
            3,
          );
        }
      });

      test('year 3+ is single only if eligible', () {
        expect(
          requiredRoomCapacity(rule: ug, year: 3, singleRoomEligible: true),
          1,
        );
        expect(
          requiredRoomCapacity(rule: ug, year: 3, singleRoomEligible: false),
          3,
        );
        expect(
          requiredRoomCapacity(rule: ug, year: 4, singleRoomEligible: true),
          1,
        );
        expect(
          requiredRoomCapacity(rule: ug, year: 4, singleRoomEligible: false),
          3,
        );
      });
    });

    test('ICD is always shared, every year, eligible or not', () {
      for (final year in [1, 2, 3]) {
        expect(
          requiredRoomCapacity(rule: icd, year: year, singleRoomEligible: true),
          3,
        );
        expect(
          requiredRoomCapacity(
            rule: icd,
            year: year,
            singleRoomEligible: false,
          ),
          3,
        );
      }
    });

    test('PG is always single, every year, eligible or not', () {
      for (final year in [1, 2]) {
        expect(
          requiredRoomCapacity(rule: pg, year: year, singleRoomEligible: true),
          1,
        );
        expect(
          requiredRoomCapacity(rule: pg, year: year, singleRoomEligible: false),
          1,
        );
      }
    });

    test('a college using two-seaters instead of three respects sharedCapacity', () {
      const twoSeaterUg = CourseRule(
        course: 'UG',
        totalYears: 4,
        seating: CourseSeating.meritSingle,
        sharedCapacity: 2,
      );
      expect(
        requiredRoomCapacity(
          rule: twoSeaterUg,
          year: 1,
          singleRoomEligible: false,
        ),
        2,
      );
    });
  });

  group('roomTypeLabel', () {
    test('1 is a Single, anything else is N-Seater', () {
      expect(roomTypeLabel(1), 'Single');
      expect(roomTypeLabel(2), '2-Seater');
      expect(roomTypeLabel(3), '3-Seater');
    });
  });

  group('ordinal', () {
    test('the common cases', () {
      expect(ordinal(1), '1st');
      expect(ordinal(2), '2nd');
      expect(ordinal(3), '3rd');
      expect(ordinal(4), '4th');
      expect(ordinal(6), '6th');
    });

    test('the teens exception', () {
      expect(ordinal(11), '11th');
      expect(ordinal(12), '12th');
      expect(ordinal(13), '13th');
    });

    test('past twenty the pattern resumes', () {
      expect(ordinal(21), '21st');
      expect(ordinal(22), '22nd');
    });
  });
}
