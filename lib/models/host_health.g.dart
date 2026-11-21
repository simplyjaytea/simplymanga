// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'host_health.dart';

// **************************************************************************
// IsarCollectionGenerator
// **************************************************************************

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types, experimental_member_use

extension GetHostHealthCollection on Isar {
  IsarCollection<HostHealth> get hostHealths => this.collection();
}

const HostHealthSchema = CollectionSchema(
  name: r'Host Health',
  id: 5513060074199184480,
  properties: {
    r'challenges': PropertySchema(
      id: 0,
      name: r'challenges',
      type: IsarType.long,
    ),
    r'host': PropertySchema(id: 1, name: r'host', type: IsarType.string),
    r'latencyEwmaMs': PropertySchema(
      id: 2,
      name: r'latencyEwmaMs',
      type: IsarType.double,
    ),
    r'samples': PropertySchema(id: 3, name: r'samples', type: IsarType.long),
    r'successEwma': PropertySchema(
      id: 4,
      name: r'successEwma',
      type: IsarType.double,
    ),
    r'updatedAt': PropertySchema(
      id: 5,
      name: r'updatedAt',
      type: IsarType.long,
    ),
  },

  estimateSize: _hostHealthEstimateSize,
  serialize: _hostHealthSerialize,
  deserialize: _hostHealthDeserialize,
  deserializeProp: _hostHealthDeserializeProp,
  idName: r'id',
  indexes: {},
  links: {},
  embeddedSchemas: {},

  getId: _hostHealthGetId,
  getLinks: _hostHealthGetLinks,
  attach: _hostHealthAttach,
  version: '3.4.1',
);

int _hostHealthEstimateSize(
  HostHealth object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  bytesCount += 3 + object.host.length * 3;
  return bytesCount;
}

void _hostHealthSerialize(
  HostHealth object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeLong(offsets[0], object.challenges);
  writer.writeString(offsets[1], object.host);
  writer.writeDouble(offsets[2], object.latencyEwmaMs);
  writer.writeLong(offsets[3], object.samples);
  writer.writeDouble(offsets[4], object.successEwma);
  writer.writeLong(offsets[5], object.updatedAt);
}

HostHealth _hostHealthDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = HostHealth();
  object.challenges = reader.readLong(offsets[0]);
  object.host = reader.readString(offsets[1]);
  object.latencyEwmaMs = reader.readDouble(offsets[2]);
  object.samples = reader.readLong(offsets[3]);
  object.successEwma = reader.readDouble(offsets[4]);
  object.updatedAt = reader.readLong(offsets[5]);
  return object;
}

P _hostHealthDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readLong(offset)) as P;
    case 1:
      return (reader.readString(offset)) as P;
    case 2:
      return (reader.readDouble(offset)) as P;
    case 3:
      return (reader.readLong(offset)) as P;
    case 4:
      return (reader.readDouble(offset)) as P;
    case 5:
      return (reader.readLong(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _hostHealthGetId(HostHealth object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _hostHealthGetLinks(HostHealth object) {
  return [];
}

void _hostHealthAttach(IsarCollection<dynamic> col, Id id, HostHealth object) {}

extension HostHealthQueryWhereSort
    on QueryBuilder<HostHealth, HostHealth, QWhere> {
  QueryBuilder<HostHealth, HostHealth, QAfterWhere> anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }
}

extension HostHealthQueryWhere
    on QueryBuilder<HostHealth, HostHealth, QWhereClause> {
  QueryBuilder<HostHealth, HostHealth, QAfterWhereClause> idEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(lower: id, upper: id));
    });
  }

  QueryBuilder<HostHealth, HostHealth, QAfterWhereClause> idNotEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            )
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            );
      } else {
        return query
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            )
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            );
      }
    });
  }

  QueryBuilder<HostHealth, HostHealth, QAfterWhereClause> idGreaterThan(
    Id id, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: id, includeLower: include),
      );
    });
  }

  QueryBuilder<HostHealth, HostHealth, QAfterWhereClause> idLessThan(
    Id id, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: id, includeUpper: include),
      );
    });
  }

  QueryBuilder<HostHealth, HostHealth, QAfterWhereClause> idBetween(
    Id lowerId,
    Id upperId, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.between(
          lower: lowerId,
          includeLower: includeLower,
          upper: upperId,
          includeUpper: includeUpper,
        ),
      );
    });
  }
}

