# KQL lab: expected results

All values below are expected, written before execution, for `azure/kql/queries/01-investigations.kql`
against `azure/kql/fixtures/security-events.csv`. All times refer to 2026-09-13.
Compare full fields, not only counts.

| Query | Exact expected result | Negative case |
|---|---|---|
| Q1 | 8 rows: E01-E05, E07, E08, E10 | E11 is outside the time window; E06 is a success |
| Q2 | 1 row: alice, 192.0.2.10, 10:00 UTC, Failures=5 | bob has only 2; carol only 1 |
| Q3 | alice / 192.0.2.10 / 5 / 10:04 / 10:05 / E06; bob / 192.0.2.20 / 2 / 10:02 / 10:03 / E09 | erin has no preceding failures; carol has no success |
| Q4 | 1 row: E12, erin, 192.0.2.50, 10:06 UTC | successful alice/bob logins have MFA=true |
| Q5 | 1 row: E14, admin-lab, AttachUserPolicy, 10:08 UTC | E13 is Denied, so it did not create a key |

Threshold negative case: changing Q2's threshold from 5 to 6 in a scratch copy must return zero rows.

Actual results, once run, go in `evidence/execution.md` and `evidence/q1.csv` through `q5.csv`.
This file records expectations only; it is not proof of execution.
