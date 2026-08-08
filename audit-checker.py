#!/usr/bin/env python3
"""audit-checker.py — report what a checker script can do.

    ./audit-checker.py path/to/check.py

This exists to make *review* cheap, not to replace it. It parses the file and
reports every import, every construct that could reach outside the process, and
how long the file is — so a person deciding whether a checker is safe to run
without a sandbox can see the whole surface at a glance instead of reading for
side effects.

**It is not a security boundary, and must not be used as one.** Static screening
of a Turing-complete language loses to a determined author: `getattr` chains,
encoded strings and dynamic imports defeat any allowlist, and every published
"safe Python subset" has been broken. That argument is in
`verification-security.md` §2 and it still stands.

What makes this useful anyway is that it is pointed at *our own* checkers —
written and reviewed by us, not supplied by an adversary optimising against the
audit. Here it does two honest jobs: it summarises the surface for a human
reviewer, and it catches drift, so a checker that quietly grows a network call
in some later edit shows up.

Exit codes: 0 nothing outside the expected surface · 1 something to look at ·
2 the file could not be parsed.
"""
import ast, sys, pathlib

# Modules a pure checker needs: parse input, do exact arithmetic, report.
EXPECTED_IMPORTS = {
    "json", "sys", "math", "itertools", "fractions", "decimal", "collections",
    "functools", "re", "typing", "dataclasses", "argparse", "pathlib",
}
# Present in some checkers for good reasons; called out so a reviewer sees them.
NOTABLE_IMPORTS = {"sympy", "numpy"}

REACHES_OUT = {
    "eval": "evaluates a string as code",
    "exec": "executes a string as code",
    "compile": "compiles a string to code",
    "__import__": "imports a module chosen at run time",
    "input": "reads from stdin",
    "breakpoint": "drops into a debugger",
}
REACHES_OUT_MODULES = {
    "os": "the operating system", "subprocess": "other processes",
    "socket": "the network", "urllib": "the network", "requests": "the network",
    "http": "the network", "shutil": "the filesystem", "tempfile": "the filesystem",
    "ctypes": "arbitrary memory", "pickle": "arbitrary object construction",
    "multiprocessing": "other processes", "importlib": "dynamic imports",
}

def main():
    if len(sys.argv) != 2:
        print("usage: audit-checker.py <check.py>"); sys.exit(2)
    path = pathlib.Path(sys.argv[1])
    try:
        src = path.read_text()
        tree = ast.parse(src, filename=str(path))
    except Exception as e:
        print(f"could not parse {path}: {e}"); sys.exit(2)

    imports, findings, writes = set(), [], []
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for a in node.names: imports.add(a.name.split(".")[0])
        elif isinstance(node, ast.ImportFrom):
            if node.module: imports.add(node.module.split(".")[0])
        elif isinstance(node, ast.Call):
            fn = node.func
            name = fn.id if isinstance(fn, ast.Name) else (
                   fn.attr if isinstance(fn, ast.Attribute) else None)
            if isinstance(fn, ast.Name) and fn.id in REACHES_OUT:
                findings.append((node.lineno, fn.id, REACHES_OUT[fn.id]))
            if name == "open":
                mode = "r"
                for i, a in enumerate(node.args):
                    if i == 1 and isinstance(a, ast.Constant): mode = str(a.value)
                for kw in node.keywords:
                    if kw.arg == "mode" and isinstance(kw.value, ast.Constant):
                        mode = str(kw.value.value)
                if any(c in mode for c in "wax+"):
                    writes.append((node.lineno, mode))
            if isinstance(fn, ast.Name) and fn.id == "getattr" and len(node.args) > 1:
                if not isinstance(node.args[1], ast.Constant):
                    findings.append((node.lineno, "getattr",
                                     "attribute name computed at run time"))

    print(f"\n  {path}  —  {len(src.splitlines())} lines\n")

    unexpected = sorted(imports - EXPECTED_IMPORTS - NOTABLE_IMPORTS)
    notable = sorted(imports & NOTABLE_IMPORTS)
    print("  imports")
    for m in sorted(imports & EXPECTED_IMPORTS): print(f"    ok        {m}")
    for m in notable: print(f"    notable   {m}  (third-party; must be pinned in task.json)")
    for m in unexpected:
        why = REACHES_OUT_MODULES.get(m, "not in the expected set")
        print(f"    LOOK      {m}  — reaches {why}" if m in REACHES_OUT_MODULES
              else f"    LOOK      {m}  — {why}")

    print("\n  constructs")
    if findings:
        for ln, what, why in findings: print(f"    LOOK      line {ln}: {what} — {why}")
    else:
        print("    ok        no eval/exec/compile/dynamic import/stdin")
    if writes:
        for ln, mode in writes: print(f"    LOOK      line {ln}: open(..., {mode!r}) — writes to disk")
    else:
        print("    ok        opens nothing for writing")

    bad = unexpected or findings or writes
    print()
    if bad:
        print("  Something here is outside the surface a checker normally needs.")
        print("  That is not a verdict — read the lines above and decide.\n")
        sys.exit(1)
    print("  Nothing outside the expected surface: reads its argument, computes,")
    print("  prints a verdict. Still worth reading; it is short.\n")
    sys.exit(0)

if __name__ == "__main__":
    main()
