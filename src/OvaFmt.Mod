MODULE OvaFmt; (* ova_fmt: an OVA character in YAML to reST, gemtext, Markdown, h-m-m, form JSON or sheet troff *)

(* Oberon-2 port of the Ada ova_fmt (ova_fmt_main.adb), with every
   string a Ropes.Rope.  See PLAN.md.

   Each file is loaded completely, every document and entity of it,
   before any of it is written, so that a file with a problem anywhere
   writes nothing.  Every missing or malformed required field in the
   file is reported, gcc style, with a summary line; any other problem
   ends the file at once, reported as "ova_fmt: error processing FILE:
   MESSAGE".  Either way the run goes on with the next file, and ends
   with status 1. *)

IMPORT Err, Fyaml, FyamlStreams, OvaCli, OvaCommon, OvaConfig, OvaEntities, OvaForm, OvaHmm, OvaInline, OvaOut, OvaRst, OvaSheet,
  OvaText, Out, Platform, Ropes, Strings, SYSTEM;

TYPE
  Entities = POINTER TO ARRAY OF OvaEntities.Entity;

VAR
  hadErrors: BOOLEAN;   (* an input error was reported: exit 1 *)

(* strerror, for an -o/--output file that can't be created: C's
   char *strerror(int), its int being SYSTEM.INT32 whatever the size
   model. *)
PROCEDURE ["C", "strerror"] strerror(e: SYSTEM.INT32): SYSTEM.ADDRESS;

(* Writes r to standard error. *)
PROCEDURE ErrRope(r: Ropes.Rope);
  VAR s: OvaText.String;
BEGIN s := OvaText.Chars(r); Err.String(s^)
END ErrRope;

(* Writes the OS's text for error code e, from strerror, to standard
   error. *)
PROCEDURE ErrReason(e: Platform.ErrorCode);
  VAR p: SYSTEM.ADDRESS; c: CHAR;
BEGIN
  p := strerror(SYSTEM.VAL(SYSTEM.INT32, e));
  IF p # 0 THEN
    SYSTEM.GET(p, c);
    WHILE c # 0X DO Err.Char(c); INC(p); SYSTEM.GET(p, c) END
  END
END ErrReason;

(* Reports a problem that ended the processing of source, in the Ada
   version's words: "ova_fmt: error processing SOURCE: MESSAGE".  Output
   so far is flushed first, so it comes before the error when both go to
   the terminal. *)
PROCEDURE Report(source, msg: Ropes.Rope);
BEGIN
  hadErrors := TRUE;
  OvaOut.Flush;
  Err.String("ova_fmt: error processing "); ErrRope(source); Err.String(": ");
  ErrRope(msg); Err.Ln
END Report;

(* The same, for an error from polibfyaml.  A syntax error's message
   is gcc style already, "FILE:LINE:COLUMN: error: TEXT", one line for
   each error, and is put as it is, but with one line feed at the end,
   not the two it has, as the Ada version puts it.  A file that can't
   be opened is "FILE: REASON", as the Ada version says it (GNAT's
   Name_Error message), not polibfyaml's "FILE: error: REASON" and line
   feed. *)
PROCEDURE ReportYaml(source: Ropes.Rope; err: Fyaml.Error);
  VAR msg, prefix: Ropes.Rope; reason: OvaText.String; sep: ARRAY 10 OF CHAR;
    f, i, n, skip: INTEGER; prefixed: BOOLEAN;
BEGIN
  IF err.kind = Fyaml.FileError THEN
    sep := ": error: ";
    f := 0; WHILE err.file[f] # 0X DO INC(f) END;
    n := 0; WHILE err.msg[n] # 0X DO INC(n) END;
    skip := f + Strings.Length(sep);
    prefixed := n >= skip;
    i := 0;
    WHILE prefixed & (i < skip) DO
      IF i < f THEN prefixed := err.msg[i] = err.file[i] ELSE prefixed := err.msg[i] = sep[i - f] END;
      INC(i)
    END;
    IF prefixed THEN
      IF (n > skip) & (err.msg[n - 1] = 0AX) THEN DEC(n) END;
      NEW(reason, n - skip + 1);
      FOR i := skip TO n - 1 DO reason[i - skip] := err.msg[i] END;
      reason[n - skip] := 0X;
      msg := Ropes.FromString(err.file^); OvaText.Add(msg, ": "); OvaText.Add(msg, reason^);
      Report(source, msg);
      RETURN
    END
  END;
  msg := Ropes.FromChars(err.msg^);
  prefix := Ropes.AppendChar(source, ":");
  IF (Ropes.Length(msg) > Ropes.Length(prefix))
     & Ropes.Equal(Ropes.Substring(msg, 0, Ropes.Length(prefix)), prefix) THEN
    hadErrors := TRUE;
    OvaOut.Flush;
    n := SHORT(Ropes.Length(msg));
    WHILE (n > 0) & (Ropes.Fetch(msg, n - 1) = 0AX) DO DEC(n) END;
    msg := Ropes.Substring(msg, 0, n);
    ErrRope(msg); Err.Ln
  ELSE Report(source, msg)
  END
