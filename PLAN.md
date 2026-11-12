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

## The inline format [done]

Added 2026-10-23 at the user's request, after the Cast of Lost-Worlds'
`001-breakout.md`, for adventures' cast lists, and the same day ported
to the Ada version (`Ova_Fmt.Format_Inline`). `-i`/`--inline` (`OvaConfig.Inline`) writes each entity
with `OvaInline` as one Markdown paragraph:

    **Name** (Secondary). Summary. Background. Appearance.
    Personality. *Abilities; Weaknesses.* Attack (Affinity: a; perks;
    flaws): Roll N, DX d, End c. Description. Defense D. Health H,
    Endurance E. TV T. Combat notes.

- With no NPC type the lead is `**Name.**`. A Fragment with a
  background leads with that (it names the NPC in bold already), then
  `Secondary NPC.`.
- The prose is joined onto one line and each part ended as a sentence
  (not after `.`, `!` or `?`, perhaps followed by a closing quote or
  parenthesis). Abilities and Weaknesses (a Companion's or Vehicle's
  and a Transformation's grants too) are `OvaCommon`'s Fragment lists,
  "Name Level (detail)", as the cast has "Attack +2 (Blaster rifle)"
  (the user's request, later on 2026-10-23); the perks and flaws
  `OvaCommon.FormatPerkFlaw` (exported for this), and `*` marks
  overrides, as in `-M`; `-n` works as in the other formats.
- Left out, as a stat block doesn't need them: tagline, character
  hooks, other notes, fluff, `options` (so `-O` changes nothing), the
  player and the portrait.
- A linked Ability (Companion, Vehicle, Transformation, spells) follows
  as its own paragraph, led by `**Companion: Name.**` or the Ability's
  name in bold.
- Paragraphs are filled to 70 columns, counting UTF-8 characters, and a
  run of blanks is one. A word that would open a Markdown block at the
  start of a line (`#`, `>`, a lone `+`, nothing but `-`, `=`, `*` or
  `_`, or digits and `.` or `)`) is kept on the line of the word before
  it, so `Endurance 10.` breaks before `Endurance`. Nothing is escaped,
  as in `-M`.

A `count:` over 1 makes one stat block stand for a group (the user,
2026-11-02, in the Ada version first; its PLAN.md has the details):
`**Guards** (three Extras).`, `**Crowd** (three).` with no NPC type,
`Extra NPCs (three).` after a Fragment's background, and `TV 1 each.`
Only this format shows it, as every other is a sheet, which describes
one. `count:` under 1 is a recorded error (`bad-count.yaml`), one that
isn't an integer ends the file (`bad-count-int.yaml`).

It was written here first, and its golden files came from this program
(a `po` reference and `make golden-po`, since removed). The Ada port
reproduced all of them byte for byte, so its cases' reference is now
`ada`, like every other case.

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
  `Heroic`, `Secondary`, `Extra`, `Boss` and `NpcTypeName` (the Ada
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

## The official character sheet as PDF [planned]

Asked for 2026-11-12: a plan for PDF output like the official
`~/Reference/RPG/OVA/OVA-Blank-Character-Sheet-Form-Fillable.pdf`,
filled from the YAML, with open source tools found on Linux and the
BSDs. Nothing below is built yet. By this repo's rule a new format goes
into the Ada version first, so each step is "Ada, then port".

### What the sheet is

Two A5 pages (419.528 x 595.276 pt), made in InDesign. It is an
AcroForm with 100 fields (`pdftk ... dump_data_fields_utf8`; the
rectangles came from pypdf). These are the Ada PLAN.md's §5 field
set:

| Field(s) | Where | Notes |
|---|---|---|
| `Character Name`, `Player Name` | p1 header | Consolas 12 |
| `Abilities Dice1`..`17`, `Ability 1`..`17` | p1 left | level and "name (detail) [perks]", one line each, Consolas 8, about 152 pt wide |
| `Weakness Dice 1`..`17`, `Weakness 1`..`17` | p1 right | the same |
| `Attack 1`..`4` / `Attack Description 1`..`4` | p1 Combat Stats | name, then a two-line description (Affinity, perks/flaws) |
| `roll`, `dx`, `end` (`_2`..`_4`) | p1 | auto-sized (`0 Tf`) |
| `Defense`, `Health`, `Endurance`, `TV` | p1 bottom | `Defense` holds `D/A/A` |
| `Combat Notes` | p1 left | multi-line, Consolas 6 |
| `Background`, `Appearance`, `Personality`, `Other Notes` | p2 | multi-line, Consolas 8 |
| `Portrait` | p2 right | a button (an image field), 163 x 287 pt |

The slots are fixed: 17 Abilities, 17 Weaknesses, 4 attacks. A
character with more needs another page. So does one with a Companion,
Vehicle or Transformation (a linked Ability, which gets its own
block), a Fragment's parent, or `notes:` callouts. The sheet has no
place for the tagline, character hooks, fluff or `options`.

### Sub-Abilities, as the rulebook prints them

The rulebook (`~/Reference/RPG/OVA/OVA_The_Anime_Role-Playing_Game.pdf`,
A5 like the sheet) prints its Sample Characters and Sample NPCs in the
sheet's own layout. They show the sheet filled in, including what it
has no lines for: an Ability with Abilities built under it. The page
numbers below are printed ones; the PDF's page is two more (printed 31
is PDF page 33). I read each block at 300 dpi (2026-11-12):

- **Miho** (p. 31), Transformation +1. The rows built under it are in
  smaller italic, indented into the name column, with a level column
  of their own: "+2 Combat Expert", "+2 Endurance Reserve", "−3 Unique
  Weakness". The last one's detail, "(Loss of Control)", wraps onto a
  hanging line under the name. The granted Weakness stays **in the
  Abilities column, inside the Transformation**, after its granted
  Abilities. It is not in the Weaknesses column.
- **Fukiko** (p. 37), Transformation +4, in the same form: "+2 Attack",
  then "+3 Barrier (AREA EFFECT; ELABORATE GESTURES; 5 END)", with the
  perks, flaws and Endurance in small caps, wrapping with a hanging
  indent. Then "+2 Combat Expert", "+2 Healer" and "−1 Bizarre
  Appearance (Cat Features)". Barrier's `note` isn't printed: its
  effect is the second Defense value, "4/5".
- **Auren** (p. 39), Magic, Arcane +3: six spells in smaller italic,
  in document order, aligned with the name column, with no level
  column: "Mana Shield (Barrier +2; 10+ Endurance)" through "Atlas Arm
  (Strong +3; 20 Endurance)".
- **Acacia** (p. 134, Sample NPCs), Magic, Witchcraft +3: three
  spells, indented a little further, in the form "Break (Frail −2, 10
  END)". Her stat block is simpler. A single column holds the
  Abilities, a faint rule, then the Weaknesses. It sits beside an
  "Attacks & Combat Stats (HEROIC)" box, which names her NPC type.
- Related, but not built-under rows:
  - Karis's Companion Arasuni (p. 29) has its own Abilities and
    Weaknesses box and a second "Attacks & Combat Stats (ARASUNI)" box
    on the same page.
  - Fukiko's Companion Azyrus, a Fragment, is prose with an
    "Attributes:" line.

In ova_fmt these are an `Ability`'s `subAbilities` and `subWeaknesses`
(`SubItem`, sorted, which matches Fukiko's order) and its `spells`
(`Spell`, in document order, which matches Auren's). `-G` already
prints them, as nested `hd` tables. The sheet output follows the
rulebook instead:

- **Rows, not lines.** `OvaSheetMap.Fill` turns each column into a
  list of rows, each with a kind:
  - `Item`: the level goes in the Dice field, the name in the Ability
    or Weakness field.
  - `Sub`: the level and the name both go in the name field, indented,
    with the level in a narrow column of its own.
  - `Spell`: no level, indented.

  A `Sub` row's text comes from `FormatSubItemLine`. A `Spell` row
  uses Acacia's shorter form, "Name (Ability L, N END)": "Break (Frail
  −2, 10 END)", "Mana Shield (Barrier +2, 10+ END)". It saves width
  on the narrow column, and is used for every spell, Auren's too (the
  user, 2026-11-12). `OvaCommon` gets a formatter for it beside
  `FormatSpellLine`, which stays as it is for the other formats. The
  `*` override marks are as in `raw`.
  An item's `note` stays off the row, as in the rulebook, and goes on
  the continuation page.
- **Granted Weaknesses go in the Abilities column**, in the
  Transformation's block, after its granted Abilities, as Miho's and
  Fukiko's are. The Weaknesses column holds only the character's own.
- **A parent and its rows are one block, kept together.** If a block
  doesn't fit in the column's remaining lines, all of it moves to the
  continuation page. Only a block taller than the whole column is
  split; the next page then repeats the parent as "Name (continued)".
- **Size and spacing.** The sheet rules its lines 13 pt apart; the
  rulebook sets built-under rows about a quarter smaller and closer
  together. The overlay sets `Item` rows at 8 pt and `Sub` and `Spell`
  rows at about 6.5 pt, **always one row per ruled line**: rows are
  never packed closer than the ruling, even though the rulebook packs
  its sub-rows about 9 pt apart. What doesn't fit goes to the
  continuation page (the user, 2026-11-12). A sub-row too wide for the column wraps with a hanging indent, as
  Miho's and Fukiko's do, and each wrapped line counts as a row. Small
  caps for the perks, flaws and Endurance (`\s-1` and upper case, as
  the overlay font has no real small caps) are optional.
- **In the filled form** each row is one line field, and the Dice
  field can only hold an `Item`'s level. A `Sub` row goes in the
  Ability field, indented with four spaces, as "    +2 Combat Expert",
  and a `Spell` row as "    Mana Shield (Barrier +2, 10+ END)", with
  the Dice field empty. The field is set in Helvetica-Oblique at 7 pt
  instead of 8, as the rulebook sets these rows smaller. Since every
  sub-row starts with the same four spaces, the indent lines up in the
  proportional face too (tested, Fukiko). The form can't wrap or
  shrink, so long rows are cut off (the limit noted in "Two ways"
  below). The rows that don't fit the slots go on a filled copy of
  page 1 ("Two ways").
- **A Companion or Vehicle is not rows.** Its parent row on the sheet
  reads "Companion (Arasuni)". Its own Abilities and Weaknesses box
  and its Attacks & Combat Stats box go on the continuation page, as
  Karis's Arasuni does in the rulebook. On the filled form (`-X`) they
  go on a page-1 copy of their own, named "Arasuni (Karis's
  Companion)" (the user, 2026-11-12). A Fragment Companion is prose
  with an Attributes line, as Azyrus is.
