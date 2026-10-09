#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h:h}"
TESTDIR=$(mktemp -d /private/tmp/native-taskmanager-tests.XXXXXX)
xcrun clang -O2 "$ROOT/Tests/MetricsTests.c" "$ROOT/Native/Metrics.c" -o "$TESTDIR/metrics"
"$TESTDIR/metrics"
xcrun swiftc -parse-as-library -module-cache-path "$TESTDIR/cache" "$ROOT/Sources/GraphGeometry.swift" "$ROOT/Tests/GraphTests.swift" -o "$TESTDIR/graphs"
"$TESTDIR/graphs"

xcrun swiftc -parse-as-library -module-cache-path "$TESTDIR/cache" "$ROOT/Sources/MenuGadgetLayout.swift" "$ROOT/Tests/MenuGadgetTests.swift" -o "$TESTDIR/gadgets"
"$TESTDIR/gadgets"