END ReportYaml;

(* One error in source, gcc style: "SOURCE:LINE:COLUMN: error: PATH:
   MESSAGE", or "SOURCE: error: PATH: MESSAGE" when there is no
   location. *)
PROCEDURE PutError(source: Ropes.Rope; e: OvaEntities.LoadError);
BEGIN
  ErrRope(source);
  IF e.hasLocation THEN
    Err.Char(":"); ErrRope(OvaText.Int(e.line)); Err.Char(":"); ErrRope(OvaText.Int(e.column))
  END;
  Err.String(": error: "); ErrRope(e.path); Err.String(": "); ErrRope(e.message); Err.Ln
END PutError;

(* Every required-field error collected for source (PutError), then a
   summary line. *)
PROCEDURE ReportErrors(source: Ropes.Rope);
  VAR i: INTEGER; e: OvaEntities.LoadError;
BEGIN
  hadErrors := TRUE;
  OvaOut.Flush;
  FOR i := 0 TO OvaEntities.errors.n - 1 DO
    e := OvaEntities.errors.items[i](OvaEntities.LoadError);
    PutError(source, e)
  END;
  Err.String("ova_fmt: "); ErrRope(OvaText.Int(OvaEntities.errors.n)); Err.String(" error(s) in ");
  ErrRope(source); Err.String("; no output produced"); Err.Ln
END ReportErrors;

(* Adds e to the n entities in es, growing es. *)
PROCEDURE Keep(VAR es: Entities; VAR n: INTEGER; e: OvaEntities.Entity);
  VAR t: Entities; i: INTEGER;
BEGIN
  IF es = NIL THEN NEW(es, 8)
  ELSIF n = LEN(es^) THEN
    NEW(t, 2 * n);
    FOR i := 0 TO n - 1 DO t[i] := es[i] END;
    es := t
  END;
  es[n] := e; INC(n)
END Keep;

(* Loads the entities of document d into es.  FALSE, with msg, for a
   problem that ends the file. *)
PROCEDURE LoadDocument(d: Fyaml.Document; source: Ropes.Rope; VAR es: Entities; VAR n: INTEGER;
                       VAR msg: Ropes.Rope): BOOLEAN;
  VAR root, item: Fyaml.Node; it: Fyaml.ItemIter; e: OvaEntities.Entity;
BEGIN
  root := d.Root();
  IF (root = NIL) OR ~root.IsSequence() THEN
    msg := Ropes.Cat(Ropes.FromString("expected a top-level YAML sequence of entities in "), source);
    RETURN FALSE
  END;
  root.Items(it);
  WHILE it.Next(item) DO
    IF ~OvaEntities.Load(item, e, msg) THEN RETURN FALSE END;
    Keep(es, n, e)
  END;
  RETURN TRUE
END LoadDocument;

