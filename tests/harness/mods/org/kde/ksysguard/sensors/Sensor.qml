import QtQuick
QtObject {
    id: s
    property string sensorId
    property int updateRateLimit
    property bool enabled: true
    property var value
    property int ticks: 0
    property Timer timer: Timer {
        interval: 500; repeat: true; running: s.enabled && !testBrokenSensors
        onTriggered: {
            s.ticks++;
            const rate = testIdle ? 0 : 12500000;
            const v = {
                "network/all/download": rate, "network/all/upload": testIdle ? 0 : 125,
                "network/all/totalDownload": 92741995 + s.ticks * rate / 2, "network/all/totalUpload": 6766305 + s.ticks * 62,
                "network/wlan0/network": "HomeWiFi", "network/wlan0/signal": 72, "network/wlan0/ipv4address": (typeof testNoIpv4 !== "undefined" && testNoIpv4) ? "" : "192.168.1.50",
                "network/wlan0/ipv6address": (typeof testIpv6 !== "undefined" && testIpv6) ? "2001:db8::50" : "", "network/wlan0/ipv6gateway": (typeof testIpv6 !== "undefined" && testIpv6) ? "fe80::1" : "", "network/wlan0/ipv6dns": (typeof testIpv6 !== "undefined" && testIpv6) ? "2001:db8::53" : "",
                "network/wlan0/ipv4gateway": "192.168.1.1", "network/wlan0/ipv4dns": "192.168.1.1"
            }[s.sensorId];
            s.value = v;
        }
    }
}
