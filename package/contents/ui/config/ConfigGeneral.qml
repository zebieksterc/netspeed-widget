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
// Settings page "General": layout, units, font size, update interval, colours (from the original widget;
// the fork added hover texts and the hints for options without effect).
// Modified 2026 for the fork (io.github.zebieksterc.netspeedwidget); see ChangeLog.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

// SimpleKCM is a scrollable page: the settings stay reachable on small screens
KCM.SimpleKCM {
    property alias cfg_showSeparately: showSeparately.checked
    property alias cfg_showLowSpeeds: showLowSpeeds.checked
    property string cfg_speedLayout: 'auto'
    property bool cfg_swapDownUp: false
    property alias cfg_showIcons: showIcons.checked
    property alias cfg_showUnits: showUnits.checked
    property string cfg_speedUnits: 'bytes'
    property alias cfg_shortUnits: shortUnits.checked
    property alias cfg_fontSize: fontSize.value
    property alias cfg_updateInterval: updateInterval.value
    property alias cfg_customColors: customColors.checked
    property alias cfg_byteColor: byteColorPicker.chosenColor
    property alias cfg_kilobyteColor: kilobyteColorPicker.chosenColor
    property alias cfg_megabyteColor: megabyteColorPicker.chosenColor
    property alias cfg_gigabyteColor: gigabyteColorPicker.chosenColor

    Kirigami.FormLayout {

        GridLayout {
            columns: 2

            Label {
                text: i18n('Layout:')
            }

            RowLayout {
                spacing: Kirigami.Units.smallSpacing

                ComboBox {
                    id: speedLayout
                    ToolTip.text: i18n('Automatic picks two rows or one row from the space in the panel. In a vertical panel it always uses two rows.')
                    ToolTip.visible: hovered
                    ToolTip.delay: 500
                    enabled: showSeparately.checked
                    textRole: 'label'
                    model: [
                        {
                            'label': i18n('Automatic'),
                            'value': 'auto'
                        },
                        {
                            'label': i18n('Above each other'),
                            'value': 'rows'
                        },
                        {
                            'label': i18n('Side by side'),
                            'value': 'columns'
                        }
                    ]
                    onCurrentIndexChanged: cfg_speedLayout = model[currentIndex]['value']

                    Component.onCompleted: {
                        for (var i = 0; i < model.length; i++) {
                            if (model[i]['value'] == plasmoid.configuration.speedLayout) {
                                speedLayout.currentIndex = i
                            }
                        }
                    }
                }
                SettingHint {
                    visible: !showSeparately.checked
                    text: i18n('No effect while download and upload are shown as one combined number ("Show download and upload speed separately" is off).')
                }
            }

            Label {
                text: i18n('Display order:')
            }

            RowLayout {
                spacing: Kirigami.Units.smallSpacing

                ComboBox {
                    id: displayOrder
                    ToolTip.text: i18n('Which speed comes first: on the upper row, or on the left when both are on one line.')
                    ToolTip.visible: hovered
                    ToolTip.delay: 500
                    enabled: showSeparately.checked
                    textRole: 'label'
                    model: [
                        {
                            'label': i18n('Show upload speed first'),
                            'value': 'up'
                        },
                        {
                            'label': i18n('Show download speed first'),
                            'value': 'down'
                        }
                    ]
                    onCurrentIndexChanged: cfg_swapDownUp = model[currentIndex]['value'] == 'up'

                    Component.onCompleted: {
                        if (plasmoid.configuration.swapDownUp) {
                            displayOrder.currentIndex = 0
                        } else {
                            displayOrder.currentIndex = 1
                        }
                    }
                }
                SettingHint {
                    visible: !showSeparately.checked
                    text: i18n('No effect while download and upload are shown as one combined number ("Show download and upload speed separately" is off).')
                }
            }

            Label {
                text: i18n('Speed units:')
            }

            ComboBox {
                id: speedUnits
                ToolTip.text: i18n('Bits: kb/s, Mb/s (as internet providers state speeds). Bytes: KiB/s, MiB/s (as download dialogs show them). 8 bits are 1 byte.')
                ToolTip.visible: hovered
                ToolTip.delay: 500
                textRole: 'label'
                model: [
                    {
                        'label': i18n('Bits'),
                        'value': 'bits'
                    },
                    {
                        'label': i18n('Bytes'),
                        'value': 'bytes'
                    }
                ]
                onCurrentIndexChanged: cfg_speedUnits = model[currentIndex]['value']

                Component.onCompleted: {
                    for (var i = 0; i < model.length; i++) {
                        if (model[i]['value'] == plasmoid.configuration.speedUnits) {
                            speedUnits.currentIndex = i
                        }
                    }
                }

                property string currentVal: model[currentIndex]['value']
            }

            CheckBox {
                id: showUnits
                ToolTip.text: i18n('Shows the unit (for example kb/s) after each number. Without it the widget is narrower, but you cannot see whether a number is kilo or mega.')
                ToolTip.visible: hovered
                ToolTip.delay: 500
                text: i18n('Show speed units')
                Layout.columnSpan: 2
            }

            CheckBox {
                id: shortUnits
                ToolTip.text: i18n('Shows only the first letter of the unit (k, M, G), which saves width.')
                ToolTip.visible: hovered
                ToolTip.delay: 500
                text: i18n('Use shortened speed units')
                Layout.columnSpan: 2
                enabled: showUnits.checked
            }

            CheckBox {
                id: showIcons
                ToolTip.text: i18n('Shows the arrows ↓ and ↑ in front of the speeds.')
                ToolTip.visible: hovered
                ToolTip.delay: 500
                text: i18n('Show upload and download icons')
                Layout.columnSpan: 2
            }

            CheckBox {
                id: showSeparately
                ToolTip.text: i18n('On: download and upload as two numbers. Off: one number, the sum of both.')
                ToolTip.visible: hovered
                ToolTip.delay: 500
                text: i18n('Show download and upload speed separately')
                Layout.columnSpan: 2
            }

            CheckBox {
                id: showLowSpeeds
                ToolTip.text: i18n('Off: anything below 1 kb/s (1 KiB/s) is shown as 0.0, so small background traffic does not make the numbers flicker.')
                ToolTip.visible: hovered
                ToolTip.delay: 500
                text: i18n('Show speeds below 1 kb/s')
                Layout.columnSpan: 2
            }

            Label {
                text: i18n('Font size:')
            }

            SpinBox {
                id: fontSize
                ToolTip.text: i18n('Size of the text relative to the space the panel gives the widget. Lower it when the widget is too tall or too wide. In a vertical panel the speeds already fill the width at 100 %, so more only enlarges the Wi-Fi and data limit lines.')
                ToolTip.visible: hovered
                ToolTip.delay: 500
                from: 10
                to: 200
                stepSize: 5
                textFromValue: function(value) { return value + ' %'; }
                valueFromText: function(text) { return Number(text.remove(RegExp(' %$'))); }
            }

            Label {
                text: i18n('Update interval:')
            }

            SpinBox {
                id: updateInterval
                ToolTip.text: i18n('How often the speeds are refreshed. The speed shown is the average over this time.')
                ToolTip.visible: hovered
                ToolTip.delay: 500
                from: 1
                to: 10
                stepSize: 1
                textFromValue: function(value) { return value + ' s'; }
                valueFromText: function(text) { return Number(text.remove(RegExp(' s$'))); }
            }

            GroupBox {
                label: CheckBox {
                    id: customColors
                    ToolTip.text: i18n('Colours the numbers by size (B, K, M, G), so a fast transfer stands out. Off: the normal text colour of the panel.')
                    ToolTip.visible: hovered
                    ToolTip.delay: 500
                    text: i18n('Use custom colours')
                }
                Layout.columnSpan: 2

                GridLayout {
                    anchors.fill: parent
                    anchors.margins: Kirigami.Units.smallSpacing
                    columns: 2

                    Label {
                        text: {
                            if (speedUnits.currentVal === 'bits') {
                                return shortUnits.checked ? 'b' : 'b/s:'
                            } else {
                                return shortUnits.checked ? 'B' : 'B/s:'
                            }
                        }
                        Layout.alignment: Qt.AlignRight
                    }

                    ColorPicker {
                        id: byteColorPicker
                    }

                    Label {
                        text: {
                            if (speedUnits.currentVal === 'bits') {
                                return shortUnits.checked ? 'k:' : 'kb/s:'
                            } else {
                                return shortUnits.checked ? 'K:' : 'KiB/s:'
                            }
                        }
                        Layout.alignment: Qt.AlignRight
                    }

                    ColorPicker {
                        id: kilobyteColorPicker
                    }

                    Label {
                        text: {
                            if (speedUnits.currentVal === 'bits') {
                                return shortUnits.checked ? 'm:' : 'Mb/s:'
                            } else {
                                return shortUnits.checked ? 'M:' : 'MiB/s:'
                            }
                        }
                        Layout.alignment: Qt.AlignRight
                    }

                    ColorPicker {
                        id: megabyteColorPicker
                    }

                    Label {
                        text: {
                            if (speedUnits.currentVal === 'bits') {
                                return shortUnits.checked ? 'g:' : 'Gb/s:'
                            } else {
                                return shortUnits.checked ? 'G:' : 'GiB/s:'
                            }
                        }
                        Layout.alignment: Qt.AlignRight
                    }

                    ColorPicker {
                        id: gigabyteColorPicker
                    }
                }
            }
        }
    }
}
