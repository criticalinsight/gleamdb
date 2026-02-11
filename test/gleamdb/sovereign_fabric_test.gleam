import gleeunit/should
import gleam/dict
import gleamdb.{p}
import gleamdb/fact.{AttributeConfig, EntityId, Int, Str}
import gleamdb/shared/types
import gleamdb/engine.{AllAttributes, Nested}

pub fn sovereign_fabric_test() {
  let db = gleamdb.new()
  
  // 1. Setup Schema for components
  let assert Ok(_) = gleamdb.set_schema(db, "user/name", AttributeConfig(unique: True, component: False))
  let assert Ok(_) = gleamdb.set_schema(db, "user/profile", AttributeConfig(unique: False, component: True))
  let assert Ok(_) = gleamdb.set_schema(db, "profile/bio", AttributeConfig(unique: False, component: False))
  
  // 2. Transact initial state (TX 1)
  let assert Ok(_) = gleamdb.transact(db, [
    #(EntityId(1), "user/name", Str("Rich")),
    #(EntityId(1), "user/profile", Int(2)),
    #(EntityId(2), "profile/bio", Str("Composer of Code"))
  ])
  
  // 3. Verify Pull API (Nested)
  let pull_pattern = Nested("user/profile", AllAttributes)
  let result = gleamdb.pull(db, fact.EntityId(1), pull_pattern)
  
  let profile_map = case dict.get(result, "user/profile") {
    Ok(engine.Map(m)) -> m
    _ -> panic as "Failed to pull nested profile"
  }
  
  dict.get(profile_map, "profile/bio")
  |> should.equal(Ok(engine.Single(Str("Composer of Code"))))
  
  // 4. Update state (TX 2)
  let assert Ok(_) = gleamdb.transact(db, [
    #(EntityId(1), "user/name", Str("Rich Hickey"))
  ])
  
  // 5. Verify Bi-temporality (as_of)
  let q = [p(#(types.Var("e"), "user/name", types.Var("name")))]
  
  // Current state
  gleamdb.query(db, q)
  |> should.equal([dict.from_list([#("e", Int(1)), #("name", Str("Rich Hickey"))])])
  
  // Historical state (TX 1)
  gleamdb.as_of(db, 1, q)
  |> should.equal([dict.from_list([#("e", Int(1)), #("name", Str("Rich"))])])
  
  // 6. Verify Component Cascades (Recursive Retraction)
  let assert Ok(_) = gleamdb.retract(db, [
    #(EntityId(1), "user/name", Str("Rich Hickey")),
    #(EntityId(1), "user/profile", Int(2))
  ])
  
  // Verify user is gone
  gleamdb.query(db, q)
  |> should.equal([])
  
  // Verify profile (component) was also retracted automatically
  let q_profile = [p(#(types.Var("e"), "profile/bio", types.Var("bio")))]
  gleamdb.query(db, q_profile)
  |> should.equal([])
}
