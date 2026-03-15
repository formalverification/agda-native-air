# Git Workflow Cheatsheet

Quick reference guide for the most common Git and GitHub workflow commands. For detailed explanations, see [WORKFLOW.md](WORKFLOW.md).

---

## Creating an Issue

1. Navigate to the repository on GitHub.
2. Click **Issues** → **New issue**.
3. Fill in title and description, then submit.

**Best practices**: Use `[tag]` prefix (e.g., `[bug]`, `[feature]`, `[doc]`) and include clear "what/why/how" details.

---

## Creating a Branch from an Issue

1. Open the issue on GitHub.
2. Look at the right sidebar → **Development** section.
3. Click **"Create a branch"**.
4. Edit branch name to include issue number: `99-fix-foobar`.
5. Click **"Create branch"**.

---

## Cloning the Repository

```bash
# Clone with SSH (recommended)
git clone git@github.com:formalverification/agda-native-air.git

# Clone with HTTPS (alternative)
git clone https://github.com/formalverification/agda-native-air.git

cd agda-native-air
```

---

## Working with Worktrees

### Create a worktree for an existing remote branch

```bash
git fetch origin
git worktree add -b 99-fix-foobar ../worktrees/99-fix-foobar origin/99-fix-foobar
cd ../worktrees/99-fix-foobar
```

### Create a worktree with a new branch

```bash
git worktree add -b 99-new-feature ../worktrees/99-new-feature main
cd ../worktrees/99-new-feature
```

### List and remove worktrees

```bash
git worktree list                               # List all worktrees.
git worktree remove ../worktrees/99-fix-foobar  # Remove a worktree.
git worktree prune                              # Clean up deleted worktrees.
```

---

## Committing and Pushing Changes

```bash
git status                                     # Check changed files.
git add .                                      # Stage all changes.
git commit -m "Fix parser bug (closes #99)"    # Commit with message.
git push origin 99-fix-foobar                  # Push to remote.
```

**Commit message tips**: Use imperative mood ("Add" not "Added"), keep first line under 50 chars, reference issue number.

---

## Creating a Pull Request

### Method 1: Use the link shown after push

```
remote: https://github.com/formalverification/agda-native-air/pull/new/99-fix-foobar
```

Click the link shown after a push, or copy it into your browser, to create the PR.

### Method 2: Through GitHub UI

1. Go to repository → **Pull requests** → **New pull request**.
2. Select your branch as "compare", `main` as "base".
3. Fill in title and description (reference issue: "Closes #99").
4. Click **"Create pull request"**.

---

## Syncing with Main Branch

### Fetch latest changes

```bash
git fetch origin
git log --oneline main..origin/main  # Check for updates
```

### Option 1: Merge (preserves history)

```bash
git checkout 99-fix-foobar
git merge origin/main
git push origin 99-fix-foobar
```

### Option 2: Rebase (cleaner history)

```bash
git checkout 99-fix-foobar
git rebase origin/main
git push origin 99-fix-foobar --force-with-lease
```

---

## Resolving Merge Conflicts

### Manual resolution

```bash
# After conflict occurs:
# 1. Edit conflicting files (remove <<<<<<, ======, >>>>>> markers)
# 2. Mark as resolved:
git add <conflicted-file>

# 3. Complete merge or rebase:
git commit -m "Merge main into 99-fix-foobar"  # (for merge)
git rebase --continue                          # (for rebase)

# 4. Push changes:
git push origin 99-fix-foobar                  # (for merge)
git push origin 99-fix-foobar --force-with-lease  # (for rebase)
```

### Using Meld (visual merge tool)

```bash
# Configure Meld (one-time setup)
git config --global merge.tool meld

# When conflict occurs:
git mergetool

# Meld will open - edit the middle pane to resolve conflicts
# Save (Ctrl+S) and close Meld
# Complete the merge/rebase as shown above
```

### Abort if needed

```bash
git merge --abort    # Abort a merge
git rebase --abort   # Abort a rebase
```

---

## SSH Key Setup (Quick Steps)

### Generate SSH key

```bash
ssh-keygen -t ed25519 -C "your_email@example.com"
# Press Enter for default location, optionally add passphrase
```

### Add to SSH agent

```bash
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519
```

### Add to GitHub

```bash
# Copy public key
cat ~/.ssh/id_ed25519.pub

# Then:
# 1. Go to GitHub → Settings → SSH and GPG keys
# 2. Click "New SSH key"
# 3. Paste key and save
```

### Test connection

```bash
ssh -T git@github.com
# Should see: "Hi username! You've successfully authenticated..."
```

---

## Common Commands Quick Reference

| Task | Command |
|------|---------|
| Check status | `git status` |
| View changes | `git diff` |
| Stage all files | `git add .` |
| Stage specific file | `git add <file>` |
| Commit | `git commit -m "message"` |
| Push | `git push origin <branch>` |
| Pull latest | `git pull origin main` |
| Fetch updates | `git fetch origin` |
| List branches | `git branch -a` |
| Switch branch | `git checkout <branch>` |
| View commit log | `git log --oneline` |
| Undo last commit (keep changes) | `git reset --soft HEAD~1` |
| Discard local changes | `git checkout -- <file>` |

---

## Workflow Summary

1. **Create issue** on GitHub.
2. **Create branch** from issue (`99-fix-foobar`).
3. **Create worktree**: `git worktree add -b 99-fix-foobar ../worktrees/99-fix-foobar origin/99-fix-foobar`
4. **Work on code** in worktree directory.
5. **Commit changes**: `git add . && git commit -m "message"`
6. **Push**: `git push origin 99-fix-foobar`
7. **Create PR** on GitHub.
8. **Sync with main** as needed (merge or rebase).
9. **Address review feedback** and push updates.
10. **Clean up worktree** after PR is merged: `git worktree remove ../worktrees/99-fix-foobar`

---

For detailed explanations, troubleshooting, and best practices, see the complete [WORKFLOW.md](WORKFLOW.md) guide.
