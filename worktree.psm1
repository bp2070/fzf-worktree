<#!
.SYNOPSIS
    Git worktree helper commands using fzf.
.DESCRIPTION
    Provides a single `wt` command with subcommands:
      - wt add     : create a new worktree from a remote branch
      - wt switch  : switch to an existing worktree
      - wt rm      : remove an existing worktree
#>
function Test-FzfAvailable {
    # Simple dependency check so failures are clearer than a missing-command error
    $fzf = Get-Command fzf -ErrorAction SilentlyContinue
    if (-not $fzf) {
        Write-Error "fzf not found in PATH. Please install fzf and ensure it is available before using 'wt'."
        return $false
    }

    return $true
}


function Invoke-WtAdd {
    # Ensure we are inside a git repository environment (worktree or bare)
    $insideWorkTree = git rev-parse --is-inside-work-tree 2>$null
    $isBareRepo     = git rev-parse --is-bare-repository 2>$null

    if (-not ($insideWorkTree -eq 'true' -or $isBareRepo -eq 'true')) {
        Write-Warning "Not in a Git repository or a bare repository context."
        return
    }
    # Fetch the latest remote updates to ensure the list is fresh
    if (-not (Test-FzfAvailable)) {
        return
    }

    Write-Host "Fetching latest remote branches from 'origin'..." -ForegroundColor Cyan
    git fetch origin --prune

    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to fetch from remote 'origin'."
        return
    }
    # Get remote branches, using commit date (most recent first) and filtering out HEAD pointer variations
    $remoteBranches = git for-each-ref --sort=-committerdate --format='%(refname:short)' refs/remotes/origin |
        Where-Object { $_ -notmatch 'HEAD$' -and $_ -notmatch '->' } |
        ForEach-Object { $_.Trim() }

    if (-not $remoteBranches) {
        Write-Error "No remote branches found on 'origin'."
        return
    }

    # Select remote branch via fzf, with preview
    $selectedRemote = $remoteBranches | fzf `
        --no-sort `
        --height 40% `
        --layout=reverse `
        --border `
        --preview 'git log --graph --decorate --color=always -n 20 --pretty=format:"%C(auto)%h %C(bold blue)%an%Creset %s %C(dim green)(%cr)%Creset" {}' `
        --preview-window 'right:70%:wrap' `
        --prompt 'Select remote branch to checkout as worktree: '

    if ([string]::IsNullOrEmpty($selectedRemote)) {
        Write-Host "Selection cancelled." -ForegroundColor Yellow
        return
    }

    # Derive local branch name and folder name from remote ref
    $localBranchName = $selectedRemote -replace '^[^/]+/', ''   # origin/feature/foo -> feature/foo
    $folderName      = $localBranchName -replace '/', '-'

    # Prefer placing worktrees as siblings of the repository root (or bare repo)
    $repoRoot = git rev-parse --show-toplevel 2>$null
    if ($repoRoot) {
        $parentDir = Split-Path $repoRoot -Parent
    } else {
        # Fallback for bare repositories where --show-toplevel is not available
        $parentDir = (Get-Item .).Parent.FullName
    }

    $targetPath = Join-Path $parentDir $folderName

    if (Test-Path $targetPath) {
        Write-Warning "The path '$targetPath' already exists. Aborting to avoid overwriting files."
        return
    }

    # Determine whether a local branch with this name already exists
    $localBranchExists = $false
    git show-ref --verify --quiet ("refs/heads/{0}" -f $localBranchName) 2>$null
    if ($LASTEXITCODE -eq 0) {
        $localBranchExists = $true
    }

    Write-Host "Creating worktree for branch '$localBranchName' at '$targetPath'..." -ForegroundColor Green

    if ($localBranchExists) {
        # Use the existing local branch
        git worktree add $targetPath $localBranchName
    } else {
        # Create a local branch that tracks the selected remote branch to avoid detached HEAD worktrees
        git worktree add -b $localBranchName $targetPath $selectedRemote
    }

    if ($LASTEXITCODE -eq 0) {
        Set-Location $targetPath
        Write-Host "Switched location to: $(Get-Location)" -ForegroundColor Green
    } else {
        Write-Error "Failed to create Git worktree."
    }
}


function Invoke-WtSwitch {
    # Ensure we are inside a git repository environment (worktree or bare)
    $insideWorkTree = git rev-parse --is-inside-work-tree 2>$null
    $isBareRepo     = git rev-parse --is-bare-repository 2>$null

    if (-not ($insideWorkTree -eq 'true' -or $isBareRepo -eq 'true')) {
        Write-Warning "Not in a Git repository or a bare repository context."
        return
    }

    if (-not (Test-FzfAvailable)) {
        return
    }

    $worktreeList = git worktree list --porcelain
    if (-not $worktreeList) {
        Write-Error "No Git worktrees found."
        return
    }

    $entries = @()
    $current = @{}

    foreach ($line in $worktreeList -split "`n") {
        if ($line -match '^worktree (.+)$') {
            if ($current.Count) {
                $entries += [pscustomobject]$current
                $current = @{}
            }
            $current.Path = $Matches[1]
        } elseif ($line -match '^branch (.+)$') {
            $current.Branch = $Matches[1]
        } elseif ($line -eq 'bare') {
            $current.Bare = $true
        }
    }

    if ($current.Count) {
        $entries += [pscustomobject]$current
    }

    # Omit the bare repo entry
    $entries = $entries | Where-Object { -not $_.Bare }

    if (-not $entries) {
        Write-Error "No Git worktrees found."
        return
    }

    $items = $entries | ForEach-Object {
        $name   = Split-Path -Leaf $_.Path
        $branch = if ($_.Branch) { $_.Branch } else { '(detached HEAD)' }
        "{0}`t{1}`t{2}" -f $_.Path, $name, $branch
    }

    $selected = $items | fzf `
        --no-sort `
        --height 40% `
        --layout=reverse `
        --border `
        --delimiter "`t" `
        --with-nth=2.. `
        --preview 'git -C {1} log --graph --decorate --color=always -n 20 --pretty=format:"%C(auto)%h %C(bold blue)%an%Creset %s %C(dim green)(%cr)%Creset"' `
        --preview-window 'right:70%:wrap' `
        --prompt 'Select worktree to switch to: '

    if ([string]::IsNullOrEmpty($selected)) {
        Write-Host "Selection cancelled." -ForegroundColor Yellow
        return
    }

    $targetPath = ($selected -split "`t", 3)[0]
    Set-Location $targetPath
    Write-Host "Switched to worktree: $targetPath" -ForegroundColor Green
}


