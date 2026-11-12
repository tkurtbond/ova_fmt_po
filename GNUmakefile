# ova_fmt -- the Ada ova_fmt ported to Oberon-2 and built with poc, the
# Peaseblossom Oberon Compiler.  See AGENTS.md and PLAN.md.
#
# poc builds a program from its main module's source.  The shared
# modules come compiled, from the poc libraries argparser, ropes and
# polibfyaml (FyThin's C part included) on the library path; the
# program's own modules it finds on the import path (src/, and test/
# for the tests) and compiles again on each build, so there is no import
# order to keep: a new module needs no rule.  What poc writes -- each
# module's .sym, .ll and .o, and the programs -- goes into $(OBJ).
#
# Every program writes this repo's modules' files into the same $(OBJ),
# so make must not build two at once.

SHELL = bash

POC      ?= poc
# Size model: polibfyaml requires -OC, and models can't be mixed, so
# every module here -- ArgParser's, Ropes' and polibfyaml's included --
# gets it.
POCFLAGS := -OC

# libfyaml's link flags: the polibfyaml library doesn't record them.
# (On Linux, -lfyaml.)
FYAML_LIBS := $(shell pkg-config --libs libfyaml)
LINK := $(foreach f,$(FYAML_LIBS),-link $(f))

# The libraries argparser and ropes are installed by the ArgParser and
# Ropes repos (make -f pocGNUmakefile install), and polibfyaml by
# polibfyaml (make install), all in POCLIBDIR.  None of their sources is
# copied here.  Args and Err come from poc's runtime library, poc-rtl.
# POCLIBDIR doesn't follow PREFIX, which says where this program installs.
POCLIBDIR ?= $(HOME)/.local/lib/poc
SHAREDLIBS := argparser ropes polibfyaml
LIBPATH := -library-path $(abspath $(POCLIBDIR))

# The libraries this build takes are the ones in $(POCLIBDIR).  A library
# on POC_LIBRARY_PATH would stop the build if another poc wrote it.
unexport POC_LIBRARY_PATH
IMPORTS := -import-path src $(LIBPATH)

OBJ   := obj
BUILD := build

PROGRAM := ova_fmt_po
MAIN    := OvaFmt

# Every source and library a program is built from, for make's
# dependencies: a reinstalled library rebuilds the programs.
SHAREDLIBMANIFESTS := $(foreach l,$(SHAREDLIBS),$(wildcard $(POCLIBDIR)/*/OC/$(l).library))
PROGSRC := $(wildcard src/*.Mod)

# Test support modules, and test programs (test/<name>.Mod, main modules).
TESTSUPPORT := test/Check.Mod
TESTS       := TestText TestOut TestForm
TESTBINS    := $(TESTS:%=$(OBJ)/%)

# Only building needs the shared modules, so the cleaning targets don't
# check for them.
ifneq ($(if $(MAKECMDGOALS),$(filter-out clean testclean uninstall golden print-%,$(MAKECMDGOALS)),all),)
$(foreach l,$(SHAREDLIBS),$(if $(wildcard $(POCLIBDIR)/*/OC/$(l).library),,$(error the $(l) library is not in $(POCLIBDIR); $(if $(filter polibfyaml,$(l)),run make install in ~/Repos/Oberon/polibfyaml,run make -f pocGNUmakefile install in ~/Repos/Oberon/$(if $(filter ropes,$(l)),Ropes,ArgParser)))))
endif

.PHONY: all test golden valgrind rst pdf gemtext markdown html groff hmm inline form sheet fonts widths install uninstall clean testclean
.NOTPARALLEL:

all: $(PROGRAM)

$(OBJ):
	mkdir -p $@

$(PROGRAM): src/$(MAIN).Mod $(PROGSRC) $(SHAREDLIBMANIFESTS) | $(OBJ)
	$(POC) $(POCFLAGS) $(IMPORTS) -output-dir $(OBJ) $(LINK) -o $@ $<

$(OBJ)/Test%: test/Test%.Mod $(TESTSUPPORT) $(PROGSRC) $(SHAREDLIBMANIFESTS) | $(OBJ)
	$(POC) $(POCFLAGS) $(IMPORTS) -import-path test -output-dir $(OBJ) $(LINK) -o $@ $<

