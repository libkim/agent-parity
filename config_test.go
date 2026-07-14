package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

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
