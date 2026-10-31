import 'package:drift/native.dart';

import 'app_database.dart';

/// An empty in-memory database with the full schema, for tests of code that sits on top of it.
AppDatabase openInMemoryDatabase() => AppDatabase(NativeDatabase.memory());
