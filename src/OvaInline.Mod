MODULE OvaInline; (* The inline format: -i/--inline *)

(* Each entity as one Markdown paragraph, a stat block for an
   adventure's cast (the user's request of 2026-10-23, modeled on the
   Cast of Lost-Worlds' 001-breakout.md):

     **Name** (Secondary). Summary. Background. *Ability +2 (detail),
     ...; Weakness -1, ...* Attack (Perks; Flaws): Roll 4, DX 3, End
     0. Defense 3. Health 20, Endurance 20. TV 6.

   A count: over 1 makes the lead "**Name** (three Secondaries)." and
   the end "TV 6 each.": one stat block standing for a group.  It is
   the only format that shows it, as a sheet describes one.

   First written here, then ported to the Ada version, whose output is
   now its reference (PLAN.md, "The inline format").  It is a stat block, so it leaves out
   what a cast list doesn't need: the tagline, character hooks, notes,
   fluff, the player and the portrait.  The prose that describes the
   entity (summary, background, appearance, personality) runs together
   on one line, as do its combat notes.  An NPC Fragment's background
   names it already, so it leads instead of the bold name.  An Ability's
   linked content (a Transformation's grants, spells, a Companion or
   Vehicle) follows as a paragraph of its own.  Abilities and
   Weaknesses, there too, are "Name Level (detail)", the rulebook's NPC
   Fragment order, as the cast has "Attack +2 (Blaster rifle)".

   Each paragraph is filled to Width columns, counting characters, not
   bytes, never breaking a line before a word that would start a
   Markdown block there (OpensBlock). *)

IMPORT OvaCommon, OvaEntities, OvaOut, OvaText, Ropes;

CONST
  Width = 70;

TYPE
  Rope = Ropes.Rope;

PROCEDURE Str(s: ARRAY OF CHAR): Rope;
BEGIN RETURN Ropes.FromString(s)
END Str;

(* Appends r to p, after a blank unless p is empty. *)
PROCEDURE Add(VAR p: Rope; r: Rope);
BEGIN
  IF p # NIL THEN p := Ropes.AppendChar(p, " ") END;
  p := Ropes.Cat(p, r)
END Add;

(* r ended with a period, unless it ends a sentence already: with ".",
   "!" or "?", perhaps then a closing quote or parenthesis. *)
PROCEDURE Sentence(r: Rope): Rope;
  VAR i: LONGINT; c: CHAR;