extension HostHealthQueryFilter
    on QueryBuilder<HostHealth, HostHealth, QFilterCondition> {
  QueryBuilder<HostHealth, HostHealth, QAfterFilterCondition> challengesEqualTo(
    int value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'challenges', value: value),
      );
    });
  }

  QueryBuilder<HostHealth, HostHealth, QAfterFilterCondition>
  challengesGreaterThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'challenges',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<HostHealth, HostHealth, QAfterFilterCondition>
  challengesLessThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'challenges',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<HostHealth, HostHealth, QAfterFilterCondition> challengesBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'challenges',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<HostHealth, HostHealth, QAfterFilterCondition> hostEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'host',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<HostHealth, HostHealth, QAfterFilterCondition> hostGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'host',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<HostHealth, HostHealth, QAfterFilterCondition> hostLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'host',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<HostHealth, HostHealth, QAfterFilterCondition> hostBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'host',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<HostHealth, HostHealth, QAfterFilterCondition> hostStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'host',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<HostHealth, HostHealth, QAfterFilterCondition> hostEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'host',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<HostHealth, HostHealth, QAfterFilterCondition> hostContains(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'host',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<HostHealth, HostHealth, QAfterFilterCondition> hostMatches(
    String pattern, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'host',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<HostHealth, HostHealth, QAfterFilterCondition> hostIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'host', value: ''),
      );
    });
  }

  QueryBuilder<HostHealth, HostHealth, QAfterFilterCondition> hostIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'host', value: ''),
      );
    });
  }

  QueryBuilder<HostHealth, HostHealth, QAfterFilterCondition> idEqualTo(
    Id value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'id', value: value),
      );
    });
  }

  QueryBuilder<HostHealth, HostHealth, QAfterFilterCondition> idGreaterThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'id',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<HostHealth, HostHealth, QAfterFilterCondition> idLessThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'id',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<HostHealth, HostHealth, QAfterFilterCondition> idBetween(
    Id lower,
    Id upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'id',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<HostHealth, HostHealth, QAfterFilterCondition>
  latencyEwmaMsEqualTo(double value, {double epsilon = Query.epsilon}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'latencyEwmaMs',
          value: value,

          epsilon: epsilon,
        ),
      );
    });
  }

  QueryBuilder<HostHealth, HostHealth, QAfterFilterCondition>
  latencyEwmaMsGreaterThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'latencyEwmaMs',
          value: value,

          epsilon: epsilon,
        ),
      );
    });
  }

  QueryBuilder<HostHealth, HostHealth, QAfterFilterCondition>
  latencyEwmaMsLessThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'latencyEwmaMs',
          value: value,

          epsilon: epsilon,
        ),
      );
    });
  }

  QueryBuilder<HostHealth, HostHealth, QAfterFilterCondition>
  latencyEwmaMsBetween(
    double lower,
    double upper, {
    bool includeLower = true,
    bool includeUpper = true,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'latencyEwmaMs',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,

          epsilon: epsilon,
        ),
      );
    });
  }

  QueryBuilder<HostHealth, HostHealth, QAfterFilterCondition> samplesEqualTo(
    int value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'samples', value: value),
      );
    });
  }

  QueryBuilder<HostHealth, HostHealth, QAfterFilterCondition>
  samplesGreaterThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'samples',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<HostHealth, HostHealth, QAfterFilterCondition> samplesLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'samples',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<HostHealth, HostHealth, QAfterFilterCondition> samplesBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'samples',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<HostHealth, HostHealth, QAfterFilterCondition>
  successEwmaEqualTo(double value, {double epsilon = Query.epsilon}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'successEwma',
          value: value,

          epsilon: epsilon,
        ),
      );
    });
  }

  QueryBuilder<HostHealth, HostHealth, QAfterFilterCondition>
  successEwmaGreaterThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'successEwma',
          value: value,

          epsilon: epsilon,
        ),
      );
    });
  }

  QueryBuilder<HostHealth, HostHealth, QAfterFilterCondition>
  successEwmaLessThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'successEwma',
          value: value,

          epsilon: epsilon,
        ),
      );
    });
  }

  QueryBuilder<HostHealth, HostHealth, QAfterFilterCondition>
  successEwmaBetween(
    double lower,
    double upper, {
    bool includeLower = true,
    bool includeUpper = true,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'successEwma',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,

          epsilon: epsilon,
        ),
      );
    });
  }

  QueryBuilder<HostHealth, HostHealth, QAfterFilterCondition> updatedAtEqualTo(
    int value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'updatedAt', value: value),
      );
    });
  }

  QueryBuilder<HostHealth, HostHealth, QAfterFilterCondition>
  updatedAtGreaterThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'updatedAt',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<HostHealth, HostHealth, QAfterFilterCondition> updatedAtLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'updatedAt',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<HostHealth, HostHealth, QAfterFilterCondition> updatedAtBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'updatedAt',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }
}

extension HostHealthQueryObject
    on QueryBuilder<HostHealth, HostHealth, QFilterCondition> {}

extension HostHealthQueryLinks
    on QueryBuilder<HostHealth, HostHealth, QFilterCondition> {}

