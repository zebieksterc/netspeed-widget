import QtQuick
import QtQuick.Layouts
Item {
    width: 300; height: 30
    property Component compactRepresentation
    property Component fullRepresentation
    property Component preferredRepresentation
    property bool expanded: false
    property string toolTipMainText
    property string toolTipSubText
    property int toolTipTextFormat
    Loader { objectName: "compactLoader"; anchors.fill: parent; sourceComponent: parent.compactRepresentation }
    Loader { objectName: "fullLoader"; y: 40; width: 500; height: 600; active: parent.expanded; sourceComponent: parent.fullRepresentation }
}
