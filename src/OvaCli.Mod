MODULE OvaCli; (* The command line: options into OvaConfig, file names into files *)

(* The Ada Ova_Fmt.Cli, on ArgParser instead of Ada arg_parser.  The
   options are added in the Ada order, with its descriptions, so the
   usage lists them the same way (its layout, and the wording of its
   errors, are ArgParser's).

   ArgParser has no options that just set a variable (the Ada
   Make_Set_Boolean_True_Option and friends), so each option has its own
   handler.  Oberon has no closures, so the handlers are module-level
   procedures setting OvaConfig's variables. *)

IMPORT ArgParser, Err, OvaConfig, OvaText, Out, Platform, Ropes, Strings;

VAR
  (* The file names on the command line, in order.  None means standard
     input. *)
  files-: OvaText.List;

  (* -h/--help was given: the usage has been written, and parsing
     stopped there. *)
  helpShown-: BOOLEAN;

  parser: ArgParser.Parser;

(* -u/--underliner and -U/--subunderliner take one character.  Anything
   else is a command-line mistake, status 2, in the Ada version's
   words (its Arg_Parser's prefix, then its own message). *)
PROCEDURE OneChar(VAR arg: ARRAY OF CHAR; names: ARRAY OF CHAR; VAR c: CHAR);
BEGIN
  IF Strings.Length(arg) # 1 THEN
    Out.Flush;
    Err.String("Invalid value for option "); Err.String(names);
    Err.String(': takes exactly one character, got "'); Err.String(arg); Err.String('"'); Err.Ln;
    Platform.Exit(ArgParser.UsageErrorStatus)
  END;
  c := arg[0]
END OneChar;

(* ---- Handlers, in option order ---- *)

PROCEDURE DoHelp(): BOOLEAN;
BEGIN parser.Usage; helpShown := TRUE; RETURN FALSE
END DoHelp;

PROCEDURE DoGemtext(): BOOLEAN;
BEGIN OvaConfig.format := OvaConfig.Gemtext; RETURN TRUE
END DoGemtext;

PROCEDURE DoMarkdown(): BOOLEAN;
BEGIN OvaConfig.format := OvaConfig.Markdown; RETURN TRUE
END DoMarkdown;

PROCEDURE DoInline(): BOOLEAN;
BEGIN OvaConfig.format := OvaConfig.Inline; RETURN TRUE
END DoInline;

(* -X writes numbers for a PDF form, which wants ASCII. *)
PROCEDURE DoForm(): BOOLEAN;
BEGIN OvaConfig.format := OvaConfig.Form; OvaConfig.unicodeMinus := FALSE; RETURN TRUE
END DoForm;

PROCEDURE DoHtml(): BOOLEAN;
BEGIN OvaConfig.format := OvaConfig.HtmlInRst; RETURN TRUE
END DoHtml;

PROCEDURE DoGroff(): BOOLEAN;
BEGIN OvaConfig.format := OvaConfig.GroffInRst; RETURN TRUE
END DoGroff;

PROCEDURE DoGemtextEmphasis(): BOOLEAN;
BEGIN OvaConfig.gemtextEmphasis := TRUE; RETURN TRUE
END DoGemtextEmphasis;

PROCEDURE DoOutput(VAR arg: ARRAY OF CHAR): BOOLEAN;
BEGIN
  OvaConfig.outputFile := Ropes.FromString(arg); OvaConfig.hasOutputFile := TRUE;
  RETURN TRUE
END DoOutput;

PROCEDURE DoSubunderliner(VAR arg: ARRAY OF CHAR): BOOLEAN;
BEGIN OneChar(arg, "-U/--subunderliner", OvaConfig.subunderliner); RETURN TRUE
END DoSubunderliner;

PROCEDURE DoUnderliner(VAR arg: ARRAY OF CHAR): BOOLEAN;
BEGIN OneChar(arg, "-u/--underliner", OvaConfig.underliner); RETURN TRUE
END DoUnderliner;

PROCEDURE DoNoUnicodeMinus(): BOOLEAN;
BEGIN OvaConfig.unicodeMinus := FALSE; RETURN TRUE
END DoNoUnicodeMinus;

PROCEDURE DoOptions(): BOOLEAN;
BEGIN OvaConfig.showOptions := TRUE; RETURN TRUE
END DoOptions;

PROCEDURE DoHmm(): BOOLEAN;
BEGIN OvaConfig.format := OvaConfig.Hmm; RETURN TRUE
END DoHmm;

PROCEDURE DoHmmDepth(val: LONGINT): BOOLEAN;
BEGIN OvaConfig.hmmDepth := SHORT(val); RETURN TRUE
END DoHmmDepth;

PROCEDURE DoHmmCompactLists(): BOOLEAN;
BEGIN OvaConfig.hmmCompactLists := TRUE; RETURN TRUE
END DoHmmCompactLists;

PROCEDURE DoHmmPlain(): BOOLEAN;
BEGIN OvaConfig.hmmPlain := TRUE; RETURN TRUE
END DoHmmPlain;

PROCEDURE DoArgument(startIdx: INTEGER; VAR arg: ARRAY OF CHAR): BOOLEAN;
BEGIN OvaText.Append(files, Ropes.FromString(arg)); RETURN TRUE
END DoArgument;

(* ---- Parse ---- *)

PROCEDURE Opt(o: ArgParser.Option);
BEGIN parser.AddOption(o)
END Opt;

(* Parses the command line into OvaConfig and files.  A mistake on the
   command line ends the program with ArgParser.UsageErrorStatus (2),
   from ArgParser or OneChar.  Check helpShown afterwards. *)
PROCEDURE Parse*;
BEGIN
  Opt(ArgParser.MakeOption("h", "help", "Display this text.", DoHelp));
  Opt(ArgParser.MakeOption("g", "gemtext",
    "Output gemtext (the Gemini protocol's hypertext markup) instead of reST.", DoGemtext));
  Opt(ArgParser.MakeOption("M", "markdown", "Output plain Markdown prose instead of reST.", DoMarkdown));
  Opt(ArgParser.MakeOption("i", "inline",
    "Output each entity as one Markdown paragraph, an inline stat block like an adventure's cast list, instead of reST.",
    DoInline));
  Opt(ArgParser.MakeOption("X", "form",
    "Output the official character sheet's form fields as JSON fills for ova_form.sh, which fills the sheet's PDF with qpdf. Implies -n/--no-unicode-minus.",
    DoForm));
  Opt(ArgParser.MakeOption("H", "html",
    "Output reST with nested HTML tables (a `.. raw:: html` block) for Abilities/Weaknesses/Combat/Attacks, instead of terse prose.",
    DoHtml));
  Opt(ArgParser.MakeOption("G", "groff",
    "Output reST with groff `hd` tables (`.. raw:: ms` blocks) laid out like the rulebook's own Sample Characters spread, instead of terse prose.",
    DoGroff));
  Opt(ArgParser.MakeOption("e", "gemtext-emphasis",
    "With -g/--gemtext, emit *italic*/**bold** markers anyway -- gemtext's spec has no inline emphasis at all, but many authors use them as an unenforced convention. Off (plain text) by default; meaningless without -g/--gemtext.",
    DoGemtextEmphasis));
  Opt(ArgParser.MakeStringOption("o", "output", "Output file.", DoOutput));
  Opt(ArgParser.MakeStringOption("U", "subunderliner",
    "Entities after the first are subentities, and use a different character for underlining the subheader.",
    DoSubunderliner));
  Opt(ArgParser.MakeStringOption("u", "underliner", "Character to use for underlining the header.", DoUnderliner));
  Opt(ArgParser.MakeOption("n", "no-unicode-minus",
    "Turns OFF Unicode MINUS SIGN (U+2212) for negative numbers, reverting to ASCII hyphen-minus.",
    DoNoUnicodeMinus));
  Opt(ArgParser.MakeOption("O", "options",
    "Render an entity's options: block (which character-creation limiting rules were used), off by default.",
    DoOptions));
  Opt(ArgParser.MakeOption("m", "hmm", "Output a tab-indented h-m-m outline instead of reST.", DoHmm));
  Opt(ArgParser.MakeIntOption("L", "hmm-depth",
    "With -m/--hmm, indentation baseline (in tab stops) for the outline, so it can be embedded under an existing outline node elsewhere. Default 0 (left margin).",
    DoHmmDepth, 0, MAX(INTEGER)));
  Opt(ArgParser.MakeOption("c", "hmm-compact-lists",
    'With -m/--hmm, fold each of Abilities/Weaknesses onto one node ("Abilities: Ability1 +1 [...], ...") instead of a header node with one child node per item. Off by default.',
    DoHmmCompactLists));
  Opt(ArgParser.MakeOption("p", "hmm-plain",
    "With -m/--hmm, turn OFF *italic*/**bold**/***bold italic*** emphasis markers entirely. Off by default (emphasis is on).",
    DoHmmPlain));
  parser.ParseArguments(1)
END Parse;

BEGIN
  OvaText.Clear(files);
  helpShown := FALSE;
  parser := ArgParser.NewParser("ova_fmt [options] [files...]", DoArgument)
END OvaCli.
