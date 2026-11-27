import QtQuick
Item {
    id: ds
    property string engine
    property var connectedSources: []
    property int interval: 0
    property int tick: 0
    signal newData(string sourceName, var data)
    function netOutput() {
        ds.tick++;
        const wifiState = (testDropAfter > 0 && testClock.seconds >= testDropAfter) ? "down" : "up";
        return "lo,5,5,0,0,unknown\neth0,0,0,1,0,down\nwlan0," + (1000000 + ds.tick * 62500) + "," + (5000 + ds.tick * 500) + ",1,1," + wifiState + "\nwg0," + (900000 + ds.tick * 62500) + ",100,0,0,unknown\n";
    }
    function connectSource(s) {
        let out = "";
        if (s.indexOf("awk ") === 0) { out = netOutput(); console.log("RUN: discovery"); }
        else if (s.indexOf("LC_ALL=C timeout 5 ping") === 0) { out = "64 bytes from 192.168.1.1: icmp_seq=1 ttl=64 time=1.23 ms\n"; console.log("RUN: " + s); }
        else { console.log("RUN: " + s); }
        Qt.callLater(() => ds.newData(s, { "exit code": 0, stdout: out, stderr: "" }));
    }
    function disconnectSource(s) {}
    Timer {
        interval: 500; repeat: true; running: ds.connectedSources.length > 0 && ds.interval > 0
        onTriggered: ds.newData(ds.connectedSources[0], { "exit code": 0, stdout: ds.netOutput(), stderr: "" })
    }
}
