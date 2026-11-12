MODULE TestForm; (* Unit tests for OvaForm's measuring and text, and OvaCommon.Reflow *)

(* The golden files check -X's output as a whole; these check FitCut's
   edge cases, Reflow, and the escapes no fixture holds (a control
   character other than LF). *)

IMPORT Check, OvaCommon, OvaForm, Ropes;

TYPE Rope = Ropes.Rope;

PROCEDURE Is(r: Rope; s: ARRAY OF CHAR): BOOLEAN;
BEGIN RETURN Ropes.EqualString(r, s)
END Is;

PROCEDURE Str(s: ARRAY OF CHAR): Rope;
BEGIN RETURN Ropes.FromString(s)
END Str;

(* At size 10 in Helvetica, "a" is 5560 wide and " " 2780, so "aa" is
   11120 and "aa aa" 25020: a field 112 tenths wide (11200) holds one
   "aa" a line, and one 100 wide (10000) not even that. *)
PROCEDURE TestFitCut;
  VAR s: ARRAY 8 OF CHAR;
BEGIN
  Check.Check(OvaForm.FitCut(Str("aa aa"), 10, FALSE, 112, 2) = 5, "FitCut: everything fits");
  Check.Check(OvaForm.FitCut(Str("aa aa"), 10, FALSE, 112, 1) = 2, "FitCut: cut after the first word");
  Check.Check(OvaForm.FitCut(Str("aa aa"), 10, FALSE, 251, 1) = 5, "FitCut: two words on a line");
  Check.Check(OvaForm.FitCut(Str("aa aa"), 10, FALSE, 250, 1) = 2, "FitCut: one unit too narrow for both");
  Check.Check(OvaForm.FitCut(Str("aa"), 10, FALSE, 100, 1) = 0, "FitCut: a word too wide for its lines");
  Check.Check(OvaForm.FitCut(Str("aa a"), 10, FALSE, 100, 2) = 2, "FitCut: a wide word takes two lines");
  Check.Check(OvaForm.FitCut(Str("aa a"), 10, FALSE, 100, 3) = 4, "FitCut: the word after a wide one");
  s[0] := "a"; s[1] := 0AX; s[2] := "a"; s[3] := 0X;
  Check.Check(OvaForm.FitCut(Str(s), 10, FALSE, 1000, 1) = 1, "FitCut: an LF starts a line");
  Check.Check(OvaForm.FitCut(Str(s), 10, FALSE, 1000, 2) = 3, "FitCut: two lines");
  (* "W" is 944 plain, 944 bold; "A" 667 plain, 722 bold. *)
  Check.Check(OvaForm.FitCut(Str("AA"), 10, FALSE, 134, 1) = 2, "FitCut: plain widths");
  Check.Check(OvaForm.FitCut(Str("AA"), 10, TRUE, 134, 1) = 0, "FitCut: bold widths");
  (* A two-byte UTF-8 character counts as a digit, 556. *)
  s[0] := 0C3X; s[1] := 0A9X; s[2] := 0C3X; s[3] := 0A9X; s[4] := 0X;
  Check.Check(OvaForm.FitCut(Str(s), 10, FALSE, 112, 1) = 4, "FitCut: UTF-8 counted by character");
  Check.Check(OvaForm.FitCut(Str(s), 10, FALSE, 111, 1) = 0, "FitCut: UTF-8, too wide");
  Check.Check(OvaForm.FitCut(NIL, 10, FALSE, 100, 1) = 0, "FitCut of nothing")
END TestFitCut;

(* s with "|" as LF, "~" as a tab, "^" as CR, "#" as BS, "%" as FF, "@"
   as 01X and "&" as 1FX. *)
PROCEDURE Ctl(s: ARRAY OF CHAR): Rope;
  VAR t: ARRAY 64 OF CHAR; i: INTEGER;
BEGIN
  i := 0;
  WHILE s[i] # 0X DO
    CASE s[i] OF
      "|": t[i] := 0AX
    | "~": t[i] := 09X
    | "^": t[i] := 0DX
    | "#": t[i] := 08X
    | "%": t[i] := 0CX
    | "@": t[i] := 01X
    | "&": t[i] := 1FX
    ELSE t[i] := s[i]
    END;
    INC(i)
  END;
  t[i] := 0X;
  RETURN Str(t)
END Ctl;

PROCEDURE TestReflow;
BEGIN
  Check.Check(Ropes.Equal(OvaCommon.Reflow(Ctl("  one  |two y||~three z^ | ")), Ctl("one two y|three z")),
    "Reflow: lines trimmed and joined, paragraphs on lines of their own");
  Check.Check(Ropes.Equal(OvaCommon.Reflow(Ctl("|||a||||b|||")), Ctl("a|b")),
    "Reflow: one LF between paragraphs, none around them");
  Check.Check(OvaCommon.Reflow(Ctl(" | ~ ^ ")) = NIL, "Reflow of blank lines is NIL");
  Check.Check(OvaCommon.Reflow(NIL) = NIL, "Reflow of NIL is NIL")
END TestReflow;

PROCEDURE TestEscape;
  VAR s: ARRAY 4 OF CHAR;
BEGIN
  Check.Check(Is(OvaForm.Escape(Str('a"b\c')), 'a\"b\\c'), "Escape: quote and backslash");
  Check.Check(Is(OvaForm.Escape(Ctl("|^~#%")), "\n\r\t\b\f"), "Escape: the short escapes");
  Check.Check(Is(OvaForm.Escape(Ctl("@&")), "\u0001\u001f"), "Escape: other control characters");
  s[0] := 0C3X; s[1] := 0A9X; s[2] := 7FX; s[3] := 0X;
  Check.Check(Ropes.Equal(OvaForm.Escape(Str(s)), Str(s)), "Escape: UTF-8 and DEL pass through");
  Check.Check(OvaForm.Escape(NIL) = NIL, "Escape of NIL is NIL")
END TestEscape;

BEGIN
  TestFitCut; TestReflow; TestEscape;
  Check.Summary
END TestForm.
