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

// governanceFixture emits a governance memory (type: governance in the
// frontmatter) so the merge tests cover that the driver never demotes it.
func governanceFixture(body string, tags ...string) string {
	var b strings.Builder
	b.WriteString("---\ncreated: 2026-07-01T00:00:00Z\n")
	if len(tags) > 0 {
		b.WriteString("tags:\n")
		for _, tag := range tags {
			b.WriteString("    - " + tag + "\n")
		}
	}
	b.WriteString("type: governance\n---\n" + body + "\n")
	return b.String()
}

// A governance memory synced across machines and edited on one side (here a tag
// added on theirs) must stay governance after the merge -- the bug was that the
// driver dropped the type and canonicalized it back to context.
func TestMergeMemoryPreservesGovernanceType(t *testing.T) {
	dir := t.TempDir()
	base := writeMergeFixture(t, dir, "base.md", governanceFixture("rule body", "a"))
	ours := writeMergeFixture(t, dir, "ours.md", governanceFixture("rule body", "a"))
	theirs := writeMergeFixture(t, dir, "theirs.md", governanceFixture("rule body", "a", "b"))

	if err := mergeMemoryFiles(base, ours, theirs); err != nil {
		t.Fatal(err)
	}
	raw, err := os.ReadFile(ours)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(raw), "type: governance") {
		t.Fatalf("merged output dropped the governance type:\n%s", raw)
	}
	e, err := parseEntry("merged", raw)
	if err != nil {
		t.Fatal(err)
	}
	if e.Type != "governance" {
		t.Fatalf("type = %q, want governance", e.Type)
	}
	if strings.Join(e.Tags, ",") != "a,b" {
		t.Fatalf("tags = %v, want [a b]", e.Tags)
	}
}

// If either side marks the memory governance, the merge keeps governance -- it
// never silently loses a standing rule, even when the other side is context.
func TestMergeMemoryKeepsGovernanceFromEitherSide(t *testing.T) {
	for _, tc := range []struct{ name, ours, theirs string }{
		{"theirs governance", memoryFixture("rule body", "a"), governanceFixture("rule body", "a")},
		{"ours governance", governanceFixture("rule body", "a"), memoryFixture("rule body", "a")},
	} {
		t.Run(tc.name, func(t *testing.T) {
			dir := t.TempDir()
			base := writeMergeFixture(t, dir, "base.md", memoryFixture("rule body", "a"))
			ours := writeMergeFixture(t, dir, "ours.md", tc.ours)
			theirs := writeMergeFixture(t, dir, "theirs.md", tc.theirs)

			if err := mergeMemoryFiles(base, ours, theirs); err != nil {
				t.Fatal(err)
			}
			raw, _ := os.ReadFile(ours)
			e, err := parseEntry("merged", raw)
			if err != nil {
				t.Fatal(err)
			}
			if e.Type != "governance" {
				t.Fatalf("type = %q, want governance\n%s", e.Type, raw)
			}
		})
	}
}

// Two ordinary context memories must not gain a type on merge -- context stays
// byte-clean (no type field), matching the server's writer.
func TestMergeMemoryContextStaysUntyped(t *testing.T) {
	dir := t.TempDir()
	base := writeMergeFixture(t, dir, "base.md", memoryFixture("body", "a"))
	ours := writeMergeFixture(t, dir, "ours.md", memoryFixture("body", "a"))
	theirs := writeMergeFixture(t, dir, "theirs.md", memoryFixture("body", "a", "b"))

	if err := mergeMemoryFiles(base, ours, theirs); err != nil {
		t.Fatal(err)
	}
	raw, _ := os.ReadFile(ours)
	if strings.Contains(string(raw), "type:") {
		t.Fatalf("context memory gained a type field:\n%s", raw)
	}
}
