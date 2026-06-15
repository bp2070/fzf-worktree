<#!
.SYNOPSIS
    Switch to an existing Git worktree using fzf.
.DESCRIPTION
    Lists all Git worktrees using porcelain output, lets you select one via fzf,
    and changes the current directory to that worktree.
#>
function Worktree-Switch {
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

Set-Alias -Name gws -Value Worktree-Switch
