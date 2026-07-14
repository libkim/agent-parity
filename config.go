package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/pelletier/go-toml/v2"
)

// memoryTools names the tools the memory server exposes. Codex auto-approval
// writes one [mcp_servers.memory.tools.<tool>] table per name.
var memoryTools = []string{"memory_add", "memory_recent", "memory_search", "memory_get"}

// mergeServerConfig adds a `memory` MCP server entry pointing at command into
// an existing agent config, preserving everything else. JSON files are parsed
// and re-serialized; TOML files get the table appended as text so comments and
// layout survive. A memory entry that already exists is left untouched, so the
// operation is safe to repeat.
func mergeServerConfig(path, command string) error {
	raw, err := os.ReadFile(path)
	if err != nil {
		return err
	}
	switch strings.ToLower(filepath.Ext(path)) {
	case ".json":
		return mergeJSON(path, raw, command)
	case ".toml":
		return mergeTOML(path, raw, command)
	default:
		return fmt.Errorf("unsupported config type: %s", path)
	}
}

// hasMemoryServer reports whether a config contains an mcpServers.memory entry,
// independent of the equivalent JSON or TOML spelling used for it.
func hasMemoryServer(path string) (bool, error) {
	raw, err := os.ReadFile(path)
	if err != nil {
		return false, err
	}
	switch strings.ToLower(filepath.Ext(path)) {
	case ".json":
		root := map[string]any{}
		dec := json.NewDecoder(bytes.NewReader(raw))
		dec.UseNumber()
		if err := dec.Decode(&root); err != nil {
			return false, err
		}
		servers, ok := root["mcpServers"].(map[string]any)
		if !ok {
			return false, nil
		}
		_, exists := servers["memory"]
		return exists, nil
	case ".toml":
		var root struct {
			MCPServers map[string]any `toml:"mcp_servers"`
		}
		if err := toml.Unmarshal(raw, &root); err != nil {
			return false, err
		}
		_, exists := root.MCPServers["memory"]
		return exists, nil
	default:
		return false, fmt.Errorf("unsupported config type: %s", path)
	}
}

func mergeJSON(path string, raw []byte, command string) error {
	root := map[string]any{}
	if len(bytes.TrimSpace(raw)) > 0 {
		dec := json.NewDecoder(bytes.NewReader(raw))
		dec.UseNumber() // keep numbers verbatim rather than coercing to float
		if err := dec.Decode(&root); err != nil {
			return err
		}
	}
	servers, ok := root["mcpServers"]
	if !ok {
		servers = map[string]any{}
	}
	sm, ok := servers.(map[string]any)
	if !ok {
		return fmt.Errorf("mcpServers is not an object")
	}
	if _, exists := sm["memory"]; exists {
		return nil // leave a pre-existing entry to the user
	}
	sm["memory"] = map[string]any{"command": command}
	root["mcpServers"] = sm
	out, err := json.MarshalIndent(root, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(path, append(out, '\n'), 0o644)
}

func mergeTOML(path string, raw []byte, command string) error {
	var root struct {
		MCPServers map[string]any `toml:"mcp_servers"`
	}
	if len(bytes.TrimSpace(raw)) > 0 {
		if err := toml.Unmarshal(raw, &root); err != nil {
			return err
		}
	}
	if _, exists := root.MCPServers["memory"]; exists {
		return nil // already present
	}
	// Parsing catches every valid TOML spelling of mcp_servers.memory. Appending
	// a fresh table preserves the existing file byte-for-byte, including comments.
	text := string(raw)
	if len(text) > 0 && !strings.HasSuffix(text, "\n") {
		text += "\n"
	}
	text += fmt.Sprintf("\n[mcp_servers.memory]\ncommand = %q\n", command)
	// Auto-approve each memory tool so Codex stops prompting. approval_mode =
	// "approve" is the value Codex writes itself for an "Always allow" choice.
	for _, tool := range memoryTools {
		text += fmt.Sprintf("\n[mcp_servers.memory.tools.%s]\napproval_mode = \"approve\"\n", tool)
	}
	return os.WriteFile(path, []byte(text), 0o644)
}

// unmergeServerConfig removes the `memory` server entry, the inverse of a
// merge, preserving every other entry. The caller confirms the entry is ours
// before calling, so this removes it unconditionally.
func unmergeServerConfig(path string) error {
	raw, err := os.ReadFile(path)
	if err != nil {
		return err
	}
	switch strings.ToLower(filepath.Ext(path)) {
	case ".json":
		return unmergeJSON(path, raw)
	case ".toml":
		return unmergeTOML(path, raw)
	default:
		return fmt.Errorf("unsupported config type: %s", path)
	}
}

func unmergeJSON(path string, raw []byte) error {
	root := map[string]any{}
	dec := json.NewDecoder(bytes.NewReader(raw))
	dec.UseNumber()
	if err := dec.Decode(&root); err != nil {
		return err
	}
	sm, ok := root["mcpServers"].(map[string]any)
	if !ok {
		return nil
	}
	if _, exists := sm["memory"]; !exists {
		return nil
	}
	delete(sm, "memory")
	out, err := json.MarshalIndent(root, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(path, append(out, '\n'), 0o644)
}

// isMemoryTableHeader reports whether a trimmed TOML header line names the
// memory server table or one of its sub-tables — [mcp_servers.memory] or
// [mcp_servers.memory.tools.*]. It deliberately does not match an unrelated
// server whose name merely starts with "memory" (e.g. [mcp_servers.memory2]).
func isMemoryTableHeader(line string) bool {
	if line == "[mcp_servers.memory]" {
		return true
	}
	return strings.HasPrefix(line, "[mcp_servers.memory.") && strings.HasSuffix(line, "]")
}

func unmergeTOML(path string, raw []byte) error {
	var out []string
	skipping, removed := false, false
	for _, ln := range strings.Split(string(raw), "\n") {
		if strings.HasPrefix(strings.TrimSpace(ln), "[") {
			// Ours is [mcp_servers.memory] and every [mcp_servers.memory.tools.*]
			// approval sub-table; each is its own header line. A different table
			// (e.g. [mcp_servers.other]) ends the skip so it is kept.
			if isMemoryTableHeader(strings.TrimSpace(ln)) {
				skipping, removed = true, true
				continue
			}
			skipping = false // a different table starts; keep it
		}
		if skipping {
			continue // drop the memory table's body lines
		}
		out = append(out, ln)
	}
	if !removed {
		return nil
	}
	text := strings.TrimRight(strings.Join(out, "\n"), "\n") + "\n"
	return os.WriteFile(path, []byte(text), 0o644)
}
