#!/bin/sh
# ova_form.sh - fill the official OVA character sheet's PDF form from
# the JSON fills that `ova_fmt -X` (or `ova_fmt_po -X`) writes.
#
# Usage: ova_form.sh [-s SHEET] [-o OUT.pdf] [-k] [FILE.json]
#
#   -s SHEET   the blank, form-fillable sheet; default $OVA_SHEET
#   -o OUT.pdf the output; default FILE with .json replaced by .pdf
#              (needed when the JSON comes from standard input)
#   -k         keep the work directory, for debugging
#
# Each fill becomes a copy of the sheet, filled with qpdf's JSON round
# trip: the fields are given their values and restyled in the PDF
# standard Helvetica faces, their appearances are dropped and
# /NeedAppearances is set, so the reader draws them and the form stays
# editable. The copies are then joined, each character in turn: every
# fill with page 1, then every fill with page 2. The portrait isn't
# filled. See the poc port's PLAN.md, "The form script, ova_form.sh".
#
# The copies in ova_fmt and ova_fmt_po must stay the same.

prog=ova_form.sh
sheet=${OVA_SHEET-}
out=
keep=false

usage() {
    echo "usage: $prog [-s SHEET] [-o OUT.pdf] [-k] [FILE.json]" >&2
    exit 1
}

while getopts s:o:k opt; do
    case $opt in
        s) sheet=$OPTARG ;;
        o) out=$OPTARG ;;
        k) keep=true ;;
        *) usage ;;
    esac
done
shift $((OPTIND - 1))
[ $# -le 1 ] || usage
in=${1--}
name=$in
[ "$in" != - ] || name="standard input"

die() {
    echo "$prog: $*" >&2
    exit 1
}

for tool in qpdf jq; do
    command -v $tool >/dev/null 2>&1 || die "$tool not found"
done
[ -n "$sheet" ] || die "no sheet: give -s SHEET or set OVA_SHEET"
[ -r "$sheet" ] || die "can't read the sheet $sheet"
if [ -z "$out" ]; then
    [ "$in" != - ] || die "-o OUT.pdf is needed when reading standard input"
    out=${in%.json}.pdf
fi

work=$(mktemp -d "${TMPDIR:-/tmp}/ova_form.XXXXXX") || die "can't make a work directory"
if $keep; then
    echo "$prog: work directory $work" >&2
else
    trap 'rm -rf "$work"' EXIT
    trap 'exit 1' HUP INT TERM
fi

# qpdf exits 3 for warnings only: they are passed on, and the run goes on.
run_qpdf() {
    qpdf "$@"
    status=$?
    [ $status -eq 0 ] || [ $status -eq 3 ] || die "qpdf failed (exit $status)"
}

if [ "$in" = - ]; then
    cat >"$work/fills.json" || die "can't read standard input"
else
    cp "$in" "$work/fills.json" || die "can't read $in"
fi
jq -e 'type == "array"' "$work/fills.json" >/dev/null 2>&1 ||
    die "$name: not a JSON array of fills"

cat >"$work/restyle.jq" <<'EOF'
# $v[0] is one fill: {"pages": [...], "sub": [...], "fields": {...}}.
def obj: if type == "object" then . else {} end;
# A field's name, from its /T ("u:Ability 1"); null if it has none.
def t: (.value | obj | .value | obj | ."/T") as $x
       | if ($x | type) == "string" then $x[2:] else null end;
def red: "0.47 0.11 0.13 rg";
def da($n; $sub):
  if   ($n | test("^(Ability|Weakness) [0-9]+$")) then
         if ($sub | index($n)) != null then "/HeOb 7 Tf 0 g" else "/HeOb 8 Tf 0 g" end
  elif ($n | test("Dice")) then "/Helv 8 Tf 0 g"
  elif ($n | test("^Attack [0-9]$")) then "/HeBo 8 Tf " + red
  elif ($n | test("^Attack Description")) then "/HeBo 7 Tf 0 g"
  elif ($n | test("^(roll|dx|end)")) then "/HeBo 0 Tf 0 g"
  elif ($n | test("^(Defense|Health|Endurance|TV)$")) then "/HeBo 18 Tf 0 g"
  elif $n == "Character Name" then "/Helv 12 Tf 0 g"
  elif $n == "Combat Notes" then "/Helv 6 Tf 0 g"
  elif $n == "Portrait" then null
  else "/Helv 8 Tf 0 g" end;
($v[0].fields) as $vals |
($v[0].sub) as $sub |
# A free object number for Helvetica-Oblique.
((.qpdf[1] | keys | map(select(startswith("obj:")) | .[4:] | split(" ")[0] | tonumber)
  | max + 1 | tostring) + " 0 R") as $heob |
{qpdf: [ .qpdf[0],
  ((.qpdf[1] | with_entries(
       if (.value | obj | .value | obj | has("/Fields")) then
         .value.value["/NeedAppearances"] = true
         | .value.value["/DR"]["/Font"]["/HeOb"] = $heob
       else t as $n | if $n == null then . else .
         | (if da($n; $sub) then .value.value["/DA"] = "u:" + da($n; $sub) else . end)
         | (if $vals[$n] != null then .value.value["/V"] = "u:" + $vals[$n] else . end)
         | del(.value.value["/AP"]) end end))
   + {("obj:" + $heob): {value: {"/Type": "/Font", "/Subtype": "/Type1",
                                 "/BaseFont": "/Helvetica-Oblique",
                                 "/Encoding": "38 0 R", "/Name": "/HeOb"}}}) ]}
EOF

run_qpdf --json-output=2 "$sheet" "$work/blank.json"

# The pages to join, as qpdf --pages arguments, one per line.
: >"$work/pages"
entities=$(jq length "$work/fills.json")
part=0
e=0
while [ $e -lt "$entities" ]; do
    fills=$(jq --argjson e $e '.[$e] | length' "$work/fills.json")
    : >"$work/p1"
    : >"$work/p2"
    f=0
    while [ $f -lt "$fills" ]; do
        jq --argjson e $e --argjson f $f '.[$e][$f]' "$work/fills.json" >"$work/fill-$part.json"
        jq --slurpfile v "$work/fill-$part.json" -f "$work/restyle.jq" \
           "$work/blank.json" >"$work/filled-$part.json" || die "jq failed on fill $part"
        run_qpdf --json-input "$work/filled-$part.json" "$work/part-$part.pdf"
        for p in $(jq -r '.pages[]' "$work/fill-$part.json"); do
            printf '%s\n%s\n' "$work/part-$part.pdf" "$p" >>"$work/p$p"
        done
        part=$((part + 1))
        f=$((f + 1))
    done
    cat "$work/p1" "$work/p2" >>"$work/pages"
    e=$((e + 1))
done

[ $part -gt 0 ] || die "$name: no fills"

set --
while read -r file && read -r page; do
    set -- "$@" "$file" "$page"
done <"$work/pages"
run_qpdf --empty --pages "$@" -- "$out"
exit 0
