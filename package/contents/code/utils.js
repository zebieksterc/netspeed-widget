/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 *
 * Based on utils.js of Netspeed Widget 3.1, Copyright 2016 Daniel Faust <hessijames@gmail.com>.
 * Modified 2026 for the fork (io.github.zebieksterc.netspeedwidget); see ChangeLog.
 *
 * Helper functions of the Netspeed Widget fork. Pure JavaScript, no QML types,
 * so everything here is tested with node (tests/helpers.test.js).
 *
 * In this order:
 *   reading /proc/net/dev    NET_DATA_SOURCE, parseTransferData, calcSpeedData, interfaceShown
 *   formatting               formatSpeed, unitLabel, formatTotal
 *   shell                    launchCommand, shellQuote
 *   connection state         isConnected, wirelessInterface, linkInterface
 *   graph and usage          pushSample, pad2, dayKey, monthKey, cleanStartDay, periodStart, periodKey,
 *                            usageNumber, USAGE_HISTORY_MONTHS, USAGE_MAX_INTERFACES, isMonthKey,
 *                            cleanHistory, cleanTotals, catchUpTotals, rollUsage, loadUsage, addUsage,
 *                            addInterfaceUsage
 *   data limits              MAX_LIMITS, parseLimits, cleanLimitStates, resetLimitState, rollLimits,
 *                            addLimitUsage, resetLimit, limitStatus, panelLimits
 *   limit helpers, resets    resetUsage, limitStage, limitHue, formatGiB,
 *                            USAGE_PLAUSIBLE_RATE, usageDelta
 *   small commands           cleanHost, routerAddress, pingCommand, parsePing, DESKTOP_ENTRY, localPath,
 *                            desktopEntryCommand, escapeHtml,
 *                            internetHost, copyIpCommand, copyTextCommand, notifyCommand, cleanIp
 *
 * Every text that ends up in a shell command goes through shellQuote or cleanHost.
 * cleanIp checks the answer of the external-IP service before it is shown or copied.
 */

// One process per reading. Output per interface:
//   name,rxBytes,txBytes,physical,wireless,operstate
// "physical" is 1 when the interface is backed by a real device (it has a
// /sys/class/net/<name>/device entry) and 0 for virtual ones (VPN, bridge,
// Docker, ...). "wireless" is 1 for Wi-Fi. "operstate" is up, down, unknown, ...
//
// A line of /proc/net/dev is "<name>:<16 numbers>". The name is right-aligned
// to 6 characters, so short names have spaces in front and names of 6 or more
// characters have none: the line is cut at the colon, never by field number.
// Only reads files; works with gawk, mawk and busybox awk.
const NET_DATA_SOURCE =
    "awk -v OFS=, 'NR > 2 { i = index($0, \":\"); if (i < 2) next;" +
    " n = substr($0, 1, i - 1); gsub(/[ \\t]/, \"\", n); if (n == \"\") next; $0 = substr($0, i + 1);" +
    " b = \"/sys/class/net/\" n;" +
    " f = b \"/device/uevent\"; p = ((getline l < f) >= 0) ? 1 : 0; close(f);" +
    " w = 0; f = b \"/uevent\"; while ((getline l < f) > 0) if (l == \"DEVTYPE=wlan\") w = 1; close(f);" +
    " o = \"unknown\"; f = b \"/operstate\"; if ((getline l < f) > 0) o = l; close(f);" +
    " print n, $1, $9, p, w, o }' /proc/net/dev";

// Output of NET_DATA_SOURCE -> { name: { rx, tx, physical, wireless, operstate } }.
// The loopback interface and damaged lines are left out.
function parseTransferData(data) {
    const transferData = {};

    for (const line of String(data === undefined || data === null ? '' : data).split("\n")) {
        const parts = line.trim().split(",");
        if (parts.length < 6) {
            continue;
        }
        // The five values are taken from the end, so a comma in the name does no harm
        const [rx, tx, physical, wireless, operstate] = parts.slice(-5);
        const name = parts.slice(0, -5).join(",");
        const rxBytes = Number(rx);
        const txBytes = Number(tx);

        // Lines that are not "name,number,number,..." (cut off output) are skipped:
        // a NaN here would end up in the speed and in the usage counters
        if (!name || name === "lo" || rx === "" || tx === "" || !(rxBytes >= 0) || !(txBytes >= 0)) {
            continue;
        }

        transferData[name] = {
            rx: rxBytes,
            tx: txBytes,
            physical: physical === "1",
            wireless: wireless === "1",
            operstate: operstate || "unknown",
        };
    }

    return transferData;
}

