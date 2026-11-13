#!/usr/bin/env bash
# The official character sheet as PDF, end to end: -S -R and -S
# through ova_sheet.sh and -X through ova_form.sh, read back with
# pdftotext, pdfinfo, pdfimages, pdftoppm and qpdf (PLAN.md, "Build and
# tests").  The golden
# files fix the program's troff and JSON; this checks what becomes of
# them, so it doesn't fix the PDFs, which depend on the groff and qpdf
# versions.  Run from the repo root by `make test`, as
#
#   test/sheet.sh [program]
#
# with the faces sheet_fonts.sh builds in $SHEET_FONTS, or, if that
# hasn't all of them, built here, and the blank sheet $OVA_SHEET (it is
# Dyskami's, and isn't in the repo).  -S -R needs no blank sheet and no
# qpdf, so its checks run without them, and only -S's and -X's are
# skipped.  Prints ok/FAIL per check, as test/cli.sh does, and exits 1
# if any failed; without a tool it needs, it says what it skipped and
# exits 0.

prog=${1:-./ova_fmt_po}
data=test/data
sheet=${OVA_SHEET-}
fonts=${SHEET_FONTS:-build/font}
failed=0

skip() { echo "skip - sheet.sh: $*"; exit 0; }

for tool in groff pdftotext pdfinfo pdfimages pdftoppm; do
  command -v $tool >/dev/null 2>&1 || skip "$tool not found"
done

