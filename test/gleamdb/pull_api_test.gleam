import gleam/dict
import gleamdb
import gleamdb/fact.{Int, Str}
import gleamdb/engine.{AllAttributes, AttributeList, Nested, Deep, Single, Map}
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

pub fn pull_api_test() {
  let db = gleamdb.new()
  
  // Setup data: Alice (1) is 30, Bob (2) is her friend
  let assert Ok(_) = gleamdb.transact(db, [
    #(fact.EntityId(1), "name", Str("Alice")),
    #(fact.EntityId(1), "age", Int(30)),
    #(fact.EntityId(2), "name", Str("Bob")),
    #(fact.EntityId(1), "friend", Int(2)),
  ])
  
  // 1. Pull all attributes for Alice
  let res1 = gleamdb.pull(db, fact.EntityId(1), AllAttributes)
  should.equal(dict.get(res1, "name"), Ok(Single(Str("Alice"))))
  should.equal(dict.get(res1, "age"), Ok(Single(Int(30))))
  
  // 2. Pull selective attributes
  let res2 = gleamdb.pull(db, fact.EntityId(1), AttributeList(["name"]))
  should.equal(dict.get(res2, "name"), Ok(Single(Str("Alice"))))
  should.equal(dict.get(res2, "age"), Error(Nil))
  
  // 3. Pull nested friend
  let res3 = gleamdb.pull(db, fact.EntityId(1), Nested("friend", AllAttributes))
  let assert Ok(Map(friend_map)) = dict.get(res3, "friend")
  should.equal(dict.get(friend_map, "name"), Ok(Single(Str("Bob"))))
  
  // 4. Deep pattern
  let res4 = gleamdb.pull(db, fact.EntityId(1), Deep([
    AttributeList(["age"]),
    Nested("friend", AttributeList(["name"]))
  ]))
  should.equal(dict.get(res4, "age"), Ok(Single(Int(30))))
  let assert Ok(Map(fm)) = dict.get(res4, "friend")
  should.equal(dict.get(fm, "name"), Ok(Single(Str("Bob"))))
}
