<!-- File: agda-native-air/agda-strux/README.md -->

# agda-strux

`agda-strux` is a subproject of the main `agda-native-air` project.  It
contains (the source code for building) the `agda-json` program, which is a Haskell
backend that extracts data from Agda source code (`.agda` files) and runs Agda as a
library to parse and interpret that data.  For each Agda file processed, the
program emits a **JSONL** file containing one JSON object per definition extracted
from the Agda file.

---

## Building `agda-json`

From the project root directory (often `agda-native-air/`), enter the following in the CLI:

``` sh
make build-agda-json
```

Alternatively, from inside the `agda-strux/` directory, 

```sh
cabal build all
```


---

## Running `agda-json`

To extract data from an Agda file called `Foo.agda`, enter the following from the `agda-strux/` directory:

```sh
AGDA_DIR=/path/to/agda-dojang/agda \
cabal run exe:agda-json -- \
  --input  path/to/Foo.agda \
  --output /tmp/Foo.jsonl \
  --include path/to/include/dir \
  --format full        # or: --format human / --human
```

Note that in the command above we set the `AGDA_DIR` to point to the repo's pinned
Agda config directory, but if you run the `cabal` command inside the Nix `backend`
shell (i.e., after running `nix develop .#backend`), then you shouldn't need to set
`AGDA_DIR` manually.


### Running on a Collection of Agda Files

You can also extract data from a large collection of Agda files.  For example, if
you clone the `agda-algebras` library into, say, `$(HOME)/git/ualib/agda-algebras/master`
and then run `make extract-lib-nix` from the `agda-native-air/` directory, then JSON
records for all definitions of the `agda-algebras` library are generated and
stored under `data/agda-algebras/raw/` (JSON data in `raw/jsonl/`, logs in
`raw/logs/`, etc.)

```sh
# assuming you already cloned agda-algebras
cd ~/git/agda-native-air
nix develop .#backend
make extract-lib-nix
```

Then inspect the resulting JSON data in `agda-native-air/data/agda-algebras/raw/jsonl`.

Check the Makefile for other examples.  Also, ensure the `AGDA_ALGEBRAS_ROOT` Makefile
variable points to the directory containing your clone of `agda-algebras`!

If you don't already have `agda-algebras` cloned, do the following (instead of the three
commands above):

``` sh
# NOT assuming you already cloned agda-algebras
cd                                  # change to home directory
mkdir -p git/ualib/agda-algebras
cd git/ualib/agda-algebras          # change to the new ~/git/ualib/agda-algebras directory
git clone https://github.com/ualib/agda-algebras.git master
cd  ~/git                           # change to git directory
git clone https://github.com/formalverification/agda-native-air.git
cd agda-native-air
make extract-lib-nix
```


### Output Formats

+  `--format full` (default): stable schema used by downstream tooling.
+  `--format human` / `--human`: saves only three fields per record---"name", "type",
   "body," (where "type" <-> theorem, "body" <-> proof); this makes the data much
   more readable and comprehensible to humans, mainly for debugging.

---

## Testing `agda-json`

From the project root directory (e.g., `agda-native-air/`), enter the following on the CLI:

```sh
make backend-test
```

Alternatively, from inside the `agda-strux/` directory,

```sh
cabal test
```

---

## Other Notes

+  Tests set `AGDA_DIR` to avoid relying on `~/.config/agda`.
+  Some tests intentionally allow empty JSONL outputs for "barrel modules"
   (i.e., container modules that merely list other modules).


---

## See Also

+ [Root project README][]
+ [`agda-dojang/README.md`][agda-dojang/README]
+ [`ml-pipeline/README.md`][ml-pipeline/README]
+ [`strux-driver/README.md`][strux-driver/README]

[Root project README]: https://github.com/formalverification/agda-native-air/blob/main/README.md
[strux-driver/README]: https://github.com/formalverification/agda-native-air/blob/main/strux-driver/README.md
[agda-dojang/README]: https://github.com/formalverification/agda-native-air/blob/main/agda-dojang/README.md
[ml-pipeline/README]: https://github.com/formalverification/agda-native-air/blob/main/ml-pipeline/README.md