tmp=$(mktemp -d "${TMPDIR:-/tmp}/ova-sheet-test.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT

if [ ! -f "$fonts/devpdf/NSR" ] || [ ! -f "$fonts/devpdf/NSXCB" ]; then
  command -v fontforge >/dev/null 2>&1 || skip "no faces in $fonts, and no fontforge to build them"
  fonts=$tmp/font
  ./sheet_fonts.sh "$fonts" >"$tmp/fonts.log" 2>&1 || {
    echo "FAIL - sheet_fonts.sh"; sed 's/^/    /' "$tmp/fonts.log"; exit 1; }
fi

ok() { echo "ok   - $1"; }
finish() {
  if [ "$failed" -eq 0 ]; then echo "All checks passed."
  else echo "$failed check(s) failed."; exit 1
  fi
  exit 0
}
fail() { echo "FAIL - $1"; [ $# -lt 2 ] || printf '%s\n' "$2" | sed 's/^/    /'; failed=$((failed + 1)); }

# pages PDF: its page count.
pages() { pdfinfo "$1" 2>/dev/null | awk '$1 == "Pages:" { print $2 }'; }

# norm: standard input with all white space one blank, so that a line
# broken by groff or pdftotext still matches, and a right quote an
# apostrophe, as groff sets one.
norm() { tr -s ' \t\n\f' '    ' | sed "s/^ //; s/ \$//; s/\xe2\x80\x99/'/g"; }

# text PDF [FIRST [LAST]]: its text, or pages FIRST to LAST's, normalized.
text() {
  local f=$1 a=() ; [ $# -lt 2 ] || a=(-f "$2" -l "${3:-$2}")
  pdftotext -raw "${a[@]}" "$f" - 2>/dev/null | norm
  echo
}

# crop PDF PAGE X Y W H: the text inside that rectangle of PAGE, in
# points from the top left, normalized.
crop() {
  pdftotext -raw -f "$2" -l "$2" -x "$3" -y "$4" -W "$5" -H "$6" "$1" - 2>/dev/null | norm
  echo
}

# has TEXT NEEDLE: whether TEXT holds NEEDLE as a plain string.
has() { [[ $1 == *"$2"* ]]; }

# sheet NAME ARGS...: NAME.tr from prog -S ARGS, then NAME.pdf from
# ova_sheet.sh.  Fails the "NAME: builds" check if either fails.
sheet() {
  local name=$1; shift
  if ! "$prog" -S "$@" >"$tmp/$name.tr" 2>"$tmp/$name.err" </dev/null; then
    fail "$name: -S" "$(cat "$tmp/$name.err")"; return 1
  fi
  if ! ./ova_sheet.sh -s "$sheet" -F "$fonts" -o "$tmp/$name.pdf" "$tmp/$name.tr" \
       >"$tmp/$name.err" 2>&1; then
    fail "$name: ova_sheet.sh" "$(cat "$tmp/$name.err")"; return 1
  fi
  ok "$name: builds"
}

# placed NAME: every line of text NAME.tr places or sets, without its
# escapes, one per line: the lines after .L, and a continuation page's
# \& lines.
placed() {
  awk '/^\.L / { getline; if ($0 !~ /^\./) print; next } /^\\&/ { print }' "$tmp/$1.tr" |
    sed -E 's/\\[fsm]\[[^]]*\]//g; s/^\\&//; s/\\e/\\/g' |
    while IFS= read -r line; do printf '%s' "$line" | norm; echo; done | grep -v '^$'
}

# check_sheet NAME: NAME.pdf has a page per .SP, and more if there are
# .CP pages, and every line NAME.tr places is in its text.
check_sheet() {
  local name=$1 nsp ncp n all missing=
  nsp=$(grep -c '^\.SP ' "$tmp/$name.tr"); ncp=$(grep -c '^\.CP' "$tmp/$name.tr")
  n=$(pages "$tmp/$name.pdf")
  if { [ "$ncp" -eq 0 ] && [ "$n" -eq "$nsp" ]; } || { [ "$ncp" -gt 0 ] && [ "$n" -ge $((nsp + ncp)) ]; }; then
    ok "$name: $n pages for $nsp sheet pages and $ncp continuations"
  else
    fail "$name: $n pages for $nsp sheet pages and $ncp continuations"
  fi
  # The blank sheet under each sheet page, told by words printed on
  # only one of its pages, which no character's text runs together.
  # Blanks are dropped: -C's page 1 sets COMBAT NOTES as two words.
  local want1 want2 got1=0 got2=0 i t
  want1=$(grep -c '^\.SP p1' "$tmp/$name.tr"); want2=$(grep -c '^\.SP p2' "$tmp/$name.tr")
  for ((i = 1; i <= n; i++)); do
    t=$(text "$tmp/$name.pdf" $i); t=${t// /}
    ! has "$t" COMBATNOTES || got1=$((got1 + 1))
    ! has "$t" CHARACTERPORTRAIT || got2=$((got2 + 1))
  done
  if [ "$got1" -eq "$want1" ] && [ "$got2" -eq "$want2" ]; then
    ok "$name: $want1 pages over the sheet's page 1, $want2 over its page 2"
  else
    fail "$name: $got1 pages over the sheet's page 1 and $got2 over its page 2, not $want1 and $want2"
  fi
  all=$(text "$tmp/$name.pdf")
  while IFS= read -r line; do
    has "$all" "$line" || { missing=$line; break; }
  done < <(placed "$name")
  if [ -z "$missing" ]; then ok "$name: every line is in the PDF's text"
  else fail "$name: a line isn't in the PDF's text" "$missing"
  fi
}

# expect LABEL TEXT NEEDLE / expect_not LABEL TEXT NEEDLE
expect() { if has "$2" "$3"; then ok "$1"; else fail "$1" "no \"$3\" in: ${2:0:300}"; fi; }
expect_not() { if has "$2" "$3"; then fail "$1" "\"$3\" in: ${2:0:300}"; else ok "$1"; fi; }

# ---- -S -R, through ova_sheet.sh with no blank sheet ----

# qpdf, for the -R runs: a stub that leaves a mark and fails, so that a
# run that calls it shows.
mkdir "$tmp/stub"
printf '#!/bin/sh\ntouch "%s/qpdf-ran"\nexit 1\n' "$tmp" >"$tmp/stub/qpdf"
chmod +x "$tmp/stub/qpdf"

# redrawn NAME ARGS...: NAME.tr from prog -S -R ARGS, then NAME.pdf from
# ova_sheet.sh with no sheet and the qpdf stub.  Fails the "NAME:
# builds" check if either fails or qpdf ran.
redrawn() {
  local name=$1; shift
  if ! "$prog" -S -R "$@" >"$tmp/$name.tr" 2>"$tmp/$name.err" </dev/null; then
    fail "$name: -S -R" "$(cat "$tmp/$name.err")"; return 1
  fi
  rm -f "$tmp/qpdf-ran"
  if ! OVA_SHEET= PATH="$tmp/stub:$PATH" ./ova_sheet.sh -F "$fonts" -o "$tmp/$name.pdf" \
       "$tmp/$name.tr" >"$tmp/$name.err" 2>&1; then
    fail "$name: ova_sheet.sh" "$(cat "$tmp/$name.err")"; return 1
  fi
  if [ -e "$tmp/qpdf-ran" ]; then fail "$name: builds without qpdf"; return 1; fi
  ok "$name: builds with no blank sheet and no qpdf"
}

# images PDF [PAGE]: how many images it has, or PAGE has.
images() {
  local f=$1 a=() ; [ $# -lt 2 ] || a=(-f "$2" -l "$2")
  pdfimages -list "${a[@]}" "$f" 2>/dev/null | tail -n +3 | wc -l
}

# colour PDF PAGE X Y: the colour of the pixel at (X, Y) points from
# the top left of PAGE, at 72 dpi: white, grey (the sheet's panels),
# red (its tabs and frames), or "other R G B".
colour() {
  local rgb
  rgb=$(pdftoppm -r 72 -f "$2" -l "$2" -x "$3" -y "$4" -W 1 -H 1 -singlefile "$1" "$tmp/px" &&
        tail -c 3 "$tmp/px.ppm" | od -An -tu1)
  set -- $rgb
  if [ $# -ne 3 ]; then echo "unread"
  elif [ "$1" -ge 250 ] && [ "$2" -ge 250 ] && [ "$3" -ge 250 ]; then echo white
  elif [ "$1" -ge 225 ] && [ "$1" -le 245 ] && [ "$2" -ge 215 ] && [ "$2" -le 235 ] &&
       [ "$3" -ge 215 ] && [ "$3" -le 235 ]; then echo grey
  elif [ "$1" -ge 90 ] && [ "$1" -le 140 ] && [ "$2" -le 50 ] && [ "$3" -le 50 ]; then echo red
  else echo "other $1 $2 $3"
  fi
}

# For each: the pages and text, as for -S, the sheet's labels being
# drawn here; and no image, so nothing of the blank sheet.
for f in Fukiko Karis Vehicle edge-sheet-overflow edge-null-name; do
  if redrawn "R-$f" "$data/$f.yaml"; then
    check_sheet "R-$f"
    n=$(images "$tmp/R-$f.pdf")
    if [ "$n" -eq 0 ]; then ok "R-$f: no images"
    else fail "R-$f: $n image(s)"
    fi
  fi
done

# The frames, where the empty sheet has no text: page 1's red name
# banner, white boxes and grey panels; page 2's grey ground, red tab
# and portrait frame, and white boxes.
if [ -f "$tmp/R-edge-null-name.pdf" ]; then
  while read -r pg x y want what; do
    got=$(colour "$tmp/R-edge-null-name.pdf" "$pg" "$x" "$y")
    if [ "$got" = "$want" ]; then ok "R-edge-null-name: page $pg, $what is $want"
    else fail "R-edge-null-name: page $pg, $what is $got, not $want"
    fi
  done <<'END'
1 110 45 red the name banner
1 200 45 white the character name box
1 130 200 white the Abilities box
1 300 450 white the Combat Stats box
1 30 120 grey the left panel
1 400 450 grey the lower panel
1 5 590 white the page's corner
2 5 5 grey the ground
2 250 5 red the portrait's tab
2 239 200 red the portrait's frame
2 320 200 white the portrait box
2 100 100 white the Background box
END
fi

# The portrait: the only image, on the sheet's page 2.
if command -v magick >/dev/null 2>&1 || command -v convert >/dev/null 2>&1; then
  im=$(command -v magick || command -v convert)
  "$im" -size 60x90 xc:red "$tmp/me.png"
  if redrawn R-portrait -P "$tmp/me.png" "$data/Fukiko.yaml"; then
    pg=$(grep '^\.SP ' "$tmp/R-portrait.tr" | grep -n 'p2' | head -1 | cut -d: -f1)
    n=$(images "$tmp/R-portrait.pdf"); np=$(images "$tmp/R-portrait.pdf" "$pg")
    if [ "$n" -eq 1 ] && [ "$np" -eq 1 ]; then ok "R-portrait: the only image, on page $pg"
    else fail "R-portrait: $n images, $np of them on page $pg, not 1 there only"
    fi
  fi
else
  echo "skip - R-portrait: no ImageMagick"
fi

# ---- -S -R -C: page 1 as one column beside an Attacks & Combat Stats box ----

for f in Acacia Miho Karis edge-sheet-overflow edge-sheet-one-column edge-null-name; do
  if redrawn "C-$f" -C "$data/$f.yaml"; then
    check_sheet "C-$f"
  fi
done

# The frames: the column where -R has the gap between its two, the
# box's red title bar where -R has the Weaknesses, the box's white
# inside, and the grey panel where -R has the Combat Stats box's frame.
if [ -f "$tmp/C-edge-null-name.pdf" ]; then
  while read -r pg x y want what; do
    got=$(colour "$tmp/C-edge-null-name.pdf" "$pg" "$x" "$y")
    if [ "$got" = "$want" ]; then ok "C-edge-null-name: page $pg, $what is $want"
    else fail "C-edge-null-name: page $pg, $what is $got, not $want"
    fi
  done <<'END'
1 110 45 red the name banner
1 100 450 white the column
1 300 110 red the box's title bar
1 212 300 white the box
1 173 300 grey the gap between the column and the box
1 400 300 grey the right panel
2 250 5 red the portrait's tab
END
fi

# column NAME PAGE / box NAME PAGE / title NAME PAGE: the text of the
# column, the box under its title, or the box's title, on PAGE.
column() { crop "$tmp/$1.pdf" "$2" 34 104 137 462; }
box() { crop "$tmp/$1.pdf" "$2" 176 132 216 434; }
title() { crop "$tmp/$1.pdf" "$2" 176 104 216 27; }

if [ -f "$tmp/C-Acacia.pdf" ]; then
  t=$(column C-Acacia 1)
  if [[ $t == *Vigorous*Arrogant*Vulnerability* ]]; then
    ok "C-Acacia: the Weaknesses in the column, under the Abilities"
  else
    fail "C-Acacia: the Weaknesses aren't in the column under the Abilities" "${t:0:300}"
  fi
  # Her first copy of page 1's rules: those before the second .SP.
  n=$(awk '/^\.SP / && ++sp == 2 { exit } /^\.CR / { n++ } END { print n + 0 }' "$tmp/C-Acacia.tr")
  if [ "$n" -eq 1 ]; then ok "C-Acacia: one rule between them"
  else fail "C-Acacia: $n rules between them, not 1"
  fi
  expect "C-Acacia: the NPC type in the box's title" "$(title C-Acacia 1)" "(HEROIC)"
  expect_not "C-Acacia: no NPC type in the notes" "$(text "$tmp/C-Acacia.pdf" 1)" "NPC Type"
  expect "C-Acacia: an attack in the box" "$(box C-Acacia 1)" "Lock Heaven"
fi
if [ -f "$tmp/C-Miho.pdf" ]; then
  expect "C-Miho: the fifth attack on page 1" "$(box C-Miho 1)" "Mode SP: Miho Ray"
  n=$(grep -c '^\.SP p1' "$tmp/C-Miho.tr")
  if [ "$n" -eq 1 ]; then ok "C-Miho: one copy of page 1 for five attacks"
  else fail "C-Miho: $n copies of page 1 for five attacks, not 1"
  fi
fi
if [ -f "$tmp/C-edge-sheet-overflow.pdf" ]; then
  # The copies of page 1 come first: copy 2 is the PDF's page 2.
  t1=$(column C-edge-sheet-overflow 1); t2=$(column C-edge-sheet-overflow 2)
  if [[ $t1 == *"Ability Number 9"*"Weakness 4"* ]] && ! has "$t1" "Weakness 5" &&
     [[ $t2 == *"Weakness 5"*"Weakness 6"* ]] && ! has "$t2" "Ability Number"; then
    ok "C-edge-sheet-overflow: the Weaknesses go on from copy 1's column to copy 2's"
  else
    fail "C-edge-sheet-overflow: the Weaknesses don't go on from copy 1's column to copy 2's" \
      "copy 1: ${t1: -200}; copy 2: ${t2:0:200}"
  fi
fi
# More Abilities than a column holds: the Weaknesses start on copy 2,
# under the last of them, and the sixth attack is there too.
if [ -f "$tmp/C-edge-sheet-one-column.pdf" ]; then
  t1=$(column C-edge-sheet-one-column 1); t2=$(column C-edge-sheet-one-column 2)
  if [[ $t1 == *"Ability 35"* ]] && ! has "$t1" "Weakness" &&
     [[ $t2 == *"Ability 40"*"Weakness A"*"Weakness B"* ]]; then
    ok "C-edge-sheet-one-column: the Weaknesses start on copy 2, under the Abilities"
  else
    fail "C-edge-sheet-one-column: the Weaknesses don't start on copy 2 under the Abilities" \
      "copy 1: ${t1: -200}; copy 2: ${t2:0:200}"
  fi
  expect "C-edge-sheet-one-column: the sixth attack on copy 2" "$(box C-edge-sheet-one-column 2)" "Attack 6"
  expect_not "C-edge-sheet-one-column: five attacks on copy 1" "$(box C-edge-sheet-one-column 1)" "Attack 6"
fi

# ---- The rest needs the blank sheet, qpdf and jq ----

for tool in qpdf jq; do
  command -v $tool >/dev/null 2>&1 || { echo "skip - -S and -X: $tool not found"; finish; }
done
[ -n "$sheet" ] || { echo "skip - -S and -X: no blank sheet: set OVA_SHEET"; finish; }
[ -r "$sheet" ] || { echo "skip - -S and -X: can't read the blank sheet $sheet"; finish; }

# ---- -S, through ova_sheet.sh ----

for f in Fukiko Miho Karis Sheet Vehicle Fragment Auren Escaping edge-sheet-overflow edge-sheet-sub; do
  sheet "$f" "$data/$f.yaml" && check_sheet "$f"
done

# Miho's Transformation grants a Weakness, set in the Abilities column
# under the Transformation, not among her own Weaknesses.  The columns
# split at the page's middle; the rows run from 110 pt to 330 pt.
if [ -f "$tmp/Miho.pdf" ]; then
  expect "Miho: the granted Weakness is in the Abilities column" \
    "$(crop "$tmp/Miho.pdf" 1 0 110 210 220)" "Loss of Control"
  expect_not "Miho: the granted Weakness isn't in the Weaknesses column" \
    "$(crop "$tmp/Miho.pdf" 1 210 110 210 220)" "Loss of Control"
fi

# 18 Abilities and a fifth attack: a second copy of page 1, taking the
# rows past the 17th (sorted, so "Ability Number 9" is the last).  Its
# long name is cut on the copy.
if [ -f "$tmp/edge-sheet-overflow.pdf" ]; then
  expect_not "edge-sheet-overflow: the last rows aren't on page 1" \
    "$(text "$tmp/edge-sheet-overflow.pdf" 1)" "Ability Number 9"
  expect "edge-sheet-overflow: they're on the copy" \
    "$(text "$tmp/edge-sheet-overflow.pdf" 2)" "Ability Number 9"
  expect "edge-sheet-overflow: the fifth attack is on the copy" \
    "$(text "$tmp/edge-sheet-overflow.pdf" 2)" "$(awk '/^\.SP/ { n++ } n == 2 && /ovared/ { print; exit }' \
       "$tmp/edge-sheet-overflow.tr" | sed -E 's/\\[fsm]\[[^]]*\]//g')"
fi

# A block that doesn't fit what's left of the column moves whole; one
# taller than the column is split, and goes on under "(continued)".
# The name is outside WinAnsi.
if [ -f "$tmp/edge-sheet-sub.pdf" ]; then
  p1=$(text "$tmp/edge-sheet-sub.pdf" 1); p2=$(text "$tmp/edge-sheet-sub.pdf" 2)
  p3=$(text "$tmp/edge-sheet-sub.pdf" 3)
  expect "edge-sheet-sub: a name outside WinAnsi survives" "$p1" "Ōtori Łukasz"
  expect "edge-sheet-sub: page 1 holds the plain rows" "$p1" "Plain Ability 13"
  expect_not "edge-sheet-sub: the block that doesn't fit isn't on page 1" "$p1" "Moving Block"
  expect "edge-sheet-sub: it moves whole to the next copy" "$p2" "Transformation (Moving Block) +1 Moved Ability 1"
  expect "edge-sheet-sub: all of it" "$p2" "Moved Ability 5"
  expect "edge-sheet-sub: the tall block starts on the same copy" "$p2" "Split Ability 01"
  expect_not "edge-sheet-sub: and is split" "$p2" "Split Ability 11"
  expect "edge-sheet-sub: going on under (continued)" "$p3" "Unique Ability (Split Block) (continued)"
  expect "edge-sheet-sub: to its end" "$p3" "Split Ability 20"
fi

# Karis's Companion has a copy of page 1 of its own, after Karis's.
if [ -f "$tmp/Karis.pdf" ]; then
  expect_not "Karis: page 1 is Karis's own" "$(crop "$tmp/Karis.pdf" 1 0 30 420 30)" "Arasuni"
  expect "Karis: page 2 is Arasuni's" "$(crop "$tmp/Karis.pdf" 2 0 30 420 30)" "Arasuni (Karis's Companion)"
fi

# Two characters, one PDF: each one's pages in turn.
if [ -f "$tmp/Karis.pdf" ] && [ -f "$tmp/Fukiko.pdf" ] && sheet two "$data/Karis.yaml" "$data/Fukiko.yaml"; then
  check_sheet two
  nk=$(pages "$tmp/Karis.pdf"); nf=$(pages "$tmp/Fukiko.pdf"); n=$(pages "$tmp/two.pdf")
  if [ "$n" -eq $((nk + nf)) ]; then ok "two: Karis's $nk pages and Fukiko's $nf"
  else fail "two: $n pages, not Karis's $nk and Fukiko's $nf"
  fi
  expect "two: Fukiko's sheet follows Karis's" "$(crop "$tmp/two.pdf" $((nk + 1)) 0 30 420 30)" "Fukiko"
fi

# The portrait: -P's image lands on the sheet's page 2, beside the
# sheet's own images.
if command -v magick >/dev/null 2>&1 || command -v convert >/dev/null 2>&1; then
  im=$(command -v magick || command -v convert)
  "$im" -size 60x90 xc:red "$tmp/me.png"
  if sheet portrait -P "$tmp/me.png" "$data/Fukiko.yaml" && [ -f "$tmp/Fukiko.pdf" ]; then
    pg=$(grep '^\.SP ' "$tmp/portrait.tr" | grep -n 'p2' | head -1 | cut -d: -f1)
    without=$(pdfimages -list -f "$pg" -l "$pg" "$tmp/Fukiko.pdf" | tail -n +3 | wc -l)
    with=$(pdfimages -list -f "$pg" -l "$pg" "$tmp/portrait.pdf" | tail -n +3 | wc -l)
    if [ "$with" -gt "$without" ]; then ok "portrait: on page $pg, the sheet's page 2"
    else fail "portrait: page $pg has $with images, and $without without it"
    fi
  fi
else
  echo "skip - portrait: no ImageMagick"
fi

# ---- -X, through ova_form.sh ----

# form NAME FILES...: NAME.json from prog -X, NAME.pdf from ova_form.sh;
# jq must accept the JSON, the PDF must have a page per page of each
# fill, and every field's value must read back from it (a copy's field
# is renamed "Background+1" and so on when the copies are joined).
form() {
  local name=$1; shift
  if ! "$prog" -X "$@" >"$tmp/$name.json" 2>"$tmp/$name.err" </dev/null; then
    fail "$name: -X" "$(cat "$tmp/$name.err")"; return
  fi
  if jq -e . "$tmp/$name.json" >/dev/null 2>"$tmp/$name.err"; then ok "$name: jq reads the JSON"
  else fail "$name: jq reads the JSON" "$(cat "$tmp/$name.err")"; return
  fi
  if ! ./ova_form.sh -s "$sheet" -o "$tmp/$name.pdf" "$tmp/$name.json" >"$tmp/$name.err" 2>&1; then
    fail "$name: ova_form.sh" "$(cat "$tmp/$name.err")"; return
  fi
  local want n
  want=$(jq '[.[][] | .pages | length] | add' "$tmp/$name.json"); n=$(pages "$tmp/$name.pdf")
  if [ "$n" -eq "$want" ]; then ok "$name: $n pages"
  else fail "$name: $n pages, not $want"
  fi
  qpdf --json --json-key=acroform "$tmp/$name.pdf" >"$tmp/$name.acro.json" 2>"$tmp/$name.err" || {
    fail "$name: qpdf reads the form" "$(cat "$tmp/$name.err")"; return; }
  local missing
  missing=$(jq -r --slurpfile have "$tmp/$name.acro.json" '
      ([$have[0].acroform.fields[] | select(.value != null)
        | [(.fullname | sub("\\+[0-9]+$"; "")), (.value | sub("^u:"; ""))]]) as $h
      | [.[][] | .fields | to_entries[] | [.key, .value]] - $h
      | .[] | "\(.[0]): \(.[1])"' "$tmp/$name.json")
  if [ -z "$missing" ]; then ok "$name: every value reads back"
  else fail "$name: values that don't read back" "$missing"
  fi
}

for f in Escaping Fukiko Karis Vehicle edge-sheet-overflow edge-sheet-sub; do
  form "form-$f" "$data/$f.yaml"
done
form form-two "$data/Karis.yaml" "$data/Fukiko.yaml"

finish
