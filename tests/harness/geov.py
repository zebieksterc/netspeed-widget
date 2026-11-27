import sys, os
src=open("run.py").read()
src=src.replace("property int formFactor: 2","property int formFactor: 3")
src=src.replace('QTimer.singleShot(t+300, app.quit)','''def geo():
    l=root.findChild(QObject,"compactLoader"); item=l.property("item")
    root.setWidth(160)
    def ex(e): return QQmlExpression(eng.contextForObject(item), item, e).evaluate()[0]
    h=ex("Math.ceil(width / layoutAspectRatio * fontSizeScale * fontSizeScale)")
    root.setHeight(h); app.processEvents()
    out=[]
    def walk2(it, ox, oy):
        for ch in it.childItems():
            if not ch.isVisible(): continue
            t=ch.property("text")
            if t: out.append("%s[x %.0f-%.0f, y %.0f-%.0f]" % (t, ox+ch.x(), ox+ch.x()+ch.width(), oy+ch.y(), oy+ch.y()+ch.height()))
            if ch.metaObject().className().startswith("QQuickRectangle") and ch.property("radius") == 3:
                out.append("BAR[x %.0f-%.0f, y %.0f-%.0f]" % (ox+ch.x(), ox+ch.x()+ch.width(), oy+ch.y(), oy+ch.y()+ch.height()))
            walk2(ch, ox+ch.x(), oy+ch.y())
    walk2(item, 0, 0)
    print("  widget 160 x %s | lineScale=%s | %s" % (h, ex("lineScale"), " ".join(out)))
QTimer.singleShot(t+100, geo)
QTimer.singleShot(t+400, app.quit)''')
exec(compile(src,"run.py","exec"))
