# Development notes

## Structure

- `package/contents/ui/main.qml` - the widget: settings, sensors, sampling, counters, limits, notifications, tooltip.
  Properties and functions of its root are used without a prefix from the other QML files (on purpose).
- `CompactRepresentation.qml` - the panel item. `FullRepresentation.qml` - the details popup.
  `SpeedGraph.qml` - the graph. `ContextMenu.qml` - the right-click entry (loaded through a Loader).
- `ui/config/` - one file per settings tab; `SettingHint.qml` is the warning triangle; `AppPicker.qml`,
  `AppMenuDialog.qml` (choose an application) and `ColorPicker.qml` are from the original widget.
- `contents/config/main.xml` declares every setting (key, type, default); `contents/config/config.qml` lists the
  tabs of the settings dialog and which file shows each.
- `package/contents/code/utils.js` - every calculation and every shell command string. No QML in it, so it is
  tested with node.
- In `main.qml` the optional parts (sensors, the command runner) are created with `Qt.createQmlObject` inside
  try/catch, so a missing module cannot stop the widget. The settings pages Data limits and Advanced import
  `plasma5support` directly and need it.
- Commands run through Plasma's "executable" data engine. Every value that goes into a command passes
  `shellQuote` or `cleanHost`; `cleanIp` checks the answer of the external-IP service.
- Settings pages cannot call the widget. They ask for a reset through the config value `resetRequest`.
- Counters live in the config value `usageState` (JSON): day, month, history, per-interface counters, limits.
  The list of limits is the config value `dataLimits` (JSON).

## Rules learned

