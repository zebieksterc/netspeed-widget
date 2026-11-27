#!/bin/bash
# check.sh - health check for the Netspeed Widget fork.
# Read-only: installs and changes nothing, needs no root. Takes about 3 seconds.
#
#   ./check.sh
#   ./check.sh --try   run the installed widget in a window of its own (plasmawindowed),
#                      to see that a new version does not crash before Plasma is restarted
#
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Exit code 0 = no [FAIL] line, 1 = at least one.

id=io.github.zebieksterc.netspeedwidget
# Data folder of the user. A relative XDG_DATA_HOME is ignored (as Qt does).
case "${XDG_DATA_HOME:-}" in
    /*) data=$XDG_DATA_HOME ;;
    *)  data="${HOME:?HOME is not set}/.local/share" ;;
esac
dest="$data/plasma/plasmoids/$id"
conf="${XDG_CONFIG_HOME:-$HOME/.config}/plasma-org.kde.plasma.desktop-appletsrc"

# ./check.sh --try : run the installed widget in a window of its own. It is a
# separate program (plasmawindowed), so if the widget crashes, only that window
# goes away and the desktop stays. Use it before restarting Plasma with a new version.
if [ "${1:-}" = "--try" ]; then
    try_id=io.github.zebieksterc.netspeedwidget
    if ! command -v plasmawindowed >/dev/null 2>&1; then
        echo "plasmawindowed not found (it belongs to plasma-workspace / plasma6-workspace)." >&2
        exit 1
    fi
    if [ ! -f "$data/plasma/plasmoids/$try_id/metadata.json" ]; then
        echo "The widget is not installed - run ./install.sh first." >&2
        exit 1
    fi
    echo "Starting version $(sed -n 's/.*"Version": *"\([^"]*\)".*/\1/p' "$data/plasma/plasmoids/$try_id/metadata.json" | head -n 1) in its own window."
    echo "Leave it open for half a minute, click it, open the details - then close the window."
    status=0
    plasmawindowed "$try_id" >/dev/null 2>&1 || status=$?
    if [ "$status" -eq 0 ]; then
        echo "Result: it ran and was closed normally. Safe to restart Plasma:"
        echo "  systemctl --user restart plasma-plasmashell.service"
    elif [ "$status" -ge 128 ]; then
        echo "Result: IT CRASHED (signal $((status - 128))). Do NOT restart Plasma with this version."
        echo "Go back with:  ./install.sh --list   and then   ./install.sh <last good version>"
    else
        echo "Result: it ended with status $status - please report it with this output:"
        echo "  https://github.com/zebieksterc/netspeed-widget/issues"
    fi
    # 0 only after a clean run, so that "./check.sh --try && ..." stops otherwise
    [ "$status" -eq 0 ] && exit 0
    exit 1
fi
# The folder of this script, also when it is started through a link
cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" || exit 1

problems=0; warnings=0
have()  { command -v "$1" >/dev/null 2>&1; }
head1() { printf '\n== %s ==\n' "$1"; }
ok()    { printf '  [ ok ] %s\n' "$1"; }
warn()  { printf '  [warn] %s\n' "$1"; warnings=$((warnings + 1)); }
bad()   { printf '  [FAIL] %s\n' "$1"; problems=$((problems + 1)); }
info()  { printf '         %s\n' "$1"; }
version_of() { sed -n 's/.*"Version": *"\([^"]*\)".*/\1/p' "$1" 2>/dev/null | head -n 1; }

# ------------------------------------------------------------ Plasma
head1 "Plasma"
if have plasmashell; then
    ver=$(plasmashell --version 2>/dev/null | awk '{print $2; exit}')
    ok "Plasma ${ver:-(version not reported)}"
else
    bad "plasmashell not found"
fi

