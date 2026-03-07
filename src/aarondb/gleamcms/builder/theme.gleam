import aarondb/gleamcms/theme.{type Theme}
import aarondb/gleamcms/themes/configurable
import aarondb/gleamcms/themes/library
import gleam/list

pub fn current() -> Theme {
  let themes = library.get_all()
  case list.first(themes) {
    Ok(t) -> t
    Error(_) -> panic as "No themes in library!"
  }
}

/// Select a theme by name from the library. Falls back to first if not found.
pub fn get_by_name(name: String) -> Theme {
  let configs = library.get_configs()
  let found = list.find(configs, fn(c) { c.name == name })
  case found {
    Ok(c) -> configurable.new(c)
    Error(_) -> current()
  }
}

/// List all theme names for the picker.
pub fn theme_names() -> List(String) {
  list.map(library.get_configs(), fn(c) { c.name })
}
