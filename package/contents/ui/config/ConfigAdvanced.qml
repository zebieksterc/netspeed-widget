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
// Settings page "Advanced": launch an application on click, count only selected interfaces, mouse options
// (from the original widget; the mouse options, hover texts and hints are the fork's).
// Modified 2026 for the fork (io.github.zebieksterc.netspeedwidget); see ChangeLog.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM
import org.kde.plasma.plasma5support as Plasma5Support
import "../../code/utils.js" as Utils

// SimpleKCM is a scrollable page: the settings stay reachable on small screens
KCM.SimpleKCM {
    property alias cfg_launchApplicationEnabled: launchApplicationEnabled.checked
    property alias cfg_launchApplication: launchApplication.menuId
    property alias cfg_interfacesWhitelistEnabled: interfacesWhitelistEnabled.checked
    property var cfg_interfacesWhitelist: []
    property alias cfg_scrollSwitchesUnits: scrollSwitchesUnits.checked
    property alias cfg_middleClickCopiesIp: middleClickCopiesIp.checked

    Kirigami.FormLayout {

        Plasma5Support.DataSource {
            id: dataSource
            engine: 'executable'
            connectedSources: [Utils.NET_DATA_SOURCE]

            onNewData: (sourceName, data) => {
                // run just once
                connectedSources.length = 0

                if (data['exit code'] > 0) {
                    print(data.stderr)
                } else {
                    const transferData = Utils.parseTransferData(data.stdout)

                    interfacesWhitelist.model.clear()

                    for (const name of plasmoid.configuration.interfacesWhitelist) {
                        interfacesWhitelist.model.append({ name, shown: true })
                    }

                    for (var name in transferData) {
                        if (plasmoid.configuration.interfacesWhitelist.indexOf(name) !== -1) {
                            continue
                        }

                        interfacesWhitelist.model.append({ name, shown: false })
                    }
                }
            }
        }

        ListModel {
            id: interfacesModel
        }

        GridLayout {
            columns: 2

            CheckBox {
                id: launchApplicationEnabled
                ToolTip.text: i18n('For example a system monitor or the network settings. The details then open from the right-click menu (Show details).')
                ToolTip.visible: hovered
                ToolTip.delay: 500
                text: i18n('Launch application when clicked:')
            }

            RowLayout {
                spacing: Kirigami.Units.smallSpacing

                AppPicker {
                    id: launchApplication
                    enabled: launchApplicationEnabled.checked
                }
                SettingHint {
                    visible: launchApplicationEnabled.checked
                    text: i18n('A click on the widget then launches the application instead of opening the details. The details (graph, counters, interfaces, internet check) stay reachable: right-click the widget and choose "Show details".')
                }
            }

            CheckBox {
                id: interfacesWhitelistEnabled
                ToolTip.text: i18n('Counts only the ticked interfaces, for example only the VPN or only Wi-Fi. The widget then reads /proc/net/dev (one short process per update) instead of the system sensors.')
                ToolTip.visible: hovered
                ToolTip.delay: 500
                text: i18n('Show only the following network interfaces:')
                Layout.columnSpan: 2
            }

            Label {
                text: i18n('When this is off, all physical network devices are counted.\nVirtual ones (VPN, bridges, containers) are ignored, so traffic is not counted twice.')
                opacity: 0.7
                Layout.columnSpan: 2
            }

            Rectangle {
                height: 200
                border {
                    width: 1
                    color: Kirigami.Theme.alternateBackgroundColor
                }
                radius: 2
                color: Kirigami.Theme.backgroundColor
                Layout.columnSpan: 2
                Layout.fillWidth: true

                ScrollView {
                    anchors.fill: parent

                    ListView {
                        id: interfacesWhitelist
                        anchors.fill: parent
                        clip: true
                        Layout.columnSpan: 2

                        model: interfacesModel

                        delegate: Item {
                            id: interfaceItem
                            height: Kirigami.Units.iconSizes.smallMedium + 2*Kirigami.Units.smallSpacing

                            property bool isHovered: false

                            CheckBox {
                                x: Kirigami.Units.smallSpacing
                                y: Kirigami.Units.smallSpacing

                                text: name
                                checked: shown
                                enabled: interfacesWhitelistEnabled.checked

                                onCheckedChanged: {
                                    // Assign a new list: changing it in place does not
                                    // tell the settings dialog that something changed
                                    var list = Array.from(cfg_interfacesWhitelist)
                                    var index = list.indexOf(name)
                                    if (checked && index === -1) {
                                        list.push(name)
                                    } else if (!checked && index !== -1) {
                                        list.splice(index, 1)
                                    } else {
                                        return
                                    }
                                    cfg_interfacesWhitelist = list
                                }
                            }
                        }
                    }
                }
            }
        }

        // ---- mouse ------------------------------------------------------------
        Item { Kirigami.FormData.isSection: true; Kirigami.FormData.label: i18n('Mouse') }
        Label {
            text: i18n('A click opens the details, or launches the application chosen above.')
            opacity: 0.7
        }
        CheckBox {
            id: scrollSwitchesUnits
            ToolTip.text: i18n('Turning the mouse wheel over the widget changes the Speed units setting (General) and keeps it.')
            ToolTip.visible: hovered
            ToolTip.delay: 500
            text: i18n('Scrolling switches between bits and bytes')
        }
        CheckBox {
            id: middleClickCopiesIp
            ToolTip.text: i18n('Puts the IP address of this computer in the local network (IPv4, or IPv6 when there is no IPv4) on the clipboard and shows a short notification.')
            ToolTip.visible: hovered
            ToolTip.delay: 500
            text: i18n('Middle-click copies the IP address')
        }
    }
}
