import aarondb/mcp/tools
import gleam/erlang/process
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result

pub type JsonRpcRequest {
  JsonRpcRequest(
    jsonrpc: String,
    id: Option(String),
    method: String,
    params: Option(json.Json),
  )
}

pub type JsonRpcResponse {
  JsonRpcResponse(
    jsonrpc: String,
    id: Option(String),
    result: Option(json.Json),
    error: Option(JsonRpcError),
  )
}

pub type JsonRpcError {
  JsonRpcError(code: Int, message: String, data: Option(json.Json))
}

// Convert a JSON object to string and print to stdout
pub fn send_response(response: JsonRpcResponse) {
  // TODO: implement standard out print
  Nil
}

// Map the tool name to a Datalog query or transaction
pub fn execute_tool(name: String, _args: json.Json) -> Result(json.Json, String) {
  case name {
    _ -> Error("Tool not implemented yet in AaronDB: " <> name)
  }
}

pub fn handle_request(req: JsonRpcRequest) -> JsonRpcResponse {
  case req.method {
    "tools/list" -> {
      let result =
        json.object([
          #(
            "tools",
            tools.precompiled_array(
              list.map(tools.all_tools(), fn(t: tools.Tool) {
                json.object([
                  #("name", json.string(t.name)),
                  #("description", json.string(t.description)),
                  #("inputSchema", t.input_schema),
                ])
              }),
            ),
          ),
        ])
      JsonRpcResponse("2.0", req.id, Some(result), None)
    }
    "tools/call" -> {
      // Decode tool call and route
      // For now, return not implemented error
      JsonRpcResponse(
        "2.0",
        req.id,
        None,
        Some(JsonRpcError(
          -32_601,
          "tools/call execution not hooked up yet",
          None,
        )),
      )
    }
    _ -> {
      JsonRpcResponse(
        "2.0",
        req.id,
        None,
        Some(JsonRpcError(-32_601, "Method not found", None)),
      )
    }
  }
}

pub fn start() {
  // Main event loop for stdio MCP
  process.sleep_forever()
}
