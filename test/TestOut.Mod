MODULE TestOut; (* Unit tests for OvaOut's ToRope and TakeRope *)

IMPORT Check, OvaOut, Ropes;

CONST BufSize = 8192;  (* OvaOut's buffer *)

PROCEDURE TestRope;
  VAR r: Ropes.Rope; i: LONGINT; ok: BOOLEAN;
BEGIN
  OvaOut.ToRope;
  r := OvaOut.TakeRope();
  Check.Check(r = NIL, "nothing written: NIL");

  OvaOut.ToRope;
  OvaOut.String("abc"); OvaOut.Ln; OvaOut.Rope(Ropes.FromString("de")); OvaOut.Repeat("f", 3);
  r := OvaOut.TakeRope();
  Check.Check(Ropes.Equal(r, Ropes.Cat(Ropes.AppendChar(Ropes.FromString("abc"), 0AX), Ropes.FromString("defff"))),
    "what was written, in order");

  (* More than the buffer holds, so it is flushed into the rope midway. *)
  OvaOut.ToRope;
  OvaOut.Repeat("x", 2 * BufSize + 5); OvaOut.Char("y");
  r := OvaOut.TakeRope();
  ok := Ropes.Length(r) = 2 * BufSize + 6;
  FOR i := 0 TO 2 * BufSize + 4 DO ok := ok & (Ropes.Fetch(r, i) = "x") END;
  Check.Check(ok & (Ropes.Fetch(r, 2 * BufSize + 5) = "y"), "past the buffer: all of it, in order");

  OvaOut.ToRope;
  r := OvaOut.TakeRope();
  Check.Check(r = NIL, "taken: kept from scratch the next time");
  Check.Check(OvaOut.Close() = 0, "no write errors")
END TestRope;

BEGIN
  TestRope;
  Check.Summary
END TestOut.
