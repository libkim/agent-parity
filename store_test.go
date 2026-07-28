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
	if entry.Body != "memory body\nsecond line" {
		t.Fatalf("body = %q", entry.Body)
	}
}

func TestSearchReadsCRLFAndDoesNotModifyFile(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "crlf.md")
	// An old-format file: CRLF plus retired strength/lastAccessed fields.
	raw := "---\r\n" +
		"created: 2026-07-18T01:02:03Z\r\n" +
		"tags: [windows]\r\n" +
		"strength: 4\r\n" +
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
	// Search is a pure read: the file must be byte-identical afterward, retired
	// fields and CRLF included.
	after, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if string(after) != raw {
		t.Fatalf("search modified the file:\n%q", string(after))
	}
}

func TestAtomicWriteLeavesNoTempAndReadsBack(t *testing.T) {
	dir := t.TempDir()
	s, err := NewStore(dir)
	if err != nil {
		t.Fatal(err)
	}
	e, err := s.Add("atomic body", []string{"x"}, "")
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
	// Reads back cleanly, and a search does not add or rewrite any file.
	got, err := s.Get(e.ID)
	if err != nil || got.Body != "atomic body" {
		t.Fatalf("readback failed: %v / %q", err, got.Body)
	}
	if _, err := s.Search("atomic", 5); err != nil {
		t.Fatal(err)
	}
	names, _ = os.ReadDir(dir)
	if len(names) != 1 {
		t.Fatalf("after search expected 1 file, got %d", len(names))
	}
}

func TestSearchRanksExactTagOverPartialOverBody(t *testing.T) {
	dir := t.TempDir()
	s, err := NewStore(dir)
	if err != nil {
		t.Fatal(err)
	}
	// created order is irrelevant to tier; ids differ by call time.
	bodyOnly, _ := s.Add("mentions deployment in prose", nil, "")
	partial, _ := s.Add("x", []string{"deployment-notes"}, "")
	exact, _ := s.Add("y", []string{"deploy"}, "")

	hits, err := s.Search("deploy", 10)
	if err != nil {
		t.Fatal(err)
	}
	if len(hits) != 3 {
		t.Fatalf("want 3 hits, got %d", len(hits))
	}
	order := []string{hits[0].ID, hits[1].ID, hits[2].ID}
	want := []string{exact.ID, partial.ID, bodyOnly.ID}
	for i := range want {
		if order[i] != want[i] {
			t.Fatalf("rank %d = %s, want %s (full order %v)", i, order[i], want[i], order)
		}
	}
}

func TestGovernanceIsSeparatedFromContext(t *testing.T) {
	dir := t.TempDir()
	s, err := NewStore(dir)
	if err != nil {
		t.Fatal(err)
	}
	ctxMem, _ := s.Add("ordinary working note about deploy", []string{"deploy"}, "context")
	govMem, _ := s.Add("never break the install/update boundary", []string{"deploy"}, "governance")

	// recent and search return only context, never governance.
	recent, _ := s.Recent(10)
	for _, e := range recent {
		if e.ID == govMem.ID {
			t.Fatal("recent returned a governance memory")
		}
	}
	hits, _ := s.Search("deploy", 10)
	if len(hits) != 1 || hits[0].ID != ctxMem.ID {
		t.Fatalf("search should return only the context memory, got %+v", hits)
	}

	// Governance() returns only governance, and Get by id still works for both.
	gov, _ := s.Governance()
	if len(gov) != 1 || gov[0].ID != govMem.ID {
		t.Fatalf("Governance() = %+v, want the one governance memory", gov)
	}
	got, err := s.Get(govMem.ID)
	if err != nil || got.Type != "governance" {
		t.Fatalf("Get(governance) = %+v, %v", got, err)
	}

	// The governance file carries type; a context file omits it (defaults).
	govRaw, _ := os.ReadFile(filepath.Join(dir, govMem.ID+".md"))
	if !strings.Contains(string(govRaw), "type: governance") {
		t.Fatalf("governance file missing type field:\n%s", govRaw)
	}
	ctxRaw, _ := os.ReadFile(filepath.Join(dir, ctxMem.ID+".md"))
	if strings.Contains(string(ctxRaw), "type:") {
		t.Fatalf("context file should omit type:\n%s", ctxRaw)
	}
}
