import sys, os
os.environ["QT_QUICK_BACKEND"]="software"
src=open("run.py").read()
src=src.replace("from PySide6.QtQuick import QQuickItem","from PySide6.QtQuick import QQuickItem, QQuickWindow\nfrom PySide6.QtTest import QTest\nfrom PySide6.QtCore import Qt, QPoint")
src=src.replace("def ev(e):","win=QQuickWindow(); win.resize(700,700); root.setParentItem(win.contentItem()); win.show()\ndef ev(e):",1)
src=src.replace('QTimer.singleShot(t+300, app.quit)','''def clicks():
    for name,btn in (("middle",Qt.MiddleButton),("left",Qt.LeftButton)):
        QTest.mouseClick(win, btn, Qt.NoModifier, QPoint(60, 15)); app.processEvents()
        print("  after %s click: copyClicks=%s expanded=%s" % (name, ev("copyClicks"), ev("expanded")))
QTimer.singleShot(t+100, clicks)
QTimer.singleShot(t+600, app.quit)''')
exec(compile(src,"run.py","exec"))
