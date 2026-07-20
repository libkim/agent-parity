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
// Reinforcement frontmatter merges without conflict — strength takes the
// higher side and lastAccessed the newest — while a body edited to different
// content on both sides is a real conflict left to the user.
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

	merged.Strength = maxInt(ours.Strength, theirs.Strength)
	if merged.Strength < 1 {
		merged.Strength = 1
	}

	if theirs.LastAccessed.After(merged.LastAccessed) {
		merged.LastAccessed = theirs.LastAccessed
	}
	if merged.Created.IsZero() {
		merged.Created = theirs.Created
	}

	merged.Tags = mergeTags(base.Tags, ours.Tags, theirs.Tags)

	y, err := yaml.Marshal(frontmatter{
		Created:      merged.Created,
		Tags:         merged.Tags,
		Strength:     merged.Strength,
		LastAccessed: merged.LastAccessed,
	})
	if err != nil {
		return err
	}
	content := "---\n" + string(y) + "---\n" + merged.Body + "\n"
	return os.WriteFile(oursPath, []byte(content), 0o644)
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

func maxInt(a, b int) int {
	if a > b {
		return a
	}
	return b
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
