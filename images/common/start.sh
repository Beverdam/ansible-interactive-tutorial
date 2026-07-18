#!/bin/sh
service ssh start > /dev/null || exit 1

# ALLOW_EXIT=false keeps re-spawning the login shell instead of letting the
# container exit when it's closed (e.g. an interactive `docker exec` shell
# accidentally exiting shouldn't kill the managed host). Compared against
# the literal string "true"/"false" explicitly, rather than executing the
# value as a command (the previous `while ! "${ALLOW_EXIT}"` idiom relied on
# "true"/"false" happening to also be real shell builtins/commands, and
# would error on any other value).
while [ "${ALLOW_EXIT}" != "true" ]; do
    script -q -c "/bin/bash -l" /dev/null
done
script -q -c "/bin/bash -l" /dev/null

# Plain `tail`, not `script -c tail`: this becomes PID 1, and its process
# name matters. Ansible's service-manager fact detection reads PID 1's comm
# to guess the init system; wrapped in `script` here, PID 1's comm was
# literally "script", which ansible-core's detection logic apparently
# matches as a (bogus) service-manager identifier -- every `service:`
# module task then fails with "module (script) is missing interpreter
# line". `tail -f /dev/null` needs no pty of its own (it's not
# interactive), so the wrapper was unnecessary anyway.
exec tail -f /dev/null
