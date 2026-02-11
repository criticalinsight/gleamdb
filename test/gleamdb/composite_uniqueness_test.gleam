import gleam/string
import gleeunit/should
import gleamdb
import gleamdb/fact

pub fn composite_uniqueness_test() {
  let db = gleamdb.new()
  
  // 1. Setup composite uniqueness for [org, email]
  gleamdb.register_composite(db, ["user/org", "user/email"])
  
  // 2. Transact first user
  let assert Ok(_) = gleamdb.transact(db, [
    #(fact.EntityId(1), "user/org", fact.Str("Acme")),
    #(fact.EntityId(1), "user/email", fact.Str("alice@acme.com"))
  ])
  
  // 3. Transact same user in different org (should pass)
  let assert Ok(_) = gleamdb.transact(db, [
    #(fact.EntityId(2), "user/org", fact.Str("Globex")),
    #(fact.EntityId(2), "user/email", fact.Str("alice@acme.com"))
  ])
  
  // 4. Transact duplicate user in same org (should fail)
  let result = gleamdb.transact(db, [
    #(fact.EntityId(3), "user/org", fact.Str("Acme")),
    #(fact.EntityId(3), "user/email", fact.Str("alice@acme.com"))
  ])
  
  case result {
    Error(msg) -> should.be_true(string.contains(string.lowercase(msg), "violation"))
    _ -> panic as "Should have failed with uniqueness violation"
  }
}
