import gleam/dict.{type Dict}
import gleam/list
import gleam/result
import gleamdb/fact.{type Datom, type Entity, type Attribute, type Value}

pub type Index =
  Dict(fact.EntityId, List(Datom))

pub type AIndex =
  Dict(String, List(Datom))

pub type AVIndex =
  Dict(String, Dict(Value, Entity))

pub fn new_index() -> Index {
  dict.new()
}

pub fn new_aindex() -> AIndex {
  dict.new()
}

pub fn new_avindex() -> AVIndex {
  dict.new()
}

pub fn insert_eavt(index: Index, datom: Datom) -> Index {
  let bucket = dict.get(index, datom.entity) |> result_to_list
  dict.insert(index, datom.entity, [datom, ..bucket])
}

pub fn insert_aevt(index: AIndex, datom: Datom) -> AIndex {
  let bucket = dict.get(index, datom.attribute) |> result_to_list
  dict.insert(index, datom.attribute, [datom, ..bucket])
}

pub fn insert_avet(index: AVIndex, datom: Datom) -> AVIndex {
  let v_dict = dict.get(index, datom.attribute) |> result.unwrap(dict.new())
  let new_v_dict = dict.insert(v_dict, datom.value, datom.entity)
  dict.insert(index, datom.attribute, new_v_dict)
}

pub fn delete_eavt(index: Index, datom: Datom) -> Index {
  insert_eavt(index, datom)
}

pub fn delete_aevt(index: AIndex, datom: Datom) -> AIndex {
  insert_aevt(index, datom)
}

pub fn delete_avet(index: AVIndex, datom: Datom) -> AVIndex {
  let v_dict = dict.get(index, datom.attribute) |> result.unwrap(dict.new())
  let new_v_dict = dict.delete(v_dict, datom.value)
  dict.insert(index, datom.attribute, new_v_dict)
}

fn result_to_list(res: Result(List(a), b)) -> List(a) {
  case res {
    Ok(l) -> l
    Error(_) -> []
  }
}

pub fn filter_by_attribute(index: AIndex, attr: Attribute) -> List(Datom) {
  dict.get(index, attr) |> result_to_list
}

pub fn filter_by_entity(index: Index, entity: fact.EntityId) -> List(Datom) {
  dict.get(index, entity) |> result_to_list
}

pub fn get_datoms_by_entity_attr_val(
  index: Index,
  entity: fact.EntityId,
  attr: Attribute,
  val: Value,
) -> List(Datom) {
  dict.get(index, entity)
  |> result_to_list
  |> list.filter(fn(d) { d.attribute == attr && d.value == val })
}

pub fn get_datoms_by_entity_attr(
  index: Index,
  entity: fact.EntityId,
  attr: Attribute,
) -> List(Datom) {
  dict.get(index, entity)
  |> result_to_list
  |> list.filter(fn(d) { d.attribute == attr })
}

pub fn get_datoms_by_val(index: AIndex, attr: Attribute, val: Value) -> List(Datom) {
  dict.get(index, attr)
  |> result_to_list
  |> list.filter(fn(d) { d.value == val })
}

pub fn get_all_datoms_for_attr(index: Index, attr: Attribute) -> List(Datom) {
  dict.values(index)
  |> list.flatten()
  |> list.filter(fn(d) { d.attribute == attr })
}

pub fn get_all_datoms_avet(index: AVIndex) -> List(Datom) {
  dict.values(index)
  |> list.flat_map(fn(v_dict) {
    dict.to_list(v_dict)
    |> list.map(fn(pair) {
      let #(val, eid) = pair
      fact.Datom(entity: eid, attribute: "unknown", value: val, tx: 0, operation: fact.Assert)
    })
  })
}

pub fn get_entity_by_av(index: AVIndex, attr: Attribute, val: Value) -> Result(fact.EntityId, Nil) {
  case dict.get(index, attr) {
    Ok(v_dict) -> dict.get(v_dict, val)
    Error(_) -> Error(Nil)
  }
}
