# empty-repo fixture

This file's only role is to give the test suite a non-empty initial
commit when it builds an isolated sandbox by copying this directory.
The actual sandbox is recreated under `/tmp/wtt-test-$$/` per test.
