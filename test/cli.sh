#!/usr/bin/env bash
# Command-line handling of ova_fmt, and the errors the golden files
# can't hold: exit statuses, and a line of the output or error each
# case must contain.  Run from the repo root by `make test`, as
# test/cli.sh [program]; prints ok/FAIL per case, as the unit tests do,
# and exits 1 if any failed.
#
# Statuses follow the Ada version: help 1 (its Help_Requested handler),
# command-line mistakes 2, bad input 1, and an output file that can't be
# created or written 1.

prog=${1:-./ova_fmt_po}
data=test/data
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
failed=0

# check LABEL STATUS PATTERN [ARGS...]: run prog ARGS with stdin from
# /dev/null, stdout and stderr together; require exit STATUS and a line
# matching the grep -E PATTERN (skipped if PATTERN is empty).
check() {
  local label=$1 want=$2 pattern=$3; shift 3
  "$prog" "$@" </dev/null >"$tmp/out" 2>&1
  local got=$?
  if [ "$got" -ne "$want" ]; then
    echo "FAIL - $label: exit $got, not $want"; sed 's/^/    /' "$tmp/out"; failed=$((failed + 1))
  elif [ -n "$pattern" ] && ! grep -qE -- "$pattern" "$tmp/out"; then
    echo "FAIL - $label: no line matching /$pattern/"; sed 's/^/    /' "$tmp/out"; failed=$((failed + 1))
  else
    echo "ok   - $label"
  fi
}

f=$data/Karis.yaml

check "-h shows the usage and exits 1, as the Ada version does" 1 '^  -p, --hmm-plain$' -h
check "--help after a file still exits 1" 1 '^ova_fmt \[options\] \[files\.\.\.\]$' "$f" --help
"$prog" -h </dev/null >"$tmp/out" 2>"$tmp/err"
if [ -s "$tmp/out" ] && [ ! -s "$tmp/err" ]; then
  echo "ok   - -h writes the usage to standard output"
else
  echo "FAIL - -h writes the usage to standard output"; failed=$((failed + 1))
fi
check "an unknown long option exits 2" 2 '^Error: Unknown option --bogus$' --bogus "$f"
check "an unknown short option exits 2" 2 '^Error: Unknown option -x$' -x "$f"
check "a missing option argument exits 2" 2 '^Error: Argument required for option -u, --underliner$' -u
check "-u with two characters exits 2" 2 '^Invalid value for option -u/--underliner: takes exactly one character, got "xx"$' -u xx "$f"
check "-U with two characters exits 2" 2 'subunderliner: takes exactly one character, got "ab"' -U ab "$f"
check "-u with an empty argument exits 2" 2 'got ""$' -u "" "$f"
check "-u= sets the underliner to =" 0 '' -u= "$f"
check "-L that isn't a number exits 2" 2 'Invalid integer value for option -L, --hmm-depth: x' -m -L x "$f"
check "-L -1 exits 2" 2 'Value out of range for option -L, --hmm-depth' -m -L -1 "$f"
check "--hmm-depth=3 indents by three more tabs" 0 $'^\t\t\t\tKaris' -m --hmm-depth=3 "$f"
check "the last format option wins" 0 '^# Karis' -m -H -M "$f"
check "-h lists -i, --inline" 1 '^  -i, --inline$' -h
check "-i leads with the name in bold" 0 '^\*\*Karis\.\*\* A bounty hunter' -i "$f"
check "-i gives the NPC type after the name" 0 '^\*\*Shadowman\*\* \([A-Z][a-z]+\)\. ' -i "$data/Shadowman.yaml"

