# ova_fmt_po - ova_fmt in Oberon-2, built with poc

`ova_fmt` reads a character for the OVA tabletop RPG (Open Versatile
Anime engine) from a YAML file -- Abilities, Weaknesses, combat stats,
Attacks, and linked content such as Transformations, Magic spells,
Companions and Vehicles -- and writes it as terse reStructuredText,
gemtext, Markdown, reST with nested HTML tables, reST with groff `hd`
tables, an [h-m-m](https://github.com/nadrad/h-m-m) outline, or the
inline format, a paragraph of Markdown per character, as an adventure's
cast lists them.

This is the Ada [ova_fmt](https://github.com/tkurtbond/ova_fmt) (`~/Repos/RPG/Tools/ova_fmt`)
ported to Oberon-2 and built with poc, the
[Peaseblossom](https://github.com/tkurtbond/peaseblossom) Oberon
compiler. Every string is a rope, from `~/Repos/Oberon/Ropes`; YAML is
read through polibfyaml, the poc binding to libfyaml. The layout of the
port follows pobesm2_fmt2 (`~/Repos/RPG/Tools/pobesm2_fmt2`), the poc
port of besm2_fmt.

Standard output, standard error and the exit status are byte-for-byte
the same as the Ada binary's (the golden tests check this), but for the
command line's own messages, which are ArgParser's. PLAN.md lists the
differences.

## Usage

```
ova_fmt [options] [files...]
```

With no files, standard input is read. Output goes to standard output,
or to the file given by `-o`.

| Format | Option |
|---|---|
| terse reST (the default) | |
| gemtext | `-g`, `--gemtext` (`-e` for `*`/`**` emphasis) |
| Markdown | `-M`, `--markdown` |
| reST with nested HTML tables | `-H`, `--html` |
| reST with groff `hd` tables | `-G`, `--groff` |
| h-m-m outline | `-m`, `--hmm` (`-L`, `-c`, `-p`) |
| inline Markdown paragraphs | `-i`, `--inline` |

If more than one format option is given, the last one wins.

The inline format writes each character as one paragraph, filled to 70
columns, for pasting into an adventure's cast list:

```
**Drerta Drokris** (Secondary). The warden's second, now the senior
surviving |PKA| aboard. ... *Attack (Blaster rifle) +2, Combat Expert
+2, ...; Code of Conduct (the purity of the breed) −2, Stubborn −2.*
Blaster rifle (Ranged; Weapon): Roll 4, DX 3, End 0. Defense 3. Health
20, Endurance 20. TV 6.
```

It leaves out what a stat block doesn't need: the tagline, character
hooks, other notes, fluff, options, the player and the portrait. A
Companion, Vehicle, Transformation or spell list follows as a paragraph
of its own.
`ova_fmt -h` lists every option. The input format is described in the
Ada repo's `PLAN.md` and in the comments of its `test-data/*.yaml`.

## Building

You need:

- poc, with its runtime library `poc-rtl`, on `PATH` (override with
  `POC=`), and clang, which poc runs.
- libfyaml, found through `pkg-config`.
- The poc libraries `argparser` and `ropes`, installed by
  `make -f pocGNUmakefile install` in ArgParser and Ropes, and
  `polibfyaml`, installed by `make install` in
  `~/Repos/Oberon/polibfyaml`, all into `POCLIBDIR` (default
  `~/.local/lib/poc`).
  Install them again after upgrading poc, which refuses a library
  another version built.
- For `make golden` only, the Ada binary (`ADA_OVA_FMT`, default
  `~/Repos/RPG/Tools/ova_fmt/ova_fmt`; `gprbuild -p -P ova_fmt.gpr`
  there).
- For `make valgrind` only, a checkout of polibfyaml at `POLIBFYAML`
  (default `~/Repos/Oberon/polibfyaml`), for its suppressions.

```sh
make                # ./ova_fmt_po
make test           # unit tests, command-line checks, golden-output tests
make golden         # regenerate test/golden/ from the Ada binary
make valgrind       # the program under valgrind, over every fixture
make rst            # build/*.gen.rst; also pdf, gemtext, markdown, html, groff, hmm, inline,
                    # with the Ada GNUmakefile's file names
make install        # to $(PREFIX)/bin, default ~/local/bin
make uninstall
make clean          # everything built; make testclean removes only build/
```

The program is built as `ova_fmt_po`, so it can be installed beside the
Ada `ova_fmt`; its messages and usage still call it `ova_fmt`, as the
Ada version's do.

## OVA and the rulebook

OVA, *OVA: The Anime Role-Playing Game*, is © 2015 Wise Turtle. This
project is not affiliated with or endorsed by Wise Turtle. It formats
characters you write; it holds none of the rulebook's rules text, and
you need the rulebook to play.

The test fixtures in `test/data/` record the rulebook's sample
characters so that the formatter's output can be checked against them;
their backgrounds and descriptions are paraphrased, and only short
captions such as attack descriptions follow the book's wording.

## Documents

- [AGENTS.md](AGENTS.md): working notes on the build, the tests, ropes
  and poc.
- [PLAN.md](PLAN.md): the port: module layout, decisions, differences
  from the Ada version, and status.