- **Acacia's one-column block** is its own option; the two-column
  sheet is the default (the user, 2026-11-12). It is a layout for the
  redrawn sheet, since the Dyskami sheet has two columns. One column
  holds the Abilities, a faint rule, then the Weaknesses, beside an
  "Attacks & Combat Stats" box, and the same kinds of rows go in it.
  The option is `-C`/`--one-column`, allowed only with `-S -R` (the
  user, 2026-11-12).

### Tools

All are packaged on Fedora, Debian and the BSDs' ports/pkgsrc. All but
pypdf are installed here. **No Java** (the user, 2026-11-12), so not
pdftk.

- **qpdf** (12.3 here): `--overlay`/`--underlay` puts one PDF's pages
  over another's, `--flatten-annotations=all` bakes in a filled form,
  and `--pages` appends continuation pages and joins PDFs. It also
  **fills the form**: `--json-output=2` dumps the whole PDF as JSON,
  and `--json-input` writes a PDF back from it. Tested: a groff page
  laid over the flattened sheet lands where it was placed, and the
  form fills and restyles (see "Two ways"). qpdf reads no XFDF or FDF.
  - `--update-from-json` (an update with only the changed objects)
    fills the values too, but in qpdf 12.3.2, on this sheet, it
    **silently ignores any change to the form's `/DR` font
    resources**. It still applies other changes to the same
    dictionary, and it exits 0. So a font can't be added that way. The
    full round trip through `--json-input` keeps the change (tested
    2026-11-12), so the fill uses that. A small hand-made form, and
    the sheet rewritten with `--object-streams=disable`, don't show the
    bug; the sheet rewritten by default or with `--qdf` does. The
    write-up, with a script that reproduces it, is
    `doc/qpdf-update-from-json-dr.md`. It is not submitted: the user
    wants to check qpdf's policy on AI-written reports first.