// Speeds in bytes per second. duration is in milliseconds.
function calcSpeedData(prevTransferData, nextTransferData, duration) {
    const speedData = {};

    for (const key in nextTransferData) {
        const next = nextTransferData[key];
        const prev = prevTransferData ? prevTransferData[key] : undefined;
        let down = 0;
        let up = 0;

        if (prev && duration > 0) {
            // A counter that went backwards means the interface was recreated
            // (VPN reconnect, modem, ...): show 0 for this interval, not a negative speed
            down = Math.max(0, next.rx - prev.rx) * 1000 / duration;
            up = Math.max(0, next.tx - prev.tx) * 1000 / duration;
        }

        speedData[key] = {
            down: down,
            up: up,
            downTotal: next.rx,
            upTotal: next.tx,
            physical: next.physical,
            wireless: next.wireless,
            operstate: next.operstate,
        };
    }

    return speedData;
}

// Which interfaces count: the selected ones, or all physical ones
function interfaceShown(name, entry, whitelistEnabled, whitelist) {
    if (whitelistEnabled) {
        // Array.from: the setting arrives as a list object; a plain string would
        // otherwise match parts of names
        return Array.from(whitelist || []).indexOf(name) !== -1;
    }
    return !!(entry && entry.physical);
}

// value: bytes per second. units: 'bits' or 'bytes'.
// Returns { number: '12.3', tier: 0..3 }; tier 0 = b/B, 1 = k/Ki, 2 = M/Mi, 3 = G/Gi.
// The next unit is used from 999.5 on (what would be shown as 1000), so the
// number never needs more than 4 digits. The tier does not depend on
// showLowSpeeds or decimals, so separate calls for number and unit agree.
// decimals: 0 or 1 (default 1).
function formatSpeed(value, units, showLowSpeeds, decimals) {
    const bits = units === 'bits';
    const step = bits ? 1000 : 1024;
    let tier = 0;

    value = Number(value);
    if (!(value > 0) || !isFinite(value)) {
        value = 0;
    }
    if (bits) {
        value *= 8;
    }
    while (tier < 3 && value >= 999.5) {
        value /= step;
        tier++;
    }

    if (tier === 0 && !showLowSpeeds) {
        value = 0;
    }

    return { number: value.toFixed(decimals === 0 ? 0 : 1), tier: tier };
}

// Unit text for a size step (0 = bytes or bits, 1 = kilo, 2 = mega, 3 = giga): "kb/s", "MiB/s", or just "k", "M"
function unitLabel(tier, units, shortUnits) {
    tier = Math.min(3, Math.max(0, Math.round(Number(tier)) || 0));
    if (units === 'bits') {
        return shortUnits ? ['b', 'k', 'm', 'g'][tier] : ['b/s', 'kb/s', 'Mb/s', 'Gb/s'][tier];
    }
    return shortUnits ? ['B', 'K', 'M', 'G'][tier] : ['B/s', 'KiB/s', 'MiB/s', 'GiB/s'][tier];
}

// Amount of data in bytes -> '1.2 GiB'. Whole bytes below 1 KiB ('512 B').
function formatTotal(value) {
    const units = ['B', 'KiB', 'MiB', 'GiB', 'TiB'];
    let tier = 0;

    value = Number(value);
    if (!(value > 0) || !isFinite(value)) {
        value = 0;
    }
    // 1023.95 would be shown as '1024.0': use the next unit instead
    while (tier < units.length - 1 && value >= 1023.95) {
        value /= 1024;
        tier++;
    }

    return (tier === 0 ? String(Math.round(value)) : value.toFixed(1)) + ' ' + units[tier];
}

// 'org.kde.konsole.desktop' -> shell command that starts the application
function launchCommand(menuId) {
    const id = String(menuId).replace(/\.desktop$/, '');
    const quoted = shellQuote(id);
    return 'kstart --application ' + quoted + ' 2>/dev/null || gtk-launch ' + quoted;
}

