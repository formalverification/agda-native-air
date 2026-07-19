<!-- File: docs/branch-protection-setup.md -->

# Branch protection and merge settings

Admin runbook for the repository settings that enforce the contribution workflow
for Issue #40.  These settings live on GitHub's servers, not in the repository, so
a repository admin has to apply them once — through the web UI (recommended) or the
API.  This document is the source of truth for what that configuration should be.

The project uses a **semi-linear history**: each PR branch is rebased onto `main`
and its commits are cleaned up *before* merge, and the merge itself lands as a
**merge commit** (the "Create a merge commit" button).  Rebasing first keeps
history free of criss-cross merges; the merge commit then records each PR as a
single, revertible unit whose branch lineage stays visible in `git log --graph`,
while `git log --first-parent main` reads as one line per PR.

There are two pieces to configure, plus the contributor workflow (§3):

+  **Merge-button settings** (Settings → General → Pull Requests) — make the merge
   commit the only merge button.
+  **A branch ruleset for `main`** (Settings → Rules → Rulesets) — require a pull
   request, one approval, resolved conversations, and green CI before anything
   reaches `main`, and block force-pushes and deletion of `main`.

These implement Issue #40's intent, with one refinement: #40 originally asked for
rebase-and-merge; we instead rebase locally and land a merge commit (see the note
in §1 on why).

| # | Intended behavior | Enforced / supported by |
|---|---|---|
| 1 | ≥ 1 review and approval before merging into `main` | Ruleset → Require a pull request → Required approvals = 1 |
| 2 | Merges land as a merge commit over a rebased, tidied branch | General → merge commit is the only button; rebase-first is the documented workflow (§3) |
| 3 | Merge only when CI is green | Ruleset → Require status checks → `All checks` |
| 4 | Nothing merges with unresolved review threads | Ruleset → Require conversation resolution |
| 5 | `main` cannot be force-pushed or deleted | Ruleset → Block force pushes + Restrict deletions |

---

## 1.  Merge-button settings

Go to **Settings → General → Pull Requests** and set:

| Setting | Value |
|---|---|
| Allow merge commits | ✅ on |
| Allow squash merging | ❌ off |
| Allow rebase merging | ❌ off |
| Allow auto-merge | ✅ on (optional; see §3) |
| Always suggest updating pull request branches | ✅ on |
| Automatically delete head branches | ✅ on (recommended) |

Enabling only "Allow merge commits" makes **Create a merge commit** the sole merge
button, so every PR lands the same way and history cleanup has to happen on the
branch beforehand (there is no squash button to lean on).

> **Why a merge commit over a rebased branch, rather than rebase-and-merge?**
> Rebase-and-merge gives a flat history but erases which commits belonged to which
> PR.  Rebasing the branch first and then landing a merge commit keeps history free
> of criss-cross merges *and* records each PR as a unit: `git log --graph` shows
> the branch lineage, `git log --first-parent main` reads as one line per PR, and a
> whole PR reverts with `git revert -m 1 <merge-commit>`.  The one thing GitHub
> cannot enforce is the rebase-first step (see §2 on "Require linear history"), so
> it is a documented convention (§3), not a hard gate.

"Automatically delete head branches" keeps the branch list tidy after merges (the
repository currently carries several stale merged branches).

---

## 2.  Branch ruleset for `main`

Go to **Settings → Rules → Rulesets → New ruleset → New branch ruleset** and
configure it as follows.

**Name**.  `protect main`

**Enforcement status**.  Active

**Bypass list**.  Leave empty for strict enforcement.  To keep an escape hatch
while bootstrapping, add the **Repository admin** role as a bypass actor — but note
that lets admins merge unreviewed, which defeats rule 1 for those accounts.

**Target branches**.  Add target → **Include default branch**.

**Rules** — enable these boxes:

+  **Restrict deletions** — nobody can delete `main`.
+  **Block force pushes** — `main`'s history cannot be rewritten.  This applies to
   `main` only; PR/feature branches stay force-pushable, which the cleanup step in
   §3 relies on.
+  **Require a pull request before merging**, with:
   +  **Required approvals**: `1`
   +  **Dismiss stale pull request approvals when new commits are pushed**: ✅
   +  **Require conversation resolution before merging**: ✅
   +  **Allowed merge methods**: check **Merge** only (uncheck Rebase and Squash)
