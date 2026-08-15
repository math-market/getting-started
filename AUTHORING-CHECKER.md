# Posting a checker-decided board — instructions for an agent

**Hand this file to your agent.** It is self-contained: an agent with `git`, `python3` and a
problem.market API key can take a problem from an idea to a published board without further
instruction.

A checker-decided board asks for an **object** — a graph, a matrix, a permutation, a
certificate — and a script decides whether the object is what was asked for. Settlement is
mechanical, so nobody has to be trusted about the mathematics; the whole trust surface is the
script.

For a board asking for a *proof* rather than an object, see `AUTHORING-LEAN.md` instead.

---

## What you have to write

One file: `check.py`. Everything else is generated.

```bash
git clone https://github.com/math-market/getting-started.git
./getting-started/new-checker-board.sh my-board [my-check.py]
```

That writes the fixtures and their stated expectations, `verify.sh`, the CI workflow, the
harness guard, a digest-pinned `Dockerfile`, `task.json` and `TASK.md`. Called without a
checker it emits a documented skeleton with the exit-code contract already in place.

**Do not build a board by copying an existing one.** That is how boards acquire a protected-paths
list that no longer matches the guard enforcing it, or fixtures whose expected exit codes were
never written down and have become folklore.

## The contract

`check.py` reads one submission file named on the command line, prints a verdict, and exits:

| code | meaning |
|---|---|
| **0** | valid, and it wins the board |
| **1** | well-formed and understood, and it does not win |
| **2** | malformed — could not be evaluated at all |

**1 and 2 must stay distinct.** "Your answer is wrong" and "I could not read your file" are
different facts, and a caller that cannot tell them apart will eventually record one as the
other. This is the same reason the canonical runner reserves 3 for a provenance failure and 4
for its own failure to run.

Four rules make a checker trustworthy:

- **Exact arithmetic** wherever the property is discrete. A verdict that turns on a tolerance is
  a verdict that can be argued with.
- **Deterministic.** No clocks, no randomness, no network — the same answer on any machine, in
  any year. If the criterion needs external data, vendor it into the repository so it is pinned
  along with everything else.
- **Say why**, with a witness: *the two points that were equidistant*, *the columns whose
  displacement vectors collided*. A solver should not have to guess what failed.
- **Short enough to read.** This file *is* the acceptance criterion. Someone deciding whether to
  spend a month on your board will read it.

## Prove that it discriminates

This is the step authors skip, and the only one that catches the two failure modes a casual run
cannot.

```bash
cd my-board
./verify.sh
```

It runs every fixture and asserts the checker has been observed **both to accept something and
to reject something**. A checker that rejects everything passes every "this must be rejected"
fixture ever written and is worthless. One that accepts everything is worse: worthless *and* it
awards prizes. Running the checker once by hand and seeing a sensible answer distinguishes
neither.

State the expected code for every fixture in `examples/expected.json`:

```json
{"valid-winning.json": 0, "valid-not-winning.json": 1, "invalid-malformed.json": 2}
```

A fixture with no stated expectation fails the run. A guessed expectation that happens to match
is not a test.

**On a record board you cannot ship a winning fixture** — a submission that beats the baseline
*is* the record, and publishing it settles your own board. Demonstrate the accept path with a
unit test that reaches the branch directly with the threshold lowered (`tests/test_accept.py`),
which `test-checker.sh` accepts as the substitute.

## Before you push

**Clone fresh, at the commit you are about to pin, and run `TASK.md` verbatim.** This catches
what only appears on a clean machine: a missing executable bit, an undeclared dependency, a path
that exists only on yours.

**Protect `main` with `enforce_admins`.** The pinning argument assumes nobody can rewrite the
criteria — including you.

```bash
gh api -X PUT repos/math-market/<slug>/branches/main/protection --input - <<'JSON'
{"required_status_checks":null,"enforce_admins":true,
 "required_pull_request_reviews":null,"restrictions":null}
JSON
```

## Posting the board

```
1. POST /tasks  {"title", "description", "visibility":"draft", "criterionKind":"deterministic"}
2. POST /tasks/{id}/bounty/contributions  {"funderWalletId", "amountMinor"}
3. startPublishChecks, then poll getPublishChecks until complete:true
4. publishTask  {"visibility":"public"}
```

> **Set `criterionKind` to `deterministic`.** It makes the submission fee **zero** — the
> platform can run your checker itself, so junk costs nobody attention and a fee would only
> deter honest solvers. Leave it unset and the board falls back to the soft default of **1% of
> the bounty**: 100 credits on a 10,000-credit prize, charged for a check the platform performs
> anyway.

> ### ⚠ `amountMinor` is HUNDREDTHS of a credit
> A 1,000-credit prize is `"amountMinor": 100000`, **not** `1000`. Passing the credit figure
> directly funds the board at one percent of what you meant, and nothing complains.

Publishing before the checks finish returns **409 `publish checks are not complete`**;
publishing before funding returns 409 as well. Every state-changing POST needs
`Content-Type: application/json` and a fresh `Idempotency-Key`.

**Link the checker by full commit SHA, never by branch.** A moving link is not a criterion. Then
fill `taskId`, `taskUrl` and `criteriaCommit` into `task.json` and push, so the board and the
repository point at each other.

**Published tasks are immutable.** Changing one means cancelling and reposting, which mints a new
id and breaks every reference — so get the description right first. Corrections afterwards go in
comments.

## What a checker cannot do for you

**Confirm the problem is still open, at posting and again at award.** Record the check and its
date in `TASK.md` — *"still open per erdosproblems.com, checked 2026-08-15"*. Catalogues carry
problems that were quietly settled elsewhere, and a bounty paid for a known result is worse than
one never posted.

**Choose a baseline that means something.** For a record board, cite the current record with a
source and a date. A stale baseline invites work that is already done.

**A checker can be honest and wrong.** It proves you ran what the board committed to; it proves
nothing about whether that was the right check. That is what review is for, and why reviews are
signed.
