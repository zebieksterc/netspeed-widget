#!/bin/bash
# Removes the Netspeed Widget fork. Remove the widget from the panel first.
#
#   ./uninstall.sh              remove the fork
#   ./uninstall.sh --original   remove the original widget (installed by ./install.sh v3.1)
#
# Your settings of the widget stay in ~/.config/plasma-org.kde.plasma.desktop-appletsrc
# until the widget is removed from the panel.
#
# SPDX-License-Identifier: GPL-2.0-or-later
set -e

case "${1:-}" in
    "")         id=io.github.zebieksterc.netspeedwidget ;;
    --original) id=org.kde.netspeedWidget ;;
    *)          sed -n '2,5s/^# \{0,1\}//p' "$(readlink -f -- "${BASH_SOURCE[0]}")" >&2; exit 1 ;;
esac

# Data folder of the user. A relative XDG_DATA_HOME is ignored (as Qt does).
case "${XDG_DATA_HOME:-}" in
    /*) data=$XDG_DATA_HOME ;;
    *)  data="${HOME:?HOME is not set}/.local/share" ;;
esac

# The fork's application entry (used for its notifications); removed first, so it
# does not stay behind when the widget itself was already removed another way
if [ "$id" = "io.github.zebieksterc.netspeedwidget" ]; then
    rm -f -- "$data/applications/$id.desktop"
fi

if [ ! -d "$data/plasma/plasmoids/$id" ]; then
    echo "$id is not installed for this user - nothing to do."
    exit 0
fi
if ! command -v kpackagetool6 >/dev/null 2>&1; then
    echo "kpackagetool6 not found - cannot remove $id." >&2
    exit 1
fi
if ! kpackagetool6 --type Plasma/Applet --remove "$id"; then
    # The original widget does not declare its package type,
    # so kpackagetool6 cannot find it. Remove the widget's own folder directly.
    folder="$data/plasma/plasmoids/$id"
    if [ -f "$folder/metadata.json" ]; then
        echo "kpackagetool6 could not remove it; removing its folder directly."
        rm -rf -- "$folder"
        echo "Removed $folder"
    else
        exit 1
    fi
fi
echo "Removed $id."
