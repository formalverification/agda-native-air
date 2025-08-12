# Metaprogramming & the TC monad in Agda: a practical intro

## Big picture

+  **Reflection** exposes Agda's syntax trees at the term/type level
   (`Agda.Builtin.Reflection`), where we see `Term`, `Name`, `Type`, `Sort`, etc.,
   and constructors like `def`, `con`, `lam`, `pi`, `var`, `meta`, `lit`.

+  **Macros** are functions that run *at type-check time* in the `TC` monad and can
   *inspect* the goal, *check* candidate terms, and even *solve* goals; macros are
   defined with the `macro` keyword; the final argument to a macro is the *goal (hole)*.

+  **The TC monad** is Agda's "type-checker effects" API: things like `inferType`,
   `checkType`, `unify`, `normalise/reduce/whnf`, `freshName`, `declarePostulate`,
   `defineFun`, `typeError`, etc; think of it as "trusted tactics," except the output
   must pass Agda's checker.

## Core TC operations (used 90% of the time)

+  `inferType t : TC Term` returns the (reflected) type of `t`

+  `checkType t A : TC Term` elaborates `t` against expected type `A`
   (filling implicits, etc); fails if it doesn't typecheck

+  `unify goal t : TC ⊤` solves the current meta/goal with `t` (if types agree)

+  `reduce/normalise/whnf t : TC Term` compute forms of `t`
   (from δ/β/ι/η unfolding; `whnf` is the mildest)

+  `typeError parts : TC α` abort with a structured message; useful for debugging

+  `catchTC m k : TC α` try/catch in TC; handy to probe "would this typecheck?"

There are many more, but these get us very far.

## Examples

1.  **"Refine" macro**.  Accept a candidate and fill the hole.

    ```agda
    module AgdaJang.Refine where
    open import Agda.Builtin.Unit using (⊤; tt)
    open import Agda.Builtin.Reflection

    macro
      refine⟨_⟩ : Term → Term → TC ⊤
      refine⟨ cand ⟩ hole = do
        goalTy ← inferType hole
        _      ← checkType cand goalTy
        unify hole cand
        return tt
    ```

    **Usage**.

    ```agda
    open import Agda.Builtin.Nat
    open import AgdaJang.Refine

    ex₁ : Nat
    ex₁ = refine⟨ zero ⟩   -- fills the goal with `zero`
    ```

2.  **"Try" macro**.  Test a candidate *without* solving.

    ```agda
    module AgdaJang.Try where
    open import Agda.Builtin.Unit using (⊤)
    open import Agda.Builtin.Reflection

    macro
      try⟨_⟩ : Term → Term → TC ⊤
      try⟨ cand ⟩ hole =
        catchTC
          (do goalTy ← inferType hole
              _      ← checkType cand goalTy
              typeError (strErr "AGDAJANG_TRY:OK" ∷ []))
          (λ _ → typeError (strErr "AGDAJANG_TRY:FAIL" ∷ []))
    ```

    **Usage**.

    Put `try⟨ candidate ⟩` in a goal; Agda will emit `AGDAJANG_TRY:OK` or `…FAIL` and
    our CLI will parse that.


3.  **Debugging macros**. Print the goal type or a `Name`.

    ```agda
    module AgdaJang.Debug where
    open import Agda.Builtin.Reflection

    macro
      showGoalType : Term → TC ⊤
      showGoalType hole = do
        ty ← inferType hole
        typeError (strErr "GOAL TYPE: " ∷ termErr ty ∷ [])
    ```

    Drop `showGoalType` in a hole to inspect the elaborated type Agda sees there.


4.  **Normalization matters**

    Often `checkType` succeeds only after unfolding, so we may want to pre-normalize
    the goal.

    ```agda
        goalTy₀ ← inferType hole
        goalTy  ← whnf goalTy₀    -- or normalise/reduce
        _       ← checkType cand goalTy
    ```

5.  **"Apply lemma" (outline)**

    An "apply" macro builds an application term (e.g., `f _ _ x`) with fresh metas
    for the implicit arguments, checks it against the goal, unifies, and leaves
    subgoals for remaining metas.  The exact helper to create fresh metas is
    version-sensitive, so we'll implement this in the repo with a tiny compatibility
    layer, but conceptually:

    +  Given a Name `f`, build a Term `def f args`
    +  For implicit args, insert fresh metas; for explicit args pass user-supplied terms
    + `checkType` the application against the goal type (possibly after `whnf`)
    + `unify hole app`

    This is the basis for an Agda "tactic" that chains lemmas.

## Common gotchas

+  **Contexts/implicits**.

   Agda inserts implicits during `checkType`. If we compare raw `Term`s directly
   we hit metas, so we use `checkType`+`unify`.

+  **Normalization**.  Many goals only line up after `whnf/normalise`.

