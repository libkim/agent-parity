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

func TestGovernanceStatusLifecycle(t *testing.T) {
	dir := t.TempDir()
	s, err := NewStore(dir)
	if err != nil {
		t.Fatal(err)
	}
	keep, _ := s.Add("always vendor the lockfile", []string{"rule"}, "governance")
	drop, _ := s.Add("prefer tabs over spaces", []string{"rule"}, "governance")

	// A fresh memory is active, and an active file omits the status field.
	if keep.Status != "active" {
		t.Fatalf("new memory status = %q, want active", keep.Status)
	}
	if raw, _ := os.ReadFile(filepath.Join(dir, keep.ID+".md")); strings.Contains(string(raw), "status:") {
		t.Fatalf("active file should omit status:\n%s", raw)
	}

	// Deprecating one drops it from Governance() but keeps it fetchable by id,
	// and the file records the status.
	if _, err := s.Update(drop.ID, "deprecated"); err != nil {
		t.Fatal(err)
	}
	if gov, _ := s.Governance(); len(gov) != 1 || gov[0].ID != keep.ID {
		t.Fatalf("Governance() after deprecate = %+v, want only %s", gov, keep.ID)
	}
	if got, err := s.Get(drop.ID); err != nil || got.Status != "deprecated" {
		t.Fatalf("Get(deprecated) = %+v, %v", got, err)
	}
	if raw, _ := os.ReadFile(filepath.Join(dir, drop.ID+".md")); !strings.Contains(string(raw), "status: deprecated") {
		t.Fatalf("deprecated file missing status:\n%s", raw)
	}

	// "merged" is likewise excluded, and moving between the two retired values
	// is still allowed: they disagree on why the rule stopped applying, not on
	// whether it did.
	if _, err := s.Update(drop.ID, "merged"); err != nil {
		t.Fatal(err)
	}
	if gov, _ := s.Governance(); len(gov) != 1 {
		t.Fatalf("merged governance should stay out of Governance(), got %+v", gov)
	}

	// Retirement is one-way. Reinstating a rule means writing it again as a new
	// memory, so a retired one can never be set back to active.
	if _, err := s.Update(drop.ID, "active"); err == nil {
		t.Fatal("Update reactivated a retired memory")
	}
	if got, err := s.Get(drop.ID); err != nil || got.Status != "merged" {
		t.Fatalf("rejected reactivation must leave the memory retired: %+v, %v", got, err)
	}
	if gov, _ := s.Governance(); len(gov) != 1 {
		t.Fatalf("rejected reactivation must not restore injection, got %+v", gov)
	}

	// The same holds for a memory that is still active: "active" is not a
	// status this API sets, so the call is refused rather than silently passing.
	if _, err := s.Update(keep.ID, "active"); err == nil {
		t.Fatal("Update accepted \"active\" as a target status")
	}
	if gov, _ := s.Governance(); len(gov) != 1 || gov[0].ID != keep.ID {
		t.Fatalf("refused call must leave the active rule untouched, got %+v", gov)
	}

	// An unknown status is rejected.
	if _, err := s.Update(keep.ID, "archived"); err == nil {
		t.Fatal("Update accepted an invalid status")
	}

	// The lifecycle is about what reaches a session's instructions, and context
	// memories never do, so a status on one would report success for a no-op:
	// recent and search do not filter on it.
	ctx, err := s.Add("ordinary working note", []string{"note"}, "")
	if err != nil {
		t.Fatal(err)
	}
	if _, err := s.Update(ctx.ID, "deprecated"); err == nil {
		t.Fatal("Update retired a context memory")
	}
	if got, err := s.Get(ctx.ID); err != nil || got.Status != "active" {
		t.Fatalf("refused call must leave the context memory untouched: %+v, %v", got, err)
	}
	if raw, _ := os.ReadFile(filepath.Join(dir, ctx.ID+".md")); strings.Contains(string(raw), "status:") {
		t.Fatalf("refused call must not write a status field:\n%s", raw)
	}
	if recent, _ := s.Recent(10); len(recent) != 1 || recent[0].ID != ctx.ID {
		t.Fatalf("context memory should still be returned by Recent, got %+v", recent)
	}
}

