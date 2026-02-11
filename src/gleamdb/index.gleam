import gleam/dict.{type Dict}
import gleam/list
import gleamdb/fact.{type Datom, type Entity, type Attribute, type Value}

pub type Index =
  Dict(Int, List(Datom))

pub type AIndex =
  Dict(String, List(Datom))

pub fn new_index() -> Index {
  dict.new()
}

pub fn new_aindex() -> AIndex {
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

fn result_to_list(res: Result(List(a), b)) -> List(a) {
  case res {
    Ok(l) -> l
    Error(_) -> []
  }
}

pub fn filter_by_attribute(index: AIndex, attr: Attribute) -> List(Datom) {
  dict.get(index, attr) |> result_to_list
}

pub fn filter_by_entity(index: Index, entity: Entity) -> List(Datom) {
  dict.get(index, entity) |> result_to_list
}

pub fn get_datoms_by_entity_attr_val(
  index: Index,
  entity: Entity,
  attr: Attribute,
  val: Value,
) -> List(Datom) {
  dict.get(index, entity)
  |> result_to_list
  |> list.filter(fn(d) { d.attribute == attr && d.value == val })
}

pub fn get_datoms_by_entity_attr(
  index: Index,
  entity: Entity,
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
