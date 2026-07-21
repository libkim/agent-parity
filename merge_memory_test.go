//go:build configeditor

package main

import (
	"os"
	"path/filepath"
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

// memoryFixture emits an old-format file that still carries the retired
// strength/lastAccessed fields, so the tests also cover that the driver reads
// old files and never writes those fields back.
func memoryFixture(body string, tags ...string) string {
	var b strings.Builder
	b.WriteString("---\ncreated: 2026-07-01T00:00:00Z\n")
	if len(tags) > 0 {
		b.WriteString("tags:\n")
		for _, tag := range tags {
			b.WriteString("    - " + tag + "\n")
		}
	}
	b.WriteString("strength: 3\nlastAccessed: 2026-07-02T00:00:00Z\n---\n" + body + "\n")
	return b.String()
}

func TestMergeMemoryUnionsTagsAndDropsRetiredFields(t *testing.T) {
	dir := t.TempDir()
	base := writeMergeFixture(t, dir, "base.md", memoryFixture("shared body", "a"))
	ours := writeMergeFixture(t, dir, "ours.md", memoryFixture("shared body", "a"))
	theirs := writeMergeFixture(t, dir, "theirs.md", memoryFixture("shared body", "a", "b"))

	if err := mergeMemoryFiles(base, ours, theirs); err != nil {
		t.Fatal(err)
	}
	raw, err := os.ReadFile(ours)
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(string(raw), "strength") || strings.Contains(string(raw), "lastAccessed") {
		t.Fatalf("merged output still carries retired fields:\n%s", raw)
	}
	e, err := parseEntry("merged", raw)
	if err != nil {
		t.Fatal(err)
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
	base := writeMergeFixture(t, dir, "base.md", memoryFixture("old body"))
	ours := writeMergeFixture(t, dir, "ours.md", memoryFixture("old body"))
	theirs := writeMergeFixture(t, dir, "theirs.md", memoryFixture("corrected body"))

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
}

func TestMergeMemoryConflictingBodiesFail(t *testing.T) {
	dir := t.TempDir()
	base := writeMergeFixture(t, dir, "base.md", memoryFixture("old body"))
	ours := writeMergeFixture(t, dir, "ours.md", memoryFixture("ours body"))
	theirs := writeMergeFixture(t, dir, "theirs.md", memoryFixture("theirs body"))

	err := mergeMemoryFiles(base, ours, theirs)
	if err == nil {
		t.Fatal("expected a conflict error")
	}
	raw, _ := os.ReadFile(ours)
	if !strings.Contains(string(raw), "ours body") {
		t.Fatal("ours must be left untouched on conflict")
	}
}

func TestMergeMemoryWithoutBaseSameBodyMerges(t *testing.T) {
	dir := t.TempDir()
	base := writeMergeFixture(t, dir, "base.md", "")
	ours := writeMergeFixture(t, dir, "ours.md", memoryFixture("same body", "a"))
	theirs := writeMergeFixture(t, dir, "theirs.md", memoryFixture("same body", "b"))

	if err := mergeMemoryFiles(base, ours, theirs); err != nil {
		t.Fatal(err)
	}
	raw, _ := os.ReadFile(ours)
	e, err := parseEntry("merged", raw)
	if err != nil {
		t.Fatal(err)
	}
	if strings.Join(e.Tags, ",") != "a,b" {
		t.Fatalf("tags = %v, want [a b]", e.Tags)
	}
}

func TestMergeMemoryWithoutBaseDifferentBodyConflicts(t *testing.T) {
	dir := t.TempDir()
	base := writeMergeFixture(t, dir, "base.md", "")
	ours := writeMergeFixture(t, dir, "ours.md", memoryFixture("ours body"))
	theirs := writeMergeFixture(t, dir, "theirs.md", memoryFixture("theirs body"))

	if err := mergeMemoryFiles(base, ours, theirs); err == nil {
		t.Fatal("expected a conflict when both sides add different bodies")
	}
}
