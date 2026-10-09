MODULE TestText; (* Unit tests for OvaText *)

IMPORT Check, OvaText, Ropes;

TYPE Rope = Ropes.Rope;

PROCEDURE Is(r: Rope; s: ARRAY OF CHAR): BOOLEAN;
BEGIN RETURN Ropes.EqualString(r, s)
END Is;

(* A rope of several leaves: Ropes.Cat merges leaves of up to
   Ropes.ShortLeafLength characters, so pieces longer than that. *)
PROCEDURE Long(a, b, c: ARRAY OF CHAR): Rope;
BEGIN
  RETURN Ropes.Cat(Ropes.Cat(Ropes.FromString(a), Ropes.FromString(b)), Ropes.FromString(c))
END Long;

PROCEDURE TestInt;
BEGIN
  Check.Check(Is(OvaText.Int(0), "0"), "Int 0");
  Check.Check(Is(OvaText.Int(42), "42"), "Int 42");
  Check.Check(Is(OvaText.Int(-7), "-7"), "Int -7");
  Check.Check(Is(OvaText.Int(MAX(INTEGER)), "2147483647"), "Int MAX(INTEGER)");
  Check.Check(Is(OvaText.Int(MIN(INTEGER)), "-2147483648"), "Int MIN(INTEGER)")
END TestInt;

PROCEDURE TestTrim;
  VAR r: Rope; s: ARRAY 8 OF CHAR;
BEGIN
  s[0] := 09X; s[1] := " "; s[2] := "a"; s[3] := " "; s[4] := "b"; s[5] := 0AX; s[6] := 0DX; s[7] := 0X;
  Check.Check(Is(OvaText.Trim(Ropes.FromString(s)), "a b"), "Trim strips tab, blank, LF and CR");
  s[0] := 0CX; s[1] := "x"; s[2] := 0X;
  r := OvaText.Trim(Ropes.FromString(s));
  Check.Check((Ropes.Length(r) = 2) & (Ropes.Fetch(r, 0) = 0CX), "Trim keeps a form feed");
  Check.Check(OvaText.Trim(Ropes.FromString("  ")) = NIL, "Trim of blanks is NIL");
  Check.Check(OvaText.Trim(NIL) = NIL, "Trim of NIL is NIL");
  r := Long("   first leaf of text, ", "the second leaf of the rope, ", "and a third one   ");
  Check.Check(Ropes.Depth(r) > 0, "a rope of several leaves");
  Check.Check(Is(OvaText.Trim(r), "first leaf of text, the second leaf of the rope, and a third one"),
    "Trim across leaves")
END TestTrim;

PROCEDURE TestCase;
  VAR s: ARRAY 4 OF CHAR; r: Rope;
BEGIN
  Check.Check(Is(OvaText.FoldCI(Ropes.FromString("AbC-z")), "abc-z"), "FoldCI lowers A..Z");
  s[0] := 0C3X; s[1] := 0D7X; s[2] := 0DEX; s[3] := 0X;
  r := OvaText.FoldCI(Ropes.FromString(s));
  Check.Check((Ropes.Fetch(r, 0) = 0E3X) & (Ropes.Fetch(r, 1) = 0D7X) & (Ropes.Fetch(r, 2) = 0FEX),
    "FoldCI lowers Latin-1 capitals but D7X, as Ada's To_Lower");
  Check.Check(Is(OvaText.ToUpper(Ropes.FromString("Arasuni-9")), "ARASUNI-9"), "ToUpper raises a..z");
  s[0] := 0E2X; s[1] := 0F7X; s[2] := 0FFX; s[3] := 0X;
  r := OvaText.ToUpper(Ropes.FromString(s));
  Check.Check((Ropes.Fetch(r, 0) = 0C2X) & (Ropes.Fetch(r, 1) = 0F7X) & (Ropes.Fetch(r, 2) = 0FFX),
    "ToUpper raises Latin-1 small letters but F7X and FFX, as Ada's To_Upper");
  r := Long("lowercase text in a leaf, ", "more lowercase in a second, ", "and a third");
  Check.Check(Is(OvaText.ToUpper(r), "LOWERCASE TEXT IN A LEAF, MORE LOWERCASE IN A SECOND, AND A THIRD"),
    "ToUpper across leaves")
END TestCase;

PROCEDURE TestList;
  VAR l: OvaText.List; i: INTEGER; r: Rope; s: OvaText.String;
BEGIN
  OvaText.Clear(l);
  Check.Check(OvaText.Join(l, ", ") = NIL, "Join of an empty list is NIL");
  FOR i := 0 TO 19 DO OvaText.Append(l, OvaText.Int(i)) END;
  Check.Check(l.n = 20, "Append grows the list");
  r := OvaText.Join(l, ",");
  Check.Check(Is(r, "0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19"), "Join");
  s := OvaText.Chars(r);
  Check.Check((LEN(s^) = Ropes.Length(r) + 1) & (s[LEN(s^) - 1] = 0X) & (s[0] = "0"), "Chars");
  s := OvaText.Chars(NIL);
  Check.Check((LEN(s^) = 1) & (s[0] = 0X), "Chars of NIL")
END TestList;

BEGIN
  TestInt; TestTrim; TestCase; TestList;
  Check.Summary
END TestText.
