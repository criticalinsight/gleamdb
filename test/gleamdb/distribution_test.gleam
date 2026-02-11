import gleam/erlang/process
import gleamdb
import gleamdb/fact.{Int}
import gleamdb/transactor
import gleamdb/engine
import gleam/dict
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

fn poll_replica_state(replica, expected_val, attempts) {
  case attempts <= 0 {
    True -> []
    False -> {
      let result = gleamdb.query(replica, [
        gleamdb.p(#(engine.Val(Int(1)), "status", engine.Var("s")))
      ])
      case result {
        [binding] -> {
          case dict.get(binding, "s") {
            Ok(val) if val == expected_val -> result
            _ -> {
              process.sleep(100)
              poll_replica_state(replica, expected_val, attempts - 1)
            }
          }
        }
        _ -> {
          process.sleep(100)
          poll_replica_state(replica, expected_val, attempts - 1)
        }
      }
    }
  }
}

fn forwarder_loop(bridge_subject, replica) {
  let datoms = process.receive_forever(bridge_subject)
  let _ = transactor.remote_transact(replica, datoms)
  forwarder_loop(bridge_subject, replica)
}

pub fn fact_propagation_test() {
  let primary = gleamdb.new()
  let replica = gleamdb.new()
  
  let ready_subject = process.new_subject()
  
  process.spawn(fn() {
    let bridge_subject = process.new_subject()
    transactor.subscribe(primary, bridge_subject)
    process.send(ready_subject, Nil)
    forwarder_loop(bridge_subject, replica)
  })

  // Wait for forwarder to be subscribed
  process.receive_forever(ready_subject)

  let assert Ok(_) = gleamdb.transact(primary, [#(fact.EntityId(1), "status", fact.Str("propagated"))])
  
  let result = poll_replica_state(replica, fact.Str("propagated"), 20)
  
  should.equal(result, [dict.from_list([#("s", fact.Str("propagated"))])])
}
