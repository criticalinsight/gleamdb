import gleam/dict.{type Dict}
import gleam/option.{type Option}
import gleam/erlang/process.{type Subject}
import gleamdb/fact.{type AttributeConfig, type Datom, type DbFunction}
import gleamdb/index.{type Index, type AIndex, type AVIndex}
import gleamdb/storage.{type StorageAdapter}
import gleamdb/raft
import gleamdb/vec_index

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
    followers: List(process.Pid),
    is_distributed: Bool,
    ets_name: Option(String),
    raft_state: raft.RaftState,
    vec_index: vec_index.VecIndex,
  )
}

pub type Clause =
  #(Part, String, Part)

pub type Part {
  Var(String)
  Val(fact.Value)
}

pub type BodyClause {
  Positive(Clause)
  Negative(Clause)
  Filter(fn(Dict(String, fact.Value)) -> Bool)
  Bind(String, fn(Dict(String, fact.Value)) -> fact.Value)
  Aggregate(
    variable: String,
    function: AggFunc,
    target: String,
    filter: List(BodyClause),
  )
  Similarity(variable: String, vector: List(Float), threshold: Float)
}

pub type AggFunc {
  Sum
  Count
  Min
  Max
  Avg
  Median
}

pub type QueryResult =
  List(Dict(String, fact.Value))

pub type ReactiveMessage {
  Subscribe(
    query: List(BodyClause),
    attributes: List(String),
    subscriber: Subject(ReactiveDelta),
    initial_state: QueryResult,
  )
  Notify(changed_attributes: List(String), current_state: DbState)
}

pub type ReactiveDelta {
  Initial(QueryResult)
  Delta(added: QueryResult, removed: QueryResult)
}
