# AGENTS.md

Working notes for an agent in this repo, which holds `ova_fmt`, an
Oberon-2 program compiled with poc, the Peaseblossom Oberon Compiler.
It reads YAML files describing OVA characters and writes them as terse
reST, gemtext, Markdown, reST with HTML or groff `hd` tables, an
h-m-m outline, the inline format (`-i`, `OvaInline`: a Markdown
paragraph per entity; PLAN.md, "The inline format"), or the official
character sheet's form fields as JSON (`-X`, `OvaSheetMap` and
`OvaForm`), which `ova_form.sh` fills the sheet's PDF with, or troff
to typeset over that sheet (`-S`, with `-P` for the portrait;
`OvaSheet`, measuring with `OvaSheetFonts` and the generated
`OvaSheetWidths`), which `ova_sheet.sh` lays over it (PLAN.md, "The
official character sheet as PDF"). With `-R` (`OvaSheetDraw`), that
troff draws the sheet's frames itself, and needs no sheet under it
(PLAN.md, "Redrawing the sheet"); with `-C` as well, page 1 is one
column beside an Attacks & Combat Stats box, as the rulebook's NPCs
are (PLAN.md, "One column").

It is a port of the Ada `ova_fmt` (`~/Repos/RPG/Tools/ova_fmt`); see
PLAN.md for the port, and the Ada repo's `PLAN.md` for the design of
the program itself. Its layout and conventions are pobesm2_fmt2's
(`~/Repos/RPG/Tools/pobesm2_fmt2`), the poc port of besm2_fmt, whose
`AGENTS.md` has more on ropes and poc. This file is operational notes,
not a design doc. A change to the Ada program belongs here too.

## Reference material

| What | Where |
|---|---|
| Ada program | `~/Repos/RPG/Tools/ova_fmt/` (`src/`, `PLAN.md`, `test-data/`) |
| Ada binary (the oracle for `make golden`) | `~/Repos/RPG/Tools/ova_fmt/ova_fmt` (`gprbuild -p -P ova_fmt.gpr` there) |
| The sibling poc port this one follows | `~/Repos/RPG/Tools/pobesm2_fmt2/` |
| Ropes | `~/Repos/Oberon/Ropes/`; poc library `ropes` in `$POCLIBDIR` |
| ArgParser (command-line parsing) | `~/Repos/Oberon/ArgParser/`; poc library `argparser` in `$POCLIBDIR` (default `~/.local/lib/poc`) |
| polibfyaml (YAML) | `~/Repos/Oberon/polibfyaml/` (`AGENTS.md`, `src/`, `test/poc-gc.supp`, `test/vg-reachable.sh`); poc library `polibfyaml` in `$POCLIBDIR` |
| poc | installed from the Peaseblossom RPM: `/usr/bin/poc`, its runtime library `poc-rtl` under `/usr/lib/poc` |
| poc source and runtime | `~/Repos/Oberon/Peaseblossom` (`doc/users-guide.md`, `doc/reference-guide.md`, `AGENTS.md`; the runtime in `rtl/llvm/`) |

Read the Ropes, polibfyaml and ArgParser `AGENTS.md` files before
working around any of those libraries.

## Build / test

```sh
make            # obj/ (poc output) and ./ova_fmt_po
make test       # unit tests, test/cli.sh, test/golden.sh check, test/sheet.sh
make golden     # regenerate test/golden/ from the Ada binary
make valgrind   # the program under valgrind over every fixture and path
make rst        # build/*.gen.rst; also pdf, gemtext, markdown, html, groff, hmm, inline, form, sheet, redraw, onecol
make install    # ova_fmt_po, ova_form.sh and ova_sheet.sh to $(PREFIX)/bin, default ~/local/bin (DESTDIR for staging)
make uninstall
make clean      # rm -rf obj ova_fmt_po build
make testclean  # rm -rf build
make print-VAR  # show a makefile variable
```

- **Don't run `make install` with the default `PREFIX` unless asked**:
  it puts `ova_fmt_po` in `~/local/bin`, beside the Ada `ova_fmt`.
  Check the target with `make install DESTDIR=<scratch>`.
- **Everything is compiled with `-OC`**, because polibfyaml requires
  it, and poc refuses a `.sym` from the other size model. Under `-OC`,
  `INTEGER` is 32 bits, like Ada's `Integer`, and `LONGINT` 64.
- **Don't copy `Ropes.Mod`, `ArgParser.Mod` or polibfyaml's modules
  into this repo.** They come compiled, from the poc libraries in
  `POCLIBDIR`. The makefile unexports `POC_LIBRARY_PATH`, so that is
  the only place it takes a library from. A change one of them needs
  is made in its own repo, tested and installed there, and needs the
  user's go-ahead. **After upgrading poc, reinstall all three**: a
  library records the poc that built it, and another poc refuses it.
- poc builds a program from its main module, compiling this repo's
  modules from source on every build into `obj/`. **A new module in
  `src/` needs nothing in the makefile**, a new unit test only its
  name in `TESTS`. Every program rewrites this repo's modules' files in
  `obj/`, so the makefile is `.NOTPARALLEL`.
- The main module is `OvaFmt`, built as `./ova_fmt_po`, named for this
  repo so it can be installed beside the Ada `ova_fmt`. Its messages
  still say `ova_fmt`, as the Ada version's do.

## Testing policy

- **The golden files** (`test/golden/`, from the Ada binary) fix
  standard output, standard error and the exit status together. Run
  `make test` after any change.
- **Regenerate golden files with `make golden`; never hand-edit one.**
  Add a line to `test/golden.cases` for new coverage and review the new
  files before committing them. A new format or option goes into the
  Ada version first, so that it can be the reference. `test/cli.sh`
  checks the inline format's filling (70 columns, no line opening a
  Markdown block). What can't be a golden file (a missing
  input file, an `-o` that can't be created or written) is checked in
  `test/cli.sh`.
