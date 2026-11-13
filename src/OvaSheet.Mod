MODULE OvaSheet; (* -S/--sheet: the official character sheet's values as troff *)

(* The Ada Ova_Fmt.Format_Sheet: troff that ova_sheet.sh typesets over
   the blank sheet (PLAN.md, "The official character sheet as PDF").

   Raw troff, no macro package, at the sheet's A5 size, for groff -k
   -Tpdf with the Noto Sans faces sheet_fonts.sh builds.  For each main
   entity, in input order: its copies of page 1 (OvaSheetMap), then page
   2, then, if anything didn't fit, plain continuation pages.  Every
   value on the sheet's pages is placed at a point and broken into lines
   here, with the faces' widths (OvaSheetFonts), so nothing depends on
   how groff fills; only the continuation pages are filled by groff.
   Each sheet page reports itself on standard error ("ova-sheet-page 3
   p1"), which tells the script which page of the blank sheet goes under
   it.

   Every measure is an integer, as in the Ada version, so that the two
   agree to the byte: positions in hundredths of a point (centipoints),
   sizes in tenths of a point, widths in ten-thousandths of a point.
   Indexes into text are from 0, so a cut (the Ada index of the last
   byte placed) is a count of bytes here. *)

IMPORT OvaCommon, OvaConfig, OvaEntities, OvaOut, OvaSheetDraw, OvaSheetFonts, OvaSheetMap, OvaSheetWidths, OvaText, Ropes;

CONST
  LF = 0AX;

  (* Where Width stops counting: 20,000 points, far wider than any
     line, and small enough that Break's sum of two such widths is
     still an INTEGER. *)
  MaxWidth = 200000000;

  (* ---- The sheet's geometry, in centipoints, from its form fields'
     rectangles: X and Y0 the lower left corner, Y0 from the bottom of
     the page, as PDF measures. ---- *)
  PageHeight = 59528;

  (* Text is kept this far inside a field on each side. *)
  Pad = 200;

  (* The fields that hold blocks of text (Combat Notes and page 2's) run
     to the edges of their boxes, so their text is kept a further
     BlockInset in from the sides. *)
  BlockInset = 400;

  (* The ruled lines of the Abilities and Weaknesses columns. *)
  RowBase = 11670;
  RowStep = 1300;

  DiceWidth = 1810;
  NameWidth = 15260;
  AbilityDiceX = 3500;
  AbilityNameX = 5720;
  WeaknessDiceX = 21610;
  WeaknessNameX = 23830;

  (* -C's page 1 (OvaSheetDraw.Page1OneColumn): one column, its rows on
     the Abilities column's lines and at its Dice and name positions,
     but a narrower name; and the Attacks & Combat Stats box beside it,
     whose attack slots are the sheet's, 39.5 pt apart from 131.616 pt
     down, narrowed to the box (set up in the module's body).  The rule
     between the Abilities and the Weaknesses has its top RuleRaise
     above the baseline of the line it takes. *)
  OneColumnNameWidth = 11330;
  RuleRaise = 330;

  (* A Sub or Spell row is indented into the name column; any row's
     second and later lines hang further in. *)
  SubIndent = 800;
  Hang = 600;

  NotesLeading = 850;
  ProseLeading = 1000;
  ClauseLeading = 800;
  ClauseLines = 3;

  (* The fields of page 2, in the order sections are laid into them
     (the Ada Prose_Field). *)
  Background = 0; Appearance = 1; Personality = 2; OtherNotes = 3; ProseFields = 4;

TYPE
  Rope = Ropes.Rope;

  Rect = RECORD x, y0, w, h: INTEGER END;

  (* A face, a size in tenths of a point, and whether it is the sheet's
     dark red.  The rulebook's emphasis, in Noto Sans (PLAN.md, "Fonts
     and type styles"); small caps are faked with upper case a size
     down. *)
  Look = RECORD face, size: INTEGER; red: BOOLEAN END;

  Chars = POINTER TO ARRAY OF CHAR;
  Looks = POINTER TO ARRAY OF Look;

  (* Styled text: t[0 .. n-1], and each byte's look. *)
  Styled = POINTER TO StyledDesc;
  StyledDesc = RECORD
    t: Chars;
    looks: Looks;
    n: INTEGER
  END;

  (* Lines of a Styled: line i is its bytes first[i] .. last[i]. *)
  Ints = POINTER TO ARRAY OF INTEGER;
  Lines = RECORD first, last: Ints; n: INTEGER END;

  (* An owner's parts of the continuation pages, gathered over its
     copies of page 1: the Character Name and Player Name fields in full
     when cut (the first cut copy's), and the notes, attacks and combat
     notes that don't fit. *)
  OwnerParts = RECORD name, player, abilityNotes, attacks, combatNotes: Rope END;

  (* The attack slots: their name, clause, ROLL, DX and END boxes, for
     the sheet's AttackSlots or -C's OneColumnAttackSlots. *)
  AttackRects = RECORD
    name, clause, roll, dx, end: ARRAY OvaSheetMap.OneColumnAttackSlots OF Rect
  END;

  (* The parts of the continuation pages: a heading, then each line of
     its content a paragraph; then, if fluff isn't NIL, its fluff: block
     (PutFluff), under fluffLabel. The Ada version's Raw section. *)
  Sections = RECORD
    labels, contents: OvaText.List;
    fluff: OvaEntities.Entity; fluffLabel: Rope
  END;

VAR
  firstEntity: BOOLEAN;
  portraits: INTEGER;               (* numbers each portrait for ova_sheet.sh *)

  characterName, playerName, portraitBox, combatNotes: Rect;
  defenseBox, healthBox, enduranceBox, tvBox: Rect;
  (* -C's: the NPC type, after the box's title as "(HEROIC)" is after
     Acacia's, its baseline near the title's; the Combat Notes; the
     stats. *)
  oneNpcType, oneCombatNotes, oneDefenseBox, oneHealthBox, oneEnduranceBox, oneTvBox: Rect;
  sheetAttacks, oneAttacks: AttackRects;
  proseRect: ARRAY ProseFields OF Rect;

  itemLook, itemCaps, subLook, subCaps, diceLook, notesLook, proseLook: Look;

(* ---- Geometry ---- *)

PROCEDURE SetRect(VAR r: Rect; x, y0, w, h: INTEGER);
BEGIN r.x := x; r.y0 := y0; r.w := w; r.h := h
END SetRect;

(* r, with the block inset at the sides. *)
PROCEDURE SetInset(VAR r: Rect; x, y0, w, h: INTEGER);
BEGIN SetRect(r, x + BlockInset, y0, w - 2 * BlockInset, h)
END SetInset;

(* r's top from the top of the page, as troff measures. *)
PROCEDURE Top(r: Rect): INTEGER;
BEGIN RETURN PageHeight - (r.y0 + r.h)
END Top;

(* Row k's baseline from the top of the page, k from 1. *)
PROCEDURE RowBaseline(k: INTEGER): INTEGER;
BEGIN RETURN RowBase + RowStep * (k - 1)
END RowBaseline;

(* The height of a capital, 0.714 em in Noto Sans, in centipoints. *)
PROCEDURE Cap(size: INTEGER): INTEGER;
BEGIN RETURN 714 * size DIV 100
END Cap;

PROCEDURE Max(a, b: INTEGER): INTEGER;
BEGIN
  IF a > b THEN RETURN a END;
  RETURN b
END Max;

PROCEDURE SetLook(VAR l: Look; face, size: INTEGER);
BEGIN l.face := face; l.size := size; l.red := FALSE
END SetLook;

PROCEDURE SameLook(a, b: Look): BOOLEAN;
BEGIN RETURN (a.face = b.face) & (a.size = b.size) & (a.red = b.red)
END SameLook;

(* ---- Output ---- *)

PROCEDURE Int(i: INTEGER);
BEGIN OvaOut.Rope(OvaText.Int(i))
END Int;

(* "116.70": centipoints as points. *)
PROCEDURE Pt(n: INTEGER);
BEGIN
  Int(n DIV 100); OvaOut.Char(".");
  OvaOut.Char(CHR(ORD("0") + n MOD 100 DIV 10)); OvaOut.Char(CHR(ORD("0") + n MOD 10))
END Pt;

(* "8", "6.5": tenths of a point as points. *)
PROCEDURE SizeImg(s: INTEGER);
BEGIN
  Int(s DIV 10);
  IF s MOD 10 # 0 THEN OvaOut.Char("."); Int(s MOD 10) END
END SizeImg;

PROCEDURE Line(s: ARRAY OF CHAR);
BEGIN OvaOut.String(s); OvaOut.Ln
END Line;

(* c as troff text: "\" as "\e", a tab as a space. *)
PROCEDURE Escape(c: CHAR);
BEGIN
  IF c = "\" THEN OvaOut.String("\e")
  ELSIF c = 09X THEN OvaOut.Char(" ")
  ELSE OvaOut.Char(c)
  END
END Escape;

(* ---- Styled text ---- *)

PROCEDURE NewStyled(): Styled;
  VAR s: Styled;
BEGIN
  NEW(s); NEW(s.t, 64); NEW(s.looks, 64); s.n := 0;
  RETURN s
END NewStyled;

PROCEDURE AddChar(s: Styled; c: CHAR; l: Look);
  VAR t: Chars; looks: Looks; i: INTEGER;
BEGIN
  IF s.n = LEN(s.t^) THEN
    NEW(t, 2 * s.n); NEW(looks, 2 * s.n);
    FOR i := 0 TO s.n - 1 DO t[i] := s.t[i]; looks[i] := s.looks[i] END;
    s.t := t; s.looks := looks
  END;
  s.t[s.n] := c; s.looks[s.n] := l; INC(s.n)
END AddChar;

(* Appends the text of a, up to its first 0X, in look l. *)
PROCEDURE AddStr(s: Styled; a: ARRAY OF CHAR; l: Look);
  VAR i: INTEGER;
BEGIN
  i := 0;
  WHILE (i < LEN(a)) & (a[i] # 0X) DO AddChar(s, a[i], l); INC(i) END
END AddStr;

(* Appends r, upper-cased (faked small caps) if upper, each "--" an
   em dash, U+2014 in UTF-8, as the rulebook sets one (the Ada
   Dashes).  Here, before anything is measured, so that lines are broken
   with the dash's own width; what is cut is cut from s, not r.  groff
   reads it through preconv (ova_sheet.sh's -k). *)
PROCEDURE AddRope(s: Styled; r: Rope; l: Look; upper: BOOLEAN);
  VAR i, n: INTEGER; c: CHAR;
BEGIN
  n := SHORT(Ropes.Length(r)); i := 0;
  WHILE i < n DO
    c := Ropes.Fetch(r, i);
    IF (c = "-") & (i + 1 < n) & (Ropes.Fetch(r, i + 1) = "-") THEN
      AddChar(s, 0E2X, l); AddChar(s, 80X, l); AddChar(s, 94X, l); INC(i, 2)
    ELSE
      IF upper & (c >= "a") & (c <= "z") THEN c := CHR(ORD(c) - 32) END;
      AddChar(s, c, l); INC(i)
    END
  END
END AddRope;

PROCEDURE Plain(r: Rope; l: Look): Styled;
  VAR s: Styled;
BEGIN s := NewStyled(); AddRope(s, r, l, FALSE); RETURN s
END Plain;

(* The width of s's bytes first .. last, in ten-thousandths of a point,
   up to MaxWidth: a run of one look at a time. *)
PROCEDURE Width(s: Styled; first, last: INTEGER): INTEGER;
  VAR w, i, j: INTEGER;
BEGIN
  w := 0; i := first;
  WHILE i <= last DO
    j := i;
    WHILE (j < last) & SameLook(s.looks[j + 1], s.looks[i]) DO INC(j) END;
    w := w + OvaSheetFonts.TextWidth(s.t^, i, j + 1, s.looks[i].face) * s.looks[i].size;
    IF w > MaxWidth THEN w := MaxWidth END;
    i := j + 1
  END;
  RETURN w
END Width;

PROCEDURE ClearLines(VAR ls: Lines);
BEGIN
  IF ls.first = NIL THEN NEW(ls.first, 8); NEW(ls.last, 8) END;
  ls.n := 0
END ClearLines;

PROCEDURE AddLine(VAR ls: Lines; first, last: INTEGER);
  VAR f, l: Ints; i: INTEGER;
BEGIN
  IF ls.n = LEN(ls.first^) THEN
    NEW(f, 2 * ls.n); NEW(l, 2 * ls.n);
    FOR i := 0 TO ls.n - 1 DO f[i] := ls.first[i]; l[i] := ls.last[i] END;
    ls.first := f; ls.last := l
  END;
  ls.first[ls.n] := first; ls.last[ls.n] := last; INC(ls.n)
END AddLine;

(* s broken greedily at spaces into lines firstWidth centipoints wide,
   then restWidth, each LF starting a new line, into at most maxLines
   lines (0: any number).  cut is how many bytes were placed, s.n if all
   of them were.  A word wider than its line has a line of its own and
   overflows it. *)
PROCEDURE Break(s: Styled; firstWidth, restWidth, maxLines: INTEGER; VAR ls: Lines; VAR cut: INTEGER);
  VAR i, j, w, cur, space, limit, lineFirst, lineLast: INTEGER; open: BOOLEAN;
BEGIN
  ClearLines(ls); cut := 0;
  i := 0; open := FALSE; cur := 0; lineFirst := 0; lineLast := 0;
  WHILE i < s.n DO
    IF s.t[i] = LF THEN
      IF open THEN AddLine(ls, lineFirst, lineLast); open := FALSE END;
      INC(i)
    ELSIF s.t[i] = " " THEN INC(i)
    ELSE
      j := i;
      WHILE (j < s.n - 1) & (s.t[j + 1] # " ") & (s.t[j + 1] # LF) DO INC(j) END;
      w := Width(s, i, j);
      IF open THEN
        space := Width(s, lineLast + 1, i - 1);
        IF ls.n = 0 THEN limit := firstWidth * 100 ELSE limit := restWidth * 100 END;
        IF cur + space + w <= limit THEN lineLast := j; cur := cur + space + w
        ELSE AddLine(ls, lineFirst, lineLast); open := FALSE
        END
      END;
      IF ~open THEN
        IF (maxLines > 0) & (ls.n = maxLines) THEN RETURN END;
        lineFirst := i; lineLast := j; cur := w; open := TRUE
      END;
      cut := j + 1; i := j + 1
    END
  END;
  IF open THEN AddLine(ls, lineFirst, lineLast) END;
  cut := s.n
END Break;

(* s's bytes first .. last as troff: each change of look an escape.  It
   starts with an escape, so it can't be read as a request. *)
PROCEDURE Troff(s: Styled; first, last: INTEGER);
  VAR i: INTEGER; red: BOOLEAN; l: Look; name: ARRAY 8 OF CHAR;
BEGIN
  red := FALSE;
  FOR i := first TO last DO
    IF (i = first) OR ~SameLook(s.looks[i], s.looks[i - 1]) THEN
      l := s.looks[i];
      IF l.red # red THEN
        IF l.red THEN OvaOut.String("\m[ovared]") ELSE OvaOut.String("\m[default]") END;
        red := l.red
      END;
      OvaSheetFonts.Name(l.face, name);
      OvaOut.String("\f["); OvaOut.String(name); OvaOut.String("]\s["); SizeImg(l.size); OvaOut.Char("]")
    END;
    Escape(s.t[i])
  END;
  IF red THEN OvaOut.String("\m[default]") END
END Troff;

(* Line k of ls, with its baseline y from the top and its left at x;
   white sets it in white (s has no red), as on -C's box title. *)
PROCEDURE PlaceColoured(y, x: INTEGER; s: Styled; first, last: INTEGER; white: BOOLEAN);
BEGIN
  OvaOut.String(".L "); Pt(y); OvaOut.Char(" "); Pt(x); OvaOut.Ln;
  IF white THEN OvaOut.String("\m[white]") END;
  Troff(s, first, last);
  IF white THEN OvaOut.String("\m[default]") END;
  OvaOut.Ln
END PlaceColoured;

PROCEDURE Place(y, x: INTEGER; s: Styled; first, last: INTEGER);
BEGIN PlaceColoured(y, x, s, first, last, FALSE)
END Place;

(* text in r's one line, centred or at its left, in face f at size,
   stepping down half a point at a time to floor until it fits; if not
   even then, the words that fit.  FALSE if not all of it fit. *)
PROCEDURE PutLineIn(text: Rope; f, size, floor: INTEGER; r: Rect; centred, red, white: BOOLEAN): BOOLEAN;
  VAR inner, s, w, x, cut: INTEGER; l: Look; st: Styled; ls: Lines;
BEGIN
  IF Ropes.Length(text) = 0 THEN RETURN TRUE END;
  inner := r.w - 2 * Pad;
  l.face := f; l.size := size; l.red := red;
  st := Plain(text, l);
  s := size;
  WHILE (s > floor) & (OvaSheetFonts.TextWidth(st.t^, 0, st.n, f) * s > inner * 100) DO
    s := Max(floor, s - 5)
  END;
  FOR x := 0 TO st.n - 1 DO st.looks[x].size := s END;
  ls.first := NIL;
  Break(st, inner, inner, 1, ls, cut);
  IF ls.n = 0 THEN RETURN FALSE END;
  w := Width(st, ls.first[0], ls.last[0]);
  IF centred & (w <= r.w * 100) THEN x := r.x + (r.w * 100 - w) DIV 200 ELSE x := r.x + Pad END;
  PlaceColoured(Top(r) + (r.h + Cap(s)) DIV 2, x, st, ls.first[0], ls.last[0], white);
  RETURN cut = st.n
END PutLineIn;

(* PutLineIn, whether it all fit or not. *)
PROCEDURE PutIn(text: Rope; f, size, floor: INTEGER; r: Rect; centred: BOOLEAN);
  VAR allFit: BOOLEAN;
BEGIN allFit := PutLineIn(text, f, size, floor, r, centred, FALSE, FALSE)
END PutIn;

(* The most lines of l at leading that r holds, top-aligned. *)
PROCEDURE BlockLines(r: Rect; l: Look; leading: INTEGER): INTEGER;
BEGIN RETURN Max(1, (r.h - 2 * Pad - Cap(l.size)) DIV leading + 1)
END BlockLines;

(* text split into what fits r at l and leading and the rest, r taking
   at least one word. *)
PROCEDURE FitBlock(text: Rope; l: Look; r: Rect; leading: INTEGER; VAR fitted, rest: Rope);
  VAR ls: Lines; cut: INTEGER; st: Styled;
BEGIN
  ls.first := NIL; st := Plain(text, l);
  Break(st, r.w - 2 * Pad, r.w - 2 * Pad, BlockLines(r, l, leading), ls, cut);
  IF (cut = 0) & (ls.n > 0) THEN cut := ls.last[0] + 1 END;
  (* From st, whose dashes are no longer the text's "--". *)
  fitted := OvaText.Trim(Ropes.FromSubchars(st.t^, 0, cut));
  rest := OvaText.Trim(Ropes.FromSubchars(st.t^, cut, st.n - cut))
END FitBlock;

(* text in r, top-aligned, a line at a time. *)
PROCEDURE PutBlock(text: Rope; l: Look; r: Rect; leading: INTEGER);
  VAR st: Styled; ls: Lines; cut, y, i: INTEGER;
BEGIN
  st := Plain(text, l); ls.first := NIL;
  y := Top(r) + Pad + Cap(l.size);
  Break(st, r.w - 2 * Pad, r.w - 2 * Pad, 0, ls, cut);
  FOR i := 0 TO ls.n - 1 DO
    Place(y, r.x + Pad, st, ls.first[i], ls.last[i]);
    y := y + leading
  END
END PutBlock;

(* ---- Rows ---- *)

PROCEDURE Indent(r: OvaSheetMap.Row): INTEGER;
BEGIN
  IF r.kind = OvaSheetMap.Item THEN RETURN 0 END;
  RETURN SubIndent
END Indent;

(* A row's text: an Item's name in italic, a Sub's level and name and a
   Spell in light italic, smaller; the bracket's perks, flaws and
   Endurance in faked small caps. *)
PROCEDURE RowText(r: OvaSheetMap.Row): Styled;
  VAR base, caps: Look; s: Styled;
BEGIN
  IF r.kind = OvaSheetMap.Item THEN base := itemLook; caps := itemCaps
  ELSE base := subLook; caps := subCaps
  END;
  s := NewStyled();
  IF r.kind = OvaSheetMap.Sub THEN AddRope(s, r.level, base, FALSE); AddStr(s, " ", base) END;
  AddRope(s, r.plain, base, FALSE);
  IF Ropes.Length(r.mods) > 0 THEN
    AddStr(s, " [", base); AddRope(s, r.mods, caps, TRUE); AddStr(s, "]", base)
  END;
  RETURN s
END RowText;

PROCEDURE RowBreak(r: OvaSheetMap.Row; s: Styled; VAR ls: Lines);
  VAR first, cut: INTEGER;
BEGIN
  IF OvaConfig.oneColumn THEN first := OneColumnNameWidth ELSE first := NameWidth END;
  first := first - 2 * Pad - Indent(r);
  Break(s, first, first - Hang, 0, ls, cut)
END RowBreak;

(* OvaSheetMap's measure: the ruled lines a row takes. *)
PROCEDURE RowLines(r: OvaSheetMap.Row): INTEGER;
  VAR ls: Lines;
BEGIN
  ls.first := NIL;
  RowBreak(r, RowText(r), ls);
  RETURN Max(1, ls.n)
END RowLines;

(* line added to lines, LF-separated. *)
PROCEDURE AddTo(VAR lines: Rope; line: Rope);
BEGIN
  IF Ropes.Length(lines) > 0 THEN lines := Ropes.AppendChar(lines, LF) END;
  lines := Ropes.Cat(lines, line)
END AddTo;

(* Rows on the ruled lines from line first down; next is the line after
   them. *)
PROCEDURE PutRows(VAR parts: OwnerParts; rows: OvaSheetMap.Seq; diceX, nameX, first: INTEGER;
                  VAR next: INTEGER);
  VAR r: OvaSheetMap.Row; st, dice: Styled; ls: Lines; i, j, k, w, x: INTEGER;
BEGIN
  k := first; ls.first := NIL;
  FOR i := 0 TO rows.n - 1 DO
    r := rows.items[i](OvaSheetMap.Row);
    st := RowText(r);
    RowBreak(r, st, ls);
    IF (r.kind = OvaSheetMap.Item) & (Ropes.Length(r.level) > 0) THEN
      dice := Plain(r.level, diceLook);
      w := Width(dice, 0, dice.n - 1);
      Place(RowBaseline(k), diceX + (DiceWidth * 100 - w) DIV 200, dice, 0, dice.n - 1)
    END;
    FOR j := 0 TO ls.n - 1 DO
      x := nameX + Pad + Indent(r);
      IF j > 0 THEN x := x + Hang END;
      Place(RowBaseline(k + j), x, st, ls.first[j], ls.last[j])
    END;
    k := k + Max(1, ls.n);
    IF r.hasNote THEN AddTo(parts.abilityNotes, OvaCommon.Reflow(r.note)) END
  END;
  next := k
END PutRows;

(* ---- Attacks ---- *)

(* The clause in faked small caps, stepping down to 5.5 pt until it
   fits ClauseLines lines; FALSE if not even then, when as many words
   as fit are placed, ending in an ellipsis rather than the comma or
   semicolon after the last (the whole clause goes in the Attacks
   section). *)
PROCEDURE PutClause(clause: Rope; r: Rect): BOOLEAN;
  VAR inner, size, cut, k, done, n, block, y, i: INTEGER; text, st: Styled; ls: Lines; l: Look;
    c: CHAR;
BEGIN
  inner := r.w - 2 * Pad;
  SetLook(l, OvaSheetWidths.Regular, 65);
  text := NewStyled(); AddRope(text, clause, l, TRUE);
  n := text.n; size := 65; ls.first := NIL;
  LOOP
    SetLook(l, OvaSheetWidths.Regular, size);
    FOR i := 0 TO n - 1 DO text.looks[i] := l END;
    st := text;
    Break(st, inner, inner, ClauseLines, ls, cut);
    IF (cut = n) OR (size <= 55) THEN EXIT END;
    size := size - 5
  END;
  IF cut < n THEN
    k := cut;
    LOOP
      LOOP
        IF k = 0 THEN EXIT END;
        c := text.t[k - 1];
        IF (c # " ") & (c # ",") & (c # ";") & (c # ":") THEN EXIT END;
        DEC(k)
      END;
      st := NewStyled();
      FOR i := 0 TO k - 1 DO AddChar(st, text.t[i], l) END;
      AddChar(st, 0E2X, l); AddChar(st, 80X, l); AddChar(st, 0A6X, l);   (* U+2026 *)
      Break(st, inner, inner, ClauseLines, ls, done);
      IF (done = st.n) OR (k = 0) THEN EXIT END;
      (* Drop the last word. *)
      WHILE (k > 0) & (text.t[k - 1] # " ") DO DEC(k) END
    END
  END;
  block := (ls.n - 1) * ClauseLeading + Cap(size);
  y := Top(r) + (r.h - block) DIV 2 + Cap(size);
  FOR i := 0 TO ls.n - 1 DO
    Place(y, r.x + Pad, st, ls.first[i], ls.last[i]);
    y := y + ClauseLeading
  END;
  RETURN cut = n
END PutClause;

(* The attacks in the slots of rects. *)
PROCEDURE PutAttacks(VAR parts: OwnerParts; attacks: OvaSheetMap.Seq; VAR rects: AttackRects);
  VAR a: OvaSheetMap.AttackSlot; n: INTEGER; nameFits, clipped: BOOLEAN; entry: Rope;
BEGIN
  FOR n := 0 TO attacks.n - 1 DO
    a := attacks.items[n](OvaSheetMap.AttackSlot);
    nameFits := PutLineIn(a.name, OvaSheetWidths.Bold, 80, 65, rects.name[n], FALSE, TRUE, FALSE);
    clipped := (Ropes.Length(a.clause) > 0) & ~PutClause(a.clause, rects.clause[n]);
    PutIn(a.roll, OvaSheetWidths.CondensedSemibold, 160, 80, rects.roll[n], TRUE);
    PutIn(a.dx, OvaSheetWidths.CondensedSemibold, 160, 80, rects.dx[n], TRUE);
    PutIn(a.endurance, OvaSheetWidths.CondensedSemibold, 160, 80, rects.end[n], TRUE);
    IF a.hasDescription OR clipped OR ~nameFits THEN
      entry := a.name;
      IF clipped THEN
        OvaText.Add(entry, " ("); entry := Ropes.Cat(entry, a.clause); entry := Ropes.AppendChar(entry, ")")
      END;
      IF a.hasDescription THEN
        OvaText.Add(entry, ": "); entry := Ropes.Cat(entry, OvaCommon.Reflow(a.description))
      END;
      AddTo(parts.attacks, entry)
    END
  END
END PutAttacks;

(* ---- Pages ---- *)

(* With -C, the Abilities and Weaknesses are one column, a faint rule
   between them when this copy has both, and the NPC type is in the
   box's title instead of the Combat Notes, if it fits. *)
PROCEDURE PutPage1(p: OvaSheetMap.Page; VAR parts: OwnerParts);
  VAR notes, fitted, t: Rope; stat, k: INTEGER; one, typePlaced: BOOLEAN;
BEGIN
  stat := OvaSheetWidths.CondensedSemibold;
  one := OvaConfig.oneColumn; typePlaced := FALSE;
  Line(".SP p1");
  IF OvaConfig.redraw THEN
    IF one THEN Line(OvaSheetDraw.Page1OneColumn) ELSE Line(OvaSheetDraw.Page1) END
  END;
  IF ~PutLineIn(p.title, OvaSheetWidths.Regular, 120, 80, characterName, FALSE, FALSE, FALSE)
     & (Ropes.Length(parts.name) = 0) THEN
    parts.name := p.title
  END;
  IF p.hasPlayer
     & ~PutLineIn(p.player, OvaSheetWidths.Regular, 120, 80, playerName, FALSE, FALSE, FALSE)
     & (Ropes.Length(parts.player) = 0) THEN
    parts.player := p.player
  END;
  PutRows(parts, p.abilities, AbilityDiceX, AbilityNameX, 1, k);
  IF ~one THEN
    PutRows(parts, p.weaknesses, WeaknessDiceX, WeaknessNameX, 1, k);
    PutAttacks(parts, p.attacks, sheetAttacks)
  ELSE
    IF (p.abilities.n > 0) & (p.weaknesses.n > 0) THEN
      OvaOut.String(OvaSheetDraw.Rule); OvaOut.Char(" "); Pt(RowBaseline(k) - RuleRaise); OvaOut.Ln;
      INC(k)
    END;
    PutRows(parts, p.weaknesses, AbilityDiceX, AbilityNameX, k, k);
    PutAttacks(parts, p.attacks, oneAttacks);
    IF Ropes.Length(p.npcType) > 0 THEN
      t := NIL; t := Ropes.AppendChar(t, "("); t := Ropes.Cat(t, Ropes.UppercaseAscii(p.npcType));
      t := Ropes.AppendChar(t, ")");
      typePlaced := PutLineIn(t, OvaSheetWidths.CondensedSemibold, 120, 80, oneNpcType, FALSE, FALSE, TRUE)
    END
  END;
  notes := NIL;
  IF (Ropes.Length(p.npcType) > 0) & ~typePlaced THEN OvaText.Add(notes, "NPC Type: "); notes := Ropes.Cat(notes, p.npcType) END;
  IF p.hasCombatNotes THEN AddTo(notes, OvaCommon.Reflow(p.combatNotes)) END;
  IF Ropes.Length(notes) > 0 THEN
    IF one THEN
      FitBlock(notes, notesLook, oneCombatNotes, NotesLeading, fitted, parts.combatNotes);
      PutBlock(fitted, notesLook, oneCombatNotes, NotesLeading)
    ELSE
      FitBlock(notes, notesLook, combatNotes, NotesLeading, fitted, parts.combatNotes);
      PutBlock(fitted, notesLook, combatNotes, NotesLeading)
    END
  END;
  IF p.hasStats & one THEN
    PutIn(p.defense, stat, 180, 80, oneDefenseBox, TRUE);
    PutIn(p.health, stat, 180, 80, oneHealthBox, TRUE);
    PutIn(p.endurance, stat, 180, 80, oneEnduranceBox, TRUE);
    PutIn(p.threatValue, stat, 180, 80, oneTvBox, TRUE)
  ELSIF p.hasStats THEN
    PutIn(p.defense, stat, 180, 80, defenseBox, TRUE);
    PutIn(p.health, stat, 180, 80, healthBox, TRUE);
    PutIn(p.endurance, stat, 180, 80, enduranceBox, TRUE);
    PutIn(p.threatValue, stat, 180, 80, tvBox, TRUE)
  END
END PutPage1;

PROCEDURE AddSection(VAR ss: Sections; label, content: Rope);
BEGIN
  IF Ropes.Length(content) > 0 THEN
    OvaText.Append(ss.labels, label); OvaText.Append(ss.contents, content)
  END
END AddSection;

(* owner & s *)
PROCEDURE Label(owner: Rope; s: ARRAY OF CHAR): Rope;
BEGIN OvaText.Add(owner, s); RETURN owner
END Label;

PROCEDURE AddOwnerSections(VAR ss: Sections; owner: Rope; parts: OwnerParts);
BEGIN
  AddSection(ss, Label(owner, ": Name"), parts.name);
  AddSection(ss, Label(owner, ": Player Name"), parts.player);
  AddSection(ss, Label(owner, ": Ability Notes"), parts.abilityNotes);
  AddSection(ss, Label(owner, ": Attacks"), parts.attacks);
  AddSection(ss, Label(owner, ": Combat Notes (continued)"), parts.combatNotes)
END AddOwnerSections;

(* r's bytes from .. to - 1 as one filled troff line: "\&" first, so
   that it can't be read as a request. *)
(* r's bytes from .. to - 1 as troff text, each "--" an em dash. *)
PROCEDURE PutRun(r: Rope; from, to: INTEGER);
  VAR i: INTEGER;
BEGIN
  i := from;
  WHILE i < to DO
    IF (Ropes.Fetch(r, i) = "-") & (i + 1 < to) & (Ropes.Fetch(r, i + 1) = "-") THEN
      OvaOut.Char(0E2X); OvaOut.Char(80X); OvaOut.Char(94X); INC(i, 2)   (* as AddRope's *)
    ELSE
      Escape(Ropes.Fetch(r, i)); INC(i)
    END
  END
END PutRun;

PROCEDURE PutText(r: Rope; from, to: INTEGER);
BEGIN
  OvaOut.String("\&"); PutRun(r, from, to); OvaOut.Ln
END PutText;

(* Whether e has a fluff: field to write. *)
PROCEDURE HasFluffField(e: OvaEntities.Entity): BOOLEAN;
  VAR i: INTEGER;
BEGIN
  IF e.hasFluff THEN
    FOR i := 0 TO OvaEntities.NFluff - 1 DO
      IF e.hasFluffField[i] THEN RETURN TRUE END
    END
  END;
  RETURN FALSE
END HasFluffField;

(* e's fluff: block as one paragraph (the Ada Fluff_Line): the
   comma-joined line every other format writes (OvaCommon.FluffLine),
   each label in Bold, as theirs are, and each value reflowed onto one
   line, since the paragraph is one line; the last ends in a period. *)
PROCEDURE PutFluff(e: OvaEntities.Entity);
  VAR t: Rope; i, last: INTEGER; first: BOOLEAN;
BEGIN
  last := OvaEntities.NFluff - 1;
  WHILE ~e.hasFluffField[last] DO DEC(last) END;
  Line(".PP");
  OvaOut.String("\&"); first := TRUE;
  FOR i := 0 TO last DO
    IF e.hasFluffField[i] THEN
      IF ~first THEN OvaOut.String(", ") END;
      first := FALSE;
      t := Ropes.AppendChar(OvaCommon.FluffLabel(i), ":");
      OvaOut.String("\f[NSB]"); PutRun(t, 0, SHORT(Ropes.Length(t)));
      OvaOut.String("\f[NSR] ");
      t := OvaCommon.Reflow(e.fluff[i]);
      t := OvaCommon.AllOneLine(t);
      IF i = last THEN t := OvaCommon.EndWithPeriod(t) END;
      PutRun(t, 0, SHORT(Ropes.Length(t)))
    END
  END;
  OvaOut.Ln
END PutFluff;

PROCEDURE PutSections(ss: Sections);
  VAR i, from, to, n: INTEGER; c: Rope;
BEGIN
  IF (ss.labels.n = 0) & (ss.fluff = NIL) THEN RETURN END;
  Line(".CP");
  FOR i := 0 TO ss.labels.n - 1 DO
    Line(".SH");
    PutText(ss.labels.items[i], 0, SHORT(Ropes.Length(ss.labels.items[i])));
    c := ss.contents.items[i]; n := SHORT(Ropes.Length(c));
    from := 0;
    WHILE from < n DO
      to := from;
      WHILE (to < n) & (Ropes.Fetch(c, to) # LF) DO INC(to) END;
      IF to > from THEN Line(".PP"); PutText(c, from, to) END;
      from := to + 1
    END
  END;
  IF ss.fluff # NIL THEN
    Line(".SH");
    PutText(ss.fluffLabel, 0, SHORT(Ropes.Length(ss.fluffLabel)));
    PutFluff(ss.fluff)
  END
END PutSections;

(* The page is the sheet's; every placed line sets its own face and
   size.  L places a line's baseline Y points from the top and X from
   the left.  SP starts a sheet page and reports it; CP starts a
   continuation page, with margins of half an inch and a footer trap;
   SH and PP are its headings and paragraphs.  The backslashes are
   doubled for copy mode, as the Ada version writes them. *)
PROCEDURE PutPreamble;
BEGIN
  OvaOut.String('.\"'); Line(" ova_fmt -S: the OVA character sheet's values, to be typeset");
  OvaOut.String('.\"'); Line(" with groff -k -Tpdf and laid over the blank sheet (ova_sheet.sh).");
  Line(".pl 595.276p");
  Line(".po 0");
  Line(".nh");
  Line(".ad l");
  Line(".defcolor ovared rgb 0.47 0.11 0.13");
  Line(".nr started 0");
  Line(".nr cont 0");
  Line(".de L");
  Line(".sp |\\$1p-1p");
  Line(".in \\$2p");
  Line("..");
  Line(".de HD");
  Line(".if \\n[cont] 'sp |36p");
  Line("..");
  Line(".wh 0 HD");
  Line(".de FT");
  Line("'bp");
  Line("..");
  Line(".de SP");
  Line(".ch FT");
  Line(".nr cont 0");
  Line(".if \\n[started] .bp");
  Line(".nr started 1");
  Line(".nf");
  Line(".vs 1p");
  Line(".tm ova-sheet-page \\n% \\$1");
  Line("..");
  Line(".de CP");
  Line(".nr cont 1");
  Line(".if \\n[started] .bp");
  Line(".nr started 1");
  Line(".wh -40p FT");
  Line(".fi");
  Line(".in 36p");
  Line(".ll 383.528p");
  Line(".vs 11p");
  Line("..");
  Line(".de PT");
  Line(".if d ova-portrait-\\$1 \\X'pdf: pdfpic \\*[ova-portrait-\\$1] -L \\$2p \\$3p'");
  Line("..");
  Line(".de SH");
  Line(".sp 8p");
  Line(".ne 4v");
  Line(".ft NSB");
  Line(".ps 10");
  Line("..");
  Line(".de PP");
  Line(".br");
  Line(".ft NSR");
  Line(".ps 9");
  Line(".sp 3p");
  Line("..")
END PutPreamble;

(* "N W H": the portrait's number and box size. *)
PROCEDURE PortraitSize(r: Rect);
BEGIN Int(portraits); OvaOut.Char(" "); Pt(r.w); OvaOut.Char(" "); Pt(r.h)
END PortraitSize;

(* The portrait: -P's, or else e's own, a relative path taken from the
   YAML file's directory.  ova_sheet.sh finds the comment, converts the
   image to a PDF, and defines ova-portrait-N as its name for PT, which
   places it with its top left at the box's, as large as fits; without
   that, PT places nothing. *)
PROCEDURE PutPortrait(e: OvaEntities.Entity);
  VAR path: Rope; r: Rect;
BEGIN
  r := portraitBox; path := NIL;
  IF OvaConfig.hasPortrait THEN path := OvaConfig.portrait
  ELSIF e.hasPortrait & (Ropes.Length(e.portrait) > 0) THEN
    path := e.portrait;
    IF Ropes.Fetch(path, 0) # "/" THEN path := Ropes.Cat(OvaConfig.sourceDir, path) END
  END;
  IF (Ropes.Length(path) = 0) OR (Ropes.IndexChar(path, LF, 0) >= 0) THEN RETURN END;
  INC(portraits);
  OvaOut.String('.\" ova-sheet-portrait '); PortraitSize(r); OvaOut.Char(" "); OvaOut.Rope(path); OvaOut.Ln;
  OvaOut.String(".L "); Pt(Top(r)); OvaOut.Char(" "); Pt(r.x); OvaOut.Ln;
  OvaOut.String(".PT "); PortraitSize(r); OvaOut.Ln
END PutPortrait;

PROCEDURE ProseName(p: INTEGER; VAR s: ARRAY OF CHAR);
BEGIN
  CASE p OF
    Background: COPY("Background", s)
  | Appearance: COPY("Appearance", s)
  | Personality: COPY("Personality", s)
  | OtherNotes: COPY("Other Notes", s)
  END
END ProseName;

(* The prose field p, has and text, fitted into its box, the rest a
   section. *)
PROCEDURE MainProse(VAR ss: Sections; VAR fitted: Rope; name: Rope; p: INTEGER; has: BOOLEAN; text: Rope);
  VAR content, rest, label: Rope; pn: ARRAY 16 OF CHAR;
BEGIN
  content := NIL;
  IF has THEN content := OvaCommon.Reflow(text) END;
  IF Ropes.Length(content) > 0 THEN
    FitBlock(content, proseLook, proseRect[p], ProseLeading, fitted, rest);
    ProseName(p, pn);
    label := Label(name, ": "); OvaText.Add(label, pn); OvaText.Add(label, " (continued)");
    AddSection(ss, label, rest)
  END
END MainProse;

(* e's pages, after the troff preamble if e is the first entity. *)
PROCEDURE ProcessEntity*(e: OvaEntities.Entity);
  VAR pages: OvaSheetMap.Seq; page: OvaSheetMap.Page; ss: Sections;
    fitted: ARRAY ProseFields OF Rope; parts: OwnerParts; note: OvaEntities.Note; i: INTEGER;
BEGIN
  OvaSheetMap.Fill(e, RowLines, OvaConfig.oneColumn, pages);
  OvaText.Clear(ss.labels); OvaText.Clear(ss.contents); ss.fluff := NIL;
  FOR i := 0 TO ProseFields - 1 DO fitted[i] := NIL END;
  parts.name := NIL; parts.player := NIL;
  parts.abilityNotes := NIL; parts.attacks := NIL; parts.combatNotes := NIL;

  IF firstEntity THEN
    PutPreamble;
    IF OvaConfig.redraw THEN OvaSheetDraw.PutPreamble(OvaConfig.oneColumn) END;
    firstEntity := FALSE
  END;

  MainProse(ss, fitted[Background], e.name, Background, e.hasBackground, e.background);
  MainProse(ss, fitted[Appearance], e.name, Appearance, e.hasAppearance, e.appearance);
  MainProse(ss, fitted[Personality], e.name, Personality, e.hasPersonality, e.personality);
  MainProse(ss, fitted[OtherNotes], e.name, OtherNotes, e.hasOtherNotes, e.otherNotes);

  FOR i := 0 TO pages.n - 1 DO
    page := pages.items[i](OvaSheetMap.Page);
    IF (i > 0) & ~page.continued THEN
      AddOwnerSections(ss, pages.items[i - 1](OvaSheetMap.Page).owner, parts);
      parts.name := NIL; parts.player := NIL;
      parts.abilityNotes := NIL; parts.attacks := NIL; parts.combatNotes := NIL
    END;
    PutPage1(page, parts)
  END;
  AddOwnerSections(ss, pages.items[pages.n - 1](OvaSheetMap.Page).owner, parts);

  FOR i := 0 TO e.notes.n - 1 DO
    note := e.notes.items[i](OvaEntities.Note);
    AddSection(ss, Ropes.Cat(Label(e.name, ": "), note.header), OvaCommon.Reflow(note.text))
  END;
  IF e.hasCharacterHooks THEN
    AddSection(ss, Label(e.name, ": Character Hooks"), OvaCommon.Reflow(e.characterHooks))
  END;
  IF HasFluffField(e) THEN
    ss.fluff := e; ss.fluffLabel := Label(e.name, ": Fluff")
  END;

  Line(".SP p2");
  IF OvaConfig.redraw THEN Line(OvaSheetDraw.Page2) END;
  FOR i := 0 TO ProseFields - 1 DO PutBlock(fitted[i], proseLook, proseRect[i], ProseLeading) END;
  PutPortrait(e);

  PutSections(ss)
END ProcessEntity;

BEGIN
  firstEntity := TRUE; portraits := 0;

  SetRect(characterName, 14650, 54130, 12980, 1790);
  SetRect(playerName, 28210, 54130, 12780, 1790);

  SetRect(sheetAttacks.name[0], 14330, 20930, 13710, 1240);
  SetRect(sheetAttacks.name[1], 14330, 16970, 13710, 1240);
  SetRect(sheetAttacks.name[2], 14330, 13010, 13710, 1230);
  SetRect(sheetAttacks.name[3], 14330, 9100, 13710, 1230);
  SetRect(sheetAttacks.clause[0], 14330, 18290, 13710, 2640);
  SetRect(sheetAttacks.clause[1], 14330, 14330, 13710, 2640);
  SetRect(sheetAttacks.clause[2], 14330, 10370, 13710, 2640);
  SetRect(sheetAttacks.clause[3], 14330, 6460, 13710, 2640);
  SetRect(sheetAttacks.roll[0], 28270, 18250, 3260, 2690);
  SetRect(sheetAttacks.roll[1], 28270, 14280, 3260, 2880);
  SetRect(sheetAttacks.roll[2], 28270, 10380, 3260, 2760);
  SetRect(sheetAttacks.roll[3], 28270, 6480, 3260, 2760);
  SetRect(sheetAttacks.dx[0], 31760, 18250, 2980, 2690);
  SetRect(sheetAttacks.dx[1], 31760, 14280, 2980, 2880);
  SetRect(sheetAttacks.dx[2], 31760, 10380, 2980, 2760);
  SetRect(sheetAttacks.dx[3], 31760, 6480, 2980, 2760);
  SetRect(sheetAttacks.end[0], 34970, 18250, 3310, 2690);
  SetRect(sheetAttacks.end[1], 34970, 14280, 3310, 2880);
  SetRect(sheetAttacks.end[2], 34970, 10380, 3310, 2760);
  SetRect(sheetAttacks.end[3], 34970, 6480, 3310, 2760);
  (* -C's. *)
  SetRect(oneAttacks.name[0], 17891, 45126, 10517, 1240);
  SetRect(oneAttacks.name[1], 17891, 41176, 10517, 1240);
  SetRect(oneAttacks.name[2], 17891, 37226, 10517, 1240);
  SetRect(oneAttacks.name[3], 17891, 33276, 10517, 1240);
  SetRect(oneAttacks.name[4], 17891, 29326, 10517, 1240);
  SetRect(oneAttacks.clause[0], 17891, 42486, 10517, 2640);
  SetRect(oneAttacks.clause[1], 17891, 38536, 10517, 2640);
  SetRect(oneAttacks.clause[2], 17891, 34586, 10517, 2640);
  SetRect(oneAttacks.clause[3], 17891, 30636, 10517, 2640);
  SetRect(oneAttacks.clause[4], 17891, 26686, 10517, 2640);
  SetRect(oneAttacks.roll[0], 28638, 42446, 3260, 2690);
  SetRect(oneAttacks.roll[1], 28638, 38496, 3260, 2690);
  SetRect(oneAttacks.roll[2], 28638, 34546, 3260, 2690);
  SetRect(oneAttacks.roll[3], 28638, 30596, 3260, 2690);
  SetRect(oneAttacks.roll[4], 28638, 26646, 3260, 2690);
  SetRect(oneAttacks.dx[0], 32128, 42446, 2980, 2690);
  SetRect(oneAttacks.dx[1], 32128, 38496, 2980, 2690);
  SetRect(oneAttacks.dx[2], 32128, 34546, 2980, 2690);
  SetRect(oneAttacks.dx[3], 32128, 30596, 2980, 2690);
  SetRect(oneAttacks.dx[4], 32128, 26646, 2980, 2690);
  SetRect(oneAttacks.end[0], 35338, 42446, 3310, 2690);
  SetRect(oneAttacks.end[1], 35338, 38496, 3310, 2690);
  SetRect(oneAttacks.end[2], 35338, 34546, 3310, 2690);
  SetRect(oneAttacks.end[3], 35338, 30596, 3310, 2690);
  SetRect(oneAttacks.end[4], 35338, 26646, 3310, 2690);
  SetRect(oneNpcType, 32330, 46461, 6646, 2000);
  SetInset(oneCombatNotes, 17847, 8028, 21129, 17100);
  SetRect(oneDefenseBox, 18047, 3588, 5200, 2850);
  SetRect(oneHealthBox, 23400, 3588, 4900, 2850);
  SetRect(oneEnduranceBox, 28400, 3588, 7200, 2850);
  SetRect(oneTvBox, 35800, 3588, 3000, 2850);

  (* The portrait, inside the box's rounded corners. *)
  SetInset(portraitBox, 24040, 27890 + BlockInset, 16280, 28710 - 2 * BlockInset);

  SetInset(combatNotes, 2810, 4680, 11250, 15970);
  SetRect(defenseBox, 14920, 2250, 4660, 2850);
  SetRect(healthBox, 21080, 2250, 4660, 2850);
  SetRect(enduranceBox, 28030, 2250, 4660, 2850);
  SetRect(tvBox, 34590, 2250, 3370, 2850);

  SetInset(proseRect[Background], 3270, 26790, 20630, 28740);
  SetInset(proseRect[Appearance], 3170, 8990, 17230, 14540);
  SetInset(proseRect[Personality], 21140, 8990, 17230, 14540);
  SetInset(proseRect[OtherNotes], 3170, 2050, 35190, 3970);

  SetLook(itemLook, OvaSheetWidths.Italic, 80);
  SetLook(itemCaps, OvaSheetWidths.Regular, 70);
  SetLook(subLook, OvaSheetWidths.LightItalic, 65);
  SetLook(subCaps, OvaSheetWidths.Regular, 55);
  SetLook(diceLook, OvaSheetWidths.Regular, 80);
  SetLook(notesLook, OvaSheetWidths.Regular, 70);
  SetLook(proseLook, OvaSheetWidths.Regular, 80)
END OvaSheet.
