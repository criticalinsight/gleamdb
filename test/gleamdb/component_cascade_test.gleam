import gleamdb
import gleamdb/fact.{Int, Str}
import gleamdb/engine.{AllAttributes}
import gleeunit
import gleeunit/should
import gleam/dict

pub fn main() {
  gleeunit.main()
}

pub fn component_cascade_test() {
  let db = gleamdb.new()
  
  // Mark 'order/items' as a component
  // Mark 'order/items' as a component
  let assert Ok(_) = gleamdb.set_schema(db, "order/items", fact.AttributeConfig(unique: False, component: True))
  
  // Setup: Order (1) has Item (2)
  let assert Ok(_) = gleamdb.transact(db, [
    #(fact.EntityId(1), "order/id", Str("ORD-100")),
    #(fact.EntityId(1), "order/items", Int(2)),
    #(fact.EntityId(2), "item/sku", Str("VALVE-01")),
    #(fact.EntityId(2), "item/qty", Int(5)),
  ])
  
  // Verify Item (2) exists
  let item_before = gleamdb.pull(db, 2, AllAttributes)
  should.equal(dict.get(item_before, "item/sku"), Ok(engine.Single(Str("VALVE-01"))))
  
  // Retract Order's items link
  let assert Ok(_) = gleamdb.retract(db, [#(fact.EntityId(1), "order/items", Int(2))])
  
  // Verify Item (2) is recursively retracted (cascade)
  let item_after = gleamdb.pull(db, 2, AllAttributes)
  should.equal(item_after, dict.new())
}
