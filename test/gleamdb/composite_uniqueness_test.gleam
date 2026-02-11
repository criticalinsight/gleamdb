import gleam/list
import gleamdb
import gleamdb/fact.{Int, Str}
import gleeunit
import gleeunit/should
import gleamdb/transactor

pub fn main() {
  gleeunit.main()
}

pub fn composite_uniqueness_test() {
  let db = gleamdb.new()
  
  // 1. Register composite constraint on [name, rol]
  // e.g., A user can have only one role per project, or name+role must be unique pair
  gleamdb.register_composite(db, ["user/name", "user/role"])
  
  // 2. Transact first entity: Alice, Admin
  let assert Ok(_) = gleamdb.transact(db, [
    #(fact.EntityId(1), "user/name", Str("Alice")),
    #(fact.EntityId(1), "user/role", Str("Admin")),
  ])
  
  // 3. Transact second entity: Bob, Admin (OK - different name)
  let assert Ok(_) = gleamdb.transact(db, [
    #(fact.EntityId(2), "user/name", Str("Bob")),
    #(fact.EntityId(2), "user/role", Str("Admin")),
  ])
  
  // 4. Transact third entity: Alice, User (OK - different role)
  let assert Ok(_) = gleamdb.transact(db, [
    #(fact.EntityId(3), "user/name", Str("Alice")),
    #(fact.EntityId(3), "user/role", Str("User")),
  ])
  
  // 5. Transact duplicate: Alice, Admin (ERROR)
  let result = gleamdb.transact(db, [
    #(fact.EntityId(4), "user/name", Str("Alice")),
    #(fact.EntityId(4), "user/role", Str("Admin")),
  ])
  
  should.be_error(result)
}
