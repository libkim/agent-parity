//go:build configeditor

package main

import (
	"errors"
	"fmt"
	"os"
	"strings"

	"gopkg.in/yaml.v3"
)

// errMemoryMergeConflict makes the driver exit nonzero so git marks the file
// conflicted and leaves the user to resolve it by hand.
var errMemoryMergeConflict = errors.New("memory bodies changed on both sides")

// mergeMemoryFiles is the git merge driver for memory markdown files: called
// with base (%O), ours (%A), theirs (%B), it writes the merged entry to ours.
// Tags union and created is preserved; a body edited to different content on
// both sides is a real conflict left to the user. Memory files are normally
// created once under a unique id and never rewritten, so same-file conflicts
// are rare — this driver only matters for the occasional explicit edit.
func mergeMemoryFiles(basePath, oursPath, theirsPath string) error {
	baseRaw, err := os.ReadFile(basePath)
	if err != nil {
		return err
	}
	oursRaw, err := os.ReadFile(oursPath)
	if err != nil {
		return err
	}
	theirsRaw, err := os.ReadFile(theirsPath)
	if err != nil {
		return err
	}

	ours, err := parseEntry("ours", oursRaw)
	if err != nil {
		return err
	}
	theirs, err := parseEntry("theirs", theirsRaw)
	if err != nil {
		return err
	}
	// An empty %O means the file has no common ancestor (added on both sides).
	hasBase := len(strings.TrimSpace(string(baseRaw))) > 0
	var base Entry
	if hasBase {
		if base, err = parseEntry("base", baseRaw); err != nil {
			return err
		}
	}

	merged := ours

	switch {
	case ours.Body == theirs.Body:
	case hasBase && ours.Body == base.Body:
		merged.Body = theirs.Body
	case hasBase && theirs.Body == base.Body:
		// merged.Body already holds ours.
	default:
		return errMemoryMergeConflict
	}

	if merged.Created.IsZero() {
		merged.Created = theirs.Created
	}
	merged.Tags = mergeTags(base.Tags, ours.Tags, theirs.Tags)
	// Governance is the escalated type; keep it whenever either side carries it
	// so a cross-machine merge never silently demotes a standing rule to context
	// (parseEntry canonicalizes the other value to "context").
	if ours.Type == "governance" || theirs.Type == "governance" {
		merged.Type = "governance"
	}

	// Mirror the server's writer (store.go write): emit type only for
	// governance, so context memories and pre-type files stay byte-identical.
	fm := frontmatter{Created: merged.Created, Tags: merged.Tags}
	if merged.Type == "governance" {
		fm.Type = "governance"
	}
	y, err := yaml.Marshal(fm)
	if err != nil {
		return err
	}
	content := "---\n" + string(y) + "---\n" + merged.Body + "\n"
	// Same atomic temp+rename as the server's writer: the driver runs during a
	// git merge, and a sync client watching the folder must never see a
	// half-written memory file.
	return atomicWrite(oursPath, []byte(content), 0o644)
}

// mergeTags keeps ours (which reflects any removals made there) and adds the
// tags theirs introduced over base.
func mergeTags(base, ours, theirs []string) []string {
	seen := make(map[string]bool, len(ours))
	merged := append([]string(nil), ours...)
	for _, t := range ours {
		seen[t] = true
	}
	inBase := make(map[string]bool, len(base))
	for _, t := range base {
		inBase[t] = true
	}
	for _, t := range theirs {
		if !seen[t] && !inBase[t] {
			merged = append(merged, t)
			seen[t] = true
		}
	}
	if len(merged) == 0 {
		return nil
	}
	return merged
}

func runMergeMemory(args []string) {
	if len(args) != 3 {
		fmt.Fprintln(os.Stderr, "usage: agent-parity-config merge-memory <base> <ours> <theirs>")
		os.Exit(2)
	}
	if err := mergeMemoryFiles(args[0], args[1], args[2]); err != nil {
		fmt.Fprintln(os.Stderr, "merge-memory:", err)
		os.Exit(1)
	}
}
