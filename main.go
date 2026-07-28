//go:build !configeditor

// Command memory-mcp is a lightweight, dependency-free stdio MCP server that
// stores cross-agent memory as plain markdown files. It exposes four tools:
// memory_add, memory_search, memory_recent, memory_get.
//
// The memory directory is taken from -dir, else $MEMORY_DIR, else ./memory.
// All logging goes to stderr; stdout is reserved for the MCP stdio channel.
package main

import (
	"context"
	"flag"
	"fmt"
	"log"
	"os"
	"strings"

	"github.com/modelcontextprotocol/go-sdk/mcp"
)

// version is stamped at build time via -ldflags "-X main.version=...".
var version = "dev"

var store *Store

type AddInput struct {
	Text string   `json:"text" jsonschema:"the memory to store: an intent, interest, recurring topic, or decision and its reason"`
	Tags []string `json:"tags,omitempty" jsonschema:"optional tags"`
	Type string   `json:"type,omitempty" jsonschema:"'governance' for a durable project rule that is delivered into every future session automatically; omit or 'context' for ordinary working memory recalled on demand"`
}
type AddOutput struct {
	ID string `json:"id"`
}

func addHandler(ctx context.Context, req *mcp.CallToolRequest, in AddInput) (*mcp.CallToolResult, AddOutput, error) {
	e, err := store.Add(in.Text, in.Tags, in.Type)
	if err != nil {
		return nil, AddOutput{}, err
	}
	return nil, AddOutput{ID: e.ID}, nil
}

type SearchInput struct {
	Query string `json:"query" jsonschema:"keywords to search stored memories"`
	Limit int    `json:"limit,omitempty" jsonschema:"max results (default 5)"`
}
type SearchOutput struct {
	Results []Entry `json:"results"`
}

func searchHandler(ctx context.Context, req *mcp.CallToolRequest, in SearchInput) (*mcp.CallToolResult, SearchOutput, error) {
	limit := in.Limit
	if limit <= 0 {
		limit = 5
	}
	res, err := store.Search(in.Query, limit)
	if err != nil {
		return nil, SearchOutput{}, err
	}
	return nil, SearchOutput{Results: res}, nil
}

type RecentInput struct {
	Limit int `json:"limit,omitempty" jsonschema:"max recent memories (default 10)"`
}
type RecentOutput struct {
	Results []Entry `json:"results"`
}

func recentHandler(ctx context.Context, req *mcp.CallToolRequest, in RecentInput) (*mcp.CallToolResult, RecentOutput, error) {
	limit := in.Limit
	if limit <= 0 {
		limit = 10
	}
	res, err := store.Recent(limit)
	if err != nil {
		return nil, RecentOutput{}, err
	}
	return nil, RecentOutput{Results: res}, nil
}

type GetInput struct {
	ID string `json:"id" jsonschema:"the memory id to fetch"`
}
type GetOutput struct {
	Entry Entry `json:"entry"`
}

func getHandler(ctx context.Context, req *mcp.CallToolRequest, in GetInput) (*mcp.CallToolResult, GetOutput, error) {
	e, err := store.Get(in.ID)
	if err != nil {
		return nil, GetOutput{}, err
	}
	return nil, GetOutput{Entry: e}, nil
}

func main() {
	dir := flag.String("dir", "", "memory directory (overrides $MEMORY_DIR; default ./memory)")
	showVersion := flag.Bool("version", false, "print version and exit")
	flag.Parse()

	if *showVersion {
		fmt.Println(version)
		return
	}

	d := *dir
	if d == "" {
		d = os.Getenv("MEMORY_DIR")
	}
	if d == "" {
		d = "memory"
	}

	var err error
	store, err = NewStore(d)
	if err != nil {
		log.Fatalf("init store: %v", err)
	}

	instructions := "Shared cross-agent memory that persists context across sessions and agents. " +
		"These tools can load lazily, so they may be missing from your initial tool list even when the server is connected; confirm availability by calling memory_recent, not by trusting a static list. " +
		"At the start of a session, call memory_recent to load prior context before acting. " +
		"When the user reveals an intent, decision, or preference worth keeping, and when a task reaches a checkpoint or finishes, call memory_add with the fact and its reason. " +
		"Call memory_add with type 'governance' only for a durable project rule that must hold in every future session; those are delivered below automatically and are not returned by recent or search. Everything else is ordinary context. " +
		"When a past topic or decision becomes relevant, call memory_search before acting. " +
		"Store durable context, not secrets, one-off chatter, or facts another source already enforces. " +
		"Memories are saved as plaintext and committed to the repo, which may be shared or public, so never store credentials, tokens, keys, or other sensitive data."

	// Governance memories are the project's standing rules. Fold them into the
	// Instructions so every session receives them at initialize, without an
	// agent having to recall them.
	if gov, gerr := store.Governance(); gerr == nil && len(gov) > 0 {
		var b strings.Builder
		b.WriteString(instructions)
		b.WriteString("\n\nProject governance (standing rules for this project; follow them):")
		for _, g := range gov {
			b.WriteString("\n- ")
			b.WriteString(g.Body)
		}
		instructions = b.String()
	}

	server := mcp.NewServer(&mcp.Implementation{Name: "cross-agent-memory", Version: version}, &mcp.ServerOptions{
		Instructions: instructions,
	})
	mcp.AddTool(server, &mcp.Tool{
		Name:        "memory_add",
		Description: "Store a durable memory (an intent, decision, preference, or outcome and its reason). Call this when the user reveals something worth keeping, and when a task reaches a checkpoint or finishes. Not for one-off chatter. Never store secrets: memories are plaintext committed to the repo (possibly shared or public), so keep out credentials, tokens, keys, and sensitive personal data.",
	}, addHandler)
	mcp.AddTool(server, &mcp.Tool{
		Name:        "memory_search",
		Description: "Search memories by tag and body keywords, ranking a tag match above a body-text match; reading never changes them. Call this before acting when a past topic, decision, or preference may be relevant.",
	}, searchHandler)
	mcp.AddTool(server, &mcp.Tool{
		Name:        "memory_recent",
		Description: "List the most recent memories. Call this at the start of every session to load prior context before acting.",
	}, recentHandler)
	mcp.AddTool(server, &mcp.Tool{
		Name:        "memory_get",
		Description: "Fetch a single memory by id.",
	}, getHandler)

	// A stdio server ending because the client disconnected (EOF) is normal,
	// not a failure, so log and exit 0 rather than crashing.
	if err := server.Run(context.Background(), &mcp.StdioTransport{}); err != nil {
		log.Printf("server stopped: %v", err)
	}
}
