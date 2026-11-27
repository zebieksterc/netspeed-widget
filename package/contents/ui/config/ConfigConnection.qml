/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 *
 * Settings page "Connection" of the Netspeed Widget fork.
 */
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

// SimpleKCM is a scrollable page: the settings stay reachable on small screens
KCM.SimpleKCM {
    property alias cfg_showDisconnected: showDisconnected.checked
    property alias cfg_notifyConnection: notifyConnection.checked
    property alias cfg_signalWarnLevel: signalWarnLevel.value
    property alias cfg_pingEnabled: pingEnabled.checked
    property alias cfg_pingHost: pingHost.text
    property alias cfg_pingInterval: pingInterval.value
    property alias cfg_externalIpEnabled: externalIpEnabled.checked
    property alias cfg_externalIpUrl: externalIpUrl.text

    Kirigami.FormLayout {

        // ---- connection -------------------------------------------------------
        CheckBox {
            id: showDisconnected
            ToolTip.text: i18n('The widget turns pale while no network interface is connected, so a lost connection is visible at a glance.')
            ToolTip.visible: hovered
            ToolTip.delay: 500
            text: i18n('Dim the widget while not connected')
        }
        CheckBox {
            id: notifyConnection
            ToolTip.text: i18n('A desktop notification when the last connection is lost and when one is back. They stay in the notification history.')
            ToolTip.visible: hovered
            ToolTip.delay: 500
            text: i18n('Notify when the connection is lost or returns')
        }

        SpinBox {
            id: signalWarnLevel
            Kirigami.FormData.label: i18n('Warn when the Wi-Fi signal stays below (%, 0 = off):')
            from: 0
            to: 90
            stepSize: 5
            ToolTip.text: i18n('A notification when the signal is below this level for a full minute. It comes once, and again only after the signal has recovered. 30 is a sensible level.')
            ToolTip.visible: hovered
            ToolTip.delay: 500
        }

        // ---- extras that start a process or use the internet ------------------
        Item { Kirigami.FormData.isSection: true; Kirigami.FormData.label: i18n('Latency to the router') }
        RowLayout {
            spacing: Kirigami.Units.smallSpacing

            CheckBox {
                id: pingEnabled
                ToolTip.text: i18n('Sends one ping to your router (the gateway) at the interval below. Shown in the details next to the signal, in the tooltip, and on the own Wi-Fi line of the widget. Nothing leaves your local network.')
                ToolTip.visible: hovered
                ToolTip.delay: 500
                text: i18n('Measure with ping and show next to the signal (one short process per measurement)')
            }
        }
        SpinBox {
            id: pingInterval
            ToolTip.text: i18n('Time between two measurements. 15 to 30 seconds is plenty.')
            ToolTip.visible: hovered
            ToolTip.delay: 500
            Kirigami.FormData.label: i18n('Every (seconds):')
            from: 5
            to: 3600
            enabled: pingEnabled.checked
        }

        Item { Kirigami.FormData.isSection: true; Kirigami.FormData.label: i18n('Internet check (button in the details)') }
        TextField {
            id: pingHost
            ToolTip.text: i18n('The internet address the Check button pings, as a name or an IP address. Empty uses 1.1.1.1.')
            ToolTip.visible: hovered
            ToolTip.delay: 500
            Kirigami.FormData.label: i18n('Host to ping:')
            placeholderText: i18n('empty = 1.1.1.1')
        }
        TextField {
            id: externalIpUrl
            ToolTip.text: i18n('A web address that answers with your public IP address as plain text. Must start with https://.')
            ToolTip.visible: hovered
            ToolTip.delay: 500
            Kirigami.FormData.label: i18n('External IP service (https; it sees your address on every check):')
            Layout.minimumWidth: Kirigami.Units.gridUnit * 16
        }
        CheckBox {
            id: externalIpEnabled
            ToolTip.text: i18n('On: the external IP service and the internet host are contacted every time you open the details.')
            ToolTip.visible: hovered
            ToolTip.delay: 500
            text: i18n('Also check every time the details open (otherwise only when the button is pressed)')
        }
    }
}
