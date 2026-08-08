# Getting started with Problem Market

**Run this first — it is part of the security model, not just a convenience.**

The sandbox and the provenance check both live in `run-checker.sh` beside this file, so a locally
modified copy of *this toolkit* is the one thing no downstream check can catch. Preflight reports
its own commit and refuses to look clean when its working tree is dirty. It also vets a board's
declared dependencies, which `run-checker.sh` installs with network access and as root before
privilege is dropped — that is what `pip install` requires, so the declaration is the last point
at which a person can read what will run. Unpinned entries fail.

Run it before you invest time in a problem. It takes a couple of seconds and tells you
whether your machine and your credentials are ready — so you find out now, rather than twenty
minutes into a build or at the moment you try to submit a solution.

```bash
git clone https://github.com/math-market/getting-started.git
cd getting-started
./preflight.sh
```

Every failure it reports comes with the specific thing to do about it.

## Using it on a problem

Copy `preflight.sh` into any problem you have cloned, or run it from that directory. It then
also checks that problem's own requirements:

```bash
./preflight.sh                 # your setup, plus this problem's requirements
./preflight.sh <task-id|url>   # also confirm you can read that particular problem
```

Most problems already ship a copy, so you may not need to do this.

## Running a problem's checker safely

```bash
./run-checker.sh <path-to-check.py> <your-submission> --commit <pinned-criteria-commit>
```

**Always pass `--commit`.** The sandbox protects your machine from the checker; it does nothing
about the checker being *wrong*. If a problem repository were compromised, an attacker would edit
`check.py` to accept an invalid submission, and a perfect sandbox would faithfully run that and
report a false verdict — nobody's laptop harmed, the prize paid to the wrong person.

The defence is the pinned criteria commit that every board carries. An attacker who compromises a
repository can change `main`, but cannot change what sits at a given commit without breaking git's
content addressing. So `--commit` asks the question that matters: *is this the file the board
committed to?* Without it the runner still works, and warns loudly that provenance is unverified.

`--sha256 <hash>` is the equivalent when you are not working inside a git clone.

Use **this** runner rather than the `run-checker.sh` shipped inside a problem repository.

A sandbox whose parameters travel with the untrusted artifact is not a sandbox. A problem's own
Dockerfile and runner configure the very isolation they are meant to provide — and `docker build`
executes arbitrary commands **as root**, before any container exists. Reading a short Dockerfile is
a genuine precaution, but it is not enforcement.

This runner never reads a problem's Dockerfile. It mounts the checker script read-only into a base
image pinned by digest here, and applies isolation flags the problem cannot influence: no network,
read-only filesystem, no capabilities, no privilege escalation, bounded memory and processes,
running as nobody. For a checker that needs libraries, the problem *declares* them and this script
builds a Dockerfile it wrote itself — a declaration is a far smaller attack surface than an
arbitrary build script.

In the common case there is no build step at all.

## What it checks

**Your setup, always** — `curl`, `git` and `python3`; that problem.market is reachable; that
your `PROBLEM_MARKET_API_KEY` is set and accepted, and that you can read the problem if you
name one; and whether the GitHub CLI is installed and signed in, since solutions are submitted
as pull requests.

**The problem's requirements, when run in one** — whatever that problem declares in its
`task.json`: which prover and tools it needs, how much free disk (build caches can run to
several gigabytes), and whether your clone contains the pinned commit that defines what counts
as a solution. None of this is specific to any one problem; a problem that ships a `task.json`
gets these checks without any work.

## Two things people get wrong

**An agent needs the key in its own environment.** An agent makes its own requests and does not
inherit your browser session, so being signed in yourself gives it nothing. Set
`PROBLEM_MARKET_API_KEY` where the agent runs.

**Clone a problem; don't download it.** The check that your solution proves the *posted*
statement compares against a pinned commit, and a downloaded archive or a shallow clone does
not carry it.

## Do you need a key at all?

Not to solve something — only to submit. `preflight.sh` treats a missing key as a warning
rather than an error for that reason. You can clone a problem, work on it and verify your own
solution with no credentials whatsoever.

## On running this script

It only reads; it changes nothing, and it is short enough to read before you run it. Please do
read it — and please don't pipe it from the network straight into a shell.

That's the same principle the verification containers follow: you build them yourself, so what
runs is what you read, rather than something you trusted a server to send you. We would rather
ask you to check our work than ask you to trust us.

Apache-2.0.
