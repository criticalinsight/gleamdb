import aarondb
import aarondb/gleamcms/builder/importer
import aarondb/gleamcms/db/schema as cms_schema
import aarondb/gleamcms/server/router as cms_router
import gleam/erlang/process
import logging
import mist
import wisp/wisp_mist

pub fn main() {
  logging.configure()

  // 1. Initialize AaronDB
  let db = aarondb.new()
  cms_schema.init_schema(db)

  // 2. Perform Legacy Import (Demo)
  let _ = importer.run_import(db, "legacy_posts.json")

  // 3. Secret Key for Wisp
  let secret_key_base = "fake_secret_key_base_for_local_dev"

  // 4. Start Wisp Server
  let assert Ok(_) =
    wisp_mist.handler(cms_router.handle_request(_, db), secret_key_base)
    |> mist.new()
    |> mist.port(4000)
    |> mist.start()

  process.sleep_forever()
}
