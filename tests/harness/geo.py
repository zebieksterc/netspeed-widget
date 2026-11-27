import sys, os, json, re
src=open("run.py").read()
src=src.replace('QTimer.singleShot(t+300, app.quit)','''def geo():
    l=root.findChild(QObject,"compactLoader"); item=l.property("item")
    need=QQmlExpression(eng.contextForObject(item), item, "Math.ceil(height * aspectRatio)").evaluate()[0]
    out=[]
    def walk2(it, ox):
        for ch in it.childItems():
            if not ch.isVisible(): continue
            t=ch.property("text")
            if t: out.append("%s[%.0f-%.0f]" % (t, ox+ch.x(), ox+ch.x()+ch.width()))
            walk2(ch, ox+ch.x())
    walk2(item, 0)
    def rects(it, ox):
        for ch in it.childItems():
            if ch.isVisible() and ch.metaObject().className().startswith("QQuickRectangle") and ch.width() > 10 and ch.height() > 10 and ch.height() < it.height()+1 and ch.property("radius") == 3:
                out.append("gauge[%.0f-%.0f]" % (ox+ch.x(), ox+ch.x()+ch.width()))
            rects(ch, ox+ch.x())
    rects(item, 0)
    print("  needed width=%s | %s" % (need, " ".join(out)))
QTimer.singleShot(t+100, geo)
QTimer.singleShot(t+300, app.quit)''')
exec(compile(src,"run.py","exec"))
