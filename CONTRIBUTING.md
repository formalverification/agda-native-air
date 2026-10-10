# Contributing to agda-native-air

Thank you for your interest in contributing to `agda-native-air`!

This project is still in an early phase.  The codebase is real and already
useful, but parts of it are being reorganized and clarified as we move
away from a private research repository and into a public collaboration space.

The goal of this document is to make contribution easier and less intimidating.

---

## What kinds of contributions are welcome?

We welcome help with

- Agda tooling and interaction workflows;
- `agda-dojang` and proof-state tooling;
- `agda-mcp` bridge design and implementation;
- `agda-strux` extraction, ETL, and schema validation;
- retrieval and graph-based views;
- fixture and benchmark design;
- tests, CI, and developer experience;
- documentation and onboarding;
- local specialist models for narrow tasks;
- mathematically informed case studies.

---

## Ground rules

### 1. Agda is the oracle

All AI components are supporting actors. Proposals are cheap; type-checked results
matter.

### 2. Prefer small, reviewable changes

Small PRs are easier to review, test, and merge.

### 3. Preserve clarity over cleverness

This project is a research environment, not just a pile of scripts.
We value explicit structure, readable docs, and reproducible workflows.

### 4. Keep experiments isolated

Exploratory work is welcome, but please put it in a clearly named place
(e.g., `experiments/`) unless it is part of the core environment.

### 5. Update docs when behavior changes

If you change setup, workflow, naming, paths, or architecture, update the relevant
docs.

---

## First-time contributor suggestions

Good early contributions include

- docs cleanup;
- naming consistency (`AgdaJang` → `AgdaDojang`);
- test improvements;
- fixture additions;
- benchmark curation;
- CI polish;
- command-line usability improvements;
- public-facing architecture diagrams.

---

## Development setup

See [`docs/HowToRun.md`](docs/HowToRun.md) for the full developer guide,
including how to build, test, run the MCP server, and connect a coding
agent.

**The short version**.

```sh
git clone git@github.com:formalverification/agda-native-air.git
cd agda-native-air
nix develop          # Agda 2.9.0, Scala/sbt, Python; NOT a pinned GHC
nix develop .#backend # add the pinned GHC 9.10.3 + Cabal (Haskell work)
make check           # build + test all components
 ```

The toolchain is Agda 2.9.0, not yet released (agda/agda at `da66a8c`, the
`nightly` of 2026-10-05), with standard-library 2.3 patched to type-check under
it (formalverification/agda-stdlib, tag `v2.3-agda-2.9.0`).  Until Agda 2.9.0
and a standard library for it are released, the toolchain is available only
through `nix develop`, and the flake needs Nix 2.28 or later; the
`formalverification` Cachix cache serves it prebuilt.

