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
// Modified 2026 for the fork (io.github.zebieksterc.netspeedwidget); see ChangeLog.
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami
import "../code/utils.js" as Utils

// The panel item. In order:
//   sizes and which lines are shown (frame, own Wi-Fi line, data limit lines), the size the widget asks the
//   panel for, text widths; then the drawing: frame, thin signal bar, graph, idle mark, the speeds
//   (arrows, numbers, units - positioned by anchors, sized from the height), signal percentage and wide bar,
//   own Wi-Fi line, data limit lines, the flash for a middle click, the mouse handling,
//   and three small functions for the text, colour and unit of a speed.
Item {
    anchors.fill: parent

    // Space between the parts of the speed line, as a share of the font size

    property double marginFactor: 0.2

    // "Font size" of the settings. In a vertical panel the speeds cannot be wider
    // than the panel, so more than 100 % has no effect on them there (it used to
    // push the numbers out of the widget); the extra lines follow the setting.
    // In a horizontal panel the height is given: there the text may grow until its
    // font is as tall as its row; more would cut the numbers off at top and bottom.
    property double fontSizeScale: plasmoid.formFactor === PlasmaCore.Types.Vertical ? Math.min(1, userFontScale)
                                 : plasmoid.formFactor === PlasmaCore.Types.Horizontal ? Math.min(userFontScale, 1 / fontHeightRatio)
                                 : userFontScale
    property double extraLineScale: Math.max(0.6, Math.min(1.6, userFontScale))
    // in a horizontal panel the lines have a fixed share of the height; there the setting can only make their text smaller
    property double extraTextScale: plasmoid.formFactor === PlasmaCore.Types.Vertical ? 1 : Math.max(0.6, Math.min(1, userFontScale))

    // Optional frame around the widget; everything else is drawn inside it
    // (the frame is also drawn, in the colour of the data limit, while the limit line is shown)
    property bool frameShown: showFrame || limitLineSpace
    property double framePad: frameShown ? Math.max(2, Math.round(Kirigami.Units.smallSpacing * 0.75)) : 0
    property double innerWidth: Math.max(1, width - 2 * framePad)
    property double innerHeight: Math.max(1, height - 2 * framePad)

    // downSpeed and upSpeed (bytes per second) are provided by main.qml

    property bool singleLine: {
        if (!showSeparately) {
            return true
        }
        switch (speedLayout) {
            case 'rows': return false
            case 'columns': return true
            default: return speedHeight / 2 * fontSizeScale < Kirigami.Theme.smallFont.pixelSize && plasmoid.formFactor != PlasmaCore.Types.Vertical
        }
    }

    property double marginWidth: speedTextMetrics.font.pixelSize * marginFactor
    property double iconWidth: showIcons ? iconTextMetrics.width + marginWidth : 0
    property double doubleIconWidth: showIcons ? (doubleIconTextMetrics.width + marginWidth) : 0
    property double speedWidth: speedTextMetrics.width + 2*marginWidth
    property double unitWidth: showUnits ? unitTextMetrics.width + marginWidth : 0
    // Network name and signal on a line of their own above the speeds (two styles):
    // 'lineBar' = a bar with icon, name and percentage inside; 'lineText' = text with a thin bar below.
    // The speeds then use the height that is left (speedHeight).
    property bool linkLineShown: ownSignalLine && linkName !== '' && !idle
    property bool linkLineBar: signalPercentPosition === 'lineBar'
    // the space is kept while idle, so the widget does not change its height
    property bool linkLineSpace: ownSignalLine && linkName !== ''
    // Data limits: one line each below the speeds (see panelLimitStates in main.qml)
    property int limitLineCount: panelLimitStates.length
    property bool limitLineSpace: limitLineCount > 0
    // the limit that is furthest along gives the frame its colour
    property double limitWorst: panelLimitStates.reduce((worst, state) => Math.max(worst, state.fraction), 0)
    property bool limitLineShown: limitLineSpace && !idle
    // In a horizontal panel the lines share the height with the speeds
    property int extraLineCount: (linkLineSpace ? 1 : 0) + limitLineCount
    property double extraLineFraction: extraLineCount <= 1 ? 0.38 : Math.min(0.29, 0.62 / extraLineCount)
    property double extraLinePx: plasmoid.formFactor === PlasmaCore.Types.Vertical ? Math.round(innerWidth * 0.14 * extraLineScale)
                                                                                 : Math.round(innerHeight * extraLineFraction)
    property double linkLinePx: linkLineSpace ? extraLinePx : 0
    property double limitLinePx: limitLineCount * extraLinePx
    property double speedHeight: Math.max(1, innerHeight - linkLinePx - limitLinePx)

    property bool signalPercentShown: showSignalPercent && wifiSignal >= 0 && !ownSignalLine
    property bool signalInBar: signalPercentShown && signalPercentPosition === 'bar'
    // In the one-line layout the bar with the percentage is made larger than the text:
    // wider always, and taller where the widget is free to grow (vertical panel)
    property double barWiden: (signalInBar && singleLine) ? 1.4 : 1
    property double lineScale: (signalInBar && singleLine && plasmoid.formFactor === PlasmaCore.Types.Vertical) ? 1.7 : 1
    property double signalWidth: signalPercentShown ? signalTextMetrics.width * barWiden + 2*marginWidth : 0
    // The same in pixels, and where the percentage goes
    property double rowHeight: singleLine ? speedHeight / lineScale : speedHeight / 2
    property double signalPx: signalWidth / speedTextMetrics.height * rowHeight * fontSizeScale
    property bool signalAtLeft: signalPercentShown && signalPercentPosition !== 'right'
    property double signalBarWidth: Math.max(2, Math.round(innerHeight / 12))
    property color signalColor: wifiSignal >= 60 ? Kirigami.Theme.positiveTextColor
                              : wifiSignal >= 30 ? Kirigami.Theme.neutralTextColor : Kirigami.Theme.negativeTextColor

    // Width / height of the speed block for the current settings; the texts are sized from it

    property double aspectRatio: {
        if (showSeparately) {
            if (singleLine) {
                return (2*iconWidth + 2*speedWidth + 2*unitWidth + marginWidth + signalWidth) * fontSizeScale / speedTextMetrics.height
            } else {
                return (iconWidth + speedWidth + unitWidth + signalWidth) * fontSizeScale / (2*speedTextMetrics.height)
            }
        } else {
            return (doubleIconWidth + speedWidth + unitWidth + signalWidth) * fontSizeScale / speedTextMetrics.height
        }
    }

    property double fontHeightRatio: speedTextMetrics.font.pixelSize / speedTextMetrics.height

    // While idle only a small "↓↑" mark is shown
    property double idleAspectRatio: (doubleIconTextMetrics.width + 2 * marginWidth) * fontSizeScale / speedTextMetrics.height
    // Width / height of the whole widget (the text line may be lower than the widget)
    property double layoutAspectRatio: aspectRatio / lineScale
    property double shownAspectRatio: idle ? idleAspectRatio : layoutAspectRatio

    // Left margin that centres the speed block in a vertical panel

    property double offset: {
        if (plasmoid.formFactor === PlasmaCore.Types.Vertical) {
            return (innerWidth - speedHeight * shownAspectRatio) / 2
        } else {
            return 0
        }
    }

    Layout.minimumWidth: {
        if (plasmoid.formFactor === PlasmaCore.Types.Vertical) {
            return 0
        } else {
            // with its own line the widget is at least wide enough for icon, a short name and the percentage
            return Math.ceil(Math.max(speedHeight * shownAspectRatio, (extraLineCount > 0 ? extraLinePx : 0) * 4.5)) + 2 * framePad
        }
    }
    Layout.minimumHeight: {
        if (plasmoid.formFactor === PlasmaCore.Types.Vertical) {
            // below their own line the speeds do not grow to the full panel width (factor 0.8; not for speeds on one line, which are small already)
            // rounded down: one pixel more height would make the text wider than the panel
            return Math.floor(innerWidth / layoutAspectRatio * fontSizeScale * fontSizeScale * (((linkLineSpace || limitLineSpace) && !singleLine) ? 0.8 : 1)) + linkLinePx + limitLinePx + 2 * framePad
        } else if (plasmoid.formFactor === PlasmaCore.Types.Horizontal) {
            return 0
        } else {
            return Math.ceil(Kirigami.Theme.smallFont.pixelSize / fontSizeScale)
        }
    }

    Layout.preferredWidth: Layout.minimumWidth
    Layout.preferredHeight: Layout.minimumHeight
    // The size the widget asks the panel for (also read by the layout tests)
    readonly property double wantedWidth: Layout.minimumWidth
    readonly property double wantedHeight: Layout.minimumHeight

    // Reference texts measured at 64 px: their proportions give the widths of arrows, numbers and units

    TextMetrics {
        id: iconTextMetrics
        text: '↓'
        font.pixelSize: 64
    }

    TextMetrics {
        id: doubleIconTextMetrics
        text: '↓↑'
        font.pixelSize: 64
    }

    TextMetrics {
        id: speedTextMetrics
        text: decimals === 0 ? '1000' : '1000.0'
        font.pixelSize: 64
    }

    TextMetrics {
        id: signalTextMetrics
        text: '100%'
        font.pixelSize: 64
    }

    TextMetrics {
        id: unitTextMetrics
        text: {
            if (speedUnits === 'bits') {
                return shortUnits ? 'm' : 'Mb/s'
            } else {
                return shortUnits ? 'M' : 'MiB/s'
            }
        }
        font.pixelSize: 64
    }

    // Optional frame around the whole widget
    Rectangle {
        anchors.fill: parent
        visible: frameShown
        radius: Kirigami.Units.cornerRadius
        color: Qt.alpha(Kirigami.Theme.textColor, 0.05)
        border.width: 1
        // with a data limit the frame takes its colour: green, then gradually to red
        border.color: limitLineSpace ? Qt.alpha(limitColor(limitWorst), 0.9) : Qt.alpha(Kirigami.Theme.textColor, 0.25)
    }

    Item {
        id: inner
        x: framePad
        y: framePad
        width: innerWidth
        height: innerHeight

        // Thin bar at the left edge: Wi-Fi signal strength
        Rectangle {
            visible: showSignal && wifiSignal >= 0 && !idle && !signalInBar && !ownSignalLine
            x: 0
            width: signalBarWidth
            height: Math.max(1, Math.round(parent.height * Math.min(100, wifiSignal) / 100))
            y: parent.height - height
            radius: width / 2
            color: signalColor
            opacity: 0.9
        }

        // Optional graph behind the numbers
        Loader {
            x: 0
            y: linkLinePx
            width: parent.width
            height: speedHeight
            active: panelGraph
            visible: !idle
            z: -1
            sourceComponent: SpeedGraph {
                downData: historyDown
                upData: historyUp
                capacity: historyLength
                downColor: Kirigami.Theme.highlightColor
                upColor: Kirigami.Theme.neutralTextColor
                fillOpacity: 0.18
                lineWidth: 1
                opacity: 0.7
            }
        }

        // Shown instead of the numbers while idle (optional)
        Text {
            anchors.fill: parent
            visible: idle
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            font.pixelSize: (singleLine ? parent.height : parent.height / 2) * fontHeightRatio * fontSizeScale
            renderType: Text.NativeRendering
            text: '↓↑'
            color: Kirigami.Theme.textColor
            opacity: (showDisconnected && connectionKnown && !connected) ? 0.3 : 0.5
        }

        Item {
            id: content
            // The text line; lower than the widget when the signal bar is enlarged
            width: parent.width
            height: speedHeight / lineScale
            y: linkLinePx + (speedHeight - height) / 2
            visible: !idle
            // Dimmed while no network interface is connected
            opacity: (showDisconnected && connectionKnown && !connected) ? 0.35 : 1

            // Invisible spacer left of the speeds: the centring margin and room for the signal at the left

            Item {
                id: offsetItem
                width: offset + (signalAtLeft ? signalPx : 0)
                height: parent.height
                x: 0
                y: 0
            }

            Text {
                id: topIcon

                height: singleLine ? parent.height : parent.height / 2
                width: (showSeparately ? 1 : 2) * iconTextMetrics.width / iconTextMetrics.height * height * fontSizeScale

                verticalAlignment: Text.AlignVCenter
                anchors.left: offsetItem.right
                anchors.leftMargin: font.pixelSize * marginFactor
                y: 0
                font.pixelSize: height * fontHeightRatio * fontSizeScale
                renderType: Text.NativeRendering

                text: showSeparately ? (swapDownUp ? '↑' : '↓') : '↓↑'
                color: Kirigami.Theme.textColor
                visible: showIcons
            }

            Text {
                id: topText

                height: singleLine ? parent.height : parent.height / 2
                width: speedTextMetrics.width / speedTextMetrics.height * height * fontSizeScale

                horizontalAlignment: Text.AlignRight
                verticalAlignment: Text.AlignVCenter
                anchors.left: showIcons ? topIcon.right : offsetItem.right
                anchors.leftMargin: font.pixelSize * marginFactor
                y: 0
                font.pixelSize: height * fontHeightRatio * fontSizeScale
                renderType: Text.NativeRendering

                text: speedText(showSeparately ? (swapDownUp ? upSpeed : downSpeed) : downSpeed + upSpeed, showLowSpeeds)
                font.features: fixedDigits ? ({ "tnum": 1 }) : ({})
                color: speedColor(showSeparately ? (swapDownUp ? upSpeed : downSpeed) : downSpeed + upSpeed)
            }

            Text {
                id: topUnitText

                height: singleLine ? parent.height : parent.height / 2
                width: unitTextMetrics.width / unitTextMetrics.height * height * fontSizeScale

                verticalAlignment: Text.AlignVCenter
                anchors.left: topText.right
                anchors.leftMargin: font.pixelSize * marginFactor
                y: 0
                font.pixelSize: height * fontHeightRatio * fontSizeScale
                renderType: Text.NativeRendering

                text: speedUnit(showSeparately ? (swapDownUp ? upSpeed : downSpeed) : downSpeed + upSpeed)
                color: Kirigami.Theme.textColor
                visible: showUnits
            }

            Text {
                id: bottomIcon

                height: singleLine ? parent.height : parent.height / 2
                width: iconTextMetrics.width / iconTextMetrics.height * height * fontSizeScale

                verticalAlignment: Text.AlignVCenter
                anchors.left: (singleLine && showUnits) ? topUnitText.right : (singleLine ? topText.right : offsetItem.right)
                anchors.leftMargin: (singleLine ? 2 : 1) * font.pixelSize * marginFactor
                y: singleLine ? 0 : parent.height / 2
                font.pixelSize: height * fontHeightRatio * fontSizeScale
                renderType: Text.NativeRendering

                text: swapDownUp ? '↓' : '↑'
                color: Kirigami.Theme.textColor
                visible: showSeparately && showIcons
            }

            Text {
                id: bottomText

                height: singleLine ? parent.height : parent.height / 2
                width: speedTextMetrics.width / speedTextMetrics.height * height * fontSizeScale

                horizontalAlignment: Text.AlignRight
                verticalAlignment: Text.AlignVCenter
                anchors.left: showIcons ? bottomIcon.right : ((singleLine && showUnits) ? topUnitText.right : (singleLine ? topText.right : offsetItem.right))
                anchors.leftMargin: font.pixelSize * marginFactor
                y: singleLine ? 0 : parent.height / 2
                font.pixelSize: height * fontHeightRatio * fontSizeScale
                renderType: Text.NativeRendering

                text: speedText(swapDownUp ? downSpeed : upSpeed, showLowSpeeds)
                font.features: fixedDigits ? ({ "tnum": 1 }) : ({})
                color: speedColor(swapDownUp ? downSpeed : upSpeed)
                visible: showSeparately
            }

            Text {
                id: bottomUnitText

                height: singleLine ? parent.height : parent.height / 2
                width: unitTextMetrics.width / unitTextMetrics.height * height * fontSizeScale

                verticalAlignment: Text.AlignVCenter
                anchors.left: bottomText.right
                anchors.leftMargin: font.pixelSize * marginFactor
                y: singleLine ? 0 : parent.height / 2
                font.pixelSize: height * fontHeightRatio * fontSizeScale
                renderType: Text.NativeRendering

                text: speedUnit(swapDownUp ? downSpeed : upSpeed)
                color: Kirigami.Theme.textColor
                visible: showSeparately && showUnits
            }

            Text {
                id: signalText

                // Right: after the last text of the (first) line. Left: before the
                // speeds, next to the signal bar. Centred between two rows.
                readonly property Item lastItem: (singleLine && showSeparately)
                    ? (showUnits ? bottomUnitText : bottomText)
                    : (showUnits ? topUnitText : topText)

                height: rowHeight
                y: (parent.height - height) / 2
                x: signalAtLeft
                    ? offset + (showSignal ? signalBarWidth : 0) + font.pixelSize * marginFactor
                    : lastItem.x + lastItem.width + 2 * font.pixelSize * marginFactor
                verticalAlignment: Text.AlignVCenter
                font.pixelSize: height * fontHeightRatio * fontSizeScale
                renderType: Text.NativeRendering

                text: Math.min(100, wifiSignal) + '%'
                color: signalColor
                visible: signalPercentShown && !signalInBar
            }

            // Wider signal bar with the percentage inside
            Rectangle {
                id: signalGauge

                readonly property double pad: signalText.font.pixelSize * marginFactor
                // Height of the whole widget, not just of the text line
                readonly property double fullHeight: content.height * lineScale

                visible: signalInBar
                // Flush with the left edge of the widget; the spare margin goes
                // between the bar and the speeds
                x: Math.max(0, offset)
                width: Math.max(0, signalPx - 2 * pad)
                height: Math.round(fullHeight * (singleLine ? 0.94 : 0.8))
                y: (content.height - height) / 2
                radius: 3
                color: "transparent"
                border.width: 1
                border.color: Qt.alpha(signalColor, 0.7)

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: 1
                    height: Math.round((parent.height - 2) * Math.min(100, Math.max(0, wifiSignal)) / 100)
                    radius: 2
                    color: Qt.alpha(signalColor, 0.35)
                }

                Text {
                    anchors.centerIn: parent
                    // Larger than the speed text where the bar is taller than the text line
                    font.pixelSize: signalText.font.pixelSize * Math.min(1.25, lineScale)
                    renderType: Text.NativeRendering
                    text: Math.min(100, wifiSignal) + '%'
                    color: Kirigami.Theme.textColor
                }
            }
        }

        // Network name and signal on their own line above the speeds
        Item {
            id: linkLine

            readonly property double gap: Math.max(1, Math.round(linkLinePx * 0.12))
            readonly property double textPx: Math.max(1, Math.round((height - (linkLineBar ? 2 : thin.height + 1)) * 0.72 * extraTextScale))
            readonly property bool hasSignal: linkWireless && wifiSignal >= 0
            readonly property double level: hasSignal ? Math.min(100, Math.max(0, wifiSignal)) / 100 : 0

            visible: linkLineShown
            x: 0
            y: 0
            width: parent.width
            height: Math.max(1, linkLinePx - gap)
            opacity: (showDisconnected && connectionKnown && !connected) ? 0.35 : 1

            // 'lineBar': a frame filled from the left up to the signal level
            Rectangle {
                anchors.fill: parent
                visible: linkLineBar
                radius: 3
                color: "transparent"
                border.width: 1
                border.color: linkLine.hasSignal ? Qt.alpha(signalColor, 0.7) : Qt.alpha(Kirigami.Theme.textColor, 0.3)

                Rectangle {
                    x: 1
                    y: 1
                    height: parent.height - 2
                    width: Math.round((parent.width - 2) * linkLine.level)
                    radius: 2
                    color: Qt.alpha(signalColor, 0.35)
                }
            }

            // 'lineText': a thin bar under the text
            Rectangle {
                id: thin
                visible: !linkLineBar && linkLine.hasSignal
                x: 0
                y: parent.height - height
                width: parent.width
                height: Math.max(2, Math.round(linkLinePx * 0.12))
                radius: height / 2
                color: Qt.alpha(Kirigami.Theme.textColor, 0.2)

                Rectangle {
                    width: Math.round(parent.width * linkLine.level)
                    height: parent.height
                    radius: parent.radius
                    color: signalColor
                }
            }

            // Icon, name (cut with "…" when too long; the tooltip has it in full), percentage at the right
            Item {
                id: linkRow
                readonly property double pad: linkLineBar ? Math.round(linkLine.textPx * 0.35) : 0
                readonly property double space: Math.round(linkLine.textPx * 0.3)
                x: pad
                y: 0
                width: parent.width - 2 * pad
                height: linkLineBar ? parent.height : parent.height - thin.height - 1

                Kirigami.Icon {
                    id: linkIcon
                    x: 0
                    y: Math.round((parent.height - height) / 2)
                    width: Math.round(linkLine.textPx * 1.1)
                    height: width
                    source: linkWireless ? 'network-wireless' : 'network-wired'
                }
                Text {
                    // Latency to the router, when it is measured for this interface
                    id: linkLatency
                    readonly property bool shown: pingEnabled && latency >= 0 && latencyInterface === linkInterface
                    visible: shown
                    x: parent.width - width - (linkLine.hasSignal ? linkPercent.width + linkRow.space : 0)
                    height: parent.height
                    verticalAlignment: Text.AlignVCenter
                    font.pixelSize: linkLine.textPx
                    renderType: Text.NativeRendering
                    text: i18n('%1 ms', latency < 10 ? latency.toFixed(1) : latency.toFixed(0))
                    color: linkLineBar ? Kirigami.Theme.textColor
                         : latency < 20 ? Kirigami.Theme.positiveTextColor
                         : latency < 100 ? Kirigami.Theme.neutralTextColor : Kirigami.Theme.negativeTextColor
                }
                Text {
                    id: linkPercent
                    visible: linkLine.hasSignal
                    x: parent.width - width
                    height: parent.height
                    verticalAlignment: Text.AlignVCenter
                    font.pixelSize: linkLine.textPx
                    renderType: Text.NativeRendering
                    text: Math.min(100, wifiSignal) + '%'
                    color: linkLineBar ? Kirigami.Theme.textColor : signalColor
                }
                Text {
                    x: linkIcon.width + linkRow.space
                    width: Math.max(0, parent.width - x - (linkLine.hasSignal ? linkPercent.width + linkRow.space : 0)
                                                 - (linkLatency.shown ? linkLatency.width + linkRow.space : 0))
                    height: parent.height
                    verticalAlignment: Text.AlignVCenter
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    font.pixelSize: linkLine.textPx
                    renderType: Text.NativeRendering
                    text: linkName
                    color: Kirigami.Theme.textColor
                }
            }
        }

        // Data limits below the speeds, one line each: icon, used / limit, percentage
        // and a thin bar. Reached: a warning triangle and "Data limit".
        Repeater {
            // the number of lines; each line follows its entry (no rebuilding every second)
            model: limitLineShown ? limitLineCount : 0

            Item {
                id: limitLine

                required property int index
                readonly property var modelData: panelLimitStates[index] || ({ id: '', iface: '', limit: 1, used: 0, offset: 0, fraction: 0 })

                readonly property double gap: Math.max(1, Math.round(extraLinePx * 0.12))
                readonly property double barPx: Math.max(2, Math.round(extraLinePx * 0.12))
                readonly property double textPx: Math.max(1, Math.round((height - barPx - 1) * 0.72 * extraTextScale))
                readonly property bool reached: modelData.fraction >= 1
                readonly property double space: Math.round(textPx * 0.3)
                readonly property color tint: limitColor(modelData.fraction)
                readonly property string amount: Utils.formatGiB(modelData.used) + (modelData.iface === '' ? ' / ' : '/') + modelData.limit
                                                 + (modelData.iface === '' ? ' ' + i18n('GiB') : '')

                x: 0
                y: inner.height - (limitLineCount - index) * extraLinePx + gap
                width: inner.width
                height: Math.max(1, extraLinePx - gap)
                opacity: (showDisconnected && connectionKnown && !connected) ? 0.35 : 1

                Kirigami.Icon {
                    id: limitIcon
                    x: 0
                    y: Math.round((limitLine.height - limitLine.barPx - 1 - height) / 2)
                    width: Math.round(limitLine.textPx * 1.1)
                    height: width
                    source: limitLine.reached ? 'dialog-warning' : 'office-chart-pie'
                }
                Text {
                    id: limitPercent
                    x: parent.width - width
                    height: limitLine.height - limitLine.barPx - 1
                    verticalAlignment: Text.AlignVCenter
                    font.pixelSize: limitLine.textPx
                    renderType: Text.NativeRendering
                    text: Math.round(limitLine.modelData.fraction * 100) + '%'
                    color: limitLine.tint
                }
                Text {
                    // "14.3 / 50 GiB" for all connections, "wwan0 26.8/50" for one interface
                    x: limitIcon.width + limitLine.space
                    width: Math.max(0, parent.width - x - limitPercent.width - limitLine.space)
                    height: limitLine.height - limitLine.barPx - 1
                    verticalAlignment: Text.AlignVCenter
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    font.pixelSize: limitLine.textPx
                    renderType: Text.NativeRendering
                    text: (limitLine.modelData.iface !== '' ? limitLine.modelData.iface + ' ' : '')
                          + (limitLine.reached ? i18n('Data limit') : limitLine.amount)
                    color: limitLine.reached ? limitLine.tint : Kirigami.Theme.textColor
                }
                Rectangle {
                    x: 0
                    y: parent.height - height
                    width: parent.width
                    height: limitLine.barPx
                    radius: height / 2
                    color: Qt.alpha(Kirigami.Theme.textColor, 0.2)

                    Rectangle {
                        width: Math.round(parent.width * Math.min(1, Math.max(0, limitLine.modelData.fraction)))
                        height: parent.height
                        radius: parent.radius
                        color: limitLine.tint
                    }
                }
            }
        }
    }

    // Short flash when a middle click was received (copy the IP address)
    Rectangle {
        id: copyFlash
        anchors.fill: parent
        radius: 3
        color: Kirigami.Theme.highlightColor
        opacity: 0

        property int seenClicks: copyClicks
        onSeenClicksChanged: {
            if (seenClicks > 0) {
                flashAnimation.restart()
            }
        }

        SequentialAnimation {
            id: flashAnimation
            NumberAnimation { target: copyFlash; property: "opacity"; from: 0; to: 0.6; duration: 80 }
            NumberAnimation { target: copyFlash; property: "opacity"; from: 0.6; to: 0; duration: 450 }
        }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton

        property double lastWheel: 0
        property bool wasExpanded: false

        onPressed: wasExpanded = expanded
        onClicked: mouse => {
            if (mouse.button === Qt.MiddleButton) {
                middleClicked()
            } else {
                activate(wasExpanded)
            }
        }

        // One switch per scroll gesture, not one per wheel step
        onWheel: wheel => {
            if (!scrollSwitchesUnits) {
                wheel.accepted = false
                return
            }
            const now = Date.now()
            if (wheel.angleDelta.y !== 0 && now - lastWheel > 400) {
                toggleUnits()
            }
            lastWheel = now
        }
    }

    // The number of a speed, in the chosen unit and with the chosen decimals
    function speedText(value, showLowSpeeds) {
        return Utils.formatSpeed(value, speedUnits, showLowSpeeds, decimals).number
    }

    // The colour of a speed: the panel's text colour, or the custom colour of its size step
    function speedColor(value) {
        if (!customColors) {
            return Kirigami.Theme.textColor
        }
        return [byteColor, kilobyteColor, megabyteColor, gigabyteColor][Utils.formatSpeed(value, speedUnits, true).tier]
    }

    // The unit text of a speed
    function speedUnit(value) {
        return Utils.unitLabel(Utils.formatSpeed(value, speedUnits, true).tier, speedUnits, shortUnits)
    }
}
