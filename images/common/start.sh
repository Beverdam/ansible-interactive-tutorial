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
exec script -q -c "tail -f /dev/null" /dev/null
