# =============================================================================
# agda-native-air — Flake (Dev Shells for Agda, Scala/sbt/JDK, Python + PyTorch)
#
# File: flake.nix
#
# GOALS
#
#   1) One command dev env: `nix develop`. Batteries included.
#   2) CPU-first by default (portable), GPU opt-in (Linux/NVIDIA).
#   3) Agda works out-of-the-box with stdlib + agda-dojang + agda-algebras
#      registered *project-locally* (no ~/.agda needed).  agda-algebras is a
#      flake input pinned at the benchmark-suite commit (issue #127), built
#      once into a store path with prebuilt interfaces; AGDA_ALGEBRAS_ROOT
#      overrides it with a live checkout.
#   4) Optional external Agda libraries (agda-categories, TypeTopology) via
#      environment variables — no flake edits required.
#   5) Keep things explicit & well-commented for future edits.
#
#
# AGDA LIBRARY CONFIGURATION
#
#   Every Agda-capable shell (default, backend, all) uses `mkAgdaShellSetup`
#   to perform all Agda configuration in one place:
#     - Sets AGDA_DIR to a *top-level* `agda/` directory in the repo root
#       (not inside agda-dojang — Agda configuration is project-wide).
#     - Writes a project-local $AGDA_DIR/libraries file (stdlib + agda-dojang).
#     - Optionally registers external Agda libraries if their *_ROOT env vars
#       are set (see "External Agda libraries" below).
#     - Defines an `agda()` shell function that passes --no-default-libraries
#       and --library flags for all registered libraries.
#
#   External Agda libraries:
#     Set these env vars *before* entering the shell (in .envrc, shell profile,
#     or inline).  Each should point at the **root** of the library checkout —
#     i.e., the directory that contains the `.agda-lib` file:
#
#       AGDA_ALGEBRAS_ROOT=~/git/ualib/agda-algebras/master  nix develop
#       AGDA_CATEGORIES_ROOT=~/git/agda-categories           nix develop
#       AGDA_TYPETOPOLOGY_ROOT=~/git/TypeTopology            nix develop
#
#     agda-algebras alone has a fallback: when AGDA_ALGEBRAS_ROOT is unset,
#     the flake-pinned store copy (with prebuilt interfaces) is registered
#     instead, so `-l agda-algebras` always resolves.
#
#     If the `.agda-lib` file is found, the library is registered and the
#     agda() wrapper passes `--library <name>` automatically.
#
#   Editors started outside the shell:
#     agda() is a shell function, so an editor never sees it.  The shells'
#     own Agda is exposed as `packages.agda` for that case: build it to an out
#     link (`nix build .#agda -o ~/.cache/agda-native-air/agda`) and run it
#     with `--library-file=<checkout>/agda/libraries` and
#     `AGDA_DIR=<checkout>/agda`.  CONTRIBUTING.md, "Editing Agda in Emacs",
#     has the Emacs setup.
#
#
# IMPORTANT NOTE ABOUT PYTHON WHEELS ON NIX
#
#   Many pip wheels (torch, numpy, pandas, etc.) are built for "normal Linux"
#   layouts where runtime libs (libstdc++.so.6, libgcc_s.so.1, zlib, openssl…)
#   are in /usr/lib. Inside a Nix shell they are NOT visible unless we provide
#   them. If we don't, imports fail with "cannot open shared object file…".
#
#   Therefore, in the CPU shells below we:
#     • include pkgsStable.stdenv.cc.cc.lib in packages;
#     • export LD_LIBRARY_PATH to point at those runtime libs.
#
#   This is scoped to the devShell, not global on your machine.
#
#
# PINNING POLICY
#
#   - nixpkgs        : general toolchain (Scala/sbt/JDK/Python/etc.)
#   - nixpkgs-agda   : the Agda package-set machinery (agdaPackages: the
#                      wrapper, the library builder, the standard library's
#                      derivation) and the site's Python
#   - agda           : Agda itself, built by Agda's own flake, whose nixpkgs
#                      also supplies the backend shell's GHC and Cabal
#
#   Agda 2.9.0 is not released yet, and no released standard library
#   type-checks under it, so until both are released the flake pins them
#   itself, as agda-algebras does (ualib/agda-algebras PR #598), as follows:
#
#     +  Agda comes from the `agda` input: agda/agda at a fixed commit, the
#        `nightly` of 2026-10-05, built from source by Agda's own flake (its
#        `base` package, without the `debug` flag of its default build).
#        nixpkgs-agda's Agda package set is rebuilt around it
#        (mkAgdaPackages).  The input's URL names the commit, so `nix flake
#        update` cannot move it; to move it, edit the URL and the standard
#        library together.
#     +  The standard library is nixpkgs-agda's derivation with its `src`
#        moved to formalverification/agda-stdlib's tag v2.3-agda-2.9.0: v2.3
#        with the five changes it needs to type-check under Agda 2.9.0, which
#        that tag's release notes list (stdlibRev and stdlibHash, below).
#     +  agda-strux links Agda as a Haskell library, and the one library
#        that matches the `agda` binary is the library output of the same
#        derivation, built with GHC 9.10.3 from Agda's own nixpkgs.  So the
#        backend shell's GHC, Cabal, and language server come from that
#        package set (pkgsHaskell), not from nixpkgs-agda.
#
#   Once Agda 2.9.0 and a standard library for it are released and nixpkgs
#   packages them, drop the `agda` input and the standard library's override,
#   and return to nixpkgs-agda supplying all of it.
#
#   The flake needs Nix 2.28 or later.  Agda's tree holds six empty
#   directories (the paths of its submodules), which Nix 2.26.3 drops when it
#   unpacks the tree, so that it computes another hash than the one
#   flake.lock records, and stops with `NAR hash mismatch`.
#
#   Updating pins (regenerates flake.lock):
#     nix flake update nixpkgs
#     nix flake update nixpkgs-agda
#
#
# AVAILABLE SHELLS
#
#   nix develop            — default: CPU, Agda + Scala + Python (day-to-day)
#   nix develop .#backend  (Agda backend dev: GHC/Cabal pinned with Agda, pkgsHaskell)
#   nix develop .#all      — monolithic: everything including Spark
#   nix develop .#proofParser — minimal Scala/sbt/JDK
#   nix develop .#mlPipeline  — Scala + Python (CPU), no Agda
#   nix develop .#site        (MkDocs Material for the project site, issue #169; no Agda)
#   nix develop .#gpu      — native Nix CUDA build (Linux only, slow first build)
# =============================================================================
{
  description = "agda-native-air: reproducible dev shells for AgdaDojang + Python/Scala (+ optional GPU)";

  # The project binary cache: prebuilt agda-algebras interfaces, the Agda
  # toolchain, and friends.  Registering it here means a fresh machine PULLS
  # instead of building (Nix prompts once to trust the substituter); CI
  # configures the same cache via cachix-action (#132 review).
  nixConfig = {
    extra-substituters = [ "https://formalverification.cachix.org" ];
    extra-trusted-public-keys = [ "formalverification.cachix.org-1:KG/AJuuli2F4/bA56rUYC9V8ZE/Zw6iZjxJEf40cQOo=" ];
  };

  # ---- Inputs ---------------------------------------------------------------
  # Keep general tools on stable.
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";

  # The Agda package-set machinery, on its own pin (unstable; the lock file
  # makes it exact).  Moving it moves the standard library's derivation and the
  # site's Python, so it moves deliberately (see PINNING POLICY above).
  inputs.nixpkgs-agda.url = "github:NixOS/nixpkgs/nixos-unstable";

  # Agda 2.9.0, unreleased: agda/agda at the commit of the `nightly` of
  # 2026-10-05.  Agda's flake builds it with its own nixpkgs; do not make it
  # follow ours, or its derivation changes and misses the binary cache, which
  # already holds the one agda-algebras uses.  Needs Nix 2.28 or later (see
  # PINNING POLICY above).
  inputs.agda.url = "github:agda/agda/da66a8c75f11d10699a6b38b261efdf244b66f2a";

  # agda-algebras, pinned at the exact commit the benchmark fixtures and the
  # corpus were cut from (issue #127; see data/benchmarks/README.md and
  # docs/corpora/agda-algebras-v0.1.md — the three records must agree).
  # Packaged below like the standard library: a derivation that typechecks
  # the library once and ships its .agdai interfaces, so CI and fresh
  # machines get a warm library from Cachix instead of a per-run rebuild.
  inputs.agda-algebras-src = {
    url = "github:ualib/agda-algebras/4662373d281daf0f20a6319f1a46755a45d33293";
    flake = false;
  };

  # The github-project roadmap engine (docs/GITHUB_PROJECT.md tooling),
  # pinned here in flake.lock; upgrade deliberately with
  # `nix flake update github-project`.  See the Makefile's project-*
  # targets and issue #92.
  inputs.github-project.url = "github:williamdemeo/github-project";

  outputs = { self, nixpkgs, nixpkgs-agda, agda, github-project, agda-algebras-src }:
  let
    systems = [ "x86_64-linux" "aarch64-darwin" "x86_64-darwin" ];

    # Provide, for each system, the following:
    #   system      : the system string (agda.packages is per system);
    #   pkgsStable  : nixpkgs, the general toolchain;
    #   pkgsAgda    : nixpkgs-agda, the Agda package-set machinery;
    #   agdaPkgs    : the Agda package set rebuilt around the `agda` input
    #                 (mkAgdaPackages: agda, mkDerivation, standard-library);
    #   pkgsHaskell : Agda's own nixpkgs, whose GHC 9.10.3 built the Agda
    #                 library agda-strux links (see PINNING POLICY).
    forAllSystems = f:
      nixpkgs.lib.genAttrs systems (system:
        let
          pkgsAgda = import nixpkgs-agda {
            inherit system;
            config = { allowUnfree = true; };
          };
        in
        f {
          inherit system pkgsAgda;
          pkgsStable = import nixpkgs {
            inherit system;
            config = { allowUnfree = true; };
          };
          agdaPkgs = mkAgdaPackages system pkgsAgda;
          pkgsHaskell = agda.inputs.nixpkgs.legacyPackages.${system};
        });

    # ---- Agda 2.9.0 + the patched standard library ---------------------------
    # Agda and its standard library MUST be resolved from the same package set:
    # nixpkgs-agda's Agda package set, rebuilt around the `agda` input's Agda,
    # with the standard library's source moved to the patched v2.3 (see
    # PINNING POLICY).  The same construction as agda-algebras' mkAgdaPackages.
    #
    # To move the standard library, set stdlibRev, put nixpkgs.lib.fakeHash in
    # stdlibHash's place, run `nix build .#agda`, and copy the hash the error
    # prints after `got:`; or ask Nix for it directly:
    #   nix flake prefetch --json github:formalverification/agda-stdlib/<rev> | jq -r .hash
    stdlibRev  = "fb5d1840d26909038b5ae1459733b0db425a7488";
    stdlibHash = "sha256-ZF+/2bUhKggpGY0WtHqKkOstRTGe8LOhK4lD+4T3xSc=";

    mkAgdaPackages = system: pkgs:
      let
        agdaPackages = pkgs.agdaPackages.override {
          Agda = agda.packages.${system}.base;
        };
      in {
        inherit (agdaPackages) agda mkDerivation;
        standard-library = agdaPackages.standard-library.overrideAttrs (_: {
          version = "2.3-agda-2.9.0";
          src = pkgs.fetchFromGitHub {
            owner = "formalverification";
            repo = "agda-stdlib";
            rev = stdlibRev;
            hash = stdlibHash;
          };
        });
      };

    # ---- Helper: Agda env with stdlib ----------------------------------------
    # The pinned Agda wrapped with the pinned standard library.  This produces an
    # Agda binary that knows about the standard library package, but we still
    # write a project-local libraries file so users don't need ~/.agda.  The
    # list form, not `(p: [ p.standard-library ])`: the function form would
    # resolve the package set's own standard library, not the patched one.
    #
    # One more wrapper around that one unsets LD_LIBRARY_PATH.  The default
    # and all shells export one for pip wheels (exportLibPath, below) that puts
    # nixos-24.05's libstdc++ first, and Agda 2.9.0 links ICU (the build's
    # enable-cluster-counting flag), built against a newer libstdc++, so under
    # that export it does not start: "version `CXXABI_1.3.15' not found
    # (required by …/libicui18n.so.76)".  A Nix-built binary finds its
    # libraries through its RPATH, so the variable can only do it harm; the
    # same holds for an editor's environment, which runs this same `agda`.
    mkAgdaEnv = pkgs: ap:
      let agdaWithStdlib = ap.agda.withPackages [ ap.standard-library ];
      in pkgs.symlinkJoin {
        name = "agda-env-${ap.agda.version}";
        paths = [ agdaWithStdlib ];
        nativeBuildInputs = [ pkgs.makeWrapper ];
        postBuild = ''
          wrapProgram $out/bin/agda --unset LD_LIBRARY_PATH
        '';
      };

    # ---- Helper: flake-pinned agda-algebras ----------------------------------
    # Same packaging shape as the Nix stdlib: $out carries the .agda-lib, src/,
    # and prebuilt _build/2.9.0 interfaces.  The pinned agdaPackages builder's
    # default buildPhase is `agda --build-library`, which type-checks every
    # module the .agda-lib exposes.  Measured at the 2026-09-07 pin: all 407
    # committed modules interfaced, a 59 MB store path built in about 2
    # minutes cold under Agda 2.9.0 (issue #234; 85 MB and about 15 minutes
    # under nixpkgs' 2.8.0, a build with the `debug` flag, so the ratio
    # compares two binaries, not two versions).  The build's warnings are the
    # library's 951 UserWarning deprecations, as under 2.8.0, and three
    # FixityDeclarationForNonOperator, new in 2.9.0, for fixities of closed
    # operators that agda-algebras removed after this commit.  (The library's
    # Everything.agda barrel is generated and git-ignored
    # upstream, so it is absent from the flake source; the builder takes no
    # everythingFile argument, per the #132 review.)  Must use the same
    # agdaPackages set as mkAgdaEnv so the library is checked by the same
    # Agda + stdlib the shells use.
    mkAgdaAlgebrasPkg = ap: ap.mkDerivation {
      pname = "agda-algebras";
      version = "unstable-2026-09-07";
      src = agda-algebras-src;
      buildInputs = [ ap.standard-library ];
      meta = {
        description = "The Agda Universal Algebra Library, pinned at the benchmark-suite commit";
        homepage = "https://github.com/ualib/agda-algebras";
      };
    };

    # ---- Helper: the shells' Agda version guards -----------------------------
    # Warnings, not errors, as in agda-algebras: whoever moved a pin (the
    # `agda` input's URL, stdlibRev) has opted into what it brings.
    agdaVersionGuard = ap: ''
      case "${ap.agda.version}" in
        2.9.*) : ;;
        *) echo "⚠  expected Agda 2.9.x, got ${ap.agda.version}" ;;
      esac
      case "${ap.standard-library.version}" in
        2.3*) : ;;
        *) echo "⚠  expected standard-library 2.3, got ${ap.standard-library.version}" ;;
      esac
    '';

    # ---- Helper: complete Agda shell setup ------------------------------------
    # Single entry-point for all Agda configuration in any devShell.
    # Call as: ${mkAgdaShellSetup agdaPkgs.standard-library (mkAgdaAlgebrasPkg agdaPkgs)}
    #
    # What it does (in order):
    #   1. Locates the repo root via git (falls back to $PWD).
    #   2. Sets AGDA_DIR to a top-level `agda/` directory in the repo root.
    #      (Project-wide Agda config lives here, not inside any subproject.)
    #   3. Writes $AGDA_DIR/libraries with stdlib + agda-dojang paths.
    #   4. Writes $AGDA_DIR/defaults (agda-dojang, standard-library).
    #   5. Checks AGDA_ALGEBRAS_ROOT, AGDA_CATEGORIES_ROOT, and
    #      AGDA_TYPETOPOLOGY_ROOT; if set, locates the .agda-lib file in
    #      that directory and appends it to the libraries file.
    #      Both files are built in a temporary file beside them and renamed
    #      into place (the registry after step 5), so a reader never sees
    #      either half-written.
    #   6. Defines an `agda()` shell function that invokes `command agda`
    #      with --no-default-libraries, --library-file, and --library flags
    #      for every successfully registered library.
    #   7. Prints a summary showing which libraries are active vs. available.
    #
    # NOTE on shell quoting:
    #   - $AGDA_DEFAULT_LIBS is intentionally *unquoted* in the agda() function
    #     so it word-splits into separate --library arguments.
    #   - We avoid ${...} for shell variables (use $VAR instead) to prevent
    #     Nix string interpolation from eating them.
    #   - The Nix interpolation ${agdaStdlibPkg} is the one exception — it
    #     resolves to the Nix store path of the standard library at eval time.
    mkAgdaShellSetup = agdaStdlibPkg: agdaAlgebrasPkg: ''
      # ==== Locate repo root ====
      # Three candidates, most explicit first, each validated against a marker
      # that only this repository carries: agda-dojang/agda-dojang.agda-lib.
      #
      # The validation is not pedantry.  `nix develop <path>#backend` runs this
      # hook in the *caller's* working directory, so `git rev-parse` answers
      # about whatever checkout the caller happened to be standing in.  When an
      # MCP client spawned the server from another project, that used to write
      # a stray — and broken, since it names an agda-dojang that is not there —
      # agda/ directory into that project's root.  Issue #76 records the
      # sighting; docs/agda-mcp/agda-mcp-environment.md records the reproduction.
      _anair_has_marker() {
        [ -n "$1" ] && [ -f "$1/agda-dojang/agda-dojang.agda-lib" ]
      }

      ROOT=""
      _anair_git_root=""

      # 1. An explicit anchor.  scripts/run-server.sh exports this so the MCP
      #    server's Agda configuration does not depend on the client's cwd.
      #    Probed with a default expansion so an inherited `set -u` (an exported
      #    SHELLOPTS carrying `nounset`) cannot abort the hook here.  Note this
      #    does not make the hook nounset-clean on its own: earlier lines still
      #    expand LD_LIBRARY_PATH and friends unguarded, and that is where such a
      #    shell actually dies today.  This just keeps the newest line from being
      #    another one.
      if _anair_has_marker "''${AGDA_NATIVE_AIR_ROOT:-}"; then
        ROOT="''${AGDA_NATIVE_AIR_ROOT:-}"
      fi

      # 2. The enclosing git checkout, when it really is this repository.
      if command -v git >/dev/null 2>&1; then
        _anair_git_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
      fi
      if [ -z "$ROOT" ] && _anair_has_marker "$_anair_git_root"; then
        ROOT="$_anair_git_root"
      fi

      # 3. Nothing identifiable.  Keep the old behaviour so the shell still
      #    starts, but say plainly what is being written where: the libraries
      #    file below will name an agda-dojang that does not exist, and failing
      #    quietly here would only move the confusion downstream.
      if [ -z "$ROOT" ]; then
        if [ -n "$_anair_git_root" ]; then ROOT="$_anair_git_root"; else ROOT="$PWD"; fi
        echo "[agda] WARNING: this does not look like the agda-native-air checkout:"
        echo "[agda]            $ROOT"
        echo "[agda]          (no agda-dojang/agda-dojang.agda-lib beneath it)"
        echo "[agda]          Agda configuration is still being written to $ROOT/agda,"
        echo "[agda]          and it will point at an agda-dojang that is not there."
        echo "[agda]          Enter the shell from the repository, or set"
        echo "[agda]          AGDA_NATIVE_AIR_ROOT to its path."
      fi
      unset -f _anair_has_marker

      # ==== Set AGDA_DIR (project-wide Agda configuration) ====
      # Lives at the repo top level — NOT inside agda-dojang or any other
      # subproject, because this config governs all Agda work across the
      # entire repository (stdlib, agda-dojang, agda-algebras, etc.).
      export AGDA_DIR="$ROOT/agda"
      mkdir -p "$AGDA_DIR"

      # ==== Phase 1: write the base libraries file ====
      # Two always-present libraries:
      #   - agda-dojang : repo-local (source lives at $ROOT/agda-dojang)
      #   - standard-library : Nix-managed (resolved from the Nix store)
      #
      # Both files are built in a temporary file beside them and renamed into
      # place, the registry only after Phase 2 has appended every external
      # library, so a reader never sees either half-written.  Every agda-mcp
      # launch enters this shell (scripts/run-server.sh), so during an
      # agent-bench arm the registry is rewritten while other subjects' judges
      # read it; writing it in place with `cat >` and then `>>` left a window
      # with no agda-algebras in it (29,170 of 10.4 million reads over 25
      # shell entries, measured 2026-09-27).  A rename within one directory
      # is atomic, and mode 644 matches what `cat >` wrote.  A file is renamed
      # only when every write to it succeeded: this hook runs without
      # `errexit`, and a failed write (a full disk, a quota) must leave the
      # previous file standing, not publish an empty one; the staged file is
      # removed either way.  `_anair_registry_ok` stays non-empty while every
      # write to the registry has succeeded.
      _anair_registry_ok=yes
      if _anair_libraries_tmp="$(mktemp "$AGDA_DIR/.libraries.XXXXXX")" &&
         chmod 644 "$_anair_libraries_tmp" &&
         cat > "$_anair_libraries_tmp" <<EOF
    $ROOT/agda-dojang/agda-dojang.agda-lib
    ${agdaStdlibPkg}/standard-library.agda-lib
    EOF
      then :; else _anair_registry_ok=""; fi

      # Default libraries — names must match `name:` fields in the .agda-lib files.
      _anair_defaults_failed=""
      if _anair_defaults_tmp="$(mktemp "$AGDA_DIR/.defaults.XXXXXX")" &&
         chmod 644 "$_anair_defaults_tmp" &&
         cat > "$_anair_defaults_tmp" <<EOF
    agda-dojang
    standard-library
    EOF
      then
        mv -f "$_anair_defaults_tmp" "$AGDA_DIR/defaults" || _anair_defaults_failed=yes
      else
        _anair_defaults_failed=yes
      fi
      if [ -n "$_anair_defaults_failed" ]; then
        rm -f "$_anair_defaults_tmp"
        echo "[agda] WARNING: could not write $AGDA_DIR/defaults; the previous one, if any, stands"
      fi

      echo "[agda] AGDA_DIR=$AGDA_DIR"

      # ==== Phase 2: optional external Agda library registration ====
      # Set these env vars in your shell profile, .envrc, or on the command
      # line before entering the shell.  Each should point at the **root**
      # of the library checkout — the directory containing the .agda-lib file:
      #
      #   AGDA_ALGEBRAS_ROOT=~/git/ualib/agda-algebras/master    nix develop
      #   AGDA_CATEGORIES_ROOT=~/git/agda-categories             nix develop
      #   AGDA_TYPETOPOLOGY_ROOT=~/git/TypeTopology              nix develop
      #
      # The accumulator AGDA_DEFAULT_LIBS collects --library flags for all
      # registered libraries.  It starts with the two base libraries and grows
      # as external ones are successfully detected.
      AGDA_DEFAULT_LIBS="--library standard-library --library agda-dojang"

      # Track registration results for the summary.  Each is set to "yes"
      # on success inside _register_agda_lib.
      _AGDA_REG_agda_algebras=""
      _AGDA_REG_agda_categories=""
      _AGDA_REG_TypeTopology=""

      # _register_agda_lib VAR_NAME DISPLAY_NAME LIB_ROOT REG_VAR_SUFFIX
      #   Searches LIB_ROOT for a *.agda-lib file.
      #   If found, appends it to the registry being built (renamed into
      #   place as $AGDA_DIR/libraries once every library is registered) and
      #   adds a --library flag to AGDA_DEFAULT_LIBS.  Sets
      #   _AGDA_REG_<suffix>=yes on success.
      _register_agda_lib() {
        local var_name="$1"
        local display_name="$2"
        local lib_root="$3"
        local reg_suffix="$4"
        if [ -n "$lib_root" ]; then
          if [ -d "$lib_root" ]; then
            local lib_file
            lib_file="$(find "$lib_root" -maxdepth 1 -name '*.agda-lib' 2>/dev/null | head -1)"
            if [ -n "$lib_file" ]; then
              # A library is advertised (a --library flag, the summary) only
              # when its line reached the staged registry; a registry that
              # could not be written names none of them.
              if [ -n "$_anair_registry_ok" ] && echo "$lib_file" >> "$_anair_libraries_tmp"; then
                AGDA_DEFAULT_LIBS="$AGDA_DEFAULT_LIBS --library $display_name"
                eval "_AGDA_REG_$reg_suffix=yes"
                echo "[agda] registered $display_name from $lib_file"
              else
                _anair_registry_ok=""
                echo "[agda] WARNING: could not register $display_name: the registry could not be written"
              fi
            else
              echo "[agda] WARNING: $var_name is set but no .agda-lib found in $lib_root"
              echo "[agda]          (expected a *.agda-lib file in that directory)"
            fi
          else
            echo "[agda] WARNING: $var_name is set but $lib_root is not an existing directory"
            echo "[agda]          (expected the root of a library checkout containing a *.agda-lib file)"
          fi
        fi
      }

      # agda-algebras defaults to the flake-pinned store copy when no live
      # checkout is named: the pin is the SAME commit the benchmark fixtures
      # and the corpus were cut from, and the store copy ships prebuilt
      # .agdai interfaces (Cachix-cached), so CI and fresh machines pay a
      # download, not a library build.  Exporting AGDA_ALGEBRAS_ROOT before
      # entering the shell still overrides it, exactly as before.
      _AGDA_ALGEBRAS_SOURCE="live checkout"
      if [ -z "$AGDA_ALGEBRAS_ROOT" ]; then
        # If the parent exported the variable EMPTY, a plain assignment would
        # keep the export attribute and leak the store path to child `make`
        # processes after all (#132 review); unset first, so the fallback is
        # shell-local whatever the parent did.
        unset AGDA_ALGEBRAS_ROOT
        # Deliberately NOT exported (#132 review): the fallback feeds the
        # library REGISTRATION below, so type-checking sees the store pin in
        # every shell.  Child processes such as `make` do not inherit it, and
        # that is the intended boundary — the corpus/metadata lanes record git
        # provenance (commit, dirty state) that a store path cannot supply, so
        # they must be pointed at a live checkout explicitly (the Makefile's
        # AGDA_ALGEBRAS_ROOT default, docs/HowToRun.md §1.3).  Exporting the
        # user's own AGDA_ALGEBRAS_ROOT before shell entry overrides both, as
        # before.
        AGDA_ALGEBRAS_ROOT="${agdaAlgebrasPkg}"
        _AGDA_ALGEBRAS_SOURCE="flake pin"
      fi

      # Register each supported external library.
      # The env var values are double-quoted: if unset, the empty string is
      # passed and the -n test inside _register_agda_lib skips it.
      _register_agda_lib AGDA_ALGEBRAS_ROOT     agda-algebras   "$AGDA_ALGEBRAS_ROOT"     agda_algebras
      _register_agda_lib AGDA_CATEGORIES_ROOT   agda-categories "$AGDA_CATEGORIES_ROOT"   agda_categories
      _register_agda_lib AGDA_TYPETOPOLOGY_ROOT TypeTopology     "$AGDA_TYPETOPOLOGY_ROOT" TypeTopology

      # Every library is registered: move the registry into place in one step,
      # if every write to it succeeded.
      if [ -n "$_anair_registry_ok" ] && mv -f "$_anair_libraries_tmp" "$AGDA_DIR/libraries"; then
        if [ -z "$_anair_defaults_failed" ]; then
          echo "[agda] wrote $AGDA_DIR/libraries and $AGDA_DIR/defaults"
        else
          echo "[agda] wrote $AGDA_DIR/libraries ($AGDA_DIR/defaults unchanged)"
        fi
      else
        rm -f "$_anair_libraries_tmp"
        echo "[agda] WARNING: could not write $AGDA_DIR/libraries; the previous one, if any, stands"
      fi
      unset _anair_libraries_tmp _anair_defaults_tmp _anair_defaults_failed _anair_registry_ok

      # ==== Agda shell function ====
      # Override the Nix-wrapped `agda` binary.  The withPackages wrapper
      # bakes in --library-file pointing at the Nix store (stdlib only).
      # We need agda-dojang and any external libraries too, so we bypass
      # that with --no-default-libraries and supply our own --library-file
      # and --library flags.
      #
      # $AGDA_DEFAULT_LIBS is intentionally unquoted so it word-splits into
      # separate arguments (e.g., "--library standard-library --library agda-dojang").
      agda() {
        command agda --no-default-libraries \
                     --library-file "$AGDA_DIR/libraries" \
                     $AGDA_DEFAULT_LIBS \
                     "$@"
      }

      # ==== Agda library summary ====
      # Uses the _AGDA_REG_* flags to accurately reflect which libraries
      # were *successfully* registered (not just whether the env var was set).
      echo "   Agda libraries:"
      echo "     * standard-library (Nix-managed)"
      echo "     * agda-dojang (repo-local)"
      if [ -n "$_AGDA_REG_agda_algebras" ]; then
        echo "     * agda-algebras ($AGDA_ALGEBRAS_ROOT; $_AGDA_ALGEBRAS_SOURCE)"
      else
        echo "     ! agda-algebras: FAILED to register (see warning above)"
      fi
      if [ -n "$_AGDA_REG_agda_categories" ]; then
        echo "     * agda-categories ($AGDA_CATEGORIES_ROOT)"
      elif [ -n "$AGDA_CATEGORIES_ROOT" ]; then
        echo "     ! agda-categories: FAILED to register (see warning above)"
      else
        echo "     - agda-categories: set AGDA_CATEGORIES_ROOT to enable"
      fi
      if [ -n "$_AGDA_REG_TypeTopology" ]; then
        echo "     * TypeTopology ($AGDA_TYPETOPOLOGY_ROOT)"
      elif [ -n "$AGDA_TYPETOPOLOGY_ROOT" ]; then
        echo "     ! TypeTopology: FAILED to register (see warning above)"
      else
        echo "     - TypeTopology: set AGDA_TYPETOPOLOGY_ROOT to enable"
      fi
    '';

    # ---- Helper: Python env (CPU vs native CUDA) ------------------------------
    # NOTE:
    #   This env is only for interactive work *inside* nix develop.
    #   Your Makefile creates its own venv and installs wheels via pip.
    mkPythonEnv = { pkgs, cuda ? false }:
      let
        py = pkgs.python311;
        pytorchPkg = pkgs.python311Packages.pytorch.override {
          cudaSupport = cuda;
        };
      in
      py.withPackages (ps: with ps; [
        pytorchPkg
        pyarrow
        numpy
        pandas
        pytest
        pip
        virtualenv
      ]);

    # ---- Helper: runtime libs path for pip wheels -----------------------------
    # Many pip wheels need these at import-time.
    mkWheelRuntimeLibPath = pkgs: pkgs.lib.makeLibraryPath [
      pkgs.stdenv.cc.cc.lib
      pkgs.zlib
      pkgs.openssl
    ];

    # ---- Helper: the project site's Python (issue #169) -----------------------
    # MkDocs Material at the versions requirements.txt pins (mkdocs 1.6.1,
    # mkdocs-material 9.5.49, the versions williamdemeo.org pins), so the Nix
    # path and the pip path build the same site; plus pytest for the site's
    # tests.  Built from pkgsAgda (nixos-unstable) rather than pkgsStable:
    # nixos-24.05 ships mkdocs 1.5.3, and the pinned Material needs the 1.6
    # line.  nixpkgs' mkdocs-material is overridden to 9.5.49 from the PyPI
    # sdist, as williamdemeo/website's flake does; the [imaging] extra
    # (Pillow, CairoSVG) rides along so the two paths agree on it too.
    # checks.site-requirements-pins fails `nix flake check` if requirements.txt
    # and this environment ever disagree.
    mkSitePython = pkgs:
      let
        ps = pkgs.python3Packages;
        mkdocs-material = ps.mkdocs-material.overridePythonAttrs (_: rec {
          version = "9.5.49";
          src = ps.fetchPypi {
            pname = "mkdocs_material";
            inherit version;
            hash = "sha256-NnG7KCtPU6HHLgitvgTSSBqY+F/tOSUwBR+A/5SpYh0=";
          };
        });
      in
      pkgs.python3.withPackages (p:
        [ p.mkdocs mkdocs-material p.pytest ]
        ++ mkdocs-material.optional-dependencies.imaging);

  in {
    formatter = forAllSystems ({ pkgsStable, ... }: pkgsStable.nixpkgs-fmt);

    # The flake-pinned agda-algebras with prebuilt interfaces, exposed so CI
    # (and a developer warming the Cachix cache) can build it explicitly:
    #   nix build .#agda-algebras && cachix push formalverification result
    # The Agda-capable devShells depend on it via mkAgdaShellSetup, so the
    # first `nix develop` after a pin bump builds (or downloads) it too.
    #
    # The pinned Agda 2.9.0 wrapped with the pinned standard library: the very
    # `agda` the Agda-capable devShells put on PATH (agdaPinnedEnv below), so an
    # editor started outside `nix develop` can run it from an out link that is
    # also a garbage-collector root:
    #   nix build .#agda -o ~/.cache/agda-native-air/agda
    # See CONTRIBUTING.md, "Editing Agda in Emacs".
    packages = forAllSystems ({ pkgsAgda, agdaPkgs, ... }: {
      agda          = mkAgdaEnv pkgsAgda agdaPkgs;
      agda-algebras = mkAgdaAlgebrasPkg agdaPkgs;
    });

    # Roadmap-engine apps re-exported under a ghproject- prefix, so
    # `nix run .#ghproject-update -- docs/GITHUB_PROJECT.md` runs the
    # engine at the version pinned by THIS repository's flake.lock.
    apps = nixpkgs.lib.genAttrs systems (system:
      nixpkgs.lib.mapAttrs'
        (name: app: nixpkgs.lib.nameValuePair "ghproject-${name}" app)
        github-project.apps.${system});

    # requirements.txt is the supported non-Nix path for the site's toolchain
    # (issue #169); two dependency sets are only safe while they agree, so
    # this fails `nix flake check` when they do not.  `make site-pins-check`
    # inside `nix develop .#site` runs the same script.
    checks = forAllSystems ({ pkgsAgda, ... }: {
      site-requirements-pins = pkgsAgda.runCommandLocal "check-site-requirements-pins"
        { nativeBuildInputs = [ (mkSitePython pkgsAgda) ]; }
        ''
          cd ${self}
          PYTHONPATH=${self} python3 -m scripts.python.site.check_requirements_pins requirements.txt
          touch "$out"
        '';
    });

    # ---- Dev Shells -----------------------------------------------------------
    devShells = forAllSystems ({ system, pkgsStable, pkgsAgda, agdaPkgs, pkgsHaskell, ... }:
      let
        # Agda env (PINNED: the `agda` input's Agda, which mkAgdaEnv wraps)
        agdaPinnedEnv = mkAgdaEnv pkgsAgda agdaPkgs;

        # The Agda configuration every Agda-capable shell runs (stdlib +
        # agda-dojang + the flake-pinned agda-algebras), and its version guards.
        agdaShellSetup = mkAgdaShellSetup agdaPkgs.standard-library (mkAgdaAlgebrasPkg agdaPkgs);
        agdaGuard      = agdaVersionGuard agdaPkgs;

        # The backend shell's Haskell package set: Agda's own nixpkgs' GHC
        # 9.10.3, which built the Agda library agda-strux links (PINNING POLICY).
        hsPkgs = pkgsHaskell.haskell.packages.ghc910;

        # Python envs (from stable)
        pythonCPU          = mkPythonEnv { pkgs = pkgsStable; cuda = false; };
        pythonGPU_NixBuild = mkPythonEnv { pkgs = pkgsStable; cuda = true;  };  # slow initial build

        # Common CLI tools shared across all shells
        commonTools = with pkgsStable; [ git ripgrep ];

        # Runtime libs for pip wheels (torch/numpy/pandas) inside the shell
        wheelRuntimeLibPath = mkWheelRuntimeLibPath pkgsStable;

        # A small snippet we can reuse across CPU shells.
        # Prepend Nix-provided runtime libs; keep existing LD_LIBRARY_PATH only if it exists.
        exportWheelRuntimeLibs = ''
          export WHEEL_LD_LIBRARY_PATH="${wheelRuntimeLibPath}"
        '';

        exportLibPath = ''
            export LD_LIBRARY_PATH="${wheelRuntimeLibPath}:$LD_LIBRARY_PATH"
        '';

        exportJavaHome = ''
          export JAVA_HOME="${pkgsStable.jdk21}"
          export PATH="$JAVA_HOME/bin:$PATH"
          unset _JAVA_OPTIONS JAVA_TOOL_OPTIONS
        '';
      in {
        # -----------------------------------------------------------------------
        # default: CPU-only, day-to-day everything shell
        #   - uses PINNED Agda (the `agda` input, via agdaPkgs)
        #   - includes Python/PyTorch (CPU) + Scala toolchain
        #   - Agda is configured via mkAgdaShellSetup (stdlib + agda-dojang +
        #     optional external libraries)
        # -----------------------------------------------------------------------
        default = pkgsStable.mkShell {
          name = "agda-native-air";
          packages = [
            pkgsStable.jdk21
            agdaPinnedEnv
            pkgsStable.scala_2_13
            pkgsStable.sbt
            pythonCPU

            # These are crucial for pip wheels created by our Makefile venv.
            # Without this, torch/numpy often fail to import (libstdc++.so.6).
            pkgsStable.stdenv.cc.cc.lib
            pkgsStable.zlib
            pkgsStable.openssl
          ] ++ commonTools;

          LANG = "C.UTF-8";
          LC_ALL = "C.UTF-8";

          shellHook = ''
            export AGDA_NATIVE_AIR_SHELL="default"
            # Make pip wheels work inside this shell (torch/numpy/pandas).
            ${exportWheelRuntimeLibs}
            ${exportJavaHome}
            ${exportLibPath}
            echo "✅ agda-native-air (CPU dev shell)"
            echo "   Agda : $(agda --version | head -n1 || true)"
            echo "   stdlib: ${agdaPkgs.standard-library.version}"
            ${agdaGuard}
            echo "   Java : $(java -version 2>&1 | head -n1 || true)"
            echo "   sbt  : $(sbt --version 2>&1 | head -n1 || true)"
            echo "   LD_LIBRARY_PATH (head): $(echo "$LD_LIBRARY_PATH" | cut -d: -f1-3)"
            echo "   WHEEL_LD_LIBRARY_PATH: $(echo "$WHEEL_LD_LIBRARY_PATH")"
            echo "   JAVA_HOME: $(echo "$JAVA_HOME")"

            # Probe python deps, but don't crash the shell if torch isn't happy yet.
            python - <<'PY'
try:
    import torch
    torch_ok = True
except Exception as e:
    torch_ok = False
    torch_err = e

import pyarrow
print(f"   pyarrow: {pyarrow.__version__}")
if torch_ok:
    print(f"   torch: {torch.__version__}, cuda={torch.cuda.is_available()}")
else:
    print(f"   torch: IMPORT FAILED ({torch_err})")
PY

            # Configure Agda: project-local libraries, external lib registration,
            # and the agda() wrapper function.
            ${agdaShellSetup}

            echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
            echo "~ Examples (things you can try right now!)"
            echo "    make eval-proof-completion                     # Demo: end-to-end proof completion "
            echo "    make train-retrieval-smoke                     # Demo: retrieval model + evaluation "
            echo "    make eval-proof-completion-smoke-retrieval "
            echo "    make extract-lib                               # Corpus extraction (requires agda-algebras)"
            echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
            echo "~ Happy proving! 🛸 "
          '';
        };

        # -----------------------------------------------------------------------
        # backend: for custom Agda backend development (agda-strux / agda-json)
        #   - pins GHC/Cabal to the SAME universe as Agda itself: Agda's own
        #     nixpkgs (pkgsHaskell), whose GHC 9.10.3 built the `agda` input
        #   - includes Agda-as-a-library + JSON deps in ghcWithPackages; the
        #     library is the `agda` input's own (the library output of the
        #     derivation whose binary the shell runs), so agda-json and `agda`
        #     are one Agda, writing and reading one interface format
        #   - Agda is configured via mkAgdaShellSetup (same as default)
        # -----------------------------------------------------------------------
        backend = pkgsStable.mkShell {
          name = "backend";
          packages = [
            pkgsStable.jdk21
            pkgsStable.scala_2_13
            pkgsStable.sbt
            agdaPinnedEnv
            (hsPkgs.ghcWithPackages (ps: with ps; [
              agda.packages.${system}.base  # Agda 2.9.0 as a Haskell library
              aeson           # JSON encoding for exporter
              text bytestring vector unordered-containers
              filepath directory
              tasty tasty-hunit  # test deps; avoids cabal rebuilding them from Hackage
            ]))
            hsPkgs.cabal-install
            hsPkgs.haskell-language-server
            pkgsHaskell.zlib
            pkgsHaskell.gmp
            pkgsHaskell.pkg-config

            pkgsStable.stdenv.cc.cc.lib
            pkgsStable.git
            pkgsStable.ripgrep
          ];

          LANG = "C.UTF-8";
          LC_ALL = "C.UTF-8";

          shellHook = ''
            export AGDA_NATIVE_AIR_SHELL="backend"
            # No pip wheels live here, so no exportLibPath; and the variable is
            # unset rather than left as inherited, since agda-json links Agda's
            # library, hence ICU, and fails to start under the other shells'
            # export the way `agda` does (see mkAgdaEnv).  Entering this shell
            # from inside the default one must not carry that export in.
            unset LD_LIBRARY_PATH

            # Configure Agda: project-local libraries, external lib registration,
            # and the agda() wrapper function.
            ${agdaShellSetup}

            echo "🛠  backend shell — Agda + GHC/Cabal are pinned together"
            echo "   ROOT      : $ROOT"
            echo "   AGDA_DIR  : $AGDA_DIR"
            echo "   Agda      : $(agda --version | head -n1 || true)"
            echo "   stdlib    : ${agdaPkgs.standard-library.version}"
            ${agdaGuard}
            echo "   GHC       : $(ghc --version 2>/dev/null || true)"
            echo "   JAVA_HOME : $(echo "$JAVA_HOME")"
            echo "   Java      : $(java -version 2>&1 | head -n1 || true)"
            # Probed from $ROOT, not from the caller's cwd: sbt creates a
            # target/ directory wherever it is invoked, and the caller's cwd may
            # be someone else's project (issue #76).  $ROOT/target is gitignored
            # here.
            echo "   sbt       : $( (cd "$ROOT" && sbt --version) 2>&1 | head -n1 || true)"
            echo "   ---------"
            # The Agda library agda-strux links must be the binary's own version.
            echo "Agda in ghc-pkg?"
            ghc-pkg list | rg "Agda-${agdaPkgs.agda.version}" || (echo "Missing Agda ${agdaPkgs.agda.version} in GHC package DB" && exit 1)
          '';
        };


        # -----------------------------------------------------------------------
        # proofParser: minimal Scala/sbt/JDK shell (fast startup, no Agda)
        # -----------------------------------------------------------------------
        proofParser = pkgsStable.mkShell {
          packages =
            [ pkgsStable.jdk21
              pkgsStable.scala_2_13
              pkgsStable.sbt
            ] ++ commonTools;

          LANG = "C.UTF-8";
          LC_ALL = "C.UTF-8";

          shellHook = ''
            ${exportJavaHome}
            ${exportLibPath}
            echo "🧰 proof-parser shell — try: cd proof-parser && sbt test"
            echo "   JAVA_HOME : $(echo "$JAVA_HOME")"
            echo "   Java      : $(java -version 2>&1 | head -n1 || true)"
            echo "   sbt       : $(sbt --version 2>&1 | head -n1 || true)"
            echo "   ---------"
            echo "   LD_LIBRARY_PATH (head): $(echo "$LD_LIBRARY_PATH" | cut -d: -f1-3)"
          '';
        };

        # -----------------------------------------------------------------------
        # mlPipeline: Scala + Python (CPU) shell targeting ETL/tests/model
        # (no Agda — use default or backend shell for Agda work)
        # -----------------------------------------------------------------------
        mlPipeline = pkgsStable.mkShell {
          packages = [
            pkgsStable.jdk21
            pkgsStable.scala_2_13
            pkgsStable.sbt
            pythonCPU

            pkgsStable.stdenv.cc.cc.lib
            pkgsStable.zlib
            pkgsStable.openssl
          ] ++ commonTools;

          LANG = "C.UTF-8";
          LC_ALL = "C.UTF-8";

          shellHook = ''
            ${exportWheelRuntimeLibs}
            ${exportJavaHome}
            ${exportLibPath}
            echo "🧪 ml-pipeline shell — try: cd ml-pipeline && sbt -batch \"project etl\" test"
          '';
        };

        # -----------------------------------------------------------------------
        # site: MkDocs Material for the project site (issue #169), no Agda
        #   - `make site`, `make site-serve`, `make site-check`, `make site-test`
        #   - Python (with mkdocs, mkdocs-material 9.5.49, pytest) from pkgsAgda;
        #     see mkSitePython for why not pkgsStable
        #   - no LD_LIBRARY_PATH export: nothing here loads a pip wheel, and the
        #     export is what breaks the profile `nix` inside the other shells
        # -----------------------------------------------------------------------
        site = pkgsAgda.mkShell {
          name = "agda-native-air-site";
          packages = [ (mkSitePython pkgsAgda) ] ++ commonTools;

          LANG = "C.UTF-8";
          LC_ALL = "C.UTF-8";

          shellHook = ''
            echo "🌐 site shell: mkdocs $(mkdocs --version | cut -d' ' -f3); try: make site && make site-check"
          '';
        };

        # -----------------------------------------------------------------------
        # all: monolithic “everything” shell (CPU)
        #   - uses PINNED Agda (the `agda` input, via agdaPkgs)
        #   - includes Spark
        #   - Agda is configured via mkAgdaShellSetup (same as default)
        # -----------------------------------------------------------------------
        all = pkgsStable.mkShell {
          packages = [
            pkgsStable.jdk21
            pkgsStable.scala_2_13
            pkgsStable.sbt
            pkgsStable.spark
            agdaPinnedEnv
            pythonCPU

            pkgsStable.stdenv.cc.cc.lib
            pkgsStable.zlib
            pkgsStable.openssl
          ] ++ commonTools;

          LANG = "C.UTF-8";
          LC_ALL = "C.UTF-8";

          shellHook = ''
            ${exportWheelRuntimeLibs}
            ${exportJavaHome}
            ${exportLibPath}
            echo "🧩 all-in-one (CPU) — Agda + Scala + Python ready to go"

            # Configure Agda: project-local libraries, external lib registration,
            # and the agda() wrapper function.
            ${agdaShellSetup}

            echo "   ROOT      : $ROOT"
            echo "   AGDA_DIR  : $AGDA_DIR"
            echo "   Agda      : $(agda --version | head -n1 || true)"
            echo "   stdlib    : ${agdaPkgs.standard-library.version}"
            ${agdaGuard}
            echo "   JAVA_HOME : $(echo "$JAVA_HOME")"
            echo "   Java      : $(java -version 2>&1 | head -n1 || true)"
            echo "   Spark     : $(spark-submit --version 2>&1 | head -n1 || true)"
            echo "   sbt       : $(sbt --version 2>&1 | head -n1 || true)"
            echo "   ---------"
            echo "   LD_LIBRARY_PATH (head): $(echo "$LD_LIBRARY_PATH" | cut -d: -f1-3)"
            echo "   WHEEL_LD_LIBRARY_PATH: $(echo "$WHEEL_LD_LIBRARY_PATH")"
            # No GHC line and no ghc-pkg check here: this shell carries no
            # GHC, so both used to report whatever GHC the host had on PATH.
            # agda-strux's GHC and its Agda library live in the backend shell.
          '';
        };

        # -----------------------------------------------------------------------
        # gpu: Native Nix CUDA build (slow first build, but fully Nix-managed)
        #   NOTE: This shell does NOT include Agda.  It is intended for GPU
        #   model training/inference only.  Use `default` or `backend` for Agda.
        # -----------------------------------------------------------------------
        gpu =
          if pkgsStable.stdenv.isLinux then
            pkgsStable.mkShell {
              packages = [
                pkgsStable.jdk21
                pythonGPU_NixBuild
                pkgsStable.scala_2_13
                pkgsStable.sbt
                pkgsStable.stdenv.cc.cc.lib
              ] ++ commonTools;

              LANG = "C.UTF-8";
              LC_ALL = "C.UTF-8";
              PYTHONNOUSERSITE = "1";
              NIXPKGS_ALLOW_UNFREE = "1";

              shellHook = ''
                ${exportLibPath}
                echo "⚡ agda-native-air (GPU dev shell - native Nix build)"
                unset LD_PRELOAD

                if command -v nvidia-smi >/dev/null 2>&1; then
                  echo "  nvidia-smi:"; nvidia-smi | head -n 3 || true
                else
                  echo "  WARN: nvidia-smi not found — install proprietary NVIDIA driver."
                fi

                python - <<'PY'
import ctypes, sys
def have(lib):
    try:
        ctypes.CDLL(lib); return True
    except OSError:
        return False
print("  Python:", sys.version.split()[0])
print("  Driver seen by loader:", "OK" if have("libcuda.so.1") else "MISSING")
try:
    import torch
    print("  torch:", torch.__version__)
    print("  cuda available:", torch.cuda.is_available())
    if torch.cuda.is_available():
        print("  device:", torch.cuda.get_device_name(0))
except Exception as e:
    print("  torch import failed:", e)
PY
             '';
            }
          else
            pkgsStable.mkShell {
              LANG = "C.UTF-8";
              LC_ALL = "C.UTF-8";
              shellHook = ''
                ${exportLibPath}
                echo "⚠️  GPU shell not available on this platform."
                echo "    CUDA is Linux/NVIDIA-only. Use: nix develop  (CPU shell)."
              '';
            };

        # -----------------------------------------------------------------------
        # gpuWheel: leave as-is; keep existing GPU-wheels shell
        # -----------------------------------------------------------------------
      });
  };
}
