// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $PlaybackProgressTable extends PlaybackProgress
    with TableInfo<$PlaybackProgressTable, PlaybackProgressData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PlaybackProgressTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _mediaIdMeta = const VerificationMeta(
    'mediaId',
  );
  @override
  late final GeneratedColumn<String> mediaId = GeneratedColumn<String>(
    'media_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _positionMsMeta = const VerificationMeta(
    'positionMs',
  );
  @override
  late final GeneratedColumn<int> positionMs = GeneratedColumn<int>(
    'position_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _durationMsMeta = const VerificationMeta(
    'durationMs',
  );
  @override
  late final GeneratedColumn<int> durationMs = GeneratedColumn<int>(
    'duration_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _completedMeta = const VerificationMeta(
    'completed',
  );
  @override
  late final GeneratedColumn<bool> completed = GeneratedColumn<bool>(
    'completed',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("completed" IN (0, 1))',
    ),
  );
  static const VerificationMeta _audioTrackIdMeta = const VerificationMeta(
    'audioTrackId',
  );
  @override
  late final GeneratedColumn<String> audioTrackId = GeneratedColumn<String>(
    'audio_track_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _subtitleTrackIdMeta = const VerificationMeta(
    'subtitleTrackId',
  );
  @override
  late final GeneratedColumn<String> subtitleTrackId = GeneratedColumn<String>(
    'subtitle_track_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastPlayedSourceKeyMeta =
      const VerificationMeta('lastPlayedSourceKey');
  @override
  late final GeneratedColumn<String> lastPlayedSourceKey =
      GeneratedColumn<String>(
        'last_played_source_key',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  @override
  List<GeneratedColumn> get $columns => [
    mediaId,
    positionMs,
    durationMs,
    updatedAt,
    completed,
    audioTrackId,
    subtitleTrackId,
    lastPlayedSourceKey,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'playback_progress';
  @override
  VerificationContext validateIntegrity(
    Insertable<PlaybackProgressData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('media_id')) {
      context.handle(
        _mediaIdMeta,
        mediaId.isAcceptableOrUnknown(data['media_id']!, _mediaIdMeta),
      );
    } else if (isInserting) {
      context.missing(_mediaIdMeta);
    }
    if (data.containsKey('position_ms')) {
      context.handle(
        _positionMsMeta,
        positionMs.isAcceptableOrUnknown(data['position_ms']!, _positionMsMeta),
      );
    } else if (isInserting) {
      context.missing(_positionMsMeta);
    }
    if (data.containsKey('duration_ms')) {
      context.handle(
        _durationMsMeta,
        durationMs.isAcceptableOrUnknown(data['duration_ms']!, _durationMsMeta),
      );
    } else if (isInserting) {
      context.missing(_durationMsMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('completed')) {
      context.handle(
        _completedMeta,
        completed.isAcceptableOrUnknown(data['completed']!, _completedMeta),
      );
    } else if (isInserting) {
      context.missing(_completedMeta);
    }
    if (data.containsKey('audio_track_id')) {
      context.handle(
        _audioTrackIdMeta,
        audioTrackId.isAcceptableOrUnknown(
          data['audio_track_id']!,
          _audioTrackIdMeta,
        ),
      );
    }
    if (data.containsKey('subtitle_track_id')) {
      context.handle(
        _subtitleTrackIdMeta,
        subtitleTrackId.isAcceptableOrUnknown(
          data['subtitle_track_id']!,
          _subtitleTrackIdMeta,
        ),
      );
    }
    if (data.containsKey('last_played_source_key')) {
      context.handle(
        _lastPlayedSourceKeyMeta,
        lastPlayedSourceKey.isAcceptableOrUnknown(
          data['last_played_source_key']!,
          _lastPlayedSourceKeyMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {mediaId};
  @override
  PlaybackProgressData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PlaybackProgressData(
      mediaId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}media_id'],
      )!,
      positionMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position_ms'],
      )!,
      durationMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_ms'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
      completed: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}completed'],
      )!,
      audioTrackId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}audio_track_id'],
      ),
      subtitleTrackId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}subtitle_track_id'],
      ),
      lastPlayedSourceKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_played_source_key'],
      ),
    );
  }

  @override
  $PlaybackProgressTable createAlias(String alias) {
    return $PlaybackProgressTable(attachedDatabase, alias);
  }
}