- **jq**: turns a flat `{"Field Name": "value"}` map into the edited
  JSON. It sets each field's `/V` and its `/DA` (font, size, colour),
  drops the field's old `/AP`, adds Helvetica-Oblique to `/DR`, and
  sets the AcroForm's `/NeedAppearances`. A filter of about 30 lines,
  kept in the repo. Every other object must pass through unchanged,
  since `--json-input` needs the whole file. The filter has to accept
  only string `/T` values: one object in this sheet has a numeric
  `/T`.
- **pdfcpu** (0.8): ruled out for filling. `pdfcpu form fill` refuses
  this sheet with "user font not loaded: Consolas", and Consolas isn't
  free to install.
- **pdftk** (pdftk-java): fills and flattens this form (tested), but
  is Java. Not used. The `/DR` problem above isn't a reason to go back
  to it: the round trip works, and pdftk can't restyle the fields
  either. It draws them in the font they name, Consolas.
- **groff** (1.23, `-Tpdf`, with `-k`/preconv for UTF-8): typesets the
  overlay. Absolute placement is easy (`.sp |Np`, `\h'|Np'`). It fills
  and hyphenates multi-line boxes, and gropdf embeds fonts. `.PDFPIC`
  places the portrait, a PDF that **rsvg-convert** or **ImageMagick**
  makes from a PNG, JPEG or SVG. This program already writes groff
  (`-G`). **Chosen for the overlay** (the user, 2026-11-12).
- **fontforge** and groff's **afmtodit** turn the Noto Sans TrueType
  files into Type 1 fonts and groff font descriptions for gropdf
  ("Fonts and type styles").
