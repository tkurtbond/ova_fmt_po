MODULE OvaRst; (* The reST formats: terse, HTML-in-reST and groff-in-reST *)

(* The Ada Ova_Fmt.Format_Rst: every format that writes a reST document
   for pandoc.  Terse is OvaCommon's; this module adds HTML-in-reST
   (-H: one ".. raw:: html" block of nested <table>s for the abilities,
   weaknesses and combat) and groff-in-reST (-G: ".. raw:: ms" blocks of
   groff hd tables, laid out like the rulebook's Sample Characters
   spread).  The Ada package's comments record why each layout is as it
   is, including the hd quirks that Put_Cell, Put_Caption and the
   ".ne" lines work around; the comments here only summarize. *)

IMPORT OvaCommon, OvaConfig, OvaEntities, OvaOut, OvaText, Ropes;

CONST
  (* A reST raw block's indent. *)
  RawPrefix = "   ";

TYPE
  Rope = Ropes.Rope;

VAR
  html: Ropes.CharSet;     (* the characters HtmlEscape replaces *)
  inRaw: BOOLEAN;          (* a ".. raw:: ms" block is open: PrintGroffTables *)

PROCEDURE Str(s: ARRAY OF CHAR): Rope;
BEGIN RETURN Ropes.FromString(s)
END Str;

PROCEDURE Line(r: Rope);
BEGIN OvaCommon.Line(r)
END Line;

(* A line of a raw block: its indent, then indent, then s. *)
PROCEDURE Raw(indent: Rope; s: ARRAY OF CHAR);
BEGIN OvaOut.String(RawPrefix); OvaOut.Rope(indent); OvaOut.String(s); OvaOut.Ln
END Raw;

(* The same, with a rope. *)
PROCEDURE RawRope(indent, r: Rope);
BEGIN OvaOut.String(RawPrefix); OvaOut.Rope(indent); Line(r)
END RawRope;

(* ---- HTML-in-reST ---- *)

(* r with &, < and > as entities: for every piece of text that goes in a
   table cell.  " needn't be: nothing is written in an attribute. *)
PROCEDURE HtmlEscape(r: Rope): Rope;
  VAR out: Rope; from, i: LONGINT; c: CHAR;
BEGIN
  out := NIL; from := 0;
  LOOP
    i := Ropes.IndexSet(r, html, TRUE, from);
    IF i < 0 THEN EXIT END;
    out := Ropes.Cat(out, Ropes.Substring(r, from, i - from));
    c := Ropes.Fetch(r, i);
    IF c = "&" THEN OvaText.Add(out, "&amp;")
    ELSIF c = "<" THEN OvaText.Add(out, "&lt;")
    ELSE OvaText.Add(out, "&gt;")
    END;
    from := i + 1
  END;
  IF from = 0 THEN RETURN r END;
  RETURN Ropes.Cat(out, Ropes.Substring(r, from, Ropes.Length(r) - from))
END HtmlEscape;

(* r without the parentheses around it, if it has them: a clause from
   OvaCommon, built for a sentence, in a table cell. *)
PROCEDURE StripParens(r: Rope): Rope;
  VAR len: LONGINT;
BEGIN
  len := Ropes.Length(r);
  IF (len >= 2) & (Ropes.Fetch(r, 0) = "(") & (Ropes.Fetch(r, len - 1) = ")") THEN
    RETURN Ropes.Substring(r, 1, len - 2)
  END;
  RETURN r
END StripParens;

(* The detail of an item, or NIL if it hasn't one. *)
PROCEDURE DetailOf(n: OvaEntities.Named): Rope;
BEGIN
  IF n.hasDetail THEN RETURN n.detail END;
  RETURN NIL
END DetailOf;

(* Appends "<td>cell</td>" to r. *)
PROCEDURE Cells(VAR r: Rope; cell: Rope);
BEGIN OvaText.Add(r, "<td>"); r := Ropes.Cat(r, cell); OvaText.Add(r, "</td>")
END Cells;

PROCEDURE Caption(indent, caption: Rope);
  VAR r: Rope;
BEGIN
  r := Ropes.Cat(Str("<caption>"), HtmlEscape(caption)); OvaText.Add(r, "</caption>");
  RawRope(indent, r)
END Caption;

PROCEDURE PrintSubItemTable(items: OvaEntities.List; caption, indent: Rope);
  VAR i: INTEGER; s: OvaEntities.SubItem; r: Rope;
BEGIN
  IF items.n = 0 THEN RETURN END;
  Raw(indent, "<table>");
  Caption(indent, caption);
  Raw(indent, "<tr><th>Name</th><th>Level</th><th>Detail</th><th>Perks/Flaws</th></tr>");
  FOR i := 0 TO items.n - 1 DO
    s := items.items[i](OvaEntities.SubItem);
    r := Str("<tr>");
    Cells(r, HtmlEscape(s.name)); Cells(r, OvaCommon.SignedImg(s.level));
    Cells(r, HtmlEscape(DetailOf(s)));
    Cells(r, HtmlEscape(StripParens(OvaCommon.FormatModifiersBracket(s.perks, s.flaws))));
    OvaText.Add(r, "</tr>");
    RawRope(indent, r)
  END;
  Raw(indent, "</table>")
END PrintSubItemTable;

PROCEDURE PrintSpellsTable(spells: OvaEntities.List; caption, indent: Rope);
  VAR i: INTEGER; s: OvaEntities.Spell; r: Rope;
BEGIN
  IF spells.n = 0 THEN RETURN END;
  Raw(indent, "<table>");
  Caption(indent, caption);
  Raw(indent, "<tr><th>Name</th><th>Ability</th><th>Level</th><th>Endurance</th></tr>");
  FOR i := 0 TO spells.n - 1 DO
    s := spells.items[i](OvaEntities.Spell);
    r := Str("<tr>");
    Cells(r, HtmlEscape(s.name)); Cells(r, HtmlEscape(s.ability));
    Cells(r, OvaCommon.SignedImg(s.level)); Cells(r, HtmlEscape(s.endurance));
    OvaText.Add(r, "</tr>");
    RawRope(indent, r)
  END;
  Raw(indent, "</table>")
END PrintSpellsTable;

PROCEDURE PrintAttacksTable(attacks: OvaEntities.List; caption, indent: Rope);
  VAR i: INTEGER; a: OvaEntities.Attack; r, d: Rope;
BEGIN
  IF attacks.n = 0 THEN RETURN END;
  Raw(indent, "<table>");
  Caption(indent, caption);
  Raw(indent, "<tr><th>Name</th><th>Roll</th><th>DX</th><th>Endurance Cost</th><th>Perks/Flaws</th><th>Description</th></tr>");
  FOR i := 0 TO attacks.n - 1 DO
    a := attacks.items[i](OvaEntities.Attack);
    r := Str("<tr>");
    Cells(r, HtmlEscape(a.name)); Cells(r, OvaCommon.NumberImg(a.roll));
    Cells(r, HtmlEscape(a.dx)); Cells(r, OvaCommon.TrimImg(a.endurance));
    Cells(r, HtmlEscape(StripParens(OvaCommon.FormatAttackClause(a))));
    IF a.hasDescription THEN d := HtmlEscape(a.description) ELSE d := NIL END;
    Cells(r, d);
    OvaText.Add(r, "</tr>");
    RawRope(indent, r)
  END;
  Raw(indent, "</table>")
END PrintAttacksTable;

PROCEDURE PrintCombatTable(c: OvaEntities.Combat; caption, indent: Rope);
  VAR r, tv: Rope;
BEGIN
  IF ~c.hasCombat THEN RETURN END;
  Raw(indent, "<table>");
  Caption(indent, caption);
  Raw(indent, "<tr><th>Health</th><th>Endurance</th><th>Defense</th><th>Threat Value</th></tr>");
  r := Str("<tr>");
  Cells(r, OvaCommon.TrimImg(c.health)); Cells(r, OvaCommon.TrimImg(c.endurance));
  Cells(r, HtmlEscape(c.defense));
  IF c.hasThreatValue THEN tv := OvaCommon.TrimImg(c.threatValue) ELSE tv := Str("—") END;
  Cells(r, tv);
  OvaText.Add(r, "</tr>");
  RawRope(indent, r);
  Raw(indent, "</table>");
  PrintAttacksTable(c.attacks, Ropes.Cat(caption, Str(" — Attacks")), indent)
END PrintCombatTable;

(* A Companion's or Vehicle's tables, in its granting ability's cell.
   With fragment: true, one "Attributes:" paragraph instead of two
   tables: there is no leaving raw HTML inside a cell. *)
PROCEDURE PrintSubEntityTables(se: OvaEntities.SubEntity; indent: Rope);
  VAR who, r: Rope;
BEGIN
  who := OvaCommon.SubEntityTitle(se);
  IF se.isFragment THEN
    IF (se.abilities.n = 0) & (se.weaknesses.n = 0) THEN
      r := Ropes.Cat(Str("<p><strong>"), HtmlEscape(who)); OvaText.Add(r, "</strong>.</p>")
    ELSE
      r := Ropes.Cat(Str("<p><strong>"), HtmlEscape(who));
      OvaText.Add(r, "</strong> -- <strong>Attributes:</strong> ");
      r := Ropes.Cat(r, OvaCommon.Semi(HtmlEscape(OvaCommon.JoinFragmentSubItems(se.abilities)),
        HtmlEscape(OvaCommon.JoinFragmentSubItems(se.weaknesses)), se.abilities.n > 0, se.weaknesses.n > 0));
      OvaText.Add(r, ".</p>")
    END;
    RawRope(indent, r);
    PrintCombatTable(se.combat, Ropes.Cat(who, Str(" — Combat")), indent);
    RETURN
  END;
  PrintSubItemTable(se.abilities, Ropes.Cat(who, Str(" — Abilities")), indent);
  PrintSubItemTable(se.weaknesses, Ropes.Cat(who, Str(" — Weaknesses")), indent);
  PrintCombatTable(se.combat, Ropes.Cat(who, Str(" — Combat")), indent)
END PrintSubEntityTables;

(* The extra cell of an ability that grants linked content. *)
PROCEDURE PrintLinkedContentCell(a: OvaEntities.Ability; indent: Rope);
  VAR inner: Rope;
BEGIN
  inner := Ropes.Cat(indent, Str("  "));
  IF a.subEntity # NIL THEN PrintSubEntityTables(a.subEntity, inner) END;
  IF (a.subAbilities.n > 0) OR (a.subWeaknesses.n > 0) THEN
    PrintSubItemTable(a.subAbilities, Ropes.Cat(a.name, Str(" — Grants (Abilities)")), inner);
    PrintSubItemTable(a.subWeaknesses, Ropes.Cat(a.name, Str(" — Grants (Weaknesses)")), inner)
  END;
  IF a.spells.n > 0 THEN PrintSpellsTable(a.spells, Ropes.Cat(a.name, Str(" — Spells")), inner) END
END PrintLinkedContentCell;

PROCEDURE PrintAbilityRow(a: OvaEntities.Ability; indent: Rope);
  VAR r: Rope;
BEGIN
  r := Str("<tr>");
  Cells(r, HtmlEscape(a.name)); Cells(r, OvaCommon.SignedImg(a.level));
  Cells(r, HtmlEscape(DetailOf(a)));
  Cells(r, HtmlEscape(StripParens(OvaCommon.FormatModifiersBracket(a.perks, a.flaws))));
  OvaOut.String(RawPrefix); OvaOut.Rope(indent); OvaOut.Rope(r);
  IF ~OvaCommon.HasLinked(a) THEN
    OvaOut.String("</tr>"); OvaOut.Ln
  ELSE
    OvaOut.Ln;
    Raw(indent, "  <td>");
    PrintLinkedContentCell(a, Ropes.Cat(indent, Str("  ")));
    Raw(indent, "  </td>");
    Raw(indent, "</tr>")
  END
END PrintAbilityRow;

PROCEDURE PrintAbilitiesTable(abilities: OvaEntities.List);
  VAR i: INTEGER;
BEGIN
  IF abilities.n = 0 THEN RETURN END;
  Raw(NIL, "<table>");
  Raw(NIL, "<caption>Abilities</caption>");
  Raw(NIL, "<tr><th>Name</th><th>Level</th><th>Detail</th><th>Perks/Flaws</th></tr>");
  FOR i := 0 TO abilities.n - 1 DO PrintAbilityRow(abilities.items[i](OvaEntities.Ability), NIL) END;
  Raw(NIL, "</table>");
  OvaOut.Ln
END PrintAbilitiesTable;

PROCEDURE PrintWeaknessesTable(weaknesses: OvaEntities.List);
  VAR i: INTEGER; w: OvaEntities.Weakness; r: Rope;
BEGIN
  IF weaknesses.n = 0 THEN RETURN END;
  Raw(NIL, "<table>");
  Raw(NIL, "<caption>Weaknesses</caption>");
  Raw(NIL, "<tr><th>Name</th><th>Level</th><th>Detail</th></tr>");
  FOR i := 0 TO weaknesses.n - 1 DO
    w := weaknesses.items[i](OvaEntities.Weakness);
    r := Str("<tr>");
    Cells(r, HtmlEscape(w.name)); Cells(r, OvaCommon.SignedImg(w.level));
    Cells(r, HtmlEscape(DetailOf(w)));
    OvaText.Add(r, "</tr>");
    RawRope(NIL, r)
  END;
  Raw(NIL, "</table>");
  OvaOut.Ln
END PrintWeaknessesTable;

PROCEDURE PrintHtmlTables(e: OvaEntities.Entity);
BEGIN
  IF (e.abilities.n = 0) & (e.weaknesses.n = 0) & ~e.combat.hasCombat THEN RETURN END;
  OvaOut.String(".. raw:: html"); OvaOut.Ln;
  OvaOut.Ln;
  PrintAbilitiesTable(e.abilities);
  PrintWeaknessesTable(e.weaknesses);
  PrintCombatTable(e.combat, Str("Combat"), NIL);
  OvaOut.Ln
END PrintHtmlTables;

(* ---- groff-in-reST ---- *)

(* r with every backslash as troff's "\e", and "\&" in front if it
   starts with "." or "'", which would make a line of it a request. *)
PROCEDURE GroffEscape(r: Rope): Rope;
  VAR out: Rope; from, i: LONGINT; c: CHAR;
BEGIN
  out := NIL; from := 0;
  LOOP
    i := Ropes.IndexChar(r, "\", from);
    IF i < 0 THEN EXIT END;
    out := Ropes.Cat(out, Ropes.Substring(r, from, i - from)); OvaText.Add(out, "\e");
    from := i + 1
  END;
  IF from = 0 THEN out := r ELSE out := Ropes.Cat(out, Ropes.Substring(r, from, Ropes.Length(r) - from)) END;
  IF out # NIL THEN
    c := Ropes.Fetch(out, 0);
    IF (c = ".") OR (c = "'") THEN out := Ropes.Cat(Str("\&"), out) END
  END;
  RETURN out
END GroffEscape;

(* "Name (detail) [Perks: ...] (note)", and " — see below" if it grants
   a sub-entity, written in its own section after this one. *)
PROCEDURE ItemCellText(s: OvaEntities.SubItem): Rope;
  VAR r: Rope;
BEGIN
  r := OvaCommon.NameDetail(s.name, s.hasDetail, s.detail);
  r := Ropes.Cat(r, OvaCommon.FormatModifiersBracket(s.perks, s.flaws));
  IF s.hasNote THEN
    OvaText.Add(r, " ("); r := Ropes.AppendChar(Ropes.Cat(r, s.note), ")")
  END;
  IF (s IS OvaEntities.Ability) & (s(OvaEntities.Ability).subEntity # NIL) THEN
    OvaText.Add(r, " — see below")
  END;
  RETURN GroffEscape(r)
END ItemCellText;

PROCEDURE SpellDetailText(s: OvaEntities.Spell): Rope;
  VAR r: Rope;
BEGIN
  r := Ropes.AppendChar(s.ability, " "); r := Ropes.Cat(r, OvaCommon.SignedImg(s.level));
  OvaText.Add(r, "; "); r := Ropes.Cat(r, s.endurance); OvaText.Add(r, " Endurance");
  RETURN GroffEscape(r)
END SpellDetailText;

(* Row counts, for the ".ne" before each top-level table. *)

PROCEDURE AbilityRowCount(a: OvaEntities.Ability): INTEGER;
  VAR n: INTEGER;
BEGIN
  n := 1;
  IF a.subAbilities.n > 0 THEN INC(n, a.subAbilities.n + 2) END;
  IF a.subWeaknesses.n > 0 THEN INC(n, a.subWeaknesses.n + 2) END;
  IF a.spells.n > 0 THEN INC(n, a.spells.n + 2) END;
  RETURN n
END AbilityRowCount;

PROCEDURE AbilitiesTableRows(abilities: OvaEntities.List): INTEGER;
  VAR n, i: INTEGER;
BEGIN
  n := 2;  (* header and caption *)
  FOR i := 0 TO abilities.n - 1 DO INC(n, AbilityRowCount(abilities.items[i](OvaEntities.Ability))) END;
  RETURN n
END AbilitiesTableRows;

(* Rows of a weaknesses or sub-items table. *)
PROCEDURE ItemsTableRows(items: OvaEntities.List): INTEGER;
BEGIN
  IF items.n = 0 THEN RETURN 0 END;
  RETURN items.n + 2
END ItemsTableRows;

PROCEDURE CombatTableRows(c: OvaEntities.Combat): INTEGER;
  VAR n, i: INTEGER; a: OvaEntities.Attack;
BEGIN
  IF ~c.hasCombat THEN RETURN 0 END;
  n := 2;  (* caption and column headers *)
  FOR i := 0 TO c.attacks.n - 1 DO
    a := c.attacks.items[i](OvaEntities.Attack);
    INC(n);
    IF StripParens(OvaCommon.FormatAttackClause(a)) # NIL THEN INC(n) END;
    IF a.hasDescription THEN INC(n) END
  END;
  RETURN n + 2  (* Defense/Health/Endurance/TV headers and values *)
END CombatTableRows;

PROCEDURE OtherStatisticsRows(e: OvaEntities.Entity): INTEGER;
  VAR n, i: INTEGER;
BEGIN
  n := 1;  (* caption *)
  FOR i := 0 TO OvaEntities.NFluff - 1 DO
    IF e.hasFluffField[i] THEN INC(n) END
  END;
  RETURN n
END OtherStatisticsRows;

PROCEDURE EmitNe(rows: INTEGER);
BEGIN
  OvaOut.String(RawPrefix); OvaOut.String(".ne "); Line(OvaCommon.TrimImg(2 * rows + 4))
END EmitNe;

(* A table cell: ".TD" with its keyword arguments, if any, and the text
   on the next line, never on the request line, where hdtbl would read
   a word of it as a keyword. *)
PROCEDURE PutCell(args: ARRAY OF CHAR; text: Rope);
BEGIN
  OvaOut.String(RawPrefix); OvaOut.String(".TD");
  IF args # "" THEN OvaOut.Char(" "); OvaOut.String(args) END;
  OvaOut.Ln;
  RawRope(NIL, text)
END PutCell;

(* A caption, quoted on the request line: on a line of its own it
   doesn't survive pandoc. *)
PROCEDURE PutCaption(text: Rope);
BEGIN
  OvaOut.String(RawPrefix); OvaOut.String('.CPTN val=b "'); OvaOut.Rope(text); OvaOut.Char('"'); OvaOut.Ln
END PutCaption;

(* A cell holding an item's level, right-aligned. *)
PROCEDURE LevelCell(level: INTEGER);
BEGIN
  OvaOut.String(RawPrefix); OvaOut.String(".TD hal=r "); Line(OvaCommon.SignedImg(level))
END LevelCell;

(* compact: a Transformation's items, nested in its ability's cell;
   else a sub-entity's own items, at full weight. *)
PROCEDURE PrintSubItemTableGroff(items: OvaEntities.List; caption: Rope; compact: BOOLEAN);
  VAR i: INTEGER; s: OvaEntities.SubItem;
BEGIN
  IF items.n = 0 THEN RETURN END;
  IF compact THEN Raw(NIL, ".TBL cols=2 border=.5p bc=black csp=1p cpd=1p width='15% 85%'")
  ELSE Raw(NIL, ".TBL cols=2 border=.5p bc=black csp=2p cpd=2p width='15% 85%'")
  END;
  PutCaption(GroffEscape(caption));
  Raw(NIL, ".TR");
  Raw(NIL, ".TH Level");
  Raw(NIL, ".TH Name");
  FOR i := 0 TO items.n - 1 DO
    s := items.items[i](OvaEntities.SubItem);
    Raw(NIL, ".TR");
    LevelCell(s.level);
    PutCell("", ItemCellText(s))
  END;
  Raw(NIL, ".ETB")
END PrintSubItemTableGroff;

PROCEDURE PrintSpellsTableGroff(spells: OvaEntities.List; caption: Rope);
  VAR i: INTEGER; s: OvaEntities.Spell;
BEGIN
  IF spells.n = 0 THEN RETURN END;
  Raw(NIL, ".TBL cols=2 border=.5p bc=black csp=1p cpd=1p width='30% 70%'");
  PutCaption(GroffEscape(caption));
  Raw(NIL, ".TR");
  Raw(NIL, ".TH Name");
  Raw(NIL, ".TH Detail");
  FOR i := 0 TO spells.n - 1 DO
    s := spells.items[i](OvaEntities.Spell);
    Raw(NIL, ".TR");
    PutCell("", GroffEscape(s.name));
    PutCell("", SpellDetailText(s))
  END;
  Raw(NIL, ".ETB")
END PrintSpellsTableGroff;

PROCEDURE PrintAbilityRowGroff(a: OvaEntities.Ability);
BEGIN
  Raw(NIL, ".TR");
  LevelCell(a.level);
  PutCell("", ItemCellText(a));
  IF (a.subAbilities.n > 0) OR (a.subWeaknesses.n > 0) OR (a.spells.n > 0) THEN
    PrintSubItemTableGroff(a.subAbilities, Ropes.Cat(a.name, Str(" — Grants (Abilities)")), TRUE);
    PrintSubItemTableGroff(a.subWeaknesses, Ropes.Cat(a.name, Str(" — Grants (Weaknesses)")), TRUE);
    PrintSpellsTableGroff(a.spells, Ropes.Cat(a.name, Str(" — Spells")))
  END
END PrintAbilityRowGroff;

PROCEDURE PrintAbilitiesTableGroff(abilities: OvaEntities.List);
  VAR i: INTEGER;
BEGIN
  IF abilities.n = 0 THEN RETURN END;
  Raw(NIL, ".TBL cols=2 border=.5p bc=black csp=2p cpd=2p width='15% 85%'");
  Raw(NIL, ".CPTN val=b Abilities");
  Raw(NIL, ".TR");
  Raw(NIL, ".TH Level");
  Raw(NIL, ".TH Name");
  FOR i := 0 TO abilities.n - 1 DO PrintAbilityRowGroff(abilities.items[i](OvaEntities.Ability)) END;
  Raw(NIL, ".ETB")
END PrintAbilitiesTableGroff;

PROCEDURE PrintWeaknessesTableGroff(weaknesses: OvaEntities.List);
  VAR i: INTEGER; w: OvaEntities.Weakness;
BEGIN
  IF weaknesses.n = 0 THEN RETURN END;
  Raw(NIL, ".TBL cols=2 border=.5p bc=black csp=2p cpd=2p width='15% 85%'");
  Raw(NIL, ".CPTN val=b Weaknesses");
  Raw(NIL, ".TR");
  Raw(NIL, ".TH Level");
  Raw(NIL, ".TH Name");
  FOR i := 0 TO weaknesses.n - 1 DO
    w := weaknesses.items[i](OvaEntities.Weakness);
    Raw(NIL, ".TR");
    LevelCell(w.level);
    PutCell("", GroffEscape(OvaCommon.NameDetail(w.name, w.hasDetail, w.detail)))
  END;
  Raw(NIL, ".ETB")
END PrintWeaknessesTableGroff;

(* The larger of a and b. *)
PROCEDURE Max(a, b: INTEGER): INTEGER;
BEGIN
  IF a > b THEN RETURN a END;
  RETURN b
END Max;

(* Abilities and weaknesses side by side, in the two cells of a
   borderless table; just the one there is, if only one is. *)
PROCEDURE PrintSideBySideGroff(abilities, weaknesses: OvaEntities.List);
BEGIN
  IF (abilities.n = 0) & (weaknesses.n = 0) THEN RETURN END;
  IF (abilities.n > 0) & (weaknesses.n > 0) THEN
    EmitNe(Max(AbilitiesTableRows(abilities), ItemsTableRows(weaknesses)));
    Raw(NIL, ".TBL cols=2 border=0 csp=4p cpd=0");
    Raw(NIL, ".TR");
    Raw(NIL, ".TD");
    PrintAbilitiesTableGroff(abilities);
    Raw(NIL, ".TD");
    PrintWeaknessesTableGroff(weaknesses);
    Raw(NIL, ".ETB")
  ELSIF abilities.n > 0 THEN
    EmitNe(AbilitiesTableRows(abilities));
    PrintAbilitiesTableGroff(abilities)
  ELSE
    EmitNe(ItemsTableRows(weaknesses));
    PrintWeaknessesTableGroff(weaknesses)
  END
END PrintSideBySideGroff;

(* A centered cell: ".TD hal=c " and the text, all on one line, for
   text that is never the user's. *)
PROCEDURE CenterCell(r: Rope);
BEGIN
  OvaOut.String(RawPrefix); OvaOut.String(".TD hal=c "); Line(r)
END CenterCell;

(* "\fBr\fP": r in bold. *)
PROCEDURE Fb(r: Rope): Rope;
BEGIN RETURN Ropes.Cat(Ropes.Cat(Str("\fB"), r), Str("\fP"))
END Fb;

(* The "Attacks & Combat Stats (LABEL)" box. *)
PROCEDURE PrintCombatTableGroff(c: OvaEntities.Combat; label: Rope);
  VAR i: INTEGER; a: OvaEntities.Attack; clause, tv, r: Rope;
BEGIN
  IF ~c.hasCombat THEN RETURN END;
  EmitNe(CombatTableRows(c));
  Raw(NIL, ".TBL cols=4 border=.5p bc=black csp=2p cpd=2p width='25% 25% 25% 25%'");
  r := Str("Attacks & Combat Stats ("); r := Ropes.Cat(r, GroffEscape(label)); r := Ropes.AppendChar(r, ")");
  PutCaption(r);
  Raw(NIL, ".TR");
  Raw(NIL, ".TH Name");
  Raw(NIL, ".TH Roll");
  Raw(NIL, ".TH DX");
  Raw(NIL, ".TH End");
  FOR i := 0 TO c.attacks.n - 1 DO
    a := c.attacks.items[i](OvaEntities.Attack);
    Raw(NIL, ".TR");
    PutCell("", Fb(GroffEscape(a.name)));
    CenterCell(OvaCommon.NumberImg(a.roll));
    PutCell("hal=c", GroffEscape(a.dx));
    CenterCell(OvaCommon.TrimImg(a.endurance));
    clause := StripParens(OvaCommon.FormatAttackClause(a));
    IF clause # NIL THEN
      Raw(NIL, ".TR");
      PutCell("colspan=4", Ropes.AppendChar(Ropes.Cat(Str("["), GroffEscape(clause)), "]"))
    END;
    IF a.hasDescription THEN
      Raw(NIL, ".TR");
      PutCell("colspan=4", Ropes.Cat(Ropes.Cat(Str("\fI"), GroffEscape(a.description)), Str("\fP")))
    END
  END;
  Raw(NIL, ".TR");
  Raw(NIL, ".TH Defense");
  Raw(NIL, ".TH Health");
  Raw(NIL, ".TH Endurance");
  Raw(NIL, ".TH TV");
  Raw(NIL, ".TR");
  PutCell("hal=c", Fb(GroffEscape(c.defense)));
  CenterCell(Fb(OvaCommon.TrimImg(c.health)));
  CenterCell(Fb(OvaCommon.TrimImg(c.endurance)));
  IF c.hasThreatValue THEN tv := OvaCommon.TrimImg(c.threatValue) ELSE tv := Str("—") END;
  CenterCell(Fb(tv));
  Raw(NIL, ".ETB")
END PrintCombatTableGroff;

(* The label of fluff field i in the "Other Statistics" box, where
   "Favorite Food" is "Fave Food". *)
PROCEDURE FluffLabel(i: INTEGER; VAR s: ARRAY OF CHAR);
BEGIN
  CASE i OF
    OvaEntities.Concept: COPY("Concept", s)
  | OvaEntities.Birthday: COPY("Birthday", s)
  | OvaEntities.Age: COPY("Age", s)
  | OvaEntities.Gender: COPY("Gender", s)
  | OvaEntities.Height: COPY("Height", s)
  | OvaEntities.Weight: COPY("Weight", s)
  | OvaEntities.Hair: COPY("Hair", s)
  | OvaEntities.Eyes: COPY("Eyes", s)
  | OvaEntities.Association: COPY("Association", s)
  | OvaEntities.Hobbies: COPY("Hobbies", s)
  | OvaEntities.FavoriteFood: COPY("Fave Food", s)
  | OvaEntities.Allies: COPY("Allies", s)
  | OvaEntities.Enemies: COPY("Enemies", s)
  | OvaEntities.LoveInterests: COPY("Love Interests", s)
  END
END FluffLabel;

(* The "Other Statistics" box, from fluff:, if it has any field. *)
PROCEDURE PrintOtherStatisticsGroff(e: OvaEntities.Entity);
  VAR i: INTEGER; label: ARRAY 16 OF CHAR;
BEGIN
  IF OtherStatisticsRows(e) <= 1 THEN RETURN END;
  EmitNe(OtherStatisticsRows(e));
  Raw(NIL, ".TBL cols=2 border=.5p bc=black csp=2p cpd=2p width='25% 75%'");
  PutCaption(Str("Other Statistics"));
  FOR i := 0 TO OvaEntities.NFluff - 1 DO
    IF e.hasFluffField[i] THEN
      FluffLabel(i, label);
      Raw(NIL, ".TR");
      OvaOut.String(RawPrefix); OvaOut.String(".TD \fB"); OvaOut.String(label); OvaOut.String("\fP"); OvaOut.Ln;
      PutCell("", GroffEscape(e.fluff[i]))
    END
  END;
  Raw(NIL, ".ETB")
END PrintOtherStatisticsGroff;

PROCEDURE PrintSideBySideSubGroff(abilities, weaknesses: OvaEntities.List; aCaption, wCaption: Rope);
BEGIN
  IF (abilities.n = 0) & (weaknesses.n = 0) THEN RETURN END;
  IF (abilities.n > 0) & (weaknesses.n > 0) THEN
    EmitNe(Max(ItemsTableRows(abilities), ItemsTableRows(weaknesses)));
    Raw(NIL, ".TBL cols=2 border=0 csp=4p cpd=0");
    Raw(NIL, ".TR");
    Raw(NIL, ".TD");
    PrintSubItemTableGroff(abilities, aCaption, FALSE);
    Raw(NIL, ".TD");
    PrintSubItemTableGroff(weaknesses, wCaption, FALSE);
    Raw(NIL, ".ETB")
  ELSIF abilities.n > 0 THEN
    EmitNe(ItemsTableRows(abilities));
    PrintSubItemTableGroff(abilities, aCaption, FALSE)
  ELSE
    EmitNe(ItemsTableRows(weaknesses));
    PrintSubItemTableGroff(weaknesses, wCaption, FALSE)
  END
END PrintSideBySideSubGroff;

(* A Companion's or Vehicle's own section, after the main character's:
   "Label: Name" goes in each table's caption, not in a heading, which
   hd's floating tables would leave behind. *)
PROCEDURE PrintSubEntitySectionGroff(se: OvaEntities.SubEntity);
  VAR who: Rope;
BEGIN
  who := OvaCommon.SubEntityTitle(se);
  PrintSideBySideSubGroff(se.abilities, se.weaknesses,
    Ropes.Cat(who, Str(" — Abilities")), Ropes.Cat(who, Str(" — Weaknesses")));
  PrintCombatTableGroff(se.combat, OvaText.ToUpper(se.name))
END PrintSubEntitySectionGroff;

PROCEDURE EnsureRawOpen;
BEGIN
  IF ~inRaw THEN
    OvaOut.String(".. raw:: ms"); OvaOut.Ln;
    OvaOut.Ln;
    Raw(NIL, ".mso hdtbl.tmac");
    inRaw := TRUE
  END
END EnsureRawOpen;

PROCEDURE EnsureRawClosed;
BEGIN
  IF inRaw THEN OvaOut.Ln; inRaw := FALSE END
END EnsureRawClosed;

(* The tables, then each sub-entity's section.  A fragment-style one is
   plain reST (OvaCommon's), so the raw block is closed for it and
   opened again if more tables follow. *)
PROCEDURE PrintGroffTables(e: OvaEntities.Entity);
  VAR i: INTEGER; se: OvaEntities.SubEntity;
BEGIN
  IF (e.abilities.n = 0) & (e.weaknesses.n = 0) & ~e.combat.hasCombat & ~e.hasFluff THEN RETURN END;
  inRaw := FALSE;
  EnsureRawOpen;
  PrintSideBySideGroff(e.abilities, e.weaknesses);
  PrintCombatTableGroff(e.combat, OvaText.ToUpper(e.name));
  IF e.hasFluff THEN PrintOtherStatisticsGroff(e) END;
  FOR i := 0 TO e.abilities.n - 1 DO
    se := e.abilities.items[i](OvaEntities.Ability).subEntity;
    IF se # NIL THEN
      IF se.isFragment THEN
        EnsureRawClosed;
        OvaCommon.PrintSubEntityFragmentStyle(se)
      ELSE
        EnsureRawOpen;
        PrintSubEntitySectionGroff(se)
      END
    END
  END;
  EnsureRawClosed
END PrintGroffTables;

(* ---- ProcessEntity ---- *)

(* Writes e in the format OvaConfig.format says, terse, HTML-in-reST or
   groff-in-reST.  entityNo is 1 for a file's first entity: see
   OvaCommon.PrintHeaderAndProse.  An NPC Fragment is the same in every
   format: OvaCommon's. *)
PROCEDURE ProcessEntity*(e: OvaEntities.Entity; entityNo: INTEGER);
BEGIN
  IF e.isFragment THEN OvaCommon.ProcessEntity(e, entityNo); RETURN END;
  IF OvaConfig.format = OvaConfig.HtmlInRst THEN
    OvaCommon.PrintHeaderAndProse(e, entityNo);
    PrintHtmlTables(e);
    OvaCommon.PrintTail(e)
  ELSIF OvaConfig.format = OvaConfig.GroffInRst THEN
    OvaCommon.PrintHeaderAndProse(e, entityNo);
    PrintGroffTables(e);
    OvaCommon.PrintNotes(e);
    OvaCommon.PrintOptionsIfShown(e)
  ELSE
    OvaCommon.ProcessEntity(e, entityNo)
  END
END ProcessEntity;

BEGIN
  Ropes.MakeCharSet("&<>", html);
  inRaw := FALSE
END OvaRst.
