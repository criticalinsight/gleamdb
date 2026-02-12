import gleam/string

pub fn to_string(v: Value) -> String {
  string.inspect(v)
}

pub type EntityId {
  EntityId(Int)
}

pub type Entity =
  EntityId

pub type Attribute = String
pub type Transaction = Int

pub type DbFunction(state) =
  fn(state, List(Value)) -> List(Fact)

pub type LookupRef = #(Attribute, Value)

pub type Eid {
  Lookup(LookupRef)
  Uid(EntityId)
}

pub type Value {
  Str(String)
  Int(Int)
  Float(Float)
  Bool(Bool)
  List(List(Value))
  Vec(List(Float))
}

pub type Operation {
  Assert
  Retract
}

pub type AttributeConfig {
  AttributeConfig(unique: Bool, component: Bool)
}

/// A Fact is #(Eid, Attribute, Value) for assertion,
/// or a more explicit Tuple for retractions.
pub type Fact = #(Eid, Attribute, Value)

pub type Datom {
  Datom(
    entity: Entity,
    attribute: Attribute,
    value: Value,
    tx: Transaction,
    operation: Operation,
  )
}
