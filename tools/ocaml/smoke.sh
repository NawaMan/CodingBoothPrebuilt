#!/usr/bin/env bash
# Functional checks, also shipped in the archive for fresh-container verification.
set -euo pipefail
prefix="${1:?usage: smoke.sh <installed-prefix>}"
source "$prefix/env.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cd "$work"
printf 'let () = print_endline "OCaml works"\n' > hello.ml
ocamlc -o hello-byte hello.ml
[[ "$(./hello-byte)" == 'OCaml works' ]]
ocamlopt -o hello-native hello.ml
[[ "$(./hello-native)" == 'OCaml works' ]]
printf '(lang dune 3.0)\n' > dune-project
printf '(executable (name hello))\n' > dune
[[ "$(dune exec -- ./hello.exe)" == 'OCaml works' ]]
printf 'print_endline "UTOP_WORKS";;\n' | utop -noinit -stdin > utop.out
grep -q UTOP_WORKS utop.out
printf 'let x=1+2\n' > format.ml
ocamlformat --enable-outside-detected-project --name format.ml format.ml > formatted.ml
grep -q 'let x = 1 + 2' formatted.ml
opam list --installed --short > packages.txt
for package in ocaml-base-compiler dune utop ocamlformat; do
    grep -qx "$package" packages.txt
done
echo 'OCaml bytecode, native compiler, Dune, UTop, OCamlFormat and opam passed.'
