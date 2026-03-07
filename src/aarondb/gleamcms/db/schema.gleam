import aarondb
import aarondb/fact.{All, AttributeConfig, Many, One}
import gleam/option.{None}

pub fn init_schema(db: aarondb.Db) {
  let _ =
    aarondb.set_schema(
      db,
      "cms.post/title",
      AttributeConfig(
        unique: False,
        component: False,
        retention: All,
        cardinality: One,
        check: None,
        composite_group: None,
        layout: fact.Row,
        tier: fact.Memory,
        eviction: fact.AlwaysInMemory,
      ),
    )
  let _ =
    aarondb.set_schema(
      db,
      "cms.post/slug",
      AttributeConfig(
        unique: True,
        component: False,
        retention: All,
        cardinality: One,
        check: None,
        composite_group: None,
        layout: fact.Row,
        tier: fact.Memory,
        eviction: fact.AlwaysInMemory,
      ),
    )
  let _ =
    aarondb.set_schema(
      db,
      "cms.post/content",
      AttributeConfig(
        unique: False,
        component: False,
        retention: All,
        cardinality: One,
        check: None,
        composite_group: None,
        layout: fact.Row,
        tier: fact.Memory,
        eviction: fact.AlwaysInMemory,
      ),
    )
  let _ =
    aarondb.set_schema(
      db,
      "cms.post/status",
      AttributeConfig(
        unique: False,
        component: False,
        retention: All,
        cardinality: One,
        check: None,
        composite_group: None,
        layout: fact.Row,
        tier: fact.Memory,
        eviction: fact.AlwaysInMemory,
      ),
    )
  let _ =
    aarondb.set_schema(
      db,
      "cms.post/published_at",
      AttributeConfig(
        unique: False,
        component: False,
        retention: All,
        cardinality: One,
        check: None,
        composite_group: None,
        layout: fact.Row,
        tier: fact.Memory,
        eviction: fact.AlwaysInMemory,
      ),
    )
  let _ =
    aarondb.set_schema(
      db,
      "cms.post/tags",
      AttributeConfig(
        unique: False,
        component: False,
        retention: All,
        cardinality: Many,
        check: None,
        composite_group: None,
        layout: fact.Row,
        tier: fact.Memory,
        eviction: fact.AlwaysInMemory,
      ),
    )
  let _ =
    aarondb.set_schema(
      db,
      "cms.post/featured_image",
      AttributeConfig(
        unique: False,
        component: False,
        retention: All,
        cardinality: One,
        check: None,
        composite_group: None,
        layout: fact.Row,
        tier: fact.Memory,
        eviction: fact.AlwaysInMemory,
      ),
    )
  Nil
}
