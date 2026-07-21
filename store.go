package main

import (
	"fmt"
	"math"
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
	ID           string    `json:"id"`
	Body         string    `json:"body"`
	Tags         []string  `json:"tags"`
	Created      time.Time `json:"created"`
	Strength     int       `json:"strength"`
	LastAccessed time.Time `json:"lastAccessed"`
}

type frontmatter struct {
	Created      time.Time `yaml:"created"`
	Tags         []string  `yaml:"tags"`
	Strength     int       `yaml:"strength"`
	LastAccessed time.Time `yaml:"lastAccessed"`
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

// Add writes a new memory and returns it.
func (s *Store) Add(body string, tags []string) (Entry, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	now := time.Now().UTC()
	e := Entry{
		ID:           fmt.Sprintf("%d", now.UnixNano()),
		Body:         strings.TrimSpace(body),
		Tags:         tags,
		Created:      now,
		Strength:     1,
		LastAccessed: now,
	}
	if err := s.write(e); err != nil {
		return Entry{}, err
	}
	return e, nil
}

func (s *Store) write(e Entry) error {
	y, err := yaml.Marshal(frontmatter{
		Created:      e.Created,
		Tags:         e.Tags,
		Strength:     e.Strength,
		LastAccessed: e.LastAccessed,
	})
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
		return Entry{ID: id, Body: strings.TrimSpace(text), Strength: 1}, nil
	}
	rest := text[len("---\n"):]
	idx := strings.Index(rest, "\n---\n")
	if idx < 0 {
		return Entry{ID: id, Body: strings.TrimSpace(text), Strength: 1}, nil
	}
	var fm frontmatter
	if err := yaml.Unmarshal([]byte(rest[:idx]), &fm); err != nil {
		return Entry{}, err
	}
	if fm.Strength < 1 {
		fm.Strength = 1
	}
	return Entry{
		ID:           id,
		Body:         strings.TrimSpace(rest[idx+len("\n---\n"):]),
		Tags:         fm.Tags,
		Created:      fm.Created,
		Strength:     fm.Strength,
		LastAccessed: fm.LastAccessed,
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

// Recent returns the newest memories first. It does not reinforce.
func (s *Store) Recent(limit int) ([]Entry, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	all, err := s.all()
	if err != nil {
		return nil, err
	}
	sort.Slice(all, func(i, j int) bool { return all[i].Created.After(all[j].Created) })
	if limit > 0 && len(all) > limit {
		all = all[:limit]
	}
	return all, nil
}

func (s *Store) Get(id string) (Entry, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.read(id)
}

// Search ranks memories by keyword match weighted by recency, then reinforces
// the returned ones. Score = matchCount * exp(-ageDays / strength), an
// Ebbinghaus-style decay where each recall raises strength so frequently used
// memories fade more slowly.
func (s *Store) Search(query string, limit int) ([]Entry, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	all, err := s.all()
	if err != nil {
		return nil, err
	}
	tokens := strings.Fields(strings.ToLower(query))
	now := time.Now().UTC()

	type scored struct {
		e     Entry
		score float64
	}
	var hits []scored
	for _, e := range all {
		hay := strings.ToLower(e.Body + " " + strings.Join(e.Tags, " "))
		match := 0
		for _, t := range tokens {
			match += strings.Count(hay, t)
		}
		if match == 0 {
			continue
		}
		strength := float64(e.Strength)
		if strength < 1 {
			strength = 1
		}
		ageDays := now.Sub(e.Created).Hours() / 24
		r := math.Exp(-ageDays / strength)
		hits = append(hits, scored{e: e, score: float64(match) * r})
	}
	sort.Slice(hits, func(i, j int) bool { return hits[i].score > hits[j].score })
	if limit > 0 && len(hits) > limit {
		hits = hits[:limit]
	}

	out := make([]Entry, 0, len(hits))
	for _, h := range hits {
		h.e.Strength++
		h.e.LastAccessed = now
		_ = s.write(h.e) // reinforce; ignore write error so a read still returns
		out = append(out, h.e)
	}
	return out, nil
}