+  **Effects vs. terms**.  TC code runs at elaboration, so we keep macros small and
   deterministic; we use `typeError` to "log".

+  **Ports**.  Reflection APIs evolve slightly across Agda versions, so we keep a
   thin wrapper module for version shims.


---

## Deeper Dive: the TC monad

### Mathematical view (category-theoretic "monad")

A monad on a category `C` (here, think Sets/Types) is an endofunctor `T : C → C` with two natural transformations:

+  **unit** `η : Id ⇒ T` (here: `returnTC`)

+  **bind/multiplication** `μ : T ∘ T ⇒ T` (here it's the *Kleisli arrow*, denoted `_>>=_`)
   satisfying the three monad laws (left identity, right identity, associativity).

For the `TC` functor,

+  objects are Agda types (`A : Set a`);
+  the functor maps `A` to `TC A`;
+  the unit is `returnTC : A → TC A`;
+  the Kleisli arrow is `_>>=_ : TC A → (A → TC B) → TC B`.

Agda does **not** (and cannot) *prove* the laws for `TC` inside Agda, because `TC`
exposes effects of the type checker (state, failures, meta-variable solving,
normalization). But `TC` is designed to behave monadically: you treat it like any
other monad and it sequences type-checking effects.

### Type-level view (the actual types you use)

From `Agda.Builtin.Reflection` (conceptually):

```agda
TC       : (A : Set a) → Set a        -- effectful computation yielding an A
returnTC : ∀ {A} → A → TC A
bindTC   : ∀ {A B} → TC A → (A → TC B) → TC B  -- written as _>>=_
catchTC  : ∀ {A} → TC A → (Error → TC A) → TC A

inferType : Term → TC Term
checkType : Term → Term → TC Term
unify     : Term → Term → TC ⊤
normalise : Term → TC Term
whnf      : Term → TC Term
-- ... many more
```

**Programmatic meaning:** `TC A` is "a computation that asks the type checker to do
things, and (if successful) produces an `A`." You sequence those computations with
`do`/`>>=`.

**Desugaring reminder:**
`do x ← m ; y ← n x ; k y` ≡ `m >>= λ x → n x >>= λ y → k y`.

### Tiny, real examples

1.  Check a candidate against the goal and solve.

    ```agda
    macro refine⟨_⟩ : Term → Term → TC ⊤
    refine⟨ cand ⟩ hole = do
      A ← inferType hole
      _ ← checkType cand A
      unify hole cand
      return tt
    ```

2.  Probe success without solving (using exceptions).

    ```agda
    macro try⟨_⟩ : Term → Term → TC ⊤
    try⟨ cand ⟩ hole =
      catchTC
        (do A ← inferType hole
            _ ← checkType cand A
            typeError (strErr "AGDAJANG_TRY:OK" ∷ []))
        (λ _ → typeError (strErr "AGDAJANG_TRY:FAIL" ∷ []))
    ```

3.  Normalizing before checking (often necessary).

    ```agda
    A₀ ← inferType hole
    A  ← whnf A₀
    _  ← checkType cand A
    ```

---

## What is `whnf`

*  **Normal form (NF)**.

   Fully normalize (β/δ/ι/η) *everywhere*: reduce under lambdas, across arguments,
   unfold definitions as needed, normalize subterms recursively.

*  **Weak Head Normal Form (WHNF)**.

   Reduce **just enough** to expose the *head* of the term:

   + β-reduce a head application `(\x → t) u  →  t[u/x]`;
   + unfold the head definition one step if needed;
   + compute record projections at the head, etc.;
   + **do not** normalize inside arguments or under lambdas recursively.

**Intuition**. `whnf` is **fast** and preserves the outer shape; it's usually what
you want before `checkType`/`unify` to avoid over-normalizing big terms.

### Micro-demo macros (handy while learning)

```agda
module AgdaJang.Debug where
open import AgdaJang.Compat
open import Agda.Builtin.List using (_∷_; [])

macro
  showTypeNFvsWHNF : Term → TC ⊤
  showTypeNFvsWHNF hole = do
    A   ← inferType hole
    A'  ← whnf A
    A'' ← normalise A
    typeError
      ( strErr "TYPE:  " ∷ termErr A
      ∷ strErr "\nWHNF: " ∷ termErr A'
      ∷ strErr "\nNF:   " ∷ termErr A''
      ∷ [] )
```

Drop `showTypeNFvsWHNF` in a goal to see the difference.

Examples you'll notice:

+ `(λ n → suc n) 3`
  *WHNF* → `suc 3` (doesn't expand `3`),
  *NF*   → `suc (suc (suc zero))`.

+ `fst (x , y)`
  *WHNF* reduces to `x` (projection at the head),
  arguments remain otherwise untouched.

