import gleam/list
import gleam/dict
import gleeunit/should
import gleamdb
import gleamdb/fact
import gleamdb/shared/types
import gleamdb/engine

pub fn component_cascade_test() {
  let db = gleamdb.new()
  
  // 1. Setup Component Schema
  let assert Ok(_) = gleamdb.set_schema(db, "order/items", fact.AttributeConfig(unique: False, component: True))
  let assert Ok(_) = gleamdb.set_schema(db, "item/name", fact.AttributeConfig(unique: False, component: False))
  
  // 2. Create Order with Items
  let assert Ok(_) = gleamdb.transact(db, [
    #(fact.Uid(fact.EntityId(1)), "order/items", fact.Int(2)),
    #(fact.Uid(fact.EntityId(2)), "item/name", fact.Str("Laptop")),
    #(fact.Uid(fact.EntityId(1)), "order/items", fact.Int(3)),
    #(fact.Uid(fact.EntityId(3)), "item/name", fact.Str("Mouse")),
  ])
  
  // 3. Verify existence
  let results = gleamdb.query(db, [
    gleamdb.p(#(types.Var("o"), "order/items", types.Var("i"))),
    gleamdb.p(#(types.Var("i"), "item/name", types.Var("n")))
  ])
  should.equal(list.length(results), 2)
  
  // 4. Retract Order (should cascade to items)
  let assert Ok(_) = gleamdb.retract(db, [
    #(fact.Uid(fact.EntityId(1)), "order/items", fact.Int(2)),
    #(fact.Uid(fact.EntityId(1)), "order/items", fact.Int(3))
  ])
  
  // 5. Verify Laptop/Mouse also gone from item/name index
  let item_after = gleamdb.pull(db, fact.Uid(fact.EntityId(2)), [engine.Wildcard])
  let assert engine.Map(m) = item_after
  should.equal(dict.size(m), 0)
  
  let results_after = gleamdb.query(db, [
    gleamdb.p(#(types.Var("i"), "item/name", types.Var("n")))
  ])
  should.equal(list.length(results_after), 0)
}
