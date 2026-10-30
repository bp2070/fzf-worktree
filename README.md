# fzf-worktree

PowerShell helpers for working with Git worktrees using [fzf](https://github.com/junegunn/fzf). Works especially well with bare-repo + sibling-worktree setups.

- **New**: create a new worktree with a given name (or prompt if omitted) and switch to it
- **Add**: create a new worktree from a remote branch (with commit preview)
- **Switch**: jump to an existing worktree
- **Remove**: delete one or more existing worktrees (with confirmation and protection for local changes)

## Requirements

- Windows PowerShell 5.1+ or PowerShell 7+
- `git` in `PATH`
- `fzf` in `PATH`

> Note: commands assume a remote named `origin` exists; remote branches are listed from `origin` only.

Typical bare-repo + sibling-worktree layout:

```text
repo.git/        # bare repository
feature-xyz/     # worktree created by `wt add`
bugfix-abc/      # another worktree
```

## Files

- `worktree.psm1` – main module exposing a single command: `wt`

## Installation

Clone somewhere you control, e.g.:

```powershell
git clone https://github.com/bp2070/fzf-worktree "$HOME\opt\fzf-worktree"
```

Import the module (add this to your PowerShell profile for persistence):

```powershell
Import-Module "$HOME\opt\fzf-worktree\worktree.psm1"
```

## Usage

From any Git repo (bare or non-bare):

```powershell
wt new <name> # create a new worktree with the given name (prompts if omitted), cd into it
wt add       # select a remote branch via fzf, create a new sibling worktree, cd into it
wt switch    # pick an existing worktree via fzf and cd into it
wt rm        # select one or more worktrees via fzf and remove them (excluding the current one)
wt rm -Force # force-remove selected worktrees, discarding local changes
```

Clean selected worktrees are removed without a confirmation. If any selected worktree contains modified or untracked files, `wt rm` shows one force-removal confirmation; type `y` to discard those changes. `wt rm -Force` also requires one `y` confirmation before force-removing the selection.

Tab completion is available for `wt` subcommands.
