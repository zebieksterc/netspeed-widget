/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 *
 * Settings page "Appearance" of the Netspeed Widget fork.
 */
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

// SimpleKCM is a scrollable page: the settings stay reachable on small screens
KCM.SimpleKCM {
    property int cfg_decimals: 1
    property alias cfg_fixedDigits: fixedDigits.checked
    property alias cfg_panelGraph: panelGraph.checked
    property alias cfg_showFrame: showFrame.checked
    property alias cfg_detailsZoom: detailsZoom.value
    property alias cfg_showSignal: showSignal.checked
    property alias cfg_showSignalPercent: showSignalPercent.checked
    property string cfg_signalPercentPosition: 'left'
    property alias cfg_hideWhenIdle: hideWhenIdle.checked
    property alias cfg_idleThreshold: idleThreshold.value

    Kirigami.FormLayout {

        // ---- display ----------------------------------------------------------
        ComboBox {
            Kirigami.FormData.label: i18n('Decimal places:')
            ToolTip.text: i18n('Digits after the decimal point: 1.3 kb/s or 1 kb/s. Fewer digits make the widget narrower.')
            ToolTip.visible: hovered
            ToolTip.delay: 500
            model: ['0', '1']
            currentIndex: cfg_decimals === 0 ? 0 : 1
            onActivated: index => cfg_decimals = index
        }
        CheckBox {
            id: fixedDigits
            ToolTip.text: i18n('Uses digits that are all equally wide, so the numbers stay in place while they change. Needs a font that offers such digits; most do.')
            ToolTip.visible: hovered
            ToolTip.delay: 500
            text: i18n('Digits of equal width (numbers do not shift)')
        }
        CheckBox {
            id: panelGraph
            ToolTip.text: i18n('Draws the last 60 readings behind the speeds in the panel: download and upload as two faint curves.')
            ToolTip.visible: hovered
            ToolTip.delay: 500
            text: i18n('Small graph behind the numbers')
        }
        CheckBox {
            id: showFrame
            ToolTip.text: i18n('A thin rounded border with a faint background around the whole widget, like the boxes in the details.')
            ToolTip.visible: hovered
            ToolTip.delay: 500
            text: i18n('Frame around the widget')
        }
        RowLayout {
            spacing: Kirigami.Units.smallSpacing

            // The wider bar with the percentage inside replaces the thin bar
            readonly property bool replaced: showSignalPercent.checked && cfg_signalPercentPosition !== 'left' && cfg_signalPercentPosition !== 'right'

            CheckBox {
                id: showSignal
                ToolTip.text: i18n('A thin vertical bar at the left edge of the widget; its height and colour follow the Wi-Fi signal strength.')
                ToolTip.visible: hovered
                ToolTip.delay: 500
                text: i18n('Wi-Fi signal bar at the left edge')
                enabled: !parent.replaced
            }
            SettingHint {
                visible: parent.replaced
                text: i18n('No effect with the current settings: the signal is already shown as a bar (wider bar or own line), which replaces this thin bar. Choose "next to the signal bar" or "after the speeds" for the percentage to use both.')
            }
        }
        CheckBox {
            id: showSignalPercent
            ToolTip.text: i18n('Shows the Wi-Fi signal strength as a number. Where it goes is chosen below. Nothing is shown on a wired connection, except on an own line.')
            ToolTip.visible: hovered
            ToolTip.delay: 500
            text: i18n('Wi-Fi signal in percent')
        }
        ComboBox {
            id: signalPercentPosition
            ToolTip.text: i18n('Own line: a separate line above the speeds with the network name; the widget gets taller. The other positions keep the signal beside the speeds.')
            ToolTip.visible: hovered
            ToolTip.delay: 500
            Kirigami.FormData.label: i18n('Position of the percentage:')
            enabled: showSignalPercent.checked
            textRole: 'label'
            model: [
                { label: i18n('Left, next to the signal bar'), value: 'left' },
                { label: i18n('Left, inside a wider signal bar'), value: 'bar' },
                { label: i18n('Right, after the speeds'), value: 'right' },
                { label: i18n('Own line: bar with network name'), value: 'lineBar' },
                { label: i18n('Own line: network name, thin bar below'), value: 'lineText' }
            ]
            currentIndex: Math.max(0, ['left', 'bar', 'right', 'lineBar', 'lineText'].indexOf(cfg_signalPercentPosition))
            onActivated: index => cfg_signalPercentPosition = model[index].value
        }
        Label {
            visible: showSignalPercent.checked && (cfg_signalPercentPosition === 'lineBar' || cfg_signalPercentPosition === 'lineText')
            text: i18n('The own line also names a wired connection. For both speeds on one line below it, set Layout to "Side by side" (General). The full name is in the tooltip.')
            wrapMode: Text.Wrap
            Layout.maximumWidth: Kirigami.Units.gridUnit * 22
            opacity: 0.7
        }

        // ---- details -----------------------------------------------------------
        Item { Kirigami.FormData.isSection: true; Kirigami.FormData.label: i18n('Details') }
        SpinBox {
            id: detailsZoom
            Kirigami.FormData.label: i18n('Size of the details (%):')
            from: 80
            to: 200
            stepSize: 10
            ToolTip.text: i18n('Makes everything in the details popup larger or smaller together: texts, icons, spacing and the popup itself. 100 is the normal size of your desktop font.')
            ToolTip.visible: hovered
            ToolTip.delay: 500
        }

        // ---- idle -------------------------------------------------------------
        Item { Kirigami.FormData.isSection: true; Kirigami.FormData.label: i18n('Idle') }
        CheckBox {
            id: hideWhenIdle
            ToolTip.text: i18n('After 5 seconds below the limit, the numbers are replaced by a pale ↓↑ mark. They return as soon as there is traffic.')
            ToolTip.visible: hovered
            ToolTip.delay: 500
            text: i18n('Shrink to a small mark while idle')
        }
        SpinBox {
            id: idleThreshold
            ToolTip.text: i18n('Traffic below this counts as idle. 1 KiB/s ignores the usual background chatter.')
            ToolTip.visible: hovered
            ToolTip.delay: 500
            Kirigami.FormData.label: i18n('Idle below (KiB/s):')
            from: 0
            to: 10000
            enabled: hideWhenIdle.checked
        }
    }
}
