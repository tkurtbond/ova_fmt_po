MODULE OvaCommon; (* What the text formats share: terse reST, gemtext, Markdown *)

(* The Ada Ova_Fmt.Format_Common: the content of the plain-text
   formats -- terse reST, gemtext and Markdown, which differ only in
   their emphasis, headings and list bullets -- and the prose and tail
   every format shares, the HTML- and groff-in-reST ones included.  The
   Ada Format_Gemini and Format_Markdown are thin entry points into
   this package's Process_Entity, so here OvaFmt calls ProcessEntity
   directly for those formats.

   The per-item line formatters return ropes, and OvaHmm builds its
   own lines from them; the Print procedures write through OvaOut.  The
   Ada package's comments explain each choice of layout; the comments
   here only summarize. *)

IMPORT OvaConfig, OvaEntities, OvaOut, OvaText, Ropes;

TYPE
  Rope = Ropes.Rope;
  Element = OvaEntities.Element;

  (* Writes one list item as a rope; see Join. *)
  Formatter = PROCEDURE (x: Element): Rope;

(* ---- Primitives ---- *)

PROCEDURE Str(s: ARRAY OF CHAR): Rope;
BEGIN RETURN Ropes.FromString(s)
END Str;

(* Writes r and a line feed: Ada.Text_IO.Put_Line. *)
PROCEDURE Line*(r: Rope);
BEGIN OvaOut.Rope(r); OvaOut.Ln
END Line;

(* Gemtext has no inline emphasis, unless -e asks for it anyway, and
   -p turns it off in h-m-m output; every other format has it. *)
PROCEDURE NoEmphasis(): BOOLEAN;
BEGIN
  RETURN (OvaConfig.format = OvaConfig.Gemtext) & ~OvaConfig.gemtextEmphasis
    OR (OvaConfig.format = OvaConfig.Hmm) & OvaConfig.hmmPlain
END NoEmphasis;

PROCEDURE Bold*(r: Rope): Rope;
  VAR b: Rope;
BEGIN
  IF NoEmphasis() THEN RETURN r END;
  b := Str("**");
  RETURN Ropes.Cat(Ropes.Cat(b, r), b)
END Bold;

PROCEDURE BoldStr*(s: ARRAY OF CHAR): Rope;
BEGIN RETURN Bold(Str(s))
END BoldStr;

PROCEDURE Italic*(r: Rope): Rope;
BEGIN
  IF NoEmphasis() THEN RETURN r END;
  RETURN Ropes.AppendChar(Ropes.Cat(Str("*"), r), "*")
END Italic;

(* A section label: a "## " heading in gemtext, whatever -e says, bold
   otherwise. *)
PROCEDURE SectionHeader*(r: Rope): Rope;
BEGIN
  IF OvaConfig.format = OvaConfig.Gemtext THEN RETURN Ropes.Cat(Str("## "), r) END;
  RETURN Bold(r)
END SectionHeader;

PROCEDURE SectionHeaderStr*(s: ARRAY OF CHAR): Rope;
BEGIN RETURN SectionHeader(Str(s))
END SectionHeaderStr;

(* A list item's prefix: gemtext's "* ", or reST's and Markdown's "- ". *)
PROCEDURE Bullet*(): Rope;
BEGIN
  IF OvaConfig.format = OvaConfig.Gemtext THEN RETURN Str("* ") END;
  RETURN Str("- ")
END Bullet;

(* ---- Numbers and text ---- *)

