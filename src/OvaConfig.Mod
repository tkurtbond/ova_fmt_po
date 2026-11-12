MODULE OvaConfig; (* Settings from the command line *)

(* The Ada Ova_Fmt.Config.  OvaCli sets these from the command line and
   the output modules read them.  They are exported read-write because
   Oberon can't say "writable only by OvaCli"; only OvaCli, and tests,
   should change them.  The Ada Config's comments explain each setting;
   the short notes here say which option sets it. *)

IMPORT Ropes;

CONST
  (* Output formats (the Ada Output_Format).  Terse (reST prose) is the
     default; -g, -M, -H, -G, -m, -i and -X choose the others, and the last
     one given wins. *)
  Terse* = 0; Gemtext* = 1; Markdown* = 2; HtmlInRst* = 3; GroffInRst* = 4; Hmm* = 5; Inline* = 6;
  Form* = 7;

VAR
  format*: INTEGER;

  hmmDepth*: INTEGER;           (* -L/--hmm-depth, >= 0 *)
  hmmCompactLists*: BOOLEAN;    (* -c/--hmm-compact-lists *)
  hmmPlain*: BOOLEAN;           (* -p/--hmm-plain *)
  gemtextEmphasis*: BOOLEAN;    (* -e/--gemtext-emphasis *)

  (* The empty rope is NIL, so whether -o was given at all is a flag of
     its own. *)
  outputFile*: Ropes.Rope;      (* -o/--output *)
  hasOutputFile*: BOOLEAN;      (* off: standard output *)

  underliner*: CHAR;            (* -u/--underliner *)
  subunderliner*: CHAR;         (* -U/--subunderliner; 0X = not given *)

  (* On: negative numbers the program writes itself get U+2212 MINUS
     SIGN; -n/--no-unicode-minus clears it, for ASCII "-". *)
  unicodeMinus*: BOOLEAN;

  showOptions*: BOOLEAN;        (* -O/--options *)

BEGIN
  format := Terse;
  hmmDepth := 0; hmmCompactLists := FALSE; hmmPlain := FALSE;
  gemtextEmphasis := FALSE;
  outputFile := NIL; hasOutputFile := FALSE;
  underliner := "="; subunderliner := 0X;
  unicodeMinus := TRUE;
  showOptions := FALSE
END OvaConfig.
