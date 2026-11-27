import os, sys
import sys, os, json
os.environ["QT_QPA_PLATFORM"]="offscreen"
from PySide6.QtCore import QUrl, QTimer, QObject
from PySide6.QtGui import QGuiApplication
from PySide6.QtQuick import QQuickItem
from PySide6.QtQml import QQmlEngine, QQmlComponent, QQmlExpression
pkg, cfg_over, opts, script = sys.argv[1], json.loads(sys.argv[2]), json.loads(sys.argv[3]), json.loads(sys.argv[4])
app=QGuiApplication(sys.argv)
eng=QQmlEngine(); eng.addImportPath(os.path.join(os.path.dirname(os.path.abspath(sys.argv[0])), "mods"))
eng.globalObject().setProperty("i18n", eng.evaluate("(function(s){ for (let i=1;i<arguments.length;i++) s=s.replace('%'+i, arguments[i]); return s; })"))
cfg={"showSeparately":True,"showLowSpeeds":False,"speedLayout":"auto","swapDownUp":False,"showIcons":True,"showUnits":True,"speedUnits":"bytes","shortUnits":False,"fontSize":100,"updateInterval":1.0,"customColors":False,"byteColor":"#000000","kilobyteColor":"#800080","megabyteColor":"#FF0000","gigabyteColor":"#FF8000","launchApplicationEnabled":False,"launchApplication":"","interfacesWhitelistEnabled":False,"interfacesWhitelist":[],
"decimals":1,"fixedDigits":False,"panelGraph":False,"showSignal":False,"showSignalPercent":False,"signalPercentPosition":"left","showDisconnected":True,"notifyConnection":False,"hideWhenIdle":False,"idleThreshold":1,"scrollSwitchesUnits":True,"middleClickCopiesIp":True,"pingEnabled":False,"pingHost":"","pingInterval":15,"externalIpEnabled":False,"externalIpUrl":"https://api.ipify.org","usageState":"","dataLimits":"","dataLimitsPanel":"auto","periodStartDay":1,"perInterfaceUsage":False,"signalWarnLevel":0,"showFrame":False,"resetRequest":"","dataLimit":0,"detailsZoom":100}
cfg.update(cfg_over)
pc=QQmlComponent(eng); pc.setData(("import QtQuick\nQtObject { property var configuration: (%s); property int formFactor: 2; property var metaData: ({version: '4.0'}) }" % json.dumps(cfg)).encode(), QUrl())
plasmoid=pc.create(); ctx=eng.rootContext(); ctx.setContextProperty("plasmoid", plasmoid)
ctx.setContextProperty("testBrokenSensors", opts.get("broken", False)); ctx.setContextProperty("testIdle", opts.get("idle", False)); ctx.setContextProperty("testDropAfter", opts.get("dropAfter", 0)); ctx.setContextProperty("testIpv6", opts.get("ipv6", False)); ctx.setContextProperty("testNoIpv4", opts.get("noIpv4", False))
cc=QQmlComponent(eng); cc.setData(b"import QtQuick\nQtObject { property int seconds: 0; property Timer t: Timer { interval: 1000; running: true; repeat: true; onTriggered: parent.seconds++ } }", QUrl())
clock=cc.create(); ctx.setContextProperty("testClock", clock)
c=QQmlComponent(eng, QUrl.fromLocalFile(pkg+"/contents/ui/main.qml"))
root=c.create()
if root is None: print("LOAD FAILED:", c.errorString()); sys.exit(1)
def ev(e):
    v,undef=QQmlExpression(eng.contextForObject(root), root, e).evaluate()
    return v
def walk(item, out):
    for ch in item.childItems():
        if not ch.isVisible(): continue
        t=ch.property("text")
        if t: out.append(t)
        walk(ch, out)
def texts(loader):
    l=root.findChild(QObject, loader); out=[]
    if l: walk(l, out)
    return out
def report(tag=""):
    print("[%s] sensors=%s proc=%s conn=%s idle=%s down=%.0f up=%.0f | panel: %s" % (tag, ev("useSensors"), ev("procActive"), ev("connected"), ev("idle"), ev("downSpeed"), ev("upSpeed"), " ".join(texts("compactLoader"))))
t=0
for step in script:
    t+=int(step[0]*1000)
    def do(step=step):
        for e in step[1:]:
            if e=="report": report(str(step[0]))
            elif e=="popup": print("  popup:", " | ".join(texts("fullLoader")))
            elif e.startswith("print "): print("  "+e[6:]+" =", ev(e[6:]))
            else: ev(e)
    QTimer.singleShot(t, do)
QTimer.singleShot(t+300, app.quit)
app.exec()
