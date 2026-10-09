MODULE OvaText; (* What this program needs of text that Ropes doesn't have *)

(* Every string in this program is a Ropes.Rope, and callers use Ropes
   directly for whatever it provides.  This module adds only what it
   lacks, in the forms the Ada version's output depends on: decimal
   integers, its trimming and its Latin-1 case mapping (Ropes' own
   differ: see Trim, Lower and Upper), a growable list of ropes with
   Join, and a flat copy for the few procedures that take an ARRAY OF
   CHAR.  The same shape as pobesm2_fmt2's Besm2Text, trimmed to what
   ova_fmt uses.

   The empty rope is NIL, so "" and "absent" can't be told apart by the
   rope alone: optional fields carry their own has-flags (OvaEntities).
   Lengths are in bytes, as the Ada version's are. *)

IMPORT Ropes;

TYPE
  Rope* = Ropes.Rope;

  (* A flat, 0X-terminated copy of a rope: see Chars. *)
  String* = POINTER TO ARRAY OF CHAR;

  Items* = POINTER TO ARRAY OF Rope;

  (* A growable list of ropes: items[0 .. n-1], any of which may be NIL
     (the empty rope).  Clear a List before its first use. *)
  List* = RECORD
    items-: Items;
    n-: INTEGER
  END;

VAR
  (* The characters Trim strips. *)
  blanks: Ropes.CharSet;

(* ---- Building ---- *)

(* Appends the text of s, up to its first 0X, to r.  r must have been
   set before (to NIL, for a rope being built up). *)
PROCEDURE Add*(VAR r: Rope; s: ARRAY OF CHAR);
BEGIN r := Ropes.Cat(r, Ropes.FromString(s))
END Add;

(* i in decimal, with a leading "-" if negative and no blanks: the Ada
   version's Trim (Integer'Image (i), Left). *)
PROCEDURE Int*(i: INTEGER): Rope;
  VAR digits: ARRAY 12 OF CHAR; n: INTEGER; u: LONGINT;
BEGIN
  (* INTEGER is 32 bits and LONGINT 64 under -OC, so -u can't overflow
     even for MIN(INTEGER).  The digits are written from the end of the
     array: 11 at most, with the sign. *)
  u := i;
  IF u < 0 THEN u := -u END;
  n := LEN(digits);
  REPEAT
    DEC(n); digits[n] := CHR(ORD("0") + SHORT(u MOD 10)); u := u DIV 10
  UNTIL u = 0;
  IF i < 0 THEN DEC(n); digits[n] := "-" END;
  RETURN Ropes.FromSubstring(digits, n, LEN(digits) - n)
END Int;

(* Appends i, as Int writes it, to r. *)
PROCEDURE AddInt*(VAR r: Rope; i: INTEGER);
BEGIN r := Ropes.Cat(r, Int(i))
END AddInt;

(* ---- Trimming ---- *)

(* r without leading and trailing blanks, tabs, line feeds and carriage
   returns: the Ada Trim_Whitespace.  Not just blanks, because a YAML
   literal block scalar ("background: |") ends with a newline.  Not
   Ropes.Trim, which strips form feeds too. *)
PROCEDURE Trim*(r: Rope): Rope;
  VAR first, last: LONGINT;
BEGIN
  first := Ropes.IndexSet(r, blanks, FALSE, 0);
  IF first < 0 THEN RETURN NIL END;
  last := Ropes.RIndexSet(r, blanks, FALSE, Ropes.Length(r) - 1);
  IF (first = 0) & (last = Ropes.Length(r) - 1) THEN RETURN r END;
  RETURN Ropes.Substring(r, first, last - first + 1)
END Trim;

(* ---- Case ---- *)

(* Ada.Characters.Handling.To_Lower, which the Ada version sorts with:
   it lowers A..Z and also the Latin-1 capitals C0X..DEX except D7X.
   In UTF-8 those are lead bytes, so this doesn't lower non-ASCII
   letters, but it does move names starting with some of them relative
   to others.  Copied as is so that names sort as they do in the Ada
   version.  Ropes.LowerChar folds A..Z only. *)
PROCEDURE Lower(c: CHAR): CHAR;
BEGIN
  IF ((c >= "A") & (c <= "Z")) OR ((c >= 0C0X) & (c <= 0DEX) & (c # 0D7X)) THEN
    RETURN CHR(ORD(c) + 32)
  END;
  RETURN c
END Lower;

(* Ada.Characters.Handling.To_Upper, which the groff-in-reST format
   uses for the name in an "Attacks & Combat Stats (NAME)" caption: it
   raises a..z and the Latin-1 small letters E0X..FEX except F7X (DFX
   and FFX have no capital in Latin-1).  On UTF-8 text that changes the
   lead byte of some multi-byte characters, so a name with, say, an em
   dash in it comes out as different (invalid) bytes, as it does in the
   Ada version; copied as is, so the output is the same. *)
PROCEDURE Upper(c: CHAR): CHAR;
BEGIN
  IF ((c >= "a") & (c <= "z")) OR ((c >= 0E0X) & (c <= 0FEX) & (c # 0F7X)) THEN
    RETURN CHR(ORD(c) - 32)
  END;
  RETURN c
END Upper;

(* r with every byte lowered as the Ada version lowers it: the key
   names are sorted by. *)
PROCEDURE FoldCI*(r: Rope): Rope;
BEGIN RETURN Ropes.Map(r, Lower)
END FoldCI;

(* r with every byte raised as the Ada To_Upper raises it. *)
PROCEDURE ToUpper*(r: Rope): Rope;
BEGIN RETURN Ropes.Map(r, Upper)
END ToUpper;

(* ---- List ---- *)

PROCEDURE Clear*(VAR l: List);
BEGIN l.items := NIL; l.n := 0
END Clear;

PROCEDURE Append*(VAR l: List; r: Rope);
  VAR t: Items; i: INTEGER;
BEGIN
  IF l.items = NIL THEN NEW(l.items, 8); l.n := 0
  ELSIF l.n = LEN(l.items^) THEN
    NEW(t, 2 * l.n);
    FOR i := 0 TO l.n - 1 DO t[i] := l.items[i] END;
    l.items := t
  END;
  l.items[l.n] := r; INC(l.n)
END Append;

(* The items joined with sep between them; NIL (empty) for an empty
   list. *)
PROCEDURE Join*(l: List; sep: ARRAY OF CHAR): Rope;
  VAR r, s: Rope; i: INTEGER;
BEGIN
  r := NIL; s := Ropes.FromString(sep);
  FOR i := 0 TO l.n - 1 DO
    IF i > 0 THEN r := Ropes.Cat(r, s) END;
    r := Ropes.Cat(r, l.items[i])
  END;
  RETURN r
END Join;

(* ---- Flat copies ---- *)

(* The text of r as a 0X-terminated array of exactly Length(r) + 1
   characters, for the procedures that take an ARRAY OF CHAR: Err.String,
   Platform's and polibfyaml's file names.  Never NIL.  Output goes
   through OvaOut.Rope instead, which doesn't copy. *)
PROCEDURE Chars*(r: Rope): String;
  VAR s: String;
BEGIN
  NEW(s, Ropes.Length(r) + 1);
  Ropes.ToString(r, s^);
  RETURN s
END Chars;

BEGIN
  Ropes.MakeCharSet(" ", blanks);
  blanks.has[09H] := TRUE; blanks.has[0AH] := TRUE; blanks.has[0DH] := TRUE
END OvaText.
