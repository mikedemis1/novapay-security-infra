# KQL lab: execution record

**Status: executed and verified.**

- Date: 2026-09-14 (queries run 2026-09-13 23:24-23:42 UTC per ADX result timestamps, which
  use the cluster's clock; the fixture data itself is dated 2026-09-13).
- Cluster: `novapay-kql-lab` (free cluster, North Europe region, `kvc-djces1h2df1v0x95z5.northeurope.kusto.windows.net`).
- Database: `NovaPaySecurityLab`. Table: `SecurityEventsV1`, created fresh, no prior data.
- Signup required a personal Microsoft account only. No Azure subscription, credit card,
  or payment detail was requested anywhere in the free-cluster route.

## K1 data checks (`queries/02-data-checks.kql`)

| Check | Expected | Actual | Pass |
|---|---|---|---|
| Row/null count | Rows=14, InvalidTime=0, InvalidMfa=0 | Rows=14, InvalidTime=0, InvalidMfa=0 | Yes |
| Duplicate EventId | 0 rows | No Rows To Show | Yes |
| Distinct EventId count | 14 | 14 | Yes |
| Ordered listing | matches CSV exactly | matches CSV exactly (E01-E14, all fields) | Yes |

## K2 investigation queries (`queries/01-investigations.kql`)

| Query | Expected | Actual | Pass |
|---|---|---|---|
| Q1 | 8 rows: E01-E05, E07, E08, E10 | 8 rows: E01-E05, E07, E08, E10 | Yes |
| Q2 | 1 row: alice, 192.0.2.10, 10:00 UTC, Failures=5 | 1 row: alice, 192.0.2.10, 10:00, Failures=5 | Yes |
| Q3 | alice/192.0.2.10/5/10:04/10:05/E06; bob/192.0.2.20/2/10:02/10:03/E09 | Same, both rows | Yes |
| Q4 | 1 row: E12, erin, 192.0.2.50, 10:06 UTC | 1 row: E12, erin, 192.0.2.50, 10:06 | Yes |
| Q5 | 1 row: E14, admin-lab, AttachUserPolicy, 10:08 UTC | 1 row: E14, admin-lab, AttachUserPolicy, 10:08 | Yes |

Threshold negative case: Q2 with `Failures >= 6` instead of `>= 5`, same fixture, same
window, returned **No Rows To Show**, as expected. The scratch query was not saved; the
stored query in `01-investigations.kql` still uses the threshold of 5.

Exports saved as `evidence/q1.csv` through `q5.csv`, transcribed from the ADX result
grids screenshotted during the run.

## Practice status

**Conceptual understanding confirmed, independent exercise explicitly deferred.**

The user answered three concept questions correctly, without generated code:
1. Why E11 (09:59) is excluded from Q1's window (fails `EventTime >= Start`).
2. Why two failure bursts either side of a 5-minute bin boundary (e.g. 3+3 across
   10:03-10:04 and 10:05-10:06) would be counted separately by Q2 and each miss the
   threshold, even though they total 6 failures in 3 elapsed minutes.
3. A legitimate, non-malicious explanation for a failure-then-success pattern (mistyped
   password, then correct), plus the extra context needed before escalating (whether the
   actor/IP is normal for that user).

The independent exercise itself (write and run a new query for each actor's count of
successful `ConsoleLogin` events in the window) was **not attempted**. The user made an
explicit, informed decision to skip it now: applications go out with roughly a 2-3 week
wait for a reply before any interview, and intends to study KQL more intensively in that
window rather than write one query today. This is a deferral, not a completed exercise.

Per the parent plan's own K3 acceptance rule, this keeps the artifact verified while
leaving T3.3's independent-question criterion open. It does not block the CV wording
below, which claims practice with the concepts actually demonstrated (filters,
aggregation, joins), not a claim of unsupervised query authorship.