For `agda-mcp` specifically (build, run, connect Claude Code), see
[HowToRun §13](docs/HowToRun.md#13--agda-mcp-ai-assisted-proof-development).

For the project site (build it, serve it locally, run its checks), see
[HowToRun §16](docs/HowToRun.md#16--the-project-site).  It has its own
shell, `nix develop .#site`, and a pip fallback in `requirements.txt`; the
pages under `docs/` are published by allowlist, so a new page is not on the
site until `mkdocs.yml` names it.

If a workflow depends on the Nix shell, please say so in docs and PR
descriptions.


---

## Editing Agda in Emacs

Inside `nix develop`, `agda` is a shell function: it runs the pinned Agda 2.9.0
with `--library-file "$AGDA_DIR/libraries"`, the registry the shell writes at
the root of each checkout, and that registry is the only place `agda-dojang`,
the pinned standard library 2.3 (patched for 2.9.0), and the pinned
agda-algebras are registered.
An Emacs started outside the shell sees none of this, so loading a benchmark
fixture fails with `Library 'agda-dojang' not found`.  You do not have to start
Emacs inside the shell; two steps give agda-mode the same Agda and the same
registry.

### 1. Pin the Agda: `nix build .#agda`

The flake exposes the dev shells' own Agda (Agda 2.9.0 wrapped with the pinned
standard library) as `packages.agda`, beside the pinned agda-algebras as
`packages.agda-algebras`.  From any checkout, build both to links under your
home:

```sh
nix build .#agda -o ~/.cache/agda-native-air/agda
nix build .#agda-algebras -o ~/.cache/agda-native-air/agda-algebras
```

What the two commands give you is as follows:

+  `nix build .#agda` builds, or downloads from the project's Cachix cache,
   exactly the `agda` the Agda-capable dev shells put on `PATH`, so
   `~/.cache/agda-native-air/agda/bin/agda` is the pinned Agda at a path that
   does not move, and `~/.cache/agda-native-air/agda/bin/agda-mode` is its
   agda-mode;
+  each `-o` link is a garbage-collector root, so `nix-collect-garbage` cannot
   delete the Agda, the standard library it wraps, or the agda-algebras copy the
   registry names;
+  after a pin moves (`flake.lock`, or the `agda` input or `stdlibRev` in
   `flake.nix`), the same two commands, run from a checkout at the new pin,
   point the links at the new store paths; each checkout's registry still names
   the old pin's paths until its shell writes it again (below), and those paths
   are no longer rooted, so re-enter the shell there too.

The registry itself, `agda/libraries`, is written by the dev shell, so enter a
checkout's shell once before editing there, and again whenever one of its
pins moves: the registry names that checkout's own `agda-dojang` and the
pin's standard library and agda-algebras by their store paths.  The following
writes it without leaving you in the shell:

```sh
nix develop .#backend --command true
```

### 2. Point agda-mode at it

Add the following to your Emacs configuration (`~/.config/doom/config.el` under
Doom Emacs, your `init.el` otherwise):

```elisp
;; Agda per checkout.  One Agda process serves every buffer, and agda-mode
;; reads `agda2-program-name' and `agda2-program-args' only when it starts
;; that process, so the process keeps the library registry of the checkout it
;; was started for.  This picks the program by the buffer's checkout, and
;; restarts the process when C-c C-l comes from a different checkout:
;;  + agda-native-air: its pinned Agda, its agda/libraries, and its AGDA_DIR;
;;  + any checkout whose dev shell writes the wrapper .agda/bin/agda (as
;;    agda-algebras' does): that wrapper, which names its own registry;
;;  + anything else: `agda2-program-name' as configured.
;; agda-mode starts Agda from the mode's body, before any hook or directory-local
;; variable applies, so the settings are bound around `agda2-restart' itself.
(defvar my/air-agda (expand-file-name "~/.cache/agda-native-air/agda/bin/agda")
  "The pinned Agda 2.9.0 of agda-native-air, kept alive by a GC root.")

(defvar my/agda-process-root nil
  "The checkout the running Agda process was started for, or nil.")

(defun my/agda-checkout (file)
  "The list (ROOT PROGRAM ARGS AGDA-DIR) for FILE's checkout, or nil."
  (cond
   ((when-let* ((root (locate-dominating-file file "agda-dojang/agda-dojang.agda-lib"))
                (registry (expand-file-name "agda/libraries" root))
                ((file-exists-p registry)))
      (list root my/air-agda (list (concat "--library-file=" registry))
            (expand-file-name "agda" root))))
   ((when-let* ((root (locate-dominating-file file ".agda/bin/agda")))
      (list root (expand-file-name ".agda/bin/agda" root) nil
            (expand-file-name ".agda" root))))))

(defun my/agda-restart (restart &rest args)
  "Around `agda2-restart': start the Agda of the current buffer's checkout."
  (let ((checkout (and (buffer-file-name) (my/agda-checkout (buffer-file-name)))))
    (setq my/agda-process-root (car checkout))
    (if (null checkout)
        (prog1 (apply restart args)
          (setq my/agda-process-root nil))
      (pcase-let ((`(,_root ,program ,program-args ,agda-dir) checkout))
        (let ((agda2-program-name program)
              (agda2-program-args program-args)
              (process-environment (cons (concat "AGDA_DIR=" agda-dir)
                                         process-environment)))
          (prog1 (apply restart args)
            (setq my/agda-process-root (car checkout))))))

(defun my/agda-load (load &rest args)
  "Around `agda2-load': restart Agda first if the buffer is in another checkout."
  (let ((root (and (buffer-file-name) (car (my/agda-checkout (buffer-file-name))))))
    (unless (equal root my/agda-process-root)
      (agda2-restart))
    (apply load args)))

(with-eval-after-load 'agda2-mode
  (advice-add 'agda2-restart :around #'my/agda-restart)
  (advice-add 'agda2-load :around #'my/agda-load))
```

If your configuration has the earlier version of this snippet, whose advice
was `my/air-agda-restart`, replace it with this one.

Then `C-c C-l` in a buffer of the checkout loads the file, restarting Agda
first if the running process was started for another checkout; `C-c C-x C-r`
still restarts it by hand.  The snippet is shaped by the following facts:

+  agda-mode starts Agda from the major mode's own body, before mode hooks or
   directory-local variables apply, so a hook or a `.dir-locals.el` would take
   effect only after a manual restart; the snippet binds its settings around
   `agda2-restart` instead;
+  it passes only `--library-file`, not the shell function's `--library` flags,
   because explicit `--library` flags make Agda ignore the file's own
   `.agda-lib`, and a benchmark fixture then fails with
   `ModuleNameDoesntMatchFileName`;
+  `AGDA_DIR` points at the checkout's `agda/`, so a file with no `.agda-lib` of
   its own (the standard-library benchmark tiers, for instance) gets the
   registry's defaults, `agda-dojang` and `standard-library`;
+  one Agda process serves every buffer, and agda-mode reads the program and
   its arguments only when it starts that process, so the process keeps the
   registry of the checkout it was started for; a file from another checkout
   fails against that registry, with an error that depends on what the
   registry names (`ModuleDefinedInOtherFile` when it finds the file's module
   in another worktree, `AmbiguousTopLevelModuleName` when it finds the module
   in two libraries, `Library 'agda-dojang' not found` when it names no
   `agda-dojang`), so the snippet records the checkout the process serves and
   restarts it when `C-c C-l` comes from another;
+  files outside every checkout the snippet recognizes keep whatever Agda your
   configuration already uses.

agda-mode refuses an Agda whose version differs from its own.  No package
manager ships agda-mode 2.9.0 until Agda 2.9.0 is released, so load the
pinned one instead of your own:

```elisp
(load-file (let ((coding-system-for-read 'utf-8))
             (shell-command-to-string "~/.cache/agda-native-air/agda/bin/agda-mode locate")))
```

The same three settings serve any other editor: run
`~/.cache/agda-native-air/agda/bin/agda` with
`--library-file=<checkout>/agda/libraries` and `AGDA_DIR=<checkout>/agda`.

### 3. Other Agda projects in the same Emacs

The snippet's second clause serves any project whose dev shell writes, at the
root of each checkout, a self-contained wrapper `.agda/bin/agda` that runs the
project's pinned Agda with that checkout's registry; agda-algebras' dev shell
writes one.  For such a project, two facts apply, as follows:

+  enter its dev shell once in each checkout, and again when the checkout's
   `flake.lock` moves, to write the wrapper;
+  the wrapper calls an Agda in the Nix store by its path, so if garbage
   collection removes that Agda, agda-mode reports its version as "unknown",
   and entering the dev shell there again restores it.

For a project with another layout, add a clause to `my/agda-checkout` that
returns the checkout's root, its Agda, that Agda's arguments, and its
`AGDA_DIR`.


---

## Issues, branching, pull requests

### Issues

We prefer issues with a clear

+  problem statement
+  motivation and scope
+  acceptance criteria

Adding a list of non-goals can be helpful.

The issue tracker should support the plan, not replace it.

---

### Branch names

Use descriptive names, ideally with an issue number when applicable.

**Examples**.

+  `12-rename-agda-jang-to-agda-dojang`
+  `18-add-mcp-tool-schema`
+  `22-fix-fixture-demo-docs`

It's best if there's a GitHub issue that describes the purpose of a branch;
in that case, if the branch is created using the link on the right-hand side of the
issue page, then GitHub will propose a good branch name for you.

### Pull request guidelines

A good PR should answer the following questions:

+  What changed?
+  Why did it change?
+  How was it tested?
+  What docs were updated?
+  Does it close or relate to an issue?

The repository ships a PR template that prompts for these.

### Merging

We keep a **semi-linear history**.  Before merge, rebase your branch onto `main`
and tidy the commit history, then land the PR as a merge commit (the "Create a
merge commit" button).  Do the rebase and cleanup *before* the approving review —
a later force-push dismisses the approval.  See
[`docs/branch-protection-setup.md`](docs/branch-protection-setup.md) for the full
workflow and the `main` protection rules.

---

## Testing expectations

At minimum, contributors should run the tests relevant to the changed component.

Examples include

+  fixture demo / evaluator tests;
+  extraction / ETL tests;
+  unit tests for `agda-dojang`, `agda-strux`, `agda-mcp`;
+  CI-related smoke tests.

If a change affects reproducibility or setup, please mention exactly what you ran.

---

## Documentation expectations

Relevant docs include the following:

+  [`README.md`](README.md)
+  [`docs/HowToRun.md`](docs/HowToRun.md)
+  [`docs/MANIFESTO.md`](docs/MANIFESTO.md) — vision
+  [`docs/PLAN.md`](docs/PLAN.md) — roadmap + milestones
+  [`docs/GITHUB_PROJECT.md`](docs/GITHUB_PROJECT.md) - living project roadmap (milestones and issues, synced with GitHub)
+  [`docs/representation.md`](docs/representation.md) — data contracts / schemas
+  [`docs/architecture.md`](docs/architecture.md) — system architecture overview
+  [`docs/public-history.md`](docs/public-history.md)

If your change affects, or is relevant to, any of these, please update them in the same PR.

---

## Coding style

We use multiple languages and tools in this repository, including Agda, Haskell,
Rust, Scala, Spark, and Python.  In general,

+  prefer explicit, maintainable code;
+  prefer deterministic behavior in evaluation tooling;
+  isolate experimental code from core infrastructure;
+  keep schemas versioned;
+  avoid silently changing public interfaces.

For language-specific conventions, follow the style already used in the relevant
subproject.

---

## Research directions

Some research directions are intentionally deferred while the environment is
stabilizing; these including the following:

+  deep reflection-driven automation;
+  deep SMT / reflection integration;
+  broad conjecture-generation workflows.

These remain interesting and encouraged as future research directions; they are
simply not a primary focus during the current public bootstrap phase.

---

## Questions

If you are unsure where a contribution belongs, open an issue or draft PR and ask.
That is much better than guessing wrong in silence.  We would rather help shape a
good contribution early than untangle a large one late.


