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
  uses the rulebook's "Name (Ability +L; N Endurance)", which is
  `FormatSpellLine` in parentheses. There is one form for both
  characters: Acacia's "10 END" is the rulebook being inconsistent,
  not a second form to copy. The `*` override marks are as in `raw`.
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
  rows at about 6.5 pt, one row per ruled line. If a column would
  overflow, it first packs the sub-rows about 9 pt apart, as the
  rulebook does, ignoring the ruling, and only then moves blocks to
  the continuation page. Whether the packed rows look right over the
  dotted ruling is to be checked by eye in step 2 of the order below.
  A sub-row too wide for the column wraps with a hanging indent, as
  Miho's and Fukiko's do, and each wrapped line counts as a row. Small
  caps for the perks, flaws and Endurance (`\s-1` and upper case, as
  the overlay font has no real small caps) are optional.
- **In XFDF** each row is one line field, and the Dice field can only
  hold an `Item`'s level. A `Sub` row goes in the Ability field as
  "  +2 Combat Expert" and a `Spell` row as "  Mana Shield (Barrier
  +2; 10+ Endurance)", with the Dice field empty. Consolas is
  monospaced, so the indent lines up. The form can't wrap or shrink,
  so long rows are cut off (the limit noted in "Two ways" below).
- **A Companion or Vehicle is not rows.** Its parent row on the sheet
  reads "Companion (Arasuni)". Its own Abilities and Weaknesses box
  and its Attacks & Combat Stats box go on the continuation page, as
  Karis's Arasuni does in the rulebook. A Fragment Companion is prose
  with an Attributes line, as Azyrus is.
- **Acacia's one-column block** is the model for an NPC sheet, part of
  the open question about redrawing the sheet. That layout puts a
  faint rule between the Abilities and the Weaknesses, and the same
  rows go above it.

### Tools

All are packaged on Fedora, Debian and the BSDs' ports/pkgsrc. All but
pypdf are installed here.

- **pdftk** (pdftk-java): `fill_form` with XFDF, `flatten`,
  `dump_data_fields_utf8`, `multistamp`. Tested: it fills and flattens
  this form. qpdf and pdfcpu can fill forms too.
- **qpdf**: `--overlay`/`--underlay` puts one PDF's pages over
  another's, `--flatten-annotations=all` bakes in a filled form, and
  `--pages` appends continuation pages. Tested: a groff page laid over
  the flattened sheet lands where it was placed.
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

