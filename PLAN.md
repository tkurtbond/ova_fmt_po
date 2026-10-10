# PLAN.md - porting ova_fmt to Oberon-2 with poc

The Ada `ova_fmt` (`~/Repos/RPG/Tools/ova_fmt`, at commit 262776d, "Add
Markdown backend") ported to Oberon-2, compiled with poc 0.5.0, then
the keys added to both for the character generator ("Keys for the
character generator"). The
design of the program itself -- the YAML schema, each output format's
layout, and why -- is in the Ada repo's `PLAN.md` and its source
comments; it isn't copied here. This file records the port.

## Approach [done]

The port follows pobesm2_fmt2 (`~/Repos/RPG/Tools/pobesm2_fmt2`), the
poc port of besm2_fmt, which solved the same problems for a sibling
program: every string is a `Ropes.Rope`; YAML comes through polibfyaml
(`Fyaml`, `FyamlStreams`); the command line through ArgParser; output
through a buffered module, since poc's `Out` can't be redirected for
`-o`. All three libraries are linked as poc libraries, not copied, and
everything is compiled `-OC`, as polibfyaml requires. Its `Besm2Out` is
copied unchanged as `OvaOut`, and `OvaText` is its `Besm2Text` cut down
to what ova_fmt needs, plus `ToUpper`.

## Modules [done]

| Oberon module | Ada unit |
|---|---|
| `OvaFmt` (main) | `ova_fmt_main.adb` |
| `OvaCli` | `Ova_Fmt.Cli` |
| `OvaConfig` | `Ova_Fmt.Config` |
| `OvaEntities` | `Ova_Fmt.Entities` |
| `OvaCommon` | `Ova_Fmt.Format_Common`, and `Format_Gemini` and `Format_Markdown`, which only call its `Process_Entity` |
| `OvaRst` | `Ova_Fmt.Format_Rst` |
| `OvaHmm` | `Ova_Fmt.Format_Hmm` |
| `OvaText` | `Ada.Strings`, `Ada.Characters.Handling` as used |
| `OvaOut` | `Ada.Text_IO`'s current output |

## Decisions

- **Records.** The Ada vectors of records become `OvaEntities.List`, a
  growable array of `Element`, with a record type per kind of item
  extending it, taken out with a type guard. `Ability` extends `SubItem`
  (the Ada records have the same fields but for the linked content), so
  `OvaCommon.FormatSubItemLine` serves both, as the Ada
  `Format_Ability_Line` and `Format_Sub_Item_Line` are the same; so are
  the two fragment-line formatters. The fourteen `fluff:` fields are an
  array indexed by constants, in the Ada field order.
- **Errors.** Oberon has no exceptions. Each `Require_*` failure is
  recorded in `OvaEntities.errors`, as in the Ada version; whatever the
  Ada version raised through to `Process_One` makes the loaders return
  `FALSE` with a message instead, and `OvaFmt` reports it in the same
  words. Error texts from polibfyaml are stripped of its
  `FILE:LINE:COLUMN: error: PATH: ` prefix (`OvaEntities.ErrorText`),
  which leaves the Ada binding's own words ('not a valid integer: "x"',
  'integer out of range: "x"', 'not a valid boolean: "x"'). A
  non-scalar value is checked here, to say 'key "K" is not a scalar
  value' as the Ada binding does.
- **Whole files.** As in the Ada version, every document and entity of
  a file is loaded before any of it is written, so a file with any
  problem writes nothing.
- **Sorting.** Abilities, Weaknesses, sub-items and Perks/Flaws are
  sorted by name then detail, folded as Ada's `To_Lower` folds them
  (Latin-1 capitals included), with a stable insertion sort. The Ada
  version uses `Generic_Sorting.Sort`, which needn't be stable: items
  equal in both name and detail could come out in another order. None
  of the fixtures has such a pair.
- **`To_Upper`.** groff-in-reST's "Attacks & Combat Stats (NAME)"
  caption upper-cases the name with Ada's Latin-1 `To_Upper`, which
  changes some UTF-8 lead bytes; `OvaText.ToUpper` does the same, so
  the output matches.
- **Help** exits with status 1, as the Ada version's `Help_Requested`
  handler does.

## Differences from the Ada version

Standard output is the same for every input. These are the differences
in what is reported, all where the Ada version dies of an unhandled
exception or where the libraries differ:

1. **YAML of the wrong shape** -- a list key (`abilities:`, `perks:`,
   `attacks:`, ...) that isn't a sequence, a list item or an entity
   that isn't a mapping, or a `combat:`, `fluff:`, `options:`,
   `companion:` or `vehicle:` that isn't a mapping -- dies in the Ada
   version with an `ASSERTION_ERROR` from libfyaml-nodes.ads, status 1.
   The port reports `ova_fmt: error processing FILE: PATH: not a
   sequence` (or `not a mapping`) and goes on with the next file.
2. **An input file that can't be opened** kills the Ada version with
   `NAME_ERROR`, ending the run. The port reports `ova_fmt: error
   processing FILE: FILE: error: No such file or directory` (polibfyaml's
   message, followed by a blank line as a YAML error is in both
   versions) and goes on with the next file.
3. **An `-o` file that can't be created** (`NAME_ERROR`) **or written**
   (`DEVICE_ERROR`): the port reports `ova_fmt: can't create PATH:
   REASON` or `ova_fmt: error writing output: REASON`. Status 1 in both.
4. **A YAML syntax error on standard input** names the input `<stdin>`
   (polibfyaml) where the Ada version, which reads standard input into a
   string first, says `(string-in-memory)`. The port's own messages say
   `(stdin)`, as the Ada version's do.
5. **The command line**: the usage's layout, and the wording of
   ArgParser's own errors (an unknown option, a missing argument, an
   `-L` that isn't a non-negative integer), are ArgParser's, as in
   pobesm2_fmt2. The statuses are the Ada version's: 2 for a mistake, 1
   for `-h`. For `-u`/`-U` with other than one character, the Ada
   version prints its message twice, in two wordings; the port prints
   the second, `ova_fmt: -u/--underliner takes exactly one character,
   got "xx"`.

## Keys for the character generator [done]

po_ova_cg (`~/Repos/RPG/Tools/po_ova_cg`), an OVA character generator
built on this program's `OvaEntities`, saves what ova_fmt had no keys
for. The user decided (2026-10-09) they are added to the Ada ova_fmt
first and then ported here: `player`, `appearance`, `other-notes`,
`portrait`; combat `notes` and `transformed`; an attack's `telekinesis`
and `transformed`; `threat-value-half` on an Ability or a granted one;
`options`' `starting-levels` and `half-cost-knowledge`; and `overrides`.
The Ada repo's PLAN.md, §9 step 9, has the schema and how each format
prints them; its `Format_Common` gained `Entity_Title` and
`Options_Text`, which this port already had as `OvaCommon.Title` and
`CreationRules`.

- `overrides` is a `SET` of `OvaEntities.OvRoll` .. `OvThreatValue`
  (the Ada `Override_Key`), `KeyName` its YAML spelling, for the
  generator's writer. A bad list is a recorded error, as in the Ada
  `Load_Overrides`, in the same words.
- `OvaCommon.Marked(r, k, overrides, raw)` writes the `*` after an
  overridden number: `\*` in reST and Markdown text, `*` in Gemtext,
  h-m-m and the raw tables (`raw`).
- `AllOneLine` moved from `OvaHmm` to `OvaCommon`, as in the Ada
  version: the tables' Combat Notes cells use it too.
- `test/data/Sheet.yaml` is the Ada repo's new fixture, using every
  key; `bad-overrides.yaml` (all four kinds of error) and
  `edge-overrides.yaml` (an empty list, and names for numbers the
  mapping doesn't have) are this repo's.

Verified: before regenerating the golden files, the new Ada binary gave
all 368 existing cases byte-for-byte, and the port matched it on
`Sheet.yaml` in 16 combinations of format and options and on both new
`bad-`/`edge-` fixtures; regenerated, only new files and new entities
in the several-files cases appeared. Then the samples gained the keys
that apply to them (the Ada PLAN.md, §9 step 9), and only Braun's and
Natsuki's outputs changed, a `*` after each ruling. Planted bugs (an unescaped `*`, a
misspelled `barrier`, half TV without `-O`, the Combat Notes rows left
out of the `.ne` count, combat `endurance` not allowed in `overrides`)
each failed between 2 and 20 cases.

## Testing [done]

- `test/golden.sh` and `test/golden.cases`: 390 cases, golden files
  from the Ada binary (`make golden`): every character fixture in every
  format and in combinations of the options, several files in one run,
  standard input, `-o`, and the error and edge-case fixtures
  (`test/data/bad-*.yaml`, `edge-*.yaml`, `Broken.yaml`). The
  capitalized fixtures are the Ada repo's `test-data/`, copied.
- `test/cli.sh`: the command line, the differences above (the
  `bad-shape-*` fixtures), and 300 copies of a character in one file,
  which runs the collector many times.
- `test/TestText.Mod`: `OvaText`, on ropes of several leaves too.
- `make valgrind`: 302 runs, clean, with polibfyaml's suppressions and
  `test/poc-gc.supp` (the conservative stack scan's reports in
  `DrainMarkStack`, which this program's frames reach too).
- The rendered outputs (`make rst gemtext hmm`, and so on) are the same
  bytes as the Ada repo's `build/` files.

## Open questions

- None yet. The Ada version's own open questions (direct-to-Lout
  output, a nested-table Markdown mode) are features still to design
  there; a change to the Ada program belongs here too.
