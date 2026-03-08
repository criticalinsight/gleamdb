import aarondb/engine
import aarondb/process_extra as aarondb_process_extra
import aarondb/shared/ast
import aarondb/shared/query_types
import aarondb/shared/state
import gleam/erlang/process.{type Subject}
import gleam/list
import gleam/option.{None}
import gleam/otp/actor
import gleam/result
import gleam/set

pub type ReactiveMessage {
  Subscribe(
    query: ast.Query,
    attributes: List(String),
    subscriber: Subject(query_types.ReactiveDelta),
    initial_state: query_types.QueryResult,
  )
  Notify(changed_attributes: List(String), current_state: state.DbState)
}

type ActiveQuery {
  ActiveQuery(
    query: ast.Query,
    attributes: List(String),
    subscriber: Subject(query_types.ReactiveDelta),
    last_result: query_types.QueryResult,
  )
}

type ReactiveState {
  ReactiveState(queries: List(ActiveQuery))
}

pub fn start_link() -> Result(Subject(state.ReactiveMessage), actor.StartError) {
  actor.new(ReactiveState(queries: []))
  |> actor.on_message(fn(st: ReactiveState, msg: state.ReactiveMessage) {
    case msg {
      state.Subscribe(query, attrs, sub, initial_state) -> {
        let new_query = ActiveQuery(query, attrs, sub, initial_state)
        actor.continue(ReactiveState(queries: [new_query, ..st.queries]))
      }
      state.Notify(changed_attrs, db_state) -> {
        let new_queries =
          list.filter_map(st.queries, fn(aq: ActiveQuery) {
            case aarondb_process_extra.is_alive(aq.subscriber) {
              False -> Error(Nil)
              True -> {
                let is_affected =
                  list.any(changed_attrs, fn(ca) {
                    list.contains(aq.attributes, ca)
                  })

                case is_affected {
                  True -> {
                    let current_result =
                      engine.run(db_state, aq.query, [], None, None)
                    let #(added, removed) = diff(aq.last_result, current_result)

                    case added.rows == [] && removed.rows == [] {
                      True -> Ok(aq)
                      False -> {
                        process.send(
                          aq.subscriber,
                          query_types.Delta(added, removed),
                        )
                        Ok(ActiveQuery(..aq, last_result: current_result))
                      }
                    }
                  }
                  False -> Ok(aq)
                }
              }
            }
          })
        actor.continue(ReactiveState(queries: new_queries))
      }
    }
  })
  |> actor.start()
  |> result.map(fn(started) { started.data })
}

fn diff(
  old: query_types.QueryResult,
  new: query_types.QueryResult,
) -> #(query_types.QueryResult, query_types.QueryResult) {
  let old_set = set.from_list(old.rows)
  let new_set = set.from_list(new.rows)

  let added_rows = set.difference(new_set, old_set) |> set.to_list()
  let removed_rows = set.difference(old_set, new_set) |> set.to_list()

  #(
    query_types.QueryResult(
      rows: added_rows,
      metadata: new.metadata,
      updated_columnar_store: None,
    ),
    query_types.QueryResult(
      rows: removed_rows,
      metadata: new.metadata,
      updated_columnar_store: None,
    ),
  )
}
