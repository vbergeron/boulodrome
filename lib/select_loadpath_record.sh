#!/usr/bin/env bash
# Picks the Loadpath.vo_path record shape matching the installed Rocq/Coq
# version. The field set of that record changed across releases (see
# dune_loadpath_record.*.ml.inc), so the right variant must be selected at
# build time rather than compiled once against a single API shape.
set -euo pipefail

version=$(ocamlfind query -format '%v' rocq-core 2>/dev/null \
  || ocamlfind query -format '%v' coq-core)

case "$version" in
  8.20*)
    cat dune_loadpath_record.8_20.ml.inc
    ;;
  9.0*)
    cat dune_loadpath_record.9_0.ml.inc
    ;;
  9.*)
    cat dune_loadpath_record.9_1.ml.inc
    ;;
  *)
    echo "dune_loadpath_record: unsupported Coq/Rocq version '$version'" >&2
    exit 1
    ;;
esac
