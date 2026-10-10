MODULE OvaEntities; (* An OVA entity, read once from its YAML *)

(* The Ada Ova_Fmt.Entities: each entity (a character, or an NPC
   Fragment) is decoded from its YAML mapping once, by Load, into plain
   records that every output format reads.  The Ada package's comments
   describe the schema and the reasons for its shape; the short notes
   here say only what differs in Oberon.

   An Ability can carry linked content: a Transformation's granted
   sub-abilities and sub-weaknesses, a Magic ability's spells, or a
   Companion's or Vehicle's whole sub-entity.  That nesting is one
   level deep, so a SubEntity holds SubItems, never Abilities.

   Errors come in two kinds, as in the Ada version:

   - A required field that is missing or malformed is recorded in
     errors (the Ada Load_Error list), with a placeholder in its place,
     and loading goes on, so that every such problem in a file is
     reported together.  Each has a path, and an approximate location:
     that of its mapping's own "name" scalar, when there is one.
   - Anything else (an optional field that is malformed, YAML of the
     wrong shape) ends loading: Load returns FALSE with a message, and
     the caller abandons the file, as the Ada version does when an
     exception reaches its Process_One.  YAML of the wrong shape (a
     list that isn't a sequence, an item that isn't a mapping) is
     "PATH: not a sequence" or "PATH: not a mapping", the Ada
     Shape_Error's words.

   Every string is a rope.  The empty rope is NIL, so a field that may
   be absent has a flag saying whether it was there, as in the Ada
   records. *)

IMPORT Fyaml, OvaText, Ropes;

