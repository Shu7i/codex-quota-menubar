#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/quota-countdown-check.XXXXXX")"
trap 'rm -rf "$CHECK_DIR"' EXIT
cat > "$CHECK_DIR/CountdownCheck.swift" <<'SWIFT'
import Foundation
@main struct CountdownCheck {
 static func main() {
  let now = Date(timeIntervalSince1970: 1000000)
  func value(_ seconds: Double, _ days: Bool = false) -> String {
   QuotaSnapshot.countdown(until: now.addingTimeInterval(seconds), now: now, allowsDays: days)
  }
  precondition(value(4 * 3600) == "4h0m")
  precondition(value(2 * 3600 + 55 * 60) == "2h55m")
  precondition(value(2 * 3600 + 55 * 60 + 59) == "2h55m")
  precondition(value(35 * 60) == "35min")
  precondition(value(3 * 86400, true) == "3Day")
  precondition(value(86399, true) == "23h59m")
  precondition(value(3600, true) == "1h0m")
  precondition(value(3599) == "59min")
  precondition(value(59) == "1min")
  precondition(value(0) == "0min" && value(-10) == "0min")
  precondition(QuotaSnapshot.countdown(until: nil, now: now, allowsDays: true) == "--")
  print("Countdown boundary checks passed")
 }
}
SWIFT
swiftc -o "$CHECK_DIR/check" "$CHECK_DIR/CountdownCheck.swift" \
  "$ROOT_DIR/Sources/CodexQuotaBar/Models/QuotaSnapshot.swift" \
  "$ROOT_DIR/Sources/CodexQuotaBar/Support/Formatters.swift"
"$CHECK_DIR/check"
