#!/usr/bin/env python3
"""T4: interactive PTY smoke test for nutsh (see PLAN.md §3a).

Drives `docker exec -it ansible.tutorial nutsh run /tutorials` through a
real pseudo-terminal, the way a human at a keyboard would. This is the only
test in the suite that exercises nutsh's interactive input/readline layer --
exactly where issues #12, #22, #25 and #37 live. `nutsh test` (T1) executes
the lesson's `expect(...)` lines programmatically and bypasses this layer
entirely, which is why Travis stayed green while these bugs existed.

Assumes the environment is already up (see tests/env.sh up).
"""
import codecs
import os
import pty
import re
import select
import signal
import subprocess
import sys
import time

CONTAINER = "ansible.tutorial"
TIMEOUT = 30


class PtySession:
    def __init__(self, cmd):
        self.master_fd, slave_fd = pty.openpty()
        self.proc = subprocess.Popen(
            cmd,
            stdin=slave_fd,
            stdout=slave_fd,
            stderr=slave_fd,
            preexec_fn=os.setsid,
            close_fds=True,
        )
        os.close(slave_fd)
        self.buffer = ""
        # Stateful decoder: a chunk boundary can land mid-character, and
        # decoding each os.read() independently would replace both the
        # truncated tail and the next chunk's orphaned continuation bytes
        # with separate U+FFFDs instead of the real character.
        self._decoder = codecs.getincrementaldecoder("utf-8")(errors="replace")

    def read_until(self, pattern, timeout=TIMEOUT):
        deadline = time.time() + timeout
        regex = re.compile(pattern)
        while time.time() < deadline:
            if regex.search(self.buffer):
                return True
            r, _, _ = select.select([self.master_fd], [], [], 0.5)
            if self.master_fd in r:
                try:
                    chunk = os.read(self.master_fd, 4096)
                except OSError:
                    break
                if not chunk:
                    break
                self.buffer += self._decoder.decode(chunk)
        return regex.search(self.buffer) is not None

    def send(self, text):
        os.write(self.master_fd, text.encode())

    def close(self):
        # setsid made this process its own group leader, so signal the
        # whole group (any local helper process docker/podman spawned in
        # it, not just the client PID) -- and always re-wait after a kill
        # so the process is actually reaped instead of left a zombie.
        try:
            pgid = os.getpgid(self.proc.pid)
        except ProcessLookupError:
            pgid = None
        if pgid is not None:
            try:
                os.killpg(pgid, signal.SIGTERM)
                self.proc.wait(timeout=5)
            except Exception:
                try:
                    os.killpg(pgid, signal.SIGKILL)
                except Exception:
                    pass
                try:
                    self.proc.wait(timeout=5)
                except Exception:
                    pass
        try:
            os.close(self.master_fd)
        except OSError:
            pass


def check(desc, ok):
    print(f"T4 [{'PASS' if ok else 'FAIL'}]: {desc}", file=sys.stderr)
    return ok


def main():
    failures = 0

    session = PtySession(["docker", "exec", "-it", CONTAINER, "nutsh", "run", "/tutorials"])
    try:
        if not check("menu appears on start", session.read_until(r"Please select a lesson")):
            failures += 1

        session.send("1\n")
        # Match the interactive bash prompt itself, NOT "~/workspace $".
        # Fases 10/12/13 chased this check as flaky-timing (fixed delay, then
        # a retry loop, then a debug dump) -- the debug dump from a real CI
        # failure finally showed the truth: the prompt DID appear, as
        # "\x1b[34m\x1b[1m~ $ \x1b[0m", but the old regex demanded the cwd be
        # "~/workspace". The lesson's make_and_go_ws does `cd /root/workspace`
        # in a run() round-trip, and on some runs the interactive prompt
        # renders before that cd has taken effect, so the prompt shows "~ $"
        # (home) rather than "~/workspace $". The shell WAS ready -- the old
        # retry loop then spammed extra "1"s straight into it
        # ("bash: 1: command not found" repeated in the dump). So this was a
        # test bug (over-specific match), not a nutsh race: send once, and
        # match the prompt generically.
        #
        # PROMPT_RE keys on the PS1's blue+bold lead-in (cli/target.go sets
        # PS1 to `\[☃\e[34m\e[1m\]\w $ ...`). That "\x1b[34m\x1b[1m" pair is
        # unique to the shell prompt: lesson text uses cyan/yellow/green
        # (36/33/32) and the lesson banner uses bare "\x1b[34m" (blue,
        # without the "\x1b[1m" bold), so neither false-matches.
        PROMPT_RE = r"\x1b\[34m\x1b\[1m[^\r\n]*\$ "
        if not check(
            "shell prompt appears after selecting a lesson (#12)",
            session.read_until(PROMPT_RE, timeout=45),
        ):
            failures += 1
            tail = session.buffer[-800:]
            print(f"T4 [DEBUG] #12 failed; last {len(tail)} chars:\n{tail!r}", file=sys.stderr)

        # #22: prove the interactive layer actually accepts and runs typed
        # input. Use a unique token echoed by the shell, not "ansible
        # --version" -- lesson 0's own instructional text literally prints
        # "ansible --version" (the command it tells you to type), so matching
        # that string was a false pass that could succeed even if the shell
        # never ran anything. `echo` of a distinctive marker only appears if
        # the shell truly executed our input.
        session.buffer = ""
        session.send("echo t4_input_marker_ok\n")
        if not check(
            "typed command is echoed back / input is captured (#22)",
            session.read_until(r"t4_input_marker_ok", timeout=20),
        ):
            failures += 1

        # 'sh' at the prompt must not crash the tokenizer (#37: "panic:
        # runtime error: slice bounds out of range" in cli/tokenizer.go).
        session.buffer = ""
        session.send("sh\n")
        session.read_until(r".", timeout=5)  # drain whatever arrives
        panicked = "panic:" in session.buffer or "slice bounds out of range" in session.buffer
        if not check("'sh' at the prompt does not panic (#37)", not panicked):
            failures += 1
        if not check("nutsh process still alive after 'sh' (#37)", session.proc.poll() is None):
            failures += 1
    finally:
        session.close()

    if failures:
        print(f"T4: {failures} check(s) failed", file=sys.stderr)
        sys.exit(1)
    print("T4: PASS", file=sys.stderr)


if __name__ == "__main__":
    main()