extension HostHealthQuerySortBy
    on QueryBuilder<HostHealth, HostHealth, QSortBy> {
  QueryBuilder<HostHealth, HostHealth, QAfterSortBy> sortByChallenges() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'challenges', Sort.asc);
    });
  }

  QueryBuilder<HostHealth, HostHealth, QAfterSortBy> sortByChallengesDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'challenges', Sort.desc);
    });
  }

  QueryBuilder<HostHealth, HostHealth, QAfterSortBy> sortByHost() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'host', Sort.asc);
    });
  }

  QueryBuilder<HostHealth, HostHealth, QAfterSortBy> sortByHostDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'host', Sort.desc);
    });
  }

  QueryBuilder<HostHealth, HostHealth, QAfterSortBy> sortByLatencyEwmaMs() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'latencyEwmaMs', Sort.asc);
    });
  }

  QueryBuilder<HostHealth, HostHealth, QAfterSortBy> sortByLatencyEwmaMsDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'latencyEwmaMs', Sort.desc);
    });
  }

  QueryBuilder<HostHealth, HostHealth, QAfterSortBy> sortBySamples() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'samples', Sort.asc);
    });
  }

  QueryBuilder<HostHealth, HostHealth, QAfterSortBy> sortBySamplesDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'samples', Sort.desc);
    });
  }

  QueryBuilder<HostHealth, HostHealth, QAfterSortBy> sortBySuccessEwma() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'successEwma', Sort.asc);
    });
  }

  QueryBuilder<HostHealth, HostHealth, QAfterSortBy> sortBySuccessEwmaDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'successEwma', Sort.desc);
    });
  }

  QueryBuilder<HostHealth, HostHealth, QAfterSortBy> sortByUpdatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.asc);
    });
  }

  QueryBuilder<HostHealth, HostHealth, QAfterSortBy> sortByUpdatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.desc);
    });
  }
}

extension HostHealthQuerySortThenBy
    on QueryBuilder<HostHealth, HostHealth, QSortThenBy> {
  QueryBuilder<HostHealth, HostHealth, QAfterSortBy> thenByChallenges() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'challenges', Sort.asc);
    });
  }

  QueryBuilder<HostHealth, HostHealth, QAfterSortBy> thenByChallengesDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'challenges', Sort.desc);
    });
  }

  QueryBuilder<HostHealth, HostHealth, QAfterSortBy> thenByHost() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'host', Sort.asc);
    });
  }

  QueryBuilder<HostHealth, HostHealth, QAfterSortBy> thenByHostDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'host', Sort.desc);
    });
  }

  QueryBuilder<HostHealth, HostHealth, QAfterSortBy> thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<HostHealth, HostHealth, QAfterSortBy> thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<HostHealth, HostHealth, QAfterSortBy> thenByLatencyEwmaMs() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'latencyEwmaMs', Sort.asc);
    });
  }

  QueryBuilder<HostHealth, HostHealth, QAfterSortBy> thenByLatencyEwmaMsDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'latencyEwmaMs', Sort.desc);
    });
  }

  QueryBuilder<HostHealth, HostHealth, QAfterSortBy> thenBySamples() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'samples', Sort.asc);
    });
  }

  QueryBuilder<HostHealth, HostHealth, QAfterSortBy> thenBySamplesDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'samples', Sort.desc);
    });
  }

  QueryBuilder<HostHealth, HostHealth, QAfterSortBy> thenBySuccessEwma() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'successEwma', Sort.asc);
    });
  }

  QueryBuilder<HostHealth, HostHealth, QAfterSortBy> thenBySuccessEwmaDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'successEwma', Sort.desc);
    });
  }

  QueryBuilder<HostHealth, HostHealth, QAfterSortBy> thenByUpdatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.asc);
    });
  }

  QueryBuilder<HostHealth, HostHealth, QAfterSortBy> thenByUpdatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.desc);
    });
  }
}

extension HostHealthQueryWhereDistinct
    on QueryBuilder<HostHealth, HostHealth, QDistinct> {
  QueryBuilder<HostHealth, HostHealth, QDistinct> distinctByChallenges() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'challenges');
    });
  }

  QueryBuilder<HostHealth, HostHealth, QDistinct> distinctByHost({
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'host', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<HostHealth, HostHealth, QDistinct> distinctByLatencyEwmaMs() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'latencyEwmaMs');
    });
  }

  QueryBuilder<HostHealth, HostHealth, QDistinct> distinctBySamples() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'samples');
    });
  }

  QueryBuilder<HostHealth, HostHealth, QDistinct> distinctBySuccessEwma() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'successEwma');
    });
  }

  QueryBuilder<HostHealth, HostHealth, QDistinct> distinctByUpdatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'updatedAt');
    });
  }
}

extension HostHealthQueryProperty
    on QueryBuilder<HostHealth, HostHealth, QQueryProperty> {
  QueryBuilder<HostHealth, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<HostHealth, int, QQueryOperations> challengesProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'challenges');
    });
  }

  QueryBuilder<HostHealth, String, QQueryOperations> hostProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'host');
    });
  }

  QueryBuilder<HostHealth, double, QQueryOperations> latencyEwmaMsProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'latencyEwmaMs');
    });
  }

  QueryBuilder<HostHealth, int, QQueryOperations> samplesProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'samples');
    });
  }

  QueryBuilder<HostHealth, double, QQueryOperations> successEwmaProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'successEwma');
    });
  }

  QueryBuilder<HostHealth, int, QQueryOperations> updatedAtProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'updatedAt');
    });
  }
}