(* Writes e, the entityNo'th of its file, in the format chosen. *)
PROCEDURE Write(e: OvaEntities.Entity; entityNo: INTEGER);
BEGIN
  CASE OvaConfig.format OF
    OvaConfig.Gemtext, OvaConfig.Markdown: OvaCommon.ProcessEntity(e, entityNo)
  | OvaConfig.Hmm: OvaHmm.ProcessEntity(e, entityNo)
  | OvaConfig.Inline: OvaInline.ProcessEntity(e, entityNo)
  | OvaConfig.Form: OvaForm.ProcessEntity(e)
  | OvaConfig.Sheet: OvaSheet.ProcessEntity(e)
  | OvaConfig.Terse, OvaConfig.HtmlInRst, OvaConfig.GroffInRst: OvaRst.ProcessEntity(e, entityNo)
  END
END Write;

(* OvaConfig.sourceDir: name up to and including its last "/", for
   -S's relative portrait paths; NIL for standard input. *)
PROCEDURE SetSourceDir(name: Ropes.Rope; stdin: BOOLEAN);
  VAR i: LONGINT;
BEGIN
  OvaConfig.sourceDir := NIL;
  IF ~stdin THEN
    i := Ropes.Length(name) - 1;
    WHILE (i >= 0) & (Ropes.Fetch(name, i) # "/") DO DEC(i) END;
    OvaConfig.sourceDir := Ropes.Substring(name, 0, i + 1)
  END
END SetSourceDir;

(* One file, or standard input if stdin. *)
PROCEDURE ProcessOne(name: Ropes.Rope; stdin: BOOLEAN);
  VAR s: FyamlStreams.Stream; d: Fyaml.Document; err: Fyaml.Error;
    source, msg: Ropes.Rope; path: OvaText.String; es: Entities; n, i: INTEGER; ok: BOOLEAN;
BEGIN
  OvaEntities.ResetErrors;
  SetSourceDir(name, stdin);
  IF stdin THEN source := Ropes.FromString("(stdin)"); s := FyamlStreams.OpenStdin(err)
  ELSE source := name; path := OvaText.Chars(name); s := FyamlStreams.OpenFile(path^, err)
  END;
  IF s = NIL THEN ReportYaml(source, err); RETURN END;
  es := NIL; n := 0; ok := TRUE;
  d := s.Next(err);
  WHILE ok & (d # NIL) DO
    ok := LoadDocument(d, source, es, n, msg);
    d.Close;
    IF ok THEN d := s.Next(err) END
  END;
  s.Close;
  IF ~ok & (OvaEntities.valueError # NIL) THEN
    (* An optional field's value of the wrong kind: put as a required
       field's error is, but on its own, as the Ada version puts it. *)
    hadErrors := TRUE; OvaOut.Flush; PutError(source, OvaEntities.valueError)
  ELSIF ~ok THEN Report(source, msg)
  ELSIF err # NIL THEN ReportYaml(source, err)
  ELSIF OvaEntities.errors.n > 0 THEN ReportErrors(source)
  ELSE
    FOR i := 0 TO n - 1 DO Write(es[i], i + 1) END
  END
END ProcessOne;

PROCEDURE ProcessAll;
  VAR i: INTEGER;
BEGIN
  IF OvaCli.files.n = 0 THEN
    ProcessOne(NIL, TRUE)
  ELSE
    FOR i := 0 TO OvaCli.files.n - 1 DO ProcessOne(OvaCli.files.items[i], FALSE) END
  END;
  (* -X's output is one JSON array across every file. *)
  IF OvaConfig.format = OvaConfig.Form THEN OvaForm.Finish END
END ProcessAll;

PROCEDURE Main;
  VAR e: Platform.ErrorCode; path: OvaText.String;
BEGIN
  OvaCli.Parse;   (* exits with status 2 on a command-line mistake *)
  IF OvaCli.helpShown THEN
    (* As in the Ada version, whose Help_Requested handler sets 1. *)
    Out.Flush; Platform.Exit(1)
  END;

  (* -C lays out a page the blank sheet doesn't have, so it is only for
     the sheet drawn by -R.  A command-line mistake: status 2. *)
  IF OvaConfig.oneColumn & ~((OvaConfig.format = OvaConfig.Sheet) & OvaConfig.redraw) THEN
    Err.String("ova_fmt: -C/--one-column needs -S/--sheet and -R/--redraw"); Err.Ln;
    Platform.Exit(2)
  END;

  IF OvaConfig.hasOutputFile THEN
    path := OvaText.Chars(OvaConfig.outputFile);
    e := OvaOut.ToFile(path^);
    IF e # 0 THEN
      (* The Ada version's words and status. *)
      Err.String("ova_fmt: can't create "); Err.String(path^);
      Err.String(": "); ErrReason(e); Err.Ln;
      Platform.Exit(1)
    END
  END;

  hadErrors := FALSE;
  ProcessAll;

  e := OvaOut.Close();
  IF e # 0 THEN
    Err.String("ova_fmt: error writing output: "); ErrReason(e); Err.Ln;
    Platform.Exit(1)
  END;
  IF hadErrors THEN Platform.Exit(1) END
END Main;

BEGIN
  Main
END OvaFmt.
