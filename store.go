package main

import (
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"time"

	"gopkg.in/yaml.v3"
)

// Entry is one stored memory. The markdown file is the source of truth;
// these fields are parsed from its YAML frontmatter plus body.
type Entry struct {
	ID      string    `json:"id"`
	Body    string    `json:"body"`
	Tags    []string  `json:"tags"`
	Created time.Time `json:"created"`
	// Type is "governance" (a durable project rule pushed into every session
	// through the server Instructions) or "context" (ordinary working memory
	// returned by recent/search). A missing field means context.
	Type string `json:"type"`
}

// frontmatter is both the write schema and the fields read back. Older memory
// files may still carry strength/lastAccessed; yaml.Unmarshal ignores unknown
// keys, so those files parse and the retired fields are dropped. New writes
// never emit them. Type is omitted for context memories, so only governance
// memories carry it and files written before the field stay unchanged.
type frontmatter struct {
	Created time.Time `yaml:"created"`
	Tags    []string  `yaml:"tags"`
	Type    string    `yaml:"type,omitempty"`
}

// memoryType canonicalizes the type: "governance" only when explicitly set,
// otherwise "context" (the default and the meaning of a missing field).
func memoryType(t string) string {
	if t == "governance" {
		return "governance"
	}
	return "context"
}

// Store is a directory of markdown files, one file per memory.
type Store struct {
	dir string
	mu  sync.Mutex
}

func NewStore(dir string) (*Store, error) {
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return nil, err
	}
	return &Store{dir: dir}, nil
}

func (s *Store) path(id string) string { return filepath.Join(s.dir, id+".md") }

// Add writes a new memory and returns it. typ is "governance" or "context"
// (empty defaults to context).
func (s *Store) Add(body string, tags []string, typ string) (Entry, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	now := time.Now().UTC()
	e := Entry{
		ID:      fmt.Sprintf("%d", now.UnixNano()),
		Body:    strings.TrimSpace(body),
		Tags:    tags,
		Created: now,
		Type:    memoryType(typ),
	}
	if err := s.write(e); err != nil {
		return Entry{}, err
	}
	return e, nil
}

func (s *Store) write(e Entry) error {
	fm := frontmatter{Created: e.Created, Tags: e.Tags}
	if e.Type == "governance" {
		fm.Type = "governance" // context is the default, so it stays out of the file
	}
	y, err := yaml.Marshal(fm)
	if err != nil {
		return err
	}
	content := "---\n" + string(y) + "---\n" + e.Body + "\n"
	return atomicWrite(s.path(e.ID), []byte(content), 0o644)
}

// atomicWrite writes data to a temp file in the same directory and renames it
// over path. A concurrent reader — including a cloud-sync client watching the
// folder — sees either the previous complete file or the new one, never a
// half-written file, since the partial content only ever lives under the temp
// name. The rename is atomic on POSIX and replaces the target on Windows.
func atomicWrite(path string, data []byte, perm os.FileMode) error {
	f, err := os.CreateTemp(filepath.Dir(path), "."+filepath.Base(path)+".*.tmp")
	if err != nil {
		return err
	}
	tmp := f.Name()
	committed := false
	defer func() {
		if !committed {
			os.Remove(tmp)
		}
	}()
	if _, err := f.Write(data); err != nil {
		f.Close()
		return err
	}
	if err := f.Sync(); err != nil {
		f.Close()
		return err
	}
	if err := f.Close(); err != nil {
		return err
	}
	if err := os.Chmod(tmp, perm); err != nil {
		return err
	}
	if err := os.Rename(tmp, path); err != nil {
		return err
	}
	committed = true
	return nil
}

func (s *Store) read(id string) (Entry, error) {
	raw, err := os.ReadFile(s.path(id))
	if err != nil {
		return Entry{}, err
	}
	return parseEntry(id, raw)
}

