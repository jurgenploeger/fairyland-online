#!/bin/sh
# Prints the error lines of an xcodebuild log as GitHub annotations, so a failed CI step says why
# without opening the full log. Usage: tools/ci_errors.sh build/archive.log
log="$1"
grep -E '(^|: )error:|error: |\*\* (ARCHIVE|EXPORT) FAILED|No profiles|No signing certificate|requires a provisioning profile|not authorized|401|403' "$log" \
  | sort -u | head -20 | while IFS= read -r line; do echo "::error::$line"; done
echo "--- last 40 lines of $log ---"
tail -40 "$log"
