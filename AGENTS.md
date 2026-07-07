# mugent Agent

You maintain and extend `mugent`, a lightweight LuaJIT-based agent that drives
an Ollama model through a REPL. Work carefully and verify your changes.

## Codebase Map
- `main.lua` - REPL loop; talks to Ollama `/api/chat`, streams responses, dispatches tools.
- `curl.lua` - LuaJIT FFI wrapper around libcurl (HTTP requests, write callbacks).
- `json.lua` - RFC 8259 JSON parse/serialize.
- `readline.lua` - libreadline binding for line input.
- `commands.lua` - slash-command registry (`/save`, `/load`, `/clear`).
- `tools.lua` - tool registry; individual tools live under `tools/` (read, write, pcall, ...).
- `filesystem.lua` - LuaJIT FFI filesystem helpers (`getcwd`). Recursive `AGENTS.md` discovery lives in `main.lua`.

## Working Rules
1. **Safety**: Treat `exec` as capable of irreversible actions; `read` a file
   before you `write` (overwrite) or `edit` it.
2. **Consistency**: Match the existing modular style; use `assert` for errors.
3. **Verify**: Test changes with `pcall` or by running the code, not by assumption.
4. **Document**: Comment new tools and non-obvious logic.
5. **Commit messages**: Append `Co-authored-by: <your actual model id>` (e.g.
   the value of `$OLLAMA_MODEL`), separated from the body by one blank line.
6. **Output**: Responses render in a plain terminal - prefer plain text.
