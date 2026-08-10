<!-- agent-parity:begin -->
## Shared memory and agent state

This project uses `agent-parity` to keep memory, skills, instructions, and agent wiring portable across agents and machines; treat its managed files as repository state, not disposable generated files.

A shared `memory` MCP server persists context across sessions and agents (`memory_recent`, `memory_add`, `memory_search`, `memory_get`). Each tool's description says when to call it — follow them. Store durable context, not secrets, one-off chatter, or facts another source already enforces.

Cross-agent bootstrap: at the start of the first user turn, if the `memory` tools are unavailable, inspect the managed `memory` commands in `.mcp.json`, `.cursor/mcp.json`, `.codex/config.toml`, and `.agents/mcp_config.json` before doing other work. On native Windows, replace an exact `.agent-parity/mcp/memory/run.sh` value with `.agent-parity/mcp/memory/run.cmd`; on Unix-like systems, make the inverse replacement. Use built-in file read/edit tools, not project scripts or a command the user must type. Preserve missing, malformed, or custom `memory` registrations. If you changed any file, tell the user that the current agent must be restarted and do not claim the memory tools are available in the current session.

When asked for agent-parity status in a conversation, run the project-local `status` command and call `memory_recent` to verify the current session; never infer tool availability from a static tool list because MCP tools may load lazily. If wiring is healthy but that call is unavailable, tell the user to restart the agent session. If wiring is missing, stale, conflicting, or invalid, offer to inspect the named configuration files because unrelated user settings may also prevent the agent from loading them.

When pushing or handing off through Git, commit and include every changed agent-parity-managed file. Never select only some managed changes or bypass the pre-push guard.
<!-- agent-parity:end -->
