MODULE OvaSheetDraw; (* -R/--redraw: the sheet's frames and labels as troff *)

(* The Ada Ova_Fmt.Sheet_Draw: with -S/--sheet, troff that draws the
   official character sheet's frames and labels, so that the output
   needs no blank sheet under it and can be shared (PLAN.md, "Redrawing
   the sheet").

   The frames are measured from the blank sheet's own drawing: its
   panels, boxes and rules, as rounded rectangles, rules and dots, in
   its colours; its labels in Noto Sans, each scaled across to the width
   it has on the sheet.  The logo, the spiral binding on page 2 and the
   vertical "Character Record" are left out.

   Coordinates are in points, x from the left and y from the top.  AT Y
   X places the next output line's baseline; RF X Y W H R COLOUR fills a
   rectangle with corners rounded by R (two crossed rectangles and a
   circle in each corner; a stroked frame is one filled rectangle on
   another); HR and VR are the Combat Stats grid's rules; the dots
   string is one of the dotted rules; TX X Y FACE HEIGHT WIDTH COLOUR
   TEXT sets a label scaled across to its width on the sheet.  Each
   polygon and rule ends where it began, so that the vertical position
   doesn't move.  Sizes are in u, a thousandth of a point under -Tpdf.
   The Ada comments hold the full reasoning. *)

IMPORT OvaOut;

CONST
  (* Draw page 1's or page 2's frames, under its text: right after the
     page's .SP. *)
  Page1* = ".FR-p1";
  Page2* = ".FR-p2";

  (* -C's page 1 in place of Page1: the sheet's header, then one column
     for the Abilities and Weaknesses beside an Attacks & Combat Stats
     box (Acacia's block in the rulebook). *)
  Page1OneColumn* = ".FR-p1c";

  (* Rule, a blank and Y: -C's faint rule across the column between the
     Abilities and the Weaknesses, its top Y points from the top. *)
  Rule* = ".CR";

PROCEDURE Line(s: ARRAY OF CHAR);
BEGIN OvaOut.String(s); OvaOut.Ln
END Line;

(* The colours and macros, for the end of OvaSheet's preamble, and with
   oneColumn (-C/--one-column) Page1OneColumn's and Rule's.  Its first
   line, a comment saying ova-sheet-redrawn, tells ova_sheet.sh not to
   lay the blank sheet under the pages. *)
PROCEDURE PutPreamble*(oneColumn: BOOLEAN);
BEGIN
  Line('.\" ova-sheet-redrawn');
  OvaOut.String('.\"'); Line(" -R: the sheet's frames and labels drawn here, not taken from the");
  OvaOut.String('.\"'); Line(" blank sheet; FR-p1 and FR-p2 draw a page's, under its text.");
  Line(".defcolor ovasheetgrey cmyk 0.065 0.1 0.072 0");
  Line(".defcolor ovasheetred rgb 0.451 0.114 0.126");
  Line(".de AT");
  Line(".sp |\\$1-1p");
  Line(".in \\$2");
  Line("..");
  Line(".de RF");
  Line(".nr rf-x \\$1p");
  Line(".nr rf-y \\$2p");
  Line(".nr rf-w \\$3p");
  Line(".nr rf-h \\$4p");
  Line(".nr rf-r \\$5p");
  Line(".nr rf-d 2*\\n[rf-r]");
  Line(".AT \\n[rf-y]u+\\n[rf-r]u \\n[rf-x]u");
  Line("\M[\\$6]\D'P \\n[rf-w]u 0 0 \\n[rf-h]u-\\n[rf-d]u -\\n[rf-w]u 0 0 \\n[rf-d]u-\\n[rf-h]u'\M[]");
  Line(".AT \\n[rf-y]u \\n[rf-x]u+\\n[rf-r]u");
  Line("\M[\\$6]\D'P \\n[rf-w]u-\\n[rf-d]u 0 0 \\n[rf-h]u \\n[rf-d]u-\\n[rf-w]u 0 0 -\\n[rf-h]u'\M[]");
  Line(".if \\n[rf-r] \{\");
  Line(".AT \\n[rf-y]u+\\n[rf-r]u \\n[rf-x]u");
  Line("\M[\\$6]\D'C \\n[rf-d]u'\h'\\n[rf-w]u-\\n[rf-d]u-\\n[rf-d]u'\D'C \\n[rf-d]u'\M[]");
  Line(".AT \\n[rf-y]u+\\n[rf-h]u-\\n[rf-r]u \\n[rf-x]u");
  Line("\M[\\$6]\D'C \\n[rf-d]u'\h'\\n[rf-w]u-\\n[rf-d]u-\\n[rf-d]u'\D'C \\n[rf-d]u'\M[]");
  Line(".\}");
  Line("..");
  Line(".de HR");
  Line(".AT \\$2p \\$1p");
  Line("\m[ovasheetred]\D't 0.5p'\D'l \\$3p 0'\m[]");
  Line("..");
  Line(".de VR");
  Line(".AT \\$2p \\$1p");
  Line("\m[ovasheetred]\D't 0.5p'\D'l 0 \\$3p'\v'-\\$3p'\m[]");
  Line("..");
  Line(".ds dots");
  Line(".nr dots 0 1");
  Line(".while \n+[dots]<=177 .as dots \M[ovasheetgrey]\D'C 1p'\M[]\h'1.003p'");
  Line(".de TX");
  Line(".AT \\$2p \\$1p");
  Line(".ds tx-f \\$3");
  Line(".nr tx-h \\$4p");
  Line(".nr tx-t \\$5p");
  Line(".ds tx-c \\$6");
  Line(".shift 6");
  Line(".nr tx-w \w'\f[\\*[tx-f]]\s'\\n[tx-h]u'\\$*'");
  Line(".nr tx-s \\n[tx-h]/10*\\n[tx-t]/(\\n[tx-w]/10)");
  Line("\f[\\*[tx-f]]\s'\\n[tx-s]u'\H'\\n[tx-h]u'\m[\\*[tx-c]]\\$*\m[]\H'0'\s[0]\f[]");
  Line("..");
  Line(".de FR-p1");
  Line(".RF 23.75 364.846 412.75 201.87 8 ovasheetgrey");
  Line(".RF -8.64 85.866 404.64 250.75 8 ovasheetgrey");
  Line(".RF 100.47 31.306 336 34.7 12.3 ovasheetred");
  Line(".RF 146.47 36 129.778 18 5.76 white");
  Line(".RF 282.334 36 127.666 18 5.76 white");
  Line(".RF 34.47 103.996 18 228.44 5.76 white");
  Line(".RF 56.47 103.996 153.29 228.44 5.76 white");
  Line(".RF 216.47 103.996 18 228.44 5.76 white");
  Line(".RF 238.47 103.996 153.29 228.44 5.76 white");
  Line(".nr dots 0");
  Line(".while \\n[dots]<17 \{\");
  Line(".AT 119.116p+(\\n[dots]u*13p) 36.6p");
  Line("\\*[dots]");
  Line(".nr dots +1");
  Line(".\}");
  Line(".RF 27.75 388.366 120.72 174.35 8 white");
  Line(".RF 140.86 358.996 247.22 220.37 15 ovasheetred");
  Line(".RF 142.86 360.996 243.22 216.37 13 white");
  Line(".RF 140.86 345.996 247.22 27.62 12 ovasheetred");
  Line(".RF 140.86 363.996 247.22 9.62 0 ovasheetred");
  Line(".HR 145.47 412.996 238.03");
  Line(".HR 145.47 452.746 238.03");
  Line(".HR 145.47 491.746 238.03");
  Line(".HR 145.47 530.746 238.03");
  Line(".VR 281.47 376.366 154.38");
  Line(".VR 316.47 376.366 154.38");
  Line(".VR 348.47 376.366 154.38");
  Line(".TX 147.37 61.496 NSXCB 8 36.9 white CHARACTER NAME");
  Line(".TX 282.3 61.496 NSXCB 8 30.57 white PLAYER NAME");
  Line(".TX 37.35 99.416 NSXCB 14 32.63 black ABILITIES");
  Line(".TX 219.02 99.416 NSXCB 14 46.79 black WEAKNESSES");
  Line(".TX 34.02 381.416 NSXCB 14 54.36 black COMBAT NOTES");
  Line(".TX 33.02 559.066 NSXCB 12 95.17 ovasheetgrey DAMAGE, COMPLICATIONS, ETC.");
  Line(".TX 146.47 369.646 NSXCB 24 94.25 white Combat Stats");
  Line(".TX 284.33 385.496 NSR 11 28.14 ovasheetred ROLL");
  Line(".TX 324.33 385.496 NSR 11 15.16 ovasheetred DX");
  Line(".TX 354.33 385.496 NSR 11 23.23 ovasheetred END");
  Line(".TX 284.33 423.496 NSR 11 28.14 ovasheetred ROLL");
  Line(".TX 324.33 423.496 NSR 11 15.16 ovasheetred DX");
  Line(".TX 354.33 423.496 NSR 11 23.23 ovasheetred END");
  Line(".TX 284.33 463.496 NSR 11 28.14 ovasheetred ROLL");
  Line(".TX 324.33 463.496 NSR 11 15.16 ovasheetred DX");
  Line(".TX 354.33 463.496 NSR 11 23.23 ovasheetred END");
  Line(".TX 284.33 502.496 NSR 11 28.14 ovasheetred ROLL");
  Line(".TX 324.33 502.496 NSR 11 15.16 ovasheetred DX");
  Line(".TX 354.33 502.496 NSR 11 23.23 ovasheetred END");
  Line(".TX 148.47 541.496 NSR 11 48.01 ovasheetred DEFENSE");
  Line(".TX 211.47 541.496 NSR 11 43.05 ovasheetred HEALTH");
  Line(".TX 271.48 541.496 NSR 11 68.31 ovasheetred ENDURANCE");
  Line(".TX 356.47 541.496 NSR 11 13.61 ovasheetred TV");
  Line("..");
  Line(".de FR-p2");
  Line(".RF 0 0 419.528 595.276 0 ovasheetgrey");
  Line(".RF 32.78 19.346 238.22 307.93 8 white");
  Line(".RF 31.78 340.066 172 165.3 8 white");
  Line(".RF 211.36 340.066 172 165.3 8 white");
  Line(".RF 31.78 516.116 351.58 58.5 8 white");
  Line(".RF 238.78 0 166.22 36.006 0 ovasheetred");
  Line(".RF 238.78 17.996 166.22 310.62 14 ovasheetred");
  Line(".RF 240.78 19.996 162.22 306.62 12 white");
  Line(".TX 36.4 36.996 NSXCB 16 58.88 ovasheetred Background");
  Line(".TX 36 356.996 NSXCB 16 58.51 ovasheetred Appearance");
  Line(".TX 219.76 356.996 NSXCB 16 58 ovasheetred Personality");
  Line(".TX 36 534 NSXCB 16 60.59 ovasheetred Other Notes");
  Line(".TX 285.02 14.996 NSXCB 12 73.74 ovasheetgrey CHARACTER PORTRAIT");
  Line("..");

  (* Continuation pages to match: a grey ground, and a white panel
     framed in red under a red "Continued" title bar, drawn by HD, the
     top-of-page trap, on each one, in an environment of its own.  FT
     does nothing while a page is drawn, since the drawing passes the
     footer trap.  The headings are red, as page 2's are. *)
  OvaOut.String('.\"'); Line(" -R: continuation pages drawn to match the sheet's; HD draws each one.");
  Line(".de FR-cp");
  Line(".RF 0 0 419.528 595.276 0 ovasheetgrey");
  Line(".RF 31.78 37 351.58 540 15 ovasheetred");
  Line(".RF 33.78 39 347.58 536 13 white");
  Line(".RF 31.78 24 351.58 27.62 12 ovasheetred");
  Line(".RF 31.78 42 351.58 9.62 0 ovasheetred");
  Line(".TX 37.39 47.65 NSXCB 24 73.83 white Continued");
  Line("..");
  Line(".nr drawing 0");
  Line(".de FT");
  Line(".if !\\n[drawing] 'bp");
  Line("..");
  Line(".de HD");
  Line(".if \\n[cont] \{\");
  Line(".nr drawing 1");
  Line(".ev ova-draw");
  Line(".nf");
  Line(".vs 1p");
  Line(".FR-cp");
  Line(".ev");
  Line(".nr drawing 0");
  Line("'sp |64p");
  Line(".\}");
  Line("..");
  Line(".am CP");
  Line(".in 44p");
  Line(".ll 371p");
  Line("..");
  Line(".am SH");
  Line(".ft NSCSB");
  Line(".ps 12");
  Line(".gcolor ovasheetred");
  Line("..");
  Line(".am PP");
  Line(".gcolor default");
  Line("..");

  (* -C's page 1, in the same terms: the sheet's header, a column of
     lines for the Abilities and Weaknesses (no Dice boxes and no dots,
     as in the rulebook), and an Attacks & Combat Stats box built as the
     sheet's Combat Stats box is, with five attack slots 39.5 pt apart,
     a Combat Notes space and the four stats along its bottom.  New
     labels are scaled as the sheet's own are.  CR is the faint rule
     between the Abilities and the Weaknesses. *)
  IF oneColumn THEN
    OvaOut.String('.\"'); Line(" -C: page 1 as one column beside an Attacks & Combat Stats box.");
    Line(".defcolor ovasheetrule gray 0.75");
    Line(".de CR");
    Line(".RF 40.47 \\$1 124 0.6 0 ovasheetrule");
    Line("..");
    Line(".de FR-p1c");
    Line(".RF -8.64 85.866 404.64 490 8 ovasheetgrey");
    Line(".RF 100.47 31.306 336 34.7 12.3 ovasheetred");
    Line(".RF 146.47 36 129.778 18 5.76 white");
    Line(".RF 282.334 36 127.666 18 5.76 white");
    Line(".RF 34.47 103.996 136 462 5.76 white");
    Line(".RF 176.47 116.996 215.29 449 15 ovasheetred");
    Line(".RF 178.47 118.996 211.29 445 13 white");
    Line(".RF 176.47 103.996 215.29 27.62 12 ovasheetred");
    Line(".RF 176.47 121.996 215.29 9.62 0 ovasheetred");
    Line(".HR 181.08 170.996 206.1");
    Line(".HR 181.08 210.496 206.1");
    Line(".HR 181.08 249.996 206.1");
    Line(".HR 181.08 289.496 206.1");
    Line(".HR 181.08 328.996 206.1");
    Line(".HR 181.08 517.376 206.1");
    Line(".VR 285.15 134.366 194.63");
    Line(".VR 320.15 134.366 194.63");
    Line(".VR 352.15 134.366 194.63");
    Line(".TX 147.37 61.496 NSXCB 8 36.9 white CHARACTER NAME");
    Line(".TX 282.3 61.496 NSXCB 8 30.57 white PLAYER NAME");
    Line(".TX 37.35 99.416 NSXCB 14 87.31 black ABILITIES & WEAKNESSES");
    Line(".TX 182.08 124.95 NSXCB 20 137.2 white Attacks & Combat Stats");
    Line(".TX 288.01 143.516 NSR 11 28.14 ovasheetred ROLL");
    Line(".TX 328.01 143.516 NSR 11 15.16 ovasheetred DX");
    Line(".TX 358.01 143.516 NSR 11 23.23 ovasheetred END");
    Line(".TX 288.01 183.016 NSR 11 28.14 ovasheetred ROLL");
    Line(".TX 328.01 183.016 NSR 11 15.16 ovasheetred DX");
    Line(".TX 358.01 183.016 NSR 11 23.23 ovasheetred END");
    Line(".TX 288.01 222.516 NSR 11 28.14 ovasheetred ROLL");
    Line(".TX 328.01 222.516 NSR 11 15.16 ovasheetred DX");
    Line(".TX 358.01 222.516 NSR 11 23.23 ovasheetred END");
    Line(".TX 288.01 262.016 NSR 11 28.14 ovasheetred ROLL");
    Line(".TX 328.01 262.016 NSR 11 15.16 ovasheetred DX");
    Line(".TX 358.01 262.016 NSR 11 23.23 ovasheetred END");
    Line(".TX 288.01 301.516 NSR 11 28.14 ovasheetred ROLL");
    Line(".TX 328.01 301.516 NSR 11 15.16 ovasheetred DX");
    Line(".TX 358.01 301.516 NSR 11 23.23 ovasheetred END");
    Line(".TX 184.47 341.496 NSR 11 85.63 ovasheetred COMBAT NOTES");
    Line(".TX 182.47 528.126 NSR 11 48.01 ovasheetred DEFENSE");
    Line(".TX 236 528.126 NSR 11 43.05 ovasheetred HEALTH");
    Line(".TX 285.85 528.126 NSR 11 68.31 ovasheetred ENDURANCE");
    Line(".TX 366.2 528.126 NSR 11 13.61 ovasheetred TV");
    Line("..");
  END
END PutPreamble;

END OvaSheetDraw.
