/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 *
 * Entry in the widget's right-click menu. While a click launches an application,
 * "Show details" is the way to the details popup. Loaded through a Loader, so
 * the widget still works should this file fail to load.
 */
import QtQuick
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore

Item {
    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            text: i18n('Show details')
            icon.name: 'view-list-details'
            visible: launchOnClick
            onTriggered: showDetails()
        }
    ]
}
