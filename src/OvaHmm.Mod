MODULE OvaHmm; (* The h-m-m outline format: -m/--hmm *)

(* The Ada Ova_Fmt.Format_Hmm: a tab-indented outline, one node per
   line.  The entity's line, its section headers one level in, their
   items one more; a linked section is a sibling of Abilities,
   Weaknesses and Combat, and a Companion's or Vehicle's own sections
   nest one level deeper.  Indentation starts at -L/--hmm-depth for
   every entity.  The item lines are OvaCommon's. *)

IMPORT OvaCommon, OvaConfig, OvaEntities, OvaOut, OvaText, Ropes;

TYPE
  Rope = Ropes.Rope;

PROCEDURE Str(s: ARRAY OF CHAR): Rope;
BEGIN RETURN Ropes.FromString(s)
END Str;

(* A node: depth tabs, then r. *)
PROCEDURE Node(depth: INTEGER; r: Rope);
BEGIN OvaOut.Repeat(09X, depth); OvaCommon.Line(r)
END Node;

(* r on one line: a node is one line, and prose from a literal block
   scalar has line feeds in it. *)
PROCEDURE AllOneLine(r: Rope): Rope;
BEGIN RETURN OvaCommon.AllOneLine(r)
END AllOneLine;

(* "**Label:** items." on one node with -c/--hmm-compact-lists, else a
   header node with a node for each item. *)
PROCEDURE PrintList(label: ARRAY OF CHAR; l: OvaEntities.List; joined: Rope; weak: BOOLEAN;
                    depth: INTEGER);
  VAR i: INTEGER; t: Rope;
BEGIN
  IF l.n = 0 THEN RETURN END;
  IF OvaConfig.hmmCompactLists THEN
    t := OvaCommon.Bold(Ropes.AppendChar(Str(label), ":"));
    t := Ropes.AppendChar(t, " ");
    Node(depth, OvaCommon.EndWithPeriod(Ropes.Cat(t, joined)))
  ELSE
    Node(depth, OvaCommon.SectionHeaderStr(label));
    FOR i := 0 TO l.n - 1 DO
      IF weak THEN Node(depth + 1, OvaCommon.FormatWeaknessLine(l.items[i]))
      ELSE Node(depth + 1, OvaCommon.FormatSubItemLine(l.items[i]))
      END
    END
  END
END PrintList;

(* Abilities or sub-items. *)
PROCEDURE PrintItems(label: ARRAY OF CHAR; l: OvaEntities.List; depth: INTEGER);
BEGIN
  IF l.n > 0 THEN PrintList(label, l, OvaCommon.JoinSubItems(l), FALSE, depth) END
END PrintItems;

PROCEDURE PrintWeaknesses(l: OvaEntities.List; depth: INTEGER);
BEGIN
  IF l.n > 0 THEN PrintList("Weaknesses", l, OvaCommon.JoinWeaknesses(l), TRUE, depth) END
END PrintWeaknesses;

(* A "Combat" node, its summary (led by npcType if that isn't NIL), and
   an "Attacks" node with a node for each attack. *)
PROCEDURE PrintCombat(c: OvaEntities.Combat; depth: INTEGER; npcType: Rope);
  VAR i: INTEGER; r: Rope;
BEGIN
  IF ~c.hasCombat THEN RETURN END;
  Node(depth, OvaCommon.SectionHeaderStr("Combat"));
  Node(depth + 1, OvaCommon.FormatCombatSummaryLine(c, npcType));
  IF c.attacks.n > 0 THEN
    Node(depth + 1, OvaCommon.SectionHeaderStr("Attacks"));
    FOR i := 0 TO c.attacks.n - 1 DO
      Node(depth + 2, OvaCommon.FormatAttackLine(c.attacks.items[i](OvaEntities.Attack)))
    END
  END;
  IF c.hasNotes THEN
    r := Ropes.AppendChar(OvaCommon.BoldStr("Combat Notes:"), " ");
    Node(depth + 1, Ropes.Cat(r, AllOneLine(c.notes)))
  END
END PrintCombat;

(* A Companion or Vehicle with fragment: true: one "Attributes:" node at
   depth, not under a header node, then its combat. *)
PROCEDURE PrintSubEntityFragmentStyle(se: OvaEntities.SubEntity; depth: INTEGER);
  VAR r: Rope;
BEGIN
  IF (se.abilities.n = 0) & (se.weaknesses.n = 0) THEN
    Node(depth, Ropes.AppendChar(OvaCommon.Bold(se.name), "."))
  ELSE
    r := OvaCommon.Bold(se.name); OvaText.Add(r, " -- ");
    r := Ropes.Cat(r, OvaCommon.BoldStr("Attributes:")); r := Ropes.AppendChar(r, " ");
    r := Ropes.Cat(r, OvaCommon.Semi(OvaCommon.JoinFragmentSubItems(se.abilities),
      OvaCommon.JoinFragmentSubItems(se.weaknesses), se.abilities.n > 0, se.weaknesses.n > 0));
    Node(depth, Ropes.AppendChar(r, "."))
  END;
  PrintCombat(se.combat, depth, NIL)
END PrintSubEntityFragmentStyle;

PROCEDURE PrintLinkedSection(a: OvaEntities.Ability; depth: INTEGER);
  VAR se: OvaEntities.SubEntity;
BEGIN
  IF ~OvaCommon.HasLinked(a) THEN RETURN END;
  se := a.subEntity;
  IF (se # NIL) & se.isFragment THEN PrintSubEntityFragmentStyle(se, depth); RETURN END;

  IF se # NIL THEN Node(depth, OvaCommon.SectionHeader(OvaCommon.SubEntityTitle(se)))
  ELSE Node(depth, OvaCommon.SectionHeader(OvaCommon.NameDetail(a.name, a.hasDetail, a.detail)))
  END;
  IF (a.subAbilities.n > 0) OR (a.subWeaknesses.n > 0) THEN
    Node(depth + 1, OvaCommon.EndWithPeriod(OvaCommon.GrantsLine(a)))
  END;
  IF a.spells.n > 0 THEN
    Node(depth + 1, OvaCommon.EndWithPeriod(Ropes.Cat(Str("Spells: "), OvaCommon.JoinSpells(a.spells))))
  END;
  IF se # NIL THEN
    PrintItems("Abilities", se.abilities, depth + 1);
    PrintItems("Weaknesses", se.weaknesses, depth + 1);
    PrintCombat(se.combat, depth + 1, NIL)
  END
END PrintLinkedSection;

PROCEDURE PrintLinkedSections(e: OvaEntities.Entity; depth: INTEGER);
  VAR i: INTEGER;
BEGIN
  FOR i := 0 TO e.abilities.n - 1 DO PrintLinkedSection(e.abilities.items[i](OvaEntities.Ability), depth) END
END PrintLinkedSections;

(* Notes, fluff and creation rules, as OvaCommon.PrintTail writes them
   but as nodes. *)
PROCEDURE PrintTail(e: OvaEntities.Entity; depth: INTEGER);
  VAR i: INTEGER; n: OvaEntities.Note; r: Rope;
BEGIN
  IF e.notes.n > 0 THEN
    Node(depth, OvaCommon.SectionHeaderStr("Notes"));
    FOR i := 0 TO e.notes.n - 1 DO
      n := e.notes.items[i](OvaEntities.Note);
      r := OvaCommon.Bold(n.header); OvaText.Add(r, " -- ");
      Node(depth + 1, Ropes.Cat(r, AllOneLine(n.text)))
    END
  END;
  IF e.hasOtherNotes THEN
    Node(depth, OvaCommon.SectionHeaderStr("Other Notes"));
    Node(depth + 1, AllOneLine(e.otherNotes))
  END;
  IF e.hasFluff THEN
    Node(depth, OvaCommon.SectionHeaderStr("Fluff"));
    Node(depth + 1, OvaCommon.EndWithPeriod(AllOneLine(OvaCommon.FluffLine(e))))
  END;
  IF OvaConfig.showOptions & e.hasOptions & OvaCommon.CreationRules(e, r) THEN
    r := Ropes.Cat(Str(" "), OvaCommon.EndWithPeriod(r));
    Node(depth, Ropes.Cat(OvaCommon.BoldStr("Creation Rules:"), r))
  END
END PrintTail;

(* A "Character Hooks" node after the other prose (or a Fragment's
   Attributes node), as OvaCommon.PrintCharacterHooks. *)
PROCEDURE PrintCharacterHooks(e: OvaEntities.Entity; depth: INTEGER);
BEGIN
  IF e.hasCharacterHooks THEN
    Node(depth, OvaCommon.SectionHeaderStr("Character Hooks"));
    Node(depth + 1, AllOneLine(e.characterHooks))
  END
END PrintCharacterHooks;

(* Writes e as an outline.  entityNo is unused: an outline has no
   underlines to tell entities apart. *)
PROCEDURE ProcessEntity*(e: OvaEntities.Entity; entityNo: INTEGER);
  VAR d1, d2, d3: INTEGER; r: Rope;
BEGIN
  d1 := OvaConfig.hmmDepth + 1;  (* the entity *)
  d2 := OvaConfig.hmmDepth + 2;  (* section headers *)
  d3 := OvaConfig.hmmDepth + 3;  (* sections' prose *)
  IF e.isFragment THEN
    (* Flat, as in every format: one "Attributes:" node whatever -c
       says. *)
    IF e.hasBackground THEN Node(d1, AllOneLine(e.background)) ELSE Node(d1, OvaCommon.Bold(e.name)) END;
    IF (e.abilities.n > 0) OR (e.weaknesses.n > 0) THEN Node(d2, OvaCommon.FragmentAttributes(e)) END;
    PrintCharacterHooks(e, d2);
    PrintCombat(e.combat, d2, NIL);
    PrintLinkedSections(e, d2)
  ELSE
    Node(d1, OvaCommon.Title(e));
    IF e.hasTagline THEN
      r := Ropes.AppendChar(Ropes.Cat(Str('"'), AllOneLine(e.tagline)), '"');
      Node(d2, OvaCommon.Italic(r))
    END;
    IF e.hasSummary THEN Node(d2, OvaCommon.Italic(AllOneLine(e.summary))) END;
    IF e.hasBackground THEN
      Node(d2, OvaCommon.SectionHeaderStr("Background"));
      Node(d3, AllOneLine(e.background))
    END;
    IF e.hasAppearance THEN
      Node(d2, OvaCommon.SectionHeaderStr("Appearance"));
      Node(d3, AllOneLine(e.appearance))
    END;
    IF e.hasPersonality THEN
      Node(d2, OvaCommon.SectionHeaderStr("Personality"));
      Node(d3, AllOneLine(e.personality))
    END;
    PrintCharacterHooks(e, d2);
    PrintItems("Abilities", e.abilities, d2);
    PrintWeaknesses(e.weaknesses, d2);
    PrintCombat(e.combat, d2, OvaCommon.NpcTypeText(e));
    PrintLinkedSections(e, d2)
  END;
  PrintTail(e, d2)
END ProcessEntity;

END OvaHmm.
