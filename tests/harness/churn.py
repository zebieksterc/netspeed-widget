# Counts how many items of the panel item and of the details are destroyed and
# created again within a few seconds of normal running. It should be none:
# rebuilding items all the time is wasteful and once crashed Plasma during development.
import sys, os
src=open("run.py").read()
src=src.replace("from PySide6.QtQuick import QQuickItem","from PySide6.QtQuick import QQuickItem, QQuickWindow\nimport shiboken6")
src=src.replace("def ev(e):","win=QQuickWindow(); win.resize(700,900); root.setParentItem(win.contentItem()); win.show()\ndef ev(e):",1)
src=src.replace('QTimer.singleShot(t+300, app.quit)','''snap={}
def items(loader):
    l=root.findChild(QObject, loader); out=set()
    def walk(it):
        for ch in it.childItems():
            out.add(shiboken6.getCppPointer(ch)[0]); walk(ch)
    if l: walk(l)
    return out
def first():
    snap["c"]=items("compactLoader"); snap["f"]=items("fullLoader")
def second():
    for key,name in (("c","panel item"),("f","details")):
        now=items(key=="c" and "compactLoader" or "fullLoader")
        gone=len(snap[key]-now); new=len(now-snap[key])
        print("  %s: %d items, %d destroyed and %d created in 4 seconds" % (name, len(now), gone, new))
QTimer.singleShot(t+100, first)
QTimer.singleShot(t+4100, second)
QTimer.singleShot(t+4400, app.quit)''')
exec(compile(src,"run.py","exec"))