- **`test/sheet.sh`** reads back the PDFs `-S -R`, `-S -R -C`, `-S`
  and `-X` make through `ova_sheet.sh` and `ova_form.sh`. `-S -R`'s
  checks, with `-C` and without, need only groff and poppler's tools; `-S`'s and `-X`'s also need the blank
  sheet (`OVA_SHEET`, which the makefile defaults), qpdf and jq. It
  skips, passing, what it lacks the tools or the sheet for; say so
  when a run skipped any of it. PLAN.md, "Build and tests", lists its
  checks.
- Fixtures: the capitalized ones in `test/data/` are the Ada repo's
  `test-data/` (copy any new one over, and keep them the same);
  `bad-*` and `edge-*` are this repo's. `[A-Z]*` cases take every
  character fixture, so a new one is covered in every format at once.
- Unit tests (`test/Test*.Mod`) print `ok   - <label>` / `FAIL -
  <label>` and end with `All checks passed.` or `<N> check(s) failed.`,
  exiting 1 on failure.
- **`make valgrind`** must have no errors, nothing lost, and no
  still-reachable block but the collector's own. Keep suppressions
  narrow: an error anywhere else is real until shown otherwise.
- **Prove a new check can fail**: plant the bug it targets and watch it
  fail.

## Working with ropes and poc here

- **The empty rope is NIL.** "Absent" needs its own flag (`hasDetail`,
  `hasTagline`, ...), as the Ada records have. Never add a flagless
  optional string.
- **Use `Ropes` directly for what it has**; `OvaText` holds only what
  it lacks: `Add`, `Int`, `Trim` (blank, tab, LF, CR, as the Ada
  `Trim_Whitespace`; not `Ropes.Trim`, which strips form feed too),
  `FoldCI`/`ToUpper` (Ada's Latin-1 `To_Lower`/`To_Upper`, which the
  sort order and the groff captions depend on; not `Ropes`' ASCII
  ones), `List` with `Join`, and `Chars`.
- **`Ropes.Length` counts bytes**, as Ada's `'Length` does: header
  underlines are as many bytes as the title.
- **Callbacks (`Ropes.Mapper`, `OvaCommon`'s `Formatter`, the loaders)
  must be module-level procedures**: a nested procedure can't be a
  procedure value.
- **Output is `OvaOut`**, never `Out` (which `-o` can't redirect) and
  never through `Ropes.ToString` into a fixed array. Flush it before
  writing to standard error.
- **No exceptions.** Loaders return `BOOLEAN`; `ASSERT`/`HALT` are for
  programmer errors only, never bad input. polibfyaml halts on a node
  of the wrong kind, so check `IsSequence`/`IsMapping`/`IsScalar`
  before using one.
- **polibfyaml gives a key with no value (`detail:`) as an empty
  scalar**, as the Ada binding does: present, and "".
- **No call chaining, no string concatenation operator.** Use a
  variable per step.
- **`*)` ends a comment anywhere, and `(*` inside a comment opens a
  nested one** -- watch for text like `*italic*` next to a parenthesis.
- **A string literal holds at most 255 characters.**
- **Every `CONST`, `TYPE` and `VAR` of a module comes before its first
  procedure** (`-strict` rejects anything else, and poc's own source
  keeps to it).

## Conventions

- Keep each module traceable to its Ada unit (PLAN.md, "Modules"), in
  the same order, with comments saying what it is and summarizing why;
  the Ada comments hold the full reasoning.
- Comments explain why, and only claim what has been verified. If a
  comment depends on how poc, Ropes, libfyaml or ArgParser behaves,
  test it with a throwaway program in the scratchpad first.
- A difference from the Ada version, new or newly found, goes in
  PLAN.md, "Differences from the Ada version".
- Record decisions and findings in PLAN.md as they happen. Mark a
  finished step `[done]` and strike through an open question once it's
  decided.
