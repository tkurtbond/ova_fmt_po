# qpdf bug report (draft): `--update-from-json` drops changes to an AcroForm's `/DR`

**Status: not submitted.** Written 2026-11-12 while planning the sheet
PDF output (PLAN.md, "The official character sheet as PDF"). It has
not been sent to the qpdf project. The user wants to check that
project's policy on AI-written bug reports first. The draft was
written by Claude (an AI assistant) and should say so if it is ever
submitted.

---

## Summary

With `--update-from-json`, a change to the `/DR` (default resources)
dictionary of a form's AcroForm object is silently lost on some
files. qpdf exits 0 and prints no warning. Another change to the
**same object in the same update** (adding `/NeedAppearances true`)
is applied. A full round trip through `--json-output=2` and
`--json-input`, with the same edit, keeps the `/DR` change.

## Versions

- qpdf 12.3.2 (Fedora 44 package `qpdf-12.3.2-1.fc44.x86_64`)
- jq 1.8.1 (only used to build the JSON)
- Linux 7.2.7

## Input

The failing file is a two-page form-fillable PDF made by Adobe InDesign
CS6 (Producer: Adobe PDF Library 10.0.1, PDF 1.6). It has an
incremental update and keeps the AcroForm object (`198 0 R`) in an
object stream. Its `/DR` is a direct dictionary:

    /DR << /Encoding << /PDFDocEncoding 38 0 R >>
           /Font << /ArialNarrow 28 0 R /ComicSansMS 274 0 R
                    /Consolas 275 0 R /Consolas,Bold 29 0 R /HeBo 30 0 R
                    /Helv 31 0 R /KozGoPr6N-Medium 32 0 R /ZaDb 33 0 R >> >>

The file is a publisher's blank character sheet (SHA-256
`27ba5663bb4d589cdb79f67b00452aea68a0a82247de230e0caf89edee97a49f`).
It is not ours to attach. A file that reproduces the bug without it
has not been found yet: see "What does and doesn't reproduce it".

## Steps to reproduce

`repro.sh FORM.pdf`, run in an empty directory:

```sh
#!/bin/sh
# Usage: repro.sh FORM.pdf
# Adds a key to the AcroForm's /DR /Font dictionary with --update-from-json
# and with a full --json-input round trip, then shows /DR /Font's keys.
set -e
in=$1
fonts() {
    qpdf --json-output=2 --json-key=qpdf "$1" |
    jq -c '.qpdf[1][] | .value? | objects | select(has("/Fields")) | ."/DR"."/Font" | keys'
}
qpdf --json-output=2 "$in" full.json
k=$(jq -r '.qpdf[1] | to_entries[] | select(.value.value? | objects | has("/Fields")) | .key' full.json)
# The AcroForm object, with /HeOb added to /DR /Font (pointing at /Helv's font)
# and /NeedAppearances set, as a control that the update is applied at all.
jq --arg k "$k" '.qpdf[1][$k].value
    | .["/DR"]["/Font"]["/HeOb"] = .["/DR"]["/Font"]["/Helv"]
    | .["/NeedAppearances"] = true' full.json > acroform.json
jq --arg k "$k" --slurpfile a acroform.json \
   '{qpdf: [.qpdf[0], {($k): {value: $a[0]}}]}' full.json > update.json
jq --arg k "$k" --slurpfile a acroform.json \
   '.qpdf[1][$k].value = $a[0]' full.json > full-edited.json
echo "AcroForm is $k"
echo "input:              $(fonts "$in")"
status=0
qpdf "$in" --update-from-json=update.json out-update.pdf || status=$?
echo "--update-from-json: $(fonts out-update.pdf) (qpdf exited $status)"
qpdf --json-output=2 --json-key=qpdf out-update.pdf |
    jq -c '.qpdf[1][] | .value? | objects | select(has("/Fields")) | {NeedAppearances: ."/NeedAppearances"}'
qpdf --json-input full-edited.json out-json-input.pdf
echo "--json-input:       $(fonts out-json-input.pdf)"
```

## Expected

`/HeOb` in the output's `/DR /Font` for both methods, as with
`--json-input`.

## Actual

    AcroForm is obj:198 0 R
    input:              ["/ArialNarrow","/ComicSansMS","/Consolas","/Consolas,Bold","/HeBo","/Helv","/KozGoPr6N-Medium","/ZaDb"]
    --update-from-json: ["/ArialNarrow","/ComicSansMS","/Consolas","/Consolas,Bold","/HeBo","/Helv","/KozGoPr6N-Medium","/ZaDb"] (qpdf exited 0)
    {"NeedAppearances":true}
    --json-input:       ["/ArialNarrow","/ComicSansMS","/Consolas","/Consolas,Bold","/HeBo","/HeOb","/Helv","/KozGoPr6N-Medium","/ZaDb"]

`/NeedAppearances` from the same update is there, so the object was
updated, but its `/DR` is the original. No warning is printed.

## What does and doesn't reproduce it

Each run used the script above, unchanged:

| Input | `/DR` change kept by `--update-from-json`? |
|---|---|
| The original file | **no** |
| `qpdf ORIG rewrite.pdf` (default options) | **no** |
| `qpdf ORIG --qdf rewrite.pdf` | **no** |
| `qpdf ORIG --object-streams=disable rewrite.pdf` | yes |
| A one-field form built by hand with `--json-input` | yes |
| The same one-field form with `--object-streams=generate` | yes |

Other changes to the same `/DR` were also lost on the original file:

- replacing `/DR` with a smaller dictionary;
- adding a key directly under `/DR`;
- setting `/DR` to `null`;
- deleting the `/DR` key.

In every case the output had the original `/DR`.

So it isn't simply object streams or the incremental update: the
`--qdf` rewrite has neither and still fails. What the failing inputs
share, and the `--object-streams=disable` rewrite lacks, hasn't been
found. An earlier, mistaken guess was that new objects can't be added
by an update. That was really this bug: the new font was referenced
from `/DR`.

## Workaround

Edit the full `--json-output=2` JSON and write it with `--json-input`,
as the script's last step does.
