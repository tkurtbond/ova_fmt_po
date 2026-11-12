MODULE OvaForm; (* -X/--form: the official character sheet's form fields as JSON *)

(* The Ada Ova_Fmt.Format_Form: JSON for ova_form.sh, which fills the
   sheet's PDF with qpdf and jq (PLAN.md, "The form script,
   ova_form.sh", and "What -X puts where").

   The output is one JSON array holding an array of fills per main
   entity, in input order, across every input file.  A fill is one
   filled copy of the sheet:

     {"pages": [1, 2], "sub": ["Ability 8"], "fields": {"Character Name": "Fukiko", ...}}

   The first is the main sheet, both pages.  Then come copies of page 1
   (OvaSheetMap: rows, attacks and sub-entities that didn't fit), then
   copies of page 2 holding what the sheet has no room or place for,
   each part opening with a label line of the program's own ("Fukiko:
   Appearance (continued)").  sub names the fields holding built-under
   rows, which the script sets smaller; fields holds only the fields
   with values.

   The form's fields can't grow, so the prose is fitted here, with
   Helvetica's widths and each field's size, in integers so that this
   port and the Ada version agree to the byte.  A one-line field clips,
   so a row too wide for its line is repeated in full on a page-2
   copy.  Indexes here are 0-based where the Ada ones are 1-based, so a
   cut is a count of bytes, the Ada index of the cut's last byte. *)

IMPORT OvaCommon, OvaEntities, OvaOut, OvaSheetMap, OvaText, Ropes;

CONST
  LF = 0AX;

  (* Inner widths and heights of the fields, in tenths of a point;
     leading is 1.2 times the size, so a field of height h at size s
     takes h DIV (s * 12) lines. *)
  RowWidth = 1485;                        (* Ability N, Weakness N *)
  AttackWidth = 1332;                     (* Attack N, Attack Description N *)
  ClauseHeight = 224;
  CombatWidth = 1085;
  CombatHeight = 1557;

  ItemSize = 8; SubSize = 7; AttackSize = 8; ClauseSize = 7; CombatSize = 6; ProseSize = 8;

  (* The fields of page 2, in the order sections are laid into them. *)
  Background = 0; Appearance = 1; Personality = 2; OtherNotes = 3;
  NProse = 4;

TYPE
  Rope = Ropes.Rope;
  String = OvaText.String;

  ProseValues = ARRAY NProse OF Rope;

  (* One filled copy of the sheet.  pages is "1, 2", "1" or "2";
     names[i] is given values[i]. *)
  Fill = POINTER TO FillDesc;
  FillDesc = RECORD (OvaSheetMap.ThingDesc)
    pages: Rope;
    sub: OvaText.List;
    names, values: OvaText.List
  END;

  (* A part of a page-2 copy: label opens it, as a line of its own. *)
  Section = POINTER TO SectionDesc;
  SectionDesc = RECORD (OvaSheetMap.ThingDesc)
    label, content: Rope
  END;

  (* An owner's parts of page-2 copies, gathered over its copies. *)
  OwnerParts = RECORD
    linesInFull, abilityNotes, attacks, combatNotes: Rope
  END;

  (* Where LayOut is in the page-2 copy it is filling. *)
  Layout = RECORD
    values: ProseValues;
    used: BOOLEAN;
    p: INTEGER;
    full: BOOLEAN                         (* past the last field of the copy *)
  END;

VAR
  (* Helvetica's widths, in 1/1000 em, from groff's devpdf font files
     HR (Helvetica; Helvetica-Oblique has the same) and HB
     (Helvetica-Bold), for " " .. "~". *)
  helvetica, helveticaBold: ARRAY 95 OF INTEGER;

  proseName: ARRAY NProse, 12 OF CHAR;
  proseWidth, proseHeight: ARRAY NProse OF INTEGER;

  (* What TrimTrailing and TrimLeading strip. *)
  spaceLF: Ropes.CharSet;

  firstEntity: BOOLEAN;

(* ---- Measuring ---- *)

(* A UTF-8 continuation byte adds nothing; any other non-ASCII byte
   starts a character, counted as wide as a digit.  Control characters
   count nothing. *)
PROCEDURE CharWidth(c: CHAR; bold: BOOLEAN): INTEGER;
BEGIN
  IF (c >= " ") & (c <= "~") THEN
    IF bold THEN RETURN helveticaBold[ORD(c) - ORD(" ")] END;
    RETURN helvetica[ORD(c) - ORD(" ")]
  ELSIF (c >= 80X) & (c <= 0BFX) THEN RETURN 0
  ELSIF c > 0BFX THEN RETURN 556
  END;
  RETURN 0
END CharWidth;

(* Whether r fits on one line of a field width tenths of a point wide:
   inside a 2 pt padding each side, a text of width W at size points
   fits when W * size <= width * 100. *)
PROCEDURE FitsLine(r: Rope; size: INTEGER; bold: BOOLEAN; width: INTEGER): BOOLEAN;
  VAR s: String; i, w: INTEGER;
BEGIN
  s := OvaText.Chars(r); w := 0;
  FOR i := 0 TO SHORT(LEN(s^)) - 2 DO w := w + CharWidth(s[i], bold) END;
  RETURN w * size <= width * 100
END FitsLine;

(* The words of text that fit in maxLines lines of a field width tenths
   wide, wrapped greedily at blanks, each LF starting a new line: the
   number of bytes up to the end of the last word that fits, all of them
   if every word does, 0 if not even the first does.  A word wider than
   the field takes as many lines as it needs, and the line after it is a
   new one.  Exported for TestForm. *)
PROCEDURE FitCut*(text: Rope; size: INTEGER; bold: BOOLEAN; width, maxLines: INTEGER): INTEGER;
  VAR s: String; n, limit, space, lines, cur, cut, i, j, w: INTEGER; fresh: BOOLEAN;
BEGIN
  s := OvaText.Chars(text); n := SHORT(LEN(s^)) - 1;
  limit := width * 100; space := CharWidth(" ", bold) * size;
  lines := 1; fresh := TRUE; cur := 0; cut := 0; i := 0;
  WHILE i < n DO
    IF s[i] = LF THEN
      INC(lines); fresh := TRUE;
      IF lines > maxLines THEN RETURN cut END;
      INC(i)
    ELSIF s[i] = " " THEN INC(i)
    ELSE
      j := i; w := 0;
      WHILE (j < n) & (s[j] # " ") & (s[j] # LF) DO w := w + CharWidth(s[j], bold) * size; INC(j) END;
      IF ~fresh THEN
        IF cur + space + w <= limit THEN cur := cur + space + w
        ELSE INC(lines); fresh := TRUE
        END
      END;
      IF fresh THEN
        IF w <= limit THEN cur := w
        ELSE lines := lines + (w + limit - 1) DIV limit - 1; cur := limit
        END;
        fresh := FALSE
      END;
      IF lines > maxLines THEN RETURN cut END;
      cut := j; i := j
    END
  END;
  RETURN n
END FitCut;

(* The number of bytes of text up to the end of its first word at or
   after from; all of them if there is none. *)
PROCEDURE FirstWordEnd(text: Rope; from: INTEGER): INTEGER;
  VAR s: String; n, i: INTEGER;
BEGIN
  s := OvaText.Chars(text); n := SHORT(LEN(s^)) - 1; i := from;
  WHILE (i < n) & ((s[i] = " ") OR (s[i] = LF)) DO INC(i) END;
  WHILE (i < n) & (s[i] # " ") & (s[i] # LF) DO INC(i) END;
  RETURN i
END FirstWordEnd;

(* r without trailing blanks and LFs. *)
PROCEDURE TrimTrailing(r: Rope): Rope;
BEGIN RETURN Ropes.Substring(r, 0, Ropes.RIndexSet(r, spaceLF, FALSE, Ropes.Length(r) - 1) + 1)
END TrimTrailing;

(* r without leading blanks and LFs. *)
PROCEDURE TrimLeading(r: Rope): Rope;
  VAR first: LONGINT;
BEGIN
  first := Ropes.IndexSet(r, spaceLF, FALSE, 0);
  IF first < 0 THEN RETURN NIL END;
  RETURN Ropes.Substring(r, first, Ropes.Length(r) - first)
END TrimLeading;

(* text split into what fits a field and the rest, the field taking at
   least one word. *)
PROCEDURE Fit(text: Rope; size: INTEGER; bold: BOOLEAN; width, maxLines: INTEGER; VAR fitted, rest: Rope);
  VAR cut: INTEGER;
BEGIN
  cut := FitCut(text, size, bold, width, maxLines);
  IF cut = 0 THEN cut := FirstWordEnd(text, 0) END;
  fitted := TrimTrailing(Ropes.Substring(text, 0, cut));
  rest := TrimLeading(Ropes.Substring(text, cut, Ropes.Length(text) - cut))
END Fit;

(* ---- Text ---- *)

(* YAML prose as a field holds it: each line trimmed (of blanks, tabs,
   LFs and CRs, as OvaText.Trim does), a paragraph's lines joined with
   blanks, paragraphs (separated by blank lines) with a single LF.  The
   form wraps the lines itself.  Exported for TestForm. *)
PROCEDURE Reflow*(r: Rope): Rope;
  VAR result, line: Rope; inPara, break: BOOLEAN; from, to, n: LONGINT;
BEGIN
  result := NIL; inPara := FALSE; break := FALSE;
  n := Ropes.Length(r); from := 0;
  WHILE from <= n DO
    to := Ropes.IndexChar(r, LF, from);
    IF to < 0 THEN to := n END;
    line := OvaText.Trim(Ropes.Substring(r, from, to - from));
    IF Ropes.Length(line) = 0 THEN break := inPara
    ELSE
      IF inPara THEN
        IF break THEN result := Ropes.AppendChar(result, LF) ELSE result := Ropes.AppendChar(result, " ") END
      END;
      result := Ropes.Cat(result, line);
      inPara := TRUE; break := FALSE
    END;
    from := to + 1
  END;
  RETURN result
END Reflow;

(* r as a JSON string's contents.  Exported for TestForm. *)
PROCEDURE Escape*(r: Rope): Rope;
  VAR s, t: String; i, k: INTEGER; c: CHAR; hex: ARRAY 17 OF CHAR;

  PROCEDURE Put2(a, b: CHAR);
  BEGIN t[k] := a; t[k + 1] := b; INC(k, 2)
  END Put2;

BEGIN
  hex := "0123456789abcdef";
  s := OvaText.Chars(r);
  NEW(t, 6 * (LEN(s^) - 1) + 1); k := 0;
  FOR i := 0 TO SHORT(LEN(s^)) - 2 DO
    c := s[i];
    IF c = '"' THEN Put2("\", '"')
    ELSIF c = "\" THEN Put2("\", "\")
    ELSIF c = LF THEN Put2("\", "n")
    ELSIF c = 0DX THEN Put2("\", "r")
    ELSIF c = 09X THEN Put2("\", "t")
    ELSIF c = 08X THEN Put2("\", "b")
    ELSIF c = 0CX THEN Put2("\", "f")
    ELSIF c < " " THEN Put2("\", "u"); Put2("0", "0"); Put2(hex[ORD(c) DIV 16], hex[ORD(c) MOD 16])
    ELSE t[k] := c; INC(k)
    END
  END;
  RETURN Ropes.FromSubstring(t^, 0, k)
END Escape;

PROCEDURE Str(s: ARRAY OF CHAR): Rope;
BEGIN RETURN Ropes.FromString(s)
END Str;

(* s, then n in decimal. *)
PROCEDURE Numbered(s: ARRAY OF CHAR; n: INTEGER): Rope;
BEGIN RETURN Ropes.Cat(Str(s), OvaText.Int(n))
END Numbered;

(* ---- Fills and the fields' geometry ---- *)

PROCEDURE NewFill(pages: ARRAY OF CHAR): Fill;
  VAR f: Fill;
BEGIN
  NEW(f); f.pages := Str(pages);
  OvaText.Clear(f.sub); OvaText.Clear(f.names); OvaText.Clear(f.values);
  RETURN f
END NewFill;

PROCEDURE Set(f: Fill; name, value: Rope);
BEGIN OvaText.Append(f.names, name); OvaText.Append(f.values, value)
END Set;

PROCEDURE SetS(f: Fill; name: ARRAY OF CHAR; value: Rope);
BEGIN Set(f, Str(name), value)
END SetS;

PROCEDURE MaxLines(height, size: INTEGER): INTEGER;
BEGIN
  IF height DIV (size * 12) < 1 THEN RETURN 1 END;
  RETURN height DIV (size * 12)
END MaxLines;

PROCEDURE SetProse(f: Fill; VAR v: ProseValues);
  VAR p: INTEGER;
BEGIN
  FOR p := 0 TO NProse - 1 DO
    IF Ropes.Length(v[p]) > 0 THEN SetS(f, proseName[p], v[p]) END
  END
END SetProse;

PROCEDURE AddSection(VAR sections: OvaSheetMap.Seq; label, content: Rope);
  VAR s: Section;
BEGIN
  IF Ropes.Length(content) > 0 THEN
    NEW(s); s.label := label; s.content := content; OvaSheetMap.Append(sections, s)
  END
END AddSection;

(* line added to lines, LF-separated. *)
PROCEDURE AddLine(VAR lines: Rope; line: Rope);
BEGIN
  IF Ropes.Length(lines) > 0 THEN lines := Ropes.AppendChar(lines, LF) END;
  lines := Ropes.Cat(lines, line)
END AddLine;

(* ---- Page 1 ---- *)

(* The text of a row's name field: a built-under row is indented. *)
PROCEDURE RowText(r: OvaSheetMap.Row): Rope;
  VAR t: Rope;
BEGIN
  CASE r.kind OF
    OvaSheetMap.Item: t := r.text
  | OvaSheetMap.Sub: t := Str("    "); t := Ropes.Cat(t, r.level); t := Ropes.AppendChar(t, " "); t := Ropes.Cat(t, r.text)
  | OvaSheetMap.Spell: t := Str("    "); t := Ropes.Cat(t, r.text)
  END;
  RETURN t
END RowText;

PROCEDURE RowFits(r: OvaSheetMap.Row): BOOLEAN;
  VAR size: INTEGER;
BEGIN
  IF r.kind = OvaSheetMap.Item THEN size := ItemSize ELSE size := SubSize END;
  RETURN FitsLine(RowText(r), size, FALSE, RowWidth)
END RowFits;

(* A row as "Lines in Full" gives it: its level and text. *)
PROCEDURE RowInFull(r: OvaSheetMap.Row): Rope;
  VAR t: Rope;
BEGIN
  IF (r.kind = OvaSheetMap.Item) & (Ropes.Length(r.level) > 0) THEN
    t := Ropes.AppendChar(r.level, " "); RETURN Ropes.Cat(t, r.text)
  END;
  RETURN TrimLeading(RowText(r))
END RowInFull;

PROCEDURE SetRows(f: Fill; VAR parts: OwnerParts; rows: OvaSheetMap.Seq; dicePrefix, namePrefix: ARRAY OF CHAR);
  VAR r: OvaSheetMap.Row; name: Rope; n: INTEGER;
BEGIN
  FOR n := 1 TO rows.n DO
    r := rows.items[n - 1](OvaSheetMap.Row);
    name := Numbered(namePrefix, n);
    IF (r.kind = OvaSheetMap.Item) & (Ropes.Length(r.level) > 0) THEN Set(f, Numbered(dicePrefix, n), r.level) END;
    Set(f, name, RowText(r));
    IF r.kind # OvaSheetMap.Item THEN OvaText.Append(f.sub, name) END;
    IF ~RowFits(r) THEN AddLine(parts.linesInFull, RowInFull(r)) END;
    IF r.hasNote THEN AddLine(parts.abilityNotes, Reflow(r.note)) END
  END
END SetRows;

PROCEDURE SetAttacks(f: Fill; VAR parts: OwnerParts; attacks: OvaSheetMap.Seq);
  VAR a: OvaSheetMap.AttackSlot; suffix, entry: Rope; n: INTEGER; clipped: BOOLEAN;
BEGIN
  FOR n := 1 TO attacks.n DO
    a := attacks.items[n - 1](OvaSheetMap.AttackSlot);
    IF n = 1 THEN suffix := NIL ELSE suffix := Numbered("_", n) END;
    clipped := (Ropes.Length(a.clause) > 0) &
      (FitCut(a.clause, ClauseSize, TRUE, AttackWidth, MaxLines(ClauseHeight, ClauseSize)) # Ropes.Length(a.clause));
    Set(f, Numbered("Attack ", n), a.name);
    IF Ropes.Length(a.clause) > 0 THEN Set(f, Numbered("Attack Description ", n), a.clause) END;
    Set(f, Ropes.Cat(Str("roll"), suffix), a.roll);
    Set(f, Ropes.Cat(Str("dx"), suffix), a.dx);
    Set(f, Ropes.Cat(Str("end"), suffix), a.endurance);
    IF a.hasDescription OR clipped OR ~FitsLine(a.name, AttackSize, TRUE, AttackWidth) THEN
      entry := a.name;
      IF clipped THEN OvaText.Add(entry, " ("); entry := Ropes.AppendChar(Ropes.Cat(entry, a.clause), ")") END;
      IF a.hasDescription THEN OvaText.Add(entry, ": "); entry := Ropes.Cat(entry, Reflow(a.description)) END;
      AddLine(parts.attacks, entry)
    END
  END
END SetAttacks;

PROCEDURE Page1Fill(p: OvaSheetMap.Page; VAR parts: OwnerParts): Fill;
  VAR f: Fill; notes, fitted: Rope;
BEGIN
  f := NewFill("1");
  SetS(f, "Character Name", p.title);
  IF p.hasPlayer THEN SetS(f, "Player Name", p.player) END;
  SetRows(f, parts, p.abilities, "Abilities Dice", "Ability ");
  SetRows(f, parts, p.weaknesses, "Weakness Dice ", "Weakness ");
  SetAttacks(f, parts, p.attacks);
  notes := NIL;
  IF Ropes.Length(p.npcType) > 0 THEN notes := Ropes.Cat(Str("NPC Type: "), p.npcType) END;
  IF p.hasCombatNotes THEN AddLine(notes, Reflow(p.combatNotes)) END;
  IF Ropes.Length(notes) > 0 THEN
    Fit(notes, CombatSize, FALSE, CombatWidth, MaxLines(CombatHeight, CombatSize), fitted, parts.combatNotes);
    SetS(f, "Combat Notes", fitted)
  END;
  IF p.hasStats THEN
    SetS(f, "Defense", p.defense);
    SetS(f, "Health", p.health);
    SetS(f, "Endurance", p.endurance);
    IF Ropes.Length(p.threatValue) > 0 THEN SetS(f, "TV", p.threatValue) END
  END;
  RETURN f
END Page1Fill;

(* owner, then s. *)
PROCEDURE Label(owner: Rope; s: ARRAY OF CHAR): Rope;
BEGIN RETURN Ropes.Cat(owner, Str(s))
END Label;

PROCEDURE AddOwnerSections(VAR sections: OvaSheetMap.Seq; owner: Rope; VAR parts: OwnerParts);
BEGIN
  AddSection(sections, Label(owner, ": Lines in Full"), parts.linesInFull);
  AddSection(sections, Label(owner, ": Ability Notes"), parts.abilityNotes);
  AddSection(sections, Label(owner, ": Attacks"), parts.attacks);
  AddSection(sections, Label(owner, ": Combat Notes (continued)"), parts.combatNotes)
END AddOwnerSections;

(* ---- Page 2 ---- *)

PROCEDURE ClearLayout(VAR l: Layout);
  VAR p: INTEGER;
BEGIN
  FOR p := 0 TO NProse - 1 DO l.values[p] := NIL END;
  l.used := FALSE; l.p := 0; l.full := FALSE
END ClearLayout;

PROCEDURE NextField(VAR l: Layout);
BEGIN
  IF l.p = NProse - 1 THEN l.full := TRUE ELSE INC(l.p) END
END NextField;

(* The page-2 copy l has filled, appended to fills; l starts another. *)
PROCEDURE Emit(VAR l: Layout; VAR fills: OvaSheetMap.Seq);
  VAR f: Fill;
BEGIN
  f := NewFill("2"); SetProse(f, l.values); OvaSheetMap.Append(fills, f);
  ClearLayout(l)
END Emit;

(* The sections laid into page-2 copies' fields in order, each section
   after the one before it in the same field, a field taking what fits
   and the rest going on to the next field or copy, the label repeated
   there with " (continued)". *)
PROCEDURE LayOut(sections: OvaSheetMap.Seq; VAR fills: OvaSheetMap.Seq);
  VAR l: Layout; s: Section; remaining, existing, label, prefix, candidate: Rope;
    i, prefixLen, len, cut: INTEGER; first: BOOLEAN;
BEGIN
  ClearLayout(l);
  FOR i := 0 TO sections.n - 1 DO
    s := sections.items[i](Section);
    remaining := s.content; first := TRUE;
    LOOP
      IF l.full THEN Emit(l, fills) END;
      existing := l.values[l.p];
      label := s.label;
      IF ~first THEN OvaText.Add(label, " (continued)") END;
      prefix := NIL;
      IF Ropes.Length(existing) > 0 THEN prefix := Ropes.AppendChar(Ropes.AppendChar(existing, LF), LF) END;
      prefix := Ropes.AppendChar(Ropes.Cat(prefix, label), LF);
      prefixLen := SHORT(Ropes.Length(prefix));
      candidate := Ropes.Cat(prefix, remaining);
      len := SHORT(Ropes.Length(candidate));
      cut := FitCut(candidate, ProseSize, FALSE, proseWidth[l.p], MaxLines(proseHeight[l.p], ProseSize));
      IF cut = len THEN l.values[l.p] := candidate; l.used := TRUE; EXIT END;
      IF (cut <= prefixLen) & (Ropes.Length(existing) = 0) THEN cut := FirstWordEnd(candidate, prefixLen) END;
      IF cut > prefixLen THEN
        l.values[l.p] := TrimTrailing(Ropes.Substring(candidate, 0, cut));
        l.used := TRUE;
        remaining := TrimLeading(Ropes.Substring(candidate, cut, len - cut));
        first := FALSE;
        IF Ropes.Length(remaining) = 0 THEN EXIT END
      END;
      NextField(l)
    END
  END;
  IF l.used THEN Emit(l, fills) END
END LayOut;

(* ---- Output ---- *)

PROCEDURE PutString(r: Rope);
BEGIN OvaOut.Char('"'); OvaOut.Rope(Escape(r)); OvaOut.Char('"')
END PutString;

PROCEDURE PutFill(f: Fill);
  VAR i: INTEGER;
BEGIN
  OvaOut.String("    {"); OvaOut.Ln;
  OvaOut.String('      "pages": ['); OvaOut.Rope(f.pages); OvaOut.String("],"); OvaOut.Ln;
  OvaOut.String('      "sub": [');
  FOR i := 0 TO f.sub.n - 1 DO
    IF i > 0 THEN OvaOut.String(", ") END;
    PutString(f.sub.items[i])
  END;
  OvaOut.String("],"); OvaOut.Ln;
  OvaOut.String('      "fields": {'); OvaOut.Ln;
  FOR i := 0 TO f.names.n - 1 DO
    OvaOut.String("        "); PutString(f.names.items[i]); OvaOut.String(": "); PutString(f.values.items[i]);
    IF i < f.names.n - 1 THEN OvaOut.Char(",") END;
    OvaOut.Ln
  END;
  OvaOut.String("      }"); OvaOut.Ln;
  OvaOut.String("    }")
END PutFill;

(* The main prose field p, fitted into main2[p], the rest a section of
   its own. *)
PROCEDURE MainProse(p: INTEGER; has: BOOLEAN; text, name: Rope; VAR main2: ProseValues;
                    VAR sections: OvaSheetMap.Seq);
  VAR content, rest, label: Rope;
BEGIN
  IF has THEN content := Reflow(text) ELSE content := NIL END;
  IF Ropes.Length(content) > 0 THEN
    Fit(content, ProseSize, FALSE, proseWidth[p], MaxLines(proseHeight[p], ProseSize), main2[p], rest);
    label := Label(name, ": "); OvaText.Add(label, proseName[p]); OvaText.Add(label, " (continued)");
    AddSection(sections, label, rest)
  END
END MainProse;

(* e's fills, after a "[" or "," as needed. *)
PROCEDURE ProcessEntity*(e: OvaEntities.Entity);
  VAR pages, fills, sections: OvaSheetMap.Seq; main2: ProseValues; parts, none: OwnerParts;
    page: OvaSheetMap.Page; note: OvaEntities.Note; main: Fill; i: INTEGER;
BEGIN
  OvaSheetMap.Fill(e, pages);
  OvaSheetMap.Clear(fills); OvaSheetMap.Clear(sections);
  FOR i := 0 TO NProse - 1 DO main2[i] := NIL END;
  none.linesInFull := NIL; none.abilityNotes := NIL; none.attacks := NIL; none.combatNotes := NIL;
  parts := none;

  MainProse(Background, e.hasBackground, e.background, e.name, main2, sections);
  MainProse(Appearance, e.hasAppearance, e.appearance, e.name, main2, sections);
  MainProse(Personality, e.hasPersonality, e.personality, e.name, main2, sections);
  MainProse(OtherNotes, e.hasOtherNotes, e.otherNotes, e.name, main2, sections);

  FOR i := 0 TO pages.n - 1 DO
    page := pages.items[i](OvaSheetMap.Page);
    IF (i > 0) & ~page.continued THEN
      AddOwnerSections(sections, pages.items[i - 1](OvaSheetMap.Page).owner, parts);
      parts := none
    END;
    OvaSheetMap.Append(fills, Page1Fill(page, parts))
  END;
  AddOwnerSections(sections, pages.items[pages.n - 1](OvaSheetMap.Page).owner, parts);

  FOR i := 0 TO e.notes.n - 1 DO
    note := e.notes.items[i](OvaEntities.Note);
    AddSection(sections, Ropes.Cat(Label(e.name, ": "), note.header), Reflow(note.text))
  END;
  IF e.hasCharacterHooks THEN
    AddSection(sections, Label(e.name, ": Character Hooks"), Reflow(e.characterHooks))
  END;

  (* The main sheet is both pages. *)
  main := fills.items[0](Fill);
  main.pages := Str("1, 2");
  SetProse(main, main2);

  LayOut(sections, fills);

  IF firstEntity THEN OvaOut.Char("[") ELSE OvaOut.Char(",") END;
  OvaOut.Ln;
  firstEntity := FALSE;
  OvaOut.String("  ["); OvaOut.Ln;
  FOR i := 0 TO fills.n - 1 DO
    PutFill(fills.items[i](Fill));
    IF i < fills.n - 1 THEN OvaOut.Char(",") END;
    OvaOut.Ln
  END;
  OvaOut.String("  ]")
END ProcessEntity;

(* Closes the array, or writes "[]" if there were no entities.  Call
   once, after the last entity of the last file. *)
PROCEDURE Finish*;
BEGIN
  IF firstEntity THEN OvaOut.String("[]"); OvaOut.Ln
  ELSE OvaOut.Ln; OvaOut.Char("]"); OvaOut.Ln
  END
END Finish;

(* ---- Initialization ---- *)

(* The widths in s, decimal numbers separated by blanks, into t from
   t[at]. *)
PROCEDURE Widths(VAR t: ARRAY OF INTEGER; at: INTEGER; s: ARRAY OF CHAR);
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
END Widths;

PROCEDURE Prose(p: INTEGER; name: ARRAY OF CHAR; width, height: INTEGER);
BEGIN COPY(name, proseName[p]); proseWidth[p] := width; proseHeight[p] := height
END Prose;

BEGIN
  Widths(helvetica, 0, "278 278 355 556 556 889 667 222 333 333 389 584 278 333 278 278");
  Widths(helvetica, 16, "556 556 556 556 556 556 556 556 556 556 278 278 584 584 584 556");
  Widths(helvetica, 32, "1015 667 667 722 722 667 611 778 722 278 500 667 556 833 722 778");
  Widths(helvetica, 48, "667 778 722 667 611 722 667 944 667 667 611 278 278 278 333 556");
  Widths(helvetica, 64, "222 556 556 500 556 556 278 556 556 222 222 500 222 833 556 556");
  Widths(helvetica, 80, "556 556 333 500 278 556 500 722 500 500 500 334 260 334 333");
  Widths(helveticaBold, 0, "278 333 474 556 556 889 722 278 333 333 389 584 278 333 278 278");
  Widths(helveticaBold, 16, "556 556 556 556 556 556 556 556 556 556 333 333 584 584 584 611");
  Widths(helveticaBold, 32, "975 722 722 722 722 667 611 778 722 278 556 722 611 833 722 778");
  Widths(helveticaBold, 48, "667 778 722 667 611 722 667 944 667 667 611 333 278 333 333 556");
  Widths(helveticaBold, 64, "278 556 611 556 611 556 333 611 611 278 278 556 278 889 611 611");
  Widths(helveticaBold, 80, "611 611 389 556 333 611 556 778 556 556 500 389 280 389 333");
  Prose(Background, "Background", 2023, 2834);
  Prose(Appearance, "Appearance", 1683, 1414);
  Prose(Personality, "Personality", 1682, 1414);
  Prose(OtherNotes, "Other Notes", 3480, 357);
  Ropes.MakeCharSet(" ", spaceLF); spaceLF.has[0AH] := TRUE;
  firstEntity := TRUE
END OvaForm.
