//go:build configeditor

package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"

	"github.com/pelletier/go-toml/v2"
	"github.com/pelletier/go-toml/v2/unstable"
)

// memoryTools names the tools the memory server exposes. Codex auto-approval
// writes one [mcp_servers.memory.tools.<tool>] table per name.
var memoryTools = []string{"memory_add", "memory_recent", "memory_search", "memory_get"}

const cursorCLIMemoryPermission = "Mcp(memory:*)"

func writeConfigFile(path string, data []byte, fallbackMode os.FileMode) error {
	mode := fallbackMode
	if info, err := os.Stat(path); err == nil {
		mode = info.Mode().Perm()
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	tmp, err := os.CreateTemp(filepath.Dir(path), "."+filepath.Base(path)+".agent-parity.*")
	if err != nil {
		return err
	}
	tmpPath := tmp.Name()
	defer os.Remove(tmpPath)
	if err := tmp.Chmod(mode); err != nil {
		tmp.Close()
		return err
	}
	if _, err := tmp.Write(data); err != nil {
		tmp.Close()
		return err
	}
	if err := tmp.Close(); err != nil {
		return err
	}
	return os.Rename(tmpPath, path)
}

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

func configMemoryCommand(path string) (string, bool, error) {
	raw, err := os.ReadFile(path)
	if err != nil {
		return "", false, err
	}
	switch strings.ToLower(filepath.Ext(path)) {
	case ".json":
		root := map[string]any{}
		dec := json.NewDecoder(bytes.NewReader(raw))
		dec.UseNumber()
		if err := dec.Decode(&root); err != nil {
			return "", false, err
		}
		servers, ok := root["mcpServers"].(map[string]any)
		if !ok {
			return "", false, nil
		}
		memory, ok := servers["memory"].(map[string]any)
		if !ok {
			if _, exists := servers["memory"]; exists {
				return "", true, fmt.Errorf("memory server is not an object")
			}
			return "", false, nil
		}
		command, ok := memory["command"].(string)
		if !ok {
			return "", true, fmt.Errorf("memory server command is not a string")
		}
		return command, true, nil
	case ".toml":
		var root struct {
			MCPServers map[string]any `toml:"mcp_servers"`
		}
		if err := toml.Unmarshal(raw, &root); err != nil {
			return "", false, err
		}
		memory, ok := root.MCPServers["memory"].(map[string]any)
		if !ok {
			if _, exists := root.MCPServers["memory"]; exists {
				return "", true, fmt.Errorf("memory server is not a table")
			}
			return "", false, nil
		}
		command, ok := memory["command"].(string)
		if !ok {
			return "", true, fmt.Errorf("memory server command is not a string")
		}
		return command, true, nil
	default:
		return "", false, fmt.Errorf("unsupported config type: %s", path)
	}
}

func ensureMemoryConfig(path, command string) (bool, error) {
	if _, err := os.Stat(path); os.IsNotExist(err) {
		if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
			return false, err
		}
		initial := []byte("{}\n")
		if strings.EqualFold(filepath.Ext(path), ".toml") {
			initial = nil
		}
		if err := writeConfigFile(path, initial, 0o644); err != nil {
			return false, err
		}
	} else if err != nil {
		return false, err
	}
	_, exists, err := configMemoryCommand(path)
	if err != nil {
		return false, err
	}
	if !exists {
		return true, mergeServerConfig(path, command)
	}
	return retargetMemoryConfig(path, command)
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
	return writeConfigFile(path, append(out, '\n'), 0o644)
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
	return writeConfigFile(path, []byte(text), 0o644)
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
	return writeConfigFile(path, append(out, '\n'), 0o644)
}

func unmergeCursorCLI(path string) error {
	raw, err := os.ReadFile(path)
	if err != nil {
		return err
	}
	root := map[string]any{}
	dec := json.NewDecoder(bytes.NewReader(raw))
	dec.UseNumber()
	if err := dec.Decode(&root); err != nil {
		return err
	}
	permissions, ok := root["permissions"].(map[string]any)
	if !ok {
		return nil
	}
	allow, ok := permissions["allow"].([]any)
	if !ok {
		return nil
	}
	kept := make([]any, 0, len(allow))
	changed := false
	for _, item := range allow {
		if value, ok := item.(string); ok && value == cursorCLIMemoryPermission {
			changed = true
			continue
		}
		kept = append(kept, item)
	}
	if !changed {
		return nil
	}
	if len(kept) == 0 {
		delete(permissions, "allow")
	} else {
		permissions["allow"] = kept
	}
	if deny, ok := permissions["deny"].([]any); ok && len(deny) == 0 {
		delete(permissions, "deny")
	}
	if len(permissions) == 0 {
		delete(root, "permissions")
	}
	if len(root) == 0 {
		return os.Remove(path)
	}
	out, err := json.MarshalIndent(root, "", "  ")
	if err != nil {
		return err
	}
	return writeConfigFile(path, append(out, '\n'), 0o644)
}

