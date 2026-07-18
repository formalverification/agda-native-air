<!-- File: docs/branch-protection-setup.md -->

# Branch protection and merge settings

Admin runbook for the repository settings that enforce the contribution workflow
described in Issue #40.  These settings live on GitHub's servers, not in the
repository, so a repository admin has to apply them once — through the web UI
(recommended) or the API.  This document is the source of truth for what that
configuration should be.

There are two independent pieces:

+  **Merge-button settings** (Settings → General → Pull Requests) — make rebase
   the only merge method and turn on auto-merge.
+  **A branch ruleset for `main`** (Settings → Rules → Rulesets) — require a pull
   request, one approval, and green CI before anything reaches `main`, and block
   force-pushes and deletion.

Together they implement the four rules from Issue #40:

| # | Issue #40 requirement | Enforced by |
|---|---|---|
| 1 | ≥ 1 review and approval before merging into `main` | Ruleset → Require a pull request → Required approvals = 1 |
| 2 | Only "Rebase and merge" (no merge commits) | General → allow rebase only; reinforced by the ruleset's allowed merge methods |
| 3 | Merge only when CI is green | Ruleset → Require status checks → `All checks` |
| 4 | Auto rebase-and-merge once CI passes and it is approved | General → Allow auto-merge, combined with rules 1 and 3 |

---

## 1.  Merge-button settings

Go to **Settings → General → Pull Requests** and set:

| Setting | Value |
|---|---|
| Allow merge commits | ❌ off |
| Allow squash merging | ❌ off |
| Allow rebase merging | ✅ on |
| Allow auto-merge | ✅ on |
| Always suggest updating pull request branches | ✅ on |
| Automatically delete head branches | ✅ on (recommended) |

Leaving rebase as the only enabled method is what removes the "Create a merge
commit" and "Squash and merge" options from the merge button, giving `main` a
linear history that keeps `git log`, `git bisect`, and `git blame` easy to read.
"Automatically delete head branches" keeps the branch list tidy after merges (the
repository currently carries a number of stale merged branches).

---

## 2.  Branch ruleset for `main`

Go to **Settings → Rules → Rulesets → New ruleset → New branch ruleset** and
configure it as follows.

**Name**.  `protect main`

**Enforcement status**.  Active

**Bypass list**.  Leave empty for strict enforcement (nobody may push straight to
`main` or merge without satisfying the rules).  If you want to keep an escape
hatch while bootstrapping, add the **Repository admin** role as a bypass actor —
but note that this lets admins merge unreviewed, which defeats rule 1 for those
accounts.

**Target branches**.  Add target → **Include default branch** (this tracks
whatever the default branch is; equivalently, add a pattern that matches `main`).

**Rules** — enable these boxes:

+  **Restrict deletions** — nobody can delete `main`.
+  **Block force pushes** — history on `main` cannot be rewritten.
+  **Require linear history** — rejects merge commits on `main` (a natural fit
   with rebase-only merging; recommended).
+  **Require a pull request before merging**, with:
   +  **Required approvals**: `1`
   +  **Dismiss stale pull request approvals when new commits are pushed**: ✅
   +  **Require conversation resolution before merging**: ✅ (recommended)
   +  **Allowed merge methods**: check **Rebase** only (uncheck Merge and Squash)
+  **Require status checks to pass**, with:
   +  **Require branches to be up to date before merging**: ✅
   +  Add check → search for **`All checks`** and select it (provided by
      **GitHub Actions**)

Then click **Create**.

> **The required check is `All checks`, and only that one.**  The CI workflow
> (`.github/workflows/ci.yml`) ends with an aggregator job named `All checks`
> (YAML key `all-green`) that depends on every other lane and fails if any of
> them fails.  Requiring just this one job means new lanes are covered
> automatically — you never have to revisit the ruleset when CI grows a lane.
> GitHub only lists a check in the picker after it has run at least once, so if
> `All checks` is not offered yet, let CI run on one open PR and then add it.

---

## 3.  How auto-merge behaves

Once sections 1 and 2 are in place, the flow for a contributor is:

1.  Open a PR into `main`.  CI runs; a reviewer approves.
2.  On the PR page, click **Enable auto-merge → Rebase and merge**.
3.  GitHub merges automatically the moment both conditions hold: `All checks` is
    green **and** the one required approval is in.  If either regresses (a new
    push restarts CI, or a new commit dismisses the stale approval), auto-merge
    waits until they are satisfied again.

This is exactly rule 4: automatic rebase-and-merge, gated on CI and review.

---

## 4.  Optional: apply the same settings from the CLI

The UI steps above are the source of truth.  If you would rather script it, these
`gh` calls apply the equivalent configuration.  Run them from an admin context
(a token with `repo` / `administration:write` scope).

```sh
REPO="formalverification/agda-native-air"   # adjust if working from a fork

# 1. Merge-button settings (rebase-only + auto-merge)
gh api "repos/$REPO" \
  --method PATCH \
  --field allow_merge_commit=false \
  --field allow_squash_merge=false \
  --field allow_rebase_merge=true \
  --field allow_auto_merge=true \
  --field delete_branch_on_merge=true

# 2. Branch ruleset for main (the modern equivalent of the UI steps in §2)
gh api "repos/$REPO/rulesets" \
  --method POST \
  --header "Accept: application/vnd.github+json" \
  --input - <<'EOF'
{
  "name": "protect main",
  "target": "branch",
  "enforcement": "active",
  "bypass_actors": [],
  "conditions": { "ref_name": { "include": ["~DEFAULT_BRANCH"], "exclude": [] } },
  "rules": [
    { "type": "deletion" },
    { "type": "non_fast_forward" },
    { "type": "required_linear_history" },
    {
      "type": "pull_request",
      "parameters": {
        "required_approving_review_count": 1,
        "dismiss_stale_reviews_on_push": true,
        "require_code_owner_review": false,
        "require_last_push_approval": false,
        "required_review_thread_resolution": true,
        "allowed_merge_methods": ["rebase"]
      }
    },
    {
      "type": "required_status_checks",
      "parameters": {
        "strict_required_status_checks_policy": true,
        "do_not_enforce_on_create": false,
        "required_status_checks": [ { "context": "All checks" } ]
      }
    }
  ]
}
EOF
```

> The exact JSON field names are worth a quick cross-check against the current
> [rulesets REST API docs](https://docs.github.com/en/rest/repos/rules), since
> GitHub occasionally extends this schema.  If you prefer the older mechanism,
> classic branch protection (`PUT /repos/$REPO/branches/main/protection`) can
> enforce rules 1 and 3 as well; it just predates rulesets and does not restrict
> merge methods (rule 2 stays with the General settings in §1 either way).

---

## 5.  Verify

+  The **"Your main branch isn't protected"** banner on the repository home page
   is gone.
+  **Settings → Rules → Rulesets** lists `protect main` as **Active**.
+  Open a throwaway PR: the merge button offers **Rebase** only, and merging is
   blocked until `All checks` is green and one approval is in.