+  **Require status checks to pass**, with:
   +  **Require branches to be up to date before merging**: ✅
   +  Add check → search for **`All checks`** and select it (provided by
      **GitHub Actions**)

Then click **Create**.

> **Leave "Require linear history" OFF.**  That rule rejects merge commits on
> `main`, so it is incompatible with this workflow — turning it on would block
> every merge.  Its usual job (keeping history free of tangled merges) is handled
> instead by the rebase-first convention in §3.  GitHub has no native "semi-linear"
> enforcement, so a reviewer should give the branch a quick glance — is it rebased
> on current `main`? — before merging.

> **The required check is `All checks`, and only that one.**  The CI workflow
> (`.github/workflows/ci.yml`) ends with an aggregator job named `All checks` (YAML
> key `all-green`) that depends on every other lane and fails if any of them fails.
> Requiring just this one job means new lanes are covered automatically — you never
> revisit the ruleset when CI grows a lane.  GitHub only lists a check in the picker
> after it has run at least once, so if `All checks` is not offered yet, let CI run
> on one open PR and then add it.

---

## 3.  Contributor workflow: rebase, tidy, merge

Because `main` requires a PR and blocks direct pushes, every change lands through a
PR's merge button — which is also the moment to confirm the PR is truly ready.

**1. Get the branch ready** — rebase onto the latest `main` and clean up the commit
history:

```sh
git fetch origin
git rebase origin/main                  # replay your commits on top of latest main
MB=$(git merge-base HEAD origin/main)    # = the new main tip you just rebased onto
git rebase -i "$MB"                      # squash fixups, reword messages, drop noise
git push --force-with-lease origin <branch-name>
```

When there are no conflicts to sort out first, `git rebase -i origin/main` does the
rebase and opens the cleanup editor in one step.  `--force-with-lease` updates your
*feature* branch — never `main` — and refuses to clobber if someone else has pushed
to it.

**2. Get the final approval.**  Do the cleanup *before* the approving review: with
"Dismiss stale approvals on push" on, a rebase + force-push after approval dismisses
it and you would need a re-approve.  So the order is **tidy → approve → merge**, with
no pushes between approval and merge.

**3. Merge on the PR page.**  Click **Create a merge commit**.  Keeping this a manual
step is the point: it is the last chance to confirm every review thread is resolved
(the ruleset's "Require conversation resolution" enforces this — the button stays
disabled until they are) and that CI is green.

If you would rather not click manually, **Enable auto-merge → Create a merge commit**
does the same once `All checks` is green, the approval is in, and all conversations
are resolved; the conversation-resolution gate means it will not merge out from under
an open thread.

> If `main` moves after you rebased (another PR merged), "Require branches to be up
> to date" will ask you to rebase again — repeat step 1.  On this low-traffic repo
> that is rare.

---

## 4.  Optional: apply the same settings from the CLI

The UI steps above are the source of truth.  To script it, these `gh` calls apply
the equivalent configuration.  Run them from an admin context (a token with `repo` /
`administration:write` scope).

```sh
REPO="formalverification/agda-native-air"   # adjust if working from a fork

# 1. Merge-button settings (merge-commit only + auto-merge)
gh api "repos/$REPO" \
  --method PATCH \
  --field allow_merge_commit=true \
  --field allow_squash_merge=false \
  --field allow_rebase_merge=false \
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
    {
      "type": "pull_request",
      "parameters": {
        "required_approving_review_count": 1,
        "dismiss_stale_reviews_on_push": true,
        "require_code_owner_review": false,
        "require_last_push_approval": false,
        "required_review_thread_resolution": true,
        "allowed_merge_methods": ["merge"]
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

> There is deliberately no `required_linear_history` rule here — it would block the
> merge commits this workflow depends on.  The exact JSON field names are worth a
> quick cross-check against the current
> [rulesets REST API docs](https://docs.github.com/en/rest/repos/rules), since
> GitHub occasionally extends this schema.

---

## 5.  Verify

+  The **"Your main branch isn't protected"** banner on the repository home page is
   gone.
+  **Settings → Rules → Rulesets** lists `protect main` as **Active**.
+  Open a throwaway PR: the merge button offers **Create a merge commit** (only), and
   stays blocked until `All checks` is green, one approval is in, and all
   conversations are resolved.
+  After a merge, `git log --graph --oneline main` shows the PR's commits branching
   off and rejoining at a merge commit.
