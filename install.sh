#!/bin/bash
# Installs the Netspeed Widget fork for the current user.
#
#   ./install.sh          install the version in this folder
#   ./install.sh v3.1     install another version from the git history (rollback)
#   ./install.sh --list   list the available versions
#
# v3.1 and older are the original widget; they install under the original
# name (org.kde.netspeedWidget), next to the fork.
#
# Writes below ~/.local/share/plasma/plasmoids (through kpackagetool6), the notification entry
# ~/.local/share/applications/io.github.zebieksterc.netspeedwidget.desktop (then refreshes the
# application cache with kbuildsycoca6), and a temporary folder (an older version, or the backup
# of the installed one) that is removed at the end.
#
# SPDX-License-Identifier: GPL-2.0-or-later
set -e -o pipefail

# This script and its folder, also when it is started through a link
self=$(readlink -f -- "${BASH_SOURCE[0]}")
here=$(dirname -- "$self")
cd -- "$here"

usage() { sed -n '2,9s/^# \{0,1\}//p' "$self"; }
die()   { echo "$*" >&2; exit 1; }

# Data folder of the user. A relative XDG_DATA_HOME is ignored (as Qt does).
case "${XDG_DATA_HOME:-}" in
    /*) data=$XDG_DATA_HOME ;;
    *)  data="${HOME:?HOME is not set}/.local/share" ;;
esac
src=package
tmp=""
cleanup() { [ -z "$tmp" ] || rm -rf -- "$tmp"; }
trap cleanup EXIT

need_git() {
    command -v git >/dev/null 2>&1 || die "git is not installed - only ./install.sh (this folder) works without it."
    git rev-parse --git-dir >/dev/null 2>&1 \
        || die "This folder is not a git repository (unpacked from an archive?) - only ./install.sh (this folder) works here."
}

[ "$#" -le 1 ] || { usage >&2; exit 1; }

case "${1:-}" in
    -h|--help)
        usage
        exit 0 ;;
    --list)
        need_git
        git tag --sort=version:refname --format='%(refname:short)  %(contents:subject)'
        exit 0 ;;
    "") ;;
    -*)
        echo "Unknown option: $1" >&2
        usage >&2
        exit 1 ;;
    *)
        need_git
        git rev-parse --verify --quiet "$1^{commit}" >/dev/null \
            || die "Unknown version: $1   (see ./install.sh --list)"
        # Take the widget files of that version without touching this folder
        tmp=$(mktemp -d)
        git archive --format=tar "$1" package 2>/dev/null | tar -x -C "$tmp" 2>/dev/null \
            || die "Version $1 has no widget files (no \"package\" folder) - not installed."
        src="$tmp/package"
        echo "Using the widget files of $1"
        ;;
esac

if [ ! -f "$src/metadata.json" ]; then
    if [ -n "$tmp" ]; then
        die "Version $1 has no metadata.json (too old for Plasma 6) - not installed."
    fi
    die "$here/package/metadata.json not found - is this the complete widget folder?"
fi
id=$(sed -n 's/.*"Id": *"\([^"]*\)".*/\1/p' "$src/metadata.json" | head -n 1)
[ -n "$id" ] || die "No \"Id\" found in $src/metadata.json - not installed."
# The Id becomes a folder name: accept nothing that could point elsewhere
case "$id" in
    .*|*[!A-Za-z0-9._-]*) die "Unexpected widget Id \"$id\" in $src/metadata.json - not installed." ;;
esac

command -v kpackagetool6 >/dev/null 2>&1 \
    || die "kpackagetool6 not found. It belongs to KDE's KPackage (the package is usually called kf6-kpackage or kpackage)."
if [ "$(id -u)" -eq 0 ]; then
    die "Do not run this as root or with sudo - the widget is installed for your own user."
fi

dest="$data/plasma/plasmoids/$id"

# Application entry: lets Plasma keep the widget's notifications in the history
# (only for the fork; the original widget does not use it)
entry="io.github.zebieksterc.netspeedwidget.desktop"
install_entry() {
    # taken from the version that is being installed
    if [ "$id" = "io.github.zebieksterc.netspeedwidget" ] && [ -f "$src/contents/data/$entry" ]; then
        if ! { mkdir -p -- "$data/applications" && cp -- "$src/contents/data/$entry" "$data/applications/"; }; then
            echo "Note: could not install the application entry - notifications will not stay in the history." >&2
            return 0
        fi
        if command -v kbuildsycoca6 >/dev/null 2>&1; then
            kbuildsycoca6 >/dev/null 2>&1 || true
        fi
    fi
}

# Remove + install instead of "upgrade", so going back to an older version works too
if [ -d "$dest" ]; then
    # Keep a copy, so a failed install does not leave you without the widget
    [ -n "$tmp" ] || tmp=$(mktemp -d)
    cp -a -- "$dest" "$tmp/previous"
    if ! kpackagetool6 --type Plasma/Applet --remove "$id"; then
        # The original widget does not declare its package
        # type, so kpackagetool6 cannot find it to remove it. The folder is
        # this widget's own, so remove it directly.
        case "$dest" in
            */plasma/plasmoids/"$id")
                if [ -f "$dest/metadata.json" ]; then
                    echo "kpackagetool6 could not remove the old version; removing its folder directly."
                    rm -rf -- "$dest"
                fi ;;
        esac
        if [ -e "$dest" ]; then
            echo "Could not remove the installed version in $dest - nothing was changed." >&2
            exit 1
        fi
    fi
    if ! kpackagetool6 --type Plasma/Applet --install "$src"; then
        if [ ! -e "$dest" ] && mkdir -p -- "$(dirname -- "$dest")" && cp -a -- "$tmp/previous" "$dest"; then
            die "Installing failed (see the message above). The previously installed version was put back."
        fi
        die "Installing failed (see the message above) and the previous version is no longer installed."
    fi
    install_entry
    echo
    echo "Replaced the installed version of $id. Restart Plasma to load it:"
    echo "  systemctl --user restart plasma-plasmashell.service"
else
    kpackagetool6 --type Plasma/Applet --install "$src" \
        || die "Installing failed (see the message above)."
    install_entry
    echo
    echo "Installed $id. Add it to a panel: right-click the panel >"
    echo "Add or Manage Widgets > search for \"Netspeed\"."
fi
