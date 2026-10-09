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

prog=${1:-./po_ova_fmt}
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
check "-u with two characters exits 2" 2 '^ova_fmt: -u/--underliner takes exactly one character, got "xx"$' -u xx "$f"
check "-U with two characters exits 2" 2 'subunderliner takes exactly one character, got "ab"' -U ab "$f"
check "-u with an empty argument exits 2" 2 'got ""$' -u "" "$f"
check "-u= sets the underliner to =" 0 '' -u= "$f"
check "-L that isn't a number exits 2" 2 'Invalid integer value for option -L, --hmm-depth: x' -m -L x "$f"
check "-L -1 exits 2" 2 'Value out of range for option -L, --hmm-depth' -m -L -1 "$f"
check "--hmm-depth=3 indents by three more tabs" 0 $'^\t\t\t\tKaris' -m --hmm-depth=3 "$f"
check "the last format option wins" 0 '^# Karis' -m -H -M "$f"

# The Ada version dies with an unhandled exception for these.
check "-o to a directory that doesn't exist exits 1 with the OS reason" 1 \
  "^ova_fmt: can't create /nonexistent/dir/out: No such file or directory$" -o /nonexistent/dir/out "$f"
check "a write error is reported, exit 1" 1 '^ova_fmt: error writing output: No space left on device$' \
  -o /dev/full "$f"
check "a missing file is reported, exit 1" 1 \
  '^ova_fmt: error processing nosuch\.yaml: nosuch\.yaml: error: No such file or directory$' nosuch.yaml
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

# Standard input: errors name it (stdin), and libfyaml's <stdin>.
"$prog" <"$data/Broken.yaml" >"$tmp/out" 2>&1
if [ $? -eq 1 ] && grep -q '^ova_fmt: 5 error(s) in (stdin); no output produced$' "$tmp/out"; then
  echo "ok   - errors on standard input name it (stdin)"
else
  echo "FAIL - errors on standard input name it (stdin)"; sed 's/^/    /' "$tmp/out"; failed=$((failed + 1))
fi
"$prog" <"$data/bad-yaml.yaml" >"$tmp/out" 2>&1
if [ $? -eq 1 ] && grep -q '^ova_fmt: error processing (stdin): <stdin>:4:1: error: flow sequence' "$tmp/out"; then
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