1. **Fill the form.** ova_fmt writes XFDF (UTF-8 XML, one `<field>` per
   form field). Then `pdftk SHEET fill_form X.xfdf output OUT.pdf
   [flatten]`. This is the simplest way, and the result is still a
   form the player can edit in a PDF reader. Tested, it has limits:
   - The fields' font is Consolas with **WinAnsi encoding**, so pdftk
     drops any character outside it: "Tōdō" came out "T d". Characters
     in WinAnsi, such as the em dash, survive. Japanese names, U+2212
     minus and the like are lost unless the reader regenerates the
     appearances (`need_appearances`, which flattening can't use).
   - Single-line fields **clip** without wrapping or shrinking, so a
     long "Name (detail) [perks]" is cut at the field's edge.
   - Text can't overflow to another page. The portrait button needs
     its own image stamp.
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
fields. The XFDF path still gets Consolas, since the form's fields
name it and pdftk uses what they name.

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

**Proposed:** do both, the overlay first. It is the complete output,
and XFDF then costs little, since its field mapping is the same code.
The form-filled PDF is the one for a player who wants to keep editing
it.

### Modules (each in the Ada version first, then ported)

| Oberon module | Ada unit | Writes |
|---|---|---|
| `OvaSheetMap` | `Ova_Fmt.Sheet_Map` | Shared: the field table above (name, page, rectangle, size, single/multi-line) as constants, and `Fill(e)`. `Fill` maps an entity onto slots: Abilities and Weaknesses sorted as now (`OvaCommon`), each "Name (detail) [perks/flaws/endurance]" with the level in the Dice column. Built-under content becomes `Sub` and `Spell` rows in blocks kept together ("Sub-Abilities, as the rulebook prints them"). Attacks go to name / "Affinity; perks; flaws" / Roll, DX, End. Defense is `OvaCommon.DefenseText`, and `*` marks overrides, as `raw` does. Prose fields are trimmed and joined (`AllOneLine` where a field is one line). Whatever didn't fit goes on an overflow list. |
| `OvaSheetDraw` | `Ova_Fmt.Sheet_Draw` | With `-R`/`--redraw`, only with `-S`: the sheet's frames, drawn in groff, written before `OvaSheet`'s text, so no Dyskami background is needed ("Redrawing the sheet"). |
| `OvaXfdf` | `Ova_Fmt.Format_Xfdf` | `-X`/`--xfdf`: XFDF for `pdftk fill_form`, XML-escaped (`&`, `<`, `>`, `"`). Overflow becomes one line at the end of Other Notes ("More on the continuation sheet"), or, with an option, goes to standard error. |
| `OvaSheet` | `Ova_Fmt.Format_Sheet` | `-S`/`--sheet`: raw troff (no macro package, so nothing moves the text) at the sheet's size. A macro `FLD page x y w h size` places each value. Two passes per value: measure with `\w`, shrink to the floor, then wrap in an `.ev` with `.ll` set to the field's width. The continuation pages are in `-ms` style: linked Abilities, then the sections the sheet has no place for, reusing `OvaCommon`'s Formatter callbacks, as `OvaHmm` does. `-P FILE`/`--portrait FILE` overrides the portrait, which is otherwise the `portrait:` path, relative to the YAML file, as in `-H`. |

They fit the existing structure. `OvaConfig` gets `Xfdf` and `Sheet`
(exclusive with the other format flags, as now). `OvaFmt` dispatches
to them per entity. A file of several entities becomes several sheets,
one per main entity, each with its own linked Abilities on its
continuation pages. Subentities are not sheets of their own.

Escaping in `OvaSheet`: troff needs `\` written as `\e`, and a line
that would start with `.` or `'` gets `\&` in front. Only the program
writes requests. `OvaText` gains the XML escape and the troff escape,
with unit tests in `TestText.Mod`.

### Build and tests

- `make sheet`: `build/%.sheet.pdf` from each fixture, by the pipeline
  above. `make xfdf`: `build/%.xfdf` and `build/%.form.pdf` through
  `pdftk fill_form ... flatten`. The blank sheet's path is a make
  variable (`OVA_SHEET`) that defaults to the Reference copy. **The
  sheet itself is not copied into either repo**: it is Dyskami's.
- Golden cases fix the program's own output (the XFDF and the troff),
  from the Ada binary as for every other format. They don't fix the
  PDFs, which depend on the groff, pdftk and qpdf versions.
- `test/sheet.sh` (run by `make test` only when pdftk, qpdf and groff
  are present) builds a few fixtures to PDF. With `pdftotext -layout`
  it checks that each value appears and that p1 and p2 are two pages,
  plus one more page if there is overflow. Checks:
  - 18 Abilities overflow (an `edge-sheet-overflow.yaml`).
  - Miho's granted Weakness is in the Abilities column: `pdftotext`
    with `-x -y -W -H` set to that column's rectangle.
  - A block that doesn't fit moves whole, and one taller than the
    column splits with "(continued)" (an `edge-sheet-sub.yaml`).
  - A non-WinAnsi name survives the overlay.
  - The XFDF escapes.
  - A Companion goes to a continuation page.

  As always, prove each check by planting its bug.
- Review by eye: render with `pdftoppm -r 110` and compare with the
  blank sheet, and with the rulebook's own pages. Check Miho, Fukiko
  (Transformation), Auren and Acacia (spells), Karis (nested
  Companion), Natsuki (overrides), a Fragment and `Defenses.yaml`.

### Order

1. Ada first: `Sheet_Map` and `Format_Xfdf`, with golden files, and
   `make xfdf` there. Then port them here (`OvaSheetMap`, `OvaXfdf`)
   and check byte for byte.
2. Ada first: `Format_Sheet`, with the field placement checked against
   rendered pages, then continuation pages and the portrait. Then port
   `OvaSheet` here.
3. `test/sheet.sh`, `make sheet`/`make xfdf`, and the valgrind runs for
   the new paths.

## Open questions

- **The official sheet as PDF** (above), to be decided before work
  starts:
  - ~~Should the overlay be in groff or Lout?~~ groff (the user,
    2026-11-12).
  - ~~Which option letters?~~ `-S`/`--sheet`, `-X`/`--xfdf` and
    `-P`/`--portrait`, and `-R`/`--redraw` for the redrawn sheet (the
    user, 2026-11-12).
  - ~~A third mode that redraws the whole sheet?~~ Yes (the user,
    2026-11-12): "Redrawing the sheet".
  - ~~Which fonts?~~ Noto Sans, proportional, with the rulebook's
    emphasis (the user, 2026-11-12): "Fonts and type styles".
  - Order of work: should the Ada version come first, as this repo's
    rule for a new format says, or this port first, as with the inline
    format?
  - Fitting rows: may built-under rows be packed closer than the
    sheet's dotted ruling, before blocks move to a continuation page?
    Or should they keep to the ruled lines, and more go to the next
    page?
  - Spell form: Auren's "Mana Shield (Barrier +2; 10+ Endurance)" for
    every spell (proposed), or Acacia's shorter "Break (Frail −2, 10
    END)", which saves width?
  - XFDF overflow: should it be a line at the end of Other Notes, a
    warning on standard error, or a continuation page appended with
    qpdf, as in the overlay?
  - Several characters in one file: one sheet per main entity, all in
    one PDF (proposed), or one PDF for each?
  - pdftk is Java (pdftk-java). Should `make test` skip the PDF checks
    when it isn't installed (proposed), or should the form be filled
    with qpdf or pdfcpu alone, so Java isn't needed?

- The Ada version's own open questions (direct-to-Lout output, a
  nested-table Markdown mode) are features still to design there; a
  change to the Ada program belongs here too.
