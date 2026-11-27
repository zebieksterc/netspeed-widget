import os, sys
import sys
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlEngine, QQmlComponent, QQmlContext
from PySide6.QtCore import QUrl
app=QGuiApplication(["x","-platform","offscreen"]); eng=QQmlEngine(); eng.addImportPath(os.path.join(os.path.dirname(os.path.abspath(sys.argv[0])), "mods"))
eng.evaluate("1"); 
class F: pass
for f in sys.argv[1:]:
    eng.globalObject().setProperty("i18n", eng.evaluate("(function(s){var a=arguments;return String(s).replace(/%(\\d)/g,function(m,n){return a[n]})})"))
    c=QQmlComponent(eng, QUrl.fromLocalFile(f)); o=c.create()
    print(f.split("/")[-1], "OK" if o else c.errorString())
    if o: print("   cfg_ properties:", sum(1 for i in range(o.metaObject().propertyCount()) if o.metaObject().property(i).name().startswith("cfg_")))
