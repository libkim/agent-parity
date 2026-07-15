package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
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

func TestMergeClaudeSettingsFresh(t *testing.T) {
	path := filepath.Join(t.TempDir(), "settings.json")
	if err := mergeClaudeSettings(path, "bash x/sync-claude.sh sync"); err != nil {
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
	if !strings.Contains(mustJSON(t, m), "sync-claude.sh") {
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
	    {"hooks": [{"type": "command", "command": "bash /old/sync-claude.sh sync"}]}
	  ]}
	}`
	if err := os.WriteFile(path, []byte(original), 0o644); err != nil {
		t.Fatal(err)
	}
	newHook := "bash /new/.agents/scripts/sync-claude.sh sync"
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
	if strings.Contains(blob, "/old/sync-claude.sh") {
		t.Error("old hook path not refreshed")
	}
	if !strings.Contains(blob, newHook) {
		t.Error("new hook not present")
	}
	if !strings.Contains(blob, "echo user-hook") {
		t.Error("user hook lost")
	}
	if n := strings.Count(blob, "sync-claude.sh"); n != 1 {
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

func TestUnmergeClaudeSettingsRoundTrip(t *testing.T) {
	// Only our keys: the file is deleted outright.
	path := filepath.Join(t.TempDir(), "settings.json")
	if err := mergeClaudeSettings(path, "bash x/sync-claude.sh sync"); err != nil {
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
	if err := mergeClaudeSettings(path2, "bash x/sync-claude.sh sync"); err != nil {
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
			if err := mergeServerConfig(path, ".agents/mcp/memory/run.sh"); err != nil {
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
	if err := mergeServerConfig(path, ".agents/mcp/memory/run.sh"); err != nil {
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

func TestMergeTOMLAppendsApprovalTools(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.toml")
	if err := os.WriteFile(path, []byte(""), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := mergeServerConfig(path, ".agents/mcp/memory/run.sh"); err != nil {
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
	for _, tool := range []string{"memory_add", "memory_recent", "memory_search", "memory_get"} {
		header := "[mcp_servers.memory.tools." + tool + "]"
		if strings.Count(text, header) != 1 {
			t.Fatalf("missing or duplicated approval table %s:\n%s", header, text)
		}
	}
	if strings.Count(text, `approval_mode = "approve"`) != 4 {
		t.Fatalf("expected 4 approval_mode lines, got:\n%s", text)
	}
}

func TestUnmergeTOMLRemovesServerAndApprovalTools(t *testing.T) {
	original := "# keep this comment\n[mcp_servers.other]\ncommand = \"other\"\n"
	path := filepath.Join(t.TempDir(), "config.toml")
	if err := os.WriteFile(path, []byte(original), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := mergeServerConfig(path, ".agents/mcp/memory/run.sh"); err != nil {
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
	if err := mergeServerConfig(path, ".agents/mcp/memory/run.sh"); err != nil {
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
	if err := mergeServerConfig(path, ".agents/mcp/memory/run.sh"); err == nil {
		t.Fatal("expected invalid TOML to be rejected")
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
