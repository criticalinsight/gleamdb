import gleam/list
import gleamdb/shared/types.{type BodyClause, Negative, Positive, Val, Var}
import gleamdb/fact

pub type QueryBuilder {
  QueryBuilder(clauses: List(BodyClause))
}

pub fn new() -> QueryBuilder {
  QueryBuilder(clauses: [])
}

pub fn select(_vars: List(String)) -> QueryBuilder {
  new()
}

/// Helper for string value
pub fn s(val: String) -> types.Part {
  Val(fact.Str(val))
}

/// Helper for int value
pub fn i(val: Int) -> types.Part {
  Val(fact.Int(val))
}

/// Helper for variable
pub fn v(name: String) -> types.Part {
  Var(name)
}

/// Helper for vector value
pub fn vec(val: List(Float)) -> types.Part {
  Val(fact.Vec(val))
}

/// Add a where clause (Entity, Attribute, Value).
pub fn where(
  builder: QueryBuilder,
  entity: types.Part,
  attr: String,
  value: types.Part,
) -> QueryBuilder {
  let clause = Positive(#(entity, attr, value))
  QueryBuilder(clauses: list.append(builder.clauses, [clause]))
}

/// Add a negative where clause (Entity, Attribute, Value).
pub fn negate(
  builder: QueryBuilder,
  entity: types.Part,
  attr: String,
  value: types.Part,
) -> QueryBuilder {
  let clause = Negative(#(entity, attr, value))
  QueryBuilder(clauses: list.append(builder.clauses, [clause]))
}

/// Count aggregate
pub fn count(builder: QueryBuilder, into: String, target: String, filter: List(BodyClause)) -> QueryBuilder {
  let clause = types.Aggregate(into, types.Count, target, filter)
  QueryBuilder(clauses: list.append(builder.clauses, [clause]))
}

/// Sum aggregate
pub fn sum(builder: QueryBuilder, into: String, target: String, filter: List(BodyClause)) -> QueryBuilder {
  let clause = types.Aggregate(into, types.Sum, target, filter)
  QueryBuilder(clauses: list.append(builder.clauses, [clause]))
}

/// Avg aggregate
pub fn avg(builder: QueryBuilder, into: String, target: String, filter: List(BodyClause)) -> QueryBuilder {
  let clause = types.Aggregate(into, types.Avg, target, filter)
  QueryBuilder(clauses: list.append(builder.clauses, [clause]))
}

/// Median aggregate
pub fn median(builder: QueryBuilder, into: String, target: String, filter: List(BodyClause)) -> QueryBuilder {
  let clause = types.Aggregate(into, types.Median, target, filter)
  QueryBuilder(clauses: list.append(builder.clauses, [clause]))
}

/// Min aggregate
pub fn min(builder: QueryBuilder, into: String, target: String, filter: List(BodyClause)) -> QueryBuilder {
  let clause = types.Aggregate(into, types.Min, target, filter)
  QueryBuilder(clauses: list.append(builder.clauses, [clause]))
}

/// Max aggregate
pub fn max(builder: QueryBuilder, into: String, target: String, filter: List(BodyClause)) -> QueryBuilder {
  let clause = types.Aggregate(into, types.Max, target, filter)
  QueryBuilder(clauses: list.append(builder.clauses, [clause]))
}

/// Placeholder for similarity search
pub fn similar(
  builder: QueryBuilder,
  entity: types.Part,
  attr: String,
  vector: List(Float),
  _threshold: Float,
) -> QueryBuilder {
  let clause = Positive(#(entity, attr, Val(fact.Vec(vector))))
  QueryBuilder(clauses: list.append(builder.clauses, [clause]))
}

/// Convert builder to a list of clauses for `gleamdb.query`.
pub fn to_clauses(builder: QueryBuilder) -> List(BodyClause) {
  builder.clauses
}
