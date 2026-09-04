//go:build configeditor

package main

import (
	"bytes"
	"encoding/json"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"

	"github.com/pelletier/go-toml/v2"
)

func readSettings(t *testing.T, path string) map[string]any {
	t.Helper()
	raw, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	m := map[string]any{}
	if err := json.Unmarshal(raw, &m); err != nil {
		t.Fatal(err)
	}
	return m
}

func mustRead(t *testing.T, path string) []byte {
	t.Helper()
	raw, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	return raw
}

func hasStr(v any, want string) bool {
	arr, _ := v.([]any)
	for _, x := range arr {
		if s, ok := x.(string); ok && s == want {
			return true
		}
	}
	return false
}

func mustJSON(t *testing.T, m map[string]any) string {
	t.Helper()
	b, err := json.Marshal(m)
	if err != nil {
		t.Fatal(err)
	}
	return string(b)
}

func TestWriteConfigFilePreservesCRLF(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.json")
	if err := os.WriteFile(path, []byte("{\r\n  \"old\": true\r\n}\r\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := writeConfigFile(path, []byte("{\n  \"new\": true\n}\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	raw := mustRead(t, path)
	if bytes.Contains(bytes.ReplaceAll(raw, []byte("\r\n"), nil), []byte("\n")) {
		t.Fatalf("writeConfigFile introduced bare LF into CRLF file: %q", raw)
	}
	if !bytes.Contains(raw, []byte("\r\n")) {
		t.Fatalf("writeConfigFile did not preserve CRLF: %q", raw)
	}
}

func TestMergeClaudeSettingsFresh(t *testing.T) {
	path := filepath.Join(t.TempDir(), "settings.json")
	if err := mergeClaudeSettings(path, ".agent-parity/bin/agent-parity sync-claude"); err != nil {
		t.Fatal(err)
	}
	m := readSettings(t, path)
	if m["autoMemoryEnabled"] != false {
		t.Errorf("autoMemoryEnabled = %v, want false", m["autoMemoryEnabled"])
	}
	if !hasStr(m["enabledMcpjsonServers"], "memory") {
		t.Error("enabledMcpjsonServers missing memory")
	}
	perms, _ := m["permissions"].(map[string]any)
	for _, p := range memoryPermissions {
		if !hasStr(perms["allow"], p) {
			t.Errorf("permissions.allow missing %s", p)
		}
	}
	if !strings.Contains(mustJSON(t, m), ".agent-parity/bin/agent-parity sync-claude") {
		t.Error("sync hook not installed")
	}
}

func TestMergeClaudeSettingsPreservesUserKeysAndRefreshesHook(t *testing.T) {
	path := filepath.Join(t.TempDir(), "settings.json")
	original := `{
	  "model": "opus",
	  "enabledMcpjsonServers": ["other"],
	  "permissions": {"allow": ["Bash(ls)"], "deny": ["Read(secret)"]},
	  "hooks": {"SessionStart": [
	    {"hooks": [{"type": "command", "command": "echo user-hook"}]},
	    {"hooks": [{"type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR/.agent-parity/scripts/sync-claude.sh\" sync"}]}
	  ]}
	}`
	if err := os.WriteFile(path, []byte(original), 0o644); err != nil {
		t.Fatal(err)
	}
	newHook := ".agent-parity/bin/agent-parity sync-claude"
	if err := mergeClaudeSettings(path, newHook); err != nil {
		t.Fatal(err)
	}
	m := readSettings(t, path)
	if m["model"] != "opus" {
		t.Errorf("user model lost: %v", m["model"])
	}
	if !hasStr(m["enabledMcpjsonServers"], "other") || !hasStr(m["enabledMcpjsonServers"], "memory") {
		t.Errorf("enabledMcpjsonServers = %v", m["enabledMcpjsonServers"])
	}
	perms := m["permissions"].(map[string]any)
	if !hasStr(perms["allow"], "Bash(ls)") {
		t.Error("user allow lost")
	}
	if !hasStr(perms["deny"], "Read(secret)") {
		t.Error("user deny lost")
	}
	blob := mustJSON(t, m)
	if strings.Contains(blob, "$CLAUDE_PROJECT_DIR") {
		t.Error("old hook path not refreshed")
	}
	if !strings.Contains(blob, newHook) {
		t.Error("new hook not present")
	}
	if !strings.Contains(blob, "echo user-hook") {
		t.Error("user hook lost")
	}
	if n := strings.Count(blob, "agent-parity sync-claude"); n != 1 {
		t.Errorf("expected exactly one sync hook, got %d", n)
	}
	before, _ := os.ReadFile(path)
	if err := mergeClaudeSettings(path, newHook); err != nil {
		t.Fatal(err)
	}
	after, _ := os.ReadFile(path)
	if string(before) != string(after) {
		t.Errorf("merge not idempotent:\n%s\nvs\n%s", before, after)
	}
}

func TestMergeClaudeSettingsRejectsConflictsAndWrongTypesWithoutRewriting(t *testing.T) {
	tests := map[string]string{
		"servers-type":     `{"enabledMcpjsonServers":"memory"}`,
		"permissions-type": `{"permissions":"custom"}`,
		"allow-type":       `{"permissions":{"allow":"custom"}}`,
		"hooks-type":       `{"hooks":"custom"}`,
		"session-type":     `{"hooks":{"SessionStart":"custom"}}`,
	}
	for name, original := range tests {
		t.Run(name, func(t *testing.T) {
			path := filepath.Join(t.TempDir(), "settings.json")
			if err := os.WriteFile(path, []byte(original), 0o644); err != nil {
				t.Fatal(err)
			}
			if err := mergeClaudeSettings(path, ".agent-parity/bin/agent-parity sync-claude"); err == nil {
				t.Fatal("expected conflicting or malformed settings to be rejected")
			}
			got, _ := os.ReadFile(path)
			if string(got) != original {
				t.Fatalf("user settings were rewritten: %s", got)
			}
		})
	}
}

func TestMergeClaudeSettingsOwnsScalarsAndPreservesOpaqueArrayMembers(t *testing.T) {
	path := filepath.Join(t.TempDir(), "settings.json")
	original := `{"autoMemoryEnabled":"wrong","enabledMcpjsonServers":[42,"other"],"permissions":{"allow":[42,{"custom":true}]},"hooks":{"SessionStart":[42,{"hooks":[42,{"command":"echo user"}]}]}}`
	if err := os.WriteFile(path, []byte(original), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := mergeClaudeSettings(path, ".agent-parity/bin/agent-parity sync-claude"); err != nil {
		t.Fatal(err)
	}
	root := readSettings(t, path)
	if root["autoMemoryEnabled"] != false || !hasStr(root["enabledMcpjsonServers"], "memory") {
		t.Fatalf("owned Claude settings did not converge: %#v", root)
	}
	if !strings.Contains(string(mustRead(t, path)), `42`) || !strings.Contains(string(mustRead(t, path)), `"custom": true`) || !strings.Contains(string(mustRead(t, path)), "echo user") {
		t.Fatalf("opaque user members were not preserved: %s", mustRead(t, path))
	}
}

func TestUnmergeClaudeSettingsRoundTrip(t *testing.T) {
	// Only our keys: the file is deleted outright.
	path := filepath.Join(t.TempDir(), "settings.json")
	if err := mergeClaudeSettings(path, ".agent-parity/bin/agent-parity sync-claude"); err != nil {
		t.Fatal(err)
	}
	if err := unmergeClaudeSettings(path); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(path); !os.IsNotExist(err) {
		t.Errorf("file should be deleted when only our keys remained, err=%v", err)
	}

	// User keys present: the file is kept, only our keys removed.
	path2 := filepath.Join(t.TempDir(), "settings.json")
	original := `{"model":"opus","enabledMcpjsonServers":["other"],"permissions":{"allow":["Bash(ls)"]},"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"echo user-hook"}]}]}}`
	if err := os.WriteFile(path2, []byte(original), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := mergeClaudeSettings(path2, ".agent-parity/bin/agent-parity sync-claude"); err != nil {
		t.Fatal(err)
	}
	if err := unmergeClaudeSettings(path2); err != nil {
		t.Fatal(err)
	}
	m := readSettings(t, path2)
	if m["model"] != "opus" {
		t.Error("user model lost on unmerge")
	}
	if _, ok := m["autoMemoryEnabled"]; ok {
		t.Error("autoMemoryEnabled not removed")
	}
	if hasStr(m["enabledMcpjsonServers"], "memory") {
		t.Error("memory not removed from enabledMcpjsonServers")
	}
	if !hasStr(m["enabledMcpjsonServers"], "other") {
		t.Error("user server lost")
	}
	perms := m["permissions"].(map[string]any)
	if !hasStr(perms["allow"], "Bash(ls)") {
		t.Error("user allow lost on unmerge")
	}
	for _, p := range memoryPermissions {
		if hasStr(perms["allow"], p) {
			t.Errorf("memory perm %s not removed", p)
		}
	}
	blob := mustJSON(t, m)
	if strings.Contains(blob, "sync-claude") {
		t.Error("sync hook not removed")
	}
	if !strings.Contains(blob, "echo user-hook") {
		t.Error("user hook lost on unmerge")
	}
}

func TestUnmergeCursorCLIPreservesUserSettings(t *testing.T) {
	path := filepath.Join(t.TempDir(), "cli.json")
	original := `{"theme":"dark","permissions":{"allow":["Shell(git:*)","Mcp(memory:*)"],"deny":["Shell(rm:*)"]}}`
	if err := os.WriteFile(path, []byte(original), 0o644); err != nil {
		t.Fatal(err)
	}
	changed, err := runConfigMutation(path, unmergeCursorCLI)
	if err != nil || !changed {
		t.Fatalf("changed=%v err=%v", changed, err)
	}
	root := readSettings(t, path)
	if root["theme"] != "dark" {
		t.Fatal("user setting was lost")
	}
	permissions := root["permissions"].(map[string]any)
	if !hasStr(permissions["allow"], "Shell(git:*)") || hasStr(permissions["allow"], "Mcp(memory:*)") {
		t.Fatalf("allowlist was not selectively cleaned: %#v", permissions["allow"])
	}
	if !hasStr(permissions["deny"], "Shell(rm:*)") {
		t.Fatal("deny list was lost")
	}
}

func TestMergeCursorCLIPreservesUserSettingsAndIsIdempotent(t *testing.T) {
	path := filepath.Join(t.TempDir(), ".cursor", "cli.json")
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	original := `{"theme":"dark","permissions":{"allow":["Shell(git:*)"],"deny":["Shell(rm:*)"]}}`
	if err := os.WriteFile(path, []byte(original), 0o644); err != nil {
		t.Fatal(err)
	}

	changed, err := mergeCursorCLI(path)
	if err != nil || !changed {
		t.Fatalf("changed=%v err=%v", changed, err)
	}
	root := readSettings(t, path)
	if root["theme"] != "dark" {
		t.Fatal("user setting was lost")
	}
	permissions := root["permissions"].(map[string]any)
	if !hasStr(permissions["allow"], "Shell(git:*)") || !hasStr(permissions["allow"], cursorCLIMemoryPermission) {
		t.Fatalf("allowlist was not merged: %#v", permissions["allow"])
	}
	if !hasStr(permissions["deny"], "Shell(rm:*)") {
		t.Fatal("deny list was lost")
	}

	first, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	changed, err = mergeCursorCLI(path)
	if err != nil || changed {
		t.Fatalf("second merge changed=%v err=%v", changed, err)
	}
	second, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(first, second) {
		t.Fatal("idempotent merge rewrote the file")
	}
}

func TestMergeCursorCLICreatesMissingFile(t *testing.T) {
	path := filepath.Join(t.TempDir(), ".cursor", "cli.json")
	changed, err := mergeCursorCLI(path)
	if err != nil || !changed {
		t.Fatalf("changed=%v err=%v", changed, err)
	}
	has, err := hasCursorCLIAllowlist(path)
	if err != nil || !has {
		t.Fatalf("created allowlist has=%v err=%v", has, err)
	}
}

func TestMergeCursorCLIRejectsInvalidStructureWithoutRewriting(t *testing.T) {
	for name, original := range map[string]string{
		"permissions": `{"permissions":"user-value"}`,
		"allow":       `{"permissions":{"allow":"user-value"}}`,
	} {
		t.Run(name, func(t *testing.T) {
			path := filepath.Join(t.TempDir(), "cli.json")
			if err := os.WriteFile(path, []byte(original), 0o644); err != nil {
				t.Fatal(err)
			}
			if changed, err := mergeCursorCLI(path); err == nil || changed {
				t.Fatalf("changed=%v err=%v", changed, err)
			}
			after, err := os.ReadFile(path)
			if err != nil {
				t.Fatal(err)
			}
			if string(after) != original {
				t.Fatalf("invalid user file was rewritten: %s", after)
			}
		})
	}
}

func TestMergeCursorCLIPreservesOpaqueAllowMembers(t *testing.T) {
	path := filepath.Join(t.TempDir(), "cli.json")
	if err := os.WriteFile(path, []byte(`{"permissions":{"allow":[42,{"custom":true},"Shell(git:*)"]}}`), 0o644); err != nil {
		t.Fatal(err)
	}
	changed, err := mergeCursorCLI(path)
	if err != nil || !changed {
		t.Fatalf("changed=%v err=%v", changed, err)
	}
	raw := mustRead(t, path)
	if !bytes.Contains(raw, []byte(`42`)) || !bytes.Contains(raw, []byte(`"custom": true`)) || !bytes.Contains(raw, []byte(cursorCLIMemoryPermission)) {
		t.Fatalf("opaque allow members were not preserved: %s", raw)
	}
}

func TestUnmergeCursorCLIRemovesOwnedEmptyScaffold(t *testing.T) {
	path := filepath.Join(t.TempDir(), "cli.json")
	if err := os.WriteFile(path, []byte(`{"permissions":{"allow":["Mcp(memory:*)"],"deny":[]}}`), 0o644); err != nil {
		t.Fatal(err)
	}
	changed, err := runConfigMutation(path, unmergeCursorCLI)
	if err != nil || !changed {
		t.Fatalf("changed=%v err=%v", changed, err)
	}
	if _, err := os.Stat(path); !os.IsNotExist(err) {
		t.Fatalf("owned empty scaffold remains: %v", err)
	}
}

func TestMergeTOMLRecognizesEquivalentMemoryEntries(t *testing.T) {
	tests := []string{
		"[mcp_servers.memory]\ncommand = \"other\"\n",
		"[mcp_servers.\"memory\"]\ncommand = \"other\"\n",
		"mcp_servers.memory.command = \"other\"\n",
		"[mcp_servers]\nmemory = { command = \"other\" }\n",
	}
	for _, original := range tests {
		t.Run(original, func(t *testing.T) {
			path := filepath.Join(t.TempDir(), "config.toml")
			if err := os.WriteFile(path, []byte(original), 0o644); err != nil {
				t.Fatal(err)
			}
			if err := mergeServerConfig(path, ".agent-parity/mcp/memory/run.sh"); err != nil {
				t.Fatal(err)
			}
			got, err := os.ReadFile(path)
			if err != nil {
				t.Fatal(err)
			}
			if string(got) != original {
				t.Fatalf("existing memory entry was modified:\n%s", got)
			}
		})
	}
}

func TestMergeTOMLAppendsAndPreservesExistingText(t *testing.T) {
	original := "# keep this comment\n[mcp_servers.other]\ncommand = \"other\"\n"
	path := filepath.Join(t.TempDir(), "config.toml")
	if err := os.WriteFile(path, []byte(original), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := mergeServerConfig(path, ".agent-parity/mcp/memory/run.sh"); err != nil {
		t.Fatal(err)
	}
	got, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.HasPrefix(string(got), original) {
		t.Fatalf("existing TOML was rewritten:\n%s", got)
	}
	if strings.Count(string(got), "[mcp_servers.memory]") != 1 {
		t.Fatalf("memory table not appended exactly once:\n%s", got)
	}
}

func TestMergeTOMLAppendsDefaultApproval(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.toml")
	if err := os.WriteFile(path, []byte(""), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := mergeServerConfig(path, ".agent-parity/mcp/memory/run.sh"); err != nil {
		t.Fatal(err)
	}
	got, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	text := string(got)
	if strings.Count(text, "[mcp_servers.memory]") != 1 {
		t.Fatalf("memory server table not appended exactly once:\n%s", text)
	}
	if strings.Count(text, `default_tools_approval_mode = "approve"`) != 1 {
		t.Fatalf("expected one default approval line, got:\n%s", text)
	}
}

func TestEnsureTOMLBackfillsDefaultApproval(t *testing.T) {
	tests := map[string]string{
		"table":  "# keep\n[mcp_servers.memory]\ncommand = \".agent-parity/mcp/memory/run.sh\"\n",
		"dotted": "# keep\nmcp_servers.memory.command = \".agent-parity/mcp/memory/run.sh\"\n",
		"inline": "# keep\nmcp_servers = { memory = { command = \".agent-parity/mcp/memory/run.sh\" } }\n",
	}
	for name, original := range tests {
		t.Run(name, func(t *testing.T) {
			path := filepath.Join(t.TempDir(), "config.toml")
			if err := os.WriteFile(path, []byte(original), 0o644); err != nil {
				t.Fatal(err)
			}
			changed, err := ensureMemoryConfig(path, ".agent-parity/mcp/memory/run.sh")
			if err != nil || !changed {
				t.Fatalf("changed=%v err=%v", changed, err)
			}
			got, err := os.ReadFile(path)
			if err != nil {
				t.Fatal(err)
			}
			if !strings.Contains(string(got), "# keep") || strings.Count(string(got), `default_tools_approval_mode = "approve"`) != 1 {
				t.Fatalf("approval was not added without losing user text:\n%s", got)
			}
			changed, err = ensureMemoryConfig(path, ".agent-parity/mcp/memory/run.sh")
			if err != nil || changed {
				t.Fatalf("second ensure changed=%v err=%v", changed, err)
			}
		})
	}
}

func TestEnsureTOMLOwnedNamespaceOverwritesDescendants(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.toml")
	original := "[mcp_servers.memory]\ncommand = \".agent-parity/mcp/memory/run.sh\"\ndefault_tools_approval_mode = \"prompt\"\n"
	if err := os.WriteFile(path, []byte(original), 0o644); err != nil {
		t.Fatal(err)
	}
	if changed, err := ensureMemoryConfig(path, ".agent-parity/mcp/memory/run.sh"); err != nil || !changed {
		t.Fatalf("changed=%v err=%v", changed, err)
	}
	got, _ := os.ReadFile(path)
	if strings.Contains(string(got), "prompt") || strings.Count(string(got), `default_tools_approval_mode = "approve"`) != 1 {
		t.Fatalf("owned TOML namespace did not converge:\n%s", got)
	}
}

func TestUnmergeTOMLRemovesServerAndApprovalTools(t *testing.T) {
	original := "# keep this comment\n[mcp_servers.other]\ncommand = \"other\"\n"
	path := filepath.Join(t.TempDir(), "config.toml")
	if err := os.WriteFile(path, []byte(original), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := mergeServerConfig(path, ".agent-parity/mcp/memory/run.sh"); err != nil {
		t.Fatal(err)
	}
	if err := unmergeServerConfig(path); err != nil {
		t.Fatal(err)
	}
	got, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	text := string(got)
	if strings.Contains(text, "mcp_servers.memory") {
		t.Fatalf("memory server/approval tables not fully removed:\n%s", text)
	}
	if strings.Contains(text, "approval_mode") {
		t.Fatalf("approval_mode lines survived unmerge:\n%s", text)
	}
	// Unrelated content survives.
	if !strings.Contains(text, "# keep this comment") || !strings.Contains(text, "[mcp_servers.other]") {
		t.Fatalf("unrelated config was not preserved:\n%s", text)
	}
}

func TestMergeUnmergeTOMLRoundTripRestoresOriginal(t *testing.T) {
	original := "# keep this comment\n[mcp_servers.other]\ncommand = \"other\"\n"
	path := filepath.Join(t.TempDir(), "config.toml")
	if err := os.WriteFile(path, []byte(original), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := mergeServerConfig(path, ".agent-parity/mcp/memory/run.sh"); err != nil {
		t.Fatal(err)
	}
	if err := unmergeServerConfig(path); err != nil {
		t.Fatal(err)
	}
	got, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if string(got) != original {
		t.Fatalf("round-trip did not restore original:\nwant:\n%q\ngot:\n%q", original, string(got))
	}
}

func TestMergeTOMLRejectsInvalidInput(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.toml")
	if err := os.WriteFile(path, []byte("invalid = [\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := mergeServerConfig(path, ".agent-parity/mcp/memory/run.sh"); err == nil {
		t.Fatal("expected invalid TOML to be rejected")
	}
}

// A file can parse and still be unable to take an appended table: TOML forbids
// extending a key already defined as an inline-table value. Every other TOML
// writer here re-reads its output before committing it; mergeTOML did not, so
// it wrote a file Codex could no longer read and reported success. The file has
// to survive intact, and the caller has to hear about it.
func TestMergeTOMLRefusesToBreakAnInlineServersTable(t *testing.T) {
	for _, content := range []string{
		"model = \"o3\"\nmcp_servers = { mine = { command = \"my-server\" } }\n",
		"mcp_servers = {}\n",
	} {
		path := filepath.Join(t.TempDir(), "config.toml")
		if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
			t.Fatal(err)
		}
		err := mergeServerConfig(path, ".agent-parity/mcp/memory/run.sh")
		if err == nil {
			after, _ := os.ReadFile(path)
			t.Fatalf("appending to an inline table was reported as success:\n%s", after)
		}
		after, readErr := os.ReadFile(path)
		if readErr != nil {
			t.Fatal(readErr)
		}
		if string(after) != content {
			t.Fatalf("the refused merge still modified the file:\n%s", after)
		}
		// The file must remain something the rest of the tool can read.
		if uErr := toml.Unmarshal(after, &map[string]any{}); uErr != nil {
			t.Fatalf("the file no longer parses: %v", uErr)
		}
	}
}

func TestHasMemoryServerRecognizesEquivalentTOML(t *testing.T) {
	for _, content := range []string{
		"[mcp_servers.\"memory\"]\ncommand = \"other\"\n",
		"mcp_servers.memory.command = \"other\"\n",
		"[mcp_servers]\nmemory = { command = \"other\" }\n",
	} {
		path := filepath.Join(t.TempDir(), "config.toml")
		if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
			t.Fatal(err)
		}
		exists, err := hasMemoryServer(path)
		if err != nil {
			t.Fatal(err)
		}
		if !exists {
			t.Fatalf("memory entry not detected in %q", content)
		}
	}
}

func TestRetargetJSONReplacesManagedMemoryNamespace(t *testing.T) {
	path := filepath.Join(t.TempDir(), "mcp.json")
	original := `{"other":"keep","mcpServers":{"other":{"command":"other"},"memory":{"command":".agent-parity/mcp/memory/run.sh","args":["--keep"]}}}`
	if err := os.WriteFile(path, []byte(original), 0o644); err != nil {
		t.Fatal(err)
	}
	changed, err := retargetMemoryConfig(path, ".agent-parity/mcp/memory/run.cmd")
	if err != nil || !changed {
		t.Fatalf("changed=%v err=%v", changed, err)
	}
	m := readSettings(t, path)
	servers := m["mcpServers"].(map[string]any)
	memory := servers["memory"].(map[string]any)
	if !reflect.DeepEqual(memory, canonicalMemoryJSON(".agent-parity/mcp/memory/run.cmd")) {
		t.Fatalf("memory namespace did not converge: %#v", memory)
	}
	if servers["other"].(map[string]any)["command"] != "other" || m["other"] != "keep" {
		t.Fatal("unrelated JSON content changed")
	}
	changed, err = retargetMemoryConfig(path, ".agent-parity/mcp/memory/run.cmd")
	if err != nil || changed {
		t.Fatalf("second retarget changed=%v err=%v", changed, err)
	}
}

func TestEnsureJSONUsesExactMCPServersMemoryPath(t *testing.T) {
	path := filepath.Join(t.TempDir(), "mcp.json")
	original := `{"nested":{"memory":{"command":".agent-parity/mcp/memory/run.cmd"}},"keep":true}`
	if err := os.WriteFile(path, []byte(original), 0o644); err != nil {
		t.Fatal(err)
	}
	changed, err := ensureMemoryConfig(path, ".agent-parity/mcp/memory/run.sh")
	if err != nil || !changed {
		t.Fatalf("changed=%v err=%v", changed, err)
	}
	root := readSettings(t, path)
	nested := root["nested"].(map[string]any)["memory"].(map[string]any)
	if nested["command"] != ".agent-parity/mcp/memory/run.cmd" {
		t.Fatal("unrelated nested memory object was modified")
	}
	servers := root["mcpServers"].(map[string]any)
	if servers["memory"].(map[string]any)["command"] != ".agent-parity/mcp/memory/run.sh" {
		t.Fatal("mcpServers.memory was not added")
	}
}

func TestRetargetPreservesAndReportsUserMemoryCommand(t *testing.T) {
	for _, original := range []string{
		`{"mcpServers":{"memory":{"command":"my-memory-server"}}}`,
		"[mcp_servers.memory]\ncommand = \"my-memory-server\"\n",
	} {
		path := filepath.Join(t.TempDir(), "config"+map[bool]string{true: ".json", false: ".toml"}[strings.HasPrefix(original, "{")])
		if err := os.WriteFile(path, []byte(original), 0o644); err != nil {
			t.Fatal(err)
		}
		if changed, err := retargetMemoryConfig(path, ".agent-parity/mcp/memory/run.cmd"); err == nil || changed || !strings.Contains(err.Error(), "edit it manually") {
			t.Fatalf("user command was not preserved with a manual-edit warning: changed=%v err=%v", changed, err)
		}
		got, _ := os.ReadFile(path)
		if string(got) != original {
			t.Fatal("rejected config was modified")
		}
	}
}

func TestMergeAndUnmergeAgentHooksPreservesUserHandlers(t *testing.T) {
	tests := []struct {
		kind, original string
	}{
		{"claude", `{"model":"keep","hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"echo user"}]}]}}`},
		{"codex", `{"description":"keep","hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"echo user"}]}]}}`},
		{"cursor", `{"version":1,"other":"keep","hooks":{"sessionStart":[{"command":"echo user"}]}}`},
		{"antigravity", `{"user-hook":{"enabled":true,"other":"keep","PreInvocation":[{"command":"echo user"}]}}`},
	}
	for _, tc := range tests {
		t.Run(tc.kind, func(t *testing.T) {
			path := filepath.Join(t.TempDir(), "hooks.json")
			if err := os.WriteFile(path, []byte(tc.original), 0o644); err != nil {
				t.Fatal(err)
			}
			if err := mergeAgentHook(path, tc.kind, "", ""); err != nil {
				t.Fatal(err)
			}
			first, _ := os.ReadFile(path)
			if !strings.Contains(string(first), "echo user") || !strings.Contains(string(first), "self-heal") {
				t.Fatalf("hook merge lost content:\n%s", first)
			}
			if err := mergeAgentHook(path, tc.kind, "", ""); err != nil {
				t.Fatal(err)
			}
			second, _ := os.ReadFile(path)
			if string(first) != string(second) {
				t.Fatalf("hook merge is not idempotent:\n%s\n%s", first, second)
			}
			if err := unmergeAgentHook(path, tc.kind); err != nil {
				t.Fatal(err)
			}
			last, _ := os.ReadFile(path)
			if !strings.Contains(string(last), "echo user") || strings.Contains(string(last), "self-heal") {
				t.Fatalf("hook unmerge removed user content or kept ours:\n%s", last)
			}
		})
	}
}

func TestMergeAgentHookRejectsWrongTypesWithoutRewriting(t *testing.T) {
	tests := []struct {
		name     string
		kind     string
		original string
	}{
		{"claude-hooks", "claude", `{"hooks":"custom"}`},
		{"codex-event", "codex", `{"hooks":{"SessionStart":"custom"}}`},
		{"cursor-container", "cursor", `{"hooks":"custom"}`},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			path := filepath.Join(t.TempDir(), "hooks.json")
			if err := os.WriteFile(path, []byte(tt.original), 0o644); err != nil {
				t.Fatal(err)
			}
			if err := mergeAgentHook(path, tt.kind, "", ""); err == nil {
				t.Fatal("expected malformed or conflicting hook settings to be rejected")
			}
			got, _ := os.ReadFile(path)
			if string(got) != tt.original {
				t.Fatalf("hook settings were rewritten: %s", got)
			}
		})
	}
}

func TestMergeAgentHookPreservesOpaqueSharedMembersAndOverwritesDedicatedNamespace(t *testing.T) {
	for _, tc := range []struct{ kind, original string }{
		{"claude", `{"hooks":{"SessionStart":[42,{"hooks":[42,{"command":"echo user"}]}]}}`},
		{"cursor", `{"hooks":{"sessionStart":[42,{"command":"echo user"}]}}`},
		{"antigravity", `{"agent-parity":{"enabled":false,"PreInvocation":[42],"custom":true},"user":"keep"}`},
	} {
		t.Run(tc.kind, func(t *testing.T) {
			path := filepath.Join(t.TempDir(), "hooks.json")
			if err := os.WriteFile(path, []byte(tc.original), 0o644); err != nil {
				t.Fatal(err)
			}
			if err := mergeAgentHook(path, tc.kind, "", ""); err != nil {
				t.Fatal(err)
			}
			raw := mustRead(t, path)
			if tc.kind != "antigravity" && (!bytes.Contains(raw, []byte(`42`)) || !bytes.Contains(raw, []byte("echo user"))) {
				t.Fatalf("opaque shared hook members were lost: %s", raw)
			}
			if tc.kind == "antigravity" {
				root := readSettings(t, path)
				managed := root["agent-parity"].(map[string]any)
				if managed["enabled"] != true || managed["custom"] != nil || root["user"] != "keep" {
					t.Fatalf("dedicated namespace did not converge: %#v", root)
				}
			}
		})
	}
}

func TestUnmergeNestedHookPreservesOpaqueGroups(t *testing.T) {
	path := filepath.Join(t.TempDir(), "hooks.json")
	original := `{"hooks":{"SessionStart":[42,{"hooks":[42,{"type":"command","command":".agent-parity/bin/agent-parity self-heal"},{"command":"echo user"}]}]}}`
	if err := os.WriteFile(path, []byte(original), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := unmergeAgentHook(path, "claude"); err != nil {
		t.Fatal(err)
	}
	raw := mustRead(t, path)
	if !bytes.Contains(raw, []byte(`42`)) || !bytes.Contains(raw, []byte("echo user")) || bytes.Contains(raw, []byte("agent-parity self-heal")) {
		t.Fatalf("unmerge did not preserve opaque/user hook members: %s", raw)
	}
}

func TestUnmergePreservesWrongTypedSharedContainers(t *testing.T) {
	t.Run("agent-hook", func(t *testing.T) {
		path := filepath.Join(t.TempDir(), "hooks.json")
		original := `{"hooks":{"SessionStart":"user-value"},"keep":true}`
		if err := os.WriteFile(path, []byte(original), 0o644); err != nil {
			t.Fatal(err)
		}
		if err := unmergeAgentHook(path, "claude"); err != nil {
			t.Fatal(err)
		}
		if got := string(mustRead(t, path)); got != original {
			t.Fatalf("wrong-typed shared hook was rewritten: %s", got)
		}
	})

	t.Run("claude-settings", func(t *testing.T) {
		path := filepath.Join(t.TempDir(), "settings.json")
		original := `{"autoMemoryEnabled":false,"enabledMcpjsonServers":"user-value","permissions":{"allow":{"custom":true}},"hooks":{"SessionStart":"user-value"}}`
		if err := os.WriteFile(path, []byte(original), 0o644); err != nil {
			t.Fatal(err)
		}
		if err := unmergeClaudeSettings(path); err != nil {
			t.Fatal(err)
		}
		root := readSettings(t, path)
		if root["enabledMcpjsonServers"] != "user-value" || root["hooks"].(map[string]any)["SessionStart"] != "user-value" {
			t.Fatalf("wrong-typed shared Claude fields were removed: %#v", root)
		}
		allow := root["permissions"].(map[string]any)["allow"].(map[string]any)
		if allow["custom"] != true {
			t.Fatalf("wrong-typed permission field was removed: %#v", root)
		}
		if _, exists := root["autoMemoryEnabled"]; exists {
			t.Fatalf("owned scalar survived uninstall: %#v", root)
		}
	})
}

func TestPortableHooksMigrateExactV060Commands(t *testing.T) {
	tests := []struct {
		kind, original, want string
	}{
		{"cursor", `{"version":1,"hooks":{"sessionStart":[{"command":".agents/bin/agent-parity.cmd self-heal","timeout":30}]}}`, ".agent-parity/bin/agent-parity self-heal cursor"},
		{"antigravity", `{"enabled":true,"PreInvocation":[{"command":".agents/bin/agent-parity.cmd self-heal","timeout":30}]}`, ".agent-parity/bin/agent-parity self-heal antigravity"},
	}
	for _, tc := range tests {
		t.Run(tc.kind, func(t *testing.T) {
			path := filepath.Join(t.TempDir(), "hooks.json")
			if err := os.WriteFile(path, []byte(tc.original), 0o644); err != nil {
				t.Fatal(err)
			}
			if err := mergeAgentHook(path, tc.kind, "", ""); err != nil {
				t.Fatal(err)
			}
			raw, _ := os.ReadFile(path)
			if strings.Contains(string(raw), `"command": ".agents/bin/agent-parity.cmd self-heal"`) {
				t.Fatalf("v0.6.0 Windows-only hook was not migrated:\n%s", raw)
			}
			if !strings.Contains(string(raw), `"command": "`+tc.want+`"`) {
				t.Fatalf("platform-neutral hook missing:\n%s", raw)
			}
			if tc.kind == "antigravity" {
				root := readSettings(t, path)
				if _, legacy := root["PreInvocation"]; legacy {
					t.Fatalf("legacy root event remains: %#v", root)
				}
				managed, ok := root["agent-parity"].(map[string]any)
				if !ok || managed["enabled"] != true || managed["PreInvocation"] == nil {
					t.Fatalf("official Antigravity hook block missing: %#v", root)
				}
			}
		})
	}
}

func TestUnmergeFreshAgentHookRemovesScaffoldingFile(t *testing.T) {
	for _, kind := range []string{"claude", "codex", "cursor", "antigravity"} {
		t.Run(kind, func(t *testing.T) {
			path := filepath.Join(t.TempDir(), "hooks.json")
			if err := mergeAgentHook(path, kind, "", ""); err != nil {
				t.Fatal(err)
			}
			if err := unmergeAgentHook(path, kind); err != nil {
				t.Fatal(err)
			}
			if _, err := os.Stat(path); !os.IsNotExist(err) {
				t.Fatalf("managed-only hook file should be removed, err=%v", err)
			}
		})
	}
}

func TestClaudeSyncAndSelfHealHooksHaveIndependentLifecycles(t *testing.T) {
	path := filepath.Join(t.TempDir(), "settings.json")
	if err := mergeClaudeSettings(path, ".agent-parity/bin/agent-parity sync-claude"); err != nil {
		t.Fatal(err)
	}
	if err := mergeAgentHook(path, "claude", "", ""); err != nil {
		t.Fatal(err)
	}
	merged, _ := os.ReadFile(path)
	if !strings.Contains(string(merged), "sync-claude") || !strings.Contains(string(merged), "agent-parity self-heal") {
		t.Fatalf("expected independent Claude hooks:\n%s", merged)
	}
	if err := unmergeAgentHook(path, "claude"); err != nil {
		t.Fatal(err)
	}
	withoutSelfHeal, _ := os.ReadFile(path)
	if !strings.Contains(string(withoutSelfHeal), "sync-claude") || strings.Contains(string(withoutSelfHeal), "agent-parity self-heal") {
		t.Fatalf("removing self-heal affected sync hook:\n%s", withoutSelfHeal)
	}
}

func TestStatusHookChecksUseExactJSONPaths(t *testing.T) {
	path := filepath.Join(t.TempDir(), "hooks.json")
	decoys := map[string]string{
		"claude":      `{"note":".agent-parity/bin/agent-parity self-heal","hooks":{"OtherEvent":[{"hooks":[{"type":"command","command":".agent-parity/bin/agent-parity self-heal"}]}]}}`,
		"codex":       `{"note":"agent-parity self-heal","hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"echo agent-parity self-heal"}]}]}}`,
		"cursor":      `{"note":".agents/bin/agent-parity.cmd self-heal","hooks":{"other":[{"command":".agents/bin/agent-parity.cmd self-heal"}]}}`,
		"antigravity": `{"note":".agent-parity/bin/agent-parity self-heal","other-hook":{"PreInvocation":[{"command":".agent-parity/bin/agent-parity self-heal"}]}}`,
	}
	for kind, raw := range decoys {
		t.Run(kind, func(t *testing.T) {
			if err := os.WriteFile(path, []byte(raw), 0o644); err != nil {
				t.Fatal(err)
			}
			has, err := hasAgentHook(path, kind)
			if err != nil || has {
				t.Fatalf("decoy was reported as registered: has=%v err=%v", has, err)
			}
			if err := mergeAgentHook(path, kind, "", ""); err != nil {
				t.Fatal(err)
			}
			has, err = hasAgentHook(path, kind)
			if err != nil || !has {
				t.Fatalf("installed hook was not found: has=%v err=%v", has, err)
			}
		})
	}
}

func TestStatusClaudeSyncCheckUsesExactJSONPathAndCommand(t *testing.T) {
	path := filepath.Join(t.TempDir(), "settings.json")
	command := ".agent-parity/bin/agent-parity sync-claude"
	if err := os.WriteFile(path, []byte(`{"note":".agent-parity/bin/agent-parity sync-claude","hooks":{"OtherEvent":[{"hooks":[{"type":"command","command":".agent-parity/bin/agent-parity sync-claude"}]}]}}`), 0o644); err != nil {
		t.Fatal(err)
	}
	has, err := hasClaudeSyncHook(path, command)
	if err != nil || has {
		t.Fatalf("decoy was reported as registered: has=%v err=%v", has, err)
	}
	if err := mergeClaudeSettings(path, command); err != nil {
		t.Fatal(err)
	}
	has, err = hasClaudeSyncHook(path, command)
	if err != nil || !has {
		t.Fatalf("installed sync hook was not found: has=%v err=%v", has, err)
	}
}

func TestStatusCursorCLIAllowlistUsesExactJSONPath(t *testing.T) {
	path := filepath.Join(t.TempDir(), "cli.json")
	if err := os.WriteFile(path, []byte(`{"note":"Mcp(memory:*)","permissions":{"deny":["Mcp(memory:*)"]}}`), 0o644); err != nil {
		t.Fatal(err)
	}
	has, err := hasCursorCLIAllowlist(path)
	if err != nil || has {
		t.Fatalf("decoy was reported as allowed: has=%v err=%v", has, err)
	}
	if err := os.WriteFile(path, []byte(`{"permissions":{"allow":["Mcp(memory:*)"]}}`), 0o644); err != nil {
		t.Fatal(err)
	}
	has, err = hasCursorCLIAllowlist(path)
	if err != nil || !has {
		t.Fatalf("allowlist entry was not found: has=%v err=%v", has, err)
	}
}

func TestStatusMemoryConfigUsesCanonicalOwnedNamespace(t *testing.T) {
	for _, tc := range []struct {
		name, file, initial, command string
	}{
		{"json", "mcp.json", `{"mcpServers":{"memory":{"command":".agent-parity/mcp/memory/run.cmd","args":["stale"]}}}`, ".agent-parity/mcp/memory/run.cmd"},
		{"toml", "config.toml", "[mcp_servers.memory]\ncommand = \".agent-parity/mcp/memory/run.cmd\"\ndefault_tools_approval_mode = \"prompt\"\n", ".agent-parity/mcp/memory/run.cmd"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			path := filepath.Join(t.TempDir(), tc.file)
			if err := os.WriteFile(path, []byte(tc.initial), 0o644); err != nil {
				t.Fatal(err)
			}
			if ok, err := hasCanonicalMemoryConfig(path, tc.command); err != nil || ok {
				t.Fatalf("stale namespace reported healthy: ok=%v err=%v", ok, err)
			}
			if changed, err := ensureMemoryConfig(path, tc.command); err != nil || !changed {
				t.Fatalf("changed=%v err=%v", changed, err)
			}
			if ok, err := hasCanonicalMemoryConfig(path, tc.command); err != nil || !ok {
				t.Fatalf("converged namespace not reported healthy: ok=%v err=%v", ok, err)
			}
		})
	}
}

func TestStatusClaudeSettingsUsesFullManagedState(t *testing.T) {
	path := filepath.Join(t.TempDir(), "settings.json")
	command := ".agent-parity/bin/agent-parity sync-claude"
	if err := mergeClaudeSettings(path, command); err != nil {
		t.Fatal(err)
	}
	if ok, err := hasClaudeSettings(path, command); err != nil || !ok {
		t.Fatalf("converged Claude settings not reported healthy: ok=%v err=%v", ok, err)
	}
	root := readSettings(t, path)
	root["autoMemoryEnabled"] = true
	raw, _ := json.Marshal(root)
	if err := os.WriteFile(path, raw, 0o644); err != nil {
		t.Fatal(err)
	}
	if ok, err := hasClaudeSettings(path, command); err != nil || ok {
		t.Fatalf("stale Claude settings reported healthy: ok=%v err=%v", ok, err)
	}
}

func TestStatusAgentHookRejectsStaleOwnedHandlerButIgnoresOpaqueMembers(t *testing.T) {
	path := filepath.Join(t.TempDir(), "hooks.json")
	if err := os.WriteFile(path, []byte(`{"hooks":{"sessionStart":[42]}}`), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := mergeAgentHook(path, "cursor", "", ""); err != nil {
		t.Fatal(err)
	}
	if ok, err := hasAgentHook(path, "cursor"); err != nil || !ok {
		t.Fatalf("canonical hook with opaque neighbor not reported healthy: ok=%v err=%v", ok, err)
	}
	root := readSettings(t, path)
	hooks := root["hooks"].(map[string]any)
	handlers := hooks["sessionStart"].([]any)
	handlers[1].(map[string]any)["custom"] = true
	raw, _ := json.Marshal(root)
	if err := os.WriteFile(path, raw, 0o644); err != nil {
		t.Fatal(err)
	}
	if ok, err := hasAgentHook(path, "cursor"); err != nil || ok {
		t.Fatalf("stale owned hook reported healthy: ok=%v err=%v", ok, err)
	}
}

func TestMergeAgentHookPreservesDisabledUserSetting(t *testing.T) {
	path := filepath.Join(t.TempDir(), "hooks.json")
	if err := os.WriteFile(path, []byte(`{"enabled":false,"other":"keep"}`), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := mergeAgentHook(path, "antigravity", "", ""); err != nil {
		t.Fatal(err)
	}
	m := readSettings(t, path)
	if m["enabled"] != false || m["other"] != "keep" {
		t.Fatalf("user hook settings changed: %#v", m)
	}
}

func TestRetargetTOMLPreservesCommentsAndOtherTables(t *testing.T) {
	original := "# keep\n[mcp_servers.memory]\ncommand = \".agent-parity/mcp/memory/run.cmd\" # launcher\n\n[mcp_servers.other]\ncommand = \"other\"\n"
	path := filepath.Join(t.TempDir(), "config.toml")
	if err := os.WriteFile(path, []byte(original), 0o644); err != nil {
		t.Fatal(err)
	}
	changed, err := retargetMemoryConfig(path, ".agent-parity/mcp/memory/run.sh")
	if err != nil || !changed {
		t.Fatalf("changed=%v err=%v", changed, err)
	}
	got, _ := os.ReadFile(path)
	if !strings.Contains(string(got), "# keep") || !strings.Contains(string(got), "[mcp_servers.other]") || !strings.Contains(string(got), `default_tools_approval_mode = "approve"`) || strings.Contains(string(got), "# launcher") {
		t.Fatalf("managed TOML namespace did not converge while preserving unrelated content:\n%s", got)
	}
}

func TestRetargetTOMLEquivalentSpellings(t *testing.T) {
	tests := []string{
		`mcp_servers.memory.command = ".agent-parity/mcp/memory/run.cmd"` + "\n",
		"[mcp_servers]\nmemory = { command = \".agent-parity/mcp/memory/run.cmd\", args = [\"--keep\"] }\n",
		"mcp_servers = { memory = { command = \".agent-parity/mcp/memory/run.cmd\", args = [\"--keep\"] }, other = { command = \"other\" } }\n",
		"[mcp_servers.\"memory\"]\ncommand = '.agent-parity/mcp/memory/run.cmd' # launcher\n",
	}
	for _, original := range tests {
		t.Run(original, func(t *testing.T) {
			path := filepath.Join(t.TempDir(), "config.toml")
			if err := os.WriteFile(path, []byte(original), 0o644); err != nil {
				t.Fatal(err)
			}
			changed, err := retargetMemoryConfig(path, ".agent-parity/mcp/memory/run.sh")
			if err != nil || !changed {
				t.Fatalf("changed=%v err=%v", changed, err)
			}
			got, err := os.ReadFile(path)
			if err != nil {
				t.Fatal(err)
			}
			if !strings.Contains(string(got), ".agent-parity/mcp/memory/run.sh") || strings.Contains(string(got), ".agent-parity/mcp/memory/run.cmd") {
				t.Fatalf("command was not retargeted: %s", got)
			}
			if strings.Contains(string(got), "--keep") {
				t.Fatal("owned inline-table descendant survived convergence")
			}
			if strings.Contains(original, "other") && !strings.Contains(string(got), "other") {
				t.Fatal("unrelated inline-table entry was lost")
			}
		})
	}
}

func TestUnmergeTOMLEquivalentSpellings(t *testing.T) {
	tests := []string{
		"# keep\nmcp_servers.memory.command = \".agent-parity/mcp/memory/run.sh\"\nother = \"keep\"\n",
		"# keep\n[mcp_servers]\nmemory = { command = \".agent-parity/mcp/memory/run.sh\", args = [\"--keep\"] }\nother = { command = \"other\" }\n",
		"# keep\nmcp_servers = { memory = { command = \".agent-parity/mcp/memory/run.sh\" }, other = { command = \"other\" } }\n",
		"# keep\n[mcp_servers.\"memory\"]\ncommand = '.agent-parity/mcp/memory/run.sh'\n[mcp_servers.other]\ncommand = \"other\"\n",
	}
	for _, original := range tests {
		t.Run(original, func(t *testing.T) {
			path := filepath.Join(t.TempDir(), "config.toml")
			if err := os.WriteFile(path, []byte(original), 0o644); err != nil {
				t.Fatal(err)
			}
			if err := unmergeServerConfig(path); err != nil {
				t.Fatal(err)
			}
			got, err := os.ReadFile(path)
			if err != nil {
				t.Fatal(err)
			}
			var root struct {
				MCPServers map[string]any `toml:"mcp_servers"`
			}
			if err := toml.Unmarshal(got, &root); err != nil {
				t.Fatalf("invalid TOML after removal: %v\n%s", err, got)
			}
			if _, exists := root.MCPServers["memory"]; exists {
				t.Fatalf("memory entry remains: %s", got)
			}
			if !strings.Contains(string(got), "# keep") {
				t.Fatal("unrelated comment was lost")
			}
		})
	}
}

func TestRetargetAcceptsLegacyVendoredBinary(t *testing.T) {
	path := filepath.Join(t.TempDir(), "mcp.json")
	original := `{"mcpServers":{"memory":{"command":".agents/mcp/memory/dist/memory-mcp-windows-amd64.exe"}}}`
	if err := os.WriteFile(path, []byte(original), 0o644); err != nil {
		t.Fatal(err)
	}
	changed, err := retargetMemoryConfig(path, ".agent-parity/mcp/memory/run.sh")
	if err != nil || !changed {
		t.Fatalf("changed=%v err=%v", changed, err)
	}
}
