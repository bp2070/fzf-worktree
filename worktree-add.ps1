<#
.SYNOPSIS
    Select a remote Git branch using fzf and check it out into a new sibling worktree
.DESCRIPTION
    Designed for bare repository worktree workflows. It fetches the latest remote refs,
    presents remote branches via fzf, strips the 'origin/' prefix, creates a sibling
    directory for the worktree, and switches your terminal location to it.
#>
function Worktree-Add {
    # 1. Ensure we are inside a git repository environment
    if (-not (git rev-parse --is-inside-work-tree 2>$null -eq "true" -or (git rev-parse --is-bare-repository 2>$null -eq "true"))) {
        Write-Warning "Not in a Git repository or a bare repository context."
        return
    }

    # 2. Fetch the latest remote updates to ensure the list is fresh
    Write-Host "Fetching latest remote branches..." -ForegroundColor Cyan
    git fetch origin --prune

    # 3. Get remote branches, using commit date (most recent first) and filtering out HEAD pointer variations
    # Uses for-each-ref because some Git versions ignore --sort on `git branch -r`.
    # Evaluates lines like "origin/feature-login" (already trimmed)
    $remoteBranches = git for-each-ref --sort=-committerdate --format='%(refname:short)' refs/remotes/origin |
        Where-Object { $_ -notmatch 'HEAD$' -and $_ -notmatch '->' } |
        ForEach-Object { $_.Trim() }

    if (-not $remoteBranches) {
        Write-Error "No remote branches found."
        return
    }

    # 4. Pipe remote branches into fzf for selection, preserving git's order (most recent first)
    #    Show a preview with recent commits for the highlighted branch
    $selectedRemote = $remoteBranches | fzf `
        --no-sort `
        --height 40% `
        --layout=reverse `
        --border `
        --preview 'git log --graph --decorate --color=always -n 20 --pretty=format:"%C(auto)%h %C(bold blue)%an%Creset %s %C(dim green)(%cr)%Creset" {}' `
        --preview-window 'right:70%:wrap' `
        --prompt 'Select remote branch to checkout as worktree: '

    # Exit early if selection was cancelled
    if ([string]::IsNullOrEmpty($selectedRemote)) {
        Write-Host "Selection cancelled." -ForegroundColor Yellow
        return
    }

    # 5. Extract local branch name by stripping the remote prefix (e.g., 'origin/')
    # This handles names with slashes smoothly (e.g., origin/feature/auth -> feature/auth)
    $localBranchName = $selectedRemote -replace '^[^/]+/', ''
    
    # 6. Determine target path. 
    # Because your current active worktree is a folder like 'main', 
    # we place the new folder as a sibling: ../branch-folder-name
    # Replace forward slashes with hyphens or subfolders depending on preference for folder paths
    $folderName = $localBranchName -replace '/', '-'
    $targetPath = Join-Path (Get-Item .).Parent.FullName $folderName

    # Check if folder or worktree already exists
    if (Test-Path $targetPath) {
        Write-Warning "The path '$targetPath' already exists. Aborting to avoid overwriting files."
        return
    }

    Write-Host "Creating worktree for branch '$localBranchName' at '$targetPath'..." -ForegroundColor Green

    # 7. Add the worktree tracking the remote branch
    # syntax: git worktree add <path> <remote-branch>
    git worktree add $targetPath $selectedRemote

    if ($LASTEXITCODE -eq 0) {
        # 8. Switch to the newly created worktree directory
        Set-Location $targetPath
        Write-Host "Switched location to: $(Get-Location)" -ForegroundColor Green
    } else {
        Write-Error "Failed to create Git worktree."
    }
}

# Set an alias so you can quickly invoke it
Set-Alias -Name gwa -Value Worktree-Add
