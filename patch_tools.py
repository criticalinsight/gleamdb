import re

with open("src/aarondb/mcp/tools.gleam", "r") as f:
    lines = f.readlines()

out = []
for i, line in enumerate(lines):
    out.append(line)
    if '"properties",' in line and 'json.object([' in lines[i+1]:
        # we found properties
        # insert capability_token property
        out.append(lines[i+1])
        out.append('            #("capability_token", json.object([#("description", json.string("The capability token validating this action.")), #("type", json.string("string"))])),\n')
        lines[i+1] = "" # clear it so we don't duplicate

with open("src/aarondb/mcp/tools.gleam", "w") as f:
    f.writelines(out)