// mergeCursorCLI adds the memory MCP permission to Cursor CLI's exact
// permissions.allow path while preserving every unrelated setting.
func mergeCursorCLI(path string) (bool, error) {
	root := map[string]any{}
	if _, err := os.Stat(path); err == nil {
		var readErr error
		root, readErr = readJSONObject(path)
		if readErr != nil {
			return false, readErr
		}
	} else if !os.IsNotExist(err) {
		return false, err
	}

	permissions, exists := root["permissions"]
	if !exists {
		permissions = map[string]any{}
		root["permissions"] = permissions
	}
	permissionMap, ok := permissions.(map[string]any)
	if !ok {
		return false, fmt.Errorf("permissions must be a JSON object")
	}

	allowValue, exists := permissionMap["allow"]
	if !exists {
		allowValue = []any{}
	}
	allow, ok := allowValue.([]any)
	if !ok {
		return false, fmt.Errorf("permissions.allow must be a JSON array")
	}
	for _, item := range allow {
		if item == cursorCLIMemoryPermission {
			return false, nil
		}
	}

	permissionMap["allow"] = append(allow, cursorCLIMemoryPermission)
	out, err := json.MarshalIndent(root, "", "  ")
	if err != nil {
		return false, err
	}
	if err := writeConfigFile(path, append(out, '\n'), 0o644); err != nil {
		return false, err
	}
	return true, nil
}

func runConfigMutation(path string, mutate func(string) error) (bool, error) {
	before, err := os.ReadFile(path)
	if os.IsNotExist(err) {
		return false, nil
	}
	if err != nil {
		return false, err
	}
	if err := mutate(path); err != nil {
		return false, err
	}
	after, err := os.ReadFile(path)
	if os.IsNotExist(err) {
		return true, nil
	}
	if err != nil {
		return false, err
	}
	return !bytes.Equal(before, after), nil
}

// unmergeTOML removes the semantic mcp_servers.memory subtree using TOML AST
// source ranges, so equivalent dotted, quoted, table, and inline spellings are
// handled without reformatting unrelated user content.
func unmergeTOML(path string, raw []byte) error {
	if _, err := memoryCommandFromTOML(raw); err != nil {
		return err
	}
	edits, err := tomlMemoryRemovalEdits(raw)
	if err != nil {
		return err
	}
	if len(edits) == 0 {
		return nil
	}
	out, err := applyTextEdits(raw, edits)
	if err != nil {
		return err
	}
	if len(bytes.TrimSpace(out)) == 0 {
		return os.Remove(path)
	}
	out = append(bytes.TrimRight(out, "\r\n"), '\n')
	if err := toml.Unmarshal(out, &map[string]any{}); err != nil {
		return fmt.Errorf("edited TOML is invalid: %w", err)
	}
	return writeConfigFile(path, out, 0o644)
}

// memoryPermissions are the permissions.allow entries that let Claude Code call
// the memory tools without prompting.
var memoryPermissions = []string{
	"mcp__memory__memory_add",
	"mcp__memory__memory_recent",
	"mcp__memory__memory_search",
	"mcp__memory__memory_get",
}

// mergeClaudeSettings merges agent-parity's keys into a Claude settings.json,
// preserving every other key the user has. It sets autoMemoryEnabled false, adds
// the memory server to enabledMcpjsonServers, adds the memory tool permissions to
// permissions.allow, and installs or refreshes the SessionStart sync hook whose
// command is hookCommand. Unlike a whole-file write this keeps user settings, and
// unlike a grep check it actually applies template changes on update. Repeatable.
func mergeClaudeSettings(path, hookCommand string) error {
	raw, err := os.ReadFile(path)
	if err != nil && !os.IsNotExist(err) {
		return err
	}
	root := map[string]any{}
	if len(bytes.TrimSpace(raw)) > 0 {
		dec := json.NewDecoder(bytes.NewReader(raw))
		dec.UseNumber()
		if err := dec.Decode(&root); err != nil {
			return err
		}
	}

	// Built-in auto memory would capture natural-language saves into Claude's own
	// store instead of the shared MCP, so agent-parity always disables it.
	root["autoMemoryEnabled"] = false
	root["enabledMcpjsonServers"] = addToStringArray(root["enabledMcpjsonServers"], "memory")

	perms, _ := root["permissions"].(map[string]any)
	if perms == nil {
		perms = map[string]any{}
	}
	allow := perms["allow"]
	for _, p := range memoryPermissions {
		allow = addToStringArray(allow, p)
	}
	perms["allow"] = allow
	root["permissions"] = perms

	root["hooks"] = mergeSessionStartHook(root["hooks"], hookCommand)

	out, err := json.MarshalIndent(root, "", "  ")
	if err != nil {
		return err
	}
	return writeConfigFile(path, append(out, '\n'), 0o644)
}

