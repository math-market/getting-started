# How verification is protected, and what we do not claim

Problem Market decides who wins a prize by running code. That makes the code, and the things
around it, worth being careful about — and worth explaining rather than asserting.

This is the reasoning. [`VERIFYING.md`](VERIFYING.md) is the practical version: which command to
run and what each one buys you.

---

## The claim we are actually making

**What counts as a solution is fixed before anyone starts work, and anyone can check afterwards
that we applied it.**

Not "our verdicts are correct." Not "our checkers are bug-free." The narrower claim is the one we
can support, and everything below exists to support it.

## Three directions of risk, not one

It is tempting to think of this as protecting ourselves from bad submissions. That is one
direction of three, and the least neglected.

**You run our code.** We ask you to run a checker against your work before submitting. That is us
asking a stranger to execute our program on their machine. If our repository were compromised, or
a checker written carelessly, the harm lands on you.

**We run your code.** Programs are executed to check their output; Lean proofs are built, and
building Lean is arbitrary code execution.

**A submission attacks the judging, not the judge.** The most valuable attack is not to break a
machine but to change the standard — to alter the checker, the build, or the statement so that
work which should fail is accepted. This is the direction most easily overlooked, and the one
that matters most for a platform that awards prizes.

## What we do about each

### You should not have to trust us

**A checker runs in a sandbox you control, from a base image pinned here, and we never read the
problem's own container definition.** The canonical runner in this repository mounts the checker
script into an image *it* chooses. A problem repository cannot configure the isolation that
contains it — because a sandbox whose parameters travel with the untrusted artifact is not a
sandbox.

For a checker needing libraries, the problem *declares* them as data and the container definition
is one we write. A declaration is a far smaller thing to read than a build script.

**And you can check the checker before running it.** `audit-checker.py` reports every import and
every construct that reaches outside the process, so the whole surface fits on one screen. It is
not a security boundary — static screening of a Turing-complete language loses to a determined
author — but it makes reading cheap, which is the real defence.

### The standard cannot move under you

**Every criterion is pinned to a commit hash.** A task links the exact version of the checker or
statement it will be judged against. Git identifies commits by a fingerprint of their contents, so
nobody — not the repository owner, not us, not GitHub — can alter what a hash refers to.

**And the runner enforces it.** `run-checker.sh --commit <sha>` refuses to run a checker that is
not byte-for-byte what the board committed to. Someone who compromised a repository could change
its main branch; they could not change the content at a pinned commit without breaking the
hashing. **A referee settling a board is required to pass this**, because running the checker at
`main` is precisely the mistake it prevents.

### A submission may not edit what judges it

Criteria repositories reject any pull request touching the build configuration, the checker, the
runner, or the workflows. That check runs from the *base branch* rather than from the pull
request, so a submission cannot delete the check that would have caught it. Fork workflows require
release by a maintainer before they run at all, on the same reasoning.

## The finding that shaped this

We built a deliberately weakened submission to test our own gates: a theorem with an extra
hypothesis making it trivially true, proved honestly in one line.

**It passed every automated check we had.** Green build against pinned Mathlib. No `sorry`. No
declared axiom. Axiom report exactly the three foundations Mathlib itself rests on. Only one check
rejected it — the comparison of the submitted statement against the pinned one.

The lesson generalises past Lean, and it is why the statement comparison exists at all: **a green
build and a clean axiom report establish that the submitter proved something honestly. They say
nothing about what.** Formal verification moves all of the trust onto the statement, which was the
one thing nothing was checking. And it is precisely the attack a non-expert reviewer cannot catch
by eye, since it is one line in a signature they may not read.

## What we do not claim

Stated plainly, because a security story with no limits listed is not one.

**Containers are not a boundary against a kernel exploit.** Docker shares the host kernel. The
constraints we apply are strong containment, not isolation. Adequate when a person runs a checker
occasionally; not adequate for a service running submissions continuously, which is a change we
would have to make before running checks server-side.

**The trust root moved; it did not disappear.** You now trust this repository instead of every
problem repository separately. That is a real improvement — one small repository that accepts no
direct pushes, where every change goes through review, including ours. It is still a root.

**Dependency installation reaches the network as root.** Installing a declared library requires
it. Declarations must be pinned to exact versions and `preflight.sh` fails if they are not, so
what installs cannot change between two runs of the same board. That is a mitigation, not an
elimination.

**A checker can be honest and wrong.** Provenance proves you ran what the board committed to. It
proves nothing about whether that was the right check. That is what review is for, and why
reviews are signed.

**Faithfulness is not mechanical.** Whether a formal statement means what its informal description
claims cannot be decided by any script, because there is no formal object called "the informal
statement" to compare against. It is a judgement, made by a named person, recorded in the review.
We would rather say so than imply a rigour we do not have.

## If you find a problem

**Please tell us: security@aletheai.org.** We will credit you by name in the record unless you
prefer otherwise, and we will publish what was wrong and what we changed — the same way we publish
everything else.

We do not run a bug bounty and are not inviting attacks. This document exists because a
verification platform that will not explain its verification is not worth trusting, not as a
challenge. The stakes are worth being honest about: prizes here are non-convertible credits with
no cash value, there is no user data worth taking, and the most an exploit achieves is a wrong
verdict on a mathematics problem — which we would rather hear about than have demonstrated.

If you are the sort of person who reads a page like this and starts probing: the interesting work
is on the boards.

## Checking any of this for yourself

Nothing above requires taking our word.

```bash
git clone https://github.com/math-market/getting-started.git
cd getting-started
./preflight.sh                 # verifies this toolkit is unmodified
cat run-checker.sh             # ~120 lines; the sandbox and the provenance check
./audit-checker.py <check.py>  # what a given checker can do
```

The criteria repositories are public, their histories are complete, and every pinned commit can be
fetched and hashed. If something here is wrong, it is checkable that it is wrong — which is the
property we are actually trying to have.
