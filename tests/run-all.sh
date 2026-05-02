#!/usr/bin/env bash
# run-all.sh — entry point for the toolkit's test suite.
set -u

failures=0

for test_script in \
  tests/test-install.sh \
  tests/test-setup.sh \
  tests/test-cleanup.sh
do
  if bash "$test_script"; then
    :
  else
    failures=$((failures + 1))
  fi
done

if [[ "$failures" -eq 0 ]]; then
  echo "PASS tests/run-all.sh"
else
  echo "FAIL tests/run-all.sh ($failures failing scripts)"
fi

exit "$failures"
