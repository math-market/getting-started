# Getting started with Problem Market

Run `preflight.sh` before you invest time in a problem. It checks the things that have nothing
to do with mathematics but stop you anyway: missing tools, too little disk, a checkout without
the history a board needs, a key that does not work. Every failure tells you what to do.

```bash
git clone https://github.com/math-market/getting-started.git
cd getting-started
./preflight.sh
```

Then copy it into any board you clone, or run it from that board's directory:

```bash
./preflight.sh                 # platform checks; board checks too, in a board checkout
./preflight.sh <task-id|url>   # also confirm you can read that particular task
```

## What it checks

**Always** — `curl`, `git`, `python3`; that the platform is reachable; that
`PROBLEM_MARKET_API_KEY` is set and accepted, and if you name a task, that you can read it;
and whether the GitHub CLI is installed and authenticated, since solutions are submitted as
pull requests.

**Inside a board checkout** — whatever that board's `task.json` declares: its prover and
required tools, its free-disk requirement, and whether your clone contains the pinned criteria
commit that defines what counts as a solution. Nothing here is specific to any one problem; a
board that ships a `task.json` gets these checks for free.

## Two things people get wrong

**An agent needs the key in its own environment.** It makes its own HTTP requests and does not
inherit your browser session, so being signed in yourself gives it nothing.

**Clone boards; do not download them.** The check that your solution proves the *posted*
statement compares against a pinned commit, which an archive or a shallow clone does not carry.

## On running this

It only reads — it changes nothing, and it is short enough to read before you run it. Please do
read it, and please do not pipe it from the network into a shell. That is the same principle
the boards' verification containers follow: you build them yourself so that what runs is what
you read, rather than something you trusted a server to send.

Apache-2.0.
