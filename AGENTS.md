# AGENTS.md

## Project overview

This repository contains a small PowerShell module for managing Git worktrees with `fzf`.

Primary goals:
- keep the user-facing API centered on a single `wt` command
- support both normal Git repositories and bare-repo + sibling-worktree setups
- provide a fast, interactive workflow for adding, switching, and removing worktrees

## File map

- `worktree.psm1` — the module implementation and the only code file
- `README.md` — installation and usage documentation
- `AGENTS.md` — guidance for coding agents working in this repo

## Current command surface

The module currently exports only:
- `wt`

Supported subcommands:
- `wt new`
- `wt add`
- `wt switch`
- `wt rm`

Helper functions in `worktree.psm1` are internal implementation details unless the user explicitly asks for a broader public API.

## Environment and dependencies

Target environment:
- Windows PowerShell 5.1+
- PowerShell 7+

External dependencies expected in `PATH`:
- `git`
- `fzf`

Behavioral assumptions in the current implementation:
- remote branch discovery uses `origin`
- `wt add` creates sibling worktrees next to the repo root when possible
- branch names used as folder names are normalized by replacing `/` with `-`

## Editing guidelines

When changing this project:

1. Preserve the simple UX.
   - Interactive flows should remain clear and low-friction.
   - Cancellation should be treated as a normal outcome, not an error.
   - Destructive actions should keep confirmation unless the user asks to remove it.

2. Keep compatibility with Windows PowerShell 5.1.
   - Avoid PowerShell 7-only syntax or features unless the project is intentionally being upgraded.
   - Prefer broadly compatible PowerShell constructs.

3. Keep `wt` as the main entry point.
   - Do not export additional commands unless the task specifically requires it.
   - If internal helpers are added, keep them private by default.

4. Respect existing Git/worktree behavior.
   - Continue supporting both bare and non-bare repository contexts.
   - Be careful when changing parsing around `git worktree list --porcelain`.
   - Do not allow `switch` or `rm` to target the current worktree unless intentionally changing that behavior.

5. Be conservative with dependencies.
   - Do not add new module dependencies without a strong reason.
   - Favor built-in PowerShell and standard Git commands.

6. Keep docs in sync.
   - Update `README.md` whenever user-visible behavior, installation steps, or subcommands change.

## Style conventions

- Match the existing script style in `worktree.psm1`.
- Prefer small helper functions over deeply nested logic if behavior grows.
- Use `Write-Host` for positive/status UX messaging, `Write-Warning` for recoverable problems, and `Write-Error` for failures.
- Keep comments focused on intent, not obvious mechanics.
- Preserve readable formatting for multi-line `fzf` invocations.

## Validation checklist

After changing `worktree.psm1`, run at least:

```powershell
pwsh -NoLogo -NoProfile -Command "Import-Module ./worktree.psm1 -Force; Get-Command wt | Out-Null"
```

If you change user-facing behavior, also:
- review `README.md` for accuracy
- sanity-check command names and examples

If interactive behavior is modified and a real Git repo is available, manually test the affected flow:
- `wt new`
- `wt add`
- `wt switch`
- `wt rm`

## Scope guidance for agents

Good changes:
- bug fixes in worktree detection, branch selection, or path handling
- UX improvements that keep the command surface simple
- compatibility fixes for PowerShell or Git edge cases
- README updates that reflect actual behavior

Changes that should be deliberate and clearly documented:
- adding new exported commands or subcommands
- changing remote-selection behavior away from `origin`
- changing where new worktrees are created
- removing confirmations or safety checks
- introducing non-interactive behavior flags
