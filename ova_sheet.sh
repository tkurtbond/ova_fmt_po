#!/bin/sh
# ova_sheet.sh - typeset the troff that `ova_fmt -S` (or `ova_fmt_po
# -S`) writes over the official OVA character sheet, as a PDF.
#
# Usage: ova_sheet.sh [-s SHEET] [-F FONTDIR] [-o OUT.pdf] [-k] [FILE.tr]
#
#   -s SHEET    the blank sheet; default $OVA_SHEET (not needed for
#               ova_fmt -S -R)
#   -F FONTDIR  the font directory sheet_fonts.sh built; default
#               $OVA_SHEET_FONTS
#   -o OUT.pdf  the output; default FILE with .tr replaced by .pdf
#               (needed when the troff comes from standard input)
#   -k          keep the work directory, for debugging
#
# The groff run is $GROFF, default groff. gropdf before groff 1.24
# embeds each Noto face whole, which makes a sheet about 2.4 MB; 1.24
# and later embed only the glyphs used, for about 1.7 MB (the blank
# sheet itself is 1.2 MB), and set the same pages.
#
# groff (1.23 or later, for gropdf's -p) typesets the text alone, at
# the sheet's A5 size. Each page of the sheet reports itself on
# groff's standard error as "ova-sheet-page N p1" (or p2), and qpdf
# lays that page of the sheet, its form flattened, under page N. The
# continuation pages are left plain.
#
# Troff from `ova_fmt -S -R` draws the sheet itself, and says so in a
# comment line, `.\" ova-sheet-redrawn`; then no sheet is needed, and
# none is laid under it. Its labels need the font directory's NSXCB.
#
# gropdf embeds only PDF, so each portrait the troff names (a comment
# line, `.\" ova-sheet-portrait N W H PATH`, W and H the box's size in
# points) is first made a PDF of the box's shape, the image centred
# on white, with ImageMagick; a PDF portrait is used as it is, at the
# box's top left. A portrait that can't be read or converted is left
# out, with a warning. See the poc port's PLAN.md, "The sheet script,
# ova_sheet.sh".
#
# The copies in ova_fmt and ova_fmt_po must stay the same.

prog=ova_sheet.sh
groff=${GROFF:-groff}
sheet=${OVA_SHEET-}
fonts=${OVA_SHEET_FONTS-}
out=
keep=false

usage() {
    echo "usage: $prog [-s SHEET] [-F FONTDIR] [-o OUT.pdf] [-k] [FILE.tr]" >&2
    exit 1
}

while getopts s:F:o:k opt; do
    case $opt in
        s) sheet=$OPTARG ;;
        F) fonts=$OPTARG ;;
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

command -v "$groff" >/dev/null 2>&1 || die "$groff not found"
[ -n "$fonts" ] || die "no font directory: give -F FONTDIR or set OVA_SHEET_FONTS"
[ -f "$fonts/devpdf/NSR" ] || die "$fonts/devpdf has no NSR: build it with sheet_fonts.sh"
if [ -z "$out" ]; then
    [ "$in" != - ] || die "-o OUT.pdf is needed when reading standard input"
    out=${in%.tr}.pdf
fi

work=$(mktemp -d "${TMPDIR:-/tmp}/ova_sheet.XXXXXX") || die "can't make a work directory"
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
    cat >"$work/sheet.tr" || die "can't read standard input"
else
    cp "$in" "$work/sheet.tr" || die "can't read $in"
fi

redrawn=false
if grep -q '^\.\\" ova-sheet-redrawn$' "$work/sheet.tr"; then redrawn=true; fi
if $redrawn; then
    [ -f "$fonts/devpdf/NSXCB" ] || die "$fonts/devpdf has no NSXCB: rebuild it with sheet_fonts.sh"
else
    command -v qpdf >/dev/null 2>&1 || die "qpdf not found"
    [ -n "$sheet" ] || die "no sheet: give -s SHEET or set OVA_SHEET"
    [ -r "$sheet" ] || die "can't read the sheet $sheet"
fi

# The sheet's form fields are empty, but would still draw their
# borders and highlights, and take clicks, over the text.
$redrawn || run_qpdf --flatten-annotations=all --remove-restrictions "$sheet" "$work/blank.pdf"

warn() {
    echo "$prog: $*" >&2
}

# Each portrait as portrait-N.pdf, named to groff as ova-portrait-N.
# A relative PATH is from the current directory, as the program wrote
# it; groff then runs in the work directory, so the names have no
# spaces in them.
magick=
for tool in magick convert; do
    if command -v $tool >/dev/null 2>&1; then magick=$tool; break; fi
done
set --
grep '^\.\\" ova-sheet-portrait ' "$work/sheet.tr" >"$work/portraits"
while read -r _ _ n w h path; do
    pdf=portrait-$n.pdf
    if [ ! -r "$path" ]; then
        warn "can't read the portrait $path; left out"
        continue
    fi
    case $path in
        *.pdf | *.PDF)
            cp "$path" "$work/$pdf" || { warn "can't copy $path; left out"; continue; } ;;
        *)
            if [ -z "$magick" ]; then
                warn "ImageMagick not found, so the portrait $path is left out"
                continue
            fi
            # The box at 300 dpi.
            px=$(awk -v w="$w" -v h="$h" 'BEGIN { printf "%dx%d", w * 300 / 72 + 0.5, h * 300 / 72 + 0.5 }')
            $magick "$path[0]" -background white -alpha remove -alpha off \
                -resize "$px" -gravity center -extent "$px" \
                -units PixelsPerInch -density 300 -compress jpeg -quality 92 \
                "$work/$pdf" || { warn "can't convert the portrait $path; left out"; continue; } ;;
    esac
    set -- "$@" -d "ova-portrait-$n=$pdf"
done <"$work/portraits"

case $fonts in
    /*) ;;
    *) fonts=$PWD/$fonts ;;
esac
(cd "$work" && "$groff" -k -Tpdf -F "$fonts" -P-p595.276p,419.528p "$@" sheet.tr \
    >text.pdf 2>groff.err) || {
    cat "$work/groff.err" >&2
    die "groff failed on $name"
}
# Passed on but for the page lines and newer gropdf's notice for each
# font it subsets: "gropdf: notice: ", two lines about it, and a blank.
awk '/^gropdf: notice: *$/ { skip = 4 }
     skip > 0 { skip--; next }
     $1 != "ova-sheet-page"' "$work/groff.err" >&2

# The --to page lists, "1,4" for the pages over page 1 of the sheet.
pages() {
    awk -v k="$1" '$1 == "ova-sheet-page" && $3 == k {
                       printf "%s%s", s, $2; s = "," }' "$work/groff.err"
}
p1=$(pages p1)
p2=$(pages p2)
[ -n "$p1$p2" ] || die "$name: no sheet pages (is it ova_fmt -S output?)"

if $redrawn; then
    cp "$work/text.pdf" "$out" || die "can't write $out"
    exit 0
fi

set --
[ -z "$p1" ] || set -- "$@" --underlay "$work/blank.pdf" --to="$p1" --from= --repeat=1 --
[ -z "$p2" ] || set -- "$@" --underlay "$work/blank.pdf" --to="$p2" --from= --repeat=2 --
run_qpdf "$work/text.pdf" "$@" "$out"
exit 0
