import sys, os, json, itertools, collections
os.environ["QT_QPA_PLATFORM"]="offscreen"; os.environ["QT_QUICK_BACKEND"]="software"
src=open("run.py").read()
head=src[:src.index("def ev(e):")]
sys.argv=["sweep", sys.argv[1], "{}", "{}", "[]"]
exec(compile(head,"run_head","exec"))
from PySide6.QtQuick import QQuickWindow
from PySide6.QtCore import QPointF
win=QQuickWindow(); win.resize(900,400); root.setParentItem(win.contentItem()); win.show()
def settle(n=3):
    for _ in range(n): app.processEvents()
# let the sensors deliver
import time
t0=time.time()
while time.time()-t0 < 4: app.processEvents(); time.sleep(0.02)
loader=root.findChild(QObject,"compactLoader"); item=loader.property("item")
def ex(e): return QQmlExpression(eng.contextForObject(item), item, e).evaluate()[0]
G=1024**3
base=dict(cfg)
def texts():
    out=[]
    def walk(it):
        for ch in it.childItems():
            if not ch.isVisible() or ch.opacity()==0: continue
            t=ch.property("text")
            if isinstance(t,str) and t and ch.width()>0 and ch.metaObject().className().startswith("QQuickText"):
                p=ch.mapToItem(item, QPointF(0,0))
                # the painted part of the text, not its (possibly wider) box
                pw=ch.property("contentWidth") or ch.width(); ha=QQmlExpression(eng.contextForObject(item), ch, "Number(horizontalAlignment)").evaluate()[0]
                x=p.x() + (ch.width()-pw if ha==2 else (ch.width()-pw)/2 if ha==4 else 0)
                out.append((t, x, p.y(), min(pw, ch.width()) , ch.height()))
            walk(ch)
    walk(item); return out
problems=collections.Counter(); examples={}; n=0
positions=[None,"left","bar","right","lineBar","lineText"]
for ff,sizes in ((3,(160,90,300)),(2,(26,44,66))):
    plasmoid.setProperty("formFactor", ff)
    for size in sizes:
        for pos,lay,sep,units,icons,fs,frame,limit,sbar,dec in itertools.product(positions,("auto","rows","columns"),(True,False),("long","short","none"),(True,False),(60,100,150),(False,True),(0,50),(False,True),(0,1)):
            conf=dict(base); conf.update(speedLayout=lay,showSeparately=sep,showUnits=units!="none",shortUnits=units=="short",showIcons=icons,fontSize=fs,showFrame=frame,dataLimits=(json.dumps([{"id":"a","iface":"wlan0","limit":limit,"day":1,"usedTenths":140},{"id":"b","iface":"","limit":500,"day":1,"usedTenths":0}]) if limit else ""),dataLimitsPanel="all",showSignal=sbar,decimals=dec,showSignalPercent=pos is not None,signalPercentPosition=pos or "left",pingEnabled=False,
                usageState=json.dumps({"day":"2026-11-27","month":"2026-11","monthDown":14*G,"monthUp":0}))
            plasmoid.setProperty("configuration", conf); settle(2)
            if ff==3:
                root.setWidth(size); settle(2); h=ex("wantedHeight"); root.setHeight(max(1,h)); 
            else:
                root.setHeight(size); settle(2); w=ex("wantedWidth"); root.setWidth(max(1,w))
            settle(3); n+=1
            W,H=root.width(),root.height(); ts=texts()
            def note(kind, detail):
                key=(kind, "vertical" if ff==3 else "horizontal", size, pos, lay, "sep" if sep else "sum")
                problems[key]+=1
                examples.setdefault(key, (detail, dict(units=units,icons=icons,fs=fs,frame=frame,limit=limit,sbar=sbar,dec=dec), (round(W),round(H))))
            for (t,x,y,w,h) in ts:
                if x < -1.5 or x+w > W+1.5 or y < -1.5 or y+h > H+1.5:
                    note("outside", "%r x %.0f-%.0f y %.0f-%.0f" % (t,x,x+w,y,y+h))
            for (a,b) in itertools.combinations(ts,2):
                ox=min(a[1]+a[3], b[1]+b[3]) - max(a[1], b[1]); oy=min(a[2]+a[4], b[2]+b[4]) - max(a[2], b[2])
                if ox > 1.5 and oy > 1.5:
                    note("overlap", "%r / %r by %.0fx%.0f" % (a[0], b[0], ox, oy))
            if not ts: note("empty", "no text at all")
print("combinations checked:", n)
print("problem groups:", len(problems))
agg=collections.Counter()
for k,v in problems.items(): agg[(k[0],k[1],k[3],k[4],k[5])]+=v
for k,v in sorted(agg.items(), key=lambda kv:-kv[1])[:40]:
    ex1=[examples[kk] for kk in examples if (kk[0],kk[1],kk[3],kk[4],kk[5])==k][0]
    print(v, k, "| e.g.", ex1[0], ex1[1], "widget", ex1[2])