// addToStringArray returns existing (coerced to a slice) with val appended unless
// it is already present, leaving any other members untouched.
func addToStringArray(existing any, val string) []any {
	arr, _ := existing.([]any)
	for _, x := range arr {
		if s, ok := x.(string); ok && s == val {
			return arr
		}
	}
	return append(arr, val)
}

// mergeSessionStartHook installs our sync hook into hooks.SessionStart, keeping
// any hooks the user already has. If an old direct sync-claude command or the
// launcher-based sync command is present, it is refreshed to the current one.
func mergeSessionStartHook(existing any, command string) map[string]any {
	hooks, _ := existing.(map[string]any)
	if hooks == nil {
		hooks = map[string]any{}
	}
	ss, _ := hooks["SessionStart"].([]any)
	found := false
	for _, entry := range ss {
		em, ok := entry.(map[string]any)
		if !ok {
			continue
		}
		inner, ok := em["hooks"].([]any)
		if !ok {
			continue
		}
		for _, h := range inner {
			hm, ok := h.(map[string]any)
			if !ok {
				continue
			}
			if cmd, ok := hm["command"].(string); ok && isClaudeSyncCommand(cmd) {
				hm["command"] = command
				found = true
			}
		}
	}
	if !found {
		ss = append(ss, map[string]any{
			"hooks": []any{
				map[string]any{"type": "command", "command": command},
			},
		})
	}
	hooks["SessionStart"] = ss
	return hooks
}

// retargetMemoryConfig changes only an agent-parity-owned memory server
// command. A user-provided memory server is deliberately left untouched.
// The bool reports whether the file changed.
func retargetMemoryConfig(path, command string) (bool, error) {
	raw, err := os.ReadFile(path)
	if err != nil {
		return false, err
	}
	switch strings.ToLower(filepath.Ext(path)) {
	case ".json":
		return retargetJSON(path, raw, command)
	case ".toml":
		return retargetTOML(path, raw, command)
	default:
		return false, fmt.Errorf("unsupported config type: %s", path)
	}
}

