package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestParseEntryAcceptsCRLFFrontmatter(t *testing.T) {
	raw := []byte("---\r\n" +
		"created: 2026-07-18T01:02:03Z\r\n" +
		"tags:\r\n  - windows\r\n  - crlf\r\n" +
		"strength: 3\r\n" +
		"lastAccessed: 2026-07-18T04:05:06Z\r\n" +
		"---\r\n" +
		"memory body\r\nsecond line\r\n")

	entry, err := parseEntry("crlf", raw)
	if err != nil {
		t.Fatal(err)
	}
	if entry.Created.IsZero() || entry.Created.Format(time.RFC3339) != "2026-07-18T01:02:03Z" {
		t.Fatalf("created was not parsed: %v", entry.Created)
	}
	if got := strings.Join(entry.Tags, ","); got != "windows,crlf" {
		t.Fatalf("tags = %q", got)
	}
	if entry.Strength != 3 {
		t.Fatalf("strength = %d", entry.Strength)
	}
	if entry.Body != "memory body\nsecond line" {
		t.Fatalf("body = %q", entry.Body)
	}
}

func TestSearchCRLFMemoryDoesNotNestFrontmatter(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "crlf.md")
	raw := "---\r\n" +
		"created: 2026-07-18T01:02:03Z\r\n" +
		"tags: [windows]\r\n" +
		"strength: 1\r\n" +
		"lastAccessed: 2026-07-18T01:02:03Z\r\n" +
		"---\r\n" +
		"searchable memory\r\n"
	if err := os.WriteFile(path, []byte(raw), 0o644); err != nil {
		t.Fatal(err)
	}
	store, err := NewStore(dir)
	if err != nil {
		t.Fatal(err)
	}
	hits, err := store.Search("searchable", 1)
	if err != nil {
		t.Fatal(err)
	}
	if len(hits) != 1 || hits[0].Created.IsZero() {
		t.Fatalf("unexpected search result: %+v", hits)
	}
	written, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	text := string(written)
	if strings.Count(text, "\n---\n") != 1 {
		t.Fatalf("frontmatter was nested:\n%s", text)
	}
	if strings.Contains(text, "\r\n") {
		t.Fatalf("reinforced file was not normalized to LF: %q", text)
	}
}

func TestAtomicWriteLeavesNoTempAndReadsBack(t *testing.T) {
	dir := t.TempDir()
	s, err := NewStore(dir)
	if err != nil {
		t.Fatal(err)
	}
	e, err := s.Add("atomic body", []string{"x"})
	if err != nil {
		t.Fatal(err)
	}
	// No leftover temp files in the store directory.
	names, _ := os.ReadDir(dir)
	for _, n := range names {
		if strings.HasSuffix(n.Name(), ".tmp") || strings.Contains(n.Name(), ".tmp") {
			t.Fatalf("leftover temp file: %s", n.Name())
		}
	}
	if len(names) != 1 {
		t.Fatalf("expected 1 file, got %d", len(names))
	}
	// Reads back cleanly, and a rewrite (reinforce) replaces atomically.
	got, err := s.Get(e.ID)
	if err != nil || got.Body != "atomic body" {
		t.Fatalf("readback failed: %v / %q", err, got.Body)
	}
	if _, err := s.Search("atomic", 5); err != nil {
		t.Fatal(err)
	}
	names, _ = os.ReadDir(dir)
	if len(names) != 1 {
		t.Fatalf("after reinforce expected 1 file, got %d", len(names))
	}
}
