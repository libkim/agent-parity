//go:build configeditor

package main

import (
	"fmt"
	"os"
)

func configEditorUsage() {
	fmt.Fprintln(os.Stderr, "usage: agent-parity-config <ensure|command|has|merge-hook|merge-claude-settings|merge-cursor-cli|has-sync-hook|has-agent-hook|has-cursor-cli|unmerge|unmerge-hook|unmerge-claude-settings|unmerge-cursor-cli> <config> [value]")
	os.Exit(2)
}

func main() {
	if len(os.Args) < 3 {
		configEditorUsage()
	}
	op, path := os.Args[1], os.Args[2]
	switch op {
	case "ensure":
		if len(os.Args) != 4 {
			configEditorUsage()
		}
		changed, err := ensureMemoryConfig(path, os.Args[3])
		if err != nil {
			fmt.Fprintln(os.Stderr, "ensure:", err)
			os.Exit(1)
		}
		if changed {
			fmt.Println("changed")
		} else {
			fmt.Println("unchanged")
		}
	case "command":
		if len(os.Args) != 3 {
			configEditorUsage()
		}
		command, exists, err := configMemoryCommand(path)
		if err != nil {
			fmt.Fprintln(os.Stderr, "command:", err)
			os.Exit(2)
		}
		if !exists {
			os.Exit(1)
		}
		fmt.Println(command)
	case "has":
		if len(os.Args) != 3 {
			configEditorUsage()
		}
		_, exists, err := configMemoryCommand(path)
		if err != nil {
			fmt.Fprintln(os.Stderr, "has:", err)
			os.Exit(2)
		}
		if !exists {
			os.Exit(1)
		}
	case "has-sync-hook":
		if len(os.Args) != 4 {
			configEditorUsage()
		}
		exists, err := hasClaudeSyncHook(path, os.Args[3])
		if err != nil {
			fmt.Fprintln(os.Stderr, "has-sync-hook:", err)
			os.Exit(2)
		}
		if !exists {
			os.Exit(1)
		}
	case "has-agent-hook":
		if len(os.Args) != 4 {
			configEditorUsage()
		}
		exists, err := hasAgentHook(path, os.Args[3])
		if err != nil {
			fmt.Fprintln(os.Stderr, "has-agent-hook:", err)
			os.Exit(2)
		}
		if !exists {
			os.Exit(1)
		}
	case "has-cursor-cli":
		if len(os.Args) != 3 {
			configEditorUsage()
		}
		exists, err := hasCursorCLIAllowlist(path)
		if err != nil {
			fmt.Fprintln(os.Stderr, "has-cursor-cli:", err)
			os.Exit(2)
		}
		if !exists {
			os.Exit(1)
		}
	case "merge-hook":
		if len(os.Args) != 4 {
			configEditorUsage()
		}
		if err := mergeAgentHook(path, os.Args[3], "", ""); err != nil {
			fmt.Fprintln(os.Stderr, "merge-hook:", err)
			os.Exit(2)
		}
	case "merge-claude-settings":
		if len(os.Args) != 4 {
			configEditorUsage()
		}
		if err := mergeClaudeSettings(path, os.Args[3]); err != nil {
			fmt.Fprintln(os.Stderr, "merge-claude-settings:", err)
			os.Exit(2)
		}
	case "merge-cursor-cli":
		if len(os.Args) != 3 {
			configEditorUsage()
		}
		changed, err := mergeCursorCLI(path)
		if err != nil {
			fmt.Fprintln(os.Stderr, "merge-cursor-cli:", err)
			os.Exit(2)
		}
		if changed {
			fmt.Println("changed")
		} else {
			fmt.Println("unchanged")
		}
	case "unmerge":
		if len(os.Args) != 3 {
			configEditorUsage()
		}
		command, exists, err := configMemoryCommand(path)
		if err != nil {
			fmt.Fprintln(os.Stderr, "unmerge:", err)
			os.Exit(2)
		}
		if !exists || !isManagedMemoryCommand(command) {
			fmt.Println("unchanged")
			return
		}
		if err := unmergeServerConfig(path); err != nil {
			fmt.Fprintln(os.Stderr, "unmerge:", err)
			os.Exit(2)
		}
		fmt.Println("changed")
	case "unmerge-hook":
		if len(os.Args) != 4 {
			configEditorUsage()
		}
		changed, err := runConfigMutation(path, func(path string) error { return unmergeAgentHook(path, os.Args[3]) })
		if err != nil {
			fmt.Fprintln(os.Stderr, "unmerge-hook:", err)
			os.Exit(2)
		}
		if changed {
			fmt.Println("changed")
		} else {
			fmt.Println("unchanged")
		}
	case "unmerge-claude-settings":
		if len(os.Args) != 3 {
			configEditorUsage()
		}
		changed, err := runConfigMutation(path, unmergeClaudeSettings)
		if err != nil {
			fmt.Fprintln(os.Stderr, "unmerge-claude-settings:", err)
			os.Exit(2)
		}
		if changed {
			fmt.Println("changed")
		} else {
			fmt.Println("unchanged")
		}
	case "unmerge-cursor-cli":
		if len(os.Args) != 3 {
			configEditorUsage()
		}
		changed, err := runConfigMutation(path, unmergeCursorCLI)
		if err != nil {
			fmt.Fprintln(os.Stderr, "unmerge-cursor-cli:", err)
			os.Exit(2)
		}
		if changed {
			fmt.Println("changed")
		} else {
			fmt.Println("unchanged")
		}
	default:
		configEditorUsage()
	}
}
