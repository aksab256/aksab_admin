import 'package:aksab_admin/screens/tabs/manager_targets.dart';
import 'package:flutter_test/flutter_test.dart';

// Phase-1 manager targets: pure model rules (month keys, five indicators,
// entry building with audit history, month summaries). No Firestore needed.
void main() {
  group('managerMonthKey / isValidManagerMonthKey', () {
    test('formats yyyy-MM with zero-padded month', () {
      expect(managerMonthKey(DateTime(2026, 1, 15)), '2026-01');
      expect(managerMonthKey(DateTime(2026, 11, 2)), '2026-11');
    });

    test('accepts strict yyyy-MM only', () {
      expect(isValidManagerMonthKey('2026-11'), isTrue);
      expect(isValidManagerMonthKey('2026-1'), isFalse);
      expect(isValidManagerMonthKey('26-11'), isFalse);
      expect(isValidManagerMonthKey('2026-13'), isFalse);
      expect(isValidManagerMonthKey('2026-00'), isFalse);
      expect(isValidManagerMonthKey(''), isFalse);
    });
  });

  group('normalizeTargetValue', () {
    test('keeps numbers, parses numeric strings, zeroes the rest', () {
      expect(normalizeTargetValue(10), 10);
      expect(normalizeTargetValue(10.5), 10.5);
      expect(normalizeTargetValue(' 25 '), 25);
      expect(normalizeTargetValue(null), 0);
      expect(normalizeTargetValue(''), 0);
      expect(normalizeTargetValue('bogus'), 0);
      expect(normalizeTargetValue(double.nan), 0);
    });

    test('negatives and infinities become 0 (never throws)', () {
      expect(normalizeTargetValue(-5), 0);
      expect(normalizeTargetValue('-3'), 0);
      expect(normalizeTargetValue(double.infinity), 0);
    });
  });

  group('normalizeManagerTargets', () {
    test('returns exactly the five canonical fields', () {
      final out = normalizeManagerTargets({
        'financialTarget': '1000',
        'visitsTarget': 12,
        'unknownField': 99,
      });
      expect(out.keys.toSet(), kManagerTargetFields.toSet());
      expect(out['financialTarget'], 1000);
      expect(out['visitsTarget'], 12);
      expect(out['hoursTarget'], 0);
      expect(out['invoicesTarget'], 0);
      expect(out['clientsTarget'], 0);
    });
  });

  group('validateManagerTargets', () {
    Map<String, String> ctr({
      String financial = '',
      String hours = '',
      String invoices = '',
      String clients = '',
      String visits = '',
    }) =>
        {
          'financialTarget': financial,
          'hoursTarget': hours,
          'invoicesTarget': invoices,
          'clientsTarget': clients,
          'visitsTarget': visits,
        };

    test('rejects all-zero months', () {
      expect(validateManagerTargets(ctr()), isNotNull);
    });

    test('accepts a single positive indicator', () {
      expect(validateManagerTargets(ctr(visits: '10')), isNull);
      expect(validateManagerTargets(ctr(financial: '5000.5')), isNull);
    });

    test('rejects non-numeric and negative input with Arabic message', () {
      final bad = validateManagerTargets(ctr(hours: 'abc'));
      expect(bad, isNotNull);
      expect(validateManagerTargets(ctr(clients: '-2')), isNotNull);
    });
  });

  group('buildManagerTargetEntry', () {
    test('stores five indicators plus audit fields, no locked flag', () {
      final now = DateTime(2026, 11, 11, 10);
      final entry = buildManagerTargetEntry(
        values: {'financialTarget': 5000, 'visitsTarget': '20'},
        setByUid: 'admin1',
        setByRole: 'admin',
        now: now,
      );
      expect(entry['financialTarget'], 5000);
      expect(entry['visitsTarget'], 20);
      expect(entry['hoursTarget'], 0);
      expect(entry['setByUid'], 'admin1');
      expect(entry['setByRole'], 'admin');
      expect(entry['setAt'], now);
      expect(entry['status'], kManagerTargetStatusAssigned);
      expect(entry.containsKey('locked'), isFalse);
      final history = entry['history'] as List;
      expect(history, hasLength(1));
      expect((history.first as Map)['byUid'], 'admin1');
    });

    test('preserves and caps previous history at 50', () {
      final now = DateTime(2026, 11, 11);
      final prev =
          List.generate(60, (i) => {'note': 'old-$i', 'at': now});
      final entry = buildManagerTargetEntry(
        values: {'financialTarget': 1},
        setByUid: 'u',
        setByRole: 'admin',
        now: now,
        previousHistory: prev,
      );
      final history = entry['history'] as List;
      expect(history, hasLength(50));
      expect((history.last as Map)['note'], 'set');
    });
  });

  group('summarizeManagerMonth', () {
    test('missing month reports hasTarget false with zeroes', () {
      final summary = summarizeManagerMonth(null, '2026-11');
      expect(summary['hasTarget'], isFalse);
      expect((summary['values'] as Map)['financialTarget'], 0);
      expect(summary['historyCount'], 0);
    });

    test('reads an existing month entry', () {
      final now = DateTime(2026, 11, 11);
      final targets = {
        '2026-11': buildManagerTargetEntry(
          values: {'financialTarget': 7000, 'clientsTarget': 15},
          setByUid: 'a',
          setByRole: 'admin',
          now: now,
        ),
      };
      final summary = summarizeManagerMonth(targets, '2026-11');
      expect(summary['hasTarget'], isTrue);
      expect((summary['values'] as Map)['financialTarget'], 7000);
      expect((summary['values'] as Map)['clientsTarget'], 15);
      expect(summary['historyCount'], 1);
    });
  });
}