function Invoke-WtRemove {
    param(
        [switch] $Force
    )

    # Ensure we are inside a git repository environment (worktree or bare)
    $insideWorkTree = git rev-parse --is-inside-work-tree 2>$null
    $isBareRepo     = git rev-parse --is-bare-repository 2>$null


    if (-not ($insideWorkTree -eq 'true' -or $isBareRepo -eq 'true')) {
        Write-Warning "Not in a Git repository or a bare repository context."
        return
    }

    if (-not (Test-FzfAvailable)) {
        return
    }

    $worktreeList = git worktree list --porcelain
    if (-not $worktreeList) {
        Write-Error "No Git worktrees found."
        return
    }

    $entries = @()
    $current = @{}

    foreach ($line in $worktreeList -split "`n") {
        if ($line -match '^worktree (.+)$') {
            if ($current.Count) {
                $entries += [pscustomobject]$current
                $current = @{}
            }
            $current.Path = $Matches[1]
        } elseif ($line -match '^branch (.+)$') {
            $current.Branch = $Matches[1]
        } elseif ($line -eq 'bare') {
            $current.Bare = $true
        }
    }

    if ($current.Count) {
        $entries += [pscustomobject]$current
    }

    if (-not $entries) {
        Write-Error "No Git worktrees found."
        return
    }

    $currentPath = (Get-Location).ProviderPath
    # Exclude bare repo entry and the current worktree. If Resolve-Path fails (stale entry), keep it so it can be cleaned up.
    $entries = $entries | Where-Object {
        try {
            -not $_.Bare -and (Resolve-Path $_.Path).ProviderPath -ne $currentPath
        } catch {
            $true
        }
    }

    if (-not $entries) {
        Write-Warning "No removable worktrees (current worktree is excluded)."
        return
    }

    $items = $entries | ForEach-Object {
        $name   = Split-Path -Leaf $_.Path
        $branch = if ($_.Branch) { $_.Branch } else { '(detached HEAD)' }
        "{0}`t{1}`t{2}" -f $_.Path, $name, $branch
    }

    $selected = $items | fzf `
        --no-sort `
        --height 40% `
        --layout=reverse `
        --border `
        --delimiter "`t" `
        --with-nth=2.. `
        --preview 'git -C {1} log --graph --decorate --color=always -n 20 --pretty=format:"%C(auto)%h %C(bold blue)%an%Creset %s %C(dim green)(%cr)%Creset"' `
        --preview-window 'right:70%:wrap' `
        --prompt 'Select worktree to remove: '

    if ([string]::IsNullOrEmpty($selected)) {
        Write-Host "Selection cancelled." -ForegroundColor Yellow
        return
    }

    $targetPath, $name, $branch = $selected -split "`t", 3

    if (-not $Force) {
        $confirmation = Read-Host "Remove worktree '$name' ($branch) at '$targetPath'? Type 'yes' to confirm"
        if ($confirmation -ne 'yes') {
            Write-Host "Removal cancelled." -ForegroundColor Yellow
            return
        }
    } else {
        Write-Host "Force-removing worktree '$name' ($branch) at '$targetPath'..." -ForegroundColor Yellow
    }

    if ($Force) {
        git worktree remove --force $targetPath
    } else {
        git worktree remove $targetPath
    }

    if ($LASTEXITCODE -eq 0) {
        Write-Host "Removed worktree: $targetPath" -ForegroundColor Green
    } else {
        Write-Error "Failed to remove Git worktree at '$targetPath'."
    }
}


function wt {
    param(
        [Parameter(Position=0)] [string] $Subcommand,
        [Parameter(ValueFromRemainingArguments=$true)] [string[]] $Rest
    )

    switch ($Subcommand) {
        'add'     { Invoke-WtAdd @Rest }
        'switch'  { Invoke-WtSwitch @Rest }
        'rm'      { Invoke-WtRemove @Rest }

        '' { 
            Write-Host "Usage: wt <subcommand>" -ForegroundColor Yellow
            Write-Host "  wt add     # create a new worktree from a remote branch" -ForegroundColor Yellow
            Write-Host "  wt switch  # switch to an existing worktree" -ForegroundColor Yellow
            Write-Host "  wt rm      # remove an existing worktree" -ForegroundColor Yellow
        }
        default {
            Write-Host "Unknown subcommand: $Subcommand" -ForegroundColor Red
            Write-Host "Valid subcommands: add, switch, rm" -ForegroundColor Yellow
        }
    }
}

# Tab completion for `wt` subcommands
Register-ArgumentCompleter -CommandName wt -ParameterName Subcommand -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

    'add','switch','rm' |
        Where-Object { $_ -like "$wordToComplete*" } |
        ForEach-Object {
            [System.Management.Automation.CompletionResult]::new(
                $_,
                $_,
                'ParameterValue',
                $_
            )
        }
}

Export-ModuleMember -Function wt
