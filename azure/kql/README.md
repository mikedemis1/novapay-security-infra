# Introductory KQL investigation lab

## Scope and status

**Status as of 2026-09-14: executed and verified in Azure Data Explorer (ADX).** All
data checks and Q1-Q5 matched their expected results exactly, including the threshold-6
negative case. Full record in `evidence/execution.md`. This is a training exercise on
invented data, not a real incident or a production log source. The independent
practice exercise (write a new query unaided) was deferred by the user's own decision
for further study before interviews; the concept questions were answered correctly.

## Synthetic schema

`fixtures/security-events.csv` holds 14 invented `ConsoleLogin`, `CreateAccessKey` and
`AttachUserPolicy` events across five fictional actors. This is a custom normalized
training schema, written for this lab. It is not an authentic CloudTrail export or an
Entra `SigninLogs` table, and no real identities, IPs or credentials appear in it.

## Free setup and ingestion

1. Create or reuse an ADX free cluster via Microsoft's
   [free-cluster route](https://learn.microsoft.com/en-us/azure/data-explorer/start-for-free-web-ui)
   (the **My Cluster** link, not the Azure Portal paid-provision flow). No subscription
   or card should be required for this route.
2. Database `NovaPaySecurityLab`, table `SecurityEventsV1` (or `V2` if `V1` already
   holds unrelated data in a reused cluster).
3. Run `queries/00-create-table.kql` by itself in the query editor.
4. Ingest `fixtures/security-events.csv` with **Get data / Local file**, mapping the
   header row and checking the `datetime`/`bool` column types in the preview before
   confirming, per
   [Microsoft's file-ingestion guide](https://learn.microsoft.com/en-us/azure/data-explorer/get-data-file).
5. Run `queries/02-data-checks.kql`, one block at a time, and confirm 14 rows, 14
   unique event IDs, no null timestamps or booleans, and that the ordered listing
   matches the CSV exactly.

## Running each query

`queries/01-investigations.kql` holds five independently selectable blocks (Q1-Q5).
Select one block's full text, from its `let` statements to its final operator, and
run it alone. The blocks repeat their own time bounds on purpose so each is
self-contained; a fixed UTC window is used instead of `ago()` so a replay on a later
date does not change the result.

## Expected versus actual

Expectations are in `expected-results.md`, written before execution. Actual results
and pass/fail per query go in `evidence/execution.md`, with exports `evidence/q1.csv`
through `q5.csv`.

## Limits

- Q2 uses aligned five-minute bins, not a sliding window; two failures on each side of
  a bin boundary can be missed even though they occurred within five elapsed minutes.
- Q3 groups failures across the whole selected interval and compares against the last
  failure only, so it can miss an earlier success if later failures also occurred.
- Actor/IP equality is a correlation clue, not proof; none of these queries prove
  compromise.
- `MfaUsed=false` is an explicit synthetic field in this fixture, not something
  inferred from a missing value.
- Q5 has no policy document attached and cannot say whether the attached policy
  grants administrative privileges.

## Practice status

Recorded in `evidence/execution.md` once run: whether the user completed the
independent exercise (each actor's count of successful `ConsoleLogin` events in the
window, sorted by actor) without generated code.

## Official sources

- https://learn.microsoft.com/en-us/azure/data-explorer/start-for-free-web-ui
- https://learn.microsoft.com/en-us/azure/data-explorer/start-for-free
- https://learn.microsoft.com/en-us/azure/data-explorer/get-data-file
- https://learn.microsoft.com/en-us/kusto/query/tutorials/join-data-from-multiple-tables?view=microsoft-fabric
