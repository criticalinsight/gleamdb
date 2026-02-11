import gleam/dict
import gleeunit/should
import gleam/erlang/process
import gleamdb.{p}
import gleamdb/fact
import gleamdb/shared/types

pub fn reactive_sovereignty_test() {
  let db = gleamdb.new()
  let self = process.new_subject()
  
  // 1. Setup Schema
  let assert Ok(_) = gleamdb.set_schema(db, "ticker/price", fact.AttributeConfig(unique: False, component: False))
  
  // 2. Subscribe to price updates
  let q = [p(#(types.Var("e"), "ticker/price", types.Var("price")))]
  gleamdb.subscribe(db, q, self)
  
  // 3. Transact a price (should trigger update)
  let assert Ok(_) = gleamdb.transact(db, [
    #(fact.EntityId(1), "ticker/price", fact.Int(100))
  ])
  
  // 4. Assert update received
  let results = process.receive(self, 1000)
  case results {
    Ok(res_list) -> {
      let assert [res] = res_list
      should.equal(dict.get(res, "price"), Ok(fact.Int(100)))
    }
    _ -> panic as "No reactive update received"
  }
  
  // 5. Transact another update
  let assert Ok(_) = gleamdb.transact(db, [
    #(fact.EntityId(1), "ticker/price", fact.Int(105))
  ])
  
  let results_2 = process.receive(self, 1000)
  case results_2 {
    Ok(res_list) -> {
      let assert [res] = res_list
      should.equal(dict.get(res, "price"), Ok(fact.Int(105)))
    }
    _ -> panic as "No second reactive update received"
  }
}
