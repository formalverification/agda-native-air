# =============================================================================
# agda-native-air — Flake (Dev Shells for Agda, Scala/sbt/JDK, Python + PyTorch)
#
# File: flake.nix
#
# GOALS
#
#   1) One command dev env: `nix develop`. Batteries included.
#   2) CPU-first by default (portable), GPU opt-in (Linux/NVIDIA).
#   3) Agda works out-of-the-box with stdlib + agda-dojang registered
#      *project-locally* (no ~/.agda needed).
#   4) Optional external Agda libraries (agda-algebras, agda-categories,
#      TypeTopology) via environment variables — no flake edits required.
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
#     If the `.agda-lib` file is found, the library is registered and the
#     agda() wrapper passes `--library <name>` automatically.
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
#   - nixpkgs-agda   : *dedicated* pin for Agda + stdlib (and backend dev tooling)
#
#   Why a dedicated Agda pin:
#     Backend work is sensitive to Agda version and its Haskell dependency graph.
#     Keeping Agda on its own pin avoids breakage when updating general tooling.
#
#   Updating pins (regenerates flake.lock):
#     nix flake lock --update-input nixpkgs
#     nix flake lock --update-input nixpkgs-agda
#
#
# AVAILABLE SHELLS
#
#   nix develop            — default: CPU, Agda + Scala + Python (day-to-day)
#   nix develop .#backend  — Agda backend dev: GHC/Cabal pinned to pkgsAgda
#   nix develop .#all      — monolithic: everything including Spark
#   nix develop .#proofParser — minimal Scala/sbt/JDK
#   nix develop .#mlPipeline  — Scala + Python (CPU), no Agda
#   nix develop .#gpu      — native Nix CUDA build (Linux only, slow first build)
# =============================================================================
{
  description = "agda-native-air: reproducible dev shells for AgdaDojang + Python/Scala (+ optional GPU)";

  # ---- Inputs ---------------------------------------------------------------
  # Keep general tools on stable.
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";

  # Pin Agda separately (start on unstable; lock file makes it exact/reproducible).
  # If you later want to pin to a specific nixpkgs revision with Agda 2.8.0,
  # you can override nixpkgs-agda in flake.lock (see commands below).
  inputs.nixpkgs-agda.url = "github:NixOS/nixpkgs/nixos-unstable";

  # The github-project roadmap engine (docs/GITHUB_PROJECT.md tooling),
  # pinned here in flake.lock; upgrade deliberately with
  # `nix flake update github-project`.  See the Makefile's project-*
  # targets and issue #92.
  inputs.github-project.url = "github:williamdemeo/github-project";

  outputs = { self, nixpkgs, nixpkgs-agda, github-project }:
  let
    systems = [ "x86_64-linux" "aarch64-darwin" "x86_64-darwin" ];

    # Provide pkgsStable + pkgsAgda for each system.
    # Make an attrset { system => f { pkgsStable, pkgsUnstable } }
    forAllSystems = f:
      nixpkgs.lib.genAttrs systems (system:
        f {
          pkgsStable = import nixpkgs {
            inherit system;
            config = { allowUnfree = true; };
          };
          pkgsAgda = import nixpkgs-agda {
            inherit system;
            config = { allowUnfree = true; };
          };
        });

    # ---- Helper: Agda env with stdlib ----------------------------------------
    # Important: Agda + stdlib must come from the SAME nixpkgs pin (pkgsAgda).
    # This produces an Agda binary that knows about the standard library package,
    # but we still write a project-local libraries file so users don't need ~/.agda.
    mkAgdaEnv = pkgs: pkgs.agda.withPackages (p: [ p.standard-library ]);

    # ---- Helper: complete Agda shell setup ------------------------------------
    # Single entry-point for all Agda configuration in any devShell.
    # Call as: ${mkAgdaShellSetup pkgsAgda.agdaPackages.standard-library}
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
    mkAgdaShellSetup = agdaStdlibPkg: ''
      # ==== Locate repo root ====
      # Fall back to $PWD if not in a git repo.

      ROOT="$PWD"
      if command -v git >/dev/null 2>&1; then
        if git rev-parse --show-toplevel >/dev/null 2>&1; then
          ROOT="$(git rev-parse --show-toplevel)"
        fi
      fi

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
      cat > "$AGDA_DIR/libraries" <<EOF
    $ROOT/agda-dojang/agda-dojang.agda-lib
    ${agdaStdlibPkg}/standard-library.agda-lib
    EOF

      # Default libraries — names must match `name:` fields in the .agda-lib files.
      cat > "$AGDA_DIR/defaults" <<EOF
    agda-dojang
    standard-library
    EOF

      echo "[agda] AGDA_DIR=$AGDA_DIR"
      echo "[agda] wrote $AGDA_DIR/libraries and $AGDA_DIR/defaults"

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
      #   If found, appends it to $AGDA_DIR/libraries and adds a --library
      #   flag to AGDA_DEFAULT_LIBS.  Sets _AGDA_REG_<suffix>=yes on success.
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
              echo "$lib_file" >> "$AGDA_DIR/libraries"
              AGDA_DEFAULT_LIBS="$AGDA_DEFAULT_LIBS --library $display_name"
              eval "_AGDA_REG_$reg_suffix=yes"
              echo "[agda] registered $display_name from $lib_file"
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

      # Register each supported external library.
      # The env var values are double-quoted: if unset, the empty string is
      # passed and the -n test inside _register_agda_lib skips it.
      _register_agda_lib AGDA_ALGEBRAS_ROOT     agda-algebras   "$AGDA_ALGEBRAS_ROOT"     agda_algebras
      _register_agda_lib AGDA_CATEGORIES_ROOT   agda-categories "$AGDA_CATEGORIES_ROOT"   agda_categories
      _register_agda_lib AGDA_TYPETOPOLOGY_ROOT TypeTopology     "$AGDA_TYPETOPOLOGY_ROOT" TypeTopology

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
        echo "     * agda-algebras ($AGDA_ALGEBRAS_ROOT)"
      elif [ -n "$AGDA_ALGEBRAS_ROOT" ]; then
        echo "     ! agda-algebras: FAILED to register (see warning above)"
      else
        echo "     - agda-algebras: set AGDA_ALGEBRAS_ROOT to enable"
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

  in {
    formatter = forAllSystems ({ pkgsStable, ... }: pkgsStable.nixpkgs-fmt);

    # Roadmap-engine apps re-exported under a ghproject- prefix, so
    # `nix run .#ghproject-update -- docs/GITHUB_PROJECT.md` runs the
    # engine at the version pinned by THIS repository's flake.lock.
    apps = nixpkgs.lib.genAttrs systems (system:
      nixpkgs.lib.mapAttrs'
        (name: app: nixpkgs.lib.nameValuePair "ghproject-${name}" app)
        github-project.apps.${system});

    # ---- Dev Shells -----------------------------------------------------------
    devShells = forAllSystems ({ pkgsStable, pkgsAgda, ... }:
      let
        # Agda env (PINNED via pkgsAgda)
        agdaPinnedEnv = mkAgdaEnv pkgsAgda;

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
        #   - uses PINNED Agda (from pkgsAgda)
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
            ${mkAgdaShellSetup pkgsAgda.agdaPackages.standard-library}

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
        #   - pins GHC/Cabal to the SAME pkgsAgda universe as Agda itself
        #   - includes Agda-as-a-library + JSON deps in ghcWithPackages
        #   - Agda is configured via mkAgdaShellSetup (same as default)
        # -----------------------------------------------------------------------
        backend = pkgsStable.mkShell {
          name = "backend";
          packages = [
            pkgsStable.jdk21
            pkgsStable.scala_2_13
            pkgsStable.sbt
            agdaPinnedEnv
            (pkgsAgda.haskellPackages.ghcWithPackages (ps: with ps; [
              Agda            # Agda as a Haskell library
              aeson           # JSON encoding for exporter
              text bytestring vector unordered-containers
              filepath directory
              tasty tasty-hunit  # test deps — avoids cabal rebuilding from Hackage
            ]))
            pkgsAgda.haskellPackages.cabal-install
            pkgsAgda.haskellPackages.haskell-language-server
            pkgsAgda.zlib
            pkgsAgda.gmp
            pkgsAgda.pkg-config

            pkgsStable.stdenv.cc.cc.lib
            pkgsStable.git
            pkgsStable.ripgrep
          ];

          LANG = "C.UTF-8";
          LC_ALL = "C.UTF-8";

          shellHook = ''
            export AGDA_NATIVE_AIR_SHELL="backend"
            ${exportLibPath}

            # Configure Agda: project-local libraries, external lib registration,
            # and the agda() wrapper function.
            ${mkAgdaShellSetup pkgsAgda.agdaPackages.standard-library}

            echo "🛠  backend shell — Agda + GHC/Cabal are pinned together"
            echo "   ROOT      : $ROOT"
            echo "   AGDA_DIR  : $AGDA_DIR"
            echo "   Agda      : $(agda --version | head -n1 || true)"
            echo "   GHC       : $(ghc --version 2>/dev/null || true)"
            echo "   JAVA_HOME : $(echo "$JAVA_HOME")"
            echo "   Java      : $(java -version 2>&1 | head -n1 || true)"
            echo "   sbt       : $(sbt --version 2>&1 | head -n1 || true)"
            echo "   ---------"
            echo "   LD_LIBRARY_PATH (head): $(echo "$LD_LIBRARY_PATH" | cut -d: -f1-3)"
            echo "   WHEEL_LD_LIBRARY_PATH: $(echo "$WHEEL_LD_LIBRARY_PATH")"
            echo "Agda in ghc-pkg?"
            ghc-pkg list | rg "Agda-2\.8\.0" || (echo "Missing Agda in GHC package DB" && exit 1)
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
        # all: monolithic “everything” shell (CPU)
        #   - uses PINNED Agda (from pkgsAgda)
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
            ${mkAgdaShellSetup pkgsAgda.agdaPackages.standard-library}

            echo "   ROOT      : $ROOT"
            echo "   AGDA_DIR  : $AGDA_DIR"
            echo "   Agda      : $(agda --version | head -n1 || true)"
            echo "   GHC       : $(ghc --version 2>/dev/null || true)"
            echo "   JAVA_HOME : $(echo "$JAVA_HOME")"
            echo "   Java      : $(java -version 2>&1 | head -n1 || true)"
            echo "   Spark     : $(spark-submit --version 2>&1 | head -n1 || true)"
            echo "   sbt       : $(sbt --version 2>&1 | head -n1 || true)"
            echo "   ---------"
            echo "   LD_LIBRARY_PATH (head): $(echo "$LD_LIBRARY_PATH" | cut -d: -f1-3)"
            echo "   WHEEL_LD_LIBRARY_PATH: $(echo "$WHEEL_LD_LIBRARY_PATH")"
            echo "Agda in ghc-pkg?"
            ghc-pkg list | rg "Agda-2\.8\.0" || (echo "Missing Agda in GHC package DB" && exit 1)
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
