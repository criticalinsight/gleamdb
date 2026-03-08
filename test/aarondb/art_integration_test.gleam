import aarondb
import aarondb/fact
import aarondb/shared/ast
import gleam/list
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

pub fn art_integration_test() {
  let db = aarondb.new()

  // 1. Setup Data: Large amount of data to potentially trigger ART optimizations
  let cities = [
    #("London", "UK"),
    #("Liverpool", "UK"),
    #("Los Angeles", "USA"),
    #("New York", "USA"),
    #("Paris", "France"),
    #("Berlin", "Germany"),
  ]

  let tx_data =
    list.index_map(cities, fn(c, i) {
      let #(name, _country) = c
      #(fact.Uid(fact.EntityId(100 + i)), "city_name", fact.Str(name))
    })
    |> list.append(
      list.index_map(cities, fn(c, i) {
        let #(_name, country) = c
        #(fact.Uid(fact.EntityId(100 + i)), "country", fact.Str(country))
      }),
    )

  let assert Ok(_) = aarondb.transact(db, tx_data)

  // 2. Query with Prefix Filter (should be optimized by ART if available)
  let clause = ast.Positive(#(ast.Var("e"), "city_name", ast.Var("n")))
  let filter = ast.StartsWith("n", "Al")
  // Testing a prefix that matches nothing first
  let result = aarondb.query(db, [clause, filter])
  should.equal(list.length(result.rows), 0)

  let filter2 = ast.StartsWith("n", "L")
  let result2 = aarondb.query(db, [clause, filter2])
  // Should match London, Liverpool, Los Angeles
  should.equal(list.length(result2.rows), 3)
}

pub fn art_geonames_optimized_test() {
  // Scenario: Querying cities in UK starting with "Lon"
  let db = aarondb.new()

  let data = [
    #("London", "UK"),
    #("Longbeach", "USA"),
    #("Lyon", "France"),
  ]

  let assert Ok(_) =
    aarondb.transact(
      db,
      list.index_map(data, fn(d, i) {
        let eid = 200 + i
        let #(city, country) = d
        [
          #(fact.Uid(fact.EntityId(eid)), "city_name", fact.Str(city)),
          #(fact.Uid(fact.EntityId(eid)), "country", fact.Str(country)),
        ]
      })
        |> list.flatten(),
    )

  let clauses = [
    ast.Positive(#(ast.Var("e"), "city_name", ast.Var("n"))),
    ast.Positive(#(ast.Var("e"), "country", ast.Val(fact.Str("UK")))),
    ast.StartsWith("n", "Lon"),
  ]

  let result = aarondb.query(db, clauses)

  // Only London matches both.
  should.equal(list.length(result.rows), 1)
}
