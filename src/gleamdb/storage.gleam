import gleamdb/fact.{type Datom}

pub type StorageAdapter {
  StorageAdapter(
    init: fn() -> Nil,
    persist: fn(Datom) -> Nil,
    persist_batch: fn(List(Datom)) -> Nil,
    recover: fn() -> Result(List(Datom), String),
  )
}
