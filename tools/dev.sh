#!/bin/sh
# Developer shortcuts. Usage: tools/dev.sh check|test|bench|map <id>|race <args...>
cd "$(dirname "$0")/.." || exit 1
case "$1" in
  check) godot --headless --path . --import >/dev/null 2>&1; godot --headless --path . -s tools/check.gd 2>&1 | grep -E "Parse Error|FAIL|scripts," ;;
  test) godot --headless --path . -s tests/run_tests.gd -- "${@:2}" 2>&1 | grep -E "FAIL|tests,|      " ;;
  bench) shift; godot --headless --path . -s tools/handling_bench.gd -- "$@" 2>&1 | grep -v -E "^\s*$|Godot Engine" ;;
  map) godot --headless --path . -s tools/track_dump.gd -- "$2" "/tmp/$2.json" 2>&1 | grep -v Godot && python3 tools/track_map.py "/tmp/$2.json" "${3:-/tmp/$2.png}" ;;
  race) shift; godot --path . -- "$@" ;;
  *) echo "usage: $0 check|test|bench|map <id> [out.png]|race <args>" ;;
esac