# Every unit test, then the command-line checks of test/cli.sh, then
# the golden-output comparison of test/golden.sh, then test/sheet.sh's
# checks of the PDFs -S and -X make (skipped without OVA_SHEET or the
# tools); fail at the end if any failed.
test: $(PROGRAM) $(TESTBINS)
	@status=0; for t in $(TESTS); do \
	  echo "== $$t"; (cd $(OBJ) && ./$$t) || status=1; \
	done; \
	echo "== cli.sh"; test/cli.sh ./$(PROGRAM) || status=1; \
	echo "== golden.sh"; test/golden.sh check ./$(PROGRAM) || status=1; \
	echo "== sheet.sh"; OVA_SHEET="$(OVA_SHEET)" SHEET_FONTS="$(SHEET_FONTS)" \
	  test/sheet.sh ./$(PROGRAM) || status=1; \
	exit $$status

# Rewrite test/golden/ from the Ada ova_fmt; see test/golden.cases.
# Needs neither this program nor its build.
ADA_OVA_FMT ?= $(HOME)/Repos/RPG/Tools/ova_fmt/ova_fmt
golden:
	ADA_OVA_FMT=$(ADA_OVA_FMT) test/golden.sh generate

# The program under valgrind: every fixture in each format, several
# files, standard input (empty, too), -o, and the early exits.
# polibfyaml's suppressions and still-reachable check, used from its
# checkout: poc-gc.supp for the conservative GC's stack scan
# (uninitialised-value errors in GarbageCollectedHeap.MarkCandidate
# only), libfyaml.supp for libfyaml's realloc(buf, 0) on empty input;
# and test/poc-gc.supp, for the same stack scan's errors in
# DrainMarkStack.  Each run must have no errors and nothing lost, and
# every still-reachable block must be the collector's own (its heap
# chunks and tables), which vg-reachable.sh checks by allocator
# (polibfyaml's AGENTS.md).
POLIBFYAML ?= $(HOME)/Repos/Oberon/polibfyaml
VALGRIND ?= valgrind -q --error-exitcode=99 --leak-check=full --show-leak-kinds=all \
  --suppressions=$(POLIBFYAML)/test/poc-gc.supp --suppressions=$(POLIBFYAML)/test/libfyaml.supp \
  --suppressions=test/poc-gc.supp
