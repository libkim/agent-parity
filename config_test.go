//go:build configeditor

package main

import (
	"bytes"
	"encoding/json"
	"os"
	"path/filepath"
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
	if err := mergeClaudeSettings(path, ".agents/bin/agent-parity sync-claude"); err != nil {
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
	if !strings.Contains(mustJSON(t, m), ".agents/bin/agent-parity sync-claude") {
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
	    {"hooks": [{"type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR/.agents/scripts/sync-claude.sh\" sync"}]}
	  ]}
	}`
	if err := os.WriteFile(path, []byte(original), 0o644); err != nil {
		t.Fatal(err)
	}
	newHook := ".agents/bin/agent-parity sync-claude"
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

func TestUnmergeClaudeSettingsRoundTrip(t *testing.T) {
	// Only our keys: the file is deleted outright.
	path := filepath.Join(t.TempDir(), "settings.json")
	if err := mergeClaudeSettings(path, ".agents/bin/agent-parity sync-claude"); err != nil {
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
	if err := mergeClaudeSettings(path2, ".agents/bin/agent-parity sync-claude"); err != nil {
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

func TestRetargetJSONChangesOnlyManagedMemoryCommand(t *testing.T) {
	path := filepath.Join(t.TempDir(), "mcp.json")
	original := `{"other":"keep","mcpServers":{"other":{"command":"other"},"memory":{"command":".agents/mcp/memory/run.sh","args":["--keep"]}}}`
	if err := os.WriteFile(path, []byte(original), 0o644); err != nil {
		t.Fatal(err)
	}
	changed, err := retargetMemoryConfig(path, ".agents/mcp/memory/run.cmd")
	if err != nil || !changed {
		t.Fatalf("changed=%v err=%v", changed, err)
	}
	m := readSettings(t, path)
	servers := m["mcpServers"].(map[string]any)
	memory := servers["memory"].(map[string]any)
	if memory["command"] != ".agents/mcp/memory/run.cmd" || !hasStr(memory["args"], "--keep") {
		t.Fatalf("memory entry not safely retargeted: %#v", memory)
	}
	if servers["other"].(map[string]any)["command"] != "other" || m["other"] != "keep" {
		t.Fatal("unrelated JSON content changed")
	}
	changed, err = retargetMemoryConfig(path, ".agents/mcp/memory/run.cmd")
	if err != nil || changed {
		t.Fatalf("second retarget changed=%v err=%v", changed, err)
	}
}

func TestEnsureJSONUsesExactMCPServersMemoryPath(t *testing.T) {
	path := filepath.Join(t.TempDir(), "mcp.json")
	original := `{"nested":{"memory":{"command":".agents/mcp/memory/run.cmd"}},"keep":true}`
	if err := os.WriteFile(path, []byte(original), 0o644); err != nil {
		t.Fatal(err)
	}
	changed, err := ensureMemoryConfig(path, ".agents/mcp/memory/run.sh")
	if err != nil || !changed {
		t.Fatalf("changed=%v err=%v", changed, err)
	}
	root := readSettings(t, path)
	nested := root["nested"].(map[string]any)["memory"].(map[string]any)
	if nested["command"] != ".agents/mcp/memory/run.cmd" {
		t.Fatal("unrelated nested memory object was modified")
	}
	servers := root["mcpServers"].(map[string]any)
	if servers["memory"].(map[string]any)["command"] != ".agents/mcp/memory/run.sh" {
		t.Fatal("mcpServers.memory was not added")
	}
}

func TestRetargetSkipsUserMemoryCommand(t *testing.T) {
	for _, original := range []string{
		`{"mcpServers":{"memory":{"command":"my-memory-server"}}}`,
		"[mcp_servers.memory]\ncommand = \"my-memory-server\"\n",
	} {
		path := filepath.Join(t.TempDir(), "config"+map[bool]string{true: ".json", false: ".toml"}[strings.HasPrefix(original, "{")])
		if err := os.WriteFile(path, []byte(original), 0o644); err != nil {
			t.Fatal(err)
		}
		if changed, err := retargetMemoryConfig(path, ".agents/mcp/memory/run.cmd"); err != nil || changed {
			t.Fatalf("user command was not skipped: changed=%v err=%v", changed, err)
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

func TestPortableHooksMigrateExactV060Commands(t *testing.T) {
	tests := []struct {
		kind, original string
	}{
		{"cursor", `{"version":1,"hooks":{"sessionStart":[{"command":".agents/bin/agent-parity.cmd self-heal","timeout":30}]}}`},
		{"antigravity", `{"enabled":true,"PreInvocation":[{"command":".agents/bin/agent-parity.cmd self-heal","timeout":30}]}`},
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
			if !strings.Contains(string(raw), `"command": ".agents/bin/agent-parity self-heal"`) {
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
	if err := mergeClaudeSettings(path, ".agents/bin/agent-parity sync-claude"); err != nil {
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
		"claude":      `{"note":".agents/bin/agent-parity self-heal","hooks":{"OtherEvent":[{"hooks":[{"type":"command","command":".agents/bin/agent-parity self-heal"}]}]}}`,
		"codex":       `{"note":"agent-parity self-heal","hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"echo agent-parity self-heal"}]}]}}`,
		"cursor":      `{"note":".agents/bin/agent-parity.cmd self-heal","hooks":{"other":[{"command":".agents/bin/agent-parity.cmd self-heal"}]}}`,
		"antigravity": `{"note":".agents/bin/agent-parity self-heal","other-hook":{"PreInvocation":[{"command":".agents/bin/agent-parity self-heal"}]}}`,
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
	command := ".agents/bin/agent-parity sync-claude"
	if err := os.WriteFile(path, []byte(`{"note":".agents/bin/agent-parity sync-claude","hooks":{"OtherEvent":[{"hooks":[{"type":"command","command":".agents/bin/agent-parity sync-claude"}]}]}}`), 0o644); err != nil {
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
	original := "# keep\n[mcp_servers.memory]\ncommand = \".agents/mcp/memory/run.cmd\" # launcher\n\n[mcp_servers.other]\ncommand = \"other\"\n"
	path := filepath.Join(t.TempDir(), "config.toml")
	if err := os.WriteFile(path, []byte(original), 0o644); err != nil {
		t.Fatal(err)
	}
	changed, err := retargetMemoryConfig(path, ".agents/mcp/memory/run.sh")
	if err != nil || !changed {
		t.Fatalf("changed=%v err=%v", changed, err)
	}
	got, _ := os.ReadFile(path)
	want := strings.Replace(original, ".agents/mcp/memory/run.cmd", ".agents/mcp/memory/run.sh", 1)
	if string(got) != want {
		t.Fatalf("unexpected TOML rewrite:\nwant:\n%s\ngot:\n%s", want, got)
	}
}

func TestRetargetTOMLEquivalentSpellings(t *testing.T) {
	tests := []string{
		`mcp_servers.memory.command = ".agents/mcp/memory/run.cmd"` + "\n",
		"[mcp_servers]\nmemory = { command = \".agents/mcp/memory/run.cmd\", args = [\"--keep\"] }\n",
		"mcp_servers = { memory = { command = \".agents/mcp/memory/run.cmd\", args = [\"--keep\"] }, other = { command = \"other\" } }\n",
		"[mcp_servers.\"memory\"]\ncommand = '.agents/mcp/memory/run.cmd' # launcher\n",
	}
	for _, original := range tests {
		t.Run(original, func(t *testing.T) {
			path := filepath.Join(t.TempDir(), "config.toml")
			if err := os.WriteFile(path, []byte(original), 0o644); err != nil {
				t.Fatal(err)
			}
			changed, err := retargetMemoryConfig(path, ".agents/mcp/memory/run.sh")
			if err != nil || !changed {
				t.Fatalf("changed=%v err=%v", changed, err)
			}
			got, err := os.ReadFile(path)
			if err != nil {
				t.Fatal(err)
			}
			if !strings.Contains(string(got), ".agents/mcp/memory/run.sh") || strings.Contains(string(got), ".agents/mcp/memory/run.cmd") {
				t.Fatalf("command was not retargeted: %s", got)
			}
			if strings.Contains(original, "--keep") && !strings.Contains(string(got), "--keep") {
				t.Fatal("unrelated inline-table value was lost")
			}
			if strings.Contains(original, "other") && !strings.Contains(string(got), "other") {
				t.Fatal("unrelated inline-table entry was lost")
			}
		})
	}
}

func TestUnmergeTOMLEquivalentSpellings(t *testing.T) {
	tests := []string{
		"# keep\nmcp_servers.memory.command = \".agents/mcp/memory/run.sh\"\nother = \"keep\"\n",
		"# keep\n[mcp_servers]\nmemory = { command = \".agents/mcp/memory/run.sh\", args = [\"--keep\"] }\nother = { command = \"other\" }\n",
		"# keep\nmcp_servers = { memory = { command = \".agents/mcp/memory/run.sh\" }, other = { command = \"other\" } }\n",
		"# keep\n[mcp_servers.\"memory\"]\ncommand = '.agents/mcp/memory/run.sh'\n[mcp_servers.other]\ncommand = \"other\"\n",
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
	changed, err := retargetMemoryConfig(path, ".agents/mcp/memory/run.sh")
	if err != nil || !changed {
		t.Fatalf("changed=%v err=%v", changed, err)
	}
}
