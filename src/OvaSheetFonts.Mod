MODULE OvaSheetFonts; (* Text widths in the Noto Sans faces -S sets *)

(* The Ada Ova_Fmt.Sheet_Fonts: widths from the tables in
   OvaSheetWidths, so that the program, not groff, decides where a line
   breaks (PLAN.md, "-S: what goes where"), and the golden files fix
   it.

   Units are integers, so this port and the Ada version agree to the
   byte: a width in thousandths of an em times a size in tenths of a
   point is in ten-thousandths of a point. *)

IMPORT OvaSheetWidths;

CONST
  (* Not a character: a byte that doesn't start or continue a valid
     UTF-8 sequence, measured as an unmeasured character. *)
  Invalid = MAX(INTEGER);

(* The face's groff name: "NSR", "NSI", ... *)
PROCEDURE Name*(f: INTEGER; VAR name: ARRAY OF CHAR);
BEGIN
  CASE f OF
    OvaSheetWidths.Regular: COPY("NSR", name)
  | OvaSheetWidths.Italic: COPY("NSI", name)
  | OvaSheetWidths.LightItalic: COPY("NSLI", name)
  | OvaSheetWidths.Bold: COPY("NSB", name)
  | OvaSheetWidths.CondensedSemibold: COPY("NSCSB", name)
  END
END Name;

(* code's width in face f, in thousandths of an em; 1000, wider than
   any measured character, for one that wasn't measured.  ASCII 32 ..
   126 are the first 95 entries, Latin-1 160 .. 255 the next 96, then
   the extras. *)
PROCEDURE CharWidth*(code, f: INTEGER): INTEGER;
  VAR i: INTEGER;
BEGIN
  IF (code >= 32) & (code <= 126) THEN RETURN OvaSheetWidths.widths[f, code - 32]
  ELSIF (code >= 160) & (code <= 255) THEN RETURN OvaSheetWidths.widths[f, code - 65]
  END;
  FOR i := 0 TO OvaSheetWidths.NExtras - 1 DO
    IF OvaSheetWidths.extras[i] = code THEN RETURN OvaSheetWidths.widths[f, 191 + i] END
  END;
  RETURN 1000
END CharWidth;

(* The width of s[from .. to - 1], UTF-8, in face f, in thousandths of
   an em.  A byte that doesn't start or continue a valid sequence counts
   as an unmeasured character; control characters count nothing. *)
PROCEDURE TextWidth*(VAR s: ARRAY OF CHAR; from, to, f: INTEGER): INTEGER;
  VAR w, i, b, code, more: INTEGER;
BEGIN
  w := 0; i := from;
  WHILE i < to DO
    b := ORD(s[i]);
    IF b < 80H THEN code := b; more := 0
    ELSIF (b >= 0C2H) & (b <= 0DFH) THEN code := b - 0C0H; more := 1
    ELSIF (b >= 0E0H) & (b <= 0EFH) THEN code := b - 0E0H; more := 2
    ELSIF (b >= 0F0H) & (b <= 0F4H) THEN code := b - 0F0H; more := 3
    ELSE code := Invalid; more := 0
    END;
    INC(i);
    WHILE more > 0 DO
      IF (i < to) & (ORD(s[i]) >= 80H) & (ORD(s[i]) <= 0BFH) THEN
        code := code * 64 + ORD(s[i]) - 80H; INC(i); DEC(more)
      ELSE
        (* Cut short: the bytes read count as one character. *)
        code := Invalid; more := 0
      END
    END;
    IF code >= 32 THEN w := w + CharWidth(code, f) END
  END;
  RETURN w
END TextWidth;

(* s with ASCII letters in upper case, the faked small caps.  Only
   ASCII: Latin-1's upper case would change UTF-8's bytes. *)
PROCEDURE Upper*(VAR s: ARRAY OF CHAR);
  VAR i: INTEGER;
BEGIN
  i := 0;
  WHILE (i < LEN(s)) & (s[i] # 0X) DO
    IF (s[i] >= "a") & (s[i] <= "z") THEN s[i] := CHR(ORD(s[i]) - 32) END;
    INC(i)
  END
END Upper;

END OvaSheetFonts.