BEGIN
  i := Ropes.Length(r);
  REPEAT
    DEC(i);
    IF i >= 0 THEN c := Ropes.Fetch(r, i) ELSE c := 0X END
  UNTIL (c # '"') & (c # "'") & (c # ")");
  IF (c = ".") OR (c = "!") OR (c = "?") THEN RETURN r END;
  RETURN Ropes.AppendChar(r, ".")
END Sentence;

(* Appends the prose r, on one line, as a sentence. *)
PROCEDURE AddProse(VAR p: Rope; r: Rope);
BEGIN Add(p, Sentence(OvaCommon.AllOneLine(r)))
END AddProse;

(* ---- Filling ---- *)

(* Whether the word s[from .. to-1], at the start of a line, would make
   it something other than a paragraph's text: a heading, a block
   quote, a list item (a lone "-", "+" or "*", or digits and a "." or
   ")"), a thematic break or a setext underline (nothing but "-", "=",
   "*" or "_"). *)
PROCEDURE OpensBlock(VAR s: ARRAY OF CHAR; from, to: INTEGER): BOOLEAN;
  VAR i: INTEGER; c: CHAR;
BEGIN
  c := s[from];
  IF (c = "#") OR (c = ">") OR (c = "+") & (to - from = 1) THEN RETURN TRUE END;
  i := from;
  WHILE (i < to) & ((s[i] = "-") OR (s[i] = "=") OR (s[i] = "*") OR (s[i] = "_")) DO INC(i) END;
  IF i = to THEN RETURN TRUE END;
  i := from;
  WHILE (i < to) & (s[i] >= "0") & (s[i] <= "9") DO INC(i) END;
  RETURN (i > from) & (i = to - 1) & ((s[i] = ".") OR (s[i] = ")"))
END OpensBlock;

(* Scans the word that starts at or after i in s[0 .. n-1], setting
   from and i to its bounds and w to its width.  A character is a byte
   that isn't a UTF-8 continuation byte (80X to 0BFX), so U+2212 is one
   column.  from = n if there is no word left. *)
PROCEDURE Word(VAR s: ARRAY OF CHAR; n: INTEGER; VAR i, from, w: INTEGER);
BEGIN
  WHILE (i < n) & (s[i] = " ") DO INC(i) END;
  from := i; w := 0;
  WHILE (i < n) & (s[i] # " ") DO
    IF (s[i] < 80X) OR (s[i] >= 0C0X) THEN INC(w) END;
    INC(i)
  END
END Word;

(* Writes p filled to Width columns, then an empty line.  Words are
   split at blanks, and a run of blanks is one.  A word that would open
   a Markdown block at the start of a line stays on the line of the word
   before it, so the break comes before that one instead.  A word, or
   words kept together, longer than Width has a line of its own. *)
PROCEDURE Paragraph(p: Rope);
  VAR s: OvaText.String; i, j, k, from, to, next, n, col, w, w2: INTEGER;
BEGIN
  s := OvaText.Chars(p); n := SHORT(Ropes.Length(p));
  col := 0; i := 0;
  Word(s^, n, i, from, w); to := i;
  WHILE from < n DO
    (* Take in the words that can't start a line. *)
    k := i; Word(s^, n, k, next, w2);
    WHILE (next < n) & OpensBlock(s^, next, k) DO
      INC(w, 1 + w2); to := k; i := k; Word(s^, n, k, next, w2)
    END;
    IF col > 0 THEN
      IF col + 1 + w > Width THEN OvaOut.Ln; col := 0 ELSE OvaOut.Char(" "); INC(col) END
    END;
    (* Write s[from .. to-1] with each run of blanks as one. *)
    FOR j := from TO to - 1 DO
      IF (s[j] # " ") OR (s[j - 1] # " ") THEN OvaOut.Char(s[j]) END
    END;
    INC(col, w);
    Word(s^, n, i, from, w); to := i
  END;
  OvaOut.Ln; OvaOut.Ln
END Paragraph;

(* ---- Parts ---- *)

(* "*abilities; weaknesses.*", NIL if there are neither.  Each is
   "Name Level (detail)", the NPC Fragment order, as in a cast list:
   "Attack +2 (Blaster rifle)". *)
PROCEDURE Traits(abilities, weaknesses: OvaEntities.List; weak: BOOLEAN): Rope;
  VAR w: Rope;
BEGIN
  IF (abilities.n = 0) & (weaknesses.n = 0) THEN RETURN NIL END;
  IF weak THEN w := OvaCommon.JoinFragmentWeaknesses(weaknesses)
  ELSE w := OvaCommon.JoinFragmentSubItems(weaknesses)
  END;
  RETURN OvaCommon.Italic(Ropes.AppendChar(OvaCommon.Semi(OvaCommon.JoinFragmentSubItems(abilities), w,
    abilities.n > 0, weaknesses.n > 0), "."))
END Traits;

(* The perks or flaws of l, each as OvaCommon writes it, joined with
   ", ". *)
PROCEDURE PerksFlaws(l: OvaEntities.List): Rope;
  VAR r: Rope; i: INTEGER;
BEGIN
  r := NIL;
  FOR i := 0 TO l.n - 1 DO
    IF i > 0 THEN OvaText.Add(r, ", ") END;
    r := Ropes.Cat(r, OvaCommon.FormatPerkFlaw(l.items[i]))
  END;
  RETURN r
END PerksFlaws;

(* Appends text to parts, after "; " if parts isn't empty. *)
PROCEDURE AddPart(VAR parts: Rope; text: Rope);
BEGIN
  IF parts # NIL THEN OvaText.Add(parts, "; ") END;
  parts := Ropes.Cat(parts, text)
END AddPart;

(* "Name (Affinity: a; perks; flaws): Roll N, DX d, End c.", then its
   description, with only the parenthesized parts there are. *)
PROCEDURE Attack(a: OvaEntities.Attack): Rope;
  VAR r, parts: Rope;
BEGIN
  parts := NIL;
  IF a.hasAffinity THEN AddPart(parts, Ropes.Cat(Str("Affinity: "), a.affinity)) END;
  IF a.perks.n > 0 THEN AddPart(parts, PerksFlaws(a.perks)) END;
  IF a.flaws.n > 0 THEN AddPart(parts, PerksFlaws(a.flaws)) END;
  r := a.name;
  IF parts # NIL THEN OvaText.Add(r, " ("); r := Ropes.AppendChar(Ropes.Cat(r, parts), ")") END;
  OvaText.Add(r, ": Roll ");
  r := Ropes.Cat(r, OvaCommon.Marked(OvaCommon.NumberImg(a.roll), OvaEntities.OvRoll, a.overrides, FALSE));
  OvaText.Add(r, ", DX ");
  r := Ropes.Cat(r, OvaCommon.Marked(a.dx, OvaEntities.OvDx, a.overrides, FALSE));
  OvaText.Add(r, ", End ");
  r := Ropes.Cat(r, OvaCommon.Marked(OvaCommon.TrimImg(a.endurance), OvaEntities.OvEndurance, a.overrides, FALSE));
  r := Ropes.AppendChar(r, ".");
  IF a.hasDescription THEN AddProse(r, a.description) END;
  RETURN r
END Attack;

(* n as a word, up to twelve, as prose has it; past that its digits:
   the Ada Count_Text. *)
PROCEDURE CountText(n: INTEGER): Rope;
BEGIN
  CASE n OF
    1: RETURN Str("one")
  | 2: RETURN Str("two")
  | 3: RETURN Str("three")
  | 4: RETURN Str("four")
  | 5: RETURN Str("five")
  | 6: RETURN Str("six")
  | 7: RETURN Str("seven")
  | 8: RETURN Str("eight")
  | 9: RETURN Str("nine")
  | 10: RETURN Str("ten")
  | 11: RETURN Str("eleven")
  | 12: RETURN Str("twelve")
  ELSE RETURN OvaCommon.TrimImg(n)
  END
END CountText;

(* e's NPC type's plural, as a count of them has it: "Secondaries". *)
PROCEDURE NpcTypePlural(e: OvaEntities.Entity): Rope;
BEGIN
  IF e.npcType = OvaEntities.Secondary THEN RETURN Str("Secondaries") END;
  RETURN Ropes.AppendChar(OvaCommon.NpcTypeText(e), "s")
END NpcTypePlural;

(* "(three)", the parenthesis that says how many. *)
PROCEDURE Parenthesized(r: Rope): Rope;
BEGIN RETURN Ropes.AppendChar(Ropes.Cat(Str("("), r), ")")
END Parenthesized;

(* c's attacks, then "Defense D. Health H, Endurance E. TV T.", then its
   notes, appended to p; nothing if there is no combat. *)
PROCEDURE AddCombat(VAR p: Rope; c: OvaEntities.Combat; group: BOOLEAN);
  VAR i: INTEGER; r: Rope;
BEGIN
  IF ~c.hasCombat THEN RETURN END;
  FOR i := 0 TO c.attacks.n - 1 DO Add(p, Attack(c.attacks.items[i](OvaEntities.Attack))) END;
  r := Ropes.Cat(Str("Defense "), OvaCommon.DefenseText(c, FALSE)); OvaText.Add(r, ". Health ");
  r := Ropes.Cat(r, OvaCommon.Marked(OvaCommon.TrimImg(c.health), OvaEntities.OvHealth, c.overrides, FALSE));
  OvaText.Add(r, ", Endurance ");
  r := Ropes.Cat(r, OvaCommon.Marked(OvaCommon.TrimImg(c.endurance), OvaEntities.OvEndurance, c.overrides, FALSE));
  r := Ropes.AppendChar(r, ".");
  IF c.hasThreatValue THEN
    OvaText.Add(r, " TV ");
    r := Ropes.Cat(r, OvaCommon.Marked(OvaCommon.TrimImg(c.threatValue), OvaEntities.OvThreatValue, c.overrides,
      FALSE));
    IF group THEN OvaText.Add(r, " each") END;
    r := Ropes.AppendChar(r, ".")
  END;
  Add(p, r);
  IF c.hasNotes THEN AddProse(p, c.notes) END
END AddCombat;

(* A paragraph for an Ability's linked content, led by its title in
   bold: "**Companion: Name.**", or the Ability's name and detail. *)
PROCEDURE Linked(a: OvaEntities.Ability);
  VAR p, t: Rope; se: OvaEntities.SubEntity;
BEGIN
  IF ~OvaCommon.HasLinked(a) THEN RETURN END;
  se := a.subEntity;
  IF se # NIL THEN t := OvaCommon.SubEntityTitle(se)
  ELSE t := OvaCommon.NameDetail(a.name, a.hasDetail, a.detail)
  END;
  p := OvaCommon.Bold(Ropes.AppendChar(t, "."));
  IF (a.subAbilities.n > 0) OR (a.subWeaknesses.n > 0) THEN
    Add(p, Sentence(Ropes.Cat(Str("Grants: "),
      OvaCommon.Semi(OvaCommon.JoinFragmentSubItems(a.subAbilities),
        OvaCommon.JoinFragmentSubItems(a.subWeaknesses), a.subAbilities.n > 0, a.subWeaknesses.n > 0))))
  END;
  IF a.spells.n > 0 THEN
    Add(p, Sentence(Ropes.Cat(Str("Spells: "), OvaCommon.JoinSpells(a.spells))))
  END;
  IF se # NIL THEN
    Add(p, Traits(se.abilities, se.weaknesses, FALSE));
    AddCombat(p, se.combat, FALSE)
  END;
  Paragraph(p)
END Linked;

(* The entity's paragraph, led by "**Name** (Secondary)." or, with no
   NPC type, "**Name.**", then its linked content's. *)
PROCEDURE ProcessEntity*(e: OvaEntities.Entity; entityNo: INTEGER);
  VAR p, r: Rope; i: INTEGER; group: BOOLEAN;
BEGIN
  group := e.count > 1;
  IF e.isFragment & e.hasBackground THEN
    p := NIL; AddProse(p, e.background);
    IF e.hasNpcType & group THEN
      r := Ropes.Cat(OvaCommon.NpcTypeText(e), Str(" NPCs "));
      Add(p, Ropes.AppendChar(Ropes.Cat(r, Parenthesized(CountText(e.count))), "."))
    ELSIF e.hasNpcType THEN Add(p, Ropes.Cat(OvaCommon.NpcTypeText(e), Str(" NPC.")))
    ELSIF group THEN Add(p, Ropes.AppendChar(Parenthesized(CountText(e.count)), "."))
    END
  ELSE
    IF group THEN
      r := CountText(e.count);
      IF e.hasNpcType THEN r := Ropes.AppendChar(r, " "); r := Ropes.Cat(r, NpcTypePlural(e)) END;
      p := OvaCommon.Bold(e.name); OvaText.Add(p, " ");
      p := Ropes.AppendChar(Ropes.Cat(p, Parenthesized(r)), ".")
    ELSIF e.hasNpcType THEN
      p := OvaCommon.Bold(e.name); OvaText.Add(p, " (");
      p := Ropes.Cat(p, OvaCommon.NpcTypeText(e)); OvaText.Add(p, ").")
    ELSE p := OvaCommon.Bold(Ropes.AppendChar(e.name, "."))
    END;
    IF e.hasSummary THEN AddProse(p, e.summary) END;
    IF e.hasBackground THEN AddProse(p, e.background) END;
    IF e.hasAppearance THEN AddProse(p, e.appearance) END;
    IF e.hasPersonality THEN AddProse(p, e.personality) END
  END;
  Add(p, Traits(e.abilities, e.weaknesses, TRUE));
  AddCombat(p, e.combat, group);
  Paragraph(p);
  FOR i := 0 TO e.abilities.n - 1 DO Linked(e.abilities.items[i](OvaEntities.Ability)) END
END ProcessEntity;

END OvaInline.