# ------------------------------------------------------------- tools
head1 "Tools the widget uses"
if have kpackagetool6; then ok "kpackagetool6 (install/remove)"
else bad "kpackagetool6 missing - cannot install"; fi
if have awk; then ok "awk (reads /proc/net/dev for selected interfaces, the details popup and as fallback)"
else warn "awk missing - only the sensor mode works, the details popup lists no interfaces"; fi
if have kstart; then ok "kstart (launch application on click)"
elif have gtk-launch; then ok "gtk-launch (launch application on click; kstart not installed)"
else warn "neither kstart nor gtk-launch - launching an application on click will not work"; fi
if have ip && have qdbus6; then ok "ip + qdbus6 (middle-click copies the IP address)"
else warn "ip or qdbus6 missing - middle-click copy will not work"; fi
if have notify-send; then ok "notify-send (connection notifications)"
else warn "notify-send missing - no notifications"; fi
if have ping && have timeout; then ok "ping (optional latency display)"
else info "ping not installed - the optional latency display will not work"; fi
if have git; then ok "git (versions and rollback)"
else warn "git missing - ./install.sh <version> and updates will not work"; fi

# ------------------------------------------------------- Qt modules
head1 "Plasma modules the widget needs"
qml=""
for q in qtpaths6 qtpaths-qt6 /usr/lib64/qt6/bin/qtpaths /usr/lib/qt6/bin/qtpaths; do
    if have "$q"; then
        qml=$("$q" --query QT_INSTALL_QML 2>/dev/null)
        break
    fi
done
if [ -z "$qml" ] || [ ! -d "$qml" ]; then
    qml=/usr/lib64/qt6/qml
    for q in /usr/lib64/qt6/qml /usr/lib/qt6/qml /usr/lib/*/qt6/qml; do
        if [ -d "$q" ]; then qml=$q; break; fi
    done
fi
module() { [ -d "$qml/$1" ]; }
name()   { printf '%s' "$1" | tr / .; }
if [ ! -d "$qml" ]; then
    warn "Qt 6 QML folder not found ($qml) - the modules cannot be checked"
else
    for m in org/kde/plasma/plasmoid org/kde/plasma/core org/kde/plasma/components org/kde/kirigami; do
        if module "$m"; then ok "$(name "$m")"
        else bad "$(name "$m") missing - the widget cannot load"; fi
    done
    if module org/kde/ksysguard/sensors; then ok "org.kde.ksysguard.sensors"
    else warn "org.kde.ksysguard.sensors missing - the widget falls back to /proc/net/dev"; fi
    if module org/kde/plasma/plasma5support; then ok "org.kde.plasma.plasma5support"
    else warn "org.kde.plasma.plasma5support missing - no /proc fallback, selected interfaces, launch on click, notifications, clipboard copy, router latency or internet ping; the settings pages Data limits and Advanced cannot open"; fi
    if ! module org/kde/ksysguard/sensors && ! module org/kde/plasma/plasma5support; then
        bad "neither data source is available - the widget would always show 0"
    fi
fi

# ------------------------------------------------------ installation
head1 "Installation"
repo_ver=$(version_of package/metadata.json)
if [ -d "$dest" ]; then
    inst_ver=$(version_of "$dest/metadata.json")
    ok "installed: version ${inst_ver:-unknown}   ($dest)"
    if grep -q '^ *"KPackageStructure": *"Plasma/Applet"' "$dest/metadata.json" 2>/dev/null \
        && ! sed -n '/"KPlugin"/,$p' "$dest/metadata.json" | grep -q '"KPackageStructure"'; then
        ok "package type is declared (Plasma offers it under Add or Manage Widgets)"
    else
        bad "the package type is not declared where Plasma reads it - the widget is not offered under Add or Manage Widgets"
    fi
    if diff -rq package "$dest" >/dev/null 2>&1; then
        ok "installed files are identical to this folder (version $repo_ver)"
    elif [ "$inst_ver" != "$repo_ver" ]; then
        warn "installed version is $inst_ver, this folder has $repo_ver (rolled back, or run ./install.sh)"
    else
        warn "installed files differ from this folder although both say version $repo_ver:"
        diff -rq package "$dest" 2>&1 | sed 's/^/           /' | head -n 10
    fi
else
    bad "the fork is not installed - run ./install.sh"
fi
if [ -f "$data/applications/$id.desktop" ]; then
    ok "application entry installed (notifications stay in the notification history)"
else
    warn "application entry missing - notifications will not stay in the history (the widget puts it back when Plasma starts; or run ./install.sh)"
fi
if [ -d "$data/plasma/plasmoids/org.kde.netspeedWidget" ]; then
    info "the original Netspeed Widget is installed as well (that is fine)"
fi
if [ -d "$dest" ] && [ -r "$conf" ]; then
    n=$(grep -c -x -F "plugin=$id" "$conf")
    if [ "${n:-0}" -gt 0 ]; then ok "placed on a panel or desktop ($n time(s))"
    else warn "installed but not placed on any panel yet"; fi
fi

# ------------------------------------------------------- live data
head1 "Live data (2 second sample)"
read_proc() { # prints: name rx tx   for physical interfaces
    # A line is "<name>:<16 numbers>"; names of 6 or more characters have no
    # space in front, so the line is cut at the colon, not by field number.
    awk 'NR > 2 { i = index($0, ":"); if (i < 2) next
        n = substr($0, 1, i - 1); gsub(/[ \t]/, "", n); $0 = substr($0, i + 1)
        f = "/sys/class/net/" n "/device/uevent"
        if (n != "" && (getline l < f) >= 0) print n, $1, $9
        close(f) }' /proc/net/dev 2>/dev/null
}
physical=$(read_proc | awk '{print $1}' | xargs)
virtual=""
for d in /sys/class/net/*; do
    n=${d##*/}
    [ -e "$d" ] && [ "$n" != lo ] && [ ! -e "$d/device" ] && virtual="$virtual$n "