// Wraps a text in single quotes for the shell, so nothing in it is interpreted as a command
function shellQuote(text) {
    return "'" + String(text).replace(/'/g, "'\\''") + "'";
}

// ---- connection state ------------------------------------------------------

// True when at least one counted interface is up. "unknown" counts as up:
// virtual interfaces (VPN, bridge) and many USB network adapters and tethered
// phones never report a state, and the kernel documents "unknown" as usable.
// An interface that is switched off or has no cable or network reports "down".
function isConnected(transferData, whitelistEnabled, whitelist) {
    for (const name in transferData) {
        const entry = transferData[name];
        if (!interfaceShown(name, entry, whitelistEnabled, whitelist)) {
            continue;
        }
        if (entry.operstate === "up" || entry.operstate === "unknown") {
            return true;
        }
    }
    return false;
}

// Name of the first Wi-Fi interface that is up, or ''
function wirelessInterface(transferData) {
    let fallback = '';
    for (const name in transferData) {
        if (transferData[name].wireless) {
            if (transferData[name].operstate === "up") {
                return name;
            }
            fallback = fallback || name;
        }
    }
    return fallback;
}

// Interface the widget names on its own line: the Wi-Fi interface when it is up,
// else the first wired physical interface that is up (or reports no state), or ''
function linkInterface(transferData) {
    let wired = '';
    for (const name in transferData) {
        const entry = transferData[name];
        if (!entry.physical) {
            continue;
        }
        if (entry.wireless && entry.operstate === "up") {
            return name;
        }
        if (!entry.wireless && wired === '' && (entry.operstate === "up" || entry.operstate === "unknown")) {
            wired = name;
        }
    }
    return wired;
}

// ---- graph and usage -------------------------------------------------------

// Returns a new array with value appended and at most max entries
function pushSample(samples, value, max) {
    const next = max > 1 ? samples.slice(-(max - 1)) : [];   // slice(-0) would keep everything
    next.push(value);
    return next;
}

// 7 -> "07"
function pad2(n) {
    return (n < 10 ? '0' : '') + n;
}

// Name of a day: "2026-11-27"
function dayKey(date) {
    return date.getFullYear() + '-' + pad2(date.getMonth() + 1) + '-' + pad2(date.getDate());
}

// Name of a calendar month: "2026-11"
function monthKey(date) {
    return date.getFullYear() + '-' + pad2(date.getMonth() + 1);
}

// Day of the month on which the counted "month" starts: 1 to 28
function cleanStartDay(day) {
    const n = Math.round(Number(day));
    return n >= 1 && n <= 28 ? n : 1;
}

// First day of the counting period the date lies in. With start day 15 the
// period of 27 November began on 15 November, that of 3 November on 15 October.
function periodStart(date, startDay) {
    const day = cleanStartDay(startDay);
    return new Date(date.getFullYear(), date.getMonth() - (date.getDate() < day ? 1 : 0), day);
}

// Name of that period: year and month of its first day, "2026-11"
function periodKey(date, startDay) {
    return monthKey(periodStart(date, startDay));
}

// A byte count that can be trusted: a finite number from 0 to 2^53, else 0
function usageNumber(v) {
    return (typeof v === 'number' && v >= 0 && v <= Number.MAX_SAFE_INTEGER) ? v : 0;
}

// Past months kept in the usage object
const USAGE_HISTORY_MONTHS = 12;
// Interfaces counted separately at most (old names must not pile up for ever)
const USAGE_MAX_INTERFACES = 16;

// True for a month name like "2026-11"
function isMonthKey(v) {
    return typeof v === 'string' && /^[0-9]{4}-[0-9]{2}$/.test(v);
}

// List of past months [{ month, down, up, day }], oldest first, cleaned (day = the start day then in use)
function cleanHistory(list) {
    const months = {};
    if (Array.isArray(list)) {
        for (const item of list) {
            if (item !== null && typeof item === 'object' && isMonthKey(item.month)) {
                months[item.month] = { month: item.month, down: usageNumber(item.down), up: usageNumber(item.up),
                                       day: cleanStartDay(item.day) };
            }
        }
    }
    return Object.keys(months).sort().map(key => months[key]).slice(-USAGE_HISTORY_MONTHS);
}

// Counters of a usage object, valid for the given date. A new day or month
// starts its counter at zero; the month that ended goes to the history.
// Besides the totals the object carries: history (past months), limits (the
// counters of the data limits) and ifaces (the same counters per interface,
// with the last byte counters seen).
// startDay: the day of the month a new period begins (1 = calendar month).
// Saved position of the byte counters of all connections -> { key, down, up } or null.
// key names what was added up ('sensors', or 'proc:' + the interface names).
function cleanTotals(totals) {
    if (totals === null || typeof totals !== 'object' || typeof totals.key !== 'string'
            || totals.key === '' || totals.key.length > 400) {
        return null;
    }
    return { key: totals.key, down: usageNumber(totals.down), up: usageNumber(totals.up) };
}

// What all connections transferred while the widget was not running (Plasma
// restarted, crashed, or was not started yet): the byte counters now, compared
// with where they stood at the last save. Same rule as for one interface in
// addInterfaceUsage: a counter that is lower than the saved one started again
// from zero (reboot), then the counter itself is what was transferred since.
// Returns { down, up, matched }, or null while the counters have not been
// delivered yet (ask again at the next reading). Nothing is added when there is
// no saved position, or when it belongs to other counters (key differs:
// matched is false then, and the caller may wait a little for the right ones).
function catchUpTotals(saved, current) {
    current = cleanTotals(current);
    if (current === null || (current.down <= 0 && current.up <= 0)) {
        return null;
    }
    saved = cleanTotals(saved);
    if (saved === null) {
        return { down: 0, up: 0, matched: true };
    }
    if (saved.key !== current.key) {
        return { down: 0, up: 0, matched: false };
    }
    return {
        down: current.down >= saved.down ? current.down - saved.down : current.down,
        up: current.up >= saved.up ? current.up - saved.up : current.up,
        matched: true,
    };
}

function rollUsage(saved, date, startDay) {
    if (saved === null || typeof saved !== 'object') {
        saved = {};
    }
    const today = dayKey(date);
    const month = periodKey(date, startDay);
    const sameDay = saved.day === today;
    const sameMonth = saved.month === month;

    let history = cleanHistory(saved.history);
    if (isMonthKey(saved.month) && saved.month < month
            && usageNumber(saved.monthDown) + usageNumber(saved.monthUp) > 0) {
        history = cleanHistory(history.concat([{ month: saved.month, down: saved.monthDown, up: saved.monthUp, day: saved.startDay }]));
    }

    const ifaces = {};
    if (saved.ifaces !== null && typeof saved.ifaces === 'object') {
        let count = 0;
        for (const name of Object.keys(saved.ifaces)) {
            const entry = saved.ifaces[name];
            if (count >= USAGE_MAX_INTERFACES || !/^[A-Za-z0-9_.-]{1,15}$/.test(name)
                    || entry === null || typeof entry !== 'object') {
                continue;
            }
            ifaces[name] = {
                dayDown: sameDay ? usageNumber(entry.dayDown) : 0,
                dayUp: sameDay ? usageNumber(entry.dayUp) : 0,
                monthDown: sameMonth ? usageNumber(entry.monthDown) : 0,
                monthUp: sameMonth ? usageNumber(entry.monthUp) : 0,
                rx: usageNumber(entry.rx),
                tx: usageNumber(entry.tx),
            };
            ++count;
        }
    }

    return {
        day: today,
        dayDown: sameDay ? usageNumber(saved.dayDown) : 0,
        dayUp: sameDay ? usageNumber(saved.dayUp) : 0,
        month: month,
        startDay: cleanStartDay(startDay),
        monthDown: sameMonth ? usageNumber(saved.monthDown) : 0,
        monthUp: sameMonth ? usageNumber(saved.monthUp) : 0,
        history: history,
        // counters of the data limits; each has its own period (see rollLimits)
        limits: cleanLimitStates(saved.limits),
        ifaces: ifaces,
        // where the byte counters of all connections stood at the last save (see catchUpTotals)
        totals: cleanTotals(saved.totals),
    };
}

// Stored usage (JSON text) -> counters valid for the given date
function loadUsage(json, date, startDay) {
    let saved = {};
    try {
        saved = JSON.parse(json || '{}');
    } catch (e) {
        saved = {};
    }
    return rollUsage(saved, date, startDay);
}

// Adds bytes to the counters; rolls over at midnight / month end.
// Negative or not-a-number amounts add nothing (they must never damage the counters).
function addUsage(usage, down, up, date, startDay) {
    const next = rollUsage(usage, date, startDay);
    down = usageNumber(down);
    up = usageNumber(up);
    next.dayDown += down;
    next.dayUp += up;
    next.monthDown += down;
    next.monthUp += up;
    return next;
}

// Counts traffic per interface from the byte counters of the interface list
// (name -> { rx, tx, physical, ... }). Returns { usage, changed, bytes }
// (bytes: name -> what was counted now, for the data limits).
// The first reading of an interface only stores its counters. A counter that
// is lower than the stored one started again from zero (restart, driver
// reload): then the counter itself is what was transferred since.
function addInterfaceUsage(usage, info, date, startDay) {
    const next = rollUsage(usage, date, startDay);
    let changed = false;
    const bytes = {};       // name -> bytes counted now (for the data limits)
    for (const name in info) {
        const entry = info[name];
        if (!entry || !entry.physical || !/^[A-Za-z0-9_.-]{1,15}$/.test(name)) {
            continue;
        }
        const rx = usageNumber(entry.rx);
        const tx = usageNumber(entry.tx);
        const prev = next.ifaces[name];
        if (prev === undefined) {
            if (Object.keys(next.ifaces).length < USAGE_MAX_INTERFACES) {
                next.ifaces[name] = { dayDown: 0, dayUp: 0, monthDown: 0, monthUp: 0, rx: rx, tx: tx };
                changed = true;
            }
            continue;
        }
        const down = rx >= prev.rx ? rx - prev.rx : rx;
        const up = tx >= prev.tx ? tx - prev.tx : tx;
        if (down > 0 || up > 0 || rx !== prev.rx || tx !== prev.tx) {
            prev.dayDown += down;
            prev.dayUp += up;
            prev.monthDown += down;
            prev.monthUp += up;
            prev.rx = rx;
            prev.tx = tx;
            changed = true;
            bytes[name] = down + up;
        }
    }
    return { usage: next, changed: changed, bytes: bytes };
}

// ---- data limits (several, each for all connections or for one interface) ------

const MAX_LIMITS = 8;

// The list of limits from the settings (JSON text) -> clean list of
// { id, iface, limit (GiB), day (1-28), usedTenths (already used, tenths of a GiB) }
function parseLimits(json) {
    let list = [];
    try {
        list = JSON.parse(json || '[]');
    } catch (e) {
        list = [];
    }
    const out = [];
    const seen = {};
    if (Array.isArray(list)) {
        for (const item of list) {
            if (out.length >= MAX_LIMITS || item === null || typeof item !== 'object') {
                continue;
            }
            const id = String(item.id || '');
            const iface = String(item.iface || '');
            const limit = Number(item.limit);
            if (!/^[A-Za-z0-9]{1,12}$/.test(id) || seen[id] || !(limit > 0) || !isFinite(limit)
                    || (iface !== '' && !/^[A-Za-z0-9_.-]{1,15}$/.test(iface))) {
                continue;
            }
            seen[id] = true;
            const used = Math.round(Number(item.usedTenths));
            out.push({ id: id, iface: iface, limit: limit, day: cleanStartDay(item.day),
                       usedTenths: used > 0 && used <= 10000000 ? used : 0 });
        }
    }
    return out;
}

// Stored counters of the limits: id -> { period, used, notified, offset, applied }
// applied = the "already used" figure (tenths) that was last taken over from the settings
function cleanLimitStates(saved) {
    const out = {};
    if (saved !== null && typeof saved === 'object' && !Array.isArray(saved)) {
        let count = 0;
        for (const id of Object.keys(saved)) {
            const e = saved[id];
            if (count >= MAX_LIMITS || !/^[A-Za-z0-9]{1,12}$/.test(id) || e === null || typeof e !== 'object') {
                continue;
            }
            out[id] = {
                period: isMonthKey(e.period) ? e.period : '',
                used: usageNumber(e.used),
                notified: e.notified === 80 || e.notified === 100 ? e.notified : 0,
                offset: usageNumber(e.offset),
                applied: usageNumber(e.applied),
            };
            ++count;
        }
    }
    return out;
}

// A limit's counters set back to zero; its period and the start value already taken over stay
function resetLimitState(e) {
    return { period: e.period, used: 0, notified: 0, offset: 0, applied: e.applied };
}

// Brings the counters of the limits up to date: starts a new period on its
// day, takes over a changed "already used" figure, forgets removed limits.
// Returns { usage, cleared }: cleared lists the ids whose "already used" figure
// ended with its period - the settings should show 0 for them again.
function rollLimits(usage, limits, date) {
    const states = {};
    const cleared = [];
    for (const cfg of limits) {
        const key = periodKey(date, cfg.day);
        let e = usage.limits ? usage.limits[cfg.id] : undefined;
        if (e === undefined) {
            e = { period: key, used: 0, notified: 0, offset: 0, applied: 0 };
        } else if (e.period !== key) {
            e = { period: key, used: 0, notified: 0, offset: 0, applied: e.applied };
            if (e.applied > 0 && e.applied === cfg.usedTenths) {
                cleared.push(cfg.id);       // the figure belonged to the period that ended
            }
        } else {
            e = { period: e.period, used: e.used, notified: e.notified, offset: e.offset, applied: e.applied };
        }
        if (cfg.usedTenths !== e.applied && cleared.indexOf(cfg.id) === -1) {
            e.offset = cfg.usedTenths / 10 * 1024 * 1024 * 1024;
            e.applied = cfg.usedTenths;
        }
        states[cfg.id] = e;
    }
    return { usage: Object.assign({}, usage, { limits: states }), cleared: cleared };
}

// Adds traffic to the limits. bytes: { '': all connections, name: one interface }
function addLimitUsage(usage, limits, bytes, date) {
    const rolled = rollLimits(usage, limits, date);
    for (const cfg of limits) {
        const add = usageNumber(bytes[cfg.iface]);
        if (add > 0) {
            rolled.usage.limits[cfg.id].used += add;
        }
    }
    return rolled;
}

// One limit set back to zero (button in the settings)
function resetLimit(usage, id) {
    const states = Object.assign({}, usage.limits);
    if (states[id] !== undefined) {
        states[id] = resetLimitState(states[id]);
    }
    return Object.assign({}, usage, { limits: states });
}

// What the widget shows for each limit:
// [{ id, iface, limit, used (bytes, with the start value), offset, fraction, hue, stage, notified }]
function limitStatus(usage, limits) {
    const out = [];
    for (const cfg of limits) {
        const e = (usage && usage.limits && usage.limits[cfg.id]) || { used: 0, offset: 0, notified: 0 };
        const used = usageNumber(e.used) + usageNumber(e.offset);
        const fraction = used / (cfg.limit * 1024 * 1024 * 1024);
        out.push({ id: cfg.id, iface: cfg.iface, limit: cfg.limit, used: used, offset: usageNumber(e.offset),
                   fraction: fraction, hue: limitHue(fraction), stage: limitStage(fraction), notified: e.notified || 0 });
    }
    return out;
}

// Which limits get a line in the panel. mode 'all', 'none' or 'auto': the limit
// of the connection in use (and a limit that counts all connections).
function panelLimits(status, mode, activeInterface) {
    if (mode === 'none') {
        return [];
    }
    if (mode === 'all') {
        return status;
    }
    return status.filter(s => s.iface === '' || (activeInterface !== '' && s.iface === activeInterface));
}

// ---- limit helpers and resets ------------------------------------------------

// Sets counters back to zero. what: 'today', 'month', 'limits' (the counters,
// warnings and start values of all data limits),
// 'history' or 'all'. The byte counters last
// seen per interface are kept, so nothing is counted twice afterwards.
function resetUsage(usage, what, date, startDay) {
    const next = rollUsage(usage, date, startDay);
    const today = what === 'today' || what === 'all';
    const month = what === 'month' || what === 'all';
    if (today) {
        next.dayDown = 0;
        next.dayUp = 0;
    }
    if (month) {
        next.monthDown = 0;
        next.monthUp = 0;
    }
    for (const name in next.ifaces) {
        if (today) {
            next.ifaces[name].dayDown = 0;
            next.ifaces[name].dayUp = 0;
        }
        if (month) {
            next.ifaces[name].monthDown = 0;
            next.ifaces[name].monthUp = 0;
        }
    }
    if (what === 'history' || what === 'all') {
        next.history = [];
    }
    if (what === 'limits' || what === 'all') {
        for (const id in next.limits) {
            next.limits[id] = resetLimitState(next.limits[id]);
        }
    }
    return next;
}

// Warning stage of a fraction: 0, 80 or 100
function limitStage(fraction) {
    return fraction >= 1 ? 100 : fraction >= 0.8 ? 80 : 0;
}

// Colour of a fraction as a hue in degrees: green (120) up to half of the
// limit, then step by step through yellow and orange to red (0) at the limit
function limitHue(fraction) {
    if (!(fraction > 0.5)) {
        return 120;
    }
    return fraction >= 1 ? 0 : Math.round(120 * (1 - fraction) / 0.5);
}

// "14.3" for a byte count in GiB
function formatGiB(bytes) {
    return (usageNumber(bytes) / (1024 * 1024 * 1024)).toFixed(1);
}

// How many bytes to count for one interval.
// delta: change of the byte counter; speed/prevSpeed: bytes per second at the
// two ends of the interval; seconds: its length.
//
// The counter is exact, so it is used whenever it can be right. It cannot be
// right when it went backwards (a device left the total, or was recreated) or
// when it grew by more than any link could carry in that time (a device with
// an old counter joined the total, e.g. Wi-Fi after standby). Only then
// speed * time is counted instead.
//
// "More than a link could carry" is 1 Gbit/s, or 4 times the measured speed
// when that is higher. The measured speed alone must not be the limit: it is
// a snapshot of the last moment of the interval, and a download that started
// and ended between two snapshots would be thrown away.
const USAGE_PLAUSIBLE_RATE = 125 * 1000 * 1000;   // bytes per second = 1 Gbit/s

function usageDelta(delta, speed, prevSpeed, seconds) {
    const rate = v => (typeof v === 'number' && v > 0 && isFinite(v)) ? v : 0;
    speed = rate(speed);
    prevSpeed = rate(prevSpeed);
    seconds = rate(seconds);

    const estimate = speed * seconds;
    if (typeof delta !== 'number' || !(delta >= 0) || !isFinite(delta)) {
        return estimate;
    }
    const limit = Math.max(4 * speed, 4 * prevSpeed, USAGE_PLAUSIBLE_RATE) * seconds + 256 * 1024;
    return delta > limit ? estimate : delta;
}

// ---- small commands --------------------------------------------------------

// Only plain host names and addresses are passed to ping
function cleanHost(host) {
    const text = String(host || '').trim();
    if (/^[A-Za-z0-9.:_-]{1,253}$/.test(text) && text[0] !== '-') {
        return text;
    }
    // An IPv6 address with a zone ("fe80::1%wlan0"): needed to reach a link-local router
    return /^[0-9A-Fa-f:]{2,45}%[A-Za-z0-9_.-]{1,15}$/.test(text) && text.indexOf(':') !== -1 ? text : '';
}

// The router to ping for an interface: its IPv4 gateway, else its IPv6 gateway.
// A link-local IPv6 gateway (fe80::...) only works with the interface named.
function routerAddress(gateway4, gateway6, iface) {
    const v4 = cleanHost(gateway4);
    if (v4 !== '') {
        return v4;
    }
    const v6 = String(gateway6 || '').trim();
    if (v6 === '' || v6.indexOf(':') === -1) {
        return '';
    }
    return cleanHost(/^fe[89ab]/i.test(v6) && v6.indexOf('%') === -1 ? v6 + '%' + iface : v6);
}

// One echo request, answer awaited for 2 seconds. LC_ALL=C keeps the decimal
// point in the output; "timeout" ends a ping that hangs in the name lookup,
// so slow DNS cannot pile up processes. Unsafe host -> a command that fails.
function pingCommand(host) {
    const safe = cleanHost(host);
    if (safe === '') {
        return 'false';
    }
    return 'LC_ALL=C timeout 5 ping -n -c 1 -W 2 ' + shellQuote(safe);
}

// Output of ping -> milliseconds, or -1 when there was no answer
function parsePing(stdout) {
    const match = /\btime[=<]([0-9]+(?:\.[0-9]+)?) ?ms/.exec(String(stdout));
    return match ? Number(match[1]) : -1;
}

// Name of the .desktop entry install.sh puts into ~/.local/share/applications.
// Notifications sent under it are treated like those of a regular application,
// so Plasma keeps them in the notification history.
const DESKTOP_ENTRY = 'io.github.zebieksterc.netspeedwidget';

// Text for a rich-text string (the tooltip): markup characters are shown, not interpreted
function escapeHtml(text) {
    return String(text).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

// Host the "Check internet" button pings: the configured one, or 1.1.1.1
function internetHost(host) {
    return cleanHost(host) || '1.1.1.1';
}

// Copies the IPv4 address of this computer - without one, its IPv6 address - to the clipboard (through Klipper)
function copyIpCommand() {
    // the IPv4 address; on a connection without one, the IPv6 address
    const first = "awk '{ sub(/\\/.*/, \"\", $4); print $4; exit }'";
    return "ip=$(ip -4 -o addr show scope global 2>/dev/null | " + first + ");" +
        " [ -n \"$ip\" ] || ip=$(ip -6 -o addr show scope global 2>/dev/null | " + first + ");" +
        " [ -n \"$ip\" ] && qdbus6 org.kde.klipper /klipper org.kde.klipper.klipper.setClipboardContents \"$ip\" >/dev/null" +
        " && notify-send -a 'Netspeed Widget' -i edit-copy -t 2000 -h string:desktop-entry:" + DESKTOP_ENTRY + " 'IP address copied' \"$ip\"";
}

// Puts a text on the clipboard (through Klipper)
function copyTextCommand(text) {
    return 'qdbus6 org.kde.klipper /klipper org.kde.klipper.klipper.setClipboardContents ' + shellQuote(text) + ' >/dev/null';
}

// "file:///a%20b" or "/a b" -> "/a b"; '' for anything that is not an absolute local path
function localPath(url) {
    let path = String(url || '');
    if (path.indexOf('file://') === 0) {
        try {
            path = decodeURIComponent(path.slice(7));
        } catch (e) {
            return '';
        }
    }
    return path.charAt(0) === '/' && path.indexOf('\0') === -1 && path.indexOf('\n') === -1 ? path : '';
}

// Command that puts the notification entry (source: its file in the package) into the
// user's applications folder, unless the same file is already there. Plasma only keeps
// notifications in its history for an application it knows; install.sh does the same,
// this covers a widget installed from a .plasmoid file. Nothing is run for a bad path.
function desktopEntryCommand(source) {
    const path = localPath(source);
    if (path === '') {
        return 'true';
    }
    const src = shellQuote(path);
    return 'b="${XDG_DATA_HOME:-}"; case "$b" in /*) ;; *) b="$HOME/.local/share" ;; esac; ' +
        'd="$b/applications"; f="$d/' + DESKTOP_ENTRY + '.desktop"; ' +
        '[ -f ' + src + ' ] || exit 0; cmp -s -- ' + src + ' "$f" && exit 0; ' +
        'mkdir -p -- "$d" && cp -- ' + src + ' "$f.new" && mv -f -- "$f.new" "$f" && ' +
        '{ kbuildsycoca6 >/dev/null 2>&1 || true; }';
}

// Command for a desktop notification that Plasma keeps in its history (see DESKTOP_ENTRY)
function notifyCommand(title, body, icon) {
    // "--": a title that starts with a dash is not taken for an option
    return 'notify-send -a ' + shellQuote('Netspeed Widget') + ' -i ' + shellQuote(icon) +
        ' -h string:desktop-entry:' + DESKTOP_ENTRY + ' -- ' +
        shellQuote(title) + ' ' + shellQuote(body);
}

// Text returned by an "what is my IP" service -> the address, or ''
function cleanIp(text) {
    const ip = String(text || '').trim();
    const v4 = /^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/.exec(ip);
    if (v4) {
        return v4.slice(1).every(part => Number(part) <= 255) ? ip : '';
    }
    // IPv6: hex groups with at least two colons, optionally ending in an IPv4 part
    return /^[0-9A-Fa-f:.]{2,45}$/.test(ip) && ip.split(':').length >= 3 ? ip : '';
}
