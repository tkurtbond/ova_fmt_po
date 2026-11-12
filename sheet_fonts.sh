#!/usr/bin/env bash
# sheet_fonts.sh - build the Noto Sans faces that ova_fmt -S's troff
# names into a groff font directory, for `groff -F DIR -Tpdf`.
#
# Usage: sheet_fonts.sh [-n NOTO_DIR] [-g DEVPDF_DIR] DIR
#
#   -n NOTO_DIR    where NotoSans-*.ttf are; default $NOTO_DIR, else
#                  /usr/share/fonts/google-noto (the BSDs keep them
#                  under /usr/local/share/fonts)
#   -g DEVPDF_DIR  groff's own devpdf directory, for enc/text.enc and
#                  map/text.map; default found beside the groff on PATH
#   DIR            the font directory made; the faces go in DIR/devpdf
#
# gropdf in groff 1.23 can't read TrueType, so fontforge writes each
# face as Type 1 (.pfa, .afm), afmtodit writes groff's description of
# it, and a `download` file tells gropdf which file to embed. gropdf
# 1.23 embeds a whole font, about 900 KB for a Noto Sans face, so each
# face is first cut down to the Latin, spacing modifier (groff sets ^
# and ~ from them), combining, Greek (and the micro sign from it),
# punctuation, currency, letterlike, arrow and minus blocks, leaving
# about 260 KB. The widths ova_fmt measures with (Ova_Fmt.Sheet_Widths,
# from sheet_widths.sh) are taken from the faces this builds.
#
# The poc port (ova_fmt_po) has a copy of this script; keep them the same.

set -eu

prog=${0##*/}
noto=${NOTO_DIR:-/usr/share/fonts/google-noto}
devpdf=

usage() { echo "usage: $prog [-n NOTO_DIR] [-g DEVPDF_DIR] DIR" >&2; exit 2; }

while getopts n:g: opt; do
  case $opt in
    n) noto=$OPTARG ;;
    g) devpdf=$OPTARG ;;
    *) usage ;;
  esac
done
shift $((OPTIND - 1))
[ $# -eq 1 ] || usage
out=$1/devpdf

for tool in fontforge afmtodit groff; do
  command -v "$tool" >/dev/null || { echo "$prog: $tool not found" >&2; exit 1; }
done
if [ -z "$devpdf" ]; then
  bin=$(dirname "$(command -v groff)")
  for d in "$bin"/../share/groff/[0-9]*/font/devpdf "$bin"/../share/groff/current/font/devpdf; do
    [ -f "$d/enc/text.enc" ] && { devpdf=$d; break; }
  done
fi
[ -n "$devpdf" ] && [ -f "$devpdf/enc/text.enc" ] && [ -f "$devpdf/map/text.map" ] ||
  { echo "$prog: groff's devpdf directory not found; give it with -g" >&2; exit 1; }

mkdir -p "$out"
: >"$out/download.new"
# groff name, then the face's file name after "NotoSans-".
for face in NSR:Regular NSI:Italic NSLI:LightItalic NSB:Bold NSCSB:CondensedSemiBold; do
  name=${face%%:*} file=NotoSans-${face#*:}
  ttf=$noto/$file.ttf
  [ -f "$ttf" ] || { echo "$prog: $ttf not found" >&2; exit 1; }
  fontforge -quiet -lang=ff -c '
    Open($1)
    SelectNone()
    SelectMore(0u0020, 0u036f); SelectMore(0u0370, 0u03ff)
    SelectMore(0u1e00, 0u1eff); SelectMore(0u2000, 0u206f)
    SelectMore(0u20a0, 0u20cf); SelectMore(0u2100, 0u21ff)
    SelectMore(0u2212)
    SelectInvert(); Clear()
    Generate($2)' "$ttf" "$out/$file.pfa" 2>/dev/null
  # afmtodit warns that two glyphs (combining marks, spaces, micro and
  # mu) share a code; harmless.
  (cd "$out" && afmtodit -e "$devpdf/enc/text.enc" "$file.afm" "$devpdf/map/text.map" "$name" 2>&1 |
    grep -v -e ' and .* map to ' -e 'already mapped to' >&2 || true)
  rm -f "$out/$file.afm"
  # Noto names U+00AF's glyph overscore, not macron, so afmtodit gives
  # it only as u00AF, and troff, which reads an input macron as a-,
  # can't set one; make a- the same glyph.
  grep -q '^a-	' "$out/$name" ||
    sed -i '/^u00AF	/a a-	"' "$out/$name"
  # TAB-separated, with an empty foundry field first: a line separated
  # by spaces leaves the face unembedded.
  printf '\t%s\t%s\n' "$(sed -n 's/^internalname //p' "$out/$name")" "$file.pfa" >>"$out/download.new"
done
mv "$out/download.new" "$out/download"
