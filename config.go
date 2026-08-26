//go:build configeditor

package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"reflect"
	"sort"
	"strconv"
	"strings"

	"github.com/pelletier/go-toml/v2"
	"github.com/pelletier/go-toml/v2/unstable"
)

const cursorCLIMemoryPermission = "Mcp(memory:*)"
const codexMemoryApprovalMode = "approve"

func writeConfigFile(path string, data []byte, fallbackMode os.FileMode) error {
	mode := fallbackMode
	if existing, err := os.ReadFile(path); err == nil {
		// A Windows checkout commonly contains CRLF even though templates and
		// generated JSON use LF. Preserve the file's existing convention so a
		// semantic no-op does not dirty every managed config in Git.
		normalized := bytes.ReplaceAll(data, []byte("\r\n"), []byte("\n"))
		normalized = bytes.ReplaceAll(normalized, []byte("\r"), []byte("\n"))
		if bytes.Contains(existing, []byte("\r\n")) {
			data = bytes.ReplaceAll(normalized, []byte("\n"), []byte("\r\n"))
		} else if bytes.Contains(existing, []byte("\n")) {
			data = normalized
		}
	}
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

func hasCanonicalMemoryConfig(path, command string) (bool, error) {
	raw, err := os.ReadFile(path)
	if err != nil {
		return false, err
	}
	switch strings.ToLower(filepath.Ext(path)) {
	case ".json":
		root, err := readJSONObject(path)
		if err != nil {
			return false, err
		}
		servers, ok := root["mcpServers"].(map[string]any)
		if !ok {
			return false, fmt.Errorf("mcpServers is not an object")
		}
		memory, ok := servers["memory"].(map[string]any)
		if !ok {
			return false, nil
		}
		return reflect.DeepEqual(memory, canonicalMemoryJSON(command)), nil
	case ".toml":
		var root struct {
			MCPServers map[string]any `toml:"mcp_servers"`
		}
		if err := toml.Unmarshal(raw, &root); err != nil {
			return false, err
		}
		memory, ok := root.MCPServers["memory"].(map[string]any)
		if !ok {
			return false, nil
		}
		return reflect.DeepEqual(memory, canonicalMemoryTOML(command)), nil
	default:
		return false, fmt.Errorf("unsupported config type: %s", path)
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
	current, exists, err := configMemoryCommand(path)
	if err != nil {
		return false, err
	}
	if !exists {
		return true, mergeServerConfig(path, command)
	}
	if current != command && !isManagedMemoryCommand(current) {
		return false, fmt.Errorf("memory server command %q conflicts with agent-parity; edit it manually", current)
	}
	if strings.EqualFold(filepath.Ext(path), ".toml") {
		return ensureTOMLMemoryConfig(path, command)
	}
	return ensureJSONMemoryConfig(path, command)
}

func canonicalMemoryJSON(command string) map[string]any {
	return map[string]any{"command": command}
}

func canonicalMemoryTOML(command string) map[string]any {
	return map[string]any{
		"command":                     command,
		"default_tools_approval_mode": codexMemoryApprovalMode,
	}
}

func ensureJSONMemoryConfig(path, command string) (bool, error) {
	root, err := readJSONObject(path)
	if err != nil {
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
	if !isManagedMemoryCommand(current) {
		return false, fmt.Errorf("memory server command %q conflicts with agent-parity; edit it manually", current)
	}
	canonical := canonicalMemoryJSON(command)
	if reflect.DeepEqual(memory, canonical) {
		return false, nil
	}
	servers["memory"] = canonical
	out, err := json.MarshalIndent(root, "", "  ")
	if err != nil {
		return false, err
	}
	if err := writeConfigFile(path, append(out, '\n'), 0o644); err != nil {
		return false, err
	}
	return true, nil
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
		return nil // ownership is resolved by ensureMemoryConfig before convergence
	}
	// Parsing catches every valid TOML spelling of mcp_servers.memory. Appending
	// a fresh table preserves the existing file byte-for-byte, including comments.
	text := string(raw)
	if len(text) > 0 && !strings.HasSuffix(text, "\n") {
		text += "\n"
	}
	text += fmt.Sprintf("\n[mcp_servers.memory]\ncommand = %q\n", command)
	// A server default also covers tools added in future releases. Existing
	// per-tool overrides are validated by ensureTOMLMemoryConfig on updates.
	text += fmt.Sprintf("default_tools_approval_mode = %q\n", codexMemoryApprovalMode)
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
		if value, ok := item.(string); ok && value == cursorCLIMemoryPermission {
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
	"mcp__memory__memory_update",
	"mcp__memory__memory_governance",
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

	if err := validateOptionalArray(root, "enabledMcpjsonServers"); err != nil {
		return err
	}
	if value, exists := root["permissions"]; exists {
		perms, ok := value.(map[string]any)
		if !ok {
			return fmt.Errorf("permissions must be a JSON object")
		}
		if err := validateOptionalArray(perms, "allow"); err != nil {
			return fmt.Errorf("permissions.%w", err)
		}
	}
	if value, exists := root["hooks"]; exists {
		if err := validateNestedHookValue(value, "hooks", "SessionStart"); err != nil {
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

func validateOptionalArray(root map[string]any, key string) error {
	value, exists := root[key]
	if !exists {
		return nil
	}
	if _, ok := value.([]any); !ok {
		return fmt.Errorf("%s must be a JSON array", key)
	}
	return nil
}

func validateNestedHookValue(value any, path, event string) error {
	hooks, ok := value.(map[string]any)
	if !ok {
		return fmt.Errorf("%s must be a JSON object", path)
	}
	groupsValue, exists := hooks[event]
	if !exists {
		return nil
	}
	if _, ok := groupsValue.([]any); !ok {
		return fmt.Errorf("%s.%s must be a JSON array", path, event)
	}
	return nil
}

func validateFlatHookContainer(value any, path, event string) error {
	container, ok := value.(map[string]any)
	if !ok {
		return fmt.Errorf("%s must be a JSON object", path)
	}
	handlersValue, exists := container[event]
	if !exists {
		return nil
	}
	if _, ok := handlersValue.([]any); !ok {
		return fmt.Errorf("%s.%s must be a JSON array", path, event)
	}
	return nil
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
	canonical := map[string]any{"type": "command", "command": command}
	hooks["SessionStart"] = mergeNestedHandlers(hooks["SessionStart"], func(command string) bool {
		return isClaudeSyncCommand(command)
	}, canonical)
	return hooks
}

func mergeNestedHandlers(existing any, managed func(string) bool, canonical map[string]any) []any {
	groups, _ := existing.([]any)
	found := false
	out := make([]any, 0, len(groups)+1)
	for _, group := range groups {
		gm, ok := group.(map[string]any)
		if !ok {
			out = append(out, group)
			continue
		}
		handlers, ok := gm["hooks"].([]any)
		if !ok {
			out = append(out, group)
			continue
		}
		kept := make([]any, 0, len(handlers))
		for _, handler := range handlers {
			hm, ok := handler.(map[string]any)
			command, _ := hm["command"].(string)
			if !ok || !managed(command) {
				kept = append(kept, handler)
				continue
			}
			if !found {
				kept = append(kept, cloneMap(canonical))
				found = true
			}
		}
		if len(kept) > 0 {
			gm["hooks"] = kept
			out = append(out, group)
		} else if len(gm) > 1 {
			delete(gm, "hooks")
			out = append(out, group)
		}
	}
	if !found {
		out = append(out, map[string]any{"hooks": []any{cloneMap(canonical)}})
	}
	return out
}

func mergeFlatHandlers(existing any, managed func(string) bool, canonical map[string]any) []any {
	handlers, _ := existing.([]any)
	found := false
	out := make([]any, 0, len(handlers)+1)
	for _, handler := range handlers {
		hm, ok := handler.(map[string]any)
		command, _ := hm["command"].(string)
		if !ok || !managed(command) {
			out = append(out, handler)
			continue
		}
		if !found {
			out = append(out, cloneMap(canonical))
			found = true
		}
	}
	if !found {
		out = append(out, cloneMap(canonical))
	}
	return out
}

func cloneMap(value map[string]any) map[string]any {
	out := make(map[string]any, len(value))
	for key, item := range value {
		out[key] = item
	}
	return out
}

// retargetMemoryConfig converges an agent-parity-owned memory server namespace.
// A user-provided memory server is deliberately left untouched.
func retargetMemoryConfig(path, command string) (bool, error) {
	switch strings.ToLower(filepath.Ext(path)) {
	case ".json":
		return ensureJSONMemoryConfig(path, command)
	case ".toml":
		return ensureTOMLMemoryConfig(path, command)
	default:
		return false, fmt.Errorf("unsupported config type: %s", path)
	}
}

func isManagedMemoryCommand(command string) bool {
	command = strings.TrimSpace(strings.ReplaceAll(command, `\`, "/"))
	for _, managed := range []string{
		".agent-parity/mcp/memory/run.sh",
		".agent-parity/mcp/memory/run.cmd",
		// Legacy: the pre-v0.9.0 layout kept the launcher under .agents/, so an
		// update from that layout must recognize and retarget these commands.
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

// ensureTOMLMemoryConfig treats a memory table whose command is a known
// agent-parity launcher as an owned namespace and replaces that namespace with
// the canonical launcher and approval policy.
func ensureTOMLMemoryConfig(path, command string) (bool, error) {
	raw, err := os.ReadFile(path)
	if err != nil {
		return false, err
	}
	var root struct {
		MCPServers map[string]any `toml:"mcp_servers"`
	}
	if err := toml.Unmarshal(raw, &root); err != nil {
		return false, err
	}
	memoryValue, exists := root.MCPServers["memory"]
	if !exists {
		return false, fmt.Errorf("mcp_servers.memory is missing")
	}
	memory, ok := memoryValue.(map[string]any)
	if !ok {
		return false, fmt.Errorf("mcp_servers.memory must be a TOML table")
	}
	current, ok := memory["command"].(string)
	if !ok {
		return false, fmt.Errorf("mcp_servers.memory.command must be a string")
	}
	if !isManagedMemoryCommand(current) {
		return false, fmt.Errorf("mcp_servers.memory.command %q conflicts with agent-parity; edit it manually", current)
	}
	canonical := canonicalMemoryTOML(command)
	if reflect.DeepEqual(memory, canonical) {
		return false, nil
	}
	out, err := replaceTOMLMemoryConfig(raw, command)
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

func replaceTOMLMemoryConfig(raw []byte, command string) ([]byte, error) {
	if span, ok, err := tomlInlineMemorySpan(raw); err != nil {
		return nil, err
	} else if ok {
		replacement := []byte("memory = { command = " + strconv.Quote(command) + ", default_tools_approval_mode = " + strconv.Quote(codexMemoryApprovalMode) + " }")
		return applyTextEdits(raw, []textEdit{{start: span.start, end: span.end, replacement: replacement}})
	}
	edits, err := tomlMemoryRemovalEdits(raw)
	if err != nil {
		return nil, err
	}
	out, err := applyTextEdits(raw, edits)
	if err != nil {
		return nil, err
	}
	out = bytes.TrimRight(out, "\r\n")
	if len(bytes.TrimSpace(out)) > 0 {
		out = append(out, '\n', '\n')
	}
	out = append(out, []byte("[mcp_servers.memory]\ncommand = "+strconv.Quote(command)+"\ndefault_tools_approval_mode = "+strconv.Quote(codexMemoryApprovalMode)+"\n")...)
	return out, nil
}

func tomlInlineMemorySpan(raw []byte) (byteSpan, bool, error) {
	target := []string{"mcp_servers", "memory"}
	var found *byteSpan
	err := parseTOMLExpressions(raw, func(_ *unstable.Parser, expr *unstable.Node, path []string) error {
		if found != nil || expr.Kind != unstable.KeyValue || !samePath(path, []string{"mcp_servers"}) {
			return nil
		}
		walkInlineKeyValues(expr.Value(), path, func(child, _ *unstable.Node, childPath []string) bool {
			if !samePath(childPath, target) {
				return false
			}
			span, ok := nodeBounds(child)
			if ok {
				found = &span
			}
			return true
		})
		return nil
	})
	if err != nil || found == nil {
		return byteSpan{}, false, err
	}
	return *found, true, nil
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

// tomlMemoryApprovalInsert returns a source edit beside the existing memory
// command, supporting table, dotted-key, and inline-table spellings without
// reformatting unrelated TOML.
func tomlMemoryApprovalInsert(raw []byte) (textEdit, error) {
	target := []string{"mcp_servers", "memory", "command"}
	var found *textEdit
	err := parseTOMLExpressions(raw, func(_ *unstable.Parser, expr *unstable.Node, path []string) error {
		if found != nil || expr.Kind != unstable.KeyValue {
			return nil
		}
		if samePath(path, target) && expr.Value().Kind == unstable.String {
			span, ok := nodeBounds(expr)
			if !ok {
				return fmt.Errorf("TOML memory command has no source range")
			}
			line := lineBounds(raw, span)
			keys := nodeKeys(expr)
			if len(keys) == 0 {
				return fmt.Errorf("TOML memory command has no source key")
			}
			keys[len(keys)-1] = "default_tools_approval_mode"
			newline := "\n"
			if bytes.Contains(raw, []byte("\r\n")) {
				newline = "\r\n"
			}
			prefix := ""
			if line.end > 0 && raw[line.end-1] != '\n' {
				prefix = newline
			}
			replacement := prefix + strings.Join(keys, ".") + " = " + strconv.Quote(codexMemoryApprovalMode) + newline
			found = &textEdit{start: line.end, end: line.end, replacement: []byte(replacement)}
			return nil
		}
		walkInlineKeyValues(expr.Value(), path, func(child, container *unstable.Node, childPath []string) bool {
			if !samePath(childPath, target) || child.Value().Kind != unstable.String {
				return false
			}
			span, ok := nodeBounds(container)
			if !ok {
				return false
			}
			end := span.end
			for end < len(raw) && raw[end] != '}' {
				end++
			}
			if end >= len(raw) {
				return false
			}
			found = &textEdit{start: end, end: end, replacement: []byte(", default_tools_approval_mode = " + strconv.Quote(codexMemoryApprovalMode))}
			return true
		})
		return nil
	})
	if err != nil {
		return textEdit{}, err
	}
	if found == nil {
		return textEdit{}, fmt.Errorf("mcp_servers.memory.command was parsed but no safe approval insertion point was found")
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
		`bash "$CLAUDE_PROJECT_DIR/.agent-parity/scripts/sync-claude.sh" sync`,
		`powershell -NoProfile -ExecutionPolicy Bypass -Command "& \"$env:CLAUDE_PROJECT_DIR/.agent-parity/scripts/sync-claude.ps1\" sync"`,
		`.agent-parity/bin/agent-parity sync-claude`,
		// Legacy: the pre-v0.9.0 layout kept these under .agents/.
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
	hooks, ok := root["hooks"].(map[string]any)
	if !ok {
		return false, nil
	}
	canonical := map[string]any{"type": "command", "command": command}
	return hasCanonicalNestedHandler(hooks["SessionStart"], isClaudeSyncCommand, canonical), nil
}

func hasClaudeSettings(path, command string) (bool, error) {
	root, err := readJSONObject(path)
	if err != nil {
		return false, err
	}
	if root["autoMemoryEnabled"] != false {
		return false, nil
	}
	servers, ok := root["enabledMcpjsonServers"].([]any)
	if !ok || !containsString(servers, "memory") {
		return false, nil
	}
	permissions, ok := root["permissions"].(map[string]any)
	if !ok {
		return false, nil
	}
	allow, ok := permissions["allow"].([]any)
	if !ok {
		return false, nil
	}
	for _, permission := range memoryPermissions {
		if !containsString(allow, permission) {
			return false, nil
		}
	}
	return hasClaudeSyncHook(path, command)
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
		canonical := map[string]any{"type": "command", "command": spec.command, "timeout": json.Number("30")}
		if spec.commandWindows != "" {
			canonical["commandWindows"] = spec.commandWindows
			canonical["statusMessage"] = "Checking agent-parity MCP wiring"
		}
		managed := agentHookCommands(spec, spec.command, spec.commandWindows)
		return hasCanonicalNestedHandler(hooks[spec.event], func(command string) bool {
			return isSelfHealCommand(command, managed...)
		}, canonical), nil
	}
	container := agentHookContainer(root, spec, false)
	canonicalHandler := map[string]any{"command": spec.command, "timeout": json.Number("30")}
	if kind == "antigravity" {
		canonical := map[string]any{"enabled": true, spec.event: []any{canonicalHandler}}
		return reflect.DeepEqual(container, canonical), nil
	}
	managed := agentHookCommands(spec, spec.command, spec.commandWindows)
	return hasCanonicalFlatHandler(container[spec.event], func(command string) bool {
		return isSelfHealCommand(command, managed...)
	}, canonicalHandler), nil
}

func hasCursorCLIAllowlist(path string) (bool, error) {
	root, err := readJSONObject(path)
	if err != nil {
		return false, err
	}
	permissionsValue, exists := root["permissions"]
	if !exists {
		return false, nil
	}
	permissions, ok := permissionsValue.(map[string]any)
	if !ok {
		return false, fmt.Errorf("permissions must be a JSON object")
	}
	allowValue, exists := permissions["allow"]
	if !exists {
		return false, nil
	}
	allow, ok := allowValue.([]any)
	if !ok {
		return false, fmt.Errorf("permissions.allow must be a JSON array")
	}
	return containsString(allow, cursorCLIMemoryPermission), nil
}

func containsString(items []any, expected string) bool {
	for _, item := range items {
		if value, ok := item.(string); ok && value == expected {
			return true
		}
	}
	return false
}

func hasCanonicalNestedHandler(existing any, managed func(string) bool, canonical map[string]any) bool {
	groups, ok := existing.([]any)
	if !ok {
		return false
	}
	found := 0
	for _, group := range groups {
		gm, ok := group.(map[string]any)
		if !ok {
			continue
		}
		handlers, ok := gm["hooks"].([]any)
		if !ok {
			continue
		}
		for _, handler := range handlers {
			hm, ok := handler.(map[string]any)
			command, _ := hm["command"].(string)
			if ok && managed(command) {
				found++
				if !reflect.DeepEqual(hm, canonical) {
					return false
				}
			}
		}
	}
	return found == 1
}

func hasCanonicalFlatHandler(existing any, managed func(string) bool, canonical map[string]any) bool {
	handlers, ok := existing.([]any)
	if !ok {
		return false
	}
	found := 0
	for _, handler := range handlers {
		hm, ok := handler.(map[string]any)
		command, _ := hm["command"].(string)
		if ok && managed(command) {
			found++
			if !reflect.DeepEqual(hm, canonical) {
				return false
			}
		}
	}
	return found == 1
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
			event: "SessionStart", command: `.agent-parity/bin/agent-parity self-heal claude`, nested: true,
			legacyCommands: []string{`.agent-parity/bin/agent-parity self-heal`, `.agents/bin/agent-parity self-heal`, `.agents/bin/agent-parity.cmd self-heal`},
		}, nil
	case "codex":
		return agentHookSpec{
			event: "SessionStart", nested: true,
			command:        `sh -c 'root=$(git rev-parse --show-toplevel) && exec "$root/.agent-parity/bin/agent-parity" self-heal codex'`,
			commandWindows: `powershell -NoProfile -ExecutionPolicy Bypass -Command "& (Join-Path (git rev-parse --show-toplevel) '.agent-parity/bin/agent-parity.cmd') self-heal codex"`,
			legacyCommands: []string{
				`sh -c 'root=$(git rev-parse --show-toplevel) && exec "$root/.agent-parity/bin/agent-parity" self-heal'`,
				`powershell -NoProfile -ExecutionPolicy Bypass -Command "& (Join-Path (git rev-parse --show-toplevel) '.agent-parity/bin/agent-parity.cmd') self-heal"`,
				`sh -c 'root=$(git rev-parse --show-toplevel) && exec "$root/.agents/bin/agent-parity" self-heal'`,
				`powershell -NoProfile -ExecutionPolicy Bypass -Command "& (Join-Path (git rev-parse --show-toplevel) '.agents/bin/agent-parity.cmd') self-heal"`,
			},
		}, nil
	case "cursor":
		return agentHookSpec{
			event: "sessionStart", container: "hooks",
			command:        ".agent-parity/bin/agent-parity self-heal cursor",
			legacyCommands: []string{".agent-parity/bin/agent-parity self-heal", ".agents/bin/agent-parity self-heal", ".agents/bin/agent-parity.cmd self-heal"},
		}, nil
	case "antigravity":
		return agentHookSpec{
			event: "PreInvocation", container: "agent-parity",
			command:        ".agent-parity/bin/agent-parity self-heal antigravity",
			legacyCommands: []string{".agent-parity/bin/agent-parity self-heal", ".agents/bin/agent-parity self-heal", ".agents/bin/agent-parity.cmd self-heal"},
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
	handlers, ok := container[event].([]any)
	if !ok {
		return false
	}
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
	if !removed {
		return false
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
		if value, exists := root["hooks"]; exists {
			if err := validateNestedHookValue(value, "hooks", spec.event); err != nil {
				return err
			}
		}
	} else if kind != "antigravity" {
		value, exists := root[spec.container]
		if !exists {
			value = map[string]any{}
		}
		if err := validateFlatHookContainer(value, spec.container, spec.event); err != nil {
			return err
		}
	}

	if spec.nested {
		hooks, _ := root["hooks"].(map[string]any)
		if hooks == nil {
			hooks = map[string]any{}
		}
		handler := map[string]any{"type": "command", "command": command, "timeout": json.Number("30")}
		if kind == "codex" {
			handler["commandWindows"] = commandWindows
			handler["statusMessage"] = "Checking agent-parity MCP wiring"
		}
		hooks[spec.event] = mergeNestedHandlers(hooks[spec.event], func(old string) bool {
			return isSelfHealCommand(old, managedCommands...)
		}, handler)
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
		if kind == "antigravity" {
			root[spec.container] = map[string]any{
				"enabled":  true,
				spec.event: []any{map[string]any{"command": command, "timeout": json.Number("30")}},
			}
		} else {
			container := agentHookContainer(root, spec, true)
			canonical := map[string]any{"command": command, "timeout": json.Number("30")}
			container[spec.event] = mergeFlatHandlers(container[spec.event], func(old string) bool {
				return isSelfHealCommand(old, managedCommands...)
			}, canonical)
		}
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
		hooks, ok := root["hooks"].(map[string]any)
		if !ok {
			return nil
		}
		groups, ok := hooks[spec.event].([]any)
		if !ok {
			return nil
		}
		keptGroups := []any{}
		managedCommands := agentHookCommands(spec, spec.command, spec.commandWindows)
		for _, group := range groups {
			gm, ok := group.(map[string]any)
			if !ok {
				keptGroups = append(keptGroups, group)
				continue
			}
			handlers, ok := gm["hooks"].([]any)
			if !ok {
				keptGroups = append(keptGroups, group)
				continue
			}
			kept := []any{}
			removed := false
			for _, handler := range handlers {
				hm, _ := handler.(map[string]any)
				cmd, _ := hm["command"].(string)
				if isSelfHealCommand(cmd, managedCommands...) {
					removed = true
					continue
				}
				kept = append(kept, handler)
			}
			if len(kept) > 0 {
				gm["hooks"] = kept
				keptGroups = append(keptGroups, group)
			} else if !removed || len(gm) > 1 {
				if removed {
					delete(gm, "hooks")
				}
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
		if kind == "antigravity" {
			delete(root, spec.container)
			removeLegacyAntigravityHook(root, managedCommands...)
		} else {
			container := agentHookContainer(root, spec, false)
			removeManagedHookHandlers(container, spec.event, managedCommands...)
			if container != nil && len(container) == 0 {
				delete(root, spec.container)
			}
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

	if existing, ok := root["enabledMcpjsonServers"].([]any); ok {
		if servers := removeStrings(existing, []string{"memory"}); len(servers) == 0 {
			delete(root, "enabledMcpjsonServers")
		} else {
			root["enabledMcpjsonServers"] = servers
		}
	}

	if perms, ok := root["permissions"].(map[string]any); ok {
		if existing, ok := perms["allow"].([]any); ok {
			if allow := removeStrings(existing, memoryPermissions); len(allow) == 0 {
				delete(perms, "allow")
			} else {
				perms["allow"] = allow
			}
		}
		if len(perms) == 0 {
			delete(root, "permissions")
		} else {
			root["permissions"] = perms
		}
	}

	if hooks, ok := root["hooks"].(map[string]any); ok {
		if existing, ok := hooks["SessionStart"].([]any); ok {
			if ss := removeSyncHook(existing); len(ss) == 0 {
				delete(hooks, "SessionStart")
			} else {
				hooks["SessionStart"] = ss
			}
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