func TestLegacyGovernanceWithoutStatusIsActive(t *testing.T) {
	dir := t.TempDir()
	s, err := NewStore(dir)
	if err != nil {
		t.Fatal(err)
	}
	// A file written before the status field existed carries no status and must
	// still be delivered as an active governance rule.
	legacy := "---\ncreated: 2020-01-01T00:00:00Z\ntags: []\ntype: governance\n---\nlegacy rule\n"
	if err := os.WriteFile(filepath.Join(dir, "42.md"), []byte(legacy), 0o644); err != nil {
		t.Fatal(err)
	}
	if e, err := s.Get("42"); err != nil || e.Status != "active" {
		t.Fatalf("legacy memory status = %+v, %v; want active", e, err)
	}
	if gov, _ := s.Governance(); len(gov) != 1 || gov[0].ID != "42" {
		t.Fatalf("legacy governance should be active and injected, got %+v", gov)
	}
}

func TestGovernanceByStatusFiltersAndIncludesRetired(t *testing.T) {
	dir := t.TempDir()
	s, err := NewStore(dir)
	if err != nil {
		t.Fatal(err)
	}
	act, _ := s.Add("live rule", nil, "governance")
	dep, _ := s.Add("old rule", nil, "governance")
	mer, _ := s.Add("absorbed rule", nil, "governance")
	s.Add("just a note", nil, "context")
	if _, err := s.Update(dep.ID, "deprecated"); err != nil {
		t.Fatal(err)
	}
	if _, err := s.Update(mer.ID, "merged"); err != nil {
		t.Fatal(err)
	}

	ids := func(es []Entry) map[string]bool {
		m := map[string]bool{}
		for _, e := range es {
			m[e.ID] = true
		}
		return m
	}

	// No filter returns every governance memory including retired ones, and no
	// context memory.
	all, _ := s.GovernanceByStatus("")
	got := ids(all)
	if len(all) != 3 || !got[act.ID] || !got[dep.ID] || !got[mer.ID] {
		t.Fatalf("GovernanceByStatus(\"\") = %+v, want the 3 governance memories", all)
	}

	// Status filters narrow to one lifecycle.
	if d, _ := s.GovernanceByStatus("deprecated"); len(d) != 1 || d[0].ID != dep.ID {
		t.Fatalf("deprecated filter = %+v, want %s", d, dep.ID)
	}
	if a, _ := s.GovernanceByStatus("active"); len(a) != 1 || a[0].ID != act.ID {
		t.Fatalf("active filter = %+v, want %s", a, act.ID)
	}
	if _, err := s.GovernanceByStatus("bogus"); err == nil {
		t.Fatal("GovernanceByStatus accepted an invalid status")
	}
}

func TestAddNormalizesCRLFBodyToLF(t *testing.T) {
	dir := t.TempDir()
	s, err := NewStore(dir)
	if err != nil {
		t.Fatal(err)
	}

	// A body quoted from a Windows source arrives with CRLF through the tool
	// call; Add is the one writer whose body is not already parseEntry output.
	entry, err := s.Add("first line\r\nsecond line\r\n\r\nfourth line", []string{"crlf"}, "")
	if err != nil {
		t.Fatal(err)
	}

	raw, err := os.ReadFile(filepath.Join(dir, entry.ID+".md"))
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(string(raw), "\r") {
		t.Fatalf("file kept CR bytes: %q", string(raw))
	}
	if !strings.Contains(string(raw), "first line\nsecond line\n\nfourth line\n") {
		t.Fatalf("body was not written with LF: %q", string(raw))
	}

	// The round trip still yields the same body parseEntry would have produced.
	got, err := s.Get(entry.ID)
	if err != nil {
		t.Fatal(err)
	}
	if got.Body != "first line\nsecond line\n\nfourth line" {
		t.Fatalf("body = %q", got.Body)
	}
}
