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
  (Latin-1 capitals included), with a stable insertion sort, as the
  Ada version's `Stable_Sort` (it used `Generic_Sorting.Sort`, which
  needn't be stable, until 2026-10-10).
- **`To_Upper`.** groff-in-reST's "Attacks & Combat Stats (NAME)"
  caption upper-cases the name with Ada's Latin-1 `To_Upper`, which
  changes some UTF-8 lead bytes; `OvaText.ToUpper` does the same, so
  the output matches.
- **Help** exits with status 1, as the Ada version's `Help_Requested`
  handler does.

## Differences from the Ada version

Standard output, standard error and the exit status are the same for
every input, but for the command line's own messages: the usage's
layout, and the wording of ArgParser's errors (an unknown option, a
missing argument, an `-L` that isn't a non-negative integer), are
ArgParser's, as in pobesm2_fmt2. The statuses are the Ada version's: 2
for a mistake, 1 for `-h`.

Until 2026-10-10 there were more, where the Ada version died of an
unhandled exception or the libraries differed. The Ada version was
fixed to match the port, and this port and polibfyaml changed with it:

- YAML of the wrong shape: the Ada version's new `Shape_Error`, in the
  port's words, `PATH: not a sequence` (or `not a mapping`); the
  `bad-shape-*` fixtures are golden cases now.
- An input file that can't be opened: both say `ova_fmt: error
  processing FILE: FILE: REASON`, the Ada version's (GNAT's) words;
  `ReportYaml` rebuilds polibfyaml's `FILE: error: REASON` and line
  feed into that.
- An `-o` file that can't be created or written: the port's words.
- Standard input: both name it `(stdin)`, the Ada version through
  alibfyaml's `Open_String` name, polibfyaml (and olibfyaml) by
  `Fyaml.stdinName`, which was `<stdin>`.
- `-u`/`-U` with other than one character: the Ada version printed its
  message twice; both now print `Invalid value for option
  -u/--underliner: takes exactly one character, got "xx"`.

## Keys for the character generator [done]

ova_cg_po (`~/Repos/RPG/Tools/ova_cg_po`), an OVA character generator
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

- `test/golden.sh` and `test/golden.cases`: 946 cases, golden files
  from the Ada binary (`make golden`): every character fixture in every
  format and in combinations of the options, several files in one run,
  standard input, `-o`, and the error and edge-case fixtures
  (`test/data/bad-*.yaml`, `edge-*.yaml`, `Broken.yaml`). The
  capitalized fixtures are the Ada repo's `test-data/`, copied.
- `test/cli.sh`: the command line, what can't be a golden case (a
  missing input file, an `-o` that can't be created or written), and
  300 copies of a character in one file, which runs the collector many
  times.
- `test/TestText.Mod`: `OvaText`, on ropes of several leaves too.
- `make valgrind`: 533 runs, clean, with polibfyaml's suppressions and
  `test/poc-gc.supp` (the conservative stack scan's reports in
  `DrainMarkStack`, which this program's frames reach too).
- The rendered outputs (`make rst gemtext hmm`, and so on) are the same
  bytes as the Ada repo's `build/` files.

## Sample NPCs, npc-type, character-hooks, endurance [done]

The Ada version's commits of 2026-10-10, each with its PLAN.md entry
there, ported together (2026-10-10):

- groff-in-reST writes a `.br` before `.mso hdtbl.tmac` at the top of
  each raw ms block, so a prose paragraph's last line prints before
  hd's tables, not after them (Ada 7f50d3b).
- The rulebook's 8 Sample NPCs and 22 NPC Fragments (Ada 0eb4c32),
  copied flat into `test/data/` from its `sample-npcs/` and
  `sample-npc-fragments/<subsection>/`.
- `npc-type` and `character-hooks` (Ada 4c57810). `OvaEntities` has
  `Heroic`, `Secondary`, `Extra` and `NpcTypeName` (the Ada
  `NPC_Kind`, `NPC_Kind_Name`); `LoadNpcType` matches ignoring case and
  blanks, a bad name a recorded error in the Ada words, a non-scalar
  fatal as for any optional string. The type leads the main entity's
  stats line (`FormatCombatSummaryLine`'s and `PrintCombatAndAttacks`'s
  new `npcType`, NIL elsewhere), is `Combat (Secondary)` in the HTML
  caption, `(SECONDARY)` in the groff box in place of the name, and
  `Attributes (Secondary):` on a Fragment
  (`OvaCommon.FragmentAttributesLabel`). The hooks are a "Character
  Hooks" section after the other prose, or after a Fragment's
  Attributes line.
- An Ability's or SubItem's `endurance` (Ada 47b49d1):
  `FormatModifiersBracket(s, raw)` now takes the item, adding "5
  Endurance" after the Perks/Flaws, `raw` for the mark inside the raw
  tables. HTML-in-reST's header is `Perks/Flaws/Endurance`, and its
  cells now have the item's note, as every other format does.

`bad-npc-type.yaml` (a bad and an empty name, both reported),
`bad-npc-type-shape.yaml` (a sequence, which ends the file) and
`edge-npc-type.yaml` (case and blanks, a Fragment's type, multi-line
hooks) are this repo's; the port matched the Ada binary on each in
three formats before they became golden files. Regenerated, the golden
files changed only by the `.br` lines, the endurance and notes, the
HTML header, and the new NPCs in the several-files cases.

## Up to three Defense values [done]

Ported from the Ada version's (uncommitted there when ported,
2026-10-10): `defense` holds up to three values, `D[/A[/A]]`, so the
generator can save Incorporeal Form's alternate Defense beside
Barrier's. `OvBarrier` became `OvDefense2`, `OvDefense3` follows it,
and Health and Threat Value moved up one (`NOverrides` = 8); their
names are `defense-2` and `defense-3`, and `barrier` is still read as
`defense-2`, in `LoadOverrides`. `LoadCombat` records four or more
values as an error (`Slashes`), and `OvaCommon.DefenseText` marks each
value by its slot.

`Defenses.yaml` and `Wisp.yaml` are the Ada repo's new fixtures, and
`Sheet.yaml` its `defense-2` change. `bad-defense.yaml` (four values,
the keys where they don't belong) and `edge-defense.yaml` (every slot
marked, a missing slot's key, `barrier` with `defense-2`, a free-form
Defense with empty values) are this repo's; the port matched the Ada
binary on all six in six formats before they became golden files.
Regenerated, no existing golden file changed but the several-files
cases, which gained the new fixtures. Planted bugs (no `barrier`
alias, four values allowed) fail the golden check; `DefenseText`'s
stop at the third slot can't be reached, since a fourth value is a
load error.

## Open questions

- None yet. The Ada version's own open questions (direct-to-Lout
  output, a nested-table Markdown mode) are features still to design
  there; a change to the Ada program belongs here too.
