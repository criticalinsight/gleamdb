import gleamdb
import gleamdb/fact
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

pub fn unique_constraint_test() {
  let db = gleamdb.new()
  
  // Set schema: email is unique
  let assert Ok(_) = gleamdb.set_schema(db, "user/email", fact.AttributeConfig(unique: True, component: False, retention: fact.All))
  
  // First transaction: OK
  let assert Ok(_) = gleamdb.transact(db, [#(fact.Uid(fact.EntityId(1)), "user/email", fact.Str("rich@hickey.com"))])
  
  // Second transaction with same email: Error
  let result2 = gleamdb.transact(db, [#(fact.Uid(fact.EntityId(2)), "user/email", fact.Str("rich@hickey.com"))])
  should.be_error(result2)
}

pub fn non_unique_attribute_test() {
  let db = gleamdb.new()
  
  // Tags are not unique
  let assert Ok(_) = gleamdb.set_schema(db, "tag", fact.AttributeConfig(unique: False, component: False, retention: fact.All))
  
  let assert Ok(_) = gleamdb.transact(db, [#(fact.Uid(fact.EntityId(1)), "tag", fact.Str("clojure"))])
  
  let assert Ok(_) = gleamdb.transact(db, [#(fact.Uid(fact.EntityId(2)), "tag", fact.Str("clojure"))])
}
