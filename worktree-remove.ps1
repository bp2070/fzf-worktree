<#!
.SYNOPSIS
    Remove an existing Git worktree using fzf.
.DESCRIPTION
    Lists all removable Git worktrees, lets you select one via fzf,
    and removes it after confirmation. The current worktree is excluded.
#>
function Worktree-Remove {
    # Ensure we are inside a git repository environment
    if (-not (git rev-parse --is-inside-work-tree 2>$null -eq "true" -or (git rev-parse --is-bare-repository 2>$null -eq "true"))) {
        Write-Warning "Not in a Git repository or a bare repository context."
        return
    }

    $worktreeList = git worktree list --porcelain
    if (-not $worktreeList) {
        Write-Error "No Git worktrees found."
        return
    }

    # Parse porcelain output into objects with Path and Branch
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

    # Do not offer the current worktree for removal
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

    # Build lines for fzf: <Path><TAB><Display>
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

Set-Alias -Name gwrm -Value Worktree-Remove
