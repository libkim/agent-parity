<!-- agent-parity:begin -->
## Memory (cross-agent)

A shared `memory` MCP server persists context across sessions and agents (`memory_recent`, `memory_add`, `memory_search`, `memory_get`). Each tool's description says when to call it — follow them. Store durable context, not secrets, one-off chatter, or facts another source already enforces. When you push or hand off through git, include `.agents/memory` changes. Don't leave new memories uncommitted.
<!-- agent-parity:end -->
