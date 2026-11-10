#!/bin/sh
# Compiles the logic tests with the app target's concurrency settings and runs them.
set -e
cd "$(dirname "$0")/.."
out="${TMPDIR:-/tmp}/iforgor-logic-tests"
xcrun swiftc -parse-as-library -default-isolation MainActor -swift-version 5 \
  iForgor/GoogleTasksAPI.swift iForgor/TasksModel.swift iForgor/GoogleAccount.swift \
  iForgor/Keychain.swift iForgor/GoogleConfig.swift iForgor/Reminders.swift \
  Tests/LogicTests.swift -o "$out"
"$out"
