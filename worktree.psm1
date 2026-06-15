<#!
.SYNOPSIS
    Git worktree helper commands using fzf.
.DESCRIPTION
    Provides a single `wt` command with subcommands:
      - wt add     : create a new worktree from a remote branch
      - wt switch  : switch to an existing worktree
      - wt rm      : remove an existing worktree
#>

function Invoke-WtAdd {
    # Ensure we are inside a git repository environment
    if (-not (git rev-parse --is-inside-work-tree 2>$null -eq "true" -or (git rev-parse --is-bare-repository 2>$null -eq "true"))) {
        Write-Warning "Not in a Git repository or a bare repository context."
        return
    }

    # Fetch the latest remote updates to ensure the list is fresh
    Write-Host "Fetching latest remote branches..." -ForegroundColor Cyan
    git fetch origin --prune

    # Get remote branches, using commit date (most recent first) and filtering out HEAD pointer variations
    $remoteBranches = git for-each-ref --sort=-committerdate --format='%(refname:short)' refs/remotes/origin |
        Where-Object { $_ -notmatch 'HEAD$' -and $_ -notmatch '->' } |
        ForEach-Object { $_.Trim() }

    if (-not $remoteBranches) {
        Write-Error "No remote branches found."
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

    # Derive local folder name from branch
    $localBranchName = $selectedRemote -replace '^[^/]+/', ''
    $folderName = $localBranchName -replace '/', '-'
    $targetPath = Join-Path (Get-Item .).Parent.FullName $folderName

    if (Test-Path $targetPath) {
        Write-Warning "The path '$targetPath' already exists. Aborting to avoid overwriting files."
        return
    }

    Write-Host "Creating worktree for branch '$localBranchName' at '$targetPath'..." -ForegroundColor Green
    git worktree add $targetPath $selectedRemote

    if ($LASTEXITCODE -eq 0) {
        Set-Location $targetPath
        Write-Host "Switched location to: $(Get-Location)" -ForegroundColor Green
    } else {
        Write-Error "Failed to create Git worktree."
    }
}

function Invoke-WtSwitch {
    if (-not (git rev-parse --is-inside-work-tree 2>$null -eq "true" -or (git rev-parse --is-bare-repository 2>$null -eq "true"))) {
        Write-Warning "Not in a Git repository or a bare repository context."
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
        }
    }

    if ($current.Count) {
        $entries += [pscustomobject]$current
    }

    if (-not $entries) {
        Write-Error "No Git worktrees found."
        return
    }

    $items = $entries | ForEach-Object {
        $branchName = if ($_.Branch) { $_.Branch } else { "(detached HEAD)" }
        $display = "{0} [{1}]" -f $_.Path, $branchName
        "{0}`t{1}" -f $_.Path, $display
    }

    $selected = $items | fzf `
        --no-sort `
        --height 40% `
        --layout=reverse `
        --border `
        --prompt 'Select worktree to switch to: ' `
        --with-nth=2..

    if ([string]::IsNullOrEmpty($selected)) {
        Write-Host "Selection cancelled." -ForegroundColor Yellow
        return
    }

    $targetPath = ($selected -split "`t", 2)[0]
    Set-Location $targetPath
    Write-Host "Switched to worktree: $targetPath" -ForegroundColor Green
}

function Invoke-WtRemove {
    if (-not (git rev-parse --is-inside-work-tree 2>$null -eq "true" -or (git rev-parse --is-bare-repository 2>$null -eq "true"))) {
        Write-Warning "Not in a Git repository or a bare repository context."
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
    $entries = $entries | Where-Object {
        try {
            (Resolve-Path $_.Path).ProviderPath -ne $currentPath
        } catch {
            $true
        }
    }

    if (-not $entries) {
        Write-Warning "No removable worktrees (current worktree is excluded)."
        return
    }

    $items = $entries | ForEach-Object {
        $branchName = if ($_.Branch) { $_.Branch } else { "(detached HEAD)" }
        $display = "{0} [{1}]" -f $_.Path, $branchName
        "{0}`t{1}" -f $_.Path, $display
    }

    $selected = $items | fzf `
        --no-sort `
        --height 40% `
        --layout=reverse `
        --border `
        --prompt 'Select worktree to remove: ' `
        --with-nth=2..

    if ([string]::IsNullOrEmpty($selected)) {
        Write-Host "Selection cancelled." -ForegroundColor Yellow
        return
    }

    $targetPath = ($selected -split "`t", 2)[0]

    $confirmation = Read-Host "Remove worktree at '$targetPath'? Type 'yes' to confirm"
    if ($confirmation -ne 'yes') {
        Write-Host "Removal cancelled." -ForegroundColor Yellow
        return
    }

    git worktree remove $targetPath
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

Export-ModuleMember -Function wt, Invoke-WtAdd, Invoke-WtSwitch, Invoke-WtRemove
