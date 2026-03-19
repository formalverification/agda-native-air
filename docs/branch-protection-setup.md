# Branch Protection & Merge Settings Setup

This document explains how to configure the GitHub repository settings and
branch protection rules that enforce the project's contribution workflow.

These settings **cannot** be stored as files in the repository — they must be
applied by a repository admin through the GitHub web UI or via the `gh` CLI.

---

## 1. Repository-Level Merge Settings

Navigate to **Settings → General → Pull Requests** and apply the following:

| Setting | Value |
|---|---|
| Allow merge commits | ❌ Disabled |
| Allow squash merging | ❌ Disabled |
| Allow rebase merging | ✅ Enabled |
| Always suggest updating pull request branches | ✅ Enabled |
| Allow auto-merge | ✅ Enabled |
| Automatically delete head branches | ✅ Enabled (optional but recommended) |

> **Why rebase-only?**  Rebase merging keeps a linear history on `main`,
> making `git log`, `git bisect`, and blame much easier to work with.

---

## 2. Branch Protection Rule for `main`

Navigate to **Settings → Branches → Add branch ruleset** (or
"Add classic branch protection rule" if rulesets are not yet available on
your plan) and configure it as follows.

### Branch name pattern

```
main
```

### Protect matching branches

| Option | Value |
|---|---|
| Require a pull request before merging | ✅ Enabled |
| — Required approvals | `1` |
| — Dismiss stale pull request approvals when new commits are pushed | ✅ Enabled |
| — Require review from Code Owners | optional |
| Require status checks to pass before merging | ✅ Enabled |
| — Require branches to be up to date before merging | ✅ Enabled |
| — Required status checks | `All checks` (the `all-green` aggregator job) |
| Require conversation resolution before merging | ✅ Enabled (recommended) |
| Do not allow bypassing the above settings | ✅ Enabled (recommended) |
| Restrict who can push to matching branches | optional (restrict to admins/bots) |
| Allow force pushes | ❌ Disabled |
| Allow deletions | ❌ Disabled |

> **Required status check name**: The CI workflow declares an aggregator job
> named **`All checks`** (YAML key `all-green`).  Enter exactly `All checks`
> in the status check search box after the CI has run at least once on a PR so
> that GitHub can discover it.

---

## 3. Verify auto-merge works end-to-end

Once both settings above are in place, a contributor can enable auto-merge
on their PR from the PR page ("Enable auto-merge → Rebase and merge").
GitHub will automatically rebase and merge the PR as soon as:

1. All required status checks are green (the `all-green` job passes), **and**
2. The required number of approvals (1) has been granted.

---

## 4. Quick setup via `gh` CLI (alternative to the UI)

If you prefer the command line, the following `gh api` calls apply the same
settings.  Run them from inside a clone of the repository with an admin
token that has `repo` scope (or `administration:write` for rulesets).

```sh
REPO="formalverification/agda-native-air"   # adjust if forked

# 1. Repository merge-button settings
gh api "repos/$REPO" \
  --method PATCH \
  --field allow_merge_commit=false \
  --field allow_squash_merge=false \
  --field allow_rebase_merge=true \
  --field allow_auto_merge=true \
  --field delete_branch_on_merge=true

# 2. Branch protection rule for main
gh api "repos/$REPO/branches/main/protection" \
  --method PUT \
  --header "Accept: application/vnd.github+json" \
  --input - <<'EOF'
{
  "required_status_checks": {
    "strict": true,
    "contexts": ["All checks"]
  },
  "enforce_admins": true,
  "required_pull_request_reviews": {
    "dismiss_stale_reviews": true,
    "require_code_owner_reviews": false,
    "required_approving_review_count": 1
  },
  "restrictions": null,
  "required_conversation_resolution": true,
  "allow_force_pushes": false,
  "allow_deletions": false
}
EOF
```

> **Note:** The status check name `All checks` must already exist in GitHub's
> list of known checks for this repo before the API call will accept it.
> Trigger one CI run on a PR first, then apply this rule.

---

## 5. Confirm the protection is active

After applying the settings, visit the repository's main page.
The warning banner *"Your main branch isn't protected"* should no longer appear.

You can also verify at **Settings → Branches** — the `main` rule should be
listed with a green shield icon.