done
info "physical interfaces: ${physical:-none}"
info "virtual interfaces:  ${virtual:-none} (ignored unless selected in the settings)"
if [ -n "$physical" ]; then
    a=$(read_proc); sleep 2; b=$(read_proc)
    proc_rate=$(printf '%s\n%s\n' "$a" "$b" | awk '
        { if ($1 in rx) { if ($2 > rx[$1]) d += $2 - rx[$1]; if ($3 > tx[$1]) u += $3 - tx[$1] } rx[$1] = $2; tx[$1] = $3 }
        END { printf "down %.0f B/s, up %.0f B/s", d / 2, u / 2 }')
    info "/proc/net/dev:       $proc_rate (average over the sample)"
else
    warn "no physical network interface found"
fi
if have kstatsviewer; then
    # "timeout": the check must never hang if kstatsviewer keeps running
    sens=$(timeout 5 kstatsviewer network/all/download network/all/upload 2>/dev/null | awk '{print $2}' | xargs)
    if [ -n "$sens" ]; then
        read -r sens_down sens_up _ <<< "$sens"
        ok "system sensors answer"
        info "system sensors:      down ${sens_down:-?} B/s, up ${sens_up:-?} B/s (single reading)"
        info "The two lines should be of the same order while traffic is steady."
    else
        warn "system sensors gave no network data - the widget will use /proc/net/dev"
    fi
else
    info "kstatsviewer not installed - cannot read the sensors from the command line"
fi

# -------------------------------------------------------------- log
head1 "Messages since login"
if have journalctl; then
    # The widget's own warnings, and QML errors that name one of its files
    msgs=$(journalctl --user -b --no-pager -o cat 2>/dev/null | grep -F -e "Netspeed Widget:" -e "$id" | tail -n 5)
    if [ -n "$msgs" ]; then
        warn "the journal has messages from or about the widget:"
        printf '%s\n' "$msgs" | cut -c1-300 | sed 's/^/           /'
    else
        ok "none"
    fi
else
    warn "journalctl not available"
fi

# ---------------------------------------------------------- summary
head1 "Summary"
if [ "$problems" -gt 0 ]; then
    echo "  $problems problem(s), $warnings warning(s) - see the [FAIL] lines above."
elif [ "$warnings" -gt 0 ]; then
    echo "  No problems, $warnings warning(s) - see the [warn] lines above."
else
    echo "  Everything looks fine."
fi
echo
[ "$problems" -eq 0 ]
