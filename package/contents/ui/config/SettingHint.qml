/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 *
 * Warning triangle for a setting that has no effect, or a side effect, with the
 * current combination of settings. The explanation shows on hover.
 */
import QtQuick
import QtQuick.Controls
import org.kde.kirigami as Kirigami

Kirigami.Icon {
    id: hint

    property string text: ''

    implicitWidth: Kirigami.Units.iconSizes.small
    implicitHeight: Kirigami.Units.iconSizes.small
    source: 'dialog-warning'

    HoverHandler {
        id: hover
    }

    ToolTip.visible: hover.hovered && hint.text !== ''
    ToolTip.text: hint.text
    ToolTip.delay: 300
}
