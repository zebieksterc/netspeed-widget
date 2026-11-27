/*
 * Copyright 2016  Daniel Faust <hessijames@gmail.com>
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License as
 * published by the Free Software Foundation; either version 2 of
 * the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http: //www.gnu.org/licenses/>.
 */
/*
 * Fork (2026): the default mode reads Plasma's system-monitor sensors instead
 * of starting a process for every update; /proc/net/dev is only read for a
 * hand-picked interface list, while the details popup is open, or when the
 * sensors are not available.
 */
import QtQuick
import org.kde.plasma.plasmoid
import org.kde.kirigami as Kirigami
import "../code/utils.js" as Utils

// The parts of this file, in order:
//   settings (the values from the settings pages), where the numbers come from (sensors or /proc),
//   interfaces and connection state, graph / peak / usage / idle state, optional extras (latency,
//   internet check), the two representations and the tooltip, start and end of the widget, timers,
//   sensors and per-interface sensors, the /proc data source, one-off commands (run),
//   interface list and connection state, sampling and counters, data limits, weak Wi-Fi signal,
//   copy everything, mouse actions, router latency, internet check, tooltip text.
PlasmoidItem {
    id: root

    // ---- settings --------------------------------------------------------
    property bool showSeparately: plasmoid.configuration.showSeparately
    property bool showLowSpeeds: plasmoid.configuration.showLowSpeeds
    property string speedLayout: plasmoid.configuration.speedLayout
    property bool swapDownUp: plasmoid.configuration.swapDownUp
    property bool showIcons: plasmoid.configuration.showIcons
    property bool showUnits: plasmoid.configuration.showUnits
    property string speedUnits: plasmoid.configuration.speedUnits
    property bool shortUnits: plasmoid.configuration.shortUnits
    property double fontSizeScale: plasmoid.configuration.fontSize / 100
    // the same value under a second name: the panel item has its own, limited fontSizeScale
    readonly property double userFontScale: fontSizeScale
    property double updateInterval: plasmoid.configuration.updateInterval
    property bool customColors: plasmoid.configuration.customColors
    property color byteColor: plasmoid.configuration.byteColor
    property color kilobyteColor: plasmoid.configuration.kilobyteColor
    property color megabyteColor: plasmoid.configuration.megabyteColor
    property color gigabyteColor: plasmoid.configuration.gigabyteColor

    property bool launchApplicationEnabled: plasmoid.configuration.launchApplicationEnabled
    property string launchApplication: plasmoid.configuration.launchApplication
    property bool interfacesWhitelistEnabled: plasmoid.configuration.interfacesWhitelistEnabled
    property var interfacesWhitelist: plasmoid.configuration.interfacesWhitelist

    property int decimals: plasmoid.configuration.decimals === 0 ? 0 : 1
    property bool fixedDigits: plasmoid.configuration.fixedDigits
    property bool panelGraph: plasmoid.configuration.panelGraph
    property bool showSignal: plasmoid.configuration.showSignal
    property bool showSignalPercent: plasmoid.configuration.showSignalPercent
    // 'left' (next to the bar), 'bar' (inside a wider bar), 'right' (after the speeds),
    // 'lineBar' / 'lineText' (a line of its own above the speeds, with the network name)
    property string signalPercentPosition: plasmoid.configuration.signalPercentPosition
    property bool showFrame: plasmoid.configuration.showFrame === true
    // Size of the details popup in percent (80 to 200)
    property int detailsZoom: Math.max(80, Math.min(200, Number(plasmoid.configuration.detailsZoom) || 100))
    property bool showDisconnected: plasmoid.configuration.showDisconnected
    property bool notifyConnection: plasmoid.configuration.notifyConnection
    property bool hideWhenIdle: plasmoid.configuration.hideWhenIdle
    property int idleThreshold: plasmoid.configuration.idleThreshold
    property bool scrollSwitchesUnits: plasmoid.configuration.scrollSwitchesUnits
    property bool middleClickCopiesIp: plasmoid.configuration.middleClickCopiesIp
    property bool pingEnabled: plasmoid.configuration.pingEnabled
    property string pingHost: plasmoid.configuration.pingHost
    property int pingInterval: plasmoid.configuration.pingInterval
    property bool externalIpEnabled: plasmoid.configuration.externalIpEnabled
    property string externalIpUrl: plasmoid.configuration.externalIpUrl
    property bool perInterfaceUsage: plasmoid.configuration.perInterfaceUsage === true
    // Day of the month on which the counted month starts (1 = calendar month)
    property int periodStartDay: Utils.cleanStartDay(plasmoid.configuration.periodStartDay)
    // Data limits: a list (JSON text) of { id, iface, limit, day, usedTenths };
    // each counts all connections or one interface, in a period of its own
    property string dataLimitsText: String(plasmoid.configuration.dataLimits || '')
    readonly property var dataLimits: Utils.parseLimits(dataLimitsText)
    // Which limits the panel shows: 'auto' (connection in use), 'all' or 'none'
    property string dataLimitsPanel: String(plasmoid.configuration.dataLimitsPanel || 'auto')
    // True once the saved counters have been read (settings that change earlier must not touch them)
    property bool usageLoaded: false

    onDataLimitsTextChanged: {
        if (usageLoaded) {
            applyLimits({});
        }
    }

    // The Data limits page asks for the reset of one limit through this value
    // ("limit:<id>:<time>"), because a settings page cannot call the widget directly.
    // The other words (session, today, …) are understood as well; no page sends them at present.
    property string resetRequest: String(plasmoid.configuration.resetRequest || '')
    onResetRequestChanged: {
        if (usageLoaded && resetRequest !== '') {
            const parts = resetRequest.split(':');
            if (parts[0] === 'limit') {
                usage = Utils.resetLimit(usage, String(parts[1]));
                usageDirty = true;
                saveUsage();
            } else if (['session', 'today', 'month', 'limits', 'history', 'all'].indexOf(parts[0]) !== -1) {
                resetCounters(parts[0]);
            }
            plasmoid.configuration.resetRequest = '';
        }
    }

    // The per-interface counters are needed for their display and for limits on one interface
    readonly property bool countInterfaces: perInterfaceUsage || dataLimits.some(limit => limit.iface !== '')

    // A new start day renames the running period; what was counted so far stays in it
    onPeriodStartDayChanged: {
        usage = Object.assign({}, usage, { month: Utils.periodKey(new Date(), periodStartDay), startDay: periodStartDay });
        usageDirty = true;
    }
    // Notify when the Wi-Fi signal stays below this many percent (0 = never)
    property int signalWarnLevel: Math.max(0, Number(plasmoid.configuration.signalWarnLevel) || 0)

    readonly property int updateMs: Math.max(100, Math.round(updateInterval * 1000))

    // ---- where the numbers come from ------------------------------------
    // Sensors: all physical devices, no process started (default).
    // /proc/net/dev: selected interfaces, the open popup, or fallback.
    property QtObject sensors: null
    property QtObject procSource: null
    property QtObject runner: null       // one-off commands
    // One-off commands that are still running: source name -> function to call with the output;
    // runnerSeq numbers the source names (32 are reused)
    property var runnerCallbacks: ({})
    property int runnerSeq: 0
    property bool graceOver: false       // sensors get a few seconds to start

    readonly property bool sensorsReady: sensors !== null && sensors.ready
    readonly property bool useSensors: !interfacesWhitelistEnabled && sensorsReady
    // Continuous reading of /proc/net/dev
    readonly property bool procActive: interfacesWhitelistEnabled || (graceOver && !sensorsReady) || expanded

    // The last reading of /proc/net/dev and when it was taken (speed = change / time)

    property var transferDataTs: 0
    property var transferData: ({})
    property var speedData: ({})         // per interface, only while procActive
    property double procDown: 0
    property double procUp: 0

    // Shown speeds in bytes per second
    readonly property double downSpeed: useSensors ? sensors.down : procDown
    readonly property double upSpeed: useSensors ? sensors.up : procUp

    // ---- interfaces and connection state ---------------------------------
    property var netInfo: ({})           // last interface list (name -> flags)
    // Connection state: known after the first interface list; a change counts when two lists in a row agree
    property bool connectionKnown: false
    property bool connected: true
    property int connectionChanges: 0
    readonly property string wirelessName: Utils.wirelessInterface(netInfo)
    property var deviceSensors: ({})     // name -> object with ssid, signal, ipv4, gateway, dns
    readonly property bool needGateway: pingEnabled
    // Wi-Fi signal in percent, or -1
    readonly property int wifiSignal: {
        const dev = wirelessName !== '' ? deviceSensors[wirelessName] : undefined;
        return dev && dev.signal > 0 ? dev.signal : -1;
    }
    // Network name and signal on a line of their own in the panel
    readonly property bool ownSignalLine: showSignalPercent
                                          && (signalPercentPosition === 'lineBar' || signalPercentPosition === 'lineText')
    readonly property string linkInterface: Utils.linkInterface(netInfo)
    readonly property bool linkWireless: linkInterface !== '' && netInfo[linkInterface].wireless === true
    // Network (connection) name of that interface; the interface name until it is known
    readonly property string linkName: {
        if (linkInterface === '') {
            return '';
        }
        const dev = deviceSensors[linkInterface];
        return dev && dev.ssid !== '' ? dev.ssid : linkInterface;
    }
    // Reading the interface list now and then (one short process)
    readonly property bool needDiscovery: showDisconnected || notifyConnection || showSignal || showSignalPercent || needGateway
                                          || countInterfaces || signalWarnLevel > 0

    // ---- graph, peak, usage, idle ----------------------------------------
    readonly property int historyLength: 60
    property var historyDown: []
    property var historyUp: []
    property double peakDown: 0
    property double peakUp: 0
    property double sessionDown: 0
    property double sessionUp: 0
    property var usage: Utils.loadUsage('', new Date())
    property bool usageDirty: false
    property var lastTotals: null        // { key, down, up }
    // false until the traffic from before this start has been added (see Utils.catchUpTotals)
    property bool totalsCaughtUp: false
    readonly property double startedAt: Date.now()
    // The previous reading: time, speeds and byte counters (to compute what was transferred since)
    property double lastSampleTs: 0
    property double lastSampleDown: 0
    property double lastSampleUp: 0
    property double idleSeconds: 0
    readonly property bool idle: hideWhenIdle && idleSeconds >= 5

    // ---- optional extras --------------------------------------------------
    // Latency to the router (gateway), measured regularly when enabled
    property double latency: -1          // ms, -1 = no answer / not measured
    property string latencyHost: ''      // the gateway address that was pinged
    property string latencyInterface: '' // the interface that gateway belongs to
    // Internet check: only on request (button in the details)
    property string externalIp: ''
    property double internetLatency: -1
    property string internetHost: ''
    property bool internetChecked: false
    property int internetPending: 0      // answers still awaited
    property int internetCheckId: 0      // number of the current check
    property var internetRequest: null   // the external IP request while it is running

    compactRepresentation: CompactRepresentation {}
    fullRepresentation: FullRepresentation {}
    preferredRepresentation: compactRepresentation

    toolTipMainText: i18n('Network usage')
    toolTipSubText: tooltipText()
    toolTipTextFormat: Text.RichText

    Component.onCompleted: {
        usage = Utils.loadUsage(plasmoid.configuration.usageState, new Date(), periodStartDay);
        usageLoaded = true;
        applyLimits({});
        // the notification entry, for a widget that was installed without install.sh
        run(Utils.desktopEntryCommand(Qt.resolvedUrl('../data/' + Utils.DESKTOP_ENTRY + '.desktop')), null);
        if (!interfacesWhitelistEnabled) {
            createSensors();
        }
        if (procActive) {
            createProcSource();
        }
    }

    Component.onDestruction: saveUsage()

    onInterfacesWhitelistEnabledChanged: {
        if (!interfacesWhitelistEnabled && sensors === null) {
            createSensors();
        }
    }

    onProcActiveChanged: {
        // Never calculate a speed from an old reading
        transferData = ({});
        speedData = ({});
        transferDataTs = 0;
        procDown = 0;
        procUp = 0;
        if (procActive) {
            createProcSource();
        }
    }

    onExpandedChanged: {
        // root.expanded: the signal has a parameter of the same name
        if (root.expanded && root.externalIpEnabled) {
            checkInternet();
        }
    }

    onNetInfoChanged: updateDeviceSensors()

    // ---- timers -----------------------------------------------------------
    Timer {
        interval: 4000
        running: true
        onTriggered: {
            root.graceOver = true;
            if (!root.interfacesWhitelistEnabled && !root.sensorsReady) {
                console.warn("Netspeed Widget: system sensors gave no data, reading /proc/net/dev instead");
            }
        }
    }

    // One sample per update: graph, peak, usage counters, idle state
    Timer {
        interval: root.updateMs
        running: true
        repeat: true
        onTriggered: root.sample()
    }

    // Interface list while /proc/net/dev is not read continuously.
    // Checked sooner while nothing moves, which is how a lost connection looks.
    // The interval is fixed: changing it restarts a running Timer, so with
    // traffic that comes and goes it would never fire.
    Timer {
        property int waited: 30
        interval: 5000
        running: !root.procActive && root.needDiscovery
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            waited += 5;
            if (waited >= 30 || (root.downSpeed === 0 && root.upSpeed === 0)) {
                waited = 0;
                root.discover();
            }
        }
    }

    // Once after start, so the popup and the Wi-Fi name are known
    Timer {
        interval: 2000
        running: true
        onTriggered: {
            if (!root.procActive) {
                root.discover();
            }
        }
    }

    Timer {
        // until the gateway address is known, look again every 2 seconds (no process is started without one)
        interval: root.latencyHost === '' ? 2000 : Math.max(5, root.pingInterval) * 1000
        running: root.pingEnabled
        repeat: true
        triggeredOnStart: true
        onTriggered: root.measureLatency()
    }

    Timer {
        id: internetWatchdog
        interval: 10000     // the ping ends after 5 seconds at most
        onTriggered: root.internetTimedOut()
    }

    Timer {
        interval: 5 * 60 * 1000
        running: true
        repeat: true
        onTriggered: root.saveUsage()
    }

    // ---- data sources -----------------------------------------------------
    function createSensors(): void {
        try {
            sensors = Qt.createQmlObject(
                'import QtQuick\n' +
                'import org.kde.ksysguard.sensors as Sensors\n' +
                'Item {\n' +
                '    id: box\n' +
                '    visible: false\n' +
                '    property int rateLimit: 1000\n' +
                '    property bool active: true\n' +
                '    readonly property bool ready: down_.value !== undefined && up_.value !== undefined && downTotal_.value !== undefined && upTotal_.value !== undefined\n' +
                '    readonly property double down: Math.max(0, Number(down_.value) || 0)\n' +
                '    readonly property double up: Math.max(0, Number(up_.value) || 0)\n' +
                '    readonly property double downTotal: Number(downTotal_.value) || 0\n' +
                '    readonly property double upTotal: Number(upTotal_.value) || 0\n' +
                '    Sensors.Sensor { id: down_; sensorId: "network/all/download"; updateRateLimit: box.rateLimit; enabled: box.active }\n' +
                '    Sensors.Sensor { id: up_; sensorId: "network/all/upload"; updateRateLimit: box.rateLimit; enabled: box.active }\n' +
                '    Sensors.Sensor { id: downTotal_; sensorId: "network/all/totalDownload"; updateRateLimit: box.rateLimit; enabled: box.active }\n' +
                '    Sensors.Sensor { id: upTotal_; sensorId: "network/all/totalUpload"; updateRateLimit: box.rateLimit; enabled: box.active }\n' +
                '}', root, "sensors");
            sensors.rateLimit = Qt.binding(() => root.updateMs);
            sensors.active = Qt.binding(() => !root.interfacesWhitelistEnabled);
        } catch (e) {
            sensors = null;
            console.warn("Netspeed Widget: system sensors are not available:", e);
        }
    }

    // Extra information about one physical device (name, signal, addresses).
    // Only subscribed while it is needed.
    function updateDeviceSensors(): void {
        let changed = false;
        const next = Object.assign({}, deviceSensors);
        for (const name in netInfo) {
            if (!netInfo[name].physical || next[name] !== undefined || !/^[A-Za-z0-9_.-]+$/.test(name)) {
                continue;
            }
            try {
                const dev = Qt.createQmlObject(
                    'import QtQuick\n' +
                    'import org.kde.ksysguard.sensors as Sensors\n' +
                    'Item {\n' +
                    '    id: box\n' +
                    '    visible: false\n' +
                    '    property bool active: false\n' +
                    '    property bool signalActive: false\n' +
                    '    readonly property string ssid: String(ssid_.value === undefined ? "" : ssid_.value)\n' +
                    '    readonly property int signal: Math.round(Number(signal_.value) || 0)\n' +
                    '    readonly property string ipv4: String(ipv4_.value === undefined ? "" : ipv4_.value)\n' +
                    '    readonly property string gateway: String(gateway_.value === undefined ? "" : gateway_.value)\n' +
                    '    readonly property string dns: String(dns_.value === undefined ? "" : dns_.value)\n' +
                    '    readonly property string ipv6: String(ipv6_.value === undefined ? "" : ipv6_.value)\n' +
                    '    readonly property string gateway6: String(gateway6_.value === undefined ? "" : gateway6_.value)\n' +
                    '    readonly property string dns6: String(dns6_.value === undefined ? "" : dns6_.value)\n' +
                    '    Sensors.Sensor { id: ssid_; sensorId: "network/' + name + '/network"; enabled: box.active }\n' +
                    '    Sensors.Sensor { id: signal_; sensorId: "network/' + name + '/signal"; enabled: box.active || box.signalActive; updateRateLimit: 5000 }\n' +
                    '    Sensors.Sensor { id: ipv4_; sensorId: "network/' + name + '/ipv4address"; enabled: box.active }\n' +
                    '    Sensors.Sensor { id: gateway_; sensorId: "network/' + name + '/ipv4gateway"; enabled: box.active }\n' +
                    '    Sensors.Sensor { id: dns_; sensorId: "network/' + name + '/ipv4dns"; enabled: box.active }\n' +
                    '    Sensors.Sensor { id: ipv6_; sensorId: "network/' + name + '/ipv6address"; enabled: box.active }\n' +
                    '    Sensors.Sensor { id: gateway6_; sensorId: "network/' + name + '/ipv6gateway"; enabled: box.active }\n' +
                    '    Sensors.Sensor { id: dns6_; sensorId: "network/' + name + '/ipv6dns"; enabled: box.active }\n' +
                    '}', root, "deviceSensors_" + name);
                dev.active = Qt.binding(() => root.expanded || root.needGateway
                                               || ((root.ownSignalLine || root.signalWarnLevel > 0) && root.linkInterface === name));
                // The signal of the Wi-Fi device is always read (one value, at most every 5 s):
                // the tooltip shows it
                dev.signalActive = Qt.binding(() => root.wirelessName === name);
                next[name] = dev;
                changed = true;
            } catch (e) {
                // Without the sensors module the popup simply has less to show
                return;
            }
        }
        if (changed) {
            deviceSensors = next;
        }
    }

    // Creates the data source that runs NET_DATA_SOURCE once per update (the /proc/net/dev mode).
    // It is only connected while procActive is true.
    function createProcSource(): void {
        if (procSource !== null) {
            return;
        }
        try {
            procSource = Qt.createQmlObject(
                'import QtQuick\n' +
                'import org.kde.plasma.plasma5support as P5Support\n' +
                'P5Support.DataSource {\n' +
                '    property bool active: false\n' +
                '    property string command\n' +
                '    engine: "executable"\n' +
                '    connectedSources: active ? [command] : []\n' +
                '}', root, "procSource");
            procSource.command = Utils.NET_DATA_SOURCE;
            procSource.interval = Qt.binding(() => root.updateMs);
            procSource.active = Qt.binding(() => root.procActive);
        } catch (e) {
            procSource = null;
            console.warn("Netspeed Widget: cannot read /proc/net/dev (plasma5support missing?):", e);
        }
    }

    // A reading of /proc/net/dev arrived: speeds per interface and the sums that the panel shows
    Connections {
        target: root.procSource
        function onNewData(sourceName, data) {
            if (!root.procActive) {
                return;
            }
            if (data['exit code'] > 0) {
                console.warn("Netspeed Widget:", data.stderr);
                // Do not keep showing an old speed
                root.speedData = ({});
                root.procDown = 0;
                root.procUp = 0;
                return;
            }

            const now = Date.now();
            const duration = now - root.transferDataTs;
            const nextTransferData = Utils.parseTransferData(data.stdout);
            const nextSpeedData = Utils.calcSpeedData(root.transferData, nextTransferData, duration);

            let down = 0;
            let up = 0;
            for (const name in nextSpeedData) {
                if (root.interfaceShown(name, nextSpeedData[name])) {
                    down += nextSpeedData[name].down;
                    up += nextSpeedData[name].up;
                }
            }

            root.speedData = nextSpeedData;
            root.procDown = down;
            root.procUp = up;
            root.transferDataTs = now;
            root.transferData = nextTransferData;
            root.updateNetInfo(nextTransferData);
        }
    }

    // ---- one-off commands -------------------------------------------------
    // Runs a shell command once; callback(data) gets stdout, stderr, exit code
    function run(command: string, callback: var): bool {
        try {
            if (runner === null) {
                runner = Qt.createQmlObject(
                    'import QtQuick\n' +
                    'import org.kde.plasma.plasma5support as P5Support\n' +
                    'P5Support.DataSource {\n' +
                    '    engine: "executable"\n' +
                    '    connectedSources: []\n' +
                    '}', root, "runner");
            }
            // The trailing comment makes the command differ from the last ones, so it
            // can be run again. Only a few numbers are used: the DataSource keeps an
            // entry for every source name it has ever seen.
            // A number whose command is still running is skipped.
            let source = '';
            for (let i = 0; i < 32 && (source === '' || source in runnerCallbacks); ++i) {
                runnerSeq = (runnerSeq + 1) % 32;
                source = command + ' # ' + runnerSeq;
            }
            if (source in runnerCallbacks) {
                return false;   // 32 commands still running: do not start more
            }
            runnerCallbacks[source] = callback;
            runner.connectSource(source);
            return true;
        } catch (e) {
            console.warn("Netspeed Widget: cannot run a command (plasma5support missing?):", e);
            return false;
        }
    }

    // A one-off command finished: hand its output to whoever started it (see run())
    Connections {
        target: root.runner
        function onNewData(sourceName, data) {
            const callback = root.runnerCallbacks[sourceName];
            delete root.runnerCallbacks[sourceName];
            root.runner.disconnectSource(sourceName);
            if (callback) {
                callback(data);
            }
        }
    }

    // Reads the interface list once (names, state, byte counters) through a short process
    function discover(): void {
        run(Utils.NET_DATA_SOURCE, data => {
            // Real output always has at least the loopback line
            if (!(data['exit code'] > 0) && String(data.stdout).trim() !== '') {
                root.updateNetInfo(Utils.parseTransferData(data.stdout));
            }
        });
    }

    // A change of the connection state must be seen in two readings in a row,
    // so a Wi-Fi roam does not produce a "lost" / "back" pair.
    function updateNetInfo(info: var): void {
        const nowConnected = Utils.isConnected(info, interfacesWhitelistEnabled, interfacesWhitelist);
        if (!connectionKnown) {
            connected = nowConnected;
            connectionKnown = true;
        } else if (nowConnected === connected) {
            connectionChanges = 0;
        } else if (++connectionChanges >= 2) {
            connectionChanges = 0;
            connected = nowConnected;
            if (notifyConnection) {
                run(nowConnected
                    ? Utils.notifyCommand(i18n('Network connected'), i18n('A network connection is available again.'), 'network-connect')
                    : Utils.notifyCommand(i18n('Network disconnected'), i18n('No network interface is connected.'), 'network-disconnect'),
                    null);
            }
        }
        netInfo = info;
        // Traffic per interface, from the byte counters that came with the list
        if (countInterfaces) {
            const counted = Utils.addInterfaceUsage(usage, info, new Date(), periodStartDay);
            if (counted.changed) {
                usage = counted.usage;
                usageDirty = true;
                applyLimits(counted.bytes);
            }
        }
    }

    // True when an interface counts: selected in the settings, or physical when nothing is selected
    function interfaceShown(name: string, entry: var): bool {
        return Utils.interfaceShown(name, entry, interfacesWhitelistEnabled, interfacesWhitelist);
    }

    // ---- sampling ---------------------------------------------------------
    // Byte counters of what is shown, or null when unknown
    function currentTotals(): var {
        if (useSensors) {
            return { key: 'sensors', down: sensors.downTotal, up: sensors.upTotal };
        }
        let down = 0;
        let up = 0;
        const names = [];
        for (const name in speedData) {
            if (interfaceShown(name, speedData[name])) {
                down += speedData[name].downTotal;
                up += speedData[name].upTotal;
                names.push(name);
            }
        }
        return names.length > 0 ? { key: 'proc:' + names.join(','), down: down, up: up } : null;
    }

    // One reading: graph, peak, session / today / month counters, data limits, idle state
    function sample(): void {
        const now = Date.now();
        // Capped: after standby the old speed must not be multiplied by the whole pause
        const seconds = lastSampleTs > 0 ? Math.min(3 * updateMs / 1000, (now - lastSampleTs) / 1000) : 0;
        const down = downSpeed;
        const up = upSpeed;

        historyDown = Utils.pushSample(historyDown, down, historyLength);
        historyUp = Utils.pushSample(historyUp, up, historyLength);
        peakDown = Math.max(peakDown, down);
        peakUp = Math.max(peakUp, up);

        // Usage: change of the byte counters, checked against the measured speed
        const totals = currentTotals();
        let caughtUpNow = false;
        if (!totalsCaughtUp && usageLoaded) {
            // Once after the start: what was transferred while the widget was not running.
            // It counts for today, this month and the limits of all connections, not for "session".
            const missed = Utils.catchUpTotals(usage.totals, totals);
            // Other counters than the saved ones (the sensors are not ready yet and /proc/net/dev
            // is read meanwhile): wait for the right ones, but not longer than half a minute.
            if (missed !== null && (missed.matched || now - startedAt > 30000)) {
                totalsCaughtUp = true;
                caughtUpNow = true;
                if (missed.down > 0 || missed.up > 0) {
                    usage = Utils.addUsage(usage, missed.down, missed.up, new Date(now), periodStartDay);
                    applyLimits({ '': missed.down + missed.up });
                }
                usageDirty = true;
            }
        }
        // (not in the reading that caught up: it already holds everything up to now)
        if (seconds > 0 && !caughtUpNow) {
            const comparable = totals !== null && lastTotals !== null && totals.key === lastTotals.key;
            // A counter that was still 0 is "not delivered yet", not a starting point:
            // the first real value is the whole amount since the connection came up,
            // which must not be counted as new traffic.
            const addDown = Utils.usageDelta(comparable && lastTotals.down > 0 ? totals.down - lastTotals.down : -1, down, lastSampleDown, seconds);
            const addUp = Utils.usageDelta(comparable && lastTotals.up > 0 ? totals.up - lastTotals.up : -1, up, lastSampleUp, seconds);
            if (addDown > 0 || addUp > 0) {
                sessionDown += addDown;
                sessionUp += addUp;
                usage = Utils.addUsage(usage, addDown, addUp, new Date(now), periodStartDay);
                usageDirty = true;
                applyLimits({ '': addDown + addUp });
            } else if (usage.day !== Utils.dayKey(new Date(now))) {
                usage = Utils.addUsage(usage, 0, 0, new Date(now), periodStartDay);   // midnight
                usageDirty = true;
            }
        }
        lastTotals = totals;
        lastSampleTs = now;
        lastSampleDown = down;
        lastSampleUp = up;

        const limit = Math.max(0, idleThreshold) * 1024;
        idleSeconds = (down <= limit && up <= limit) ? idleSeconds + updateMs / 1000 : 0;
    }

    // Writes the counters to the settings file, if they changed
    function saveUsage(): void {
        if (usageDirty) {
            // Remember where the byte counters stand, for the catch-up after the next start.
            // Not before this start has caught up itself: the saved position is still needed.
            if (totalsCaughtUp && lastTotals !== null && (lastTotals.down > 0 || lastTotals.up > 0)) {
                usage = Object.assign({}, usage, { totals: { key: lastTotals.key, down: lastTotals.down, up: lastTotals.up } });
            }
            plasmoid.configuration.usageState = JSON.stringify(usage);
            usageDirty = false;
        }
    }

    // what: 'session' (peak and this session), 'today', 'month', 'limits'
    // (the counters of all data limits), 'history' or 'all'
    function resetCounters(what: string): void {
        if (what === 'session' || what === 'all') {
            peakDown = 0;
            peakUp = 0;
            sessionDown = 0;
            sessionUp = 0;
        }
        if (what !== 'session') {
            usage = Utils.resetUsage(usage, what, new Date(), periodStartDay);
            usageDirty = true;
            saveUsage();
        }
    }

    // First day of the running month, e.g. "15 Nov"; '' for a calendar month
    readonly property string periodSince: periodStartDay <= 1 ? ''
        : Utils.periodStart(new Date(), periodStartDay).toLocaleDateString(Qt.locale(), 'd MMM')

    // ---- data limits ------------------------------------------------------
    // What is shown for each limit (see Utils.limitStatus)
    readonly property var limitStates: Utils.limitStatus(usage, dataLimits)
    // The limits that get a line in the panel
    readonly property var panelLimitStates: Utils.panelLimits(limitStates, dataLimitsPanel, linkInterface)

    // Green up to half of the limit, then step by step through yellow and orange to red
    function limitColor(fraction: double): color {
        return Qt.hsla(Utils.limitHue(fraction) / 360, 0.72, 0.5, 1);
    }

    // "Data limit" or "Data limit on <interface>"
    function limitTitle(state: var): string {
        return state.iface === '' ? i18n('Data limit') : i18n('Data limit on %1', state.iface);
    }

    // "14.3 / 50 GiB"
    function limitAmount(state: var): string {
        return i18n('%1 / %2 GiB', Utils.formatGiB(state.used), state.limit);
    }

    // Counts traffic for the limits (bytes: '' = all connections, name = one
    // interface), starts new periods, and sends the 80 % / 100 % notifications
    function applyLimits(bytes: var): void {
        if (dataLimits.length === 0) {
            if (usage.limits && Object.keys(usage.limits).length > 0) {
                usage = Object.assign({}, usage, { limits: {} });
                usageDirty = true;
            }
            return;
        }
        const before = JSON.stringify(usage.limits || {});
        const rolled = Utils.addLimitUsage(usage, dataLimits, bytes, new Date());
        let states = rolled.usage.limits;
        let notify = [];
        for (const state of Utils.limitStatus(rolled.usage, dataLimits)) {
            if (state.stage > state.notified) {
                states[state.id].notified = state.stage;
                notify.push(state);
            }
        }
        if (JSON.stringify(states) !== before) {
            usage = rolled.usage;
            usageDirty = true;
        }
        for (const state of notify) {
            saveUsage();
            run(Utils.notifyCommand(
                    state.stage >= 100 ? i18n('%1 reached', limitTitle(state)) : i18n('%1: 80 % used', limitTitle(state)),
                    i18n('%1 of %2 GiB in this period.', Utils.formatGiB(state.used), state.limit),
                    state.stage >= 100 ? 'dialog-warning' : 'dialog-information'), null);
        }
        // "Already used" figures that ended with their period: back to 0 in the settings
        if (rolled.cleared.length > 0) {
            const list = dataLimits.map(limit => rolled.cleared.indexOf(limit.id) !== -1
                                                  ? Object.assign({}, limit, { usedTenths: 0 }) : limit);
            plasmoid.configuration.dataLimits = JSON.stringify(list);
        }
    }

    // ---- weak Wi-Fi signal -----------------------------------------------
    property int signalLowSeconds: 0
    property bool signalWarned: false

    Timer {
        interval: 10000
        running: root.signalWarnLevel > 0
        repeat: true
        onTriggered: {
            const signal = root.wifiSignal;
            if (signal >= 0 && signal < root.signalWarnLevel) {
                root.signalLowSeconds += 10;
                if (root.signalLowSeconds >= 60 && !root.signalWarned) {
                    root.signalWarned = true;
                    root.run(Utils.notifyCommand(i18n('Wi-Fi signal weak'),
                                                 i18n('%1 is at %2 % for over a minute.', root.linkWireless ? root.linkName : root.wirelessName, signal),
                                                 'network-wireless-signal-weak'), null);
                }
            } else if (signal < 0 || signal >= root.signalWarnLevel + 5) {
                // back above the level (with a little margin), or no Wi-Fi: may warn again
                root.signalLowSeconds = 0;
                root.signalWarned = false;
            }
        }
    }

    // ---- copy everything about the connection ----------------------------
    function connectionSummary(): string {
        const lines = [];
        for (const name in deviceSensors) {
            const dev = deviceSensors[name];
            if (dev.ipv4 === '' && dev.ipv6 === '') {
                continue;
            }
            lines.push(name + (dev.ssid !== '' ? ' (' + dev.ssid + ')' : ''));
            if (dev.ipv4 !== '') {
                lines.push('  IP: ' + dev.ipv4);
            }
            if (dev.gateway !== '') {
                lines.push('  Gateway: ' + dev.gateway);
            }
            if (dev.dns !== '') {
                lines.push('  DNS: ' + dev.dns);
            }
            if (dev.ipv6 !== '') {
                lines.push('  IPv6: ' + dev.ipv6);
                if (dev.gateway6 !== '') {
                    lines.push('  IPv6 gateway: ' + dev.gateway6);
                }
                if (dev.dns6 !== '') {
                    lines.push('  IPv6 DNS: ' + dev.dns6);
                }
            }
            if (name === wirelessName && wifiSignal >= 0) {
                lines.push('  Signal: ' + wifiSignal + ' %');
            }
            if (pingEnabled && name === latencyInterface && latency >= 0) {
                lines.push('  Router latency: ' + latency.toFixed(1) + ' ms');
            }
        }
        if (externalIp !== '') {
            lines.push('External IP: ' + externalIp);
        }
        return lines.join('\n');
    }

    // ---- actions ----------------------------------------------------------
    function toggleUnits(): void {
        plasmoid.configuration.speedUnits = speedUnits === 'bits' ? 'bytes' : 'bits';
    }

    // The panel item flashes when copyClicks changes: proof that a middle click
    // arrived, independent of the setting and of whether the copy itself works
    property int copyClicks: 0

    // Called for every middle click on the panel item, before anything else
    function middleClicked(): void {
        copyClicks += 1;
        if (middleClickCopiesIp) {
            copyIpAddress();
        }
    }

    // Copies any text; used by the address lines in the details popup
    function copyText(text: string): void {
        const started = run(Utils.copyTextCommand(text), data => {
            if (data['exit code'] > 0) {
                console.warn("Netspeed Widget: copying to the clipboard failed (exit code " + data['exit code'] + ") "
                             + String(data.stderr || '').trim());
            }
        });
        if (!started) {
            console.warn("Netspeed Widget: could not start the command that copies to the clipboard");
        }
    }

    // Copies the IP address of this computer to the clipboard (middle click)
    function copyIpAddress(): void {
        const started = run(Utils.copyIpCommand(), data => {
            if (data['exit code'] > 0) {
                console.warn("Netspeed Widget: copying the IP address failed (exit code " + data['exit code'] + ") "
                             + String(data.stderr || '').trim());
            }
        });
        if (!started) {
            console.warn("Netspeed Widget: could not start the command that copies the IP address");
        }
    }

    // Starts the application chosen under Advanced
    function launchConfiguredApplication(): void {
        if (launchApplication !== '') {
            run(Utils.launchCommand(launchApplication), null);
        }
    }

    // Version of the installed widget (from metadata.json), '' when it cannot be read
    readonly property string widgetVersion: (plasmoid.metaData && plasmoid.metaData.version) ? String(plasmoid.metaData.version) : ''

    // The same label in the details and in the tooltip, on a tinted background
    readonly property string versionLabel: widgetVersion !== '' ? i18n('Netspeed Widget (fork) %1', widgetVersion) : ''
    readonly property color versionTint: Qt.alpha(Kirigami.Theme.neutralTextColor, 0.35)

    // A click launches an application instead of opening the details
    readonly property bool launchOnClick: launchApplicationEnabled && launchApplication !== ''

    // Right-click menu entry "Show details" (see ContextMenu.qml)
    Loader {
        source: 'ContextMenu.qml'
    }

    // Opens the details popup (right-click menu entry)
    function showDetails(): void {
        expanded = true;
    }

    // Left click on the panel item. wasExpanded: state when the button went
    // down; the popup closes by itself as soon as the panel gets the click.
    function activate(wasExpanded: bool): void {
        if (launchOnClick) {
            launchConfiguredApplication();
        } else {
            expanded = !wasExpanded;
        }
    }

    // Latency to the router: one ping to the gateway of the first interface that has one
    function measureLatency(): void {
        let host = '';
        let iface = '';
        for (const name in deviceSensors) {
            host = Utils.routerAddress(deviceSensors[name].gateway, deviceSensors[name].gateway6, name);
            if (host !== '') {
                iface = name;
                break;
            }
        }
        if (host === '') {
            latency = -1;
            latencyHost = '';
            latencyInterface = '';
            return;
        }
        run(Utils.pingCommand(host), data => {
            const dev = root.deviceSensors[iface];
            if (!dev || Utils.routerAddress(dev.gateway, dev.gateway6, iface) !== host) {
                return;     // the gateway changed or went away meanwhile
            }
            root.latency = Utils.parsePing(data.stdout);
            root.latencyHost = host;
            root.latencyInterface = iface;
        });
    }

    // Internet check, on request: external IP address from the web service and
    // one ping to the internet host. Nothing here runs unless it is asked for.
    // Each check has a number; answers that belong to an older check are ignored.
    // The watchdog ends a check whose answers never arrive (QML's XMLHttpRequest
    // has no timeout of its own), so the button cannot stay disabled.
    function checkInternet(): void {
        if (internetPending > 0) {
            return;
        }
        const id = ++internetCheckId;
        const host = Utils.internetHost(pingHost);
        internetPending = 2;
        internetWatchdog.restart();
        const pinged = stdout => {
            if (id !== root.internetCheckId) {
                return;
            }
            root.internetLatency = Utils.parsePing(stdout);
            root.internetHost = host;
            root.internetAnswered();
        };
        if (!run(Utils.pingCommand(host), data => pinged(data.stdout))) {
            pinged('');
        }
        fetchExternalIp(id);
    }

    // One of the two answers of an internet check has arrived (ping or external IP)
    function internetAnswered(): void {
        internetChecked = true;
        internetPending = Math.max(0, internetPending - 1);
        if (internetPending === 0) {
            internetWatchdog.stop();
        }
    }

    // The watchdog: ends an internet check whose answers did not arrive
    function internetTimedOut(): void {
        internetCheckId += 1;       // late answers are ignored
        if (internetRequest !== null) {
            const request = internetRequest;
            internetRequest = null;
            externalIp = '';
            request.abort();
        }
        if (internetHost === '') {
            internetHost = Utils.internetHost(pingHost);
        }
        internetChecked = true;
        internetPending = 0;
    }

    // Asks the web service for the external IP address; id is the number of the check
    function fetchExternalIp(id: int): void {
        if (!/^https:\/\//.test(externalIpUrl)) {
            externalIp = '';
            internetAnswered();
            return;
        }
        const request = new XMLHttpRequest();
        internetRequest = request;
        request.onreadystatechange = () => {
            if (id !== root.internetCheckId || root.internetRequest !== request) {
                return;
            }
            // An address is a few characters: do not load a large answer
            const tooLong = (request.readyState === XMLHttpRequest.HEADERS_RECEIVED
                             && Number(request.getResponseHeader('Content-Length')) > 64)
                         || (request.readyState === XMLHttpRequest.LOADING && request.responseText.length > 64);
            if (tooLong || request.readyState === XMLHttpRequest.DONE) {
                root.internetRequest = null;
                root.externalIp = !tooLong && request.status === 200 ? Utils.cleanIp(request.responseText) : '';
                root.internetAnswered();
                if (tooLong) {
                    request.abort();
                }
            }
        };
        request.open('GET', externalIpUrl);
        request.send();
    }

    // ---- tooltip ----------------------------------------------------------
    function tooltipText(): string {
        let details = '';

        if (showDisconnected && connectionKnown && !connected) {
            details = '<b>' + i18n('Not connected') + '</b><br><br>';
        }

        if (useSensors) {
            details += '<b>' + i18n('All physical network devices') + '</b><br>'
                + i18n('Downloaded: <b>%1</b>, Uploaded: <b>%2</b>',
                       Utils.formatTotal(sensors.downTotal), Utils.formatTotal(sensors.upTotal));
        } else {
            let list = '';
            for (const name in speedData) {
                if (!interfaceShown(name, speedData[name])) {
                    continue;
                }
                if (list !== '') {
                    list += '<br><br>';
                }
                list += '<b>' + Utils.escapeHtml(name) + '</b><br>'
                    + i18n('Downloaded: <b>%1</b>, Uploaded: <b>%2</b>',
                           Utils.formatTotal(speedData[name].downTotal), Utils.formatTotal(speedData[name].upTotal));
            }
            details += list !== '' ? list : i18n('No network interface to show');
        }

        details += '<br><br>' + i18n('Today: ↓ <b>%1</b> ↑ <b>%2</b>',
                                     Utils.formatTotal(usage.dayDown), Utils.formatTotal(usage.dayUp));
        if (wifiSignal >= 0) {
            details += '<br>' + i18n('Wi-Fi %1: signal <b>%2 %</b>', Utils.escapeHtml(wirelessName), wifiSignal);
        }
        for (const state of limitStates) {
            details += '<br>' + Utils.escapeHtml(limitTitle(state)) + ': <b>' + limitAmount(state) + '</b> (' + Math.round(state.fraction * 100) + ' %)';
        }
        if (ownSignalLine && linkName !== '' && linkName !== linkInterface) {
            details += '<br>' + i18n('Network: <b>%1</b>', Utils.escapeHtml(linkName));
        }
        if (pingEnabled && latencyHost !== '') {
            details += '<br>' + (latency >= 0
                ? i18n('Router %1: <b>%2 ms</b>', latencyHost, latency.toFixed(1))
                : i18n('Router %1: <b>no answer</b>', latencyHost));
        }

        return details + '<br><br><i>'
            + (useSensors ? i18n('Source: system sensors') : i18n('Source: /proc/net/dev'))
            + (launchOnClick ? '<br>' + i18n('Right-click > Show details: graph, counters, interfaces') : '')
            + '</i>'
            + (versionLabel !== '' ? '<br><span style="background-color:' + versionTint + '">&nbsp;' + Utils.escapeHtml(versionLabel) + '&nbsp;</span>' : '');
    }
}
