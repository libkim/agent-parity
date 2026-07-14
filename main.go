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

	"github.com/modelcontextprotocol/go-sdk/mcp"
)

// version is stamped at build time via -ldflags "-X main.version=...".
var version = "dev"

var store *Store

type AddInput struct {
	Text string   `json:"text" jsonschema:"the memory to store: an intent, interest, recurring topic, or decision and its reason"`
	Tags []string `json:"tags,omitempty" jsonschema:"optional tags"`
}
type AddOutput struct {
	ID string `json:"id"`
}

func addHandler(ctx context.Context, req *mcp.CallToolRequest, in AddInput) (*mcp.CallToolResult, AddOutput, error) {
	e, err := store.Add(in.Text, in.Tags)
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
	mergeConfig := flag.String("merge-config", "", "add the memory server entry to a JSON/TOML agent config and exit")
	unmergeConfig := flag.String("unmerge-config", "", "remove the memory server entry from a JSON/TOML agent config and exit")
	hasMemoryConfig := flag.String("has-memory-config", "", "report by exit status whether an agent config has a memory server entry")
	command := flag.String("command", ".agents/mcp/memory/run.sh", "launcher path recorded by -merge-config")
	flag.Parse()

	if *showVersion {
		fmt.Println(version)
		return
	}

	if *mergeConfig != "" {
		if err := mergeServerConfig(*mergeConfig, *command); err != nil {
			fmt.Fprintln(os.Stderr, "merge-config:", err)
			os.Exit(1)
		}
		return
	}

	if *unmergeConfig != "" {
		if err := unmergeServerConfig(*unmergeConfig); err != nil {
			fmt.Fprintln(os.Stderr, "unmerge-config:", err)
			os.Exit(1)
		}
		return
	}

	if *hasMemoryConfig != "" {
		exists, err := hasMemoryServer(*hasMemoryConfig)
		if err != nil {
			fmt.Fprintln(os.Stderr, "has-memory-config:", err)
			os.Exit(2)
		}
		if !exists {
			os.Exit(1)
		}
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

	server := mcp.NewServer(&mcp.Implementation{Name: "cross-agent-memory", Version: version}, &mcp.ServerOptions{
		Instructions: "Shared cross-agent memory that persists context across sessions and agents. " +
			"At the start of a session, call memory_recent to load prior context before acting. " +
			"When the user reveals an intent, decision, or preference worth keeping — and when a task reaches a checkpoint or finishes — call memory_add with the fact and its reason. " +
			"When a past topic or decision becomes relevant, call memory_search before acting. " +
			"Store durable context, not secrets, one-off chatter, or facts another source already enforces.",
	})
	mcp.AddTool(server, &mcp.Tool{
		Name:        "memory_add",
		Description: "Store a durable memory (an intent, decision, preference, or outcome and its reason). Call this when the user reveals something worth keeping, and when a task reaches a checkpoint or finishes. Not for secrets or one-off chatter.",
	}, addHandler)
	mcp.AddTool(server, &mcp.Tool{
		Name:        "memory_search",
		Description: "Search memories by keywords, ranked by relevance and recency (recall reinforces them so they fade more slowly). Call this before acting when a past topic, decision, or preference may be relevant.",
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
