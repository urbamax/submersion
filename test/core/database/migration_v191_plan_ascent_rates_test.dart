import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:submersion/core/database/database.dart';

/// Reads the SQL default expression declared for [column] on [table] and asks
/// SQLite to evaluate it, so the assertion holds whichever literal spelling
/// (`3.0`, `3`, ...) the DDL happens to use. Returns null when the column
/// declares no default at all.
Future<double?> _defaultAsDouble(
  AppDatabase db,
  String table,
  String column,
) async {
  final cols = await db.customSelect("PRAGMA table_info('$table')").get();
  final row = cols.firstWhere((c) => c.read<String>('name') == column);
  final expression = row.read<String?>('dflt_value');
  if (expression == null) return null;
  final evaluated = await db
      .customSelect('SELECT ($expression) AS value')
      .getSingle();
  return evaluated.read<double>('value');
}

const _columns = {
  'intermediate_ascent_rate': 6.0,
  'shallow_ascent_rate': 3.0,
  'final_ascent_rate': 1.0,
};

void main() {
  test('v191 is present in the migration ladder', () {
    // v191 is a past migration now: main landed v194
    // (dive_tanks.transmitter_serial) and the suunto-nautic branch adds v192
    // (dives.pp_o2_working). The exact-version assertion is the newest rung's
    // own job; assert membership here, not equality.
    expect(AppDatabase.currentSchemaVersion, greaterThanOrEqualTo(191));
    expect(AppDatabase.migrationVersions, contains(191));
  });

  test('a fresh database has both dive_plans ascent-rate columns', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    final cols = await db.customSelect("PRAGMA table_info('dive_plans')").get();
    final names = cols.map((c) => c.read<String>('name')).toSet();
    expect(names, containsAll(_columns.keys));
  });

  test('the columns are not null and carry the standard rates', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    final cols = await db.customSelect("PRAGMA table_info('dive_plans')").get();
    for (final entry in _columns.entries) {
      final column = cols.firstWhere(
        (c) => c.read<String>('name') == entry.key,
      );
      expect(column.read<int>('notnull'), 1, reason: entry.key);
      // A NOT NULL column with no default would break inserts from an older
      // writer, and the wrong default would silently change every existing
      // plan's schedule, so pin the value rather than just its presence.
      expect(
        await _defaultAsDouble(db, 'dive_plans', entry.key),
        entry.value,
        reason: entry.key,
      );
    }
  });

  test(
    'a database stranded before v191 gains the columns via beforeOpen',
    () async {
      final nativeDb = NativeDatabase.memory(
        setup: (rawDb) {
          rawDb.execute('''
          CREATE TABLE dive_plans (
            id TEXT NOT NULL PRIMARY KEY,
            name TEXT NOT NULL,
            gf_low INTEGER NOT NULL,
            gf_high INTEGER NOT NULL,
            ascent_rate REAL NOT NULL DEFAULT 9.0,
            created_at INTEGER,
            updated_at INTEGER
          )
        ''');
        },
      );
      final db = AppDatabase(nativeDb);
      addTearDown(db.close);

      final cols = await db
          .customSelect("PRAGMA table_info('dive_plans')")
          .get();
      final names = cols.map((c) => c.read<String>('name')).toSet();
      expect(names, containsAll(_columns.keys));
      // The backstop's ALTER TABLE spells its own defaults, independently of the
      // table definition above, so pin those too.
      for (final entry in _columns.entries) {
        expect(
          await _defaultAsDouble(db, 'dive_plans', entry.key),
          entry.value,
          reason: entry.key,
        );
      }
    },
  );

  test('the assert is a no-op when the table is absent', () async {
    final nativeDb = NativeDatabase.memory(
      setup: (rawDb) {
        rawDb.execute('CREATE TABLE unrelated (id TEXT)');
      },
    );
    final db = AppDatabase(nativeDb);
    addTearDown(db.close);

    await db.customSelect('SELECT 1').get();
  });
}
