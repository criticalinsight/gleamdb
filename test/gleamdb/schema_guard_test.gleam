import gleamdb
import gleamdb/fact.{Str}
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

pub fn schema_guard_test() {
  let db = gleamdb.new()
  
  // 1. Ingest duplicate data (initially valid, as attribute is not unique)
  let assert Ok(_) = gleamdb.transact(db, [
    #(fact.Uid(fact.EntityId(1)), "username", Str("Alice")),
    #(fact.Uid(fact.EntityId(2)), "username", Str("Alice")), // Duplicate!
  ])
  
  // 2. Attempt to make "username" unique (Should Fail)
  let result = gleamdb.set_schema(db, "username", fact.AttributeConfig(unique: True, component: False, retention: fact.All))
  should.be_error(result)
  
  // 3. Retract duplicate
  let assert Ok(_) = gleamdb.retract(db, [
    #(fact.Uid(fact.EntityId(2)), "username", Str("Alice"))
  ])
  
  // 4. Attempt to make "username" unique again (Should Succeed)
  let result_retry = gleamdb.set_schema(db, "username", fact.AttributeConfig(unique: True, component: False, retention: fact.All))
  should.be_ok(result_retry)
}