(* A number that is never negative (Health, Endurance, Threat Value, a
   Perk's counts-as), or one written as it is. *)
PROCEDURE TrimImg*(n: INTEGER): Rope;
BEGIN RETURN OvaText.Int(n)
END TrimImg;

(* U+2212 MINUS SIGN, or "-" under -n/--no-unicode-minus. *)
PROCEDURE MinusGlyph(): Rope;
BEGIN
  IF OvaConfig.unicodeMinus THEN RETURN Str("−") END;
  RETURN Str("-")
END MinusGlyph;

(* A number that may be negative (a roll, a chosen cost), with the
   minus glyph -n chooses. *)
PROCEDURE NumberImg*(n: INTEGER): Rope;
BEGIN
  IF n < 0 THEN RETURN Ropes.Cat(MinusGlyph(), TrimImg(-n)) END;
  RETURN TrimImg(n)
END NumberImg;

(* A Level: always signed. *)
PROCEDURE SignedImg*(n: INTEGER): Rope;
BEGIN
  IF n >= 0 THEN RETURN Ropes.Cat(Str("+"), TrimImg(n)) END;
  RETURN NumberImg(n)
END SignedImg;

(* r with a period at the end, unless it already ends with one. *)
PROCEDURE EndWithPeriod*(r: Rope): Rope;
  VAR len: LONGINT;
BEGIN
  len := Ropes.Length(r);
  IF (len > 0) & (Ropes.Fetch(r, len - 1) = ".") THEN RETURN r END;
  RETURN Ropes.AppendChar(r, ".")
END EndWithPeriod;

(* "Name (detail)", or "Name" without a detail. *)
PROCEDURE NameDetail*(name: Rope; hasDetail: BOOLEAN; detail: Rope): Rope;
  VAR r: Rope;
BEGIN
  r := name;
  IF hasDetail THEN OvaText.Add(r, " ("); r := Ropes.AppendChar(Ropes.Cat(r, detail), ")") END;
  RETURN r
END NameDetail;

PROCEDURE ToSpace(c: CHAR): CHAR;
BEGIN
  IF c = 0AX THEN RETURN " " END;
  RETURN c
END ToSpace;

(* r with every line feed a blank: for an h-m-m node, or a raw table's
   cell, which hold one line of text. *)
PROCEDURE AllOneLine*(r: Rope): Rope;
BEGIN
  IF Ropes.IndexChar(r, 0AX, 0) < 0 THEN RETURN r END;
  RETURN Ropes.Map(r, ToSpace)
END AllOneLine;

(* ---- The keys added for the character generator ---- *)

(* What follows a number its mapping's overrides: list names: NIL if
   it isn't overridden; "*"; or "\*" where the text is reST or
   Markdown, so the "*" can't open emphasis.  raw: the number goes in
   a raw HTML or groff table, so it's "*".  Gemtext and h-m-m have no
   emphasis to escape from. *)
PROCEDURE OverrideMark*(overridden, raw: BOOLEAN): Rope;
BEGIN
  IF ~overridden THEN RETURN NIL
  ELSIF raw OR (OvaConfig.format = OvaConfig.Gemtext) OR (OvaConfig.format = OvaConfig.Hmm) THEN
    RETURN Str("*")
  END;
  RETURN Str("\*")
END OverrideMark;

(* r, then OverrideMark(k IN overrides, raw). *)
PROCEDURE Marked*(r: Rope; k: INTEGER; overrides: SET; raw: BOOLEAN): Rope;
BEGIN RETURN Ropes.Cat(r, OverrideMark(k IN overrides, raw))
END Marked;

(* c's defense with a mark after each overridden value: a "2/4/6"
   Defense's are defense, defense-2 and defense-3. *)
PROCEDURE DefenseText*(c: OvaEntities.Combat; raw: BOOLEAN): Rope;
  VAR from, slash: LONGINT; k: INTEGER; r: Rope;
BEGIN
  r := NIL; from := 0; k := OvaEntities.OvDefense;
  slash := Ropes.IndexChar(c.defense, "/", from);
  WHILE (slash >= 0) & (k # OvaEntities.OvDefense3) DO
    r := Ropes.Cat(r, Marked(Ropes.Substring(c.defense, from, slash - from), k, c.overrides, raw));
    r := Ropes.Cat(r, Str("/"));
    from := slash + 1; INC(k);
    slash := Ropes.IndexChar(c.defense, "/", from)
  END;
  RETURN Ropes.Cat(r, Marked(Ropes.Substring(c.defense, from, Ropes.Length(c.defense) - from), k, c.overrides, raw))
END DefenseText;

(* " (half TV)" after the Level of an Ability or SubItem whose
   threat-value-half is true, with -O/--options; else NIL. *)
PROCEDURE HalfTVText*(s: OvaEntities.SubItem): Rope;
BEGIN
  IF OvaConfig.showOptions & s.hasThreatValueHalf & s.threatValueHalf THEN RETURN Str(" (half TV)") END;
  RETURN NIL
END HalfTVText;

(* " (text)" appended to r. *)
PROCEDURE AddParens(VAR r: Rope; text: Rope);
BEGIN OvaText.Add(r, " ("); r := Ropes.AppendChar(Ropes.Cat(r, text), ")")
END AddParens;

(* The items of l, each written by f, joined with ", ". *)
PROCEDURE Join(l: OvaEntities.List; f: Formatter): Rope;
  VAR r: Rope; i: INTEGER;
BEGIN
  r := NIL;
  FOR i := 0 TO l.n - 1 DO
    IF i > 0 THEN OvaText.Add(r, ", ") END;
    r := Ropes.Cat(r, f(l.items[i]))
  END;
  RETURN r
END Join;

(* ---- Perks and Flaws ---- *)

(* "Name: detail x2 (−5)", each part only if there. *)
PROCEDURE FormatPerkFlaw(x: Element): Rope;
  VAR pf: OvaEntities.PerkFlaw; r: Rope;
BEGIN
  pf := x(OvaEntities.PerkFlaw);
  r := pf.name;
  IF pf.hasDetail THEN OvaText.Add(r, ": "); r := Ropes.Cat(r, pf.detail) END;
  IF pf.hasCountsAs THEN OvaText.Add(r, " x"); r := Ropes.Cat(r, TrimImg(pf.countsAs)) END;
  IF pf.hasCost THEN AddParens(r, NumberImg(pf.cost)) END;
  RETURN r
END FormatPerkFlaw;

(* Appends text to parts, after "; " if parts isn't empty. *)
PROCEDURE AddPart(VAR parts: Rope; text: Rope);
BEGIN
  IF parts # NIL THEN OvaText.Add(parts, "; ") END;
  parts := Ropes.Cat(parts, text)
END AddPart;

(* " [Perks: ...; Flaws: ...; 5 Endurance]" for an Ability or a SubItem,
   with only the parts there are; NIL if none is.  raw: it goes in a raw
   HTML or groff table (see OverrideMark). *)
PROCEDURE FormatModifiersBracket*(s: OvaEntities.SubItem; raw: BOOLEAN): Rope;
  VAR parts: Rope;
BEGIN
  parts := NIL;
  IF s.perks.n > 0 THEN AddPart(parts, Ropes.Cat(Str("Perks: "), Join(s.perks, FormatPerkFlaw))) END;
  IF s.flaws.n > 0 THEN AddPart(parts, Ropes.Cat(Str("Flaws: "), Join(s.flaws, FormatPerkFlaw))) END;
  IF s.hasEndurance THEN
    AddPart(parts, Ropes.Cat(Marked(TrimImg(s.endurance), OvaEntities.OvEndurance, s.overrides, raw),
      Str(" Endurance")))
  END;
  IF parts = NIL THEN RETURN NIL END;
  RETURN Ropes.AppendChar(Ropes.Cat(Str(" ["), parts), "]")
END FormatModifiersBracket;

(* Appends "label: text" to parts, after "; " if parts isn't empty. *)
PROCEDURE AddClause(VAR parts: Rope; label: ARRAY OF CHAR; text: Rope);
BEGIN
  IF parts # NIL THEN OvaText.Add(parts, "; ") END;
  OvaText.Add(parts, label); OvaText.Add(parts, ": "); parts := Ropes.Cat(parts, text)
END AddClause;

(* "(Affinity: ...; Perks: ...; Flaws: ...)" for an attack, with only
   the clauses there are; NIL if none is. *)
PROCEDURE FormatAttackClause*(a: OvaEntities.Attack): Rope;
  VAR parts: Rope;
BEGIN
  parts := NIL;
  IF a.hasAffinity THEN AddClause(parts, "Affinity", a.affinity) END;
  IF a.perks.n > 0 THEN AddClause(parts, "Perks", Join(a.perks, FormatPerkFlaw)) END;
  IF a.flaws.n > 0 THEN AddClause(parts, "Flaws", Join(a.flaws, FormatPerkFlaw)) END;
  IF parts = NIL THEN RETURN NIL END;
  RETURN Ropes.AppendChar(Ropes.Cat(Str("("), parts), ")")
END FormatAttackClause;

(* ---- Item lines ---- *)

(* "Name (detail) +L [Perks: ...; Flaws: ...] (note)": an Ability or a
   SubItem (the Ada Format_Ability_Line and Format_Sub_Item_Line, which
   are the same). *)
PROCEDURE FormatSubItemLine*(x: Element): Rope;
  VAR s: OvaEntities.SubItem; r: Rope;
BEGIN
  s := x(OvaEntities.SubItem);
  r := NameDetail(s.name, s.hasDetail, s.detail);
  r := Ropes.AppendChar(r, " "); r := Ropes.Cat(r, SignedImg(s.level)); r := Ropes.Cat(r, HalfTVText(s));
  r := Ropes.Cat(r, FormatModifiersBracket(s, FALSE));
  IF s.hasNote THEN AddParens(r, s.note) END;
  RETURN r
END FormatSubItemLine;

(* "Name (detail) +L". *)
PROCEDURE FormatWeaknessLine*(x: Element): Rope;
  VAR w: OvaEntities.Weakness; r: Rope;
BEGIN
  w := x(OvaEntities.Weakness);
  r := NameDetail(w.name, w.hasDetail, w.detail);
  r := Ropes.AppendChar(r, " ");
  RETURN Ropes.Cat(r, SignedImg(w.level))
END FormatWeaknessLine;

(* An NPC Fragment's order, "Name +L (detail) [...] (note)": an Ability
   or a SubItem (the Ada Format_Fragment_Ability_Line and
   Format_Fragment_Sub_Item_Line, which are the same). *)
PROCEDURE FormatFragmentSubItemLine*(x: Element): Rope;
  VAR s: OvaEntities.SubItem; r: Rope;
BEGIN
  s := x(OvaEntities.SubItem);
  r := Ropes.AppendChar(s.name, " "); r := Ropes.Cat(r, SignedImg(s.level)); r := Ropes.Cat(r, HalfTVText(s));
  IF s.hasDetail THEN AddParens(r, s.detail) END;
  r := Ropes.Cat(r, FormatModifiersBracket(s, FALSE));
  IF s.hasNote THEN AddParens(r, s.note) END;
  RETURN r
END FormatFragmentSubItemLine;

(* "Name +L (detail)". *)
PROCEDURE FormatFragmentWeaknessLine*(x: Element): Rope;
  VAR w: OvaEntities.Weakness; r: Rope;
BEGIN
  w := x(OvaEntities.Weakness);
  r := Ropes.AppendChar(w.name, " "); r := Ropes.Cat(r, SignedImg(w.level));
  IF w.hasDetail THEN AddParens(r, w.detail) END;
  RETURN r
END FormatFragmentWeaknessLine;

(* "Name (Ability +L; E Endurance)". *)
PROCEDURE FormatSpellLine*(x: Element): Rope;
  VAR s: OvaEntities.Spell; r: Rope;
BEGIN
  s := x(OvaEntities.Spell);
  r := s.name; OvaText.Add(r, " ("); r := Ropes.Cat(r, s.ability);
  r := Ropes.AppendChar(r, " "); r := Ropes.Cat(r, SignedImg(s.level));
  OvaText.Add(r, "; "); r := Ropes.Cat(r, Marked(s.endurance, OvaEntities.OvEndurance, s.overrides, FALSE));
  OvaText.Add(r, " Endurance)");
  RETURN r
END FormatSpellLine;

(* Abilities or SubItems, joined with ", ". *)
PROCEDURE JoinSubItems*(l: OvaEntities.List): Rope;
BEGIN RETURN Join(l, FormatSubItemLine)
END JoinSubItems;

PROCEDURE JoinWeaknesses*(l: OvaEntities.List): Rope;
BEGIN RETURN Join(l, FormatWeaknessLine)
END JoinWeaknesses;

PROCEDURE JoinFragmentSubItems*(l: OvaEntities.List): Rope;
BEGIN RETURN Join(l, FormatFragmentSubItemLine)
END JoinFragmentSubItems;

PROCEDURE JoinFragmentWeaknesses*(l: OvaEntities.List): Rope;
BEGIN RETURN Join(l, FormatFragmentWeaknessLine)
END JoinFragmentWeaknesses;

PROCEDURE JoinSpells*(l: OvaEntities.List): Rope;
BEGIN RETURN Join(l, FormatSpellLine)
END JoinSpells;

(* a, then "; " if both a and b are there, then b: abilities then
   weaknesses, already joined. *)
PROCEDURE Semi*(a, b: Rope; haveA, haveB: BOOLEAN): Rope;
BEGIN
  IF haveA & haveB THEN OvaText.Add(a, "; ") END;
  RETURN Ropes.Cat(a, b)
END Semi;

(* ---- Combat ---- *)

(* "**Name:** Roll **N dice** | **DX d** | **Endurance Cost: c**
   (clause). *Description*", with no bullet. *)
PROCEDURE FormatAttackLine*(a: OvaEntities.Attack): Rope;
  VAR r, t, clause: Rope;
BEGIN
  t := Ropes.AppendChar(a.name, ":"); r := Bold(t);
  OvaText.Add(r, " Roll ");
  t := Marked(NumberImg(a.roll), OvaEntities.OvRoll, a.overrides, FALSE);
  OvaText.Add(t, " dice"); r := Ropes.Cat(r, Bold(t));
  OvaText.Add(r, " | ");
  t := Ropes.Cat(Str("DX "), Marked(a.dx, OvaEntities.OvDx, a.overrides, FALSE)); r := Ropes.Cat(r, Bold(t));
  OvaText.Add(r, " | ");
  t := Marked(TrimImg(a.endurance), OvaEntities.OvEndurance, a.overrides, FALSE);
  t := Ropes.Cat(Str("Endurance Cost: "), t); r := Ropes.Cat(r, Bold(t));
  clause := FormatAttackClause(a);
  IF clause # NIL THEN r := Ropes.AppendChar(r, " "); r := Ropes.Cat(r, clause) END;
  r := Ropes.AppendChar(r, ".");
  IF a.hasDescription THEN r := Ropes.AppendChar(r, " "); r := Ropes.Cat(r, Italic(a.description)) END;
  RETURN r
END FormatAttackLine;

(* "**Health:** H | **Endurance:** E | **Defense:** D | **Threat Value
   (TV):** T", an em dash for a missing TV; no bullet.  Led by "**NPC
   Type:** T | " if npcType isn't NIL. *)
PROCEDURE FormatCombatSummaryLine*(c: OvaEntities.Combat; npcType: Rope): Rope;
  VAR r: Rope;
BEGIN
  r := NIL;
  IF npcType # NIL THEN
    r := BoldStr("NPC Type:"); r := Ropes.AppendChar(r, " "); r := Ropes.Cat(r, npcType);
    OvaText.Add(r, " | ")
  END;
  r := Ropes.Cat(r, BoldStr("Health:")); r := Ropes.AppendChar(r, " ");
  r := Ropes.Cat(r, Marked(TrimImg(c.health), OvaEntities.OvHealth, c.overrides, FALSE));
  OvaText.Add(r, " | "); r := Ropes.Cat(r, BoldStr("Endurance:"));
  r := Ropes.AppendChar(r, " ");
  r := Ropes.Cat(r, Marked(TrimImg(c.endurance), OvaEntities.OvEndurance, c.overrides, FALSE));
  OvaText.Add(r, " | "); r := Ropes.Cat(r, BoldStr("Defense:"));
  r := Ropes.AppendChar(r, " "); r := Ropes.Cat(r, DefenseText(c, FALSE));
  OvaText.Add(r, " | "); r := Ropes.Cat(r, BoldStr("Threat Value (TV):"));
  r := Ropes.AppendChar(r, " ");
  IF c.hasThreatValue THEN
    r := Ropes.Cat(r, Marked(TrimImg(c.threatValue), OvaEntities.OvThreatValue, c.overrides, FALSE))
  ELSE OvaText.Add(r, "—")
  END;
  RETURN r
END FormatCombatSummaryLine;

(* An attack: a sub-bullet in reST and Markdown; gemtext's lists don't
   nest, so just its bullet there. *)
PROCEDURE PrintAttack(a: OvaEntities.Attack);
BEGIN
  IF OvaConfig.format = OvaConfig.Gemtext THEN OvaOut.Rope(Bullet()) ELSE OvaOut.String("  - ") END;
  Line(FormatAttackLine(a))
END PrintAttack;

(* The combat summary, its line led by npcType if that isn't NIL, then
   the attacks and combat notes. *)
PROCEDURE PrintCombatAndAttacks*(c: OvaEntities.Combat; npcType: Rope);
  VAR i: INTEGER;
BEGIN
  IF ~c.hasCombat THEN RETURN END;
  Line(Ropes.Cat(Bullet(), FormatCombatSummaryLine(c, npcType)));
  OvaOut.Ln;
  IF c.attacks.n > 0 THEN
    Line(Ropes.Cat(Bullet(), BoldStr("Attacks:")));
    OvaOut.Ln;
    FOR i := 0 TO c.attacks.n - 1 DO PrintAttack(c.attacks.items[i](OvaEntities.Attack)) END;
    OvaOut.Ln
  END;
  (* A paragraph, not a bullet: several lines would need indenting in a
     reST bullet. *)
  IF c.hasNotes THEN
    OvaOut.Rope(BoldStr("Combat Notes:")); OvaOut.Char(" "); Line(c.notes); OvaOut.Ln
  END
END PrintCombatAndAttacks;

(* ---- Linked content ---- *)

(* A Companion or Vehicle with fragment: true: "**Name** --
   **Attributes:** ...", or "**Name**." if it has neither abilities nor
   weaknesses, then its combat. *)
PROCEDURE PrintSubEntityFragmentStyle*(se: OvaEntities.SubEntity);
  VAR r: Rope;
BEGIN
  IF (se.abilities.n = 0) & (se.weaknesses.n = 0) THEN
    Line(Ropes.AppendChar(Bold(se.name), "."))
  ELSE
    r := Bold(se.name); OvaText.Add(r, " -- "); r := Ropes.Cat(r, BoldStr("Attributes:"));
    r := Ropes.AppendChar(r, " ");
    r := Ropes.Cat(r, Semi(JoinFragmentSubItems(se.abilities), JoinFragmentSubItems(se.weaknesses),
      se.abilities.n > 0, se.weaknesses.n > 0));
    Line(Ropes.AppendChar(r, "."))
  END;
  OvaOut.Ln;
  PrintCombatAndAttacks(se.combat, NIL)
END PrintSubEntityFragmentStyle;

(* "Label: Name", a sub-entity's heading. *)
PROCEDURE SubEntityTitle*(se: OvaEntities.SubEntity): Rope;
BEGIN RETURN Ropes.Cat(Ropes.Cat(se.label, Str(": ")), se.name)
END SubEntityTitle;

(* "Grants: ...; ...", a Transformation's granted items, without the
   period. *)
PROCEDURE GrantsLine*(a: OvaEntities.Ability): Rope;
BEGIN
  RETURN Ropes.Cat(Str("Grants: "), Semi(JoinSubItems(a.subAbilities), JoinSubItems(a.subWeaknesses),
    a.subAbilities.n > 0, a.subWeaknesses.n > 0))
END GrantsLine;

(* Whether a has linked content: a Transformation's items, spells, or a
   sub-entity. *)
PROCEDURE HasLinked*(a: OvaEntities.Ability): BOOLEAN;
BEGIN
  RETURN (a.subAbilities.n > 0) OR (a.subWeaknesses.n > 0) OR (a.spells.n > 0) OR (a.subEntity # NIL)
END HasLinked;

(* A section for an Ability's linked content, after the main entity's
   attacks. *)
PROCEDURE PrintLinkedSection(a: OvaEntities.Ability);
  VAR se: OvaEntities.SubEntity;
BEGIN
  IF ~HasLinked(a) THEN RETURN END;
  se := a.subEntity;
  IF (se # NIL) & se.isFragment THEN PrintSubEntityFragmentStyle(se); RETURN END;

  IF se # NIL THEN Line(SectionHeader(SubEntityTitle(se)))
  ELSE Line(SectionHeader(NameDetail(a.name, a.hasDetail, a.detail)))
  END;
  OvaOut.Ln;

  IF (a.subAbilities.n > 0) OR (a.subWeaknesses.n > 0) THEN
    Line(EndWithPeriod(GrantsLine(a))); OvaOut.Ln
  END;
  IF a.spells.n > 0 THEN
    Line(EndWithPeriod(Ropes.Cat(Str("Spells: "), JoinSpells(a.spells)))); OvaOut.Ln
  END;
  IF se # NIL THEN
    IF se.abilities.n > 0 THEN
      Line(EndWithPeriod(Ropes.Cat(Str("Abilities: "), JoinSubItems(se.abilities)))); OvaOut.Ln
    END;
    IF se.weaknesses.n > 0 THEN
      Line(EndWithPeriod(Ropes.Cat(Str("Weaknesses: "), JoinSubItems(se.weaknesses)))); OvaOut.Ln
    END;
    PrintCombatAndAttacks(se.combat, NIL)
  END
END PrintLinkedSection;

PROCEDURE PrintLinkedSections(e: OvaEntities.Entity);
  VAR i: INTEGER;
BEGIN
  FOR i := 0 TO e.abilities.n - 1 DO PrintLinkedSection(e.abilities.items[i](OvaEntities.Ability)) END
END PrintLinkedSections;

(* ---- Header, prose and tail ---- *)

(* An NPC Fragment's name is in its background's prose; only without
   one is the bare name written, bold. *)
PROCEDURE PrintFragmentHeader(e: OvaEntities.Entity);
BEGIN
  IF e.hasBackground THEN Line(e.background) ELSE Line(Bold(e.name)) END;
  OvaOut.Ln
END PrintFragmentHeader;

(* e's npc-type's name, or NIL if it has none: the Ada NPC_Type_Text. *)
PROCEDURE NpcTypeText*(e: OvaEntities.Entity): Rope;
BEGIN
  IF e.hasNpcType THEN RETURN OvaEntities.NpcTypeName(e.npcType) END;
  RETURN NIL
END NpcTypeText;

(* "**Attributes (Secondary):**" with an npc-type, else
   "**Attributes:**". *)
PROCEDURE FragmentAttributesLabel*(e: OvaEntities.Entity): Rope;
BEGIN
  IF e.hasNpcType THEN
    RETURN Bold(Ropes.Cat(Ropes.Cat(Str("Attributes ("), NpcTypeText(e)), Str("):")))
  END;
  RETURN BoldStr("Attributes:")
END FragmentAttributesLabel;

(* "**Attributes:** abilities; weaknesses." *)
PROCEDURE FragmentAttributes*(e: OvaEntities.Entity): Rope;
  VAR r: Rope;
BEGIN
  r := FragmentAttributesLabel(e); r := Ropes.AppendChar(r, " ");
  r := Ropes.Cat(r, Semi(JoinFragmentSubItems(e.abilities), JoinFragmentWeaknesses(e.weaknesses),
    e.abilities.n > 0, e.weaknesses.n > 0));
  RETURN Ropes.AppendChar(r, ".")
END FragmentAttributes;

PROCEDURE PrintFragmentAttributes(e: OvaEntities.Entity);
BEGIN
  IF (e.abilities.n = 0) & (e.weaknesses.n = 0) THEN RETURN END;
  Line(FragmentAttributes(e)); OvaOut.Ln
END PrintFragmentAttributes;

(* After the other prose, as the Sample NPCs' pages have it (and after a
   Fragment's Attributes line, it having no other prose section). *)
PROCEDURE PrintCharacterHooks(e: OvaEntities.Entity);
BEGIN
  IF e.hasCharacterHooks THEN
    Line(SectionHeaderStr("Character Hooks")); OvaOut.Ln;
    Line(e.characterHooks); OvaOut.Ln
  END
END PrintCharacterHooks;

(* The entity's title: "Name (concept)", or "Name", then ", played by
   Player" with a player: (the Ada Entity_Title). *)
PROCEDURE Title*(e: OvaEntities.Entity): Rope;
  VAR has: BOOLEAN; r: Rope;
BEGIN
  has := e.hasFluff & e.hasFluffField[OvaEntities.Concept];
  r := NameDetail(e.name, has, e.fluff[OvaEntities.Concept]);
  IF e.hasPlayer THEN OvaText.Add(r, ", played by "); r := Ropes.Cat(r, e.player) END;
  RETURN r
END Title;

(* Title, tagline, summary, background, personality and character
   hooks: the same in every format but the title's heading: "# Title"
   in gemtext and Markdown, else the title underlined, with -U's
   character for every entity of a file after the first if it was
   given. *)
PROCEDURE PrintHeaderAndProse*(e: OvaEntities.Entity; entityNo: INTEGER);
  VAR title: Rope; c: CHAR;
BEGIN
  title := Title(e);
  IF (OvaConfig.format = OvaConfig.Gemtext) OR (OvaConfig.format = OvaConfig.Markdown) THEN
    OvaOut.String("# "); Line(title)
  ELSE
    IF (entityNo > 1) & (OvaConfig.subunderliner # 0X) THEN c := OvaConfig.subunderliner
    ELSE c := OvaConfig.underliner
    END;
    Line(title);
    OvaOut.Repeat(c, Ropes.Length(title)); OvaOut.Ln
  END;
  OvaOut.Ln;

  (* The portrait, in HTML-in-reST only: its path is relative to the
     YAML file, so the HTML must be made beside it. *)
  IF (OvaConfig.format = OvaConfig.HtmlInRst) & e.hasPortrait THEN
    OvaOut.String(".. image:: "); Line(e.portrait);
    OvaOut.String("   :alt: "); Line(e.name);
    OvaOut.Ln
  END;

  IF e.hasTagline THEN
    Line(Italic(Ropes.AppendChar(Ropes.Cat(Str('"'), e.tagline), '"'))); OvaOut.Ln
  END;
  IF e.hasSummary THEN Line(Italic(e.summary)); OvaOut.Ln END;
  IF e.hasBackground THEN
    Line(SectionHeaderStr("Background")); OvaOut.Ln;
    Line(e.background); OvaOut.Ln
  END;
  IF e.hasAppearance THEN
    Line(SectionHeaderStr("Appearance")); OvaOut.Ln;
    Line(e.appearance); OvaOut.Ln
  END;
  IF e.hasPersonality THEN
    Line(SectionHeaderStr("Personality")); OvaOut.Ln;
    Line(e.personality); OvaOut.Ln
  END;
  PrintCharacterHooks(e)
END PrintHeaderAndProse;

PROCEDURE PrintNotes*(e: OvaEntities.Entity);
  VAR i: INTEGER; n: OvaEntities.Note;
BEGIN
  IF e.notes.n > 0 THEN
    Line(SectionHeaderStr("Notes")); OvaOut.Ln;
    FOR i := 0 TO e.notes.n - 1 DO
      n := e.notes.items[i](OvaEntities.Note);
      OvaOut.Rope(Bold(n.header)); OvaOut.String(" -- "); Line(n.text);
      OvaOut.Ln
    END
  END;
  IF e.hasOtherNotes THEN
    Line(SectionHeaderStr("Other Notes")); OvaOut.Ln;
    Line(e.otherNotes); OvaOut.Ln
  END
END PrintNotes;

(* Appends item to r, after ", " unless r is empty. *)
PROCEDURE AddItem(VAR r: Rope; first: BOOLEAN; item: Rope);
BEGIN
  IF ~first THEN OvaText.Add(r, ", ") END;
  r := Ropes.Cat(r, item)
END AddItem;

(* The creation rules of e's options: block, as "Base Zero (±5), Power
   Ceiling (15), ...", without the period; FALSE if there are none. *)
PROCEDURE CreationRules*(e: OvaEntities.Entity; VAR r: Rope): BOOLEAN;
  VAR t: Rope; first: BOOLEAN;
BEGIN
  r := NIL; first := TRUE;
  IF e.options.hasBaseZero THEN
    t := Ropes.AppendChar(Ropes.Cat(Str("Base Zero (±"), TrimImg(e.options.baseZero)), ")");
    AddItem(r, first, t); first := FALSE
  END;
  IF e.options.hasPowerCeiling THEN
    t := Ropes.AppendChar(Ropes.Cat(Str("Power Ceiling ("), TrimImg(e.options.powerCeiling)), ")");
    AddItem(r, first, t); first := FALSE
  END;
  IF e.options.hasStartingLevels THEN
    t := Ropes.AppendChar(Ropes.Cat(Str("Starting Levels ("), TrimImg(e.options.startingLevels)), ")");
    AddItem(r, first, t); first := FALSE
  END;
  IF e.options.scaledCost THEN AddItem(r, first, Str("Scaled Cost")); first := FALSE END;
  IF e.options.halfCostKnowledge THEN AddItem(r, first, Str("Half-Cost Knowledge")); first := FALSE END;
  IF e.options.combinedEffectiveness THEN AddItem(r, first, Str("Combined Effectiveness")); first := FALSE END;
  RETURN ~first
END CreationRules;

(* "**Creation Rules:** ...", only with -O/--options. *)
PROCEDURE PrintOptionsIfShown*(e: OvaEntities.Entity);
  VAR r: Rope;
BEGIN
  IF OvaConfig.showOptions & e.hasOptions & CreationRules(e, r) THEN
    OvaOut.Rope(BoldStr("Creation Rules:")); OvaOut.Char(" "); Line(EndWithPeriod(r));
    OvaOut.Ln
  END
END PrintOptionsIfShown;

(* The label of fluff field i, as the text formats write it. *)
PROCEDURE FluffLabel(i: INTEGER): Rope;
  VAR s: ARRAY 16 OF CHAR;
BEGIN
  CASE i OF
    OvaEntities.Concept: s := "Concept"
  | OvaEntities.Birthday: s := "Birthday"
  | OvaEntities.Age: s := "Age"
  | OvaEntities.Gender: s := "Gender"
  | OvaEntities.Height: s := "Height"
  | OvaEntities.Weight: s := "Weight"
  | OvaEntities.Hair: s := "Hair"
  | OvaEntities.Eyes: s := "Eyes"
  | OvaEntities.Association: s := "Association"
  | OvaEntities.Hobbies: s := "Hobbies"
  | OvaEntities.FavoriteFood: s := "Favorite Food"
  | OvaEntities.Allies: s := "Allies"
  | OvaEntities.Enemies: s := "Enemies"
  | OvaEntities.LoveInterests: s := "Love Interests"
  END;
  RETURN Str(s)
END FluffLabel;

(* "**Concept:** ..., **Age:** ...", every fluff field there is, without
   the period. *)
PROCEDURE FluffLine*(e: OvaEntities.Entity): Rope;
  VAR r, t: Rope; i: INTEGER; first: BOOLEAN;
BEGIN
  r := NIL; first := TRUE;
  FOR i := 0 TO OvaEntities.NFluff - 1 DO
    IF e.hasFluffField[i] THEN
      t := Bold(Ropes.AppendChar(FluffLabel(i), ":"));
      t := Ropes.AppendChar(t, " "); t := Ropes.Cat(t, e.fluff[i]);
      AddItem(r, first, t); first := FALSE
    END
  END;
  RETURN r
END FluffLine;

(* Notes, fluff and creation rules: the same in every format but
   groff-in-reST, which has its own fluff table. *)
PROCEDURE PrintTail*(e: OvaEntities.Entity);
BEGIN
  PrintNotes(e);
  IF e.hasFluff THEN
    Line(SectionHeaderStr("Fluff")); OvaOut.Ln;
    Line(EndWithPeriod(FluffLine(e))); OvaOut.Ln
  END;
  PrintOptionsIfShown(e)
END PrintTail;

(* The whole entity for terse reST, gemtext and Markdown, and an NPC
   Fragment in every format but h-m-m: a Fragment is flat whatever the
   format. *)
PROCEDURE ProcessEntity*(e: OvaEntities.Entity; entityNo: INTEGER);
BEGIN
  IF e.isFragment THEN
    PrintFragmentHeader(e);
    PrintFragmentAttributes(e);
    PrintCharacterHooks(e);
    PrintCombatAndAttacks(e.combat, NIL);
    PrintLinkedSections(e)
  ELSE
    PrintHeaderAndProse(e, entityNo);
    IF e.abilities.n > 0 THEN
      OvaOut.Rope(Bullet()); OvaOut.Rope(BoldStr("Abilities:")); OvaOut.Char(" ");
      OvaOut.Rope(JoinSubItems(e.abilities)); Line(Str("."));
      OvaOut.Ln
    END;
    IF e.weaknesses.n > 0 THEN
      OvaOut.Rope(Bullet()); OvaOut.Rope(BoldStr("Weaknesses:")); OvaOut.Char(" ");
      OvaOut.Rope(JoinWeaknesses(e.weaknesses)); Line(Str("."));
      OvaOut.Ln
    END;
    PrintCombatAndAttacks(e.combat, NpcTypeText(e));
    PrintLinkedSections(e)
  END;
  PrintTail(e)
END ProcessEntity;

END OvaCommon.
