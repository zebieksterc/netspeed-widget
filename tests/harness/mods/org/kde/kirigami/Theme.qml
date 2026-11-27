pragma Singleton
import QtQuick
QtObject {
    readonly property color textColor: "#ffffff"; readonly property color highlightColor: "#3daee9"
    readonly property color neutralTextColor: "#f67400"; readonly property color positiveTextColor: "#27ae60"
    readonly property color negativeTextColor: "#da4453"
    readonly property font smallFont: Qt.font({pixelSize: 11}); readonly property font defaultFont: Qt.font({pointSize: 10})
}
