---
name: write-governance
description: Write a standing project rule that every future session must follow — the kind stored as a governance memory and delivered automatically at the start of each session. Use when the user settles a durable rule, boundary, or invariant. One of agent-parity's default authoring skills.
---

# Writing a governance rule

A governance rule is a standing constraint the project must hold in every future session — a boundary, an invariant, a non-negotiable. Unlike an ordinary memory recalled on demand, it is delivered into every session automatically, so it is always in effect and always costs context. Write each one to earn that cost.

## Write it

- **One rule per entry.** State a single constraint. If you wrote "and", split it.
- **Declarative and actionable.** Say what must or must not happen, in words an agent can act on — not a topic or an aspiration.
- **Rationale only when it is not self-evident.** A rule with a "because" reads as if it has an exception wherever the reason does not apply. Add the reason only when the rule cannot be applied without it — an intent, or an abstract criterion. Otherwise state the rule alone.
- **Name the boundary.** If the rule separates two things that were being confused, say which is which.

## Keep the set small

Every governance rule is read in full at the start of every session, so the set competes with the actual work for context. Prefer few load-bearing rules over many small ones. Before adding one, check whether it is already covered; before keeping one, check whether it still holds. Retire a rule that no longer applies instead of letting it accumulate.

## Store it

Save the finished rule with memory_add using type governance. Ordinary decisions and working context are not governance — store those as context memory, so governance stays reserved for rules that truly must hold every time.
