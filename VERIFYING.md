# Verifying a solution, and how safe each way is

Checking a submission asks **two independent questions**, and it is worth keeping them apart
because they have different answers, different costs, and different failure modes.

**Is the verdict right?** Did the checker that ran actually decide what the board said it would
decide? A compromised problem repository does not need to attack your computer — it can simply
edit `check.py` so that an invalid submission is accepted. Nothing is damaged, and the prize goes
to the wrong person.

**Is my machine safe?** The checker is a program, and running a program written by someone else is
running a program written by someone else.

The first question costs nothing to answer. The second costs Docker. Most people conflate them and
end up either paying for both or getting neither.

---

## The short version

```bash
# once
git clone https://github.com/math-market/getting-started.git

# every time
getting-started/preflight.sh
getting-started/run-checker.sh <check.py> <submission> --commit <pinned-sha>
```

The pinned commit is on the board, in the line that says *Criterion (pinned)*.

To skip Docker, add `--no-sandbox`. You keep the answer to the first question and give up the
second.

---

## Degrees of safety

| What you run | Verdict trustworthy | Machine protected | Needs |
|---|---|---|---|
| `python3 check.py sub.json` | **no** | no | python |
| `run-checker.sh … --commit --no-sandbox` | **yes** | no | python, git |
| `run-checker.sh … --commit` | **yes** | contained | + docker, ~1 GB |
| `preflight.sh` first, either way | — | + toolkit unmodified, dependencies pinned | git |

**Running `check.py` directly.** Fine if you have read it — they are short, and
`./audit-checker.py check.py` will show you the whole surface in one screen. But you are trusting
whatever happens to be in your working copy, which may not be what the board pinned.

**`--commit`.** Verifies the checker is byte-for-byte what the board committed to, and refuses to
run otherwise. This is cryptographic rather than procedural: someone who compromises a repository
can change `main`, but cannot change the content at a given commit without breaking git's hashing.
**A referee settling a board must always pass this.** Running the checker at `main` is the mistake
it exists to prevent.

**The sandbox.** No network, read-only filesystem, no capabilities, no privilege escalation,
bounded memory and processes, running as nobody. The checker script is mounted into a base image
pinned by digest *here*; the problem's own `Dockerfile` is never read, because a sandbox configured
by the thing it is meant to contain is not a sandbox.

**`preflight.sh`.** Checks that this toolkit is itself unmodified — these scripts apply the sandbox
and verify provenance, so a tampered copy is the one thing nothing downstream can catch — and that
any dependencies the board declares are pinned to exact versions, since they are installed with
network access before privilege is dropped.

---

## What none of this protects against

Stated plainly, because a security story with no limits listed is not one.

**A kernel exploit from inside the container.** Docker shares the host kernel. The flags above are
strong containment, not isolation. Adequate when a person runs a checker occasionally; not adequate
for a service running submissions continuously, which needs gVisor or similar.

**A compromised `getting-started`.** The trust root moved here; it did not disappear. This
repository accepts no direct pushes — not even from administrators — and every change goes through
a reviewed pull request, which is why it is a smaller target than eleven problem repositories. It
is still a target.

**Dependency installation.** `pip install` needs the network and runs before privilege is dropped.
Declarations must be pinned, and `preflight.sh` fails if they are not, so what installs cannot
change under you between runs. That is a mitigation, not an elimination.

**A checker that is honest and wrong.** Provenance proves you are running what the board committed
to. It says nothing about whether that was correct. That is what review is for.

---

## Why it is built this way

[`SECURITY.md`](SECURITY.md) gives the reasoning: the three directions of risk, why a problem
repository is never allowed to configure the sandbox that contains it, and the deliberately
weakened submission that passed every automated check except the statement comparison.

## Vetting

`vetted.json` records checkers examined for direct execution, with two deliberately separate
fields: `auditedClean`, the reproducible output of `audit-checker.py`, and `reviewedBy`, a named
person stating they read the code.

An automated audit is **not** a security boundary and does not become one by being recorded.
Static screening of a Turing-complete language loses to a determined author. What the audit is good
for is making human review cheap, and catching drift when a checker quietly grows a new capability
in a later edit.

Every entry is currently `auditedClean` with `reviewedBy: null`. The audit has run; nobody has
signed. `--no-sandbox` tells you so when you use it.
