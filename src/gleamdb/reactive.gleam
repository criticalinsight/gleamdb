import gleam/list
import gleam/result
import gleam/option.{None}
import gleam/erlang/process.{type Subject}
import gleam/otp/actor
import gleamdb/shared/types.{type ReactiveDelta, type ReactiveMessage, type QueryResult, Delta, Notify, Subscribe}
import gleamdb/engine

type ActiveQuery {
  ActiveQuery(
    query: List(types.BodyClause),
    attributes: List(String),
    subscriber: Subject(ReactiveDelta),
    last_result: QueryResult,
  )
}

type State {
  State(queries: List(ActiveQuery))
}

pub fn start_link() -> Result(Subject(ReactiveMessage), actor.StartError) {
  actor.new(State(queries: []))
  |> actor.on_message(fn(state: State, msg: ReactiveMessage) {
    case msg {
      Subscribe(query, attrs, sub, initial_state) -> {
        let new_query = ActiveQuery(query, attrs, sub, initial_state)
        actor.continue(State(queries: [new_query, ..state.queries]))
      }
      Notify(changed_attrs, db_state) -> {
        let new_queries = list.map(state.queries, fn(aq: ActiveQuery) {
          let is_affected = list.any(changed_attrs, fn(ca) {
            list.contains(aq.attributes, ca)
          })
          
          case is_affected {
            True -> {
              let current_result = engine.run(db_state, aq.query, [], None)
              let #(added, removed) = diff(aq.last_result, current_result)
              
              case added == [] && removed == [] {
                True -> aq // No actual change
                False -> {
                  process.send(aq.subscriber, Delta(added, removed))
                  ActiveQuery(..aq, last_result: current_result)
                }
              }
            }
            False -> aq
          }
        })
        actor.continue(State(queries: new_queries))
      }
    }
  })
  |> actor.start()
  |> result.map(fn(started) { started.data })
}

fn diff(old: QueryResult, new: QueryResult) -> #(QueryResult, QueryResult) {
  let added = list.filter(new, fn(item) { !list.contains(old, item) })
  let removed = list.filter(old, fn(item) { !list.contains(new, item) })
  
  #(added, removed)
}
