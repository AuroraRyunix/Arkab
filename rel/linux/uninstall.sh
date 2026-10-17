#!/bin/sh
# Removes the Arkab program from a box installed with install.sh.
#
#   sudo /opt/arkab/uninstall.sh
#
# It removes the service, its units and /opt/arkab. It does NOT remove the
# data, the service's settings or the user that owns the data: the queue, the servers' keys
# and the captures are still there when Arkab is
# installed again, and they are yours to delete. The last lines say how.

set -eu

INSTALL_DIR="/opt/arkab"
DATA_DIR="/var/lib/arkab"
UNIT_DIR="/etc/systemd/system"

main() {
    [ "$(id -u)" = 0 ] || { echo "run this as root: sudo $0" >&2; exit 1; }

    for unit in arkab-update.path arkab-update.service arkab.service; do
        systemctl disable --now "$unit" >/dev/null 2>&1 || true
        rm -f "$UNIT_DIR/$unit"
    done
    systemctl daemon-reload || true

    # The program, and what the updater noted about its last run. Nothing
    # else: the two paths are spelled out so that no variable can be empty.
    rm -rf /opt/arkab
    rm -rf /var/lib/arkab-update

    echo "Arkab is removed from $INSTALL_DIR."
    echo "Your data is untouched, in $DATA_DIR, and so are the settings in /etc/arkab."
    echo "Installing Arkab again finds both."
    echo "To delete the data for good - there is no way back - that is yours to do:"
    echo "  the folder $DATA_DIR, the folder /etc/arkab, and the user 'arkab'."
}

main "$@"