# inline-fill FILE: whether the inline output in FILE is filled: no line
# over 70 characters (counted in UTF-8) unless it is one word, and none
# whose first word would open a Markdown block (a heading, a block
# quote, a list item, a thematic break or setext underline).
inline_fill() {
  LC_ALL=C.UTF-8 awk '
    length($0) > 70 && index($0, " ") { print FILENAME ":" FNR ": over 70: " $0; bad = 1 }
    $1 ~ /^(#|>|\+$|[-=*_]+$|[0-9]+[.)]$)/ { print FILENAME ":" FNR ": opens a block: " $0; bad = 1 }
    END { exit bad }' "$1"
}
for y in "$data"/[A-Z]*.yaml; do "$prog" -i "$y"; done >"$tmp/inline" 2>/dev/null
if inline_fill "$tmp/inline" >"$tmp/out"; then
  echo "ok   - -i fills every character fixture to 70 columns, with no line opening a block"
else
  echo "FAIL - -i fills every character fixture to 70 columns, with no line opening a block"
  sed 's/^/    /' "$tmp/out" | head -20; failed=$((failed + 1))
fi
# The filler keeps a word that can't start a line with the word before.
printf -- "- name: Fill\n  summary: '%s'\n" \
  "aaaaaaaaa bbbbbbbbb ccccccccc ddddddddd eeeeeeeee fffffff ggggg 10. # > - * 1) + === x" \
  >"$tmp/fill.yaml"
"$prog" -i "$tmp/fill.yaml" >"$tmp/fill" 2>&1
if inline_fill "$tmp/fill" >"$tmp/out" && grep -q '^ggggg 10\. # > - \* 1) + === x\.$' "$tmp/fill"; then
  echo "ok   - -i breaks before the word ahead of one that can't start a line"
else
  echo "FAIL - -i breaks before the word ahead of one that can't start a line"
  sed 's/^/    /' "$tmp/fill" "$tmp/out"; failed=$((failed + 1))
fi

# What can't be a golden case (a path that must not exist, a full
# device).  The YAML of the wrong shape (bad-shape-*) is in
# test/golden.cases too; these check that a bad file doesn't end the run.
check "-o to a directory that doesn't exist exits 1 with the OS reason" 1 \
  "^ova_fmt: can't create /nonexistent/dir/out: No such file or directory$" -o /nonexistent/dir/out "$f"
check "a write error is reported, exit 1" 1 '^ova_fmt: error writing output: No space left on device$' \
  -o /dev/full "$f"
check "a missing file is reported, exit 1" 1 \
  '^ova_fmt: error processing nosuch\.yaml: nosuch\.yaml: No such file or directory$' nosuch.yaml
check "the run goes on after a missing file" 1 '^Karis \(Hotheaded' nosuch.yaml "$f"
check "abilities: that isn't a sequence" 1 \
  '^ova_fmt: error processing test/data/bad-shape-not-sequence\.yaml: /0/abilities: not a sequence$' \
  "$data/bad-shape-not-sequence.yaml"
check "an ability that isn't a mapping" 1 \
  '^ova_fmt: error processing test/data/bad-shape-not-mapping\.yaml: /0/abilities/0: not a mapping$' \
  "$data/bad-shape-not-mapping.yaml"
check "an entity that isn't a mapping" 1 \
  '^ova_fmt: error processing test/data/bad-shape-entity\.yaml: /0: not a mapping$' \
  "$data/bad-shape-entity.yaml"
check "a fluff: that isn't a mapping" 1 \
  '^ova_fmt: error processing test/data/bad-shape-fluff\.yaml: /0/fluff: not a mapping$' \
  "$data/bad-shape-fluff.yaml"
check "a bad file doesn't stop the next one" 1 '^Karis \(Hotheaded' "$data/bad-shape-fluff.yaml" "$f"

# Standard input: errors name it (stdin), libfyaml's included.
"$prog" <"$data/Broken.yaml" >"$tmp/out" 2>&1
if [ $? -eq 1 ] && grep -q '^ova_fmt: 5 error(s) in (stdin); no output produced$' "$tmp/out"; then
  echo "ok   - errors on standard input name it (stdin)"
else
  echo "FAIL - errors on standard input name it (stdin)"; sed 's/^/    /' "$tmp/out"; failed=$((failed + 1))
fi
"$prog" <"$data/bad-yaml.yaml" >"$tmp/out" 2>&1
if [ $? -eq 1 ] && [ "$(cat "$tmp/out")" = '(stdin):4:1: error: flow sequence without a closing bracket' ]; then
  echo "ok   - a YAML error on standard input"
else
  echo "FAIL - a YAML error on standard input"; sed 's/^/    /' "$tmp/out"; failed=$((failed + 1))
fi

# Many collections: a big input, made of many copies of a fixture's
# entity, must come out as as many copies of its output.
for i in $(seq 1 300); do sed -n '/^-/,$p' "$data/Karis.yaml"; done >"$tmp/big.yaml"
"$prog" "$data/Karis.yaml" >"$tmp/one"
for i in $(seq 1 300); do cat "$tmp/one"; done >"$tmp/want"
if "$prog" "$tmp/big.yaml" >"$tmp/many" 2>&1 && cmp -s "$tmp/want" "$tmp/many"; then
  echo "ok   - 300 copies of Karis"
else
  echo "FAIL - 300 copies of Karis"; failed=$((failed + 1))
fi

if [ $failed -eq 0 ]; then
  echo "All checks passed."
else
  echo "$failed check(s) failed."; exit 1
fi
