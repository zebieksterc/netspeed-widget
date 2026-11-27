import sys, os
os.environ["QT_QUICK_BACKEND"]="software"
src=open("run.py").read()
src=src.replace("from PySide6.QtQuick import QQuickItem","from PySide6.QtQuick import QQuickItem, QQuickWindow")
src=src.replace("def ev(e):","win=QQuickWindow(); win.resize(520,640); root.setParentItem(win.contentItem()); win.show()\ndef ev(e):",1)
src=src.replace('QTimer.singleShot(t+300, app.quit)','''def geo():
    l=root.findChild(QObject,"fullLoader"); item=l.property("item"); out=[]
    def walk2(it, oy, depth):
        for ch in it.childItems():
            if not ch.isVisible(): continue
            cn=ch.metaObject().className()
            if cn.startswith("QQuickRectangle"):
                out.append("%sbox y %.0f-%.0f h=%.0f w=%.0f" % ("  "*depth, oy+ch.y(), oy+ch.y()+ch.height(), ch.height(), ch.width()))
            walk2(ch, oy+ch.y(), depth+1)
    walk2(item, 0, 0)
    def texts2(it, oy):
        for ch in it.childItems():
            if not ch.isVisible(): continue
            t=ch.property('text')
            if t and ('wlan0' in t or 'eth0' in t or 'Signal' in t or t=='down' or 'HomeWiFi' in t or 'IP ' in t): out.append('   x %.0f w %.0f  %s' % (ch.mapToItem(item, 0, 0).x(), ch.width(), t[:30]))
            texts2(ch, oy+ch.y())
    texts2(item, 0)
    col=[c for c in item.childItems()][0]
    print("popup column implicit height:", col.implicitHeight()); print("\\n".join(out))
QTimer.singleShot(t+100, geo)
QTimer.singleShot(t+200, lambda: win.grabWindow().save('/tmp/netspeed-details.png'))
QTimer.singleShot(t+400, app.quit)''')
exec(compile(src,"run.py","exec"))