func parseEntry(id string, raw []byte) (Entry, error) {
	// Git and Windows tools may check memory files out with CRLF. Parse the
	// frontmatter against one canonical newline form while keeping writes LF.
	text := strings.ReplaceAll(string(raw), "\r\n", "\n")
	if !strings.HasPrefix(text, "---\n") {
		return Entry{ID: id, Body: strings.TrimSpace(text)}, nil
	}
	rest := text[len("---\n"):]
	idx := strings.Index(rest, "\n---\n")
	if idx < 0 {
		return Entry{ID: id, Body: strings.TrimSpace(text)}, nil
	}
	var fm frontmatter
	if err := yaml.Unmarshal([]byte(rest[:idx]), &fm); err != nil {
		return Entry{}, err
	}
	return Entry{
		ID:      id,
		Body:    strings.TrimSpace(rest[idx+len("\n---\n"):]),
		Tags:    fm.Tags,
		Created: fm.Created,
		Type:    memoryType(fm.Type),
	}, nil
}

func (s *Store) all() ([]Entry, error) {
	files, err := os.ReadDir(s.dir)
	if err != nil {
		return nil, err
	}
	var out []Entry
	for _, f := range files {
		if f.IsDir() || !strings.HasSuffix(f.Name(), ".md") {
			continue
		}
		e, err := s.read(strings.TrimSuffix(f.Name(), ".md"))
		if err != nil {
			continue // skip unparseable files rather than failing the whole call
		}
		out = append(out, e)
	}
	return out, nil
}

// Recent returns the newest context memories first, by created time.
// Governance memories are excluded: they reach every session through the server
// Instructions, not through on-demand recall.
func (s *Store) Recent(limit int) ([]Entry, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	all, err := s.all()
	if err != nil {
		return nil, err
	}
	ctx := all[:0]
	for _, e := range all {
		if e.Type != "governance" {
			ctx = append(ctx, e)
		}
	}
	sort.Slice(ctx, func(i, j int) bool { return ctx[i].Created.After(ctx[j].Created) })
	if limit > 0 && len(ctx) > limit {
		ctx = ctx[:limit]
	}
	return ctx, nil
}

// Governance returns the governance memories, oldest first, for the server to
// fold into its Instructions at session start.
func (s *Store) Governance() ([]Entry, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	all, err := s.all()
	if err != nil {
		return nil, err
	}
	var gov []Entry
	for _, e := range all {
		if e.Type == "governance" {
			gov = append(gov, e)
		}
	}
	sort.Slice(gov, func(i, j int) bool { return gov[i].Created.Before(gov[j].Created) })
	return gov, nil
}

func (s *Store) Get(id string) (Entry, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.read(id)
}

// Search returns memories matching the query, ranked by a static, deterministic
// signal so a read never modifies a file. A query token that exactly matches a
// tag outranks one that only matches part of a tag, which outranks one found in
// the body text; more matched tokens and then a newer Created break ties. Tags
// rank above body text because they are the intended recall key, but body text
// stays a fallback so auto-generated tag drift doesn't hide a memory.
func (s *Store) Search(query string, limit int) ([]Entry, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	all, err := s.all()
	if err != nil {
		return nil, err
	}
	tokens := strings.Fields(strings.ToLower(query))

	const (
		tierBody    = 1
		tierPartial = 2
		tierExact   = 3
	)
	type scored struct {
		e     Entry
		tier  int
		count int
	}
	var hits []scored
	for _, e := range all {
		if e.Type == "governance" {
			continue // governance reaches sessions through the Instructions, not search
		}
		tags := make([]string, len(e.Tags))
		for i, t := range e.Tags {
			tags[i] = strings.ToLower(t)
		}
		body := strings.ToLower(e.Body)

		tier, count := 0, 0
		for _, tok := range tokens {
			best := 0
			for _, tag := range tags {
				if tag == tok {
					best = tierExact
					break
				}
				if strings.Contains(tag, tok) && best < tierPartial {
					best = tierPartial
				}
			}
			if best == 0 && strings.Contains(body, tok) {
				best = tierBody
			}
			if best > 0 {
				count++
				if best > tier {
					tier = best
				}
			}
		}
		if tier == 0 {
			continue
		}
		hits = append(hits, scored{e: e, tier: tier, count: count})
	}
	sort.Slice(hits, func(i, j int) bool {
		if hits[i].tier != hits[j].tier {
			return hits[i].tier > hits[j].tier
		}
		if hits[i].count != hits[j].count {
			return hits[i].count > hits[j].count
		}
		return hits[i].e.Created.After(hits[j].e.Created)
	})
	if limit > 0 && len(hits) > limit {
		hits = hits[:limit]
	}

	out := make([]Entry, 0, len(hits))
	for _, h := range hits {
		out = append(out, h.e)
	}
	return out, nil
}
