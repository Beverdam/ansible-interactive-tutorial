#!/usr/bin/env python3
"""T1 replacement: drive each lesson's real command sequence directly,
bypassing nutsh's `test` mode entirely.

Why: nutsh's test-mode interpreter has a race condition in its own PTY
tokenizer (confirmed by reading nutsh's source, `cli/cli.go` +
`parser/interpret.go` -- `QueryInteractive`'s prompt-boundary detection and
the follow-up `run("echo $?")` used by `success` don't reliably
synchronize), which panics on 13 of 15 lessons even though the driven
command visibly ran and succeeded. This is a nutsh engine bug, not a
tutorial-content bug: T4 (tests/t4_pty.py) proves the *interactive* engine
(`nutsh run`, what an actual user experiences) is unaffected. See
docs/FASE4.md.

Rather than patch/fork nutsh's Go internals, this script extracts each
lesson's real command sequence directly from its `.nutsh` source -- the
same `expect("...")` commands nutsh's own test mode would have typed -- and
runs them for real via `docker exec`, checking each command's exit code
against what the lesson's own `if [!]success && ...` guard requires. Lesson
7 ("Playbooks and failures") and lesson 8's config-test step are the two
commands in the whole suite guarded by `!success`; they still run, we just
expect them to fail.

Usage: t1_lessons.py <lesson-file-stem, e.g. 0-step-00>
"""
import re
import subprocess
import sys
from pathlib import Path

BASEDIR = Path(__file__).resolve().parent.parent
TUTORIALS = BASEDIR / "tutorials"
CONTAINER = "ansible.tutorial"

# A lesson body is a sequence of top-level setup lines (a bare `run(`cmd`)`
# call or one of the two workspace macros, each alone on its line) and
# `prompt { ... }` blocks. This mirrors exactly what nutsh's own parser
# treats as top-level statements vs. prompt bodies -- see parser/test.go's
# `annotate`/`collect_expects` in the nutsh source for the equivalent walk.
STEP_RE = re.compile(
    r"^(?P<setup>run\(`[^`]*`\)|make_and_go_ws|clear_ws)[ \t]*$"
    r"|(?P<prompt>prompt\s*\{.*?\n\})",
    re.MULTILINE | re.DOTALL,
)
NEGATE_RE = re.compile(r"if\s*!\s*success")
EXPECT_RE = re.compile(r'expect\s*\(\s*"([^"]*)"\s*\)')
SETUP_RUN_RE = re.compile(r"run\(`([^`]*)`\)")


def extract_steps(src: str):
    """Return an ordered list of (expect_failure: bool, shell_cmd: str)."""
    steps = []
    for m in STEP_RE.finditer(src):
        if m.group("setup"):
            text = m.group("setup")
            if text == "make_and_go_ws":
                steps.append((False, "mkdir -p /root/workspace && cd /root/workspace"))
            elif text == "clear_ws":
                steps.append((False, "rm -rf /root/workspace/*"))
            else:
                run_m = SETUP_RUN_RE.match(text)
                steps.append((False, run_m.group(1)))
        else:
            body = m.group("prompt")
            expect_m = EXPECT_RE.search(body)
            if not expect_m:
                continue
            cmd = expect_m.group(1)
            if cmd.strip() in ("", "done"):
                # "" is the "Please press Enter to continue" pacing block.
                # "done" is 14-freeplay's own DSL exit signal (nutsh
                # interprets it to end the free-play REPL), not a real
                # shell command -- running it via `sh -c "done"` would
                # just fail since `done` is a shell keyword, not a command.
                # Neither represents tutorial content to verify.
                continue
            steps.append((bool(NEGATE_RE.search(body)), cmd))
    return steps


def build_script(steps):
    # Executed as one script by one persistent `bash` reading from stdin
    # (see main()), *not* re-wrapped in a nested `bash -c` per step: a
    # nested shell's `cd`/env changes don't propagate back to the parent,
    # which silently broke `make_and_go_ws`'s `cd /root/workspace` -- every
    # step still "succeeded" (each ran fine from whatever directory the
    # parent script was actually in, /root), but files never landed in the
    # bind-mounted /root/workspace T7 depends on to see converged state
    # from a second, throwaway container. Commands are already
    # shell-quoted as written in the lesson source (e.g. the single quotes
    # in `ansible -m shell -a 'uname -a' ...`), so they can be inserted
    # directly as script lines.
    lines = ["set -u", "cd /root", ""]
    for i, (expect_failure, cmd) in enumerate(steps):
        escaped = cmd.replace("\\", "\\\\").replace('"', '\\"')
        lines.append(f'echo "=== step {i}: {escaped} ==="')
        lines.append(cmd)
        lines.append("rc=$?")
        if expect_failure:
            lines.append(
                f'if [ "$rc" -eq 0 ]; then echo "STEP FAILED (expected non-zero, got 0): {escaped}"; exit 1; fi'
            )
        else:
            lines.append(
                f'if [ "$rc" -ne 0 ]; then echo "STEP FAILED (rc=$rc): {escaped}"; exit 1; fi'
            )
        lines.append(f'echo "--- step {i} OK (rc=$rc) ---"')
    lines.append('echo "ALL STEPS PASSED"')
    return "\n".join(lines) + "\n"


def main():
    if len(sys.argv) != 2:
        print(f"usage: {sys.argv[0]} <lesson-file-stem>", file=sys.stderr)
        return 2
    lesson = sys.argv[1]
    path = TUTORIALS / f"{lesson}.nutsh"
    if not path.exists():
        print(f"no such lesson file: {path}", file=sys.stderr)
        return 2

    src = path.read_text()
    steps = extract_steps(src)
    if not steps:
        print(f"T1 [{lesson}]: no real commands to verify (freeplay/pacing-only lesson) -- PASS")
        return 0

    script = build_script(steps)
    proc = subprocess.run(
        ["docker", "exec", "-i", CONTAINER, "bash"],
        input=script,
        text=True,
        capture_output=True,
    )
    print(proc.stdout, end="")
    if proc.stderr:
        print(proc.stderr, end="", file=sys.stderr)

    if proc.returncode != 0 or "ALL STEPS PASSED" not in proc.stdout:
        print(f"T1 [{lesson}]: FAIL")
        return 1
    print(f"T1 [{lesson}]: PASS ({len(steps)} steps)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