class PlaybackProgressData extends DataClass
    implements Insertable<PlaybackProgressData> {
  final String mediaId;
  final int positionMs;
  final int durationMs;
  final int updatedAt;
  final bool completed;
  final String? audioTrackId;
  final String? subtitleTrackId;
  final String? lastPlayedSourceKey;
  const PlaybackProgressData({
    required this.mediaId,
    required this.positionMs,
    required this.durationMs,
    required this.updatedAt,
    required this.completed,
    this.audioTrackId,
    this.subtitleTrackId,
    this.lastPlayedSourceKey,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['media_id'] = Variable<String>(mediaId);
    map['position_ms'] = Variable<int>(positionMs);
    map['duration_ms'] = Variable<int>(durationMs);
    map['updated_at'] = Variable<int>(updatedAt);
    map['completed'] = Variable<bool>(completed);
    if (!nullToAbsent || audioTrackId != null) {
      map['audio_track_id'] = Variable<String>(audioTrackId);
    }
    if (!nullToAbsent || subtitleTrackId != null) {
      map['subtitle_track_id'] = Variable<String>(subtitleTrackId);
    }
    if (!nullToAbsent || lastPlayedSourceKey != null) {
      map['last_played_source_key'] = Variable<String>(lastPlayedSourceKey);
    }
    return map;
  }

  PlaybackProgressCompanion toCompanion(bool nullToAbsent) {
    return PlaybackProgressCompanion(
      mediaId: Value(mediaId),
      positionMs: Value(positionMs),
      durationMs: Value(durationMs),
      updatedAt: Value(updatedAt),
      completed: Value(completed),
      audioTrackId: audioTrackId == null && nullToAbsent
          ? const Value.absent()
          : Value(audioTrackId),
      subtitleTrackId: subtitleTrackId == null && nullToAbsent
          ? const Value.absent()
          : Value(subtitleTrackId),
      lastPlayedSourceKey: lastPlayedSourceKey == null && nullToAbsent
          ? const Value.absent()
          : Value(lastPlayedSourceKey),
    );
  }

  factory PlaybackProgressData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PlaybackProgressData(
      mediaId: serializer.fromJson<String>(json['mediaId']),
      positionMs: serializer.fromJson<int>(json['positionMs']),
      durationMs: serializer.fromJson<int>(json['durationMs']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
      completed: serializer.fromJson<bool>(json['completed']),
      audioTrackId: serializer.fromJson<String?>(json['audioTrackId']),
      subtitleTrackId: serializer.fromJson<String?>(json['subtitleTrackId']),
      lastPlayedSourceKey: serializer.fromJson<String?>(
        json['lastPlayedSourceKey'],
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'mediaId': serializer.toJson<String>(mediaId),
      'positionMs': serializer.toJson<int>(positionMs),
      'durationMs': serializer.toJson<int>(durationMs),
      'updatedAt': serializer.toJson<int>(updatedAt),
      'completed': serializer.toJson<bool>(completed),
      'audioTrackId': serializer.toJson<String?>(audioTrackId),
      'subtitleTrackId': serializer.toJson<String?>(subtitleTrackId),
      'lastPlayedSourceKey': serializer.toJson<String?>(lastPlayedSourceKey),
    };
  }

  PlaybackProgressData copyWith({
    String? mediaId,
    int? positionMs,
    int? durationMs,
    int? updatedAt,
    bool? completed,
    Value<String?> audioTrackId = const Value.absent(),
    Value<String?> subtitleTrackId = const Value.absent(),
    Value<String?> lastPlayedSourceKey = const Value.absent(),
  }) => PlaybackProgressData(
    mediaId: mediaId ?? this.mediaId,
    positionMs: positionMs ?? this.positionMs,
    durationMs: durationMs ?? this.durationMs,
    updatedAt: updatedAt ?? this.updatedAt,
    completed: completed ?? this.completed,
    audioTrackId: audioTrackId.present ? audioTrackId.value : this.audioTrackId,
    subtitleTrackId: subtitleTrackId.present
        ? subtitleTrackId.value
        : this.subtitleTrackId,
    lastPlayedSourceKey: lastPlayedSourceKey.present
        ? lastPlayedSourceKey.value
        : this.lastPlayedSourceKey,
  );
  PlaybackProgressData copyWithCompanion(PlaybackProgressCompanion data) {
    return PlaybackProgressData(
      mediaId: data.mediaId.present ? data.mediaId.value : this.mediaId,
      positionMs: data.positionMs.present
          ? data.positionMs.value
          : this.positionMs,
      durationMs: data.durationMs.present
          ? data.durationMs.value
          : this.durationMs,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      completed: data.completed.present ? data.completed.value : this.completed,
      audioTrackId: data.audioTrackId.present
          ? data.audioTrackId.value
          : this.audioTrackId,
      subtitleTrackId: data.subtitleTrackId.present
          ? data.subtitleTrackId.value
          : this.subtitleTrackId,
      lastPlayedSourceKey: data.lastPlayedSourceKey.present
          ? data.lastPlayedSourceKey.value
          : this.lastPlayedSourceKey,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PlaybackProgressData(')
          ..write('mediaId: $mediaId, ')
          ..write('positionMs: $positionMs, ')
          ..write('durationMs: $durationMs, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('completed: $completed, ')
          ..write('audioTrackId: $audioTrackId, ')
          ..write('subtitleTrackId: $subtitleTrackId, ')
          ..write('lastPlayedSourceKey: $lastPlayedSourceKey')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    mediaId,
    positionMs,
    durationMs,
    updatedAt,
    completed,
    audioTrackId,
    subtitleTrackId,
    lastPlayedSourceKey,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PlaybackProgressData &&
          other.mediaId == this.mediaId &&
          other.positionMs == this.positionMs &&
          other.durationMs == this.durationMs &&
          other.updatedAt == this.updatedAt &&
          other.completed == this.completed &&
          other.audioTrackId == this.audioTrackId &&
          other.subtitleTrackId == this.subtitleTrackId &&
          other.lastPlayedSourceKey == this.lastPlayedSourceKey);
}

class PlaybackProgressCompanion extends UpdateCompanion<PlaybackProgressData> {
  final Value<String> mediaId;
  final Value<int> positionMs;
  final Value<int> durationMs;
  final Value<int> updatedAt;
  final Value<bool> completed;
  final Value<String?> audioTrackId;
  final Value<String?> subtitleTrackId;
  final Value<String?> lastPlayedSourceKey;
  final Value<int> rowid;
  const PlaybackProgressCompanion({
    this.mediaId = const Value.absent(),
    this.positionMs = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.completed = const Value.absent(),
    this.audioTrackId = const Value.absent(),
    this.subtitleTrackId = const Value.absent(),
    this.lastPlayedSourceKey = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PlaybackProgressCompanion.insert({
    required String mediaId,
    required int positionMs,
    required int durationMs,
    required int updatedAt,
    required bool completed,
    this.audioTrackId = const Value.absent(),
    this.subtitleTrackId = const Value.absent(),
    this.lastPlayedSourceKey = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : mediaId = Value(mediaId),
       positionMs = Value(positionMs),
       durationMs = Value(durationMs),
       updatedAt = Value(updatedAt),
       completed = Value(completed);
  static Insertable<PlaybackProgressData> custom({
    Expression<String>? mediaId,
    Expression<int>? positionMs,
    Expression<int>? durationMs,
    Expression<int>? updatedAt,
    Expression<bool>? completed,
    Expression<String>? audioTrackId,
    Expression<String>? subtitleTrackId,
    Expression<String>? lastPlayedSourceKey,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (mediaId != null) 'media_id': mediaId,
      if (positionMs != null) 'position_ms': positionMs,
      if (durationMs != null) 'duration_ms': durationMs,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (completed != null) 'completed': completed,
      if (audioTrackId != null) 'audio_track_id': audioTrackId,
      if (subtitleTrackId != null) 'subtitle_track_id': subtitleTrackId,
      if (lastPlayedSourceKey != null)
        'last_played_source_key': lastPlayedSourceKey,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PlaybackProgressCompanion copyWith({
    Value<String>? mediaId,
    Value<int>? positionMs,
    Value<int>? durationMs,
    Value<int>? updatedAt,
    Value<bool>? completed,
    Value<String?>? audioTrackId,
    Value<String?>? subtitleTrackId,
    Value<String?>? lastPlayedSourceKey,
    Value<int>? rowid,
  }) {
    return PlaybackProgressCompanion(
      mediaId: mediaId ?? this.mediaId,
      positionMs: positionMs ?? this.positionMs,
      durationMs: durationMs ?? this.durationMs,
      updatedAt: updatedAt ?? this.updatedAt,
      completed: completed ?? this.completed,
      audioTrackId: audioTrackId ?? this.audioTrackId,
      subtitleTrackId: subtitleTrackId ?? this.subtitleTrackId,
      lastPlayedSourceKey: lastPlayedSourceKey ?? this.lastPlayedSourceKey,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (mediaId.present) {
      map['media_id'] = Variable<String>(mediaId.value);
    }
    if (positionMs.present) {
      map['position_ms'] = Variable<int>(positionMs.value);
    }
    if (durationMs.present) {
      map['duration_ms'] = Variable<int>(durationMs.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (completed.present) {
      map['completed'] = Variable<bool>(completed.value);
    }
    if (audioTrackId.present) {
      map['audio_track_id'] = Variable<String>(audioTrackId.value);
    }
    if (subtitleTrackId.present) {
      map['subtitle_track_id'] = Variable<String>(subtitleTrackId.value);
    }
    if (lastPlayedSourceKey.present) {
      map['last_played_source_key'] = Variable<String>(
        lastPlayedSourceKey.value,
      );
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PlaybackProgressCompanion(')
          ..write('mediaId: $mediaId, ')
          ..write('positionMs: $positionMs, ')
          ..write('durationMs: $durationMs, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('completed: $completed, ')
          ..write('audioTrackId: $audioTrackId, ')
          ..write('subtitleTrackId: $subtitleTrackId, ')
          ..write('lastPlayedSourceKey: $lastPlayedSourceKey, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $FavouritesTable extends Favourites
    with TableInfo<$FavouritesTable, Favourite> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FavouritesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _mediaIdMeta = const VerificationMeta(
    'mediaId',
  );
  @override
  late final GeneratedColumn<String> mediaId = GeneratedColumn<String>(
    'media_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _addedAtMeta = const VerificationMeta(
    'addedAt',
  );
  @override
  late final GeneratedColumn<int> addedAt = GeneratedColumn<int>(
    'added_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [mediaId, addedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'favourites';
  @override
  VerificationContext validateIntegrity(
    Insertable<Favourite> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('media_id')) {
      context.handle(
        _mediaIdMeta,
        mediaId.isAcceptableOrUnknown(data['media_id']!, _mediaIdMeta),
      );
    } else if (isInserting) {
      context.missing(_mediaIdMeta);
    }
    if (data.containsKey('added_at')) {
      context.handle(
        _addedAtMeta,
        addedAt.isAcceptableOrUnknown(data['added_at']!, _addedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_addedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {mediaId};
  @override
  Favourite map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Favourite(
      mediaId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}media_id'],
      )!,
      addedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}added_at'],
      )!,
    );
  }

  @override
  $FavouritesTable createAlias(String alias) {
    return $FavouritesTable(attachedDatabase, alias);
  }
}

class Favourite extends DataClass implements Insertable<Favourite> {
  final String mediaId;
  final int addedAt;
  const Favourite({required this.mediaId, required this.addedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['media_id'] = Variable<String>(mediaId);
    map['added_at'] = Variable<int>(addedAt);
    return map;
  }

  FavouritesCompanion toCompanion(bool nullToAbsent) {
    return FavouritesCompanion(
      mediaId: Value(mediaId),
      addedAt: Value(addedAt),
    );
  }

  factory Favourite.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Favourite(
      mediaId: serializer.fromJson<String>(json['mediaId']),
      addedAt: serializer.fromJson<int>(json['addedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'mediaId': serializer.toJson<String>(mediaId),
      'addedAt': serializer.toJson<int>(addedAt),
    };
  }

  Favourite copyWith({String? mediaId, int? addedAt}) => Favourite(
    mediaId: mediaId ?? this.mediaId,
    addedAt: addedAt ?? this.addedAt,
  );
  Favourite copyWithCompanion(FavouritesCompanion data) {
    return Favourite(
      mediaId: data.mediaId.present ? data.mediaId.value : this.mediaId,
      addedAt: data.addedAt.present ? data.addedAt.value : this.addedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Favourite(')
          ..write('mediaId: $mediaId, ')
          ..write('addedAt: $addedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(mediaId, addedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Favourite &&
          other.mediaId == this.mediaId &&
          other.addedAt == this.addedAt);
}

class FavouritesCompanion extends UpdateCompanion<Favourite> {
  final Value<String> mediaId;
  final Value<int> addedAt;
  final Value<int> rowid;
  const FavouritesCompanion({
    this.mediaId = const Value.absent(),
    this.addedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  FavouritesCompanion.insert({
    required String mediaId,
    required int addedAt,
    this.rowid = const Value.absent(),
  }) : mediaId = Value(mediaId),
       addedAt = Value(addedAt);
  static Insertable<Favourite> custom({
    Expression<String>? mediaId,
    Expression<int>? addedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (mediaId != null) 'media_id': mediaId,
      if (addedAt != null) 'added_at': addedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  FavouritesCompanion copyWith({
    Value<String>? mediaId,
    Value<int>? addedAt,
    Value<int>? rowid,
  }) {
    return FavouritesCompanion(
      mediaId: mediaId ?? this.mediaId,
      addedAt: addedAt ?? this.addedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (mediaId.present) {
      map['media_id'] = Variable<String>(mediaId.value);
    }
    if (addedAt.present) {
      map['added_at'] = Variable<int>(addedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FavouritesCompanion(')
          ..write('mediaId: $mediaId, ')
          ..write('addedAt: $addedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $NextUpTable extends NextUp with TableInfo<$NextUpTable, NextUpData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $NextUpTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _seriesIdMeta = const VerificationMeta(
    'seriesId',
  );
  @override
  late final GeneratedColumn<String> seriesId = GeneratedColumn<String>(
    'series_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _mediaIdMeta = const VerificationMeta(
    'mediaId',
  );
  @override
  late final GeneratedColumn<String> mediaId = GeneratedColumn<String>(
    'media_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _seasonMeta = const VerificationMeta('season');
  @override
  late final GeneratedColumn<int> season = GeneratedColumn<int>(
    'season',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _episodeMeta = const VerificationMeta(
    'episode',
  );
  @override
  late final GeneratedColumn<int> episode = GeneratedColumn<int>(
    'episode',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    seriesId,
    mediaId,
    season,
    episode,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'next_up';
  @override
  VerificationContext validateIntegrity(
    Insertable<NextUpData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('series_id')) {
      context.handle(
        _seriesIdMeta,
        seriesId.isAcceptableOrUnknown(data['series_id']!, _seriesIdMeta),
      );
    } else if (isInserting) {
      context.missing(_seriesIdMeta);
    }
    if (data.containsKey('media_id')) {
      context.handle(
        _mediaIdMeta,
        mediaId.isAcceptableOrUnknown(data['media_id']!, _mediaIdMeta),
      );
    } else if (isInserting) {
      context.missing(_mediaIdMeta);
    }
    if (data.containsKey('season')) {
      context.handle(
        _seasonMeta,
        season.isAcceptableOrUnknown(data['season']!, _seasonMeta),
      );
    } else if (isInserting) {
      context.missing(_seasonMeta);
    }
    if (data.containsKey('episode')) {
      context.handle(
        _episodeMeta,
        episode.isAcceptableOrUnknown(data['episode']!, _episodeMeta),
      );
    } else if (isInserting) {
      context.missing(_episodeMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {seriesId};
  @override
  NextUpData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return NextUpData(
      seriesId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}series_id'],
      )!,
      mediaId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}media_id'],
      )!,
      season: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}season'],
      )!,
      episode: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}episode'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $NextUpTable createAlias(String alias) {
    return $NextUpTable(attachedDatabase, alias);
  }
}

class NextUpData extends DataClass implements Insertable<NextUpData> {
  final String seriesId;
  final String mediaId;
  final int season;
  final int episode;
  final int updatedAt;
  const NextUpData({
    required this.seriesId,
    required this.mediaId,
    required this.season,
    required this.episode,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['series_id'] = Variable<String>(seriesId);
    map['media_id'] = Variable<String>(mediaId);
    map['season'] = Variable<int>(season);
    map['episode'] = Variable<int>(episode);
    map['updated_at'] = Variable<int>(updatedAt);
    return map;
  }

  NextUpCompanion toCompanion(bool nullToAbsent) {
    return NextUpCompanion(
      seriesId: Value(seriesId),
      mediaId: Value(mediaId),
      season: Value(season),
      episode: Value(episode),
      updatedAt: Value(updatedAt),
    );
  }

  factory NextUpData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return NextUpData(
      seriesId: serializer.fromJson<String>(json['seriesId']),
      mediaId: serializer.fromJson<String>(json['mediaId']),
      season: serializer.fromJson<int>(json['season']),
      episode: serializer.fromJson<int>(json['episode']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'seriesId': serializer.toJson<String>(seriesId),
      'mediaId': serializer.toJson<String>(mediaId),
      'season': serializer.toJson<int>(season),
      'episode': serializer.toJson<int>(episode),
      'updatedAt': serializer.toJson<int>(updatedAt),
    };
  }

  NextUpData copyWith({
    String? seriesId,
    String? mediaId,
    int? season,
    int? episode,
    int? updatedAt,
  }) => NextUpData(
    seriesId: seriesId ?? this.seriesId,
    mediaId: mediaId ?? this.mediaId,
    season: season ?? this.season,
    episode: episode ?? this.episode,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  NextUpData copyWithCompanion(NextUpCompanion data) {
    return NextUpData(
      seriesId: data.seriesId.present ? data.seriesId.value : this.seriesId,
      mediaId: data.mediaId.present ? data.mediaId.value : this.mediaId,
      season: data.season.present ? data.season.value : this.season,
      episode: data.episode.present ? data.episode.value : this.episode,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('NextUpData(')
          ..write('seriesId: $seriesId, ')
          ..write('mediaId: $mediaId, ')
          ..write('season: $season, ')
          ..write('episode: $episode, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(seriesId, mediaId, season, episode, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is NextUpData &&
          other.seriesId == this.seriesId &&
          other.mediaId == this.mediaId &&
          other.season == this.season &&
          other.episode == this.episode &&
          other.updatedAt == this.updatedAt);
}

class NextUpCompanion extends UpdateCompanion<NextUpData> {
  final Value<String> seriesId;
  final Value<String> mediaId;
  final Value<int> season;
  final Value<int> episode;
  final Value<int> updatedAt;
  final Value<int> rowid;
  const NextUpCompanion({
    this.seriesId = const Value.absent(),
    this.mediaId = const Value.absent(),
    this.season = const Value.absent(),
    this.episode = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  NextUpCompanion.insert({
    required String seriesId,
    required String mediaId,
    required int season,
    required int episode,
    required int updatedAt,
    this.rowid = const Value.absent(),
  }) : seriesId = Value(seriesId),
       mediaId = Value(mediaId),
       season = Value(season),
       episode = Value(episode),
       updatedAt = Value(updatedAt);
  static Insertable<NextUpData> custom({
    Expression<String>? seriesId,
    Expression<String>? mediaId,
    Expression<int>? season,
    Expression<int>? episode,
    Expression<int>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (seriesId != null) 'series_id': seriesId,
      if (mediaId != null) 'media_id': mediaId,
      if (season != null) 'season': season,
      if (episode != null) 'episode': episode,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  NextUpCompanion copyWith({
    Value<String>? seriesId,
    Value<String>? mediaId,
    Value<int>? season,
    Value<int>? episode,
    Value<int>? updatedAt,
    Value<int>? rowid,
  }) {
    return NextUpCompanion(
      seriesId: seriesId ?? this.seriesId,
      mediaId: mediaId ?? this.mediaId,
      season: season ?? this.season,
      episode: episode ?? this.episode,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (seriesId.present) {
      map['series_id'] = Variable<String>(seriesId.value);
    }
    if (mediaId.present) {
      map['media_id'] = Variable<String>(mediaId.value);
    }
    if (season.present) {
      map['season'] = Variable<int>(season.value);
    }
    if (episode.present) {
      map['episode'] = Variable<int>(episode.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('NextUpCompanion(')
          ..write('seriesId: $seriesId, ')
          ..write('mediaId: $mediaId, ')
          ..write('season: $season, ')
          ..write('episode: $episode, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DownloadRecordsTable extends DownloadRecords
    with TableInfo<$DownloadRecordsTable, DownloadRecordRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DownloadRecordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _sourceKeyMeta = const VerificationMeta(
    'sourceKey',
  );
  @override
  late final GeneratedColumn<String> sourceKey = GeneratedColumn<String>(
    'source_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _filePathMeta = const VerificationMeta(
    'filePath',
  );
  @override
  late final GeneratedColumn<String> filePath = GeneratedColumn<String>(
    'file_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _totalBytesMeta = const VerificationMeta(
    'totalBytes',
  );
  @override
  late final GeneratedColumn<int> totalBytes = GeneratedColumn<int>(
    'total_bytes',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _validatorMeta = const VerificationMeta(
    'validator',
  );
  @override
  late final GeneratedColumn<String> validator = GeneratedColumn<String>(
    'validator',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastUsedAtMeta = const VerificationMeta(
    'lastUsedAt',
  );
  @override
  late final GeneratedColumn<int> lastUsedAt = GeneratedColumn<int>(
    'last_used_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    sourceKey,
    kind,
    filePath,
    totalBytes,
    validator,
    lastUsedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'download_records';
  @override
  VerificationContext validateIntegrity(
    Insertable<DownloadRecordRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('source_key')) {
      context.handle(
        _sourceKeyMeta,
        sourceKey.isAcceptableOrUnknown(data['source_key']!, _sourceKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceKeyMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('file_path')) {
      context.handle(
        _filePathMeta,
        filePath.isAcceptableOrUnknown(data['file_path']!, _filePathMeta),
      );
    }
    if (data.containsKey('total_bytes')) {
      context.handle(
        _totalBytesMeta,
        totalBytes.isAcceptableOrUnknown(data['total_bytes']!, _totalBytesMeta),
      );
    }
    if (data.containsKey('validator')) {
      context.handle(
        _validatorMeta,
        validator.isAcceptableOrUnknown(data['validator']!, _validatorMeta),
      );
    }
    if (data.containsKey('last_used_at')) {
      context.handle(
        _lastUsedAtMeta,
        lastUsedAt.isAcceptableOrUnknown(
          data['last_used_at']!,
          _lastUsedAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_lastUsedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {sourceKey};
  @override
  DownloadRecordRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DownloadRecordRow(
      sourceKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_key'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      filePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}file_path'],
      ),
      totalBytes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}total_bytes'],
      ),
      validator: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}validator'],
      ),
      lastUsedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_used_at'],
      )!,
    );
  }

  @override
  $DownloadRecordsTable createAlias(String alias) {
    return $DownloadRecordsTable(attachedDatabase, alias);
  }
}

class DownloadRecordRow extends DataClass
    implements Insertable<DownloadRecordRow> {
  final String sourceKey;
  final String kind;
  final String? filePath;
  final int? totalBytes;
  final String? validator;
  final int lastUsedAt;
  const DownloadRecordRow({
    required this.sourceKey,
    required this.kind,
    this.filePath,
    this.totalBytes,
    this.validator,
    required this.lastUsedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['source_key'] = Variable<String>(sourceKey);
    map['kind'] = Variable<String>(kind);
    if (!nullToAbsent || filePath != null) {
      map['file_path'] = Variable<String>(filePath);
    }
    if (!nullToAbsent || totalBytes != null) {
      map['total_bytes'] = Variable<int>(totalBytes);
    }
    if (!nullToAbsent || validator != null) {
      map['validator'] = Variable<String>(validator);
    }
    map['last_used_at'] = Variable<int>(lastUsedAt);
    return map;
  }

  DownloadRecordsCompanion toCompanion(bool nullToAbsent) {
    return DownloadRecordsCompanion(
      sourceKey: Value(sourceKey),
      kind: Value(kind),
      filePath: filePath == null && nullToAbsent
          ? const Value.absent()
          : Value(filePath),
      totalBytes: totalBytes == null && nullToAbsent
          ? const Value.absent()
          : Value(totalBytes),
      validator: validator == null && nullToAbsent
          ? const Value.absent()
          : Value(validator),
      lastUsedAt: Value(lastUsedAt),
    );
  }

  factory DownloadRecordRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DownloadRecordRow(
      sourceKey: serializer.fromJson<String>(json['sourceKey']),
      kind: serializer.fromJson<String>(json['kind']),
      filePath: serializer.fromJson<String?>(json['filePath']),
      totalBytes: serializer.fromJson<int?>(json['totalBytes']),
      validator: serializer.fromJson<String?>(json['validator']),
      lastUsedAt: serializer.fromJson<int>(json['lastUsedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'sourceKey': serializer.toJson<String>(sourceKey),
      'kind': serializer.toJson<String>(kind),
      'filePath': serializer.toJson<String?>(filePath),
      'totalBytes': serializer.toJson<int?>(totalBytes),
      'validator': serializer.toJson<String?>(validator),
      'lastUsedAt': serializer.toJson<int>(lastUsedAt),
    };
  }

  DownloadRecordRow copyWith({
    String? sourceKey,
    String? kind,
    Value<String?> filePath = const Value.absent(),
    Value<int?> totalBytes = const Value.absent(),
    Value<String?> validator = const Value.absent(),
    int? lastUsedAt,
  }) => DownloadRecordRow(
    sourceKey: sourceKey ?? this.sourceKey,
    kind: kind ?? this.kind,
    filePath: filePath.present ? filePath.value : this.filePath,
    totalBytes: totalBytes.present ? totalBytes.value : this.totalBytes,
    validator: validator.present ? validator.value : this.validator,
    lastUsedAt: lastUsedAt ?? this.lastUsedAt,
  );
  DownloadRecordRow copyWithCompanion(DownloadRecordsCompanion data) {
    return DownloadRecordRow(
      sourceKey: data.sourceKey.present ? data.sourceKey.value : this.sourceKey,
      kind: data.kind.present ? data.kind.value : this.kind,
      filePath: data.filePath.present ? data.filePath.value : this.filePath,
      totalBytes: data.totalBytes.present
          ? data.totalBytes.value
          : this.totalBytes,
      validator: data.validator.present ? data.validator.value : this.validator,
      lastUsedAt: data.lastUsedAt.present
          ? data.lastUsedAt.value
          : this.lastUsedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DownloadRecordRow(')
          ..write('sourceKey: $sourceKey, ')
          ..write('kind: $kind, ')
          ..write('filePath: $filePath, ')
          ..write('totalBytes: $totalBytes, ')
          ..write('validator: $validator, ')
          ..write('lastUsedAt: $lastUsedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(sourceKey, kind, filePath, totalBytes, validator, lastUsedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DownloadRecordRow &&
          other.sourceKey == this.sourceKey &&
          other.kind == this.kind &&
          other.filePath == this.filePath &&
          other.totalBytes == this.totalBytes &&
          other.validator == this.validator &&
          other.lastUsedAt == this.lastUsedAt);
}

class DownloadRecordsCompanion extends UpdateCompanion<DownloadRecordRow> {
  final Value<String> sourceKey;
  final Value<String> kind;
  final Value<String?> filePath;
  final Value<int?> totalBytes;
  final Value<String?> validator;
  final Value<int> lastUsedAt;
  final Value<int> rowid;
  const DownloadRecordsCompanion({
    this.sourceKey = const Value.absent(),
    this.kind = const Value.absent(),
    this.filePath = const Value.absent(),
    this.totalBytes = const Value.absent(),
    this.validator = const Value.absent(),
    this.lastUsedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DownloadRecordsCompanion.insert({
    required String sourceKey,
    required String kind,
    this.filePath = const Value.absent(),
    this.totalBytes = const Value.absent(),
    this.validator = const Value.absent(),
    required int lastUsedAt,
    this.rowid = const Value.absent(),
  }) : sourceKey = Value(sourceKey),
       kind = Value(kind),
       lastUsedAt = Value(lastUsedAt);
  static Insertable<DownloadRecordRow> custom({
    Expression<String>? sourceKey,
    Expression<String>? kind,
    Expression<String>? filePath,
    Expression<int>? totalBytes,
    Expression<String>? validator,
    Expression<int>? lastUsedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (sourceKey != null) 'source_key': sourceKey,
      if (kind != null) 'kind': kind,
      if (filePath != null) 'file_path': filePath,
      if (totalBytes != null) 'total_bytes': totalBytes,
      if (validator != null) 'validator': validator,
      if (lastUsedAt != null) 'last_used_at': lastUsedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DownloadRecordsCompanion copyWith({
    Value<String>? sourceKey,
    Value<String>? kind,
    Value<String?>? filePath,
    Value<int?>? totalBytes,
    Value<String?>? validator,
    Value<int>? lastUsedAt,
    Value<int>? rowid,
  }) {
    return DownloadRecordsCompanion(
      sourceKey: sourceKey ?? this.sourceKey,
      kind: kind ?? this.kind,
      filePath: filePath ?? this.filePath,
      totalBytes: totalBytes ?? this.totalBytes,
      validator: validator ?? this.validator,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (sourceKey.present) {
      map['source_key'] = Variable<String>(sourceKey.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (filePath.present) {
      map['file_path'] = Variable<String>(filePath.value);
    }
    if (totalBytes.present) {
      map['total_bytes'] = Variable<int>(totalBytes.value);
    }
    if (validator.present) {
      map['validator'] = Variable<String>(validator.value);
    }
    if (lastUsedAt.present) {
      map['last_used_at'] = Variable<int>(lastUsedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DownloadRecordsCompanion(')
          ..write('sourceKey: $sourceKey, ')
          ..write('kind: $kind, ')
          ..write('filePath: $filePath, ')
          ..write('totalBytes: $totalBytes, ')
          ..write('validator: $validator, ')
          ..write('lastUsedAt: $lastUsedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TorrentResumeTable extends TorrentResume
    with TableInfo<$TorrentResumeTable, TorrentResumeData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TorrentResumeTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _infoHashMeta = const VerificationMeta(
    'infoHash',
  );
  @override
  late final GeneratedColumn<String> infoHash = GeneratedColumn<String>(
    'info_hash',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dataMeta = const VerificationMeta('data');
  @override
  late final GeneratedColumn<Uint8List> data = GeneratedColumn<Uint8List>(
    'data',
    aliasedName,
    false,
    type: DriftSqlType.blob,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [infoHash, data, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'torrent_resume';
  @override
  VerificationContext validateIntegrity(
    Insertable<TorrentResumeData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('info_hash')) {
      context.handle(
        _infoHashMeta,
        infoHash.isAcceptableOrUnknown(data['info_hash']!, _infoHashMeta),
      );
    } else if (isInserting) {
      context.missing(_infoHashMeta);
    }
    if (data.containsKey('data')) {
      context.handle(
        _dataMeta,
        this.data.isAcceptableOrUnknown(data['data']!, _dataMeta),
      );
    } else if (isInserting) {
      context.missing(_dataMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {infoHash};
  @override
  TorrentResumeData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TorrentResumeData(
      infoHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}info_hash'],
      )!,
      data: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}data'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $TorrentResumeTable createAlias(String alias) {
    return $TorrentResumeTable(attachedDatabase, alias);
  }
}

class TorrentResumeData extends DataClass
    implements Insertable<TorrentResumeData> {
  final String infoHash;
  final Uint8List data;
  final int updatedAt;
  const TorrentResumeData({
    required this.infoHash,
    required this.data,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['info_hash'] = Variable<String>(infoHash);
    map['data'] = Variable<Uint8List>(data);
    map['updated_at'] = Variable<int>(updatedAt);
    return map;
  }

  TorrentResumeCompanion toCompanion(bool nullToAbsent) {
    return TorrentResumeCompanion(
      infoHash: Value(infoHash),
      data: Value(data),
      updatedAt: Value(updatedAt),
    );
  }

  factory TorrentResumeData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TorrentResumeData(
      infoHash: serializer.fromJson<String>(json['infoHash']),
      data: serializer.fromJson<Uint8List>(json['data']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'infoHash': serializer.toJson<String>(infoHash),
      'data': serializer.toJson<Uint8List>(data),
      'updatedAt': serializer.toJson<int>(updatedAt),
    };
  }

  TorrentResumeData copyWith({
    String? infoHash,
    Uint8List? data,
    int? updatedAt,
  }) => TorrentResumeData(
    infoHash: infoHash ?? this.infoHash,
    data: data ?? this.data,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  TorrentResumeData copyWithCompanion(TorrentResumeCompanion data) {
    return TorrentResumeData(
      infoHash: data.infoHash.present ? data.infoHash.value : this.infoHash,
      data: data.data.present ? data.data.value : this.data,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TorrentResumeData(')
          ..write('infoHash: $infoHash, ')
          ..write('data: $data, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(infoHash, $driftBlobEquality.hash(data), updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TorrentResumeData &&
          other.infoHash == this.infoHash &&
          $driftBlobEquality.equals(other.data, this.data) &&
          other.updatedAt == this.updatedAt);
}

class TorrentResumeCompanion extends UpdateCompanion<TorrentResumeData> {
  final Value<String> infoHash;
  final Value<Uint8List> data;
  final Value<int> updatedAt;
  final Value<int> rowid;
  const TorrentResumeCompanion({
    this.infoHash = const Value.absent(),
    this.data = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TorrentResumeCompanion.insert({
    required String infoHash,
    required Uint8List data,
    required int updatedAt,
    this.rowid = const Value.absent(),
  }) : infoHash = Value(infoHash),
       data = Value(data),
       updatedAt = Value(updatedAt);
  static Insertable<TorrentResumeData> custom({
    Expression<String>? infoHash,
    Expression<Uint8List>? data,
    Expression<int>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (infoHash != null) 'info_hash': infoHash,
      if (data != null) 'data': data,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TorrentResumeCompanion copyWith({
    Value<String>? infoHash,
    Value<Uint8List>? data,
    Value<int>? updatedAt,
    Value<int>? rowid,
  }) {
    return TorrentResumeCompanion(
      infoHash: infoHash ?? this.infoHash,
      data: data ?? this.data,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (infoHash.present) {
      map['info_hash'] = Variable<String>(infoHash.value);
    }
    if (data.present) {
      map['data'] = Variable<Uint8List>(data.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TorrentResumeCompanion(')
          ..write('infoHash: $infoHash, ')
          ..write('data: $data, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $PlaybackProgressTable playbackProgress = $PlaybackProgressTable(
    this,
  );
  late final $FavouritesTable favourites = $FavouritesTable(this);
  late final $NextUpTable nextUp = $NextUpTable(this);
  late final $DownloadRecordsTable downloadRecords = $DownloadRecordsTable(
    this,
  );
  late final $TorrentResumeTable torrentResume = $TorrentResumeTable(this);
  late final Index playbackProgressUpdatedAt = Index(
    'playback_progress_updated_at',
    'CREATE INDEX playback_progress_updated_at ON playback_progress (updated_at)',
  );
  late final Index downloadRecordsLastUsedAt = Index(
    'download_records_last_used_at',
    'CREATE INDEX download_records_last_used_at ON download_records (last_used_at)',
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    playbackProgress,
    favourites,
    nextUp,
    downloadRecords,
    torrentResume,
    playbackProgressUpdatedAt,
    downloadRecordsLastUsedAt,
  ];
}

typedef $$PlaybackProgressTableCreateCompanionBuilder =
    PlaybackProgressCompanion Function({
      required String mediaId,
      required int positionMs,
      required int durationMs,
      required int updatedAt,
      required bool completed,
      Value<String?> audioTrackId,
      Value<String?> subtitleTrackId,
      Value<String?> lastPlayedSourceKey,
      Value<int> rowid,
    });
typedef $$PlaybackProgressTableUpdateCompanionBuilder =
    PlaybackProgressCompanion Function({
      Value<String> mediaId,
      Value<int> positionMs,
      Value<int> durationMs,
      Value<int> updatedAt,
      Value<bool> completed,
      Value<String?> audioTrackId,
      Value<String?> subtitleTrackId,
      Value<String?> lastPlayedSourceKey,
      Value<int> rowid,
    });

class $$PlaybackProgressTableFilterComposer
    extends Composer<_$AppDatabase, $PlaybackProgressTable> {
  $$PlaybackProgressTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get mediaId => $composableBuilder(
    column: $table.mediaId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get positionMs => $composableBuilder(
    column: $table.positionMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get completed => $composableBuilder(
    column: $table.completed,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get audioTrackId => $composableBuilder(
    column: $table.audioTrackId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get subtitleTrackId => $composableBuilder(
    column: $table.subtitleTrackId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastPlayedSourceKey => $composableBuilder(
    column: $table.lastPlayedSourceKey,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PlaybackProgressTableOrderingComposer
    extends Composer<_$AppDatabase, $PlaybackProgressTable> {
  $$PlaybackProgressTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get mediaId => $composableBuilder(
    column: $table.mediaId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get positionMs => $composableBuilder(
    column: $table.positionMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get completed => $composableBuilder(
    column: $table.completed,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get audioTrackId => $composableBuilder(
    column: $table.audioTrackId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get subtitleTrackId => $composableBuilder(
    column: $table.subtitleTrackId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastPlayedSourceKey => $composableBuilder(
    column: $table.lastPlayedSourceKey,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PlaybackProgressTableAnnotationComposer
    extends Composer<_$AppDatabase, $PlaybackProgressTable> {
  $$PlaybackProgressTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get mediaId =>
      $composableBuilder(column: $table.mediaId, builder: (column) => column);

  GeneratedColumn<int> get positionMs => $composableBuilder(
    column: $table.positionMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<bool> get completed =>
      $composableBuilder(column: $table.completed, builder: (column) => column);

  GeneratedColumn<String> get audioTrackId => $composableBuilder(
    column: $table.audioTrackId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get subtitleTrackId => $composableBuilder(
    column: $table.subtitleTrackId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastPlayedSourceKey => $composableBuilder(
    column: $table.lastPlayedSourceKey,
    builder: (column) => column,
  );
}

class $$PlaybackProgressTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PlaybackProgressTable,
          PlaybackProgressData,
          $$PlaybackProgressTableFilterComposer,
          $$PlaybackProgressTableOrderingComposer,
          $$PlaybackProgressTableAnnotationComposer,
          $$PlaybackProgressTableCreateCompanionBuilder,
          $$PlaybackProgressTableUpdateCompanionBuilder,
          (
            PlaybackProgressData,
            BaseReferences<
              _$AppDatabase,
              $PlaybackProgressTable,
              PlaybackProgressData
            >,
          ),
          PlaybackProgressData,
          PrefetchHooks Function()
        > {
  $$PlaybackProgressTableTableManager(
    _$AppDatabase db,
    $PlaybackProgressTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PlaybackProgressTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PlaybackProgressTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PlaybackProgressTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> mediaId = const Value.absent(),
                Value<int> positionMs = const Value.absent(),
                Value<int> durationMs = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<bool> completed = const Value.absent(),
                Value<String?> audioTrackId = const Value.absent(),
                Value<String?> subtitleTrackId = const Value.absent(),
                Value<String?> lastPlayedSourceKey = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PlaybackProgressCompanion(
                mediaId: mediaId,
                positionMs: positionMs,
                durationMs: durationMs,
                updatedAt: updatedAt,
                completed: completed,
                audioTrackId: audioTrackId,
                subtitleTrackId: subtitleTrackId,
                lastPlayedSourceKey: lastPlayedSourceKey,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String mediaId,
                required int positionMs,
                required int durationMs,
                required int updatedAt,
                required bool completed,
                Value<String?> audioTrackId = const Value.absent(),
                Value<String?> subtitleTrackId = const Value.absent(),
                Value<String?> lastPlayedSourceKey = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PlaybackProgressCompanion.insert(
                mediaId: mediaId,
                positionMs: positionMs,
                durationMs: durationMs,
                updatedAt: updatedAt,
                completed: completed,
                audioTrackId: audioTrackId,
                subtitleTrackId: subtitleTrackId,
                lastPlayedSourceKey: lastPlayedSourceKey,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$PlaybackProgressTable, PlaybackProgressData>(
                    table,
                  ),
                  BaseReferences<
                    _$AppDatabase,
                    $PlaybackProgressTable,
                    PlaybackProgressData
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PlaybackProgressTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PlaybackProgressTable,
      PlaybackProgressData,
      $$PlaybackProgressTableFilterComposer,
      $$PlaybackProgressTableOrderingComposer,
      $$PlaybackProgressTableAnnotationComposer,
      $$PlaybackProgressTableCreateCompanionBuilder,
      $$PlaybackProgressTableUpdateCompanionBuilder,
      (
        PlaybackProgressData,
        BaseReferences<
          _$AppDatabase,
          $PlaybackProgressTable,
          PlaybackProgressData
        >,
      ),
      PlaybackProgressData,
      PrefetchHooks Function()
    >;
typedef $$FavouritesTableCreateCompanionBuilder = FavouritesCompanion Function({
  required String mediaId,
  required int addedAt,
  Value<int> rowid,
});
typedef $$FavouritesTableUpdateCompanionBuilder = FavouritesCompanion Function({
  Value<String> mediaId,
  Value<int> addedAt,
  Value<int> rowid,
});

class $$FavouritesTableFilterComposer
    extends Composer<_$AppDatabase, $FavouritesTable> {
  $$FavouritesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get mediaId => $composableBuilder(
    column: $table.mediaId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$FavouritesTableOrderingComposer
    extends Composer<_$AppDatabase, $FavouritesTable> {
  $$FavouritesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get mediaId => $composableBuilder(
    column: $table.mediaId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$FavouritesTableAnnotationComposer
    extends Composer<_$AppDatabase, $FavouritesTable> {
  $$FavouritesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get mediaId =>
      $composableBuilder(column: $table.mediaId, builder: (column) => column);

  GeneratedColumn<int> get addedAt =>
      $composableBuilder(column: $table.addedAt, builder: (column) => column);
}

class $$FavouritesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $FavouritesTable,
          Favourite,
          $$FavouritesTableFilterComposer,
          $$FavouritesTableOrderingComposer,
          $$FavouritesTableAnnotationComposer,
          $$FavouritesTableCreateCompanionBuilder,
          $$FavouritesTableUpdateCompanionBuilder,
          (
            Favourite,
            BaseReferences<_$AppDatabase, $FavouritesTable, Favourite>,
          ),
          Favourite,
          PrefetchHooks Function()
        > {
  $$FavouritesTableTableManager(_$AppDatabase db, $FavouritesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FavouritesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FavouritesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FavouritesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> mediaId = const Value.absent(),
                Value<int> addedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FavouritesCompanion(
                mediaId: mediaId,
                addedAt: addedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String mediaId,
                required int addedAt,
                Value<int> rowid = const Value.absent(),
              }) => FavouritesCompanion.insert(
                mediaId: mediaId,
                addedAt: addedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$FavouritesTable, Favourite>(table),
                  BaseReferences<_$AppDatabase, $FavouritesTable, Favourite>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$FavouritesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $FavouritesTable,
      Favourite,
      $$FavouritesTableFilterComposer,
      $$FavouritesTableOrderingComposer,
      $$FavouritesTableAnnotationComposer,
      $$FavouritesTableCreateCompanionBuilder,
      $$FavouritesTableUpdateCompanionBuilder,
      (Favourite, BaseReferences<_$AppDatabase, $FavouritesTable, Favourite>),
      Favourite,
      PrefetchHooks Function()
    >;
typedef $$NextUpTableCreateCompanionBuilder = NextUpCompanion Function({
  required String seriesId,
  required String mediaId,
  required int season,
  required int episode,
  required int updatedAt,
  Value<int> rowid,
});
typedef $$NextUpTableUpdateCompanionBuilder = NextUpCompanion Function({
  Value<String> seriesId,
  Value<String> mediaId,
  Value<int> season,
  Value<int> episode,
  Value<int> updatedAt,
  Value<int> rowid,
});

class $$NextUpTableFilterComposer
    extends Composer<_$AppDatabase, $NextUpTable> {
  $$NextUpTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get seriesId => $composableBuilder(
    column: $table.seriesId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mediaId => $composableBuilder(
    column: $table.mediaId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get season => $composableBuilder(
    column: $table.season,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get episode => $composableBuilder(
    column: $table.episode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$NextUpTableOrderingComposer
    extends Composer<_$AppDatabase, $NextUpTable> {
  $$NextUpTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get seriesId => $composableBuilder(
    column: $table.seriesId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mediaId => $composableBuilder(
    column: $table.mediaId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get season => $composableBuilder(
    column: $table.season,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get episode => $composableBuilder(
    column: $table.episode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$NextUpTableAnnotationComposer
    extends Composer<_$AppDatabase, $NextUpTable> {
  $$NextUpTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get seriesId =>
      $composableBuilder(column: $table.seriesId, builder: (column) => column);

  GeneratedColumn<String> get mediaId =>
      $composableBuilder(column: $table.mediaId, builder: (column) => column);

  GeneratedColumn<int> get season =>
      $composableBuilder(column: $table.season, builder: (column) => column);

  GeneratedColumn<int> get episode =>
      $composableBuilder(column: $table.episode, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$NextUpTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $NextUpTable,
          NextUpData,
          $$NextUpTableFilterComposer,
          $$NextUpTableOrderingComposer,
          $$NextUpTableAnnotationComposer,
          $$NextUpTableCreateCompanionBuilder,
          $$NextUpTableUpdateCompanionBuilder,
          (NextUpData, BaseReferences<_$AppDatabase, $NextUpTable, NextUpData>),
          NextUpData,
          PrefetchHooks Function()
        > {
  $$NextUpTableTableManager(_$AppDatabase db, $NextUpTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$NextUpTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$NextUpTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$NextUpTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> seriesId = const Value.absent(),
                Value<String> mediaId = const Value.absent(),
                Value<int> season = const Value.absent(),
                Value<int> episode = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => NextUpCompanion(
                seriesId: seriesId,
                mediaId: mediaId,
                season: season,
                episode: episode,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String seriesId,
                required String mediaId,
                required int season,
                required int episode,
                required int updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => NextUpCompanion.insert(
                seriesId: seriesId,
                mediaId: mediaId,
                season: season,
                episode: episode,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$NextUpTable, NextUpData>(table),
                  BaseReferences<_$AppDatabase, $NextUpTable, NextUpData>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$NextUpTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $NextUpTable,
      NextUpData,
      $$NextUpTableFilterComposer,
      $$NextUpTableOrderingComposer,
      $$NextUpTableAnnotationComposer,
      $$NextUpTableCreateCompanionBuilder,
      $$NextUpTableUpdateCompanionBuilder,
      (NextUpData, BaseReferences<_$AppDatabase, $NextUpTable, NextUpData>),
      NextUpData,
      PrefetchHooks Function()
    >;
typedef $$DownloadRecordsTableCreateCompanionBuilder =
    DownloadRecordsCompanion Function({
      required String sourceKey,
      required String kind,
      Value<String?> filePath,
      Value<int?> totalBytes,
      Value<String?> validator,
      required int lastUsedAt,
      Value<int> rowid,
    });
typedef $$DownloadRecordsTableUpdateCompanionBuilder =
    DownloadRecordsCompanion Function({
      Value<String> sourceKey,
      Value<String> kind,
      Value<String?> filePath,
      Value<int?> totalBytes,
      Value<String?> validator,
      Value<int> lastUsedAt,
      Value<int> rowid,
    });

class $$DownloadRecordsTableFilterComposer
    extends Composer<_$AppDatabase, $DownloadRecordsTable> {
  $$DownloadRecordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get sourceKey => $composableBuilder(
    column: $table.sourceKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get filePath => $composableBuilder(
    column: $table.filePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get totalBytes => $composableBuilder(
    column: $table.totalBytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get validator => $composableBuilder(
    column: $table.validator,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastUsedAt => $composableBuilder(
    column: $table.lastUsedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DownloadRecordsTableOrderingComposer
    extends Composer<_$AppDatabase, $DownloadRecordsTable> {
  $$DownloadRecordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get sourceKey => $composableBuilder(
    column: $table.sourceKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get filePath => $composableBuilder(
    column: $table.filePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get totalBytes => $composableBuilder(
    column: $table.totalBytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get validator => $composableBuilder(
    column: $table.validator,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastUsedAt => $composableBuilder(
    column: $table.lastUsedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DownloadRecordsTableAnnotationComposer
    extends Composer<_$AppDatabase, $DownloadRecordsTable> {
  $$DownloadRecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get sourceKey =>
      $composableBuilder(column: $table.sourceKey, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get filePath =>
      $composableBuilder(column: $table.filePath, builder: (column) => column);

  GeneratedColumn<int> get totalBytes => $composableBuilder(
    column: $table.totalBytes,
    builder: (column) => column,
  );

  GeneratedColumn<String> get validator =>
      $composableBuilder(column: $table.validator, builder: (column) => column);

  GeneratedColumn<int> get lastUsedAt => $composableBuilder(
    column: $table.lastUsedAt,
    builder: (column) => column,
  );
}

class $$DownloadRecordsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $DownloadRecordsTable,
          DownloadRecordRow,
          $$DownloadRecordsTableFilterComposer,
          $$DownloadRecordsTableOrderingComposer,
          $$DownloadRecordsTableAnnotationComposer,
          $$DownloadRecordsTableCreateCompanionBuilder,
          $$DownloadRecordsTableUpdateCompanionBuilder,
          (
            DownloadRecordRow,
            BaseReferences<
              _$AppDatabase,
              $DownloadRecordsTable,
              DownloadRecordRow
            >,
          ),
          DownloadRecordRow,
          PrefetchHooks Function()
        > {
  $$DownloadRecordsTableTableManager(
    _$AppDatabase db,
    $DownloadRecordsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DownloadRecordsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DownloadRecordsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DownloadRecordsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> sourceKey = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String?> filePath = const Value.absent(),
                Value<int?> totalBytes = const Value.absent(),
                Value<String?> validator = const Value.absent(),
                Value<int> lastUsedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DownloadRecordsCompanion(
                sourceKey: sourceKey,
                kind: kind,
                filePath: filePath,
                totalBytes: totalBytes,
                validator: validator,
                lastUsedAt: lastUsedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String sourceKey,
                required String kind,
                Value<String?> filePath = const Value.absent(),
                Value<int?> totalBytes = const Value.absent(),
                Value<String?> validator = const Value.absent(),
                required int lastUsedAt,
                Value<int> rowid = const Value.absent(),
              }) => DownloadRecordsCompanion.insert(
                sourceKey: sourceKey,
                kind: kind,
                filePath: filePath,
                totalBytes: totalBytes,
                validator: validator,
                lastUsedAt: lastUsedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$DownloadRecordsTable, DownloadRecordRow>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $DownloadRecordsTable,
                    DownloadRecordRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DownloadRecordsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $DownloadRecordsTable,
      DownloadRecordRow,
      $$DownloadRecordsTableFilterComposer,
      $$DownloadRecordsTableOrderingComposer,
      $$DownloadRecordsTableAnnotationComposer,
      $$DownloadRecordsTableCreateCompanionBuilder,
      $$DownloadRecordsTableUpdateCompanionBuilder,
      (
        DownloadRecordRow,
        BaseReferences<_$AppDatabase, $DownloadRecordsTable, DownloadRecordRow>,
      ),
      DownloadRecordRow,
      PrefetchHooks Function()
    >;
typedef $$TorrentResumeTableCreateCompanionBuilder =
    TorrentResumeCompanion Function({
      required String infoHash,
      required Uint8List data,
      required int updatedAt,
      Value<int> rowid,
    });
typedef $$TorrentResumeTableUpdateCompanionBuilder =
    TorrentResumeCompanion Function({
      Value<String> infoHash,
      Value<Uint8List> data,
      Value<int> updatedAt,
      Value<int> rowid,
    });

class $$TorrentResumeTableFilterComposer
    extends Composer<_$AppDatabase, $TorrentResumeTable> {
  $$TorrentResumeTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get infoHash => $composableBuilder(
    column: $table.infoHash,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get data => $composableBuilder(
    column: $table.data,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$TorrentResumeTableOrderingComposer
    extends Composer<_$AppDatabase, $TorrentResumeTable> {
  $$TorrentResumeTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get infoHash => $composableBuilder(
    column: $table.infoHash,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get data => $composableBuilder(
    column: $table.data,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TorrentResumeTableAnnotationComposer
    extends Composer<_$AppDatabase, $TorrentResumeTable> {
  $$TorrentResumeTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get infoHash =>
      $composableBuilder(column: $table.infoHash, builder: (column) => column);

  GeneratedColumn<Uint8List> get data =>
      $composableBuilder(column: $table.data, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$TorrentResumeTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TorrentResumeTable,
          TorrentResumeData,
          $$TorrentResumeTableFilterComposer,
          $$TorrentResumeTableOrderingComposer,
          $$TorrentResumeTableAnnotationComposer,
          $$TorrentResumeTableCreateCompanionBuilder,
          $$TorrentResumeTableUpdateCompanionBuilder,
          (
            TorrentResumeData,
            BaseReferences<
              _$AppDatabase,
              $TorrentResumeTable,
              TorrentResumeData
            >,
          ),
          TorrentResumeData,
          PrefetchHooks Function()
        > {
  $$TorrentResumeTableTableManager(_$AppDatabase db, $TorrentResumeTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TorrentResumeTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TorrentResumeTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TorrentResumeTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> infoHash = const Value.absent(),
                Value<Uint8List> data = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TorrentResumeCompanion(
                infoHash: infoHash,
                data: data,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String infoHash,
                required Uint8List data,
                required int updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => TorrentResumeCompanion.insert(
                infoHash: infoHash,
                data: data,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$TorrentResumeTable, TorrentResumeData>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $TorrentResumeTable,
                    TorrentResumeData
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$TorrentResumeTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TorrentResumeTable,
      TorrentResumeData,
      $$TorrentResumeTableFilterComposer,
      $$TorrentResumeTableOrderingComposer,
      $$TorrentResumeTableAnnotationComposer,
      $$TorrentResumeTableCreateCompanionBuilder,
      $$TorrentResumeTableUpdateCompanionBuilder,
      (
        TorrentResumeData,
        BaseReferences<_$AppDatabase, $TorrentResumeTable, TorrentResumeData>,
      ),
      TorrentResumeData,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$PlaybackProgressTableTableManager get playbackProgress =>
      $$PlaybackProgressTableTableManager(_db, _db.playbackProgress);
  $$FavouritesTableTableManager get favourites =>
      $$FavouritesTableTableManager(_db, _db.favourites);
  $$NextUpTableTableManager get nextUp =>
      $$NextUpTableTableManager(_db, _db.nextUp);
  $$DownloadRecordsTableTableManager get downloadRecords =>
      $$DownloadRecordsTableTableManager(_db, _db.downloadRecords);
  $$TorrentResumeTableTableManager get torrentResume =>
      $$TorrentResumeTableTableManager(_db, _db.torrentResume);
}
