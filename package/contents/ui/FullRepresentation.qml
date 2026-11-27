/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 *
 * Details popup of the Netspeed Widget fork: current speed, graph, counters
 * and one block per network interface.
 * Properties and functions without a prefix come from main.qml.
 */
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents
import "../code/utils.js" as Utils

// The parts of this file, in order:
//   sizes (everything is made from the zoomed z… values), a text width, the tile texts,
//   components (AddressStrip, StatTile, TileValue, LimitRow), monthLabel / speedLabel, the list of
//   interfaces, then the content from top to bottom:
//   current speed, graph, box "All connections", one box per interface, history, box "Internet", footer.
Item {
    id: popup

    // "Size of the details" from the settings: everything in the popup - texts,
    // icons, spacing, the popup itself - is made from these values, so it all
    // grows together and stays sharp (nothing is stretched).
    readonly property real zoom: Math.max(0.8, Math.min(2, detailsZoom / 100))
    readonly property int zSmall: Math.round(Kirigami.Units.smallSpacing * zoom)
    readonly property int zLarge: Math.round(Kirigami.Units.largeSpacing * zoom)
    readonly property int zGrid: Math.round(Kirigami.Units.gridUnit * zoom)
    readonly property int zIcon: Math.round(Kirigami.Units.iconSizes.small * zoom)
    readonly property int zRadius: Math.round(Kirigami.Units.cornerRadius * zoom)
    readonly property real zFontSize: Kirigami.Theme.defaultFont.pointSize * zoom
    readonly property font zSmallFont: Qt.font({ family: Kirigami.Theme.smallFont.family,
                                                 pointSize: Kirigami.Theme.smallFont.pointSize * zoom })

    // One fixed size (set with "Size of the details"): the popup cannot be dragged larger
    Layout.minimumWidth: zGrid * 25
    Layout.preferredWidth: zGrid * 25
    Layout.maximumWidth: zGrid * 25
    Layout.minimumHeight: column.implicitHeight + 2 * zLarge
    // The height follows the content
    Layout.preferredHeight: Layout.minimumHeight
    Layout.maximumHeight: Layout.minimumHeight

    // Fixed column widths, so the texts keep their place when the numbers change
    TextMetrics {
        id: headerSpeedMetrics
        font.pointSize: zFontSize * 1.4
        font.bold: true
        text: '↓ 1000.0 KiB/s'
    }

    readonly property color downColor: Kirigami.Theme.highlightColor
    readonly property color upColor: Kirigami.Theme.neutralTextColor

    // Stands in for a limit while the list is being replaced (a row never reads an entry that is gone)

    readonly property var emptyLimit: ({ id: '', iface: '', limit: 1, used: 0, offset: 0, fraction: 0 })

    // Texts of the four tiles of the All connections box, by position:
    // 0 = peak, 1 = session, 2 = today, 3 = this month
    function tileLabel(index: int): string {
        return index === 0 ? i18n('Peak') : index === 1 ? i18n('Session') : index === 2 ? i18n('Today')
             : periodSince === '' ? i18n('This month') : i18n('Since %1', periodSince);
    }
    // Value of a tile by position; down = the download value, else the upload value
    function tileValue(index: int, down: bool): string {
        switch (index) {
        case 0: return popup.speedLabel(down ? peakDown : peakUp);
        case 1: return Utils.formatTotal(down ? sessionDown : sessionUp);
        case 2: return Utils.formatTotal(down ? usage.dayDown : usage.dayUp);
        default: return Utils.formatTotal(down ? usage.monthDown : usage.monthUp);
        }
    }

    // A tinted strip with addresses, one or two lines. A click copies "address";
    // hovering shows the whole text when a line had to be cut with "…".
    component AddressStrip: Rectangle {
        id: strip
        property string line: ''
        property string line2: ''
        property string address: ''
        property bool copied: false

        Layout.fillWidth: true
        Layout.topMargin: Math.round(zSmall / 2)
        implicitHeight: stripColumn.implicitHeight + zSmall
        radius: zRadius
        color: Qt.alpha(Kirigami.Theme.highlightColor, stripMouse.containsMouse ? 0.35 : 0.18)

        ColumnLayout {
            id: stripColumn
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: zSmall
            anchors.rightMargin: zSmall
            spacing: 0

            PlasmaComponents.Label {
                id: stripLabel
                Layout.fillWidth: true
                textFormat: Text.PlainText   // never interpret a name or an answer as markup
                text: strip.copied ? i18n('Copied %1', strip.address) : strip.line
                font.bold: strip.copied
                elide: Text.ElideRight
            }
            PlasmaComponents.Label {
                id: stripLabel2
                Layout.fillWidth: true
                visible: strip.line2 !== ''
                textFormat: Text.PlainText
                text: strip.line2
                elide: Text.ElideRight
            }
        }
        MouseArea {
            id: stripMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                copyText(strip.address)
                strip.copied = true
                stripTimer.restart()
            }
        }
        QQC2.ToolTip.text: strip.line + (strip.line2 !== '' ? '\n' + strip.line2 : '')
        QQC2.ToolTip.visible: stripMouse.containsMouse && (stripLabel.truncated || stripLabel2.truncated)
        QQC2.ToolTip.delay: 500

        Timer {
            id: stripTimer
            interval: 1500
            onTriggered: strip.copied = false
        }
    }

    // A tile: label, download value, upload value. Hovering shows them in full.
    component StatTile: Rectangle {
        id: statTile
        property string label: ''
        property string down: ''
        property string up: ''
        property string note: ''

        Layout.fillWidth: true
        Layout.preferredWidth: 1     // equal shares of the row
        implicitHeight: statColumn.implicitHeight + zSmall
        radius: zRadius
        color: Qt.alpha(Kirigami.Theme.textColor, statHover.hovered ? 0.12 : 0.07)

        HoverHandler { id: statHover }
        QQC2.ToolTip.text: statTile.label + ': ↓ ' + statTile.down + '  ↑ ' + statTile.up + (statTile.note !== '' ? '\n' + statTile.note : '')
        QQC2.ToolTip.visible: statHover.hovered
        QQC2.ToolTip.delay: 500

        ColumnLayout {
            id: statColumn
            anchors.fill: parent
            anchors.leftMargin: zSmall
            anchors.rightMargin: Math.round(zSmall / 2)
            anchors.topMargin: Math.round(zSmall / 2)
            anchors.bottomMargin: Math.round(zSmall / 2)
            spacing: 0

            PlasmaComponents.Label {
                Layout.fillWidth: true
                text: statTile.label
                font: zSmallFont
                opacity: 0.6
                elide: Text.ElideRight
            }
            TileValue { arrow: '↓'; tint: Kirigami.Theme.highlightColor; value: statTile.down }
            TileValue { arrow: '↑'; tint: Kirigami.Theme.neutralTextColor; value: statTile.up }
        }
    }

    // One line of a tile: coloured arrow and a value that is never wrapped
    component TileValue: RowLayout {
        property string arrow: ''
        property color tint: Kirigami.Theme.textColor
        property string value: ''

        Layout.fillWidth: true
        spacing: Math.round(zSmall / 2)

        PlasmaComponents.Label {
            text: arrow
            color: tint
            font: zSmallFont
        }
        PlasmaComponents.Label {
            Layout.fillWidth: true
            text: value
            font: zSmallFont
            wrapMode: Text.NoWrap
            elide: Text.ElideRight
        }
    }

    // One data limit: icon and text, percentage in its colour, bar, and a small note
    component LimitRow: ColumnLayout {
        id: limitRow
        property var state: ({ iface: '', limit: 1, used: 0, offset: 0, fraction: 0 })
        // name the interface in the text (not needed inside that interface's own box)
        property bool showName: false
        readonly property color tint: limitColor(state.fraction)

        Layout.fillWidth: true
        Layout.leftMargin: Math.round(zSmall / 2)
        Layout.rightMargin: Math.round(zSmall / 2)
        spacing: Math.round(zSmall / 2)

        RowLayout {
            Layout.fillWidth: true
            spacing: zSmall

            Kirigami.Icon {
                Layout.preferredWidth: zIcon
                Layout.preferredHeight: zIcon
                source: limitRow.state.fraction >= 1 ? 'dialog-warning' : 'office-chart-pie'
            }
            PlasmaComponents.Label {
                Layout.fillWidth: true
                textFormat: Text.PlainText
                elide: Text.ElideRight
                text: (limitRow.showName ? i18n('Data limit on %1', limitRow.state.iface) : i18n('Data limit'))
                      + (limitRow.state.fraction >= 1 ? ' ' + i18n('reached') : '') + ': '
                      + i18n('%1 used', limitAmount(limitRow.state))
                color: limitRow.state.fraction >= 1 ? limitRow.tint : Kirigami.Theme.textColor
            }
            PlasmaComponents.Label {
                text: Math.round(limitRow.state.fraction * 100) + ' %'
                font.bold: true
                color: limitRow.tint
            }
        }
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: Math.max(4, Math.round(zSmall * 1.5))
            radius: height / 2
            color: Qt.alpha(Kirigami.Theme.textColor, 0.15)

            Rectangle {
                width: Math.round(parent.width * Math.min(1, Math.max(0, limitRow.state.fraction)))
                height: parent.height
                radius: parent.radius
                color: limitRow.tint
            }
        }
        PlasmaComponents.Label {
            Layout.fillWidth: true
            visible: limitRow.state.offset > 0
            textFormat: Text.PlainText
            elide: Text.ElideRight
            font: zSmallFont
            opacity: 0.6
            text: i18n('includes %1 GiB entered as already used', Utils.formatGiB(limitRow.state.offset))
        }
    }

    // "2026-10" -> "October 2026" in the language of the desktop
    // A period that began on another day: "15 Oct – 14 Nov 2026"
    function monthLabel(key: string, startDay: int): string {
        const parts = String(key).split('-');
        const day = Utils.cleanStartDay(startDay);
        const date = new Date(Number(parts[0]), Number(parts[1]) - 1, day);
        if (isNaN(date.getTime())) {
            return String(key);
        }
        if (day <= 1) {
            return date.toLocaleDateString(Qt.locale(), 'MMMM yyyy');
        }
        const last = new Date(date.getFullYear(), date.getMonth() + 1, day - 1);
        return date.toLocaleDateString(Qt.locale(), 'd MMM') + ' – ' + last.toLocaleDateString(Qt.locale(), 'd MMM yyyy');
    }

    // A speed as text with its unit, e.g. "1.3 kb/s"
    function speedLabel(value: double): string {
        const parts = Utils.formatSpeed(value, speedUnits, true, 1);
        return parts.number + ' ' + Utils.unitLabel(parts.tier, speedUnits, false);
    }

    // Names of the interfaces to list, in a stable order
    // (interfaceList: the same names, but only replaced when they really change -
    // interfaceNames is a new list every second while the details are open)
    property var interfaceList: []
    readonly property string interfaceKey: interfaceNames.join('\n')
    onInterfaceKeyChanged: interfaceList = interfaceKey === '' ? [] : interfaceKey.split('\n')

    readonly property var interfaceNames: {
        const names = [];
        for (const name in speedData) {
            if (interfaceShown(name, speedData[name])) {
                names.push(name);
            }
        }
        return names.sort();
    }

    // Labels and buttons that set no font of their own inherit it from here
    QQC2.Control {
        id: fontScope
        anchors.fill: parent
        padding: zLarge
        font.pointSize: zFontSize
        background: null

        contentItem: ColumnLayout {
            id: column
            spacing: zSmall

            // ---- current speed ------------------------------------------------
            RowLayout {
                Layout.fillWidth: true
                spacing: zLarge

                PlasmaComponents.Label {
                    Layout.preferredWidth: Math.ceil(headerSpeedMetrics.width)
                    text: '↓ ' + popup.speedLabel(downSpeed)
                    color: popup.downColor
                    font.pointSize: zFontSize * 1.4
                    font.bold: true
                }
                PlasmaComponents.Label {
                    Layout.preferredWidth: Math.ceil(headerSpeedMetrics.width)
                    text: '↑ ' + popup.speedLabel(upSpeed)
                    color: popup.upColor
                    font.pointSize: zFontSize * 1.4
                    font.bold: true
                }
                Item { Layout.fillWidth: true }
                PlasmaComponents.Label {
                    visible: showDisconnected && connectionKnown && !connected
                    text: i18n('Not connected')
                    color: Kirigami.Theme.negativeTextColor
                }
            }

            // ---- graph --------------------------------------------------------
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: zGrid * 5
                color: "transparent"
                border.width: 1
                border.color: Qt.alpha(Kirigami.Theme.textColor, 0.2)
                radius: zRadius

                SpeedGraph {
                    id: graph
                    anchors.fill: parent
                    anchors.margins: 1
                    downData: historyDown
                    upData: historyUp
                    capacity: historyLength
                    downColor: popup.downColor
                    upColor: popup.upColor
                }
                PlasmaComponents.Label {
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.margins: zSmall
                    text: popup.speedLabel(Math.max(1024, graph.maximum))
                    font: zSmallFont
                    opacity: 0.6
                }
                PlasmaComponents.Label {
                    anchors.bottom: parent.bottom
                    anchors.right: parent.right
                    anchors.margins: zSmall
                    text: i18n('last %1 s', Math.round(historyLength * updateMs / 1000))
                    font: zSmallFont
                    opacity: 0.6
                }
            }

            // ---- all connections: counters, limits, actions ---------------------
            // The same kind of box as the interfaces below
            Rectangle {
                id: allBox

                // limits that count everything, and limits of an interface that has no box right now
                readonly property var limits: limitStates.filter(state => state.iface === '' || popup.interfaceNames.indexOf(state.iface) === -1)

                Layout.fillWidth: true
                Layout.topMargin: zSmall
                implicitHeight: allColumn.implicitHeight + 2 * zSmall
                radius: zRadius
                color: Qt.alpha(Kirigami.Theme.textColor, 0.05)
                border.width: 1
                border.color: Qt.alpha(Kirigami.Theme.textColor, 0.15)

                ColumnLayout {
                    id: allColumn
                    anchors.fill: parent
                    anchors.margins: zSmall
                    spacing: Math.round(zSmall / 2)

                    // Header strip: title and the two actions
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: allHead.implicitHeight + zSmall
                        radius: zRadius
                        color: Qt.alpha(Kirigami.Theme.textColor, 0.13)

                        RowLayout {
                            id: allHead
                            anchors.fill: parent
                            anchors.leftMargin: zSmall
                            anchors.rightMargin: Math.round(zSmall / 2)
                            spacing: zSmall

                            Kirigami.Icon {
                                Layout.preferredWidth: zIcon
                                Layout.preferredHeight: zIcon
                                source: 'network-workgroup'
                            }
                            PlasmaComponents.Label {
                                Layout.fillWidth: true
                                text: i18n('All connections')
                                font.bold: true
                                font.pointSize: zFontSize * 1.1
                                elide: Text.ElideRight
                            }
                            PlasmaComponents.ToolButton {
                                id: copyAllButton
                                property bool copied: false
                                text: copied ? i18n('Copied') : i18n('Copy all')
                                icon.name: 'edit-copy'
                                onClicked: {
                                    const text = connectionSummary()
                                    if (text !== '') {
                                        copyText(text)
                                        copied = true
                                        copyAllTimer.restart()
                                    }
                                }
                                QQC2.ToolTip.text: i18n('Copies interface, addresses, gateway, DNS, signal and the external IP address (when checked) as text.')
                                QQC2.ToolTip.visible: hovered
                                QQC2.ToolTip.delay: 500

                                Timer {
                                    id: copyAllTimer
                                    interval: 1500
                                    onTriggered: copyAllButton.copied = false
                                }
                            }
                            PlasmaComponents.ToolButton {
                                text: i18n('Reset …')
                                icon.name: 'edit-clear-history'
                                checkable: true
                                checked: resetChoices.visible
                                onClicked: resetChoices.visible = !resetChoices.visible
                            }
                        }
                    }
                    // What to reset: shown by the button above, hidden again after a choice
                    Flow {
                        id: resetChoices
                        Layout.fillWidth: true
                        visible: false
                        spacing: zSmall

                        Repeater {
                            model: [
                                { what: 'session', label: i18n('Peak and session') },
                                { what: 'today', label: i18n('Today') },
                                { what: 'month', label: i18n('This month') },
                                { what: 'limits', label: i18n('Data limits') },
                                { what: 'history', label: i18n('History') },
                                { what: 'all', label: i18n('Everything') }
                            ]
                            PlasmaComponents.Button {
                                required property var modelData
                                text: modelData.label
                                onClicked: {
                                    resetCounters(modelData.what)
                                    resetChoices.visible = false
                                }
                            }
                        }
                    }
                    // Four tiles: peak, session, today, month. Number and unit stay on one line.
                    // The tiles are created once (a fixed number) and only their texts change:
                    // a list that is rebuilt every second, or one that depends on theme colours,
                    // would destroy and recreate them all the time (that crashed Plasma once during development).
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Math.round(zSmall / 2)

                        Repeater {
                            model: 4

                            StatTile {
                                required property int index
                                label: popup.tileLabel(index)
                                down: popup.tileValue(index, true)
                                up: popup.tileValue(index, false)
                                note: i18n('Counted while this widget is running.')
                            }
                        }
                    }
                    Repeater {
                        // the number of rows; each row follows its entry of the list
                        model: allBox.limits.length
                        LimitRow {
                            required property int index
                            state: allBox.limits[index] || emptyLimit
                            showName: state.iface !== ''
                        }
                    }
                }
            }

            // ---- interfaces ---------------------------------------------------
            Repeater {
                model: popup.interfaceList

                // One box per interface
                Rectangle {
                    id: device
                    required property string modelData
                    readonly property var speeds: speedData[modelData] || ({ down: 0, up: 0, downTotal: 0, upTotal: 0, operstate: '' })
                    readonly property var info: deviceSensors[modelData] || null
                    readonly property var limits: limitStates.filter(state => state.iface === device.modelData)
                    // today / month of this interface, when they are counted
                    readonly property var counted: (perInterfaceUsage && usage.ifaces) ? (usage.ifaces[device.modelData] || null) : null

                    Layout.fillWidth: true
                    implicitHeight: deviceColumn.implicitHeight + 2 * zSmall
                    radius: zRadius
                    color: Qt.alpha(Kirigami.Theme.textColor, 0.05)
                    border.width: 1
                    border.color: Qt.alpha(Kirigami.Theme.textColor, 0.15)

                    ColumnLayout {
                        id: deviceColumn
                        anchors.fill: parent
                        anchors.margins: zSmall
                        spacing: 0

                        // Header strip: icon, interface name, connection name, signal / state
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.bottomMargin: Math.round(zSmall / 2)
                            implicitHeight: headerRow.implicitHeight + zSmall
                            radius: zRadius
                            color: Qt.alpha(Kirigami.Theme.textColor, device.speeds.operstate === 'down' ? 0.06 : 0.13)

                            RowLayout {
                                id: headerRow
                                anchors.fill: parent
                                anchors.leftMargin: zSmall
                                anchors.rightMargin: zSmall
                                spacing: zSmall

                                Kirigami.Icon {
                                    Layout.preferredWidth: zIcon
                                    Layout.preferredHeight: zIcon
                                    source: device.speeds.wireless ? 'network-wireless' : 'network-wired'
                                    opacity: device.speeds.operstate === 'down' ? 0.5 : 1
                                }
                                PlasmaComponents.Label {
                                    textFormat: Text.PlainText   // never interpret a name or an answer as markup
                                    text: device.modelData
                                    font.bold: true
                                    font.pointSize: zFontSize * 1.1
                                    opacity: device.speeds.operstate === 'down' ? 0.6 : 1
                                }
                                PlasmaComponents.Label {
                                    Layout.fillWidth: true
                                    textFormat: Text.PlainText   // never interpret a name or an answer as markup
                                    text: device.info && device.info.ssid !== '' ? device.info.ssid : ''
                                    elide: Text.ElideRight
                                    opacity: 0.8
                                }
                                // Latency to the router, next to the signal
                                PlasmaComponents.Label {
                                    visible: pingEnabled && latencyHost !== '' && latencyInterface === device.modelData
                                             && device.speeds.operstate !== 'down'
                                    text: latency >= 0 ? i18n('Router %1 ms', latency < 10 ? latency.toFixed(1) : latency.toFixed(0))
                                                       : i18n('Router: no answer')
                                    font.bold: true
                                    color: latency < 0 ? Kirigami.Theme.negativeTextColor
                                         : latency < 20 ? Kirigami.Theme.positiveTextColor
                                         : latency < 100 ? Kirigami.Theme.neutralTextColor : Kirigami.Theme.negativeTextColor
                                }
                                PlasmaComponents.Label {
                                    visible: device.info !== null && device.info.signal > 0
                                    text: device.info ? i18n('Signal %1 %', device.info.signal) : ''
                                    font.bold: true
                                    color: !device.info ? Kirigami.Theme.textColor
                                         : device.info.signal >= 60 ? Kirigami.Theme.positiveTextColor
                                         : device.info.signal >= 30 ? Kirigami.Theme.neutralTextColor : Kirigami.Theme.negativeTextColor
                                }
                                PlasmaComponents.Label {
                                    visible: device.speeds.operstate === 'down'
                                    text: i18n('down')
                                    font.bold: true
                                    color: Kirigami.Theme.negativeTextColor
                                }
                            }
                        }
                        // Tiles: speed and total always; today and month when they are counted.
                        // An interface that is down shows only its header.
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.topMargin: Math.round(zSmall / 2)
                            visible: device.speeds.operstate !== 'down'
                            spacing: Math.round(zSmall / 2)

                            StatTile {
                                label: i18n('Speed')
                                down: popup.speedLabel(device.speeds.down)
                                up: popup.speedLabel(device.speeds.up)
                            }
                            StatTile {
                                label: i18n('Total')
                                down: Utils.formatTotal(device.speeds.downTotal)
                                up: Utils.formatTotal(device.speeds.upTotal)
                                note: i18n('Since this connection came up.')
                            }
                            StatTile {
                                visible: device.counted !== null
                                label: i18n('Today')
                                down: device.counted ? Utils.formatTotal(device.counted.dayDown) : ''
                                up: device.counted ? Utils.formatTotal(device.counted.dayUp) : ''
                            }
                            StatTile {
                                visible: device.counted !== null
                                label: periodSince === '' ? i18n('This month') : i18n('Since %1', periodSince)
                                down: device.counted ? Utils.formatTotal(device.counted.monthDown) : ''
                                up: device.counted ? Utils.formatTotal(device.counted.monthUp) : ''
                            }
                        }
                        // Data limits of this interface
                        Repeater {
                            model: device.limits.length
                            LimitRow {
                                required property int index
                                state: device.limits[index] || emptyLimit
                                Layout.topMargin: Math.round(zSmall / 2)
                            }
                        }
                        // Addresses on tinted strips: IPv4, and IPv6 when the connection has it.
                        // A click copies the IP address of that strip.
                        AddressStrip {
                            visible: device.info !== null && device.info.ipv4 !== ''
                            address: device.info ? device.info.ipv4 : ''
                            line: !device.info ? '' : i18n('IP %1', device.info.ipv4)
                                  + (device.info.gateway !== '' ? '   ' + i18n('Gateway %1', device.info.gateway) : '')
                                  + (device.info.dns !== '' ? '   ' + i18n('DNS %1', device.info.dns) : '')
                        }
                        AddressStrip {
                            visible: device.info !== null && device.info.ipv6 !== ''
                            address: device.info ? device.info.ipv6 : ''
                            // two lines: an IPv6 address alone can fill the width
                            line: !device.info ? '' : i18n('IPv6 %1', device.info.ipv6)
                            line2: !device.info ? '' : [device.info.gateway6 !== '' ? i18n('Gateway %1', device.info.gateway6) : '',
                                                        device.info.dns6 !== '' ? i18n('DNS %1', device.info.dns6) : ''].filter(part => part !== '').join('   ')
                        }
                    }
                }
            }

            PlasmaComponents.Label {
                visible: popup.interfaceNames.length === 0
                text: i18n('Reading the network interfaces …')
                opacity: 0.6
            }

            // ---- past months ---------------------------------------------------
            // Filled from the month counter when a month ends; a click shows all 12
            Rectangle {
                id: historyBox

                property bool showAll: false
                readonly property var months: (usage.history || []).slice().reverse().slice(0, showAll ? 12 : 3)

                Layout.fillWidth: true
                Layout.topMargin: zSmall
                visible: usage.history !== undefined && usage.history.length > 0
                implicitHeight: historyColumn.implicitHeight + 2 * zSmall
                radius: zRadius
                color: Qt.alpha(Kirigami.Theme.textColor, 0.05)
                border.width: 1
                border.color: Qt.alpha(Kirigami.Theme.textColor, 0.15)

                ColumnLayout {
                    id: historyColumn
                    anchors.fill: parent
                    anchors.margins: zSmall
                    spacing: 0

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.bottomMargin: Math.round(zSmall / 2)
                        implicitHeight: historyHead.implicitHeight + zSmall
                        radius: zRadius
                        color: Qt.alpha(Kirigami.Theme.textColor, historyMouse.containsMouse ? 0.2 : 0.13)

                        RowLayout {
                            id: historyHead
                            anchors.fill: parent
                            anchors.leftMargin: zSmall
                            anchors.rightMargin: zSmall
                            spacing: zSmall

                            Kirigami.Icon {
                                Layout.preferredWidth: zIcon
                                Layout.preferredHeight: zIcon
                                source: 'view-calendar-month'
                            }
                            PlasmaComponents.Label {
                                text: i18n('History')
                                font.bold: true
                                font.pointSize: zFontSize * 1.1
                            }
                            PlasmaComponents.Label {
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignRight
                                opacity: 0.8
                                visible: usage.history !== undefined && usage.history.length > 3
                                text: historyBox.showAll ? i18n('show less') : i18n('show all %1 months', usage.history ? usage.history.length : 0)
                            }
                        }
                        MouseArea {
                            id: historyMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: usage.history !== undefined && usage.history.length > 3
                            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: historyBox.showAll = !historyBox.showAll
                        }
                    }
                    Repeater {
                        model: historyBox.months.length

                        RowLayout {
                            required property int index
                            readonly property var modelData: historyBox.months[index] || ({ month: '', day: 1, down: 0, up: 0 })
                            Layout.fillWidth: true
                            spacing: zLarge

                            PlasmaComponents.Label {
                                Layout.preferredWidth: zGrid * 10
                                opacity: 0.6
                                textFormat: Text.PlainText
                                text: popup.monthLabel(modelData.month, modelData.day)
                            }
                            PlasmaComponents.Label {
                                Layout.preferredWidth: zGrid * 6
                                text: '↓ ' + Utils.formatTotal(modelData.down)
                            }
                            PlasmaComponents.Label {
                                Layout.fillWidth: true
                                text: '↑ ' + Utils.formatTotal(modelData.up)
                            }
                        }
                    }
                }
            }

            // ---- internet check: runs only when asked for ----------------------
            // Same look as an interface box: header strip, then the address strip
            Rectangle {
                id: internetBox

                Layout.fillWidth: true
                Layout.topMargin: zSmall
                implicitHeight: internetColumn.implicitHeight + 2 * zSmall
                radius: zRadius
                color: Qt.alpha(Kirigami.Theme.textColor, 0.05)
                border.width: 1
                border.color: Qt.alpha(Kirigami.Theme.textColor, 0.15)

                ColumnLayout {
                    id: internetColumn
                    anchors.fill: parent
                    anchors.margins: zSmall
                    spacing: 0

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: internetRow.implicitHeight + zSmall
                        radius: zRadius
                        color: Qt.alpha(Kirigami.Theme.textColor, 0.13)

                        RowLayout {
                            id: internetRow
                            anchors.fill: parent
                            anchors.leftMargin: zSmall
                            anchors.rightMargin: Math.round(zSmall / 2)
                            spacing: zSmall

                            Kirigami.Icon {
                                Layout.preferredWidth: zIcon
                                Layout.preferredHeight: zIcon
                                source: 'globe'
                            }
                            PlasmaComponents.Label {
                                text: i18n('Internet')
                                font.bold: true
                                font.pointSize: zFontSize * 1.1
                            }
                            PlasmaComponents.Label {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                opacity: 0.8
                                textFormat: Text.PlainText   // never interpret a name or an answer as markup
                                text: internetPending > 0 ? i18n('checking …')
                                    : internetChecked ? internetHost
                                    : i18n('not checked yet')
                            }
                            PlasmaComponents.Label {
                                visible: internetChecked && internetPending === 0
                                text: internetLatency >= 0
                                    ? i18n('%1 ms', internetLatency < 10 ? internetLatency.toFixed(1) : internetLatency.toFixed(0))
                                    : i18n('no answer')
                                font.bold: true
                                color: internetLatency < 0 ? Kirigami.Theme.negativeTextColor
                                     : internetLatency < 50 ? Kirigami.Theme.positiveTextColor
                                     : internetLatency < 150 ? Kirigami.Theme.neutralTextColor : Kirigami.Theme.negativeTextColor
                            }
                            PlasmaComponents.ToolButton {
                                id: internetButton
                                text: internetChecked ? i18n('Check again') : i18n('Check')
                                icon.name: 'view-refresh'
                                enabled: internetPending === 0
                                onClicked: checkInternet()
                            }
                        }
                    }
                    // External address on a tinted strip; a click copies it
                    Rectangle {
                        id: externalStrip

                        property bool copied: false

                        Layout.fillWidth: true
                        Layout.topMargin: Math.round(zSmall / 2)
                        visible: internetChecked
                        implicitHeight: externalLabel.implicitHeight + zSmall
                        radius: zRadius
                        color: externalIp === '' ? Qt.alpha(Kirigami.Theme.textColor, 0.06)
                             : Qt.alpha(Kirigami.Theme.highlightColor, externalMouse.containsMouse ? 0.35 : 0.18)

                        PlasmaComponents.Label {
                            id: externalLabel
                            anchors.fill: parent
                            anchors.leftMargin: zSmall
                            anchors.rightMargin: zSmall
                            verticalAlignment: Text.AlignVCenter
                            textFormat: Text.PlainText   // never interpret a name or an answer as markup
                            text: externalStrip.copied ? i18n('Copied %1', externalIp)
                                : externalIp !== '' ? i18n('External IP %1', externalIp)
                                : internetPending > 0 ? i18n('External IP …')
                                : i18n('External IP not available')
                            font.bold: externalStrip.copied
                            opacity: externalIp === '' ? 0.6 : 1
                            elide: Text.ElideRight
                        }

                        MouseArea {
                            id: externalMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: externalIp !== ''
                            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: {
                                copyText(externalIp)
                                externalStrip.copied = true
                                externalCopiedTimer.restart()
                            }
                        }

                        Timer {
                            id: externalCopiedTimer
                            interval: 1500
                            onTriggered: externalStrip.copied = false
                        }
                    }
                }
            }

            PlasmaComponents.Label {
                Layout.fillWidth: true
                Layout.topMargin: zSmall
                text: (useSensors ? i18n('Panel reads the system sensors.') : i18n('Panel reads /proc/net/dev.'))
                    + ' ' + i18n('Click an address line to copy the IP address.')
                textFormat: Text.PlainText
                font: zSmallFont
                opacity: 0.5
                wrapMode: Text.Wrap
            }
            // Name and version of the widget on a line of their own, as in the tooltip
            Rectangle {
                visible: versionLabel !== ''
                implicitWidth: versionText.implicitWidth + 2 * zSmall
                implicitHeight: versionText.implicitHeight + Math.round(zSmall / 2)
                radius: zRadius
                color: versionTint

                PlasmaComponents.Label {
                    id: versionText
                    anchors.centerIn: parent
                    text: versionLabel
                    textFormat: Text.PlainText
                    font: zSmallFont
                }
            }
        }
    }
}
