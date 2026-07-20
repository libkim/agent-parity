//go:build configeditor

package main

import (
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
)

func writeMergeFixture(t *testing.T, dir, name, content string) string {
	t.Helper()
	p := filepath.Join(dir, name)
	if err := os.WriteFile(p, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
	return p
}

func memoryFixture(strength int, lastAccessed, body string, tags ...string) string {
	var b strings.Builder
	b.WriteString("---\ncreated: 2026-07-01T00:00:00Z\n")
	if len(tags) > 0 {
		b.WriteString("tags:\n")
		for _, tag := range tags {
			b.WriteString("    - " + tag + "\n")
		}
	}
	b.WriteString("strength: " + strconv.Itoa(strength) + "\n")
	b.WriteString("lastAccessed: " + lastAccessed + "\n---\n" + body + "\n")
	return b.String()
}

func TestMergeMemoryTakesMaxStrength(t *testing.T) {
	dir := t.TempDir()
	base := writeMergeFixture(t, dir, "base.md", memoryFixture(3, "2026-07-02T00:00:00Z", "shared body", "a"))
	ours := writeMergeFixture(t, dir, "ours.md", memoryFixture(5, "2026-07-03T00:00:00Z", "shared body", "a"))
	theirs := writeMergeFixture(t, dir, "theirs.md", memoryFixture(4, "2026-07-04T00:00:00Z", "shared body", "a", "b"))

	if err := mergeMemoryFiles(base, ours, theirs); err != nil {
		t.Fatal(err)
	}
	raw, err := os.ReadFile(ours)
	if err != nil {
		t.Fatal(err)
	}
	e, err := parseEntry("merged", raw)
	if err != nil {
		t.Fatal(err)
	}
	// base 3, ours 5, theirs 4 -> the higher side wins.
	if e.Strength != 5 {
		t.Fatalf("strength = %d, want 5", e.Strength)
	}
	if got := e.LastAccessed.UTC().Format("2006-01-02"); got != "2026-07-04" {
		t.Fatalf("lastAccessed date = %s, want 2026-07-04", got)
	}
	if strings.Join(e.Tags, ",") != "a,b" {
		t.Fatalf("tags = %v, want [a b]", e.Tags)
	}
	if e.Body != "shared body" {
		t.Fatalf("body = %q", e.Body)
	}
}

func TestMergeMemoryTakesSingleSidedBodyEdit(t *testing.T) {
	dir := t.TempDir()
	base := writeMergeFixture(t, dir, "base.md", memoryFixture(1, "2026-07-02T00:00:00Z", "old body"))
	ours := writeMergeFixture(t, dir, "ours.md", memoryFixture(2, "2026-07-03T00:00:00Z", "old body"))
	theirs := writeMergeFixture(t, dir, "theirs.md", memoryFixture(1, "2026-07-02T00:00:00Z", "corrected body"))

	if err := mergeMemoryFiles(base, ours, theirs); err != nil {
		t.Fatal(err)
	}
	raw, _ := os.ReadFile(ours)
	e, err := parseEntry("merged", raw)
	if err != nil {
		t.Fatal(err)
	}
	if e.Body != "corrected body" {
		t.Fatalf("body = %q, want the edited side", e.Body)
	}
	if e.Strength != 2 {
		t.Fatalf("strength = %d, want 2", e.Strength)
	}
}

func TestMergeMemoryConflictingBodiesFail(t *testing.T) {
	dir := t.TempDir()
	base := writeMergeFixture(t, dir, "base.md", memoryFixture(1, "2026-07-02T00:00:00Z", "old body"))
	ours := writeMergeFixture(t, dir, "ours.md", memoryFixture(1, "2026-07-02T00:00:00Z", "ours body"))
	theirs := writeMergeFixture(t, dir, "theirs.md", memoryFixture(1, "2026-07-02T00:00:00Z", "theirs body"))

	err := mergeMemoryFiles(base, ours, theirs)
	if err == nil {
		t.Fatal("expected a conflict error")
	}
	raw, _ := os.ReadFile(ours)
	if !strings.Contains(string(raw), "ours body") {
		t.Fatal("ours must be left untouched on conflict")
	}
}

func TestMergeMemoryWithoutBaseUsesMax(t *testing.T) {
	dir := t.TempDir()
	base := writeMergeFixture(t, dir, "base.md", "")
	ours := writeMergeFixture(t, dir, "ours.md", memoryFixture(2, "2026-07-03T00:00:00Z", "same body"))
	theirs := writeMergeFixture(t, dir, "theirs.md", memoryFixture(5, "2026-07-02T00:00:00Z", "same body"))

	if err := mergeMemoryFiles(base, ours, theirs); err != nil {
		t.Fatal(err)
	}
	raw, _ := os.ReadFile(ours)
	e, err := parseEntry("merged", raw)
	if err != nil {
		t.Fatal(err)
	}
	if e.Strength != 5 {
		t.Fatalf("strength = %d, want 5", e.Strength)
	}
}
