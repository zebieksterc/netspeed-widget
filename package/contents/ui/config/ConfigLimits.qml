/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 *
 * Settings page "Data limits" of the Netspeed Widget fork: up to 8 limits
 * (the number is MAX_LIMITS in utils.js), each for all connections or for one network interface, with its own
 * start day, start value and reset.
 *
 * The list is stored as JSON text in dataLimits:
 *   [{ "id": "a1", "iface": "wwan0", "limit": 50, "day": 15, "usedTenths": 125 }]
 */
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM
import org.kde.plasma.plasma5support as Plasma5Support
import "../../code/utils.js" as Utils

KCM.SimpleKCM {
    id: page

    property string cfg_dataLimits: ''
    property string cfg_dataLimitsPanel: 'auto'
    property alias cfg_periodStartDay: periodStartDay.value
    property alias cfg_perInterfaceUsage: perInterfaceUsage.checked

    // The list being edited, and the physical interfaces of this computer
    property var limits: []
    property var interfaces: []
    // True once the list has been read from the settings (earlier changes of the controls are not edits)
    property bool loaded: false

    onCfg_dataLimitsChanged: {
        // only when the value comes from outside (the dialog loading, Defaults), not from our own edits
        if (cfg_dataLimits !== JSON.stringify(limits)) {
            limits = Utils.parseLimits(cfg_dataLimits)
        }
    }
    Component.onCompleted: {
        limits = Utils.parseLimits(cfg_dataLimits)
        loaded = true
    }

    // Takes a new list of limits and writes it to the setting (which enables Apply)
    function store(list) {
        limits = list
        cfg_dataLimits = list.length > 0 ? JSON.stringify(list) : ''
    }
    // Changes one field of one limit
    function change(index, key, value) {
        if (!loaded || index < 0 || index >= limits.length || limits[index][key] === value) {
            return
        }
        const list = limits.map(item => Object.assign({}, item))
        list[index][key] = value
        store(list)
    }
    // Adds a limit with an id that is not in use yet
    function add() {
        const list = limits.map(item => Object.assign({}, item))
        let n = 1
        while (list.some(item => item.id === 'l' + n)) {
            ++n
        }
        list.push({ id: 'l' + n, iface: '', limit: 50, day: 1, usedTenths: 0 })
        store(list)
    }
    // Removes a limit
    function remove(index) {
        store(limits.filter((item, i) => i !== index))
    }
    // "All connections" plus the interfaces; one that is saved but not plugged in stays selectable
    function choices(current) {
        const names = interfaces.slice()
        if (current !== '' && names.indexOf(current) === -1) {
            names.push(current)
        }
        return [{ label: i18n('All connections'), value: '' }].concat(names.map(name => ({ label: i18n('Only %1', name), value: name })))
    }

    Plasma5Support.DataSource {
        engine: 'executable'
        connectedSources: [Utils.NET_DATA_SOURCE]
        onNewData: (sourceName, data) => {
            connectedSources.length = 0     // run just once
            if (!(data['exit code'] > 0)) {
                const info = Utils.parseTransferData(data.stdout)
                page.interfaces = Object.keys(info).filter(name => info[name].physical)
            }
        }
    }

    ColumnLayout {
        spacing: Kirigami.Units.largeSpacing

        Kirigami.FormLayout {
            Layout.fillWidth: true

            ComboBox {
                id: panelMode
                Kirigami.FormData.label: i18n('In the widget show:')
                Layout.minimumWidth: Kirigami.Units.gridUnit * 16
                textRole: 'label'
                model: [
                    { label: i18n('The limit of the connection in use'), value: 'auto' },
                    { label: i18n('All limits'), value: 'all' },
                    { label: i18n('No limit (only in the details)'), value: 'none' }
                ]
                currentIndex: Math.max(0, ['auto', 'all', 'none'].indexOf(cfg_dataLimitsPanel))
                onActivated: index => cfg_dataLimitsPanel = model[index].value
                ToolTip.text: i18n('Each limit shown adds a line below the speeds, and the frame of the widget takes the colour of the limit that is furthest along. "Connection in use" shows the limit of the interface that is connected right now (Wi-Fi before cable), plus a limit that counts all connections.')
                ToolTip.visible: hovered
                ToolTip.delay: 500
            }
            SpinBox {
                id: periodStartDay
                Kirigami.FormData.label: i18n('"This month" in the details starts on day:')
                from: 1
                to: 28
                ToolTip.text: i18n('For the month counter and the history in the details. Each limit below has a start day of its own.')
                ToolTip.visible: hovered
                ToolTip.delay: 500
            }
            // ---- counting per interface ----
            CheckBox {
                id: perInterfaceUsage
                text: i18n('Count today and this month for each interface')
                ToolTip.text: i18n('Adds "Today" and "This month" tiles to each interface in the details. For this the widget reads the interface list every 30 seconds (every 5 seconds while nothing is transferred) with one short process.')
                ToolTip.visible: hovered
                ToolTip.delay: 500
            }
        }

        Label {
            Layout.fillWidth: true
            visible: page.limits.length === 0
            wrapMode: Text.Wrap
            opacity: 0.7
            text: i18n('No data limit yet. A limit counts download plus upload over a month and warns you at 80 % and at 100 %.')
        }

        Repeater {
            model: page.limits.length

            Rectangle {
                id: block
                required property int index
                readonly property var entry: page.limits[index] || ({ id: '', iface: '', limit: 1, day: 1, usedTenths: 0 })

                Layout.fillWidth: true
                implicitHeight: blockLayout.implicitHeight + 2 * Kirigami.Units.largeSpacing
                radius: Kirigami.Units.cornerRadius
                color: Qt.alpha(Kirigami.Theme.textColor, 0.04)
                border.width: 1
                border.color: Qt.alpha(Kirigami.Theme.textColor, 0.15)

                ColumnLayout {
                    id: blockLayout
                    anchors.fill: parent
                    anchors.margins: Kirigami.Units.largeSpacing
                    spacing: Kirigami.Units.smallSpacing

                    GridLayout {
                        Layout.fillWidth: true
                        columns: 4
                        columnSpacing: Kirigami.Units.largeSpacing
                        rowSpacing: Kirigami.Units.smallSpacing

                        Label { text: i18n('Connection:') }
                        ComboBox {
                            Layout.fillWidth: true
                            textRole: 'label'
                            model: page.choices(block.entry.iface)
                            currentIndex: Math.max(0, model.findIndex(item => item.value === block.entry.iface))
                            onActivated: i => page.change(block.index, 'iface', model[i].value)
                            ToolTip.text: i18n('All connections, or only one network interface - for example the mobile modem or a tethered phone, so that traffic over home Wi-Fi does not count. For one interface the widget reads its byte counter every 30 seconds (one short process); that counter also includes traffic from before you logged in.')
                            ToolTip.visible: hovered
                            ToolTip.delay: 500
                        }
                        Label { text: i18n('Limit (GiB):') }
                        SpinBox {
                            from: 1
                            to: 100000
                            editable: true
                            value: block.entry.limit
                            onValueModified: page.change(block.index, 'limit', value)
                            ToolTip.text: i18n('Download plus upload of one month. You get a notification at 80 % and at 100 %.')
                            ToolTip.visible: hovered
                            ToolTip.delay: 500
                        }

                        Label { text: i18n('Month starts on day:') }
                        SpinBox {
                            from: 1
                            to: 28
                            editable: true
                            value: block.entry.day
                            onValueModified: page.change(block.index, 'day', value)
                            ToolTip.text: i18n('The day this data plan renews. On that day the counter of this limit starts again from zero.')
                            ToolTip.visible: hovered
                            ToolTip.delay: 500
                        }
                        Label { text: i18n('Already used (GiB):') }
                        SpinBox {
                            id: usedBox
                            from: 0
                            to: 10000000
                            editable: true
                            // kept in tenths of a GiB
                            textFromValue: function(v) { return (v / 10).toFixed(1) }
                            valueFromText: function(text) { return Math.round((parseFloat(String(text).replace(',', '.')) || 0) * 10) }
                            value: block.entry.usedTenths
                            onValueModified: page.change(block.index, 'usedTenths', value)
                            ToolTip.text: i18n('What your provider says you have used so far in this month, before this widget began to count. It is added to what the widget counts and goes back to 0 by itself when the next month of this limit starts.')
                            ToolTip.visible: hovered
                            ToolTip.delay: 500
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing

                        Button {
                            id: resetButton
                            property bool done: false
                            text: done ? i18n('Done - counting from zero') : i18n('Reset this limit now')
                            icon.name: 'edit-clear-history'
                            onClicked: {
                                // takes effect at once; the start value goes back to 0 with it
                                plasmoid.configuration.resetRequest = 'limit:' + block.entry.id + ':' + Date.now()
                                page.change(block.index, 'usedTenths', 0)
                                done = true
                            }
                            ToolTip.text: i18n('Sets the counter of this limit, its warnings and "Already used" back to zero - right away, without Apply. For a clean start: choose connection and start day, press Apply, press this button, then enter the figure from your provider under "Already used" and press Apply again.')
                            ToolTip.visible: hovered
                            ToolTip.delay: 500
                        }
                        Item { Layout.fillWidth: true }
                        Button {
                            text: i18n('Remove')
                            icon.name: 'list-remove'
                            onClicked: page.remove(block.index)
                        }
                    }
                }
            }
        }

        Button {
            text: i18n('Add a limit')
            icon.name: 'list-add'
            enabled: page.limits.length < 8     // MAX_LIMITS in utils.js
            onClicked: page.add()
        }
    }
}