- **Lout**: considered for the overlay, and what the Ada PLAN.md §9
  step 7 plans for a direct-to-Lout backend. Not chosen: absolute
  placement is clumsier in Lout than in groff, and its PostScript
  output needs ps2pdf.
- **Ghostscript** (`ps2pdf`, and for checking), **poppler-utils**
  (`pdftoppm` to render pages for review, `pdftotext` for tests,
  `pdffonts`), **mutool** (MuPDF) as a second renderer.
- Not chosen: LaTeX (`textpos`/`pdfpages`), typst and Inkscape. They
  are able, but each is a large dependency the toolchain doesn't
  already have.

### Two ways, and the findings that decide between them

1. **Fill the form.** ova_fmt writes the field values, and qpdf puts
   them in the form (pdftk is Java, and pdfcpu can't load the form's
   font; see "Tools"). qpdf reads no XFDF, so the program writes a
   flat JSON map, `{"Field Name": "value", ...}`, and jq edits qpdf's
   JSON of the sheet with it:

       qpdf --json-output=2 SHEET blank.json   # once; 2.3 MB
       ova_fmt_po -X x.yaml > vals.json
       jq --slurpfile v vals.json -f sheet-fill.jq blank.json > filled.json
       qpdf --json-input filled.json out.pdf

   The result is still a form the player can edit in a PDF reader, and
   it is **left editable, not flattened** (the user, 2026-11-12: "the
   most useful").

   **The fields are restyled in proportional faces.** The sheet's
   fields name Consolas, which the user liked less than the
   rulebook's proportional type with its differing styles. Each
   field's `/DA` names its own font, size and colour, so the jq filter
   rewrites them with the rulebook's emphasis ("Fonts and type
   styles"), in the PDF standard fonts, which every reader has and
   which need nothing embedded:

   | Fields | Face |
   |---|---|
   | `Ability N`, `Weakness N` | Helvetica-Oblique 8; built-under and spell rows 7 |
   | `Attack N` | Helvetica-Bold 8, dark red (`0.47 0.11 0.13 rg`) |
   | `Attack Description N` | Helvetica-Bold 7 |
   | `roll`, `dx`, `end` (`_2`..`_4`) | Helvetica-Bold, auto-sized (`0 Tf`) |
   | `Defense`, `Health`, `Endurance`, `TV` | Helvetica-Bold 18 |
   | `Character Name` | Helvetica 12 |
   | `Combat Notes` | Helvetica 6 |
   | the Dice fields and the prose | Helvetica 8 |

   The sheet's `/DR` already has Helvetica (`/Helv`) and Helvetica-Bold
   (`/HeBo`); the filter adds Helvetica-Oblique as `/HeOb`. Tested on
   Fukiko (2026-11-12), which the user said "looks much better".
   Restyled, the attack descriptions and Combat Notes now wrap within
   their fields. Noto Sans would have to be embedded in the form, and
   a reader redraws an edited field in the font the field names, so
   the standard fonts are the practical choice; each reader
   substitutes its own Helvetica (Nimbus Sans here).

   Tested (2026-11-12, Fukiko), it has limits:
   - The fields' fonts use **WinAnsi encoding**. Flattened
     (`--generate-appearances --flatten-annotations=all`), qpdf turns
     every character outside it into "?": "Tōdō" came out "T?d?", and
     U+2212 "?2". It also drops the newlines in multi-line fields.
     pdftk's flattening did much the same ("T d").
   - Left unflattened, with `/NeedAppearances` set, the reader draws
     the fields itself. With Consolas, MuPDF showed "Tōdō", "−2" and
     the newlines, in a fallback serif; poppler kept the newlines but
     dropped ō and −. So with `-X` the program writes ASCII `-` for a
     minus, as `-n` does (the user, 2026-11-12: it is what a player
     would type anyway).
   - Single-line fields **clip** without wrapping or shrinking, so a
     long "Name (detail) [perks]" is cut at the field's edge.
   - Text can't overflow into the form, so whatever doesn't fit goes
     on a **second copy of page 1**, filled on its own and appended
     with qpdf (the user's proposal, 2026-11-12). Its Character Name
     reads "Fukiko (continued)". It takes the Ability and Weakness
     rows past the 17 slots and the attacks past the four boxes, and
     stays as editable as the first. Tested: each copy filled by the
     jq filter, then `qpdf --empty --pages fill.pdf 1-2 cont.pdf 1 --
     out.pdf` gave three pages and 195 working fields. qpdf renamed
     the copy's fields ("Attack Description 1+1", "roll+1") and kept
     their values, kept `/NeedAppearances`, and copied `/DR`'s fonts
     (`/HeOb_1`), so the copy renders in the restyled faces. Since each
     copy is filled before the join, the program never writes the
     `+1` names. The pages can be in any order: `--pages fill.pdf 1
     cont.pdf 1 fill.pdf 2` (tested) puts the copy between the sheet's
     two pages, with the same 195 fields, since qpdf takes the two
     mentions of `fill.pdf` as one file and renames none of its
     fields. The portrait button needs its own image stamp.
   - Several characters are one PDF, a filled sheet each. `qpdf
     --empty --pages a.pdf b.pdf -- both.pdf` keeps both forms working:
     tested, it renames the second copy's fields ("Weakness Dice 9+1"),
     200 fields in all.
2. **Overlay typeset text on the blank sheet.** ova_fmt writes a groff
   document at the sheet's page size. Each value goes in its field's
   rectangle, in a font with the characters it needs. If a value is
   too long, its point size steps down to a floor, then it wraps. The
   overflow goes on continuation pages: linked Abilities, extra
   attacks, notes, hooks, and whatever the slots couldn't hold.
   Then:

       qpdf --flatten-annotations=all --remove-restrictions SHEET blank.pdf   # once
       ova_fmt_po -S x.yaml | groff -k -Tpdf -P-p595.276p,419.528p > text.pdf
       qpdf blank.pdf --overlay text.pdf --to=1-2 -- --pages . text.pdf 3-z -- out.pdf

   (A one-page variant just for p1 or p2 comes from the `--to` range.
   `--pages` appends the continuation pages, which are plain pages and
   need no background.) Tested: positioning works, and UTF-8 needs
   `-k`. This gives full Unicode, wrapping and fitting, the portrait
   (`.PDFPIC`), and no fixed limits.

### Fonts and type styles [decided]

The user decided (2026-11-12): a proportional font, as in the
rulebook's sample characters, and that font is **Noto Sans**. Not
monospace: Consolas was only ever proposed to match the form's own
fields. The filled form (`-X`) can't embed Noto Sans practically, so
it gets the same emphasis in the PDF standard Helvetica faces ("Two
ways", 1).

The rulebook uses Calluna Sans (`pdffonts` on PDF page 33), which is
commercial; Noto Sans is free and on every system here. Each part of
an entry keeps the rulebook's emphasis, in the matching Noto Sans
face:

| Part | Rulebook | Overlay |
|---|---|---|
| Ability, Weakness rows | Calluna Sans Italic | Noto Sans Italic, 8 pt; the detail in parentheses too |
| Built-under and spell rows | Calluna Sans Light Italic, smaller | Noto Sans Light Italic, about 6.5 pt |
| Their perks, flaws and Endurance | small caps | upper case one size down (`\s-1`) in Noto Sans Regular. The Type 1 conversion drops OpenType's `smcp`, so real small caps aren't available. |
| Attack name | Calluna Sans Bold, dark red | Noto Sans Bold, dark red (a `.defcolor` from the sheet's colour) |
| Attack's perks, flaws, Affinity | small caps | the same faked small caps |
| Attack description | Calluna Sans Bold | Noto Sans Bold |
| Roll, DX, End; Defense, Health, Endurance, TV | the sheet's large condensed numerals | Noto Sans Condensed SemiBold, sized to the box |
| Name, player, prose (p2) | | Noto Sans Regular |

**gropdf can't read TrueType** in groff 1.23. A make step builds a
font directory under `build/font/devpdf`:

1. `fontforge` writes each face as `.pfa` and `.afm`.
2. `afmtodit -e enc/text.enc FACE.afm map/text.map NAME` writes groff's
   description.
3. A `download` file lists each face. Its lines are TAB-separated,
   with an empty foundry field first; a line separated by spaces gives
   Perl warnings and leaves the face unembedded.

`groff -F build/font` then uses the fonts. The TTF directory is a make
variable, since the BSDs keep it under `/usr/local/share/fonts`.

Tested here (2026-11-12) with Regular, Italic, Bold and BoldItalic:
all four embedded, "Tōdō Ōkami" and U+2212 came through `-k`, and the
faked small caps looked right at 200 dpi. afmtodit warns that two Greek
glyph names map to one code; that is harmless.

### Redrawing the sheet [decided]

The user decided (2026-11-12) there will also be a third mode: groff
draws the sheet itself, with no Dyskami artwork, so the output can be
shared. `OvaSheetDraw` (Ada `Ova_Fmt.Sheet_Draw`) writes the frames:

- the rounded panels, done with `\D'p'` polygons and `\D'a'` arcs;
- the dotted rules and the shaded backgrounds (`\M` fill colour);
- the Combat Stats box's grid;
- the headings ("Abilities", "Weaknesses", "Attacks & Combat Stats",
  "Background" and so on), set in Noto Sans ExtraCondensed Bold in
  place of the rulebook's Chalet Comprime;
- no OVA logo.

It uses the same field rectangles as the overlay, so `OvaSheet` places
the text the same way over either background. For NPCs,
Acacia's one-column block is the model, as noted under "Sub-Abilities"
above.

All three are planned: the overlay first, since it is the complete
output, then the filled form, which costs little, since its field
mapping is the same code. The filled form is the one for a player who
wants to keep editing it.

### Modules (each in the Ada version first, then ported)

| Oberon module | Ada unit | Writes |
|---|---|---|
| `OvaSheetMap` | `Ova_Fmt.Sheet_Map` | Shared: the field table above (name, page, rectangle, size, single/multi-line) as constants, and `Fill(e)`. `Fill` maps an entity onto slots: Abilities and Weaknesses sorted as now (`OvaCommon`), each "Name (detail) [perks/flaws/endurance]" with the level in the Dice column. Built-under content becomes `Sub` and `Spell` rows in blocks kept together ("Sub-Abilities, as the rulebook prints them"). Attacks go to name / "Affinity; perks; flaws" / Roll, DX, End. Defense is `OvaCommon.DefenseText`, and `*` marks overrides, as `raw` does. Prose fields are trimmed and joined (`AllOneLine` where a field is one line). Whatever didn't fit goes on an overflow list. |
| `OvaSheetDraw` | `Ova_Fmt.Sheet_Draw` | With `-R`/`--redraw`, only with `-S`: the sheet's frames, drawn in groff, written before `OvaSheet`'s text, so no Dyskami background is needed ("Redrawing the sheet"). |
| `OvaForm` | `Ova_Fmt.Format_Form` | `-X`/`--form`: the page fills for qpdf ("Two ways"), JSON-escaped (`"`, `\`, control characters; a multi-line field's newlines as `\n`). An array per main entity of fills `{"pages": [...], "sub": [...], "fields": {...}}`, which `ova_form.sh` turns into a PDF ("The form script"). The letter `-X` dates from XFDF, which it no longer writes (the user, 2026-11-12). |
| `OvaSheet` | `Ova_Fmt.Format_Sheet` | `-S`/`--sheet`: raw troff (no macro package, so nothing moves the text) at the sheet's size. A macro `FLD page x y w h size` places each value. Two passes per value: measure with `\w`, shrink to the floor, then wrap in an `.ev` with `.ll` set to the field's width. The continuation pages are in `-ms` style: linked Abilities, then the sections the sheet has no place for, reusing `OvaCommon`'s Formatter callbacks, as `OvaHmm` does. `-P FILE`/`--portrait FILE` overrides the portrait, which is otherwise the `portrait:` path, relative to the YAML file, as in `-H`. |

They fit the existing structure. `OvaConfig` gets `Form` and `Sheet`
(exclusive with the other format flags, as now). `OvaFmt` dispatches
to them per entity. A file of several entities becomes **one PDF**
with a sheet per main entity (the user, 2026-11-12), each with its own
linked Abilities on its continuation pages. Subentities are not sheets
of their own. For the overlay, each sheet's two pages go over the
blank sheet and its continuation pages follow it; the qpdf page ranges
come from a page count the program writes (a comment, or a file
beside the output).

Escaping in `OvaSheet`: troff needs `\` written as `\e`, and a line
that would start with `.` or `'` gets `\&` in front. Only the program
writes requests. `OvaText` gains the JSON escape and the troff escape,
with unit tests in `TestText.Mod`.

### The form script, `ova_form.sh` [decided]

The program writes the fills; a script, `ova_form.sh`, runs jq and
qpdf on them (the user, 2026-11-12). The program then starts no
processes (untested in poc), and the golden files fix the JSON alone,
which doesn't depend on the qpdf version.

What `-X` writes: a JSON array with an array of fills per main
entity, in the input's order. A fill is one copy of the sheet:

    [ [ {"pages": [1, 2],
         "sub": ["Ability 8", "Ability 9"],
         "fields": {"Character Name": "Fukiko", "Ability 1": "...",
                    "Abilities Dice1": "+2", "Background": "..."}},
        {"pages": [1], "sub": [],
         "fields": {"Character Name": "Fukiko (continued)",
                    "Ability 1": "Extra Ability Eighteen", ...}},
        {"pages": [2], "sub": [],
         "fields": {"Background": "Fukiko: Linked Abilities\n..."}} ],
      [ ...the next character's fills... ] ]

- The main sheet is one fill for both pages, since no field name is
  on both, so it costs one qpdf run.
- `sub` names the fields holding sub-rows, which the script sets in
  7 pt (the restyle table in "Two ways"); the test filter had them
  written in.
- `fields` holds only the fields with values; the rest stay empty.

Usage:

    ova_form.sh [-s SHEET] [-o OUT.pdf] [-k] [FILE.json]

| Option | Meaning |
|---|---|
| `-s SHEET` | The blank sheet; default `$OVA_SHEET`. Neither given is an error: the sheet isn't ours to bundle. |
| `-o OUT.pdf` | The output; default FILE with `.json` replaced by `.pdf`. Needed when the JSON comes from standard input. |
| `-k` | Keep the work directory, for debugging. |

Steps:

1. Check that `qpdf` and `jq` are there.
2. Make a work directory with `mktemp -d` under `$TMPDIR`, removed by
   a `trap` on exit unless `-k`.
3. `qpdf --json-output=2 SHEET blank.json`, once (about 2.3 MB).
4. For each fill: the restyle filter (the test's `style.jq`, kept in
   the script as a heredoc so the script is one file) sets the
   fill's values and each field's `/DA`, deletes `/AP`, adds `/HeOb`
   to `/DR` and sets `/NeedAppearances`, writing `filled-N.json`;
   then `qpdf --json-input filled-N.json part-N.pdf`.
5. Join with `qpdf --empty --pages ... -- OUT.pdf`. For each
   character, in order: every fill with page 1, in the order
   written, then every fill with page 2 (the user, 2026-11-12). So
   Fukiko above is `part-0.pdf 1 part-1.pdf 1 part-0.pdf 2 part-2.pdf
   2`, and a second character's pages follow in the same way.
6. Exit 0 on success, and on qpdf's exit 3 (warnings only), passing
   the warnings on; otherwise exit 1 with qpdf's message.

It doesn't fill the portrait button, which needs its own image stamp,
and doesn't flatten the form, which stays editable. The script is
written in the Ada repo first and copied here, as the fixtures are.
Both repos' `make install` put the same file in `$(PREFIX)/bin`, so
the copies must stay the same.

A typical use:

    export OVA_SHEET=~/Reference/RPG/OVA/OVA-Blank-Character-Sheet-Form-Fillable.pdf
    ova_fmt_po -X -o fukiko.json test/data/Fukiko.yaml
    ova_form.sh fukiko.json

`fukiko.json` has one fill, `"pages": [1, 2]`, since Fukiko's 12
Abilities, 6 Weaknesses and 4 attacks fit; `fukiko.pdf` is two
editable pages. With 18 Abilities and a fifth attack, a `[1]` fill
adds "Fukiko (continued)" as page 2, and her own page 2 becomes page
3; with linked Abilities, a `[2]` fill adds a last page whose
Background starts "Fukiko: Linked Abilities". `ova_fmt_po -X
Party.yaml | ova_form.sh -o party.pdf` gives one PDF, each
character's pages in turn.

### Build and tests

- `make sheet`: `build/%.sheet.pdf` from each fixture, by the pipeline
  above. `make form`: `build/%.fields.json` and `build/%.form.pdf`
  through `ova_form.sh`, unflattened. The blank
  sheet's path is a make
  variable (`OVA_SHEET`) that defaults to the Reference copy. **The
  sheet itself is not copied into either repo**: it is Dyskami's.
- Golden cases fix the program's own output (the JSON field map and
  the troff), from the Ada binary as for every other format. They
  don't fix the PDFs, which depend on the groff and qpdf versions.
- `test/sheet.sh` (run by `make test` only when qpdf, jq and groff
  are present) builds a few fixtures to PDF. With `pdftotext -layout`
  it checks that each value appears and that p1 and p2 are two pages,
  plus one more page if there is overflow. Checks:
  - 18 Abilities overflow (an `edge-sheet-overflow.yaml`).
  - Miho's granted Weakness is in the Abilities column: `pdftotext`
    with `-x -y -W -H` set to that column's rectangle.
  - A block that doesn't fit moves whole, and one taller than the
    column splits with "(continued)" (an `edge-sheet-sub.yaml`).
  - A non-WinAnsi name survives the overlay.
  - The JSON map escapes, and `jq` accepts it.
  - The filled form's values read back (`qpdf --json-key=acroform`).
  - A Companion goes to a continuation page.
  - Two characters give one PDF with two sheets.

  As always, prove each check by planting its bug.
- Review by eye: render with `pdftoppm -r 110` and compare with the
  blank sheet, and with the rulebook's own pages. Check Miho, Fukiko
  (Transformation), Auren and Acacia (spells), Karis (nested
  Companion), Natsuki (overrides), a Fragment and `Defenses.yaml`.

### Order

The Ada version comes first, as this repo's rule says (the user,
2026-11-12).

1. Ada first: `Sheet_Map` and `Format_Form`, with golden files, and
   `make form` there. Then port them here (`OvaSheetMap`, `OvaForm`)
   and check byte for byte.
2. Ada first: `Format_Sheet`, with the field placement checked against
   rendered pages, then continuation pages and the portrait. Then port
   `OvaSheet` here.
3. `test/sheet.sh`, `make sheet`/`make form`, and the valgrind runs for
   the new paths.

## Open questions

- **The official sheet as PDF** (above), to be decided before work
  starts:
  - ~~Should the overlay be in groff or Lout?~~ groff (the user,
    2026-11-12).
  - ~~Which option letters?~~ `-S`/`--sheet`, `-X`/`--xfdf` (now
    `--form`, below) and
    `-P`/`--portrait`, and `-R`/`--redraw` for the redrawn sheet (the
    user, 2026-11-12).
  - ~~A third mode that redraws the whole sheet?~~ Yes (the user,
    2026-11-12): "Redrawing the sheet".
  - ~~Which fonts?~~ Noto Sans, proportional, with the rulebook's
    emphasis (the user, 2026-11-12): "Fonts and type styles".
  - ~~Order of work: Ada first, or this port first?~~ The Ada version
    first (the user, 2026-11-12).
  - ~~Fitting rows: pack built-under rows closer than the ruling?~~
    No: they always stay on the ruled lines, and more goes to the next
    page (the user, 2026-11-12).
  - ~~Spell form: Auren's or Acacia's?~~ Acacia's shorter "Break
    (Frail −2, 10 END)", for every spell (the user, 2026-11-12).
  - ~~XFDF overflow: a line in Other Notes, standard error, or a
    continuation page?~~ A continuation page added with qpdf, as with
    `-S` (the user, 2026-11-12), and then a filled copy of page 1
    (below).
  - ~~Several characters in one file: one PDF, or one each?~~ One PDF
    with a sheet per main character (the user, 2026-11-12).
  - ~~pdftk is Java: skip the checks without it, or fill the form
    another way?~~ Fill it with qpdf or pdfcpu alone, so Java isn't
    needed (the user, 2026-11-12). pdfcpu can't load the form's
    Consolas, so it is qpdf, with jq ("Two ways").
  - ~~Acacia's one-column block: the NPC layout, or an option?~~ Its
    own option, with the two-column sheet the default (the user,
    2026-11-12).

  Raised by those answers, still open:

  - ~~The one-column option's letters?~~ `-C`/`--one-column`, only
    with `-S -R`, since the Dyskami sheet's art has two columns (the
    user, 2026-11-12).
  - ~~`-X`/`--xfdf` no longer writes XFDF: rename it?~~ Keep `-X`,
    rename the long option `--form`; the module is `OvaForm` (Ada
    `Format_Form`) and `make xfdf` becomes `make form` (the user,
    2026-11-12).
  - ~~How the `-X` continuation page is written?~~ Not by groff: a
    second, separately filled copy of page 1, appended with qpdf, for
    rows past the slots and attacks past four (the user's proposal,
    2026-11-12; tested, "Two ways"). Then:
    - ~~Who runs qpdf and jq: the program, or a script?~~ A script,
      `ova_form.sh`, with each character's page-1 copies after its
      page 1 and before its page 2 (the user, 2026-11-12): "The form
      script".
    - ~~What else goes on copies?~~ Linked Abilities and prose too
      long for page 2 go on a page-2 copy (the user, 2026-11-12). Page
      2 has no name field and its printed labels can't change, so each
      field of the copy opens with a label line of the program's own:
      "Fukiko: Linked Abilities" in Background, "Fukiko: Appearance
      (continued)" and so on. A Companion's or Vehicle's own boxes go
      on a page-1 copy named "Arasuni (Karis's Companion)" (the user,
      2026-11-12).
  - ~~Is the filled form left editable, not flattened?~~ Yes (the
    user, 2026-11-12), and its fields are restyled in Helvetica faces.
  - ~~With `-X`, should a minus be ASCII `-`?~~ Yes (the user,
    2026-11-12): it is what a player would type anyway.
  - ~~qpdf's `--update-from-json` ignores `/DR` changes: go back to
    pdftk and Java?~~ No: the full `--json-input` round trip works
    ("Tools"). ~~Report it to qpdf?~~ Written up in
    `doc/qpdf-update-from-json-dr.md`, not submitted until the user has
    checked qpdf's policy on AI-written reports.
  - ~~How are text widths measured?~~ In the program, from groff's
    font description files, so the page breaks are deterministic and
    the golden files fix them (the user, 2026-11-12).
    Only `-S` needs this: the form's rows clip, so `-X` fits by
    counting slots.

- The Ada version's own open questions (direct-to-Lout output, a
  nested-table Markdown mode) are features still to design there; a
  change to the Ada program belongs here too.