func isManagedMemoryCommand(command string) bool {
	command = strings.TrimSpace(strings.ReplaceAll(command, `\`, "/"))
	for _, managed := range []string{
		".agents/mcp/memory/run.sh",
		".agents/mcp/memory/run.cmd",
		".agents/mcp/memory/dist/memory-mcp-linux-amd64",
		".agents/mcp/memory/dist/memory-mcp-linux-arm64",
		".agents/mcp/memory/dist/memory-mcp-darwin-amd64",
		".agents/mcp/memory/dist/memory-mcp-darwin-arm64",
		".agents/mcp/memory/dist/memory-mcp-windows-amd64.exe",
	} {
		if command == managed {
			return true
		}
	}
	return false
}

func retargetJSON(path string, raw []byte, command string) (bool, error) {
	root := map[string]any{}
	dec := json.NewDecoder(bytes.NewReader(raw))
	dec.UseNumber()
	if err := dec.Decode(&root); err != nil {
		return false, err
	}
	servers, ok := root["mcpServers"].(map[string]any)
	if !ok {
		return false, fmt.Errorf("mcpServers is not an object")
	}
	memory, ok := servers["memory"].(map[string]any)
	if !ok {
		return false, fmt.Errorf("memory server is not an object")
	}
	current, ok := memory["command"].(string)
	if !ok {
		return false, fmt.Errorf("memory server command is not a string")
	}
	if current == command {
		return false, nil
	}
	if !isManagedMemoryCommand(current) {
		return false, nil
	}
	memory["command"] = command
	out, err := json.MarshalIndent(root, "", "  ")
	if err != nil {
		return false, err
	}
	if err := writeConfigFile(path, append(out, '\n'), 0o644); err != nil {
		return false, err
	}
	return true, nil
}

func memoryCommandFromTOML(raw []byte) (string, error) {
	var root struct {
		MCPServers map[string]any `toml:"mcp_servers"`
	}
	if err := toml.Unmarshal(raw, &root); err != nil {
		return "", err
	}
	memory, ok := root.MCPServers["memory"].(map[string]any)
	if !ok {
		return "", fmt.Errorf("memory server is not a table")
	}
	command, ok := memory["command"].(string)
	if !ok {
		return "", fmt.Errorf("memory server command is not a string")
	}
	return command, nil
}

func retargetTOML(path string, raw []byte, command string) (bool, error) {
	current, err := memoryCommandFromTOML(raw)
	if err != nil {
		return false, err
	}
	if current == command {
		return false, nil
	}
	if !isManagedMemoryCommand(current) {
		return false, nil
	}

	span, err := tomlMemoryCommandSpan(raw)
	if err != nil {
		return false, err
	}
	out, err := applyTextEdits(raw, []textEdit{{start: span.start, end: span.end, replacement: []byte(strconv.Quote(command))}})
	if err != nil {
		return false, err
	}
	var check map[string]any
	if err := toml.Unmarshal(out, &check); err != nil {
		return false, fmt.Errorf("edited TOML is invalid: %w", err)
	}
	if err := writeConfigFile(path, out, 0o644); err != nil {
		return false, err
	}
	return true, nil
}

type textEdit struct {
	start       int
	end         int
	replacement []byte
}

type byteSpan struct {
	start int
	end   int
}

func applyTextEdits(raw []byte, edits []textEdit) ([]byte, error) {
	sort.Slice(edits, func(i, j int) bool { return edits[i].start > edits[j].start })
	out := append([]byte(nil), raw...)
	lastStart := len(raw)
	for _, edit := range edits {
		if edit.start < 0 || edit.end < edit.start || edit.end > len(raw) || edit.end > lastStart {
			return nil, fmt.Errorf("overlapping or invalid config edit %d:%d", edit.start, edit.end)
		}
		out = append(append(append([]byte(nil), out[:edit.start]...), edit.replacement...), out[edit.end:]...)
		lastStart = edit.start
	}
	return out, nil
}

func nodeKeys(node *unstable.Node) []string {
	var keys []string
	it := node.Key()
	for it.Next() {
		keys = append(keys, string(it.Node().Data))
	}
	return keys
}

func hasPathPrefix(path, prefix []string) bool {
	if len(path) < len(prefix) {
		return false
	}
	for i := range prefix {
		if path[i] != prefix[i] {
			return false
		}
	}
	return true
}

func samePath(a, b []string) bool {
	return len(a) == len(b) && hasPathPrefix(a, b)
}

func nodeBounds(node *unstable.Node) (byteSpan, bool) {
	start, end, found := 0, 0, false
	var visit func(*unstable.Node)
	visit = func(current *unstable.Node) {
		if current == nil {
			return
		}
		if current.Raw.Length > 0 {
			s := int(current.Raw.Offset)
			e := s + int(current.Raw.Length)
			if !found || s < start {
				start = s
			}
			if !found || e > end {
				end = e
			}
			found = true
		}
		children := current.Children()
		for children.Next() {
			visit(children.Node())
		}
	}
	visit(node)
	return byteSpan{start: start, end: end}, found
}

func lineBounds(raw []byte, span byteSpan) byteSpan {
	for span.start > 0 && raw[span.start-1] != '\n' {
		span.start--
	}
	for span.end < len(raw) && raw[span.end] != '\n' {
		span.end++
	}
	if span.end < len(raw) {
		span.end++
	}
	return span
}

func inlineEntryBounds(raw []byte, node *unstable.Node, container *unstable.Node) (byteSpan, error) {
	span, ok := nodeBounds(node)
	if !ok {
		return byteSpan{}, fmt.Errorf("TOML inline memory entry has no source range")
	}
	outer, ok := nodeBounds(container)
	if !ok {
		return byteSpan{}, fmt.Errorf("TOML inline table has no source range")
	}
	end := span.end
	for end < outer.end && (raw[end] == ' ' || raw[end] == '\t' || raw[end] == '\r' || raw[end] == '\n') {
		end++
	}
	if end < outer.end && raw[end] == ',' {
		end++
		for end < outer.end && (raw[end] == ' ' || raw[end] == '\t') {
			end++
		}
		return byteSpan{start: span.start, end: end}, nil
	}
	start := span.start
	for start > outer.start && (raw[start-1] == ' ' || raw[start-1] == '\t' || raw[start-1] == '\r' || raw[start-1] == '\n') {
		start--
	}
	if start > outer.start && raw[start-1] == ',' {
		start--
	}
	return byteSpan{start: start, end: span.end}, nil
}

func walkInlineKeyValues(node *unstable.Node, prefix []string, visit func(*unstable.Node, *unstable.Node, []string) bool) bool {
	if node == nil || node.Kind != unstable.InlineTable {
		return false
	}
	it := node.Children()
	for it.Next() {
		child := it.Node()
		if child.Kind != unstable.KeyValue {
			continue
		}
		path := append(append([]string(nil), prefix...), nodeKeys(child)...)
		if visit(child, node, path) {
			return true
		}
		if walkInlineKeyValues(child.Value(), path, visit) {
			return true
		}
	}
	return false
}

func parseTOMLExpressions(raw []byte, visit func(*unstable.Parser, *unstable.Node, []string) error) error {
	p := &unstable.Parser{KeepComments: true}
	p.Reset(raw)
	var table []string
	for p.NextExpression() {
		expr := p.Expression()
		switch expr.Kind {
		case unstable.Table, unstable.ArrayTable:
			table = nodeKeys(expr)
			if err := visit(p, expr, append([]string(nil), table...)); err != nil {
				return err
			}
		case unstable.KeyValue:
			path := append(append([]string(nil), table...), nodeKeys(expr)...)
			if err := visit(p, expr, path); err != nil {
				return err
			}
		}
	}
	return p.Error()
}

func tomlMemoryCommandSpan(raw []byte) (byteSpan, error) {
	target := []string{"mcp_servers", "memory", "command"}
	var found *byteSpan
	err := parseTOMLExpressions(raw, func(_ *unstable.Parser, expr *unstable.Node, path []string) error {
		if expr.Kind != unstable.KeyValue {
			return nil
		}
		if samePath(path, target) && expr.Value().Kind == unstable.String {
			span := byteSpan{start: int(expr.Value().Raw.Offset), end: int(expr.Value().Raw.Offset + expr.Value().Raw.Length)}
			found = &span
			return nil
		}
		walkInlineKeyValues(expr.Value(), path, func(child, _ *unstable.Node, childPath []string) bool {
			if samePath(childPath, target) && child.Value().Kind == unstable.String {
				span := byteSpan{start: int(child.Value().Raw.Offset), end: int(child.Value().Raw.Offset + child.Value().Raw.Length)}
				found = &span
				return true
			}
			return false
		})
		return nil
	})
	if err != nil {
		return byteSpan{}, err
	}
	if found == nil {
		return byteSpan{}, fmt.Errorf("mcp_servers.memory.command was parsed but its source value was not found")
	}
	return *found, nil
}

func tomlMemoryRemovalEdits(raw []byte) ([]textEdit, error) {
	target := []string{"mcp_servers", "memory"}
	var edits []textEdit
	err := parseTOMLExpressions(raw, func(_ *unstable.Parser, expr *unstable.Node, path []string) error {
		if hasPathPrefix(path, target) {
			span, ok := nodeBounds(expr)
			if !ok {
				return fmt.Errorf("TOML memory expression has no source range")
			}
			span = lineBounds(raw, span)
			edits = append(edits, textEdit{start: span.start, end: span.end})
			return nil
		}
		if expr.Kind != unstable.KeyValue {
			return nil
		}
		var nested *byteSpan
		var nestedErr error
		walkInlineKeyValues(expr.Value(), path, func(child, container *unstable.Node, childPath []string) bool {
			if samePath(childPath, target) {
				span, err := inlineEntryBounds(raw, child, container)
				if err != nil {
					nestedErr = err
				} else {
					nested = &span
				}
				return true
			}
			return false
		})
		if nestedErr != nil {
			return nestedErr
		}
		if nested != nil {
			edits = append(edits, textEdit{start: nested.start, end: nested.end})
		}
		return nil
	})
	return edits, err
}

func isClaudeSyncCommand(command string) bool {
	normalized := strings.TrimSpace(strings.ReplaceAll(command, `\`, "/"))
	for _, managed := range []string{
		`bash "$CLAUDE_PROJECT_DIR/.agents/scripts/sync-claude.sh" sync`,
		`powershell -NoProfile -ExecutionPolicy Bypass -Command "& \"$env:CLAUDE_PROJECT_DIR/.agents/scripts/sync-claude.ps1\" sync"`,
		`.agents/bin/agent-parity sync-claude`,
	} {
		if normalized == managed {
			return true
		}
	}
	return false
}

func isSelfHealCommand(command string, managed ...string) bool {
	normalized := strings.TrimSpace(strings.ReplaceAll(command, `\`, "/"))
	for _, candidate := range managed {
		if candidate != "" && normalized == strings.TrimSpace(strings.ReplaceAll(candidate, `\`, "/")) {
			return true
		}
	}
	return false
}

func readJSONObject(path string) (map[string]any, error) {
	raw, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	root := map[string]any{}
	dec := json.NewDecoder(bytes.NewReader(raw))
	dec.UseNumber()
	if err := dec.Decode(&root); err != nil {
		return nil, err
	}
	if err := dec.Decode(&struct{}{}); err != io.EOF {
		if err == nil {
			return nil, fmt.Errorf("multiple JSON values")
		}
		return nil, err
	}
	return root, nil
}

// hasClaudeSyncHook checks the actual Claude SessionStart hook path and exact
// command. An occurrence in any unrelated JSON field is deliberately ignored.
func hasClaudeSyncHook(path, command string) (bool, error) {
	root, err := readJSONObject(path)
	if err != nil {
		return false, err
	}
	hooks, _ := root["hooks"].(map[string]any)
	groups, _ := hooks["SessionStart"].([]any)
	for _, group := range groups {
		gm, _ := group.(map[string]any)
		handlers, _ := gm["hooks"].([]any)
		for _, handler := range handlers {
			hm, _ := handler.(map[string]any)
			if hm["type"] == "command" && hm["command"] == command {
				return true, nil
			}
		}
	}
	return false, nil
}

// hasAgentHook checks only the event/container defined for the named agent.
// For Codex both platform commands must be present because its hook format
// stores Unix and Windows commands together.
func hasAgentHook(path, kind string) (bool, error) {
	spec, err := hookSpec(kind)
	if err != nil {
		return false, err
	}
	root, err := readJSONObject(path)
	if err != nil {
		return false, err
	}
	if spec.nested {
		hooks, _ := root["hooks"].(map[string]any)
		groups, _ := hooks[spec.event].([]any)
		for _, group := range groups {
			gm, _ := group.(map[string]any)
			handlers, _ := gm["hooks"].([]any)
			for _, handler := range handlers {
				hm, _ := handler.(map[string]any)
				if hm["type"] != "command" || hm["command"] != spec.command {
					continue
				}
				if spec.commandWindows != "" && hm["commandWindows"] != spec.commandWindows {
					continue
				}
				return true, nil
			}
		}
		return false, nil
	}
	container := agentHookContainer(root, spec, false)
	handlers, _ := container[spec.event].([]any)
	for _, handler := range handlers {
		hm, _ := handler.(map[string]any)
		if hm["command"] == spec.command {
			return true, nil
		}
	}
	return false, nil
}

func hasCursorCLIAllowlist(path string) (bool, error) {
	root, err := readJSONObject(path)
	if err != nil {
		return false, err
	}
	permissions, _ := root["permissions"].(map[string]any)
	allow, _ := permissions["allow"].([]any)
	for _, item := range allow {
		if item == cursorCLIMemoryPermission {
			return true, nil
		}
	}
	return false, nil
}

type agentHookSpec struct {
	event          string
	command        string
	commandWindows string
	nested         bool
	container      string
	legacyCommands []string
}

// hookSpec is the single registry for agent-specific hook syntax. Hook merge
// and removal operate on this description instead of selecting agents again.
func hookSpec(kind string) (agentHookSpec, error) {
	switch kind {
	case "claude":
		return agentHookSpec{
			event: "SessionStart", command: `.agents/bin/agent-parity self-heal`, nested: true,
		}, nil
	case "codex":
		return agentHookSpec{
			event: "SessionStart", nested: true,
			command:        `sh -c 'root=$(git rev-parse --show-toplevel) && exec "$root/.agents/bin/agent-parity" self-heal'`,
			commandWindows: `powershell -NoProfile -ExecutionPolicy Bypass -Command "& (Join-Path (git rev-parse --show-toplevel) '.agents/bin/agent-parity.cmd') self-heal"`,
		}, nil
	case "cursor":
		return agentHookSpec{
			event: "sessionStart", container: "hooks",
			command:        ".agents/bin/agent-parity self-heal",
			legacyCommands: []string{".agents/bin/agent-parity.cmd self-heal"},
		}, nil
	case "antigravity":
		return agentHookSpec{
			event: "PreInvocation", container: "agent-parity",
			command:        ".agents/bin/agent-parity self-heal",
			legacyCommands: []string{".agents/bin/agent-parity.cmd self-heal"},
		}, nil
	default:
		return agentHookSpec{}, fmt.Errorf("unsupported hook kind: %s", kind)
	}
}

func agentHookCommands(spec agentHookSpec, command, commandWindows string) []string {
	commands := []string{command, commandWindows}
	commands = append(commands, spec.legacyCommands...)
	return commands
}

func agentHookContainer(root map[string]any, spec agentHookSpec, create bool) map[string]any {
	if spec.container == "" {
		return root
	}
	container, _ := root[spec.container].(map[string]any)
	if container == nil && create {
		container = map[string]any{}
		root[spec.container] = container
	}
	return container
}

func removeManagedHookHandlers(container map[string]any, event string, commands ...string) bool {
	if container == nil {
		return false
	}
	handlers, _ := container[event].([]any)
	kept := make([]any, 0, len(handlers))
	removed := false
	for _, handler := range handlers {
		hm, _ := handler.(map[string]any)
		command, _ := hm["command"].(string)
		if isSelfHealCommand(command, commands...) {
			removed = true
			continue
		}
		kept = append(kept, handler)
	}
	if len(kept) == 0 {
		delete(container, event)
	} else {
		container[event] = kept
	}
	return removed
}

// v0.6.0 wrote Antigravity's managed PreInvocation handler at the document
// root. Move only that exact released command; unrelated root fields remain.
func removeLegacyAntigravityHook(root map[string]any, commands ...string) {
	if !removeManagedHookHandlers(root, "PreInvocation", commands...) {
		return
	}
	if len(root) == 1 && root["enabled"] == true {
		delete(root, "enabled")
	}
}

// mergeAgentHook installs or refreshes only agent-parity's self-heal handler,
// preserving every user-defined hook in the same file.
func mergeAgentHook(path, kind, command, commandWindows string) error {
	spec, err := hookSpec(kind)
	if err != nil {
		return err
	}
	if command == "" {
		command = spec.command
		commandWindows = spec.commandWindows
	}
	managedCommands := agentHookCommands(spec, command, commandWindows)
	raw, err := os.ReadFile(path)
	if err != nil && !os.IsNotExist(err) {
		return err
	}
	root := map[string]any{}
	if len(bytes.TrimSpace(raw)) > 0 {
		dec := json.NewDecoder(bytes.NewReader(raw))
		dec.UseNumber()
		if err := dec.Decode(&root); err != nil {
			return err
		}
	}

	if spec.nested {
		hooks, _ := root["hooks"].(map[string]any)
		if hooks == nil {
			hooks = map[string]any{}
		}
		groups, _ := hooks[spec.event].([]any)
		found := false
		for _, group := range groups {
			gm, _ := group.(map[string]any)
			handlers, _ := gm["hooks"].([]any)
			for _, handler := range handlers {
				hm, _ := handler.(map[string]any)
				old, _ := hm["command"].(string)
				if !isSelfHealCommand(old, managedCommands...) {
					continue
				}
				hm["type"] = "command"
				hm["command"] = command
				hm["timeout"] = 30
				if kind == "codex" {
					hm["commandWindows"] = commandWindows
					hm["statusMessage"] = "Checking agent-parity MCP wiring"
				}
				found = true
			}
		}
		if !found {
			handler := map[string]any{"type": "command", "command": command, "timeout": 30}
			if kind == "codex" {
				handler["commandWindows"] = commandWindows
				handler["statusMessage"] = "Checking agent-parity MCP wiring"
			}
			groups = append(groups, map[string]any{"hooks": []any{handler}})
		}
		hooks[spec.event] = groups
		root["hooks"] = hooks
	} else {
		if kind == "cursor" {
			if _, exists := root["version"]; !exists {
				root["version"] = json.Number("1")
			}
		}
		if kind == "antigravity" {
			removeLegacyAntigravityHook(root, managedCommands...)
		}
		container := agentHookContainer(root, spec, true)
		if kind == "antigravity" {
			container["enabled"] = true
		}
		handlers, _ := container[spec.event].([]any)
		found := false
		for _, handler := range handlers {
			hm, _ := handler.(map[string]any)
			old, _ := hm["command"].(string)
			if isSelfHealCommand(old, managedCommands...) {
				hm["command"] = command
				hm["timeout"] = 30
				found = true
			}
		}
		if !found {
			handlers = append(handlers, map[string]any{"command": command, "timeout": 30})
		}
		container[spec.event] = handlers
	}

	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	out, err := json.MarshalIndent(root, "", "  ")
	if err != nil {
		return err
	}
	return writeConfigFile(path, append(out, '\n'), 0o644)
}

func unmergeAgentHook(path, kind string) error {
	spec, err := hookSpec(kind)
	if err != nil {
		return err
	}
	raw, err := os.ReadFile(path)
	if err != nil {
		if os.IsNotExist(err) {
			return nil
		}
		return err
	}
	root := map[string]any{}
	dec := json.NewDecoder(bytes.NewReader(raw))
	dec.UseNumber()
	if err := dec.Decode(&root); err != nil {
		return err
	}
	if spec.nested {
		hooks, _ := root["hooks"].(map[string]any)
		groups, _ := hooks[spec.event].([]any)
		keptGroups := []any{}
		for _, group := range groups {
			gm, _ := group.(map[string]any)
			handlers, _ := gm["hooks"].([]any)
			kept := []any{}
			for _, handler := range handlers {
				hm, _ := handler.(map[string]any)
				cmd, _ := hm["command"].(string)
				if !isSelfHealCommand(cmd, spec.command, spec.commandWindows) {
					kept = append(kept, handler)
				}
			}
			if len(kept) > 0 {
				gm["hooks"] = kept
				keptGroups = append(keptGroups, group)
			}
		}
		if len(keptGroups) == 0 {
			delete(hooks, spec.event)
		} else {
			hooks[spec.event] = keptGroups
		}
		if len(hooks) == 0 {
			delete(root, "hooks")
		}
	} else {
		managedCommands := agentHookCommands(spec, spec.command, spec.commandWindows)
		container := agentHookContainer(root, spec, false)
		removeManagedHookHandlers(container, spec.event, managedCommands...)
		if kind == "antigravity" {
			removeLegacyAntigravityHook(root, managedCommands...)
			if len(container) == 1 && container["enabled"] == true {
				delete(root, spec.container)
			}
		} else if container != nil && len(container) == 0 {
			delete(root, spec.container)
		}
	}
	if len(root) == 0 ||
		(kind == "cursor" && len(root) == 1 && root["version"] == json.Number("1")) {
		return os.Remove(path)
	}
	out, err := json.MarshalIndent(root, "", "  ")
	if err != nil {
		return err
	}
	return writeConfigFile(path, append(out, '\n'), 0o644)
}

// unmergeClaudeSettings removes the keys mergeClaudeSettings added — the
// autoMemoryEnabled flag, the memory server from enabledMcpjsonServers, the
// memory permissions, and the sync hook — leaving every other setting the user
// has. If nothing but our keys remained, the file is deleted outright.
func unmergeClaudeSettings(path string) error {
	raw, err := os.ReadFile(path)
	if err != nil {
		if os.IsNotExist(err) {
			return nil
		}
		return err
	}
	if len(bytes.TrimSpace(raw)) == 0 {
		return nil
	}
	root := map[string]any{}
	dec := json.NewDecoder(bytes.NewReader(raw))
	dec.UseNumber()
	if err := dec.Decode(&root); err != nil {
		return err
	}

	delete(root, "autoMemoryEnabled")

	if servers := removeStrings(root["enabledMcpjsonServers"], []string{"memory"}); len(servers) == 0 {
		delete(root, "enabledMcpjsonServers")
	} else {
		root["enabledMcpjsonServers"] = servers
	}

	if perms, ok := root["permissions"].(map[string]any); ok {
		if allow := removeStrings(perms["allow"], memoryPermissions); len(allow) == 0 {
			delete(perms, "allow")
		} else {
			perms["allow"] = allow
		}
		if len(perms) == 0 {
			delete(root, "permissions")
		} else {
			root["permissions"] = perms
		}
	}

	if hooks, ok := root["hooks"].(map[string]any); ok {
		if ss := removeSyncHook(hooks["SessionStart"]); len(ss) == 0 {
			delete(hooks, "SessionStart")
		} else {
			hooks["SessionStart"] = ss
		}
		if len(hooks) == 0 {
			delete(root, "hooks")
		} else {
			root["hooks"] = hooks
		}
	}

	if len(root) == 0 {
		return os.Remove(path)
	}
	out, err := json.MarshalIndent(root, "", "  ")
	if err != nil {
		return err
	}
	return writeConfigFile(path, append(out, '\n'), 0o644)
}

// removeStrings returns existing (coerced to a slice) with every element equal to
// one of vals dropped, preserving order and any non-matching members.
func removeStrings(existing any, vals []string) []any {
	arr, _ := existing.([]any)
	drop := map[string]bool{}
	for _, v := range vals {
		drop[v] = true
	}
	out := []any{}
	for _, x := range arr {
		if s, ok := x.(string); ok && drop[s] {
			continue
		}
		out = append(out, x)
	}
	return out
}

// removeSyncHook drops our direct or launcher-based sync entries from a
// SessionStart list, keeping any other hooks the user registered. An entry whose
// every hook was ours is removed entirely; one that mixed ours with theirs keeps
// only theirs.
func removeSyncHook(existing any) []any {
	ss, _ := existing.([]any)
	out := []any{}
	for _, entry := range ss {
		em, ok := entry.(map[string]any)
		if !ok {
			out = append(out, entry)
			continue
		}
		inner, ok := em["hooks"].([]any)
		if !ok {
			out = append(out, entry)
			continue
		}
		kept := []any{}
		for _, h := range inner {
			if hm, ok := h.(map[string]any); ok {
				if cmd, ok := hm["command"].(string); ok && isClaudeSyncCommand(cmd) {
					continue
				}
			}
			kept = append(kept, h)
		}
		if len(kept) == 0 {
			continue
		}
		em["hooks"] = kept
		out = append(out, em)
	}
	return out
}
