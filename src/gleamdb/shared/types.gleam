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
    predicates: Dict(String, fn(fact.Value) -> Bool),
    stored_rules: List(Rule),
    virtual_predicates: Dict(String, VirtualAdapter),
  )
}

pub type VirtualAdapter =
  fn(List(fact.Value)) -> List(List(fact.Value))

pub type Clause =
  #(Part, String, Part)

pub type Part {
  Var(String)
  Val(fact.Value)
}

pub type BodyClause {
  Positive(Clause)
  Negative(Clause)
  Filter(Expression)
  Bind(String, fn(Dict(String, fact.Value)) -> fact.Value)
  Aggregate(
    variable: String,
    function: AggFunc,
    target: String,
    filter: List(BodyClause),
  )

  Similarity(variable: String, vector: List(Float), threshold: Float)
  Temporal(variable: String, entity: Part, attribute: String, start: Int, end: Int)
  Limit(n: Int)
  Offset(n: Int)
  OrderBy(variable: String, direction: OrderDirection)
  GroupBy(variable: String)
  ShortestPath(
    from: Part,
    to: Part,
    edge: String,
    path_var: String,
    cost_var: Option(String),
  )
  PageRank(
    entity_var: String,
    edge: String,
    rank_var: String,
    dumping_factor: Float,
    iterations: Int,
  )
  Virtual(
    predicate: String,
    args: List(Part),
    outputs: List(String),
  )
}

pub type Rule {
  Rule(head: Clause, body: List(BodyClause))
}

pub type OrderDirection {
  Asc
  Desc
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

pub type Expression {
  Eq(Part, Part)
  Neq(Part, Part)
  Gt(Part, Part)
  Lt(Part, Part)
  And(Expression, Expression)
  Or(Expression, Expression)
}
