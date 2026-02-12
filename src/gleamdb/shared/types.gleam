import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleamdb/fact.{type AttributeConfig, type Datom, type DbFunction}
import gleamdb/index.{type Index, type AIndex, type AVIndex}
import gleamdb/storage.{type StorageAdapter}

pub type DbState {
  DbState(
    adapter: StorageAdapter,
    eavt: Index,
    aevt: AIndex,
    avet: AVIndex,
    latest_tx: Int,
    subscribers: List(Subject(List(Datom))),
    schema: Dict(String, AttributeConfig),
    functions: Dict(String, DbFunction(DbState)),
    composites: List(List(String)),
    reactive_actor: Subject(ReactiveMessage),
  )
}

pub type Clause =
  #(Part, String, Part)

pub type Part {
  Var(String)
  Val(fact.Value)
}

pub type AggFunc {
  Count
  Sum
  Min
  Max
}

pub type BodyClause {
  Positive(Clause)
  Negative(Clause)
  Aggregate(variable: String, func: AggFunc, target: String)
  Similarity(variable: String, vector: List(Float), threshold: Float)
}

pub type QueryResultItem =
  Dict(String, fact.Value)

pub type QueryResult =
  List(QueryResultItem)

pub type ReactiveResult =
  QueryResult

pub type ReactiveDelta {
  Initial(QueryResult)
  Delta(added: QueryResult, removed: QueryResult)
}

pub type ReactiveMessage {
  Subscribe(
    query: List(BodyClause),
    attributes: List(String),
    subscriber: Subject(ReactiveDelta),
    initial_state: QueryResult,
  )
  Notify(changed_attributes: List(String), current_state: DbState)
}
