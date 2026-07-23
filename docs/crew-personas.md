# Crew personas

Crew personas are private reusable work profiles for crewmates.
A profile changes how authorized work is approached, not what work is authorized.
It never overrides Firstmate, project instructions, isolation, scope, delivery mode, validation, status, supervision, destructive authority, merge authority, or captain communication boundaries.

## Setup and storage

Private definitions live under `config/crew-personas/<lowercase-kebab-name>.md`.
The directory is gitignored.
The tracked sanitized starter source is [`docs/examples/crew-personas/`](examples/crew-personas/).
`bin/fm-bootstrap.sh` runs `bin/fm-persona.sh init`, which atomically installs any missing starter files without replacing local definitions.
Run `bin/fm-persona.sh init` directly to install them before bootstrap.
Run `bin/fm-persona.sh list`, `validate`, `validate <name>`, or `render <name>` to inspect the local library.

A name contains lowercase letters, digits, and hyphens, starts and ends alphanumeric, and cannot contain whitespace, dots, separators, controls, or traversal.
The owner helper rejects missing files, non-regular files, symlinks, binary content, oversized content, and an invalid required structure.
A persona starts with one display-name H1 and has exactly these H2 sections in order: Mission, Domain Expertise, Tool Expertise, Decision Rules, Working Method, Verification Strategy, Common Failure Modes, Deliverable Standards, and Boundaries.
Keep personas concise and concrete rather than roleplay or adjectives.

Custom personas must state that repository instructions outrank them, read the nearest applicable `AGENTS.md`, inspect repository-owned commands first, use `rg` when available, preserve unrelated changes, avoid destructive commands without explicit authorization, verify the smallest relevant surface first, escalate genuine product or irreversible decisions, report evidence rather than confidence, and never install a tool merely to satisfy a persona.
For every tool family named, say when to use it, what question it answers, evidence to inspect first, the repository-preferred command shape, the smallest verification, failure modes, when not to use it, and the acceptable fallback.
Verify that a named tool exists in repository files, docs, configuration, lockfiles, existing scripts, or executable discovery before relying on it.

## Selecting a persona

Firstmate selects a persona with this precedence: an explicit captain selection, then the matched dispatch profile's `persona`, then no persona.
It never infers a persona from model, harness, provider, effort, backend, delivery mode, or merge authority.
Create a brief with `bin/fm-brief.sh <task-id> <repo> --persona investigator`.
The rendered profile appears under `# Work Profile` immediately after `# Task`, while all mandatory scaffold sections remain in their normal order.
The brief atomically records the canonical selected name in `data/<task-id>/persona`.
Spawn reads that sidecar and records `persona=<name>` in task metadata.
An explicit `bin/fm-spawn.sh ... --persona <name>` must match the sidecar or spawning refuses.
No selected persona produces the prior brief and metadata behavior.
Older metadata without `persona=` remains valid for recovery, inspection, cleanup, and supervision.

A scout keeps its persona when promoted to a ship task.
Use `bin/fm-promote.sh <task-id> --persona <name>` only to deliberately replace it.

## Dispatch profiles

`config/crew-dispatch.json` profiles may include an optional `persona` field.
Bootstrap validates the profile field and fully validates each referenced local persona, so an invalid reference blocks dispatch configuration.
The selected quota-balanced candidate carries its own persona unchanged.

```json
{
  "when": "Bounded backend implementation",
  "use": {
    "harness": "pi",
    "model": "openai-codex/gpt-5.6-sol",
    "effort": "medium",
    "persona": "backend-engineer"
  }
}
```

```json
{
  "when": "Ambiguous change",
  "use": [
    { "harness": "claude", "model": "claude-sonnet-5", "effort": "high", "persona": "architect" },
    { "harness": "codex", "model": "gpt-5.5", "effort": "high", "persona": "reviewer" }
  ]
}
```

Use a profile persona for both ship and scout work only when its method fits the task.
For example, select `investigator` for a scout that must reproduce a bug, or `backend-engineer` for an authorized service implementation.
A persona is not an implementation authorization.

## Secondmates

The primary-authoritative inherited-local-material mechanism propagates the complete validated `config/crew-personas/` library to live secondmate homes.
It stages and replaces only that inherited target, mirrors removal when the primary removes its library, and asks a running secondmate to reread after a change.
Secondmates may use inherited profiles for their own crews.
Secondmate-local extensions are unsupported, because the next convergence intentionally replaces the inherited library.
`config/secondmate-harness` remains primary-only and is unrelated to persona inheritance.
