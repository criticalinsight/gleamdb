import gleam/list
import gleam/result
import gleam/option.{None}
import gleam/erlang/process.{type Subject}
import gleam/otp/actor
import gleamdb/shared/types.{type BodyClause, type DbState, type QueryResult}
import gleamdb/engine

pub type Message {
  Subscribe(
    query: List(BodyClause),
    attributes: List(String),
    subscriber: Subject(QueryResult),
  )
  Notify(changed_attributes: List(String), current_state: DbState)
}

type ActiveQuery {
  ActiveQuery(
    query: List(BodyClause),
    attributes: List(String),
    subscriber: Subject(QueryResult),
  )
}

type State {
  State(queries: List(ActiveQuery))
}

pub fn start_link() -> Result(Subject(Message), actor.StartError) {
  actor.new(State(queries: []))
  |> actor.on_message(fn(state: State, msg: Message) {
    case msg {
      Subscribe(query, attrs, sub) -> {
        let new_query = ActiveQuery(query, attrs, sub)
        actor.continue(State(queries: [new_query, ..state.queries]))
      }
      Notify(changed_attrs, db_state) -> {
        list.each(state.queries, fn(aq: ActiveQuery) {
          let is_affected = list.any(changed_attrs, fn(ca) {
            list.contains(aq.attributes, ca)
          })
          
          case is_affected {
            True -> {
              let results = engine.run(db_state, aq.query, [], None)
              process.send(aq.subscriber, results)
            }
            False -> Nil
          }
        })
        actor.continue(state)
      }
    }
  })
  |> actor.start()
  |> result.map(fn(started) { started.data })
}
