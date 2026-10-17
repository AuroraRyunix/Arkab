#!/bin/sh
# Starts Arkab from this folder, in this terminal, without installing
# anything: to try it, or on a box you would rather not install a service on.
# install.sh, beside this file, is the other way.
#
# The data goes to ~/.arkab (or ARKAB_DATA), not into this folder: a new
# version unpacked beside the old one finds it.
set -e
here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
PORT=${PORT:-4050}
export PORT

# `./arkab.sh details [--once | --json]`: the numbers the Windows launcher's
# Details panel shows (version, uptime, CPU, memory, the queue, the servers, the boards) and the last lines of the log, in this terminal. It asks
# the Arkab already running from this data folder, through a second,
# short-lived runtime (`eval` starts nothing of the server); see
# Arkab.LauncherDetails.CLI and docs/launcher-details.md.
if [ "${1:-}" = details ]; then
  shift
  exec "$here/bin/arkab" eval "Arkab.LauncherDetails.CLI.main()" "$@"
fi

echo "Starting Arkab on http://localhost:$PORT"
echo "Data: ${ARKAB_DATA:-$HOME/.arkab}"
echo "Press Ctrl-C to stop it. The boards are not read while it is stopped."
echo
exec "$here/bin/arkab" start