1. **A Repeater never gets a model that is recomputed from changing data, and never one that depends on
   `Kirigami.Theme` values.** Use a number as model and let the delegate read `list[index]`.
   A development version broke this rule: its tiles were a list containing theme colours. When Plasma applied the theme to the
   freshly loaded popup, the colours changed, the list was rebuilt and the tiles were destroyed while the theme
   was still notifying them. plasmashell crashed at every start (SIGSEGV in the Breeze style's event filter,
   called from Kirigami's theme notification during `QQuickItem::windowChanged`).
   `tests/harness/churn.py` counts destroyed and recreated items; it must report 0.
   Allowed as models: a number, a constant list (the reset choices), and `interfaceList` in the details, which
   is only replaced when the interface names really change (see `interfaceKey`).
2. **The harness cannot find crashes inside the real Kirigami or Breeze code** - it uses stand-ins.
   Before restarting Plasma with a version that changes the QML structure: `./check.sh --try`.
3. Labels that show a network name, an interface name, an address or an answer from the internet set
   `textFormat: Text.PlainText`. Names in the rich-text tooltip go through `Utils.escapeHtml`.
4. QML's `XMLHttpRequest` has no timeout. The internet check has its own watchdog and numbers each check.
5. In the details popup every size comes from the zoomed values (`zSmall`, `zLarge`, `zGrid`, `zIcon`,
   `zRadius`, `zFontSize`, `zSmallFont`); labels without a font inherit it from the `QQC2.Control`
   around the content. Inside inline components use these plain names, not `popup.…`.
6. `KPackageStructure` must be a top-level string in `metadata.json`, or Plasma does not list the widget.
7. Notifications carry `-h string:desktop-entry:<id>` and the matching `.desktop` entry is installed, or Plasma
   does not keep them in its history. The entry is in `package/contents/data/`; `install.sh` copies it, and the
   widget does so itself when it starts (`Utils.desktopEntryCommand`), for installs from a `.plasmoid` file.
8. In a vertical panel the speed text may not be wider than the panel: the font scale is limited to 1 there and
   the requested height is rounded down. In a horizontal panel it is limited to the row height.

## Testing

    node tests/helpers.test.js package/contents/code/utils.js     # the calculations
    shellcheck install.sh uninstall.sh check.sh

The harness needs Python with PySide6 (`pip install pyside6-essentials`). Run it from `tests/harness/`:

    cd tests/harness
    python3 run.py ../../package '{}' '{}' '[[3,"report"]]'
    python3 pop.py ../../package '{}' '{}' '[[3,"expanded = true"],[4,"popup"]]'
    python3 churn.py ../../package '{}' '{}' '[[3,"expanded = true"],[4,"report"]]'     # must report 0 / 0
    python3 click.py ../../package '{}' '{}' '[[3,"report"]]'
    python3 sweep.py ../../package          # 62,208 combinations of settings and panel sizes; takes a few minutes

Arguments: the package folder, settings as JSON (keys of `contents/config/main.xml`), options as JSON
(`broken` = no sensors, `idle`, `dropAfter`, `ipv6`, `noIpv4`), and a script: a list of `[seconds, step, …]` where a
step is `report`, `popup`, `print <expression>` or any expression to evaluate on the widget.
`popshot.py` also writes a picture of the popup to `/tmp/netspeed-details.png`.
`mods/` holds the stand-ins for the Plasma, Kirigami and sensor modules.

Known result of `sweep.py`: it ends with "problem groups: 12" and four lines of 96 combinations. All of them are one case: in a horizontal panel with the wide signal bar and a large font -
the line box of the percentage is 3 px taller than a 26 px panel; the digits themselves fit.

What the scripts print when all is well: `run.py` - a line `[3] sensors=True … | panel: ↓ … ↑ …`;
`pop.py` - `popup:` followed by every text of the details; `click.py` - `after middle click: copyClicks=1
expanded=False` and `after left click: copyClicks=1 expanded=True`; `churn.py` - `0 destroyed and 0 created` twice.

Limits of the harness:
- Every run prints `ContextMenu.qml: PlasmaCore.Action is not a type`. That is expected: the stand-ins have no
  menu, so the right-click entry "Show details" is not tested here.
- `geo.py`, `geov.py`, `geov2.py` print the positions of the texts of the panel item (horizontal panel, vertical
  panel, and the same with the extra lines); `popshot.py` is `pop.py` plus a picture.
- `cfgload.py <file>` loads one settings page. It only works for `ConfigGeneral.qml`; the other pages use parts the
  stand-ins lack (`Kirigami.FormData`, `org.kde.plasma.extras`).
- `run.py` holds a copy of all settings with their defaults and a fixed version number for the version
  label. A new setting must be added there too.

## Where the settings and counters are stored

`~/.config/plasma-org.kde.plasma.desktop-appletsrc`, section
`[Containments][<n>][Applets][<m>][Configuration][General | Advanced | Extras]` of the applet with
`plugin=io.github.zebieksterc.netspeedwidget`. Only values that differ from the default are written.

- `usageState` (JSON): `day`, `dayDown`, `dayUp`, `month` (name of the running period), `startDay`, `monthDown`,
  `monthUp`, `history` (list of `{ month, down, up, day }`, 12 at most), `ifaces` (name -> `dayDown`, `dayUp`,
  `monthDown`, `monthUp`, `rx`, `tx` = last byte counters seen), `limits` (id -> `period`, `used`, `notified`,
  `offset`, `applied`), `totals` (`{ key, down, up }`: where the byte counters of all connections stood at the
  last save; `Utils.catchUpTotals` adds the difference once after the start).
- `dataLimits` (JSON): list of `{ id, iface ('' = all connections), limit (GiB), day (1-28), usedTenths }`.

## Adding a setting

1. Declare it in `contents/config/main.xml` (group `Extras`).
2. Read it in `main.qml`: `property <type> <name>: plasmoid.configuration.<key>`.
3. On the right page in `ui/config/`: `property alias cfg_<key>: <control>.<value>` and the control, with a
   `ToolTip.text` that says what it does. If it can be without effect, add a `SettingHint`.
4. Add it to the settings table in `README.md`, to the defaults in `tests/harness/run.py`, and to `ChangeLog`.

## Debugging

    journalctl --user -b -f | grep -e "Netspeed Widget:" -e io.github.zebieksterc.netspeedwidget
    plasmawindowed io.github.zebieksterc.netspeedwidget      # the widget in its own window, messages in the terminal

Every warning the widget writes itself starts with "Netspeed Widget:". After changing files of an installed
widget Plasma must be restarted; it keeps the loaded version in memory.

## Releasing

1. Change the code, raise `Version` in `package/metadata.json`, add an entry at the top of `ChangeLog`.
2. Run the tests above (helpers, churn, click; sweep after layout changes).
3. `./install.sh`, `./check.sh --try`, restart Plasma, `./check.sh`.
4. `git commit`, `git tag -a vX.Y`, `git push --follow-tags`.

GitHub Actions (`.github/workflows/build.yml`) runs the helper tests and shellcheck on every push and pull
request and builds `netspeed-widget-<version>.plasmoid` (the `package/` folder as a zip), attached to the run.
A pushed version tag also publishes a release with that file and the ChangeLog entry; the tag must equal
`v<Version>`. By hand: *Actions > Build > Run workflow* (tick "release" to publish). The runner has no Plasma,
so it cannot replace step 3.
