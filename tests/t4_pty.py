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
        # The prompt is drawn as "~/workspace $ " wrapped in ANSI color
        # codes (which continue past the "$"), so anchoring on end-of-buffer
        # is unreliable -- match the literal prompt text instead.
        #
        # Fase 5: bumped 20s -> 45s after a GitHub Actions run failed here
        # with no code change anywhere on this test's execution path (the
        # ansible-tutorial image and this file were byte-identical to the
        # immediately preceding run, which passed) -- shared-runner PTY/
        # container-startup variance, not a functional regression.
        if not check(
            "shell prompt appears after selecting a lesson (#12)",
            session.read_until(r"workspace \$", timeout=45),
        ):
            failures += 1

        session.buffer = ""
        session.send("ansible --version\n")
        if not check(
            "typed command is echoed back / input is captured (#22)",
            session.read_until(r"ansible --version", timeout=20),
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