CONST
  (* The fluff: fields, in the order every format writes them (the Ada
     Fluff_Block's field order); index fluff and hasFluffField with
     these. *)
  Concept* = 0; Birthday* = 1; Age* = 2; Gender* = 3; Height* = 4; Weight* = 5;
  Hair* = 6; Eyes* = 7; Association* = 8; Hobbies* = 9; FavoriteFood* = 10;
  Allies* = 11; Enemies* = 12; LoveInterests* = 13;
  NFluff* = 14;

  (* The numbers an overrides: list can name (the Ada Override_Key), the
     elements of an overrides set; see LoadOverrides. *)
  OvRoll* = 0; OvDx* = 1; OvEndurance* = 2; OvDefense* = 3; OvBarrier* = 4;
  OvHealth* = 5; OvThreatValue* = 6;
  NOverrides = 7;

  (* An npc-type: (rulebook p. 133, "Using NPC Type"), an NPC's
     importance to the story: the Ada NPC_Kind.  Matched ignoring case;
     anything else is a recorded error.  See NpcTypeName. *)
  Heroic* = 0; Secondary* = 1; Extra* = 2;
  NNpcTypes = 3;

TYPE
  Rope = Ropes.Rope;

  (* The base of every kind of list item, so one list type serves them
     all.  A backend takes an item out with a type guard:
     e.abilities.items[i](Ability). *)
  Element* = POINTER TO ElementDesc;
  ElementDesc* = RECORD END;

  Elements = POINTER TO ARRAY OF Element;
  List* = RECORD
    items-: Elements;                     (* items[0 .. n-1] *)
    n-: INTEGER
  END;

  (* The items that are sorted: by name, then by detail (an absent
     detail sorts as ""), ignoring case. *)
  Named* = POINTER TO NamedDesc;
  NamedDesc* = RECORD (ElementDesc)
    name-: Rope;
    hasDetail-: BOOLEAN;
    detail-: Rope
  END;

  (* A Perk or a Flaw: a plain name, or a mapping with a detail, a
     repeat count (counts-as) and a chosen cost, each optional. *)
  PerkFlaw* = POINTER TO PerkFlawDesc;
  PerkFlawDesc* = RECORD (NamedDesc)
    hasCountsAs-: BOOLEAN; countsAs-: INTEGER;
    hasCost-: BOOLEAN; cost-: INTEGER
  END;

  Attack* = POINTER TO AttackDesc;
  AttackDesc* = RECORD (ElementDesc)
    name-: Rope;
    perks-, flaws-: List;                 (* of PerkFlaw, sorted *)
    hasAffinity-: BOOLEAN; affinity-: Rope;
    hasDescription-: BOOLEAN; description-: Rope;  (* trimmed *)
    roll-: INTEGER;
    dx-: Rope;                            (* text: "1/2" happens *)
    endurance-: INTEGER;
    telekinesis-, transformed-: BOOLEAN;  (* the generator's inputs, not printed *)
    overrides-: SET                       (* of OvRoll, OvDx, OvEndurance *)
  END;

  (* A combat: block.  hasCombat is FALSE when there is none (a
     Companion may have no combat stats). *)
  Combat* = RECORD
    hasCombat-: BOOLEAN;
    defense-: Rope;                       (* text: "4/5" happens *)
    health-, endurance-: INTEGER;
    hasThreatValue-: BOOLEAN; threatValue-: INTEGER;
    attacks-: List;                       (* of Attack, in document order *)
    hasNotes-: BOOLEAN; notes-: Rope;     (* the Combat Notes, trimmed *)
    transformed-: BOOLEAN;                (* the generator's input, not printed *)
    overrides-: SET                       (* of OvDefense .. OvThreatValue, OvEndurance *)
  END;

  (* A linked sub-ability or sub-weakness, or a Companion's or
     Vehicle's own ability or weakness. *)
  SubItem* = POINTER TO SubItemDesc;
  SubItemDesc* = RECORD (NamedDesc)
    level-: INTEGER;
    perks-, flaws-: List;                 (* of PerkFlaw, sorted *)
    hasEndurance-: BOOLEAN; endurance-: INTEGER;
    hasNote-: BOOLEAN; note-: Rope;
    hasThreatValueHalf-, threatValueHalf-: BOOLEAN;
    overrides-: SET                       (* of OvEndurance *)
  END;

  (* A Magic ability's spell. *)
  Spell* = POINTER TO SpellDesc;
  SpellDesc* = RECORD (ElementDesc)
    name-, ability-: Rope;
    level-: INTEGER;
    endurance-: Rope;                     (* text: "10+" happens *)
    overrides-: SET                       (* of OvEndurance *)
  END;

  (* A Companion or Vehicle, nested under the Ability that grants it.
     label is "Companion" or "Vehicle", for the headings. *)
  SubEntity* = POINTER TO SubEntityDesc;
  SubEntityDesc* = RECORD
    label-, name-: Rope;
    isFragment-: BOOLEAN;
    abilities-, weaknesses-: List;        (* of SubItem, sorted *)
    combat-: Combat
  END;

  (* A top-level Ability: a SubItem's fields, and its linked content.
     subEntity is NIL if it grants none. *)
  Ability* = POINTER TO AbilityDesc;
  AbilityDesc* = RECORD (SubItemDesc)
    subAbilities-, subWeaknesses-: List;  (* of SubItem, sorted *)
    spells-: List;                        (* of Spell, in document order *)
    subEntity-: SubEntity
  END;

  Weakness* = POINTER TO WeaknessDesc;
  WeaknessDesc* = RECORD (NamedDesc)
    level-: INTEGER
  END;

  Note* = POINTER TO NoteDesc;
  NoteDesc* = RECORD (ElementDesc)
    header-, text-: Rope                  (* text trimmed *)
  END;

  (* An options: block: the character-creation limiting rules. *)
  Options* = RECORD
    hasBaseZero-: BOOLEAN; baseZero-: INTEGER;
    hasPowerCeiling-: BOOLEAN; powerCeiling-: INTEGER;
    hasStartingLevels-: BOOLEAN; startingLevels-: INTEGER;
    scaledCost-, halfCostKnowledge-, combinedEffectiveness-: BOOLEAN
  END;

  Entity* = POINTER TO EntityDesc;
  EntityDesc* = RECORD
    name-: Rope;                          (* required *)
    hasPlayer-, hasPortrait-: BOOLEAN;
    player-, portrait-: Rope;             (* untrimmed, as in the Ada version *)
    hasTagline-, hasSummary-, hasBackground-, hasAppearance-, hasPersonality-,
    hasCharacterHooks-, hasOtherNotes-: BOOLEAN;
    tagline-, summary-, background-, appearance-, personality-,
    characterHooks-, otherNotes-: Rope;   (* trimmed *)
    hasNpcType-: BOOLEAN; npcType-: INTEGER;  (* Heroic, Secondary or Extra *)
    abilities-: List;                     (* of Ability, sorted *)
    weaknesses-: List;                    (* of Weakness, sorted *)
    combat-: Combat;
    notes-: List;                         (* of Note, in document order *)
    hasFluff-: BOOLEAN;
    hasFluffField-: ARRAY NFluff OF BOOLEAN;
    fluff-: ARRAY NFluff OF Rope;         (* untrimmed, as in the Ada version *)
    hasOptions-: BOOLEAN;
    options-: Options;
    isFragment-: BOOLEAN                  (* an NPC Fragment *)
  END;

  (* A required field that is missing or malformed. *)
  LoadError* = POINTER TO LoadErrorDesc;
  LoadErrorDesc* = RECORD (ElementDesc)
    message-, path-: Rope;
    hasLocation-: BOOLEAN;
    line-, column-: INTEGER               (* 1-based *)
  END;

  (* Reads one mapping item of a list; see LoadList. *)
  Loader = PROCEDURE (m: Fyaml.Node; VAR x: Element): BOOLEAN;

VAR
  (* Every LoadError recorded since ResetErrors, in the order found. *)
  errors-: List;

  (* The message for the Load in progress when a loader returns FALSE. *)
  fatal: Rope;

  fluffKeys: ARRAY NFluff, 16 OF CHAR;
  overrideKeys: ARRAY NOverrides, 16 OF CHAR;

(* ---- Lists ---- *)

PROCEDURE Clear(VAR l: List);
BEGIN l.items := NIL; l.n := 0
END Clear;

PROCEDURE Add(VAR l: List; x: Element);
  VAR t: Elements; i: INTEGER;
BEGIN
  IF l.items = NIL THEN NEW(l.items, 8)
  ELSIF l.n = LEN(l.items^) THEN
    NEW(t, 2 * l.n);
    FOR i := 0 TO l.n - 1 DO t[i] := l.items[i] END;
    l.items := t
  END;
  l.items[l.n] := x; INC(l.n)
END Add;

(* -1, 0 or 1 as a's name, then detail, folded as the Ada To_Lower
   folds them, comes before, with or after b's. *)
PROCEDURE CompareKeys(an, ad, bn, bd: Rope): INTEGER;
  VAR c: INTEGER;
BEGIN
  c := Ropes.Compare(an, bn);
  IF c = 0 THEN c := Ropes.Compare(ad, bd) END;
  RETURN c
END CompareKeys;

(* Sorts l, a list of Named, by name and then detail, ignoring case: the
   Ada Ability_CI_Less and friends.  An insertion sort: stable, and the
   lists are short.  Each item is folded once, into keys. *)
PROCEDURE SortByName(VAR l: List);
  VAR i, j: INTEGER; x: Element; kn, kd: Rope; names, details: OvaText.Items;
BEGIN
  IF l.n < 2 THEN RETURN END;
  NEW(names, l.n); NEW(details, l.n);
  FOR i := 0 TO l.n - 1 DO
    names[i] := OvaText.FoldCI(l.items[i](Named).name);
    details[i] := OvaText.FoldCI(l.items[i](Named).detail)
  END;
  FOR i := 1 TO l.n - 1 DO
    x := l.items[i]; kn := names[i]; kd := details[i]; j := i;
    WHILE (j > 0) & (CompareKeys(kn, kd, names[j - 1], details[j - 1]) < 0) DO
      l.items[j] := l.items[j - 1]; names[j] := names[j - 1]; details[j] := details[j - 1];
      DEC(j)
    END;
    l.items[j] := x; names[j] := kn; details[j] := kd
  END
END SortByName;

(* ---- Errors ---- *)

(* Forgets every recorded error.  Call before each file: errors collect
   across every Load otherwise. *)
PROCEDURE ResetErrors*;
BEGIN Clear(errors)
END ResetErrors;

(* The text of a polibfyaml error without its "FILE:LINE:COLUMN: error: "
   and "PATH: " prefixes or its final line feed: just what the Ada
   binding's exception message says, as in 'not a valid integer: "x"'. *)
PROCEDURE ErrorText(err: Fyaml.Error): Rope;
  VAR r, p: Rope; i: LONGINT;
BEGIN
  r := Ropes.FromString(err.msg^);
  i := Ropes.Find(r, ": error: ", 0);
  IF i >= 0 THEN r := Ropes.Substring(r, i + 9, Ropes.Length(r) - i - 9) END;
  IF err.path # NIL THEN
    p := Ropes.FromString(err.path^); OvaText.Add(p, ": ");
    IF (Ropes.Length(r) >= Ropes.Length(p)) & Ropes.Equal(Ropes.Substring(r, 0, Ropes.Length(p)), p) THEN
      r := Ropes.Substring(r, Ropes.Length(p), Ropes.Length(r) - Ropes.Length(p))
    END
  END;
  i := Ropes.Length(r);
  IF (i > 0) & (Ropes.Fetch(r, i - 1) = 0AX) THEN r := Ropes.Substring(r, 0, i - 1) END;
  RETURN r
END ErrorText;

(* n's path, in polibfyaml's ByPath syntax ("/1/abilities/2"). *)
PROCEDURE PathOf(n: Fyaml.Node): Rope;
  VAR p: Fyaml.String;
BEGIN p := n.Path(); RETURN Ropes.FromString(p^)
END PathOf;

(* Records an error for key in mapping m: the Ada Record_Error.  The
   location is that of m's own "name" scalar, if it has one: the
   missing key itself has no position to report (the Ada
   Approximate_Location). *)
PROCEDURE Record(m: Fyaml.Node; key: ARRAY OF CHAR; message: Rope);
  VAR e: LoadError; name: Fyaml.Node;
BEGIN
  NEW(e);
  e.message := message;
  e.path := PathOf(m); e.path := Ropes.AppendChar(e.path, "/"); OvaText.Add(e.path, key);
  name := m.Value("name");
  e.hasLocation := (name # NIL) & name.IsScalar() & name.Location(e.line, e.column);
  Add(errors, e)
END Record;

(* The Ada binding's message for a key whose value isn't a scalar. *)
PROCEDURE NotScalar(key: ARRAY OF CHAR): Rope;
  VAR r: Rope;
BEGIN
  r := Ropes.FromString('key "'); OvaText.Add(r, key); OvaText.Add(r, '" is not a scalar value');
  RETURN r
END NotScalar;

(* Fails the Load in progress with message "PATH: text". *)
PROCEDURE FailAt(n: Fyaml.Node; text: ARRAY OF CHAR): BOOLEAN;
BEGIN
  fatal := PathOf(n); OvaText.Add(fatal, ": "); OvaText.Add(fatal, text);
  RETURN FALSE
END FailAt;

(* ---- Fields ---- *)

(* The text of the scalar for key, which is required: the Ada
   Require_String.  Records an error, and gives NIL, if it is missing
   or isn't a scalar. *)
PROCEDURE RequireString(m: Fyaml.Node; key: ARRAY OF CHAR; VAR s: Rope);
  VAR v: Fyaml.Node; t: Fyaml.String; msg: Rope;
BEGIN
  s := NIL;
  v := m.Value(key);
  IF v = NIL THEN
    msg := Ropes.FromString('missing required key "'); OvaText.Add(msg, key); OvaText.Add(msg, '"');
    Record(m, key, msg)
  ELSIF ~v.IsScalar() THEN Record(m, key, NotScalar(key))
  ELSE t := v.Scalar(); s := Ropes.FromString(t^)
  END
END RequireString;

(* The integer for key, which is required: the Ada Require_Integer.
   Records an error, and gives 0, if it is missing or malformed. *)
PROCEDURE RequireInteger(m: Fyaml.Node; key: ARRAY OF CHAR; VAR i: INTEGER);
  VAR v: Fyaml.Node; err: Fyaml.Error; msg: Rope;
BEGIN
  i := 0;
  v := m.Value(key);
  IF v = NIL THEN
    msg := Ropes.FromString('missing required key "'); OvaText.Add(msg, key); OvaText.Add(msg, '"');
    Record(m, key, msg)
  ELSIF ~v.IsScalar() THEN Record(m, key, NotScalar(key))
  ELSIF ~v.IntegerValue(i, err) THEN i := 0; Record(m, key, ErrorText(err))
  END
END RequireInteger;

(* The text of the scalar for key, if there is such a key, which has
   says: the Ada Has_Key then String_Value.  A value that isn't a
   scalar fails the Load. *)
PROCEDURE OptString(m: Fyaml.Node; key: ARRAY OF CHAR; VAR has: BOOLEAN; VAR s: Rope): BOOLEAN;
  VAR v: Fyaml.Node; t: Fyaml.String;
BEGIN
  s := NIL;
  v := m.Value(key); has := v # NIL;
  IF has THEN
    IF ~v.IsScalar() THEN fatal := NotScalar(key); RETURN FALSE END;
    t := v.Scalar(); s := Ropes.FromString(t^)
  END;
  RETURN TRUE
END OptString;

(* The integer for key, if there is such a key, which has says.  A
   malformed one fails the Load. *)
PROCEDURE OptInteger(m: Fyaml.Node; key: ARRAY OF CHAR; VAR has: BOOLEAN; VAR i: INTEGER): BOOLEAN;
  VAR v: Fyaml.Node; err: Fyaml.Error;
BEGIN
  i := 0;
  v := m.Value(key); has := v # NIL;
  IF has THEN
    IF ~v.IsScalar() THEN fatal := NotScalar(key); RETURN FALSE END;
    IF ~v.IntegerValue(i, err) THEN fatal := ErrorText(err); RETURN FALSE END
  END;
  RETURN TRUE
END OptInteger;

(* The boolean for key, if there is such a key; b is unchanged if there
   isn't.  A malformed one fails the Load. *)
PROCEDURE OptBoolean(m: Fyaml.Node; key: ARRAY OF CHAR; VAR b: BOOLEAN): BOOLEAN;
  VAR v: Fyaml.Node; err: Fyaml.Error;
BEGIN
  v := m.Value(key);
  IF v # NIL THEN
    IF ~v.IsScalar() THEN fatal := NotScalar(key); RETURN FALSE END;
    IF ~v.BooleanValue(b, err) THEN fatal := ErrorText(err); RETURN FALSE END
  END;
  RETURN TRUE
END OptBoolean;

(* The sequence for key, or NIL if there's no such key; anything else
   there fails the Load. *)
PROCEDURE Sequence(m: Fyaml.Node; key: ARRAY OF CHAR; VAR s: Fyaml.Node): BOOLEAN;
BEGIN
  s := m.Value(key);
  RETURN (s = NIL) OR s.IsSequence() OR FailAt(s, "not a sequence")
END Sequence;

(* The mapping for key, or NIL if there's no such key; anything else
   there fails the Load. *)
PROCEDURE Mapping(m: Fyaml.Node; key: ARRAY OF CHAR; VAR s: Fyaml.Node): BOOLEAN;
BEGIN
  s := m.Value(key);
  RETURN (s = NIL) OR s.IsMapping() OR FailAt(s, "not a mapping")
END Mapping;

(* The items of the sequence for key (none if absent), each a mapping
   read by load, into l. *)
PROCEDURE LoadList(m: Fyaml.Node; key: ARRAY OF CHAR; load: Loader; VAR l: List): BOOLEAN;
  VAR seq, item: Fyaml.Node; it: Fyaml.ItemIter; x: Element;
BEGIN
  Clear(l);
  IF ~Sequence(m, key, seq) THEN RETURN FALSE END;
  IF seq # NIL THEN
    seq.Items(it);
    WHILE it.Next(item) DO
      IF ~item.IsMapping() THEN RETURN FailAt(item, "not a mapping") END;
      IF ~load(item, x) THEN RETURN FALSE END;
      Add(l, x)
    END
  END;
  RETURN TRUE
END LoadList;

(* ---- overrides: ---- *)

(* The Ada Key_Name: k's YAML spelling ("threat-value"). *)
PROCEDURE KeyName*(k: INTEGER; VAR name: ARRAY OF CHAR);
BEGIN COPY(overrideKeys[k], name)
END KeyName;

(* m's overrides: list, if any, into o: the Ada Load_Overrides.  A list
   that isn't a sequence, or an item that isn't one of the allowed key
   names, is a recorded error, like a missing required key. *)
PROCEDURE LoadOverrides(m: Fyaml.Node; allowed: SET; VAR o: SET);
  VAR seq, item: Fyaml.Node; it: Fyaml.ItemIter; t: Fyaml.String; k: INTEGER;
    found, first: BOOLEAN; msg: Rope;
BEGIN
  o := {};
  seq := m.Value("overrides");
  IF seq = NIL THEN (* none *)
  ELSIF ~seq.IsSequence() THEN Record(m, "overrides", Ropes.FromString("not a sequence of key names"))
  ELSE
    seq.Items(it);
    WHILE it.Next(item) DO
      IF item.IsScalar() THEN
        t := item.Scalar(); found := FALSE;
        FOR k := 0 TO NOverrides - 1 DO
          IF ~found & (k IN allowed) & (t^ = overrideKeys[k]) THEN INCL(o, k); found := TRUE END
        END;
        IF ~found THEN
          msg := Ropes.FromString('"'); OvaText.Add(msg, t^); OvaText.Add(msg, '" is not one of ');
          first := TRUE;
          FOR k := 0 TO NOverrides - 1 DO
            IF k IN allowed THEN
              IF ~first THEN OvaText.Add(msg, ", ") END;
              OvaText.Add(msg, overrideKeys[k]); first := FALSE
            END
          END;
          Record(m, "overrides", msg)
        END
      ELSE Record(m, "overrides", Ropes.FromString("an item is not a key name"))
      END
    END
  END
END LoadOverrides;

(* The rulebook's capitalization of npc-type k ("Heroic"). *)
PROCEDURE NpcTypeName*(k: INTEGER): Rope;
BEGIN
  CASE k OF
    Heroic: RETURN Ropes.FromString("Heroic")
  | Secondary: RETURN Ropes.FromString("Secondary")
  | Extra: RETURN Ropes.FromString("Extra")
  END
END NpcTypeName;

(* m's npc-type:, if any: the Ada Load_NPC_Type.  Anything but one of
   the three names is a recorded error, like an overrides: name:
   silently dropping it would lose the type from the output.  A value
   that isn't a scalar fails the Load, as any optional string's does. *)
PROCEDURE LoadNpcType(m: Fyaml.Node; VAR has: BOOLEAN; VAR k: INTEGER): BOOLEAN;
  VAR there: BOOLEAN; raw, msg: Rope; i: INTEGER;
BEGIN
  has := FALSE; k := Heroic;
  IF ~OptString(m, "npc-type", there, raw) THEN RETURN FALSE END;
  IF there THEN
    FOR i := 0 TO NNpcTypes - 1 DO
      IF ~has & Ropes.Equal(OvaText.FoldCI(OvaText.Trim(raw)), OvaText.FoldCI(NpcTypeName(i))) THEN
        has := TRUE; k := i
      END
    END;
    IF ~has THEN
      msg := Ropes.Cat(Ropes.FromString('"'), raw);
      OvaText.Add(msg, '" is not one of Heroic, Secondary, Extra');
      Record(m, "npc-type", msg)
    END
  END;
  RETURN TRUE
END LoadNpcType;

(* ---- Perks and Flaws ---- *)

(* A Perk or Flaw: a scalar (just the name) or a mapping. *)
PROCEDURE LoadPerkFlaw(n: Fyaml.Node; VAR pf: PerkFlaw): BOOLEAN;
  VAR t: Fyaml.String;
BEGIN
  NEW(pf);
  IF n.IsScalar() THEN
    t := n.Scalar(); pf.name := Ropes.FromString(t^);
    RETURN TRUE
  ELSIF n.IsMapping() THEN
    RequireString(n, "name", pf.name);
    RETURN OptString(n, "detail", pf.hasDetail, pf.detail)
      & OptInteger(n, "counts-as", pf.hasCountsAs, pf.countsAs)
      & OptInteger(n, "cost", pf.hasCost, pf.cost)
  END;
  (* The Ada version's own message, which has no path. *)
  fatal := Ropes.FromString("unrecognized Perk/Flaw shape");
  RETURN FALSE
END LoadPerkFlaw;

(* The Perks or Flaws for key (none if absent), sorted, into l. *)
PROCEDURE LoadPerkFlaws(m: Fyaml.Node; key: ARRAY OF CHAR; VAR l: List): BOOLEAN;
  VAR seq, item: Fyaml.Node; it: Fyaml.ItemIter; pf: PerkFlaw;
BEGIN
  Clear(l);
  IF ~Sequence(m, key, seq) THEN RETURN FALSE END;
  IF seq # NIL THEN
    seq.Items(it);
    WHILE it.Next(item) DO
      IF ~LoadPerkFlaw(item, pf) THEN RETURN FALSE END;
      Add(l, pf)
    END;
    SortByName(l)
  END;
  RETURN TRUE
END LoadPerkFlaws;

(* ---- Attacks and combat: blocks ---- *)

PROCEDURE LoadAttack(m: Fyaml.Node; VAR x: Element): BOOLEAN;
  VAR a: Attack;
BEGIN
  NEW(a); x := a;
  RequireString(m, "name", a.name);
  IF ~LoadPerkFlaws(m, "perks", a.perks) OR ~LoadPerkFlaws(m, "flaws", a.flaws)
     OR ~OptString(m, "affinity", a.hasAffinity, a.affinity)
     OR ~OptString(m, "description", a.hasDescription, a.description) THEN
    RETURN FALSE
  END;
  a.description := OvaText.Trim(a.description);
  RequireInteger(m, "roll", a.roll);
  RequireString(m, "dx", a.dx);
  RequireInteger(m, "endurance", a.endurance);
  a.telekinesis := FALSE; a.transformed := FALSE;
  IF ~OptBoolean(m, "telekinesis", a.telekinesis) OR ~OptBoolean(m, "transformed", a.transformed) THEN
    RETURN FALSE
  END;
  LoadOverrides(m, {OvRoll, OvDx, OvEndurance}, a.overrides);
  RETURN TRUE
END LoadAttack;

(* The combat: block m into c.  m has no "name" of its own, so these
   errors have a path but no location, as in the Ada version. *)
PROCEDURE LoadCombat(m: Fyaml.Node; VAR c: Combat): BOOLEAN;
BEGIN
  c.hasCombat := TRUE;
  RequireString(m, "defense", c.defense);
  RequireInteger(m, "health", c.health);
  RequireInteger(m, "endurance", c.endurance);
  IF ~OptInteger(m, "threat-value", c.hasThreatValue, c.threatValue)
     OR ~LoadList(m, "attacks", LoadAttack, c.attacks)
     OR ~OptString(m, "notes", c.hasNotes, c.notes)
     OR ~OptBoolean(m, "transformed", c.transformed) THEN
    RETURN FALSE
  END;
  c.notes := OvaText.Trim(c.notes);
  LoadOverrides(m, {OvEndurance .. OvThreatValue}, c.overrides);
  RETURN TRUE
END LoadCombat;

(* The combat: block for key, if there is one, into c. *)
PROCEDURE OptCombat(m: Fyaml.Node; VAR c: Combat): BOOLEAN;
  VAR n: Fyaml.Node;
BEGIN
  c.hasCombat := FALSE; c.defense := NIL; c.health := 0; c.endurance := 0;
  c.hasThreatValue := FALSE; c.threatValue := 0; Clear(c.attacks);
  c.hasNotes := FALSE; c.notes := NIL; c.transformed := FALSE; c.overrides := {};
  RETURN Mapping(m, "combat", n) & ((n = NIL) OR LoadCombat(n, c))
END OptCombat;

(* ---- Sub-items, spells, sub-entities ---- *)

(* The fields an Ability and a SubItem share, from m into s. *)
PROCEDURE LoadSubItemFields(m: Fyaml.Node; s: SubItem): BOOLEAN;
BEGIN
  RequireString(m, "name", s.name);
  RequireInteger(m, "level", s.level);
  s.threatValueHalf := FALSE;
  IF ~OptString(m, "detail", s.hasDetail, s.detail)
     OR ~LoadPerkFlaws(m, "perks", s.perks) OR ~LoadPerkFlaws(m, "flaws", s.flaws)
     OR ~OptInteger(m, "endurance", s.hasEndurance, s.endurance)
     OR ~OptString(m, "note", s.hasNote, s.note) THEN
    RETURN FALSE
  END;
  s.hasThreatValueHalf := m.Value("threat-value-half") # NIL;
  IF ~OptBoolean(m, "threat-value-half", s.threatValueHalf) THEN RETURN FALSE END;
  LoadOverrides(m, {OvEndurance}, s.overrides);
  RETURN TRUE
END LoadSubItemFields;

PROCEDURE LoadSubItem(m: Fyaml.Node; VAR x: Element): BOOLEAN;
  VAR s: SubItem;
BEGIN NEW(s); x := s; RETURN LoadSubItemFields(m, s)
END LoadSubItem;

(* The SubItems for key (none if absent), sorted, into l. *)
PROCEDURE LoadSubItems(m: Fyaml.Node; key: ARRAY OF CHAR; VAR l: List): BOOLEAN;
BEGIN
  IF ~LoadList(m, key, LoadSubItem, l) THEN RETURN FALSE END;
  SortByName(l);
  RETURN TRUE
END LoadSubItems;

PROCEDURE LoadSpell(m: Fyaml.Node; VAR x: Element): BOOLEAN;
  VAR s: Spell;
BEGIN
  NEW(s); x := s;
  RequireString(m, "name", s.name);
  RequireString(m, "ability", s.ability);
  RequireInteger(m, "level", s.level);
  RequireString(m, "endurance", s.endurance);
  LoadOverrides(m, {OvEndurance}, s.overrides);
  RETURN TRUE
END LoadSpell;

PROCEDURE LoadSubEntity(m: Fyaml.Node; label: ARRAY OF CHAR; VAR se: SubEntity): BOOLEAN;
BEGIN
  NEW(se);
  se.label := Ropes.FromString(label);
  RequireString(m, "name", se.name);
  se.isFragment := FALSE;
  RETURN OptBoolean(m, "fragment", se.isFragment)
    & LoadSubItems(m, "abilities", se.abilities)
    & LoadSubItems(m, "weaknesses", se.weaknesses)
    & OptCombat(m, se.combat)
END LoadSubEntity;

(* ---- Abilities, weaknesses, notes ---- *)

PROCEDURE LoadAbility(m: Fyaml.Node; VAR x: Element): BOOLEAN;
  VAR a: Ability; n: Fyaml.Node;
BEGIN
  NEW(a); x := a;
  IF ~LoadSubItemFields(m, a)
     OR ~LoadSubItems(m, "abilities", a.subAbilities)
     OR ~LoadSubItems(m, "weaknesses", a.subWeaknesses)
     OR ~LoadList(m, "spells", LoadSpell, a.spells) THEN
    RETURN FALSE
  END;
  a.subEntity := NIL;
  IF ~Mapping(m, "companion", n) THEN RETURN FALSE END;
  IF n # NIL THEN RETURN LoadSubEntity(n, "Companion", a.subEntity) END;
  IF ~Mapping(m, "vehicle", n) THEN RETURN FALSE END;
  IF n # NIL THEN RETURN LoadSubEntity(n, "Vehicle", a.subEntity) END;
  RETURN TRUE
END LoadAbility;

PROCEDURE LoadWeakness(m: Fyaml.Node; VAR x: Element): BOOLEAN;
  VAR w: Weakness;
BEGIN
  NEW(w); x := w;
  RequireString(m, "name", w.name);
  RequireInteger(m, "level", w.level);
  RETURN OptString(m, "detail", w.hasDetail, w.detail)
END LoadWeakness;

(* A note has no "name" of its own, so its errors have a path but no
   location. *)
PROCEDURE LoadNote(m: Fyaml.Node; VAR x: Element): BOOLEAN;
  VAR n: Note;
BEGIN
  NEW(n); x := n;
  RequireString(m, "header", n.header);
  RequireString(m, "text", n.text);
  n.text := OvaText.Trim(n.text);
  RETURN TRUE
END LoadNote;

(* ---- fluff: and options: ---- *)

PROCEDURE LoadFluff(m: Fyaml.Node; e: Entity): BOOLEAN;
  VAR i: INTEGER;
BEGIN
  FOR i := 0 TO NFluff - 1 DO
    IF ~OptString(m, fluffKeys[i], e.hasFluffField[i], e.fluff[i]) THEN RETURN FALSE END
  END;
  RETURN TRUE
END LoadFluff;

PROCEDURE LoadOptions(m: Fyaml.Node; VAR o: Options): BOOLEAN;
BEGIN
  o.scaledCost := FALSE; o.halfCostKnowledge := FALSE; o.combinedEffectiveness := FALSE;
  RETURN OptInteger(m, "base-zero", o.hasBaseZero, o.baseZero)
    & OptInteger(m, "power-ceiling", o.hasPowerCeiling, o.powerCeiling)
    & OptInteger(m, "starting-levels", o.hasStartingLevels, o.startingLevels)
    & OptBoolean(m, "scaled-cost", o.scaledCost)
    & OptBoolean(m, "half-cost-knowledge", o.halfCostKnowledge)
    & OptBoolean(m, "combined-effectiveness", o.combinedEffectiveness)
END LoadOptions;

(* ---- Entities ---- *)

(* Trims a prose field, as the Ada Load_Entity does. *)
PROCEDURE Prose(m: Fyaml.Node; key: ARRAY OF CHAR; VAR has: BOOLEAN; VAR s: Rope): BOOLEAN;
BEGIN
  IF ~OptString(m, key, has, s) THEN RETURN FALSE END;
  s := OvaText.Trim(s);
  RETURN TRUE
END Prose;

PROCEDURE LoadEntity(m: Fyaml.Node; e: Entity): BOOLEAN;
  VAR n: Fyaml.Node;
BEGIN
  RequireString(m, "name", e.name);
  e.isFragment := FALSE;
  IF ~OptBoolean(m, "fragment", e.isFragment)
     OR ~OptString(m, "player", e.hasPlayer, e.player)
     OR ~Prose(m, "tagline", e.hasTagline, e.tagline)
     OR ~Prose(m, "summary", e.hasSummary, e.summary)
     OR ~Prose(m, "background", e.hasBackground, e.background)
     OR ~Prose(m, "appearance", e.hasAppearance, e.appearance)
     OR ~Prose(m, "personality", e.hasPersonality, e.personality)
     OR ~Prose(m, "character-hooks", e.hasCharacterHooks, e.characterHooks)
     OR ~LoadNpcType(m, e.hasNpcType, e.npcType)
     OR ~Prose(m, "other-notes", e.hasOtherNotes, e.otherNotes)
     OR ~OptString(m, "portrait", e.hasPortrait, e.portrait)
     OR ~LoadList(m, "abilities", LoadAbility, e.abilities) THEN
    RETURN FALSE
  END;
  SortByName(e.abilities);
  IF ~LoadList(m, "weaknesses", LoadWeakness, e.weaknesses) THEN RETURN FALSE END;
  SortByName(e.weaknesses);
  IF ~OptCombat(m, e.combat) OR ~LoadList(m, "notes", LoadNote, e.notes)
     OR ~Mapping(m, "fluff", n) THEN
    RETURN FALSE
  END;
  e.hasFluff := n # NIL;
  IF e.hasFluff & ~LoadFluff(n, e) THEN RETURN FALSE END;
  IF ~Mapping(m, "options", n) THEN RETURN FALSE END;
  e.hasOptions := n # NIL;
  RETURN ~e.hasOptions OR LoadOptions(n, e.options)
END LoadEntity;

(* Reads entity e from m, an item of a document's top-level sequence.
   A required field that is missing or malformed is added to errors,
   and loading goes on: check errors.n once the whole file is loaded.
   Anything else wrong returns FALSE with msg set (never empty) and e
   NIL; the caller abandons the file. *)
PROCEDURE Load*(m: Fyaml.Node; VAR e: Entity; VAR msg: Rope): BOOLEAN;
  VAR ok: BOOLEAN;
BEGIN
  fatal := NIL; msg := NIL;
  NEW(e);
  IF m.IsMapping() THEN ok := LoadEntity(m, e) ELSE ok := FailAt(m, "not a mapping") END;
  IF ~ok THEN msg := fatal; e := NIL END;
  RETURN ok
END Load;

BEGIN
  Clear(errors); fatal := NIL;
  fluffKeys[Concept] := "concept"; fluffKeys[Birthday] := "birthday";
  fluffKeys[Age] := "age"; fluffKeys[Gender] := "gender";
  fluffKeys[Height] := "height"; fluffKeys[Weight] := "weight";
  fluffKeys[Hair] := "hair"; fluffKeys[Eyes] := "eyes";
  fluffKeys[Association] := "association"; fluffKeys[Hobbies] := "hobbies";
  fluffKeys[FavoriteFood] := "favorite-food"; fluffKeys[Allies] := "allies";
  fluffKeys[Enemies] := "enemies"; fluffKeys[LoveInterests] := "love-interests";
  overrideKeys[OvRoll] := "roll"; overrideKeys[OvDx] := "dx";
  overrideKeys[OvEndurance] := "endurance"; overrideKeys[OvDefense] := "defense";
  overrideKeys[OvBarrier] := "barrier"; overrideKeys[OvHealth] := "health";
  overrideKeys[OvThreatValue] := "threat-value"
END OvaEntities.
