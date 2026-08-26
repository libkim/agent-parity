//go:build !configeditor

package main

import (
	"strings"
	"testing"
)

func TestGovernanceInstructionsExposeIDs(t *testing.T) {
	out := withGovernance("BASE", []Entry{{ID: "42", Body: "rule one"}, {ID: "43", Body: "rule two"}})
	if !strings.Contains(out, "[42] rule one") || !strings.Contains(out, "[43] rule two") {
		t.Fatalf("governance instructions must prefix each rule with its id:\n%s", out)
	}
	if withGovernance("BASE", nil) != "BASE" {
		t.Fatal("empty governance should leave the base instructions unchanged")
	}
}
