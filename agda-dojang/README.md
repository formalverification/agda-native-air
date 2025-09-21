<!-- agda-ai-prover/agda-jang/README.md -->

# AgdaJang: AI-Assisted Proof Dojo

**AgdaJang** is the interactive proving component of `agda-ai-prover`.  
It provides a small, safe tactic vocabulary inside Agda and Python tooling to probe, test, and search proof strategies.

---

## ✨ Features

-  **Agda Macros (TC monad tactics)**

   - `refine⟨_⟩`: insert a candidate term
   - `apply⟨_⟩`: apply a function/lemma and generate subgoals
   - `applyWith⟨_,_⟩`: apply with explicit arguments
   - `applyReport⟨_⟩` / `applySolveReport⟨_⟩`: structured reporting of subgoals
   - `intro`: introduce a λ when the goal is a function type

-  **Python Tools**

   - [`jang_try.py`](python/tools/jang_try.py): generate scratch Agda modules, run candidates or tactics, parse subgoals.
   - [`search.py`](python/tools/search.py): a simple BFS/beam search over tactics and candidates.

-  **Makefile Shortcuts:**

   -  `make check` → type-checks all Agda macros

   -  `make demo1` → runs `jang_try.py` with `suc zero : Nat`

      expected output: `[OK] suc zero`

   -  `make demo2` → runs `jang_try.py` with `applyReport:_+_`

       expected output:  
       ```
       [OK] tactic applyReport:_+_
       Subgoals:
         - AGDAJANG_GOAL:0:visible: Nat
         - AGDAJANG_GOAL:1:visible: Nat
      ```


---

## ⚡ Quickstart with Nix (recommended)

We provide a `flake.nix` at the repo root. This pins **Agda + stdlib + Python + Scala**.

### 1. Enter the shell

```bash
cd agda-ai-prover
nix develop
```

If this runs to successful completion, it will provide

+ `agda` with the stdlib registered,
+ `python3` (with venv support),
+ `scala`, `sbt`, `jdk`.


### 2. Run AgdaJang demos

```bash
cd agda-jang
make check    # Type-check Agda macros
make demo1    # OK: suc zero : Nat
make demo2    # Subgoal report for _+_
```

### 3. Library file

AgdaJang ships with an `agda-jang.agda-lib` file containing the following:

```text
name: agda-jang
include: agda
depend: standard-library
```

This ensures `-l agda-jang` makes our macros available in any Agda file.

---

## 🧱 Project Layout

```
agda-jang/
├── agda/
│   └── AgdaJang/       # Prelude, Refine, Apply, Debug, Everything
├── python/tools/       # jang_try.py, search.py, helpers
├── Makefile            # check + demos
└── README.md           # (this file)
```

---

## 🛠️ Without Nix

* Install Agda (≥ 2.6.4) and [agda-stdlib](https://github.com/agda/agda-stdlib).
* Ensure `agda` is on PATH and stdlib is registered.
* Install Python 3.10+.
* Run the same Make targets as above.

---

## 🚀 Next Steps

* Add more tactics (`rewrite`, smarter `introN`).
* JSON logging for subgoal traces (dataset prep).
* Integration with trained LLM policies.
