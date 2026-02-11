import gleam/dict.{type Dict}
import gleamdb/fact.{type Datom, type Entity, type Attribute}

pub type Index = Dict(Int, List(Datom))
pub type AIndex = Dict(String, List(Datom))

pub fn new_index() -> Index {
  dict.new()
}

pub fn new_aindex() -> AIndex {
  dict.new()
}

/// Inserts a datom into the EAVT index (bucketed by Entity).
pub fn insert_eavt(index: Index, datom: Datom) -> Index {
  let bucket = dict.get(index, datom.entity) |> result_to_list
  dict.insert(index, datom.entity, [datom, ..bucket])
}

/// Inserts a datom into the AEVT index (bucketed by Attribute).
pub fn insert_aevt(index: AIndex, datom: Datom) -> AIndex {
  let bucket = dict.get(index, datom.attribute) |> result_to_list
  dict.insert(index, datom.attribute, [datom, ..bucket])
}

fn result_to_list(res: Result(List(a), Nil)) -> List(a) {
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
