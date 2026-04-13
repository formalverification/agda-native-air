# =============================================================================
# agda-native-air — Flake (Dev Shells for Agda, Scala/sbt/JDK, Python + PyTorch)
#
# Goals:
#   1) One command dev env: `nix develop`. Batteries included.
#   2) CPU-first by default (portable), GPU opt-in (Linux/NVIDIA).
#   3) Agda works out-of-the-box with stdlib registered *project-locally*.
#   4) Keep things explicit & well-commented for future edits.
#
# IMPORTANT NOTE ABOUT PYTHON WHEELS ON NIX
#   Many pip wheels (torch, numpy, pandas, etc.) are built for "normal Linux"
#   layouts where runtime libs (libstdc++.so.6, libgcc_s.so.1, zlib, openssl…)
#   are in /usr/lib. Inside a Nix shell they are NOT visible unless we provide
#   them. If we don’t, imports fail with “cannot open shared object file…”.
#
#   Therefore, in the CPU shells below we:
#     • include pkgsStable.stdenv.cc.cc.lib in packages
#     • export LD_LIBRARY_PATH to point at those runtime libs
#
# This is scoped to the devShell, not global on your machine.
#
# Pinning policy (important):
#   - nixpkgs        : general toolchain (Scala/sbt/JDK/Python/etc.)
#   - nixpkgs-agda   : *dedicated* pin for Agda + stdlib (and backend dev tooling)
#
# Why a dedicated Agda pin?
#   Backend work is sensitive to Agda version and its Haskell dependency graph.
#   Keeping Agda on its own pin avoids breakage when you update general tooling.
#
# Updating pins (regenerates flake.lock):
#   nix flake lock --update-input nixpkgs
#   nix flake lock --update-input nixpkgs-agda
#
# Checking Agda version:
#   nix develop -c agda --version
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

  outputs = { self, nixpkgs, nixpkgs-agda }:
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

    # ---- Helper: write a project-local libraries file for Agda ----------------
    mkAgdaLibrariesFile = agdaStdlibPkg: ''
      ROOT="$PWD"
      if command -v git >/dev/null 2>&1; then
        if git rev-parse --show-toplevel >/dev/null 2>&1; then
          ROOT="$(git rev-parse --show-toplevel)"
        fi
      fi

      export AGDA_DIR="$ROOT/agda-dojang/agda"
      mkdir -p "$AGDA_DIR"

      cat > "$AGDA_DIR/libraries" <<EOF
    $ROOT/agda-dojang/agda-dojang.agda-lib
    ${agdaStdlibPkg}/standard-library.agda-lib
    EOF

      # IMPORTANT: choose which libraries are active by default.
      # These names must match the `name:` fields inside the .agda-lib files.
      cat > "$AGDA_DIR/defaults" <<EOF
    agda-dojang
    standard-library
    EOF

      echo "[agda] AGDA_DIR=$AGDA_DIR"
      echo "[agda] wrote $AGDA_DIR/libraries and $AGDA_DIR/defaults"
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

    # ---- Dev Shells -----------------------------------------------------------
    devShells = forAllSystems ({ pkgsStable, pkgsAgda, ... }:
      let
        # Agda env (PINNED via pkgsAgda)
        agdaPinnedEnv = mkAgdaEnv pkgsAgda;

        # Python envs (from stable)
        pythonCPU          = mkPythonEnv { pkgs = pkgsStable; cuda = false; };
        pythonGPU_NixBuild = mkPythonEnv { pkgs = pkgsStable; cuda = true;  };  # slow initial build

        # Common CLI tools
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
        #   - uses PINNED Agda
        #   - keeps our Python/PyTorch + Scala toolchain intact
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

            ${mkAgdaLibrariesFile pkgsAgda.agdaPackages.standard-library}

            # Override Agda to use repo-local library config.
            # The withPackages wrapper bakes in --library-file pointing at the
            # Nix store (stdlib only).  We need agda-dojang too.
            agda() {
              command agda --no-default-libraries \
                           --library-file "$AGDA_DIR/libraries" \
                           --library standard-library \
                           --library agda-dojang \
                           "$@"
            }
            export -f agda

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
        # backend: for custom Agda backend development
        #   - pins GHC/Cabal to the SAME pkgsAgda universe as Agda itself
        # -----------------------------------------------------------------------
        backend = pkgsStable.mkShell {
          name = "backend";
          packages = [
            pkgsStable.jdk21
            pkgsStable.scala_2_13
            pkgsStable.sbt
            agdaPinnedEnv

            #pkgsAgda.haskellPackages.ghc
            (pkgsAgda.haskellPackages.ghcWithPackages (ps: with ps; [
              Agda            # Agda as a Haskell library
              aeson           # JSON encoding for your exporter
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
            # ---------------------------------------------------------------------------
            # Ensure AGDA_DIR points at the repo-local Agda config, even from subdirs.
            # Prefer git to locate the repo root; fall back to current dir.
            # ---------------------------------------------------------------------------
            ROOT="$(
              git rev-parse --show-toplevel 2>/dev/null || pwd
            )"

            export AGDA_DIR="$ROOT/agda-dojang/agda"

            # If the repo structure ever differs, fail loudly:
            if [ ! -d "$AGDA_DIR" ]; then
              echo "ERROR: AGDA_DIR does not exist: $AGDA_DIR"
              echo "       (computed ROOT=$ROOT)"
              exit 1
            fi

            # Write repo-local libraries file at $AGDA_DIR/libraries (NOT ~/.config/agda)
            ${mkAgdaLibrariesFile pkgsAgda.agdaPackages.standard-library}
            ${exportLibPath}

            # Override Agda to use repo-local library config.
            # The withPackages wrapper bakes in --library-file pointing at the
            # Nix store (stdlib only).  We need agda-dojang too.
            agda() {
              command agda --no-default-libraries \
                           --library-file "$AGDA_DIR/libraries" \
                           --library standard-library \
                           --library agda-dojang \
                           "$@"
            }
            export -f agda

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
        # proofParser: minimal Scala/sbt/JDK shell (fast startup)
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
            echo "   ROOT      : $ROOT"
            echo "   JAVA_HOME : $(echo "$JAVA_HOME")"
            echo "   Java      : $(java -version 2>&1 | head -n1 || true)"
            echo "   sbt       : $(sbt --version 2>&1 | head -n1 || true)"
            echo "   ---------"
            echo "   LD_LIBRARY_PATH (head): $(echo "$LD_LIBRARY_PATH" | cut -d: -f1-3)"
          '';
        };

        # -----------------------------------------------------------------------
        # mlPipeline: Scala + Python (CPU) shell targeting ETL/tests/model
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
        #   - also uses PINNED Agda
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
            ${mkAgdaLibrariesFile pkgsAgda.agdaPackages.standard-library}

            # Override Agda to use repo-local library config.
            # The withPackages wrapper bakes in --library-file pointing at the
            # Nix store (stdlib only).  We need agda-dojang too.
            agda() {
              command agda --no-default-libraries \
                           --library-file "$AGDA_DIR/libraries" \
                           --library standard-library \
                           --library agda-dojang \
                           "$@"
            }
            export -f agda

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
                ${mkAgdaLibrariesFile pkgsAgda.agdaPackages.standard-library}
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