valgrind: $(PROGRAM) | $(OBJ)
	@status=0; n=0; log=$(OBJ)/valgrind.log; \
	vg() { n=$$((n + 1)); $(VALGRIND) ./$(PROGRAM) "$$@" >/dev/null 2>$$log; st=$$?; \
	  if [ $$st -eq 99 ] || grep -qE '(definitely|indirectly|possibly) lost: [1-9]' $$log \
	     || ! $(POLIBFYAML)/test/vg-reachable.sh $$log >/dev/null \
	     || ! grep -q 'are still reachable' $$log; then \
	    echo "FAIL - valgrind $$*"; sed 's/^/    /' $$log; status=1; fi; }; \
	for f in test/data/*.yaml; do \
	  for fl in "" "-g -e" "-M" "-H -O" "-G" "-m -c" "-m -p -L 2" "-i -n -O" "-X" "-S" "-S -P x.png"; do vg $$fl $$f </dev/null; done; \
	done; \
	vg test/data/*.yaml </dev/null; \
	vg -X test/data/*.yaml </dev/null; \
	vg -S test/data/*.yaml </dev/null; \
	vg -U '~' <test/data/Options.yaml; \
	vg </dev/null; \
	vg -o $(OBJ)/valgrind.out test/data/Karis.yaml </dev/null; \
	vg -h </dev/null; vg -L x </dev/null; vg -o /nonexistent/out test/data/Karis.yaml </dev/null; \
	vg -o /dev/full test/data/Karis.yaml </dev/null; \
	echo "valgrind: $$n runs"; \
	if [ $$status -eq 0 ]; then echo "All checks passed."; else exit 1; fi

# ---- Rendered test output, as in the Ada GNUmakefile ----
#
# Every character fixture but Broken.yaml, which is invalid on purpose
# (bad-* and edge-* are the error tests').  The
# targets and file names are the Ada GNUmakefile's.
TEST_DATA := $(filter-out test/data/Broken.yaml,$(wildcard test/data/[A-Z]*.yaml))
BASES := $(basename $(notdir $(TEST_DATA)))

TERSE_OUTPUT      := $(BASES:%=$(BUILD)/%.gen.rst)
PDF_OUTPUT        := $(BASES:%=$(BUILD)/%.rst.ms.pdf)
GEMTEXT_OUTPUT    := $(BASES:%=$(BUILD)/%.gmi) $(BASES:%=$(BUILD)/%.emp.gmi)
MARKDOWN_OUTPUT   := $(BASES:%=$(BUILD)/%.md) $(BASES:%=$(BUILD)/%.md.ms.pdf)
HTML_OUTPUT       := $(BASES:%=$(BUILD)/%.html.gen.rst) $(BASES:%=$(BUILD)/%.html)
GROFF_OUTPUT      := $(BASES:%=$(BUILD)/%.groff.gen.rst) $(BASES:%=$(BUILD)/%.groff.pdf)
HMM_OUTPUT        := $(BASES:%=$(BUILD)/%.hmm) $(BASES:%=$(BUILD)/%.compact.hmm) $(BASES:%=$(BUILD)/%.plain.hmm)
INLINE_OUTPUT     := $(BASES:%=$(BUILD)/%.inline.md)

# The official character sheet's form, filled (-X/--form and
# ova_form.sh, the Ada repo's copy; PLAN.md, "The official character
# sheet as PDF").  The blank sheet is Dyskami's and isn't in the repo.
OVA_SHEET ?= $(HOME)/Reference/RPG/OVA/OVA-Blank-Character-Sheet-Form-Fillable.pdf
FORM_OUTPUT       := $(BASES:%=$(BUILD)/%.form.pdf)

# The same sheet with -S/--sheet's text typeset over it (ova_sheet.sh,
# the Ada repo's copy), in the Noto Sans faces sheet_fonts.sh builds
# into SHEET_FONTS.  Rerun `make widths` only when the faces change: the
# widths -S measures with are built into the program
# (src/OvaSheetWidths.Mod, from sheet_widths.sh -O).
SHEET_FONTS ?= $(BUILD)/font
SHEET_OUTPUT      := $(BASES:%=$(BUILD)/%.sheet.pdf)

rst: $(TERSE_OUTPUT)
pdf: rst $(PDF_OUTPUT)
gemtext: $(GEMTEXT_OUTPUT)
markdown: $(MARKDOWN_OUTPUT)
html: $(HTML_OUTPUT)
groff: $(GROFF_OUTPUT)
hmm: $(HMM_OUTPUT)
inline: $(INLINE_OUTPUT)
form: $(FORM_OUTPUT)
sheet: fonts $(SHEET_OUTPUT)

fonts: $(SHEET_FONTS)/devpdf/download

$(SHEET_FONTS)/devpdf/download: sheet_fonts.sh
	./sheet_fonts.sh $(SHEET_FONTS)

widths: fonts
	./sheet_widths.sh -O $(SHEET_FONTS) >src/OvaSheetWidths.Mod.new
	mv src/OvaSheetWidths.Mod.new src/OvaSheetWidths.Mod

$(BUILD):
	mkdir -p $@

$(BUILD)/%.gen.rst: test/data/%.yaml $(PROGRAM) | $(BUILD)
	./$(PROGRAM) $< >$@
$(BUILD)/%.gmi: test/data/%.yaml $(PROGRAM) | $(BUILD)
	./$(PROGRAM) -g $< >$@
$(BUILD)/%.emp.gmi: test/data/%.yaml $(PROGRAM) | $(BUILD)
	./$(PROGRAM) -g -e $< >$@
$(BUILD)/%.md: test/data/%.yaml $(PROGRAM) | $(BUILD)
	./$(PROGRAM) -M $< >$@
$(BUILD)/%.html.gen.rst: test/data/%.yaml $(PROGRAM) | $(BUILD)
	./$(PROGRAM) -H $< >$@
$(BUILD)/%.html: $(BUILD)/%.html.gen.rst
	pandoc -r rst -w html --standalone -o $@ $<
$(BUILD)/%.groff.gen.rst: test/data/%.yaml $(PROGRAM) | $(BUILD)
	./$(PROGRAM) -G $< >$@
$(BUILD)/%.groff.pdf: $(BUILD)/%.groff.gen.rst
	pandoc -r rst -w ms --template=tkb -o $@ $<
$(BUILD)/%.hmm: test/data/%.yaml $(PROGRAM) | $(BUILD)
	./$(PROGRAM) -m $< >$@
$(BUILD)/%.compact.hmm: test/data/%.yaml $(PROGRAM) | $(BUILD)
	./$(PROGRAM) -m -c $< >$@
$(BUILD)/%.plain.hmm: test/data/%.yaml $(PROGRAM) | $(BUILD)
	./$(PROGRAM) -m -p $< >$@
$(BUILD)/%.inline.md: test/data/%.yaml $(PROGRAM) | $(BUILD)
	./$(PROGRAM) -i $< >$@
$(BUILD)/%.fields.json: test/data/%.yaml $(PROGRAM) | $(BUILD)
	./$(PROGRAM) -X $< >$@
$(BUILD)/%.form.pdf: $(BUILD)/%.fields.json ova_form.sh
	./ova_form.sh -s "$(OVA_SHEET)" -o $@ $<
$(BUILD)/%.sheet.tr: test/data/%.yaml $(PROGRAM) | $(BUILD)
	./$(PROGRAM) -S $< >$@
$(BUILD)/%.sheet.pdf: $(BUILD)/%.sheet.tr ova_sheet.sh $(SHEET_FONTS)/devpdf/download
	./ova_sheet.sh -s "$(OVA_SHEET)" -F $(SHEET_FONTS) -o $@ $<

#MS_COLUMNS = -V twocolumns
$(BUILD)/%.rst.ms.pdf: $(BUILD)/%.gen.rst
	pandoc -r rst -w ms --template=tkb $(MS_COLUMNS) -o $@ $<
$(BUILD)/%.md.ms.pdf: $(BUILD)/%.md
	pandoc -r markdown -w ms --template=tkb $(MS_COLUMNS) -o $@ $<

.PRECIOUS: $(BUILD)/%.gen.rst $(BUILD)/%.rst.ms.pdf $(BUILD)/%.gmi $(BUILD)/%.emp.gmi $(BUILD)/%.md \
  $(BUILD)/%.md.ms.pdf $(BUILD)/%.html.gen.rst $(BUILD)/%.html $(BUILD)/%.hmm $(BUILD)/%.compact.hmm \
  $(BUILD)/%.plain.hmm $(BUILD)/%.groff.gen.rst $(BUILD)/%.groff.pdf $(BUILD)/%.inline.md \
  $(BUILD)/%.fields.json $(BUILD)/%.form.pdf $(BUILD)/%.sheet.tr $(BUILD)/%.sheet.pdf

# ---- Installation ----
#
# To $(PREFIX)/bin, $HOME/local/bin by default as in the Ada version
# (its ova_fmt.gpr's Install package), under its own name, beside the
# Ada ova_fmt, with ova_form.sh, which fills the sheet from -X's
# output, and ova_sheet.sh, which typesets -S's over it.  DESTDIR is prepended, for staging.
PREFIX ?= $(HOME)/local
BINDIR ?= $(PREFIX)/bin

install: $(PROGRAM)
	install -d $(DESTDIR)$(BINDIR)
	install -m 755 $(PROGRAM) $(DESTDIR)$(BINDIR)/$(PROGRAM)
	install -m 755 ova_form.sh $(DESTDIR)$(BINDIR)/ova_form.sh
	install -m 755 ova_sheet.sh $(DESTDIR)$(BINDIR)/ova_sheet.sh

uninstall:
	rm -f $(DESTDIR)$(BINDIR)/$(PROGRAM) $(DESTDIR)$(BINDIR)/ova_form.sh $(DESTDIR)$(BINDIR)/ova_sheet.sh

clean: testclean
	rm -rf $(OBJ) $(PROGRAM)

testclean:
	rm -rf $(BUILD)

print-%: ; @echo $* = $($*)
