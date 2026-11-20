#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h:h}"
TESTDIR=$(mktemp -d "${TMPDIR:-/private/tmp}/native-taskmanager-tests.XXXXXX")
xcrun clang -std=c11 -Wall -Wextra -Werror -O2 "$ROOT/Tests/CPUDeltaTests.c" -o "$TESTDIR/cpudelta"
"$TESTDIR/cpudelta"
xcrun clang -O2 "$ROOT/Tests/MetricsTests.c" "$ROOT/Native/Metrics.c" -o "$TESTDIR/metrics"
xcrun clang -O2 "$ROOT/Tests/SuspendTests.c" "$ROOT/Native/Metrics.c" -o "$TESTDIR/suspend"
"$TESTDIR/suspend"
"$TESTDIR/metrics"
xcrun swiftc -parse-as-library -module-cache-path "$TESTDIR/cache" "$ROOT/Sources/GraphGeometry.swift" "$ROOT/Tests/GraphTests.swift" -o "$TESTDIR/graphs"
xcrun swiftc -parse-as-library -module-cache-path "$TESTDIR/cache" "$ROOT/Sources/ProcessGrouping.swift" "$ROOT/Tests/GroupingTests.swift" -o "$TESTDIR/grouping"
"$TESTDIR/grouping"
"$TESTDIR/graphs"

xcrun swiftc -parse-as-library -module-cache-path "$TESTDIR/cache" "$ROOT/Sources/MenuGadgetLayout.swift" "$ROOT/Tests/MenuGadgetTests.swift" -o "$TESTDIR/gadgets"
"$TESTDIR/gadgets"
