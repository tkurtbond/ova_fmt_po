MODULE OvaSheetMap; (* An entity mapped onto the official character sheet's slots *)

(* The Ada Ova_Fmt.Sheet_Map: what goes on which copy of page 1 of the
   official OVA character sheet, which has 17 Ability lines, 17
   Weakness lines and 4 attack boxes (PLAN.md, "The official character
   sheet as PDF").  It measures nothing; OvaForm (-X) does.

   The rows follow the rulebook's Sample Characters:
   - an Ability's Transformation rows (its granted Abilities, then its
     granted Weaknesses) and its spells go under it, in the Abilities
     column;
   - a parent and its rows are one block, kept together: a block that
     doesn't fit in what is left of the column moves whole to the next
     copy, and only one taller than the column is split, the next copy
     repeating the parent as "Name (continued)";
   - a Companion or Vehicle is one row in its parent's column, and its
     own boxes go on copies of page 1 of their own, titled "Arasuni
     (Karis's Companion)" -- a Fragment one too.
   What isn't a slot (the prose, an item's note, an attack's
   description) is left to the format.  -X clips a row at its line, so
   a row is a line; -S wraps a row onto the ruled lines below it, so it
   gives Fill a procedure counting a row's lines.

   The Ada vectors are a Seq here, of Things that a type guard takes
   out.  Rows, attacks and pages are made once and never changed, so
   the copies of page 1 can share them. *)

IMPORT OvaCommon, OvaEntities, OvaText, Ropes;

CONST
  AbilitySlots* = 17;
  WeaknessSlots* = 17;
  AttackSlots* = 4;

  (* -C/--one-column's page 1, drawn by -R: one column of lines, the
     Abilities, a line for a faint rule, then the Weaknesses, and an
     Attacks & Combat Stats box beside it with more attack slots
     (Acacia's block in the rulebook; PLAN.md, "One column"). *)
  OneColumnSlots* = 35;
  OneColumnAttackSlots* = 5;

  (* A row's kind (the Ada Row_Kind).  Item: an Ability or Weakness of
     the sheet's owner, its level in the Dice column.  Sub: one granted
     by the Item above it (a Transformation's), its level in the name
     column.  Spell: a spell of the Item above it, with no level. *)
  Item* = 0; Sub* = 1; Spell* = 2;

TYPE
  Rope = Ropes.Rope;

  Thing* = POINTER TO ThingDesc;
  ThingDesc* = RECORD END;
  Things = POINTER TO ARRAY OF Thing;

  (* A growable list: items[0 .. n-1].  Clear one before its first
     use. *)
  Seq* = RECORD
    items-: Things;
    n-: INTEGER
  END;

  (* level is "+2", or NIL for a Spell or a repeated parent.  text is
     "Barrier [Perks: ...; 5 Endurance]"; plain and mods are its two
     parts, for -S's faked small caps: plain without the bracket
     ("Barrier"), mods what is inside it ("Perks: ...; 5 Endurance"),
     NIL if there is none.  note is the item's note: as "Barrier: note
     text", for the format to place off the row, since the rulebook
     doesn't print it there. *)
  Row* = POINTER TO RowDesc;
  RowDesc* = RECORD (ThingDesc)
    kind-: INTEGER;
    level-, text-, plain-, mods-: Rope;
    hasNote-: BOOLEAN;
    note-: Rope
  END;

  (* clause is "Affinity: Love; Perks: Ranged", or NIL if the attack
     has none: never empty when it has one, so it needs no flag. *)
  AttackSlot* = POINTER TO AttackSlotDesc;
  AttackSlotDesc* = RECORD (ThingDesc)
    name-, clause-, roll-, dx-, endurance-: Rope;
    hasDescription-: BOOLEAN;
    description-: Rope
  END;

  (* One copy of page 1.  owner names whose boxes these are ("Fukiko",
     "Arasuni"), title is the Character Name field.  The Combat Stats
     boxes are on the owner's first copy only.  threatValue and npcType
     are NIL when there is none, as the Ada "" is: neither is ever
     empty when there is one. *)
  Page* = POINTER TO PageDesc;
  PageDesc* = RECORD (ThingDesc)
    owner-, title-: Rope;
    continued-: BOOLEAN;                  (* not the owner's first copy *)
    hasPlayer-: BOOLEAN; player-: Rope;
    abilities-: Seq;                      (* of Row, at most AbilitySlots *)
    weaknesses-: Seq;                     (* of Row, at most WeaknessSlots *)
    attacks-: Seq;                        (* of AttackSlot, at most AttackSlots *)
    hasStats-: BOOLEAN;
    defense-, health-, endurance-, threatValue-: Rope;
    npcType-: Rope;
    hasCombatNotes-: BOOLEAN; combatNotes-: Rope
  END;

  (* A parent row and the rows under it, kept together, with the parent
     as it is repeated if the block has to be split. *)
  Block = POINTER TO BlockDesc;
  BlockDesc = RECORD (ThingDesc)
    rows: Seq;                            (* of Row *)
    continued: Row
  END;

  (* How many ruled lines a row takes, at least 1. *)
  RowLines* = PROCEDURE (r: Row): INTEGER;

  (* One column's rows on one copy of page 1. *)
  Column = POINTER TO ColumnDesc;
  ColumnDesc = RECORD (ThingDesc)
    rows: Seq                             (* of Row *)
  END;

(* ---- Seq ---- *)

PROCEDURE Clear*(VAR s: Seq);
BEGIN s.items := NIL; s.n := 0
END Clear;

PROCEDURE Append*(VAR s: Seq; t: Thing);
  VAR a: Things; i: INTEGER;
BEGIN
  IF s.items = NIL THEN NEW(s.items, 8); s.n := 0
  ELSIF s.n = LEN(s.items^) THEN
    NEW(a, 2 * s.n);
    FOR i := 0 TO s.n - 1 DO a[i] := s.items[i] END;
    s.items := a
  END;
  s.items[s.n] := t; INC(s.n)
END Append;

(* ---- Rows ---- *)

(* A row of kind with level, its text plain and bracket (" [...]" from
   FormatModifiersBracket, or NIL). *)
PROCEDURE NewRow(kind: INTEGER; level, plain, bracket: Rope; hasNote: BOOLEAN; note: Rope): Row;
  VAR r: Row;
BEGIN
  NEW(r); r.kind := kind; r.level := level;
  r.text := Ropes.Cat(plain, bracket); r.plain := plain; r.mods := NIL;
  IF Ropes.Length(bracket) > 0 THEN r.mods := Ropes.Substring(bracket, 2, Ropes.Length(bracket) - 3) END;
  r.hasNote := hasNote; r.note := note;
  RETURN r
END NewRow;

(* "Name (detail): note", or NIL without a note. *)
PROCEDURE NoteOf(s: OvaEntities.SubItem): Rope;
  VAR r: Rope;
BEGIN
  IF ~s.hasNote THEN RETURN NIL END;
  r := OvaCommon.NameDetail(s.name, s.hasDetail, s.detail); OvaText.Add(r, ": ");
  RETURN Ropes.Cat(r, s.note)
END NoteOf;

(* "Name (detail)", then (half TV) with -O, then the bracket: an
   Ability's or a SubItem's row. *)
PROCEDURE SubItemRow(s: OvaEntities.SubItem; kind: INTEGER): Row;
  VAR plain: Rope;
BEGIN
  plain := Ropes.Cat(OvaCommon.NameDetail(s.name, s.hasDetail, s.detail), OvaCommon.HalfTVText(s));
  RETURN NewRow(kind, OvaCommon.SignedImg(s.level), plain, OvaCommon.FormatModifiersBracket(s, TRUE),
    s.hasNote, NoteOf(s))
END SubItemRow;

PROCEDURE Single(r: Row): Block;
  VAR b: Block;
BEGIN
  NEW(b); Clear(b.rows); Append(b.rows, r); b.continued := r;
  RETURN b
END Single;

(* The Ability's own row, then its Transformation's granted Abilities
   and Weaknesses, then its spells. *)
PROCEDURE AbilityBlock(a: OvaEntities.Ability): Block;
  VAR b: Block; name, text: Rope; i: INTEGER;
BEGIN
  NEW(b); Clear(b.rows);
  name := OvaCommon.NameDetail(a.name, a.hasDetail, a.detail);
  Append(b.rows, SubItemRow(a, Item));
  FOR i := 0 TO a.subAbilities.n - 1 DO
    Append(b.rows, SubItemRow(a.subAbilities.items[i](OvaEntities.SubItem), Sub))
  END;
  FOR i := 0 TO a.subWeaknesses.n - 1 DO
    Append(b.rows, SubItemRow(a.subWeaknesses.items[i](OvaEntities.SubItem), Sub))
  END;
  FOR i := 0 TO a.spells.n - 1 DO
    Append(b.rows, NewRow(Spell, NIL,
      OvaCommon.FormatShortSpellLine(a.spells.items[i](OvaEntities.Spell), TRUE), NIL, FALSE, NIL))
  END;
  text := name; OvaText.Add(text, " (continued)");
  b.continued := NewRow(Item, NIL, text, NIL, FALSE, NIL);
  RETURN b
END AbilityBlock;

(* ---- Place ---- *)

(* The lines r takes: lines(r), or 1 if lines is NIL. *)
PROCEDURE Height(r: Thing; lines: RowLines): INTEGER;
BEGIN
  IF lines = NIL THEN RETURN 1 END;
  RETURN lines(r(Row))
END Height;

PROCEDURE RowsHeight(rows: Seq; lines: RowLines): INTEGER;
  VAR h, i: INTEGER;
BEGIN
  h := 0;
  FOR i := 0 TO rows.n - 1 DO h := h + Height(rows.items[i], lines) END;
  RETURN h
END RowsHeight;

(* Adds r to cur, whose rows take used lines. *)
PROCEDURE Add(cur: Column; VAR used: INTEGER; r: Thing; lines: RowLines);
BEGIN Append(cur.rows, r); used := used + Height(r, lines)
END Add;

(* Ends the current column, cur, appending it to columns. *)
PROCEDURE NextColumn(VAR columns: Seq; VAR cur: Column; VAR used: INTEGER);
BEGIN Append(columns, cur); NEW(cur); Clear(cur.rows); used := 0
END NextColumn;

(* Blocks into columns of slots lines, one column per copy of page 1,
   keeping each block together when it can.  The first column has its
   first firstUsed lines taken already (-C's Weaknesses, under the
   Abilities); if its first block doesn't fit what is left, that column
   is empty.  left is what is left of the column, never negative: a row
   taller than the column overfills one. *)
PROCEDURE Place(blocks: Seq; slots: INTEGER; lines: RowLines; firstUsed: INTEGER; VAR columns: Seq);
  VAR cur: Column; b: Block; i, j, used, left, h, first: INTEGER;
BEGIN
  Clear(columns); NEW(cur); Clear(cur.rows); used := firstUsed;
  FOR i := 0 TO blocks.n - 1 DO
    b := blocks.items[i](Block);
    h := RowsHeight(b.rows, lines);
    IF used >= slots THEN left := 0 ELSE left := slots - used END;
    IF h <= left THEN
      FOR j := 0 TO b.rows.n - 1 DO Add(cur, used, b.rows.items[j], lines) END
    ELSIF h <= slots THEN
      NextColumn(columns, cur, used);
      FOR j := 0 TO b.rows.n - 1 DO Add(cur, used, b.rows.items[j], lines) END
    ELSE
      (* Taller than the column: split, starting here unless there isn't
         room for the parent and one row under it. *)
      first := Height(b.rows.items[0], lines);
      IF b.rows.n > 1 THEN first := first + Height(b.rows.items[1], lines) END;
      IF (left < first) & (used > 0) THEN NextColumn(columns, cur, used) END;
      FOR j := 0 TO b.rows.n - 1 DO
        IF used >= slots THEN left := 0 ELSE left := slots - used END;
        IF (Height(b.rows.items[j], lines) > left) & (cur.rows.n > 0) THEN
          NextColumn(columns, cur, used); Add(cur, used, b.continued, lines)
        END;
        Add(cur, used, b.rows.items[j], lines)
      END
    END
  END;
  IF cur.rows.n > 0 THEN NextColumn(columns, cur, used) END
END Place;

(* ---- Copies of page 1 ---- *)

PROCEDURE AttackOf(a: OvaEntities.Attack): AttackSlot;
  VAR s: AttackSlot; clause: Rope;
BEGIN
  NEW(s);
  s.name := a.name;
  (* Without the parentheses: the box is the attack's own. *)
  clause := OvaCommon.FormatAttackClause(a);
  s.clause := Ropes.Substring(clause, 1, Ropes.Length(clause) - 2);
  s.roll := OvaCommon.Marked(OvaCommon.NumberImg(a.roll), OvaEntities.OvRoll, a.overrides, TRUE);
  s.dx := OvaCommon.Marked(a.dx, OvaEntities.OvDx, a.overrides, TRUE);
  s.endurance := OvaCommon.Marked(OvaCommon.TrimImg(a.endurance), OvaEntities.OvEndurance, a.overrides, TRUE);
  s.hasDescription := a.hasDescription; s.description := a.description;
  RETURN s
END AttackOf;

PROCEDURE Max(a, b: INTEGER): INTEGER;
BEGIN
  IF a > b THEN RETURN a END;
  RETURN b
END Max;

PROCEDURE Min(a, b: INTEGER): INTEGER;
BEGIN
  IF a < b THEN RETURN a END;
  RETURN b
END Min;

(* The owner's copies, appended to pages: the first titled title, the
   rest title " (continued)".  npcType is NIL for none.  With
   oneColumn, the Weaknesses go on from the last copy with Abilities,
   a line below them: wFirst is how many copies come before their
   first. *)
PROCEDURE AddCopies(VAR pages: Seq; owner, title: Rope; hasPlayer: BOOLEAN; player: Rope;
                    abilities, weaknesses: Seq; combat: OvaEntities.Combat; npcType: Rope;
                    lines: RowLines; oneColumn: BOOLEAN);
  VAR aColumns, wColumns: Seq; p: Page; attacks, copies, n, i, wFirst, slots: INTEGER;
BEGIN
  wFirst := 0;
  IF oneColumn THEN
    Place(abilities, OneColumnSlots, lines, 0, aColumns);
    IF aColumns.n = 0 THEN
      Place(weaknesses, OneColumnSlots, lines, 0, wColumns)
    ELSE
      wFirst := aColumns.n - 1;
      Place(weaknesses, OneColumnSlots, lines,
        RowsHeight(aColumns.items[aColumns.n - 1](Column).rows, lines) + 1, wColumns)
    END;
    slots := OneColumnAttackSlots
  ELSE
    Place(abilities, AbilitySlots, lines, 0, aColumns);
    Place(weaknesses, WeaknessSlots, lines, 0, wColumns);
    slots := AttackSlots
  END;
  IF combat.hasCombat THEN attacks := combat.attacks.n ELSE attacks := 0 END;
  copies := Max(1, Max(Max(aColumns.n, wFirst + wColumns.n), (attacks + slots - 1) DIV slots));
  FOR n := 1 TO copies DO
    NEW(p);
    p.owner := owner;
    p.continued := n > 1;
    IF n = 1 THEN p.title := title
    ELSE p.title := title; OvaText.Add(p.title, " (continued)")
    END;
    p.hasPlayer := FALSE; p.player := NIL;
    IF n = 1 THEN p.hasPlayer := hasPlayer; p.player := player END;
    Clear(p.abilities); Clear(p.weaknesses); Clear(p.attacks);
    IF n <= aColumns.n THEN p.abilities := aColumns.items[n - 1](Column).rows END;
    IF (n > wFirst) & (n - wFirst <= wColumns.n) THEN
      p.weaknesses := wColumns.items[n - wFirst - 1](Column).rows
    END;
    FOR i := (n - 1) * slots TO Min(n * slots, attacks) - 1 DO
      Append(p.attacks, AttackOf(combat.attacks.items[i](OvaEntities.Attack)))
    END;
    p.hasStats := FALSE; p.hasCombatNotes := FALSE;
    p.defense := NIL; p.health := NIL; p.endurance := NIL; p.threatValue := NIL; p.combatNotes := NIL;
    IF (n = 1) & combat.hasCombat THEN
      p.hasStats := TRUE;
      p.defense := OvaCommon.DefenseText(combat, TRUE);
      p.health := OvaCommon.Marked(OvaCommon.TrimImg(combat.health), OvaEntities.OvHealth, combat.overrides, TRUE);
      p.endurance := OvaCommon.Marked(OvaCommon.TrimImg(combat.endurance), OvaEntities.OvEndurance,
        combat.overrides, TRUE);
      IF combat.hasThreatValue THEN
        p.threatValue := OvaCommon.Marked(OvaCommon.TrimImg(combat.threatValue), OvaEntities.OvThreatValue,
          combat.overrides, TRUE)
      END;
      p.hasCombatNotes := combat.hasNotes; p.combatNotes := combat.notes
    END;
    p.npcType := NIL;
    IF n = 1 THEN p.npcType := npcType END;
    Append(pages, p)
  END
END AddCopies;

(* pages: e's copies of page 1, of Page: its own first (at least one, titled
   with its name; any more "Name (continued)"), then each Companion's
   or Vehicle's, in the order of the Abilities granting them.  The
   numbers are as in raw tables: ASCII "*" for an override.  A column
   holds AbilitySlots lines, each row taking lines(row) of them, or one
   if lines is NIL.  With oneColumn, a copy's Abilities and Weaknesses
   share OneColumnSlots lines: the Weaknesses start on the copy where
   the Abilities end, a line below them (for the rule), and a copy
   holds OneColumnAttackSlots attacks. *)
PROCEDURE Fill*(e: OvaEntities.Entity; lines: RowLines; oneColumn: BOOLEAN; VAR pages: Seq);
  VAR abilities, weaknesses, sAbl, sWk: Seq; a: OvaEntities.Ability; w: OvaEntities.Weakness;
    se: OvaEntities.SubEntity; title: Rope; i, j: INTEGER;
BEGIN
  Clear(pages); Clear(abilities); Clear(weaknesses);
  FOR i := 0 TO e.abilities.n - 1 DO Append(abilities, AbilityBlock(e.abilities.items[i](OvaEntities.Ability))) END;
  FOR i := 0 TO e.weaknesses.n - 1 DO
    w := e.weaknesses.items[i](OvaEntities.Weakness);
    Append(weaknesses, Single(NewRow(Item, OvaCommon.SignedImg(w.level),
      OvaCommon.NameDetail(w.name, w.hasDetail, w.detail), NIL, FALSE, NIL)))
  END;
  AddCopies(pages, e.name, e.name, e.hasPlayer, e.player, abilities, weaknesses, e.combat,
    OvaCommon.NpcTypeText(e), lines, oneColumn);

  FOR i := 0 TO e.abilities.n - 1 DO
    a := e.abilities.items[i](OvaEntities.Ability);
    IF a.subEntity # NIL THEN
      se := a.subEntity;
      Clear(sAbl); Clear(sWk);
      FOR j := 0 TO se.abilities.n - 1 DO Append(sAbl, Single(SubItemRow(se.abilities.items[j](OvaEntities.SubItem), Item))) END;
      FOR j := 0 TO se.weaknesses.n - 1 DO Append(sWk, Single(SubItemRow(se.weaknesses.items[j](OvaEntities.SubItem), Item))) END;
      (* Nothing of its own to show: its parent's row names it. *)
      IF (sAbl.n > 0) OR (sWk.n > 0) OR se.combat.hasCombat THEN
        title := se.name; OvaText.Add(title, " ("); title := Ropes.Cat(title, e.name);
        OvaText.Add(title, "'s "); title := Ropes.Cat(title, se.label); title := Ropes.AppendChar(title, ")");
        AddCopies(pages, se.name, title, FALSE, NIL, sAbl, sWk, se.combat, NIL, lines, oneColumn)
      END
    END
  END
END Fill;

END OvaSheetMap.
