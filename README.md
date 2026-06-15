# fzf-worktree (PowerShell)

PowerShell helpers for working with Git worktrees using [fzf](https://github.com/junegunn/fzf).

- **Add**: create a new worktree from a remote branch (with commit preview)
- **Switch**: jump to an existing worktree
- **Remove**: delete an existing worktree (with confirmation)

Works especially well with bare-repo + sibling-worktree setups.

## Requirements

- Windows PowerShell 5.1+ or PowerShell 7+
- `git` in `PATH`
- `fzf` in `PATH`

## Files

- `worktree.psm1` – main module exposing a single command: `wt`
- `worktree-add.ps1` / `worktree-switch.ps1` / `worktree-remove.ps1` – standalone script versions (optional)

## Installation

Clone somewhere you control, e.g.:

```powershell
git clone https://github.com/<you>/fzf-worktree.git "$HOME\Tools\fzf-worktree"
```

Import the module (add this to your PowerShell profile for persistence):

```powershell
Import-Module "$HOME\Tools\fzf-worktree\worktree.psm1"
```

## Usage

From any Git repo (bare or non-bare):

```powershell
wt add       # select a remote branch via fzf, create a new sibling worktree, cd into it
wt switch    # pick an existing worktree via fzf and cd into it
wt rm        # pick a worktree via fzf and remove it (excluding the current one)
```

Tab completion is available for `wt` subcommands.
