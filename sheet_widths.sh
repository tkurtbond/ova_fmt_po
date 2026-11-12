#!/usr/bin/env bash
# sheet_widths.sh - write the character widths ova_fmt -S measures
# with, as the Ada spec Ova_Fmt.Sheet_Widths (or, with -O, the poc
# port's Oberon module OvaSheetWidths), to standard output.
#
# Usage: sheet_widths.sh [-O] FONTDIR
#
# FONTDIR is what sheet_fonts.sh built. groff itself reports each
# width (`\w` at 1 point, which on devpdf, at 72000 units an inch, is
# thousandths of an em), so the tables hold exactly what gropdf sets,
# whatever glyph groff maps an input character to. They are built into
# the program, not read at run time, so that the golden files don't
# depend on the installed groff (the poc port's PLAN.md, "Open
# questions"). Regenerate them only when the fonts change.
#
# The poc port (ova_fmt_po) has a copy of this script; keep them the same.

set -eu

prog=${0##*/}
lang=ada
if [ "${1-}" = -O ]; then lang=oberon; shift; fi
[ $# -eq 1 ] || { echo "usage: $prog [-O] FONTDIR" >&2; exit 2; }
fontdir=$1

faces="NSR NSI NSLI NSB NSCSB"
# Beyond ASCII 32..126 and Latin-1 160..255: the minus sign, dashes,
# quotes, ellipsis, trade mark, bullet, and the macron vowels of
# romanized Japanese names.
extras="2212 2013 2014 2018 2019 201C 201D 2026 2122 2022 014C 014D 016A 016B"

codes() {
  seq 32 126
  seq 160 255
  for x in $extras; do printf '%d\n' "0x$x"; done
}

# widths FACE: one width per code, in codes' order.
widths() {
  {
    printf '.ft %s\n.ps 1\n' "$1"
    for c in $(codes); do
      if [ "$c" = 92 ]; then ch='\e'; else ch=$(printf "\\U$(printf %08x "$c")"); fi
      if [ "$c" = 64 ]; then d="'"; else d=@; fi
      printf '.nr w \\w%s%s%s\n.tm \\nw\n' "$d" "$ch" "$d"
    done
  } | groff -k -Tpdf -F "$fontdir" -z 2>&1
}

# list ITEMS...: comma-separated, $per to a line, indented by $indent.
per=13
list() {
  printf '%s\n' "$@" | awk -v ind="$indent" -v per="$per" '
    { a[NR] = $0 }
    END { for (i = 1; i <= NR; i++) {
            if ((i - 1) % per == 0) printf "%s%s", (i > 1 ? "\n" : ""), ind
            else printf " "
            printf "%s%s", a[i], (i < NR ? "," : "") }
          print "" }'
}

for f in $faces; do
  [ -f "$fontdir/devpdf/$f" ] || { echo "$prog: no $f in $fontdir/devpdf; run sheet_fonts.sh" >&2; exit 1; }
  if widths "$f" | grep -qv '^[0-9]*$'; then
    echo "$prog: groff warned measuring $f:" >&2; widths "$f" | grep -v '^[0-9]*$' >&2; exit 1
  fi
done
n=$(codes | wc -l)
ne=$(echo $extras | wc -w)

if [ $lang = ada ]; then
  cat <<EOF
--  Ova_Fmt.Sheet_Widths - the widths of the characters -S measures, in
--  each Noto Sans face it sets, in thousandths of an em. Written by
--  sheet_widths.sh from the faces sheet_fonts.sh builds; don't edit.
--  Ova_Fmt.Sheet_Fonts looks them up.

package Ova_Fmt.Sheet_Widths is

   --  NSR, NSI, NSLI, NSB, NSCSB to groff.
   type Face is (Regular, Italic, Light_Italic, Bold, Condensed_Semibold);

   --  The characters measured: ASCII 32 .. 126, Latin-1 160 .. 255,
   --  then Extras, in that order.
   Count : constant := $n;

   type Code_List is array (Positive range <>) of Natural;

   Extras : constant Code_List (1 .. $ne) :=
EOF
  indent='     (' per=7
  list $(for x in $extras; do printf '16#%s#\n' "$x"; done) | sed '2,$s/^     (/      /'
  echo '      );'
  per=13
  cat <<EOF

   type Width_List is array (1 .. Count) of Natural;

   Widths : constant array (Face) of Width_List :=
EOF
  i=0
  for f in $faces; do
    i=$((i + 1))
    case $f in NSR) face=Regular;; NSI) face=Italic;; NSLI) face=Light_Italic;;
               NSB) face=Bold;; NSCSB) face=Condensed_Semibold;; esac
    printf '     %s%s =>\n' "$([ $i = 1 ] && echo '(' || echo ' ')" "$face"
    indent='         '
    list $(widths "$f") | sed '1s/^         /        (/'
    printf '        )%s\n' "$([ $i = 5 ] && echo ');' || echo ',')"
  done
  echo
  echo 'end Ova_Fmt.Sheet_Widths;'
else
  cat <<EOF
MODULE OvaSheetWidths; (* the widths of the characters -S measures *)

(* The Ada Ova_Fmt.Sheet_Widths: in each Noto Sans face -S sets, in
   thousandths of an em.  Written by sheet_widths.sh -O from the faces
   sheet_fonts.sh builds; don't edit.  OvaSheetFonts looks them up.
   They are filled at initialization from strings of numbers, since a
   string literal holds at most 255 characters. *)

CONST
  (* The faces: NSR, NSI, NSLI, NSB, NSCSB to groff. *)
  Regular* = 0; Italic* = 1; LightItalic* = 2; Bold* = 3; CondensedSemibold* = 4;
  Faces* = 5;

  (* The characters measured: ASCII 32 .. 126, Latin-1 160 .. 255,
     then extras, in that order. *)
  Count* = $n;
  NExtras* = $ne;

VAR
  extras-: ARRAY NExtras OF INTEGER;
  widths-: ARRAY Faces, Count OF INTEGER;

(* The widths in s, decimal numbers separated by blanks, into t from
   t[at]. *)
PROCEDURE Put(VAR t: ARRAY OF INTEGER; at: INTEGER; s: ARRAY OF CHAR);
  VAR i, v: INTEGER;
BEGIN
  i := 0;
  WHILE s[i] # 0X DO
    WHILE s[i] = " " DO INC(i) END;
    v := 0;
    WHILE (s[i] >= "0") & (s[i] <= "9") DO v := v * 10 + ORD(s[i]) - ORD("0"); INC(i) END;
    t[at] := v; INC(at)
  END;
  ASSERT(at <= LEN(t))
END Put;

BEGIN
EOF
  i=0
  for x in $extras; do
    printf '  extras[%d] := %sH;\n' $i "$(printf %s "$x" | sed 's/^[A-F]/0&/')"
    i=$((i + 1))
  done
  i=0
  for f in $faces; do
    widths "$f" | awk -v f=$i -v per=$per '
      { a[NR - 1] = $0 }
      END { for (k = 0; k < NR; k += per) {
              s = ""
              for (j = k; j < k + per && j < NR; j++) s = s (j > k ? " " : "") a[j]
              printf "  Put(widths[%d], %d, \"%s\");\n", f, k, s } }'
    i=$((i + 1))
  done
  echo 'END OvaSheetWidths.'
fi
