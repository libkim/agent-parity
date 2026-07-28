---
name: write-requirement
description: Turn a request into a clear, testable requirement — what to accomplish and how to know it is done. Use before starting non-trivial work, or when a task, project, document, or change is stated vaguely. Works for any domain, not only software. One of agent-parity's default authoring skills.
---

# Writing a requirement

A requirement states what to accomplish and how completion is judged, without prescribing how to build it. Write it so someone else — a person or another agent — could carry it out and independently confirm it is finished.

## Structure

Write these parts in order:

1. **Goal** — one sentence naming what to accomplish and for whom. State the outcome, not the steps.
2. **Requirements** — the conditions the result must satisfy, each as a single statement. Use "must" for a hard condition and "should" for a preference. One claim per line; if a line joins two claims with "and", split it.
3. **Acceptance** — how to confirm each requirement is met, written as concrete checks: given a starting state, when an action happens, then the observable result. If you cannot write a check for a requirement, it is not yet testable — rewrite it until you can.
4. **Assumptions** — what you took as given to write the above. Stating them lets a reader correct a wrong one.

## Make it testable

A requirement is testable when its truth can be observed without opinion. Replace terms that depend on judgment with the observable property you actually mean: not "fast" but the bound that matters, not "clean" or "robust" but the behavior you would check for. If a requirement cannot be observed, either make it observable or drop it.

## Handle unknowns

When a detail is genuinely undecided, mark it inline as `[NEEDS CLARIFICATION: the specific question]`. Keep at most three; if more surface, the request is too broad to specify as one unit — split it. For every other gap, make an informed guess from context and record it under Assumptions instead of blocking. Do not invent a value and present it as settled.

## Afterward

Once the goal or a decision is settled, store it with memory_add so later sessions and other agents inherit it. The requirement is the reasoning done once; the memory is where its conclusion persists.
