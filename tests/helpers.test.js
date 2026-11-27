// Tests for package/contents/code/utils.js. Read-only apart from a fixture
// folder in the system temp directory, which is removed at the end.
//
//   node tests/helpers.test.js package/contents/code/utils.js
//
// Exit code 0 = all passed.
const fs = require('fs'), os = require('os'), path = require('path');
const vm = require('vm'), cp = require('child_process');

const ctx = {}; vm.createContext(ctx);
const names = "NET_DATA_SOURCE,parseTransferData,calcSpeedData,interfaceShown,formatSpeed,unitLabel,formatTotal," +
    "launchCommand,shellQuote,isConnected,wirelessInterface,pushSample,dayKey,monthKey,loadUsage,addUsage," +
    "usageDelta,routerAddress,parseLimits,rollLimits,addLimitUsage,resetLimit,limitStatus,panelLimits,addInterfaceUsage,resetUsage,periodKey,periodStart,cleanStartDay,cleanTotals,catchUpTotals,localPath,desktopEntryCommand,DESKTOP_ENTRY,limitStage,limitHue,formatGiB,rollUsage,linkInterface,cleanHost,internetHost,escapeHtml,copyTextCommand,pingCommand,parsePing,copyIpCommand,notifyCommand,cleanIp";
vm.runInContext(fs.readFileSync(process.argv[2], 'utf8') + "\nthis.U={" + names + "};", ctx);
const U = ctx.U;

let fail = 0, count = 0;
const eq = (a, b, m) => {
    count++;
    if (JSON.stringify(a) !== JSON.stringify(b)) {
        fail++;
        console.log("FAIL", m, JSON.stringify(a), "!=", JSON.stringify(b));
    }
};
const have = tool => cp.spawnSync('sh', ['-c', 'command -v ' + tool], { stdio: 'ignore' }).status === 0;
const sh = cmd => cp.spawnSync('sh', ['-c', cmd], { encoding: 'utf8' });

// ---------------------------------------------------------------- formatSpeed
eq(U.formatSpeed(12500000, 'bits', false), { number: "100.0", tier: 2 }, "100 Mb/s");
eq(U.formatSpeed(12500000, 'bits', false, 0), { number: "100", tier: 2 }, "0 decimals");
eq(U.formatSpeed(12500000, 'bytes', false, 1), { number: "11.9", tier: 2 }, "MiB");
eq(U.formatSpeed(999, 'bytes', false), { number: "0.0", tier: 0 }, "low hidden");
eq(U.formatSpeed(999, 'bytes', true), { number: "999.0", tier: 0 }, "low shown");
// bits are bytes * 8 and nothing else (the original multiplied by 8 * 1.024)
eq(U.formatSpeed(125, 'bits', true), { number: "1.0", tier: 1 }, "125 B/s = 1.0 kb/s");
eq(U.formatSpeed(125000, 'bits', true), { number: "1.0", tier: 2 }, "125 kB/s = 1.0 Mb/s");
eq(U.formatSpeed(125000000, 'bits', true), { number: "1.0", tier: 3 }, "125 MB/s = 1.0 Gb/s");
// the next unit starts at 1000, bytes are divided by 1024
eq(U.formatSpeed(1000, 'bytes', true), { number: "1.0", tier: 1 }, "1000 B/s -> KiB");
eq(U.formatSpeed(1024 * 999, 'bytes', true), { number: "999.0", tier: 1 }, "999 KiB/s");
eq(U.formatSpeed(1024 * 1000, 'bytes', true), { number: "1.0", tier: 2 }, "1000 KiB/s -> MiB");
eq(U.formatSpeed(1024 * 1024 * 1000, 'bytes', true), { number: "1.0", tier: 3 }, "1000 MiB/s -> GiB");
// values that round up to 1000 must not be shown as "1000" / "1000.0"
eq(U.formatSpeed(999.6, 'bytes', true, 0), { number: "1", tier: 1 }, "999.6 B/s, 0 decimals");
eq(U.formatSpeed(999.96, 'bytes', true, 1), { number: "1.0", tier: 1 }, "999.96 B/s, 1 decimal");
eq(U.formatSpeed(999.96 * 1024, 'bytes', true, 1), { number: "1.0", tier: 2 }, "999.96 KiB/s");
eq(U.formatSpeed(999.6 * 1000 / 8, 'bits', true, 0), { number: "1", tier: 2 }, "999.6 kb/s, 0 decimals");
eq(U.formatSpeed(999.4, 'bytes', true, 0), { number: "999", tier: 0 }, "999.4 stays");
// the tier is the same for every decimals / showLowSpeeds combination (number and unit are separate calls)
for (const v of [0, 1, 999.4, 999.5, 999.6, 999.96, 1000, 1023, 1024, 1023487, 1023488, 1024000, 1048576, 1e9, 2e12]) {
    for (const units of ['bits', 'bytes']) {
        const tiers = [U.formatSpeed(v, units, true, 0), U.formatSpeed(v, units, true, 1),
                       U.formatSpeed(v, units, false, 0), U.formatSpeed(v, units, true)].map(r => r.tier);
        eq(tiers, [tiers[0], tiers[0], tiers[0], tiers[0]], "same tier " + v + " " + units);
        for (const dec of [0, 1]) {
            const n = U.formatSpeed(v, units, true, dec);
            if (n.tier < 3) {
                eq(n.number.length <= (dec ? 5 : 3), true, "width " + v + " " + units + " " + dec + ": " + n.number);
            }
        }
    }
}
eq(U.formatSpeed(-5, 'bytes', true).number, "0.0", "negative speed");
eq(U.formatSpeed(NaN, 'bits', true).number, "0.0", "NaN speed");
eq(U.formatSpeed(undefined, 'bytes', true, 0), { number: "0", tier: 0 }, "undefined speed");
eq(U.formatSpeed(Infinity, 'bytes', true).number, "0.0", "infinite speed");
eq(U.unitLabel(2, 'bits', false), "Mb/s", "unit bits");
eq(U.unitLabel(1, 'bytes', false), "KiB/s", "unit bytes");
eq(U.unitLabel(3, 'bytes', true), "G", "unit short");
eq(U.unitLabel(9, 'bytes', false), "GiB/s", "unit tier too high");
eq(U.unitLabel(undefined, 'bits', false), "b/s", "unit tier missing");

// ---------------------------------------------------------------- formatTotal
eq(U.formatTotal(0), "0 B", "total 0");
eq(U.formatTotal(512), "512 B", "total bytes");
eq(U.formatTotal(1024), "1.0 KiB", "total KiB");
eq(U.formatTotal(1536 * 1024), "1.5 MiB", "total MiB");
eq(U.formatTotal(1023.96 * 1024 * 1024), "1.0 GiB", "total 1023.96 MiB is not '1024.0 MiB'");
eq(U.formatTotal(1023.9 * 1024), "1023.9 KiB", "total 1023.9 KiB");
eq(U.formatTotal(5000 * 1024 * 1024 * 1024), "4.9 TiB", "total TiB");
eq(U.formatTotal(-1), "0 B", "total negative");
eq(U.formatTotal(NaN), "0 B", "total NaN");
eq(U.formatTotal(undefined), "0 B", "total undefined");

// ---------------------------------------------------------- parseTransferData
const t = U.parseTransferData("lo,5,5,0,0,unknown\neth0,1000,500,1,0,down\nwlan0,1000,500,1,1,up\nwg0,10,5,0,0,unknown\n");
eq(Object.keys(t), ["eth0", "wlan0", "wg0"], "names");
eq(t.wlan0, { rx: 1000, tx: 500, physical: true, wireless: true, operstate: "up" }, "entry");
eq(U.parseTransferData(""), {}, "empty output");
eq(U.parseTransferData(undefined), {}, "no output");
eq(U.parseTransferData("eth0,12,34\ngarbage\n,1,2,1,0,up\neth1,x,5,1,0,up\neth2,,5,1,0,up\neth3,7,8,1,0,up\r\n"),
   { eth3: { rx: 7, tx: 8, physical: true, wireless: false, operstate: "up" } }, "broken lines are skipped");
eq(Object.keys(U.parseTransferData("a,b,1,2,0,0,up\n")), ["a,b"], "comma in the name");

// -------------------------------------------------------------- calcSpeedData
const prev = U.parseTransferData("eth0,1000,1000,1,0,up\nwg0,5000,5000,0,0,unknown\n");
const next = U.parseTransferData("eth0,3000,1500,1,0,up\nwg0,100,200,0,0,unknown\nusb0,9999,9999,1,0,unknown\n");
const sp = U.calcSpeedData(prev, next, 2000);
eq([sp.eth0.down, sp.eth0.up, sp.eth0.downTotal, sp.eth0.upTotal], [1000, 250, 3000, 1500], "speed");
eq([sp.wg0.down, sp.wg0.up], [0, 0], "counter went backwards -> 0, not negative");
eq([sp.usb0.down, sp.usb0.up], [0, 0], "new interface -> 0, not its whole counter");
eq(U.calcSpeedData({}, next, 1000).eth0.down, 0, "first reading");
eq(U.calcSpeedData(undefined, next, 1000).eth0.down, 0, "no previous reading");
eq(U.calcSpeedData(prev, next, 0).eth0.down, 0, "zero duration");
eq(U.calcSpeedData(prev, next, -5).eth0.down, 0, "negative duration (clock set back)");

// --------------------------------------------------- interfaceShown / state
eq(U.interfaceShown("eth0", t.eth0, false, []), true, "physical shown");
eq(U.interfaceShown("wg0", t.wg0, false, []), false, "virtual hidden");
eq(U.interfaceShown("wg0", t.wg0, true, ["wg0"]), true, "selected virtual shown");
eq(U.interfaceShown("eth0", t.eth0, true, ["wg0"]), false, "not selected hidden");
eq(U.interfaceShown("eth", t.eth0, true, "eth0"), false, "text instead of a list does not match parts of names");
eq(U.interfaceShown("eth0", t.eth0, true, undefined), false, "no list");
eq(U.isConnected(t, false, []), true, "wifi up");
eq(U.isConnected({ eth0: t.eth0 }, false, []), false, "cable down");
eq(U.isConnected(t, true, ["wg0"]), true, "virtual unknown counts as up");
eq(U.isConnected(t, true, ["eth0"]), false, "selected cable down");
eq(U.isConnected(t, true, ["nothere"]), false, "selected interface missing");
eq(U.isConnected({}, false, []), false, "no interfaces");
// USB adapters and tethered phones often never leave "unknown"
eq(U.isConnected(U.parseTransferData("usb0,1,1,1,0,unknown\n"), false, []), true, "physical unknown counts as up");
eq(U.isConnected(U.parseTransferData("wlan0,1,1,1,1,dormant\n"), false, []), false, "dormant is not connected");
eq(U.wirelessInterface(t), "wlan0", "wifi name");
eq(U.wirelessInterface(U.parseTransferData("wlan0,1,1,1,1,down\nwlan1,1,1,1,1,up\n")), "wlan1", "wifi that is up wins");
eq(U.wirelessInterface(U.parseTransferData("wlan0,1,1,1,1,down\n")), "wlan0", "wifi down is still named");
eq(U.wirelessInterface({}), "", "no wifi");

// ------------------------------------------------------------------ pushSample
eq(U.pushSample([1, 2, 3], 4, 3), [2, 3, 4], "pushSample");
eq(U.pushSample([], 1, 3), [1], "pushSample empty");
eq(U.pushSample([1, 2, 3], 4, 1), [4], "pushSample max 1 does not grow");

// ---------------------------------------------------------------------- usage
const d = new Date(2026, 10, 26, 7, 0, 0);
eq(U.dayKey(d), "2026-11-26", "dayKey"); eq(U.monthKey(d), "2026-11", "monthKey");
eq(U.dayKey(new Date(2026, 0, 5)), "2026-01-05", "dayKey padding");
eq(U.dayKey(new Date(2026, 10, 26, 23, 59, 59, 999)), "2026-11-26", "last moment of the day");
eq(U.dayKey(new Date(2026, 10, 27, 0, 0, 0, 0)), "2026-11-27", "midnight (local time)");
let u = U.loadUsage('{"day":"2026-11-25","dayDown":5,"dayUp":1,"month":"2026-11","monthDown":50,"monthUp":10}', d);
eq([u.dayDown, u.monthDown], [0, 50], "new day keeps month");
u = U.addUsage(u, 100, 10, d); eq([u.dayDown, u.dayUp, u.monthDown, u.monthUp], [100, 10, 150, 20], "addUsage");
const beforeBad = JSON.stringify(u);
eq(JSON.stringify(U.addUsage(u, NaN, undefined, d)), beforeBad, "NaN adds nothing (it used to erase the counters)");
eq(JSON.stringify(U.addUsage(u, -500, -1, d)), beforeBad, "negative adds nothing");
eq(JSON.stringify(U.addUsage(u, Infinity, 1e300, d)), beforeBad, "absurd amounts add nothing");
eq(JSON.stringify(u), beforeBad, "addUsage does not change its argument");
u = U.addUsage(u, 1, 1, new Date(2026, 10, 27, 0, 0, 1));
eq([u.day, u.dayDown, u.month, u.monthDown], ["2026-11-27", 1, "2026-11", 151], "day rollover keeps month");
u = U.addUsage(u, 1, 1, new Date(2026, 11, 1)); eq([u.day, u.dayDown, u.month, u.monthDown], ["2026-12-01", 1, "2026-12", 1], "month rollover");
u = U.addUsage(u, 1, 1, new Date(2027, 0, 1)); eq([u.day, u.dayDown, u.month, u.monthDown], ["2027-01-01", 1, "2027-01", 1], "year rollover");
eq(U.loadUsage('garbage', d).monthDown, 0, "bad json");
for (const bad of ['', 'null', '5', '"text"', '[]', '[1,2]', 'true', '{"day":5}', undefined, null]) {
    eq(U.loadUsage(bad, d), { day: "2026-11-26", dayDown: 0, dayUp: 0, month: "2026-11", startDay: 1, monthDown: 0, monthUp: 0, history: [], limits: {}, ifaces: {}, totals: null }, "loadUsage " + bad);
}
u = U.loadUsage('{"day":"2026-11-26","dayDown":-5,"dayUp":"7","month":"2026-11","monthDown":1e300,"monthUp":null}', d);
eq([u.dayDown, u.dayUp, u.monthDown, u.monthUp], [0, 0, 0, 0], "negative / text / absurd / null values");
// summer time: the day that is 23 or 25 hours long is still one day
u = U.loadUsage('', new Date(2026, 2, 29, 0, 30));
u = U.addUsage(u, 10, 0, new Date(2026, 2, 29, 4, 30));
u = U.addUsage(u, 10, 0, new Date(2026, 2, 29, 23, 30));
eq([u.day, u.dayDown], ["2026-03-29", 20], "day of the clock change");

// usageDelta(delta, speed, prevSpeed, seconds)
eq(U.usageDelta(1000, 1000, 1000, 1), 1000, "normal delta");
eq(U.usageDelta(0, 1000, 1000, 1), 0, "counter did not move: nothing is added");
eq(U.usageDelta(-5, 1000, 1000, 1), 1000, "reset -> estimate");
eq(U.usageDelta(5e9, 1000, 1000, 1), 1000, "jump -> estimate");
eq(U.usageDelta(3e6, 1e6, 2e6, 1), 3e6, "burst within limit");
// a download between two readings: both speeds are low, the counter is right
eq(U.usageDelta(100e6, 0, 0, 10), 100e6, "100 MB burst unseen by the speed, 10 s interval");
eq(U.usageDelta(50e6, 2000, 0, 1), 50e6, "50 MB burst, 1 s interval");
eq(U.usageDelta(1e6, 0, 0, 0.1), 1e6, "0.1 s interval");
// a device joining the total with an old counter of several GB
eq(U.usageDelta(3e9, 5000, 4000, 1), 5000, "3 GB jump in 1 s");
eq(U.usageDelta(40e9, 5000, 4000, 10), 50000, "40 GB jump in 10 s");
// a fast link is not cut off at 1 Gbit/s when the speed was seen
eq(U.usageDelta(600e6, 300e6, 280e6, 2), 600e6, "2.5 Gbit/s link");
eq(U.usageDelta(NaN, 1000, 1000, 1), 1000, "NaN delta");
eq(U.usageDelta(undefined, 1000, 1000, 1), 1000, "missing delta");
eq(U.usageDelta(Infinity, 1000, 1000, 1), 1000, "infinite delta");
eq(U.usageDelta(-1, NaN, NaN, 1), 0, "NaN speed never gives NaN");
eq(U.usageDelta(-1, -50, 0, 1), 0, "negative speed");
eq(U.usageDelta(-1, 1000, 1000, -3), 0, "negative time");
eq(U.usageDelta(-1, 1000, 1000, NaN), 0, "NaN time");

// ---------------------------------------------------------- cleanHost / ping
eq(U.cleanHost("1.1.1.1"), "1.1.1.1", "host ok"); eq(U.cleanHost("a; rm -rf /"), "", "host rejected"); eq(U.cleanHost("-f"), "", "dash rejected");
eq(U.cleanHost("  example.org \n"), "example.org", "host trimmed");
eq(U.cleanHost("2606:4700:4700::1111"), "2606:4700:4700::1111", "ipv6 host");
eq(U.cleanHost("fe80::1%wlan0"), "fe80::1%wlan0", "ipv6 host with zone"); eq(U.cleanHost("example.org%eth0"), "", "zone only on an ipv6 address");
eq(U.cleanHost("fe80::1%eth0;id"), "", "zone with a command"); eq(U.cleanHost("fe80::1%"), "", "empty zone");
eq(U.routerAddress("192.168.1.1", "fe80::1", "wlan0"), "192.168.1.1", "router: ipv4 first");
eq(U.routerAddress("", "fe80::1", "wlan0"), "fe80::1%wlan0", "router: link-local ipv6 gets the interface");
eq(U.routerAddress("", "2001:db8::1", "wlan0"), "2001:db8::1", "router: global ipv6 as it is");
eq(U.routerAddress("", "", "wlan0"), "", "router: none"); eq(U.routerAddress("", "nonsense", "wlan0"), "", "router: not an address");
eq(cp.execFileSync("sh", ["-c", U.pingCommand("fe80::1%lo").replace(/^LC_ALL=C timeout 5 ping/, "printf '%s\\n'")]).toString().trim().split("\n").pop(), "fe80::1%lo", "ping gets the zoned address as one argument");
for (const bad of ["", null, undefined, "a b", "$(reboot)", "`id`", "a'b", 'a"b', "a\nb", "a|b", "a&b", "a>b", "x".repeat(254)]) {
    eq(U.cleanHost(bad), "", "host rejected: " + JSON.stringify(bad));
}
eq(U.escapeHtml('<img src="x">&'), '&lt;img src="x"&gt;&amp;', "escapeHtml");
eq(cp.execFileSync("sh", ["-c", U.copyTextCommand("a'b $(id)").replace(/^qdbus6/, "printf %s\\\\n").replace(" >/dev/null", "")]).toString().split("\n")[3], "a'b $(id)", "copyTextCommand keeps the text as one argument");
eq(U.linkInterface({lo:{physical:false,operstate:"unknown"},eth0:{physical:true,wireless:false,operstate:"down"},wlan0:{physical:true,wireless:true,operstate:"up"}}), "wlan0", "link: wifi up");
eq(U.linkInterface({eth0:{physical:true,wireless:false,operstate:"up"},wlan0:{physical:true,wireless:true,operstate:"down"}}), "eth0", "link: wired up");
eq(U.linkInterface({eth0:{physical:true,wireless:false,operstate:"up"},wlan0:{physical:true,wireless:true,operstate:"up"}}), "wlan0", "link: wifi preferred");
eq(U.linkInterface({eth0:{physical:true,wireless:false,operstate:"down"},wlan0:{physical:true,wireless:true,operstate:"down"}}), "", "link: none");
// ---------------------------------------------------------- history, interfaces, limit
{
    const G = 1024 * 1024 * 1024;
    const nov = new Date(2026, 10, 26), dec = new Date(2026, 11, 1), dec2 = new Date(2026, 11, 2);
    let u = U.loadUsage('{"day":"2026-11-26","dayDown":5,"dayUp":1,"month":"2026-11","monthDown":100,"monthUp":20}', nov);
    eq(u.history.length, 0, "no history yet");
    u = U.addUsage(u, 7, 3, dec);
    eq(JSON.stringify(u.history), '[{"month":"2026-11","down":100,"up":20,"day":1}]', "ended month goes to the history");
    eq(u.monthDown, 7, "new month starts at the new traffic");
    u = U.addUsage(u, 1, 1, dec2);
    eq(u.history.length, 1, "history entry is added once");
    let many = { day: "2020-01-01", month: "2020-01", monthDown: 1, monthUp: 0, history: [] };
    for (let y = 2020, m = 1, i = 0; i < 20; ++i) { many = U.rollUsage(many, new Date(y, m, 1)); many.monthDown = 5; if (++m > 11) { m = 0; ++y; } }
    eq(many.history.length, 12, "history keeps 12 months");
    eq(U.rollUsage({ history: [{ month: "x" }, null, 5, { month: "2026-01", down: -1, up: "a" }] }, nov).history.length, 1, "damaged history entries are dropped or cleaned");
    eq(JSON.stringify(U.rollUsage({ history: "no", ifaces: [1, 2], notified: 55 }, nov).ifaces), "{}", "damaged extras are ignored");

    const info1 = { wlan0: { rx: 1000, tx: 100, physical: true }, tun0: { rx: 5, tx: 5, physical: false } };
    let r = U.addInterfaceUsage(U.loadUsage("", nov), info1, nov);
    eq(r.changed, true, "first reading stores the counters"); eq(r.usage.ifaces.wlan0.monthDown, 0, "first reading counts nothing");
    eq(r.usage.ifaces.tun0, undefined, "virtual interfaces are not counted");
    r = U.addInterfaceUsage(r.usage, { wlan0: { rx: 1500, tx: 130, physical: true } }, nov);
    eq(r.usage.ifaces.wlan0.dayDown, 500, "interface download"); eq(r.usage.ifaces.wlan0.monthUp, 30, "interface upload");
    eq(U.addInterfaceUsage(r.usage, { wlan0: { rx: 1500, tx: 130, physical: true } }, nov).changed, false, "no traffic, no change");
    r = U.addInterfaceUsage(r.usage, { wlan0: { rx: 200, tx: 10, physical: true } }, nov);
    eq(r.usage.ifaces.wlan0.dayDown, 700, "counter started again from zero: the counter itself is counted");
    r = U.addInterfaceUsage(r.usage, { wlan0: { rx: 300, tx: 10, physical: true } }, dec);
    eq(r.usage.ifaces.wlan0.dayDown, 100, "interface counters roll over with the day"); eq(r.usage.ifaces.wlan0.monthDown, 100, "and with the month");
    const saved = JSON.parse(JSON.stringify(r.usage));
    eq(U.loadUsage(JSON.stringify(saved), dec).ifaces.wlan0.rx, 300, "interface counters survive saving");
    const crowd = {}; for (let i = 0; i < 40; ++i) { crowd["eth" + i] = { rx: 1, tx: 1, physical: true }; }
    eq(Object.keys(U.addInterfaceUsage(U.loadUsage("", nov), crowd, nov).usage.ifaces).length, 16, "at most 16 interfaces");

    eq(U.limitStage(0.79), 0, "stage below 80"); eq(U.limitStage(0.8), 80, "stage 80"); eq(U.limitStage(1.04), 100, "stage 100");
    eq(U.limitHue(0), 120, "green at 0"); eq(U.limitHue(0.5), 120, "green at half"); eq(U.limitHue(0.75), 60, "yellow at 75 %");
    eq(U.limitHue(0.9), 24, "orange at 90 %"); eq(U.limitHue(1), 0, "red at the limit"); eq(U.limitHue(3), 0, "red beyond"); eq(U.limitHue(NaN), 120, "hue of nonsense");
    eq(U.formatGiB(14.34 * G), "14.3", "GiB text");

    // counting period that starts on another day than the 1st
    eq(U.periodKey(new Date(2026, 10, 27), 15), "2026-11", "period: after the start day");
    eq(U.periodKey(new Date(2026, 10, 3), 15), "2026-10", "period: before the start day belongs to the previous one");
    eq(U.periodKey(new Date(2026, 0, 3), 15), "2025-12", "period: across the new year");
    eq(U.periodKey(new Date(2026, 10, 15), 15), "2026-11", "period: on the start day");
    eq(U.periodKey(new Date(2026, 10, 27), 1), "2026-11", "period: calendar month"); eq(U.periodKey(new Date(2026, 10, 27)), "2026-11", "period: no start day given");
    eq(U.cleanStartDay(31), 1, "start day above 28"); eq(U.cleanStartDay("x"), 1, "start day nonsense"); eq(U.cleanStartDay(28), 28, "start day 28");
    eq(U.periodStart(new Date(2026, 10, 3), 15).getMonth(), 9, "period start month"); eq(U.periodStart(new Date(2026, 10, 3), 15).getDate(), 15, "period start day");
    let p = U.loadUsage("", new Date(2026, 10, 10), 15);
    eq(p.month, "2026-10", "usage is keyed by the period"); eq(p.startDay, 15, "usage remembers the start day");
    p = U.addUsage(p, 100, 10, new Date(2026, 10, 14), 15);
    p = U.addUsage(p, 5, 5, new Date(2026, 10, 15), 15);
    eq(p.monthDown, 5, "a new period starts on the start day"); eq(p.dayDown, 5, "and a new day");
    eq(JSON.stringify(p.history), '[{"month":"2026-10","down":100,"up":10,"day":15}]', "the ended period goes to the history with its start day");
    p = U.addUsage(p, 1, 0, new Date(2026, 11, 1), 15);
    eq(p.monthDown, 6, "the 1st does not start a new period"); eq(p.history.length, 1, "nor add to the history");
    eq(U.rollUsage({ history: [{ month: "2026-01", down: 1, up: 1 }] }, nov).history[0].day, 1, "old history entries count from the 1st");

    // start value and resets
    const full = { day: "2026-11-26", dayDown: 5, dayUp: 1, month: "2026-11", monthDown: 100, monthUp: 20,
                   history: [{ month: "2026-10", down: 1, up: 1 }], ifaces: { wlan0: { dayDown: 4, dayUp: 1, monthDown: 90, monthUp: 9, rx: 777, tx: 55 } } };
    let rs = U.resetUsage(full, "today", nov);
    eq([rs.dayDown, rs.monthDown, rs.ifaces.wlan0.dayDown, rs.ifaces.wlan0.monthDown], [0, 100, 0, 90], "reset today");
    rs = U.resetUsage(full, "month", nov);
    eq([rs.dayDown, rs.monthDown, rs.monthUp, rs.ifaces.wlan0.monthDown, rs.ifaces.wlan0.dayDown], [5, 0, 0, 0, 4], "reset month");
    eq([rs.ifaces.wlan0.rx, rs.ifaces.wlan0.tx, rs.history.length], [777, 55, 1], "reset keeps the last byte counters and the history");
    eq(U.resetUsage(full, "history", nov).history.length, 0, "reset history"); eq(U.resetUsage(full, "history", nov).monthDown, 100, "reset history keeps the month");
    rs = U.resetUsage(full, "all", nov);
    eq([rs.dayDown, rs.monthDown, rs.history.length, rs.ifaces.wlan0.rx], [0, 0, 0, 777], "reset all");
    eq(U.resetUsage(full, "nonsense", nov).monthDown, 100, "unknown reset changes nothing");

    // several limits
    const cfgText = JSON.stringify([{ id: "a", iface: "wwan0", limit: 50, day: 15, usedTenths: 125 }, { id: "b", iface: "", limit: 500, day: 1 },
        { id: "a", iface: "", limit: 1 }, { id: "bad id", limit: 5 }, { id: "c", limit: 0 }, { id: "d", iface: "x;y", limit: 5 }, null, 7]);
    const lim = U.parseLimits(cfgText);
    eq(lim.map(l => l.id).join(","), "a,b", "limits: duplicates, bad ids, zero limits and bad interfaces are dropped");
    eq([lim[0].day, lim[0].usedTenths, lim[1].day, lim[1].usedTenths], [15, 125, 1, 0], "limits: fields");
    eq(U.parseLimits("nonsense").length, 0, "limits: damaged text"); eq(U.parseLimits("").length, 0, "limits: empty");
    eq(U.parseLimits(JSON.stringify(Array.from({ length: 20 }, (v, i) => ({ id: "l" + i, limit: 1 })))).length, 8, "limits: at most 8");
    let lr = U.rollLimits(U.loadUsage("", nov), lim, new Date(2026, 10, 20));
    eq(lr.usage.limits.a.period, "2026-11", "limit period by its own start day"); eq(lr.usage.limits.a.offset, 12.5 * G, "start value taken over");
    eq(lr.usage.limits.b.offset, 0, "no start value"); eq(lr.cleared.length, 0, "nothing cleared");
    lr = U.addLimitUsage(lr.usage, lim, { "": 1000, wwan0: 300, wlan0: 700 }, new Date(2026, 10, 20));
    eq([lr.usage.limits.a.used, lr.usage.limits.b.used], [300, 1000], "each limit counts its own connection");
    const kept = U.loadUsage(JSON.stringify(lr.usage), new Date(2026, 10, 21));
    eq(kept.limits.a.used, 300, "limit counters survive saving"); eq(kept.limits.a.applied, 125, "and what was applied");
    let st = U.limitStatus(kept, lim);
    eq(st[0].used, 12.5 * G + 300, "status: used with the start value"); eq(st[0].fraction > 0.25 && st[0].fraction < 0.2501, true, "status: fraction");
    eq(U.panelLimits(st, "auto", "wwan0").map(s => s.id).join(","), "a,b", "panel auto: connection in use and the all-connections limit");
    eq(U.panelLimits(st, "auto", "wlan0").map(s => s.id).join(","), "b", "panel auto: other connection");
    eq(U.panelLimits(st, "all", "").length, 2, "panel all"); eq(U.panelLimits(st, "none", "wwan0").length, 0, "panel none");
    // 1 December: b (day 1) starts again, a (day 15) does not
    lr = U.addLimitUsage(kept, lim, { "": 5, wwan0: 5 }, new Date(2026, 11, 1));
    eq([lr.usage.limits.a.used, lr.usage.limits.b.used], [305, 5], "periods end on their own days");
    // 15 December: a starts again and its start value ends
    lr = U.addLimitUsage(lr.usage, lim, { wwan0: 9 }, new Date(2026, 11, 15));
    eq([lr.usage.limits.a.used, lr.usage.limits.a.offset, lr.cleared.join(",")], [9, 0, "a"], "new period: counter and start value start again, settings to be cleared");
    const limCleared = U.parseLimits(JSON.stringify([{ id: "a", iface: "wwan0", limit: 50, day: 15, usedTenths: 0 }, { id: "b", iface: "", limit: 500, day: 1 }]));
    lr = U.rollLimits(lr.usage, limCleared, new Date(2026, 11, 16));
    eq([lr.usage.limits.a.offset, lr.usage.limits.a.applied, lr.cleared.length], [0, 0, 0], "after the settings were cleared");
    // a new figure entered later is taken over
    const limNew = U.parseLimits(JSON.stringify([{ id: "a", iface: "wwan0", limit: 50, day: 15, usedTenths: 30 }]));
    lr = U.rollLimits(lr.usage, limNew, new Date(2026, 11, 16));
    eq(lr.usage.limits.a.offset, 3 * G, "a new start value is taken over"); eq(lr.usage.limits.b, undefined, "a removed limit is forgotten");
    eq(U.resetLimit(lr.usage, "a").limits.a.offset, 0, "reset of one limit clears the start value"); eq(U.resetLimit(lr.usage, "a").limits.a.applied, 30, "and does not take it over again");
    eq(U.resetUsage(kept, "limits", nov).limits.a.used, 0, "reset of all limits"); eq(U.resetUsage(kept, "month", nov).limits.a.used, 300, "reset of the month leaves the limits");

}
eq(U.internetHost(""), "1.1.1.1", "internet host default"); eq(U.internetHost(" 9.9.9.9 "), "9.9.9.9", "internet host set"); eq(U.internetHost("a;b"), "1.1.1.1", "internet host unsafe");
eq(U.pingCommand("1.1.1.1"), "LC_ALL=C timeout 5 ping -n -c 1 -W 2 '1.1.1.1'", "ping command");
eq(U.pingCommand("x; touch /tmp/owned"), "false", "ping command with an unsafe host runs nothing");
eq(U.pingCommand("-f"), "false", "ping command with an option as host");
eq(U.parsePing("64 bytes from 1.1.1.1: icmp_seq=1 ttl=57 time=12.3 ms"), 12.3, "ping"); eq(U.parsePing("100% packet loss"), -1, "ping lost");
eq(U.parsePing("64 bytes from 127.0.0.1: icmp_seq=1 ttl=64 time=0.045 ms\n\n--- 127.0.0.1 ping statistics ---\n" +
    "1 packets transmitted, 1 received, 0% packet loss, time 0ms\nrtt min/avg/max/mdev = 0.045/0.045/0.045/0.000 ms\n"), 0.045, "ping full output");
eq(U.parsePing("64 bytes from 10.0.0.1: icmp_seq=1 ttl=64 time<1 ms"), 1, "ping time<1");
eq(U.parsePing("64 bytes from 10.0.0.1: seq=0 ttl=64 time=7 ms"), 7, "ping whole number");
eq(U.parsePing("PING x (10.0.0.9) 56(84) bytes of data.\n\n--- x ping statistics ---\n" +
    "1 packets transmitted, 0 received, 100% packet loss, time 0ms\n"), -1, "ping: 'time 0ms' of the summary is not an answer");
eq(U.parsePing("From 10.0.0.1 icmp_seq=1 Destination Host Unreachable"), -1, "ping unreachable");
eq(U.parsePing("64 bytes: time=12,3 ms"), -1, "comma decimals are not half-read as 3 ms");
eq(U.parsePing(""), -1, "ping empty"); eq(U.parsePing(undefined), -1, "ping no output");

// ---------------------------------------------------------------------- cleanIp
eq(U.cleanIp(" 203.0.113.7\n"), "203.0.113.7", "ip"); eq(U.cleanIp("<html>"), "", "ip rejected");
eq(U.cleanIp("2001:db8::1"), "2001:db8::1", "ipv6");
eq(U.cleanIp("::ffff:203.0.113.7"), "::ffff:203.0.113.7", "ipv4-mapped ipv6");
for (const bad of ["", "bad", "deadbeef", "...", "1.2.3", "999.1.1.1", "1.2.3.4.5", "12:30", "203.0.113.7 <br>", null, undefined]) {
    eq(U.cleanIp(bad), "", "ip rejected: " + JSON.stringify(bad));
}

// ------------------------------------------------------------- shell commands
eq(U.shellQuote("it's"), "'it'\\''s'", "shellQuote");
for (const text of ["it's", "a b", "$(echo x)", "`echo x`", "a\"b", "a\\b", "line1\nline2", "; echo x #", "-n", "", "ēžū 'x' $HOME"]) {
    // the shell must hand back exactly the text, whatever is in it
    const r = sh("printf %s " + U.shellQuote(text) + " # 123");
    eq(r.stdout, text, "shellQuote round trip " + JSON.stringify(text));
}
eq(U.launchCommand("org.kde.konsole.desktop"), "kstart --application 'org.kde.konsole' 2>/dev/null || gtk-launch 'org.kde.konsole'", "launch command");
// Every command gets ' # <number>' appended by the widget: it must stay valid
// shell, and nothing of the text may be executed
const commands = [U.NET_DATA_SOURCE, U.copyIpCommand(), U.notifyCommand("it's", "a b", "network-disconnect"),
    U.notifyCommand("-x", "$(touch /tmp/nsw-test-owned) `id` '; id; '", "a'b"), U.pingCommand("1.1.1.1"), U.pingCommand("bad host"),
    U.launchCommand("org.kde.konsole.desktop"), U.launchCommand("x'; id; '")];
for (const c of commands) {
    for (const suffix of ["", " # 1", " # 2147483647"]) {
        if (sh("sh -n -c " + U.shellQuote(c + suffix)).status !== 0) { fail++; console.log("FAIL shell syntax:", c + suffix); }
        count++;
    }
}

// ---------------------------------------------- NET_DATA_SOURCE on a fixture
// A made-up /proc/net/dev and /sys/class/net, run through every awk found here,
// and stand-ins for the desktop tools.
const fixture = fs.mkdtempSync(path.join(os.tmpdir(), 'nsw-test-'));
try {
    // Stand-ins for the desktop tools, first in PATH: each prints its arguments, one per line
    const bin = path.join(fixture, 'bin');
    fs.mkdirSync(bin);
    const tool = (name, body) => fs.writeFileSync(path.join(bin, name), "#!/bin/sh\n" + body + "\n", { mode: 0o755 });
    const withFakes = cmd => sh("PATH=" + U.shellQuote(bin) + ":$PATH; " + cmd);
    tool("notify-send", 'printf "%s\\n" "$@"');
    tool("gtk-launch", 'printf "gtk-launch %s\\n" "$@"');
    tool("kstart", 'exit 1');
    tool("qdbus6", 'echo "clip=$4"');
    tool("ip", 'echo "2: eth0    inet 192.168.1.20/24 brd 192.168.1.255 scope global eth0"; echo "3: docker0    inet 172.17.0.1/16 scope global docker0"');
    eq(withFakes(U.notifyCommand("-t", "50% $(id) `id` 'q'", "a'b") + " # 7").stdout,
       "-a\nNetspeed Widget\n-i\na'b\n-h\nstring:desktop-entry:io.github.zebieksterc.netspeedwidget\n--\n-t\n50% $(id) `id` 'q'\n", "notify arguments arrive unchanged");
    eq(withFakes(U.launchCommand("x'; id; '.desktop") + " # 8").stdout, "gtk-launch x'; id; '\n", "launch id arrives unchanged, gtk-launch used when kstart fails");
    tool("kstart", 'printf "kstart %s\\n" "$@"');
    eq(withFakes(U.launchCommand("org.kde.konsole.desktop") + " # 8").stdout, "kstart --application\nkstart org.kde.konsole\n", "kstart used once when it works");
    // copy IP: the address is cut at the slash, the first one wins
    eq(withFakes(U.copyIpCommand().replace('>/dev/null &&', '&&') + " # 9").stdout,
       "clip=192.168.1.20\n-a\nNetspeed Widget\n-i\nedit-copy\n-t\n2000\n-h\nstring:desktop-entry:io.github.zebieksterc.netspeedwidget\nIP address copied\n192.168.1.20\n", "copy IP");
    tool("ip", ':');
    eq(withFakes(U.copyIpCommand().replace('>/dev/null &&', '&&') + " # 10").stdout, "", "copy IP without an address does nothing");

    const sys = path.join(fixture, 'sys');
    const line = (name, rx, tx) => name.padStart(6) + ': ' + rx + ' 436 0 0 0 0 0 0 ' + tx + ' 472 0 0 0 0 0 0';
    fs.writeFileSync(path.join(fixture, 'dev'), [
        "Inter-|   Receive                                                |  Transmit",
        " face |bytes    packets errs drop fifo frame compressed multicast|bytes    packets errs drop fifo colls carrier compressed",
        "    lo:  690362     877    0    0    0     0          0         0   690362     877    0    0    0     0       0          0",
        line("eth0", 451484, 431396),                                  // short name: spaces in front
        line("enp3s0", 1234567, 7654321),                              // 6 characters: no space in front
        line("wlp2s0", "18446744073709551615", "98765432109876"),      // largest possible counter
        "enp0s20f0u2:12345678 436 0 0 0 0 0 0 87654321 472 0 0 0 0 0 0", // no space after the colon (old kernels)
        line("br-0123456789ab", 111, 222),                             // 15 characters, dash
        line("eth0.100", 333, 444),                                    // VLAN, dot
        line("veth1@if2", 555, 666),
        line("wg0", 777, 888),
        line("usb0", 999, 1000),
        line("gone0", 1, 2),                                           // listed, but no folder in /sys
        "",
    ].join("\n"));
    const dev = (name, opts) => {
        fs.mkdirSync(path.join(sys, name), { recursive: true });
        if (opts.state !== undefined) fs.writeFileSync(path.join(sys, name, 'operstate'), opts.state + "\n");
        fs.writeFileSync(path.join(sys, name, 'uevent'), (opts.devtype ? "DEVTYPE=" + opts.devtype + "\n" : "") + "INTERFACE=" + name + "\nIFINDEX=2\n");
        if (opts.physical) {
            fs.mkdirSync(path.join(sys, name, 'device'));
            fs.writeFileSync(path.join(sys, name, 'device', 'uevent'), "DRIVER=x\n");
        }
    };
    dev("lo", { state: "unknown" });
    dev("eth0", { state: "up", physical: true });
    dev("enp3s0", { state: "down", physical: true });
    dev("wlp2s0", { state: "up", physical: true, devtype: "wlan" });
    dev("enp0s20f0u2", { state: "unknown", physical: true });
    dev("br-0123456789ab", { state: "up", devtype: "bridge" });
    dev("eth0.100", { state: "up", devtype: "vlan" });
    dev("veth1@if2", { state: "lowerlayerdown" });
    dev("wg0", { state: "unknown", devtype: "wireguard" });
    dev("usb0", { physical: true, devtype: "wwan" });             // no operstate file
    const expected =
        "lo,690362,690362,0,0,unknown\n" +
        "eth0,451484,431396,1,0,up\n" +
        "enp3s0,1234567,7654321,1,0,down\n" +
        "wlp2s0,18446744073709551615,98765432109876,1,1,up\n" +
        "enp0s20f0u2,12345678,87654321,1,0,unknown\n" +
        "br-0123456789ab,111,222,0,0,up\n" +
        "eth0.100,333,444,0,0,up\n" +
        "veth1@if2,555,666,0,0,lowerlayerdown\n" +
        "wg0,777,888,0,0,unknown\n" +
        "usb0,999,1000,1,0,unknown\n" +
        "gone0,1,2,0,0,unknown\n";
    const onFixture = U.NET_DATA_SOURCE.split("/proc/net/dev").join(path.join(fixture, 'dev')).split("/sys/class/net/").join(sys + "/");
    const awks = ["awk", "gawk", "mawk", "busybox awk", "original-awk"].filter(a => have(a.split(" ")[0]));
    for (const awk of awks) {
        const r = sh(onFixture.replace(/^awk/, awk) + " # 1");
        eq(r.stdout, expected, "NET_DATA_SOURCE with " + awk);
        eq([r.status, r.stderr], [0, ""], "NET_DATA_SOURCE exit code and stderr with " + awk);
    }
    console.log("NET_DATA_SOURCE checked with: " + awks.join(", "));
    const parsed = U.parseTransferData(expected);
    eq(Object.keys(parsed).length, 10, "fixture parsed (all but lo)");
    eq([parsed.enp3s0.rx, parsed.enp3s0.tx, parsed.enp3s0.physical], [1234567, 7654321, true], "6-character name parsed");
    eq(U.wirelessInterface(parsed), "wlp2s0", "fixture wifi");
} finally {
    fs.rmSync(fixture, { recursive: true, force: true });
}

// --------------------------------------------- NET_DATA_SOURCE on this machine
// Every interface of the real /proc/net/dev must come out with the same counters
// position as "ip"/the kernel names them.
const out = cp.execSync(U.NET_DATA_SOURCE + " # 1", { shell: '/bin/sh' }).toString();
const real = fs.readFileSync('/proc/net/dev', 'utf8').split("\n").slice(2).filter(l => l.includes(":")).map(l => l.split(":")[0].trim());
eq(out.trim().split("\n").map(l => l.split(",")[0]), real, "names of this machine");
eq(out.trim().split("\n").every(l => /^[^,]+,\d+,\d+,[01],[01],[a-z]+$/.test(l)), true, "line format on this machine");
console.log("awk output on this machine:\n" + out.trim());

// ------------------------------------------------------------ catch-up after a restart
{
    const S = { key: "sensors", down: 1000, up: 200 };
    eq(U.catchUpTotals(S, { key: "sensors", down: 1500, up: 260 }), { down: 500, up: 60, matched: true }, "traffic while the widget was off is caught up");
    eq(U.catchUpTotals(S, { key: "sensors", down: 1000, up: 200 }), { down: 0, up: 0, matched: true }, "nothing transferred, nothing added");
    eq(U.catchUpTotals(S, { key: "sensors", down: 300, up: 250 }), { down: 300, up: 50, matched: true }, "counter started again after a reboot: the counter itself");
    eq(U.catchUpTotals(S, { key: "sensors", down: 0, up: 0 }), null, "counters not delivered yet: ask again");
    eq(U.catchUpTotals(S, null), null, "no counters yet: ask again");
    eq(U.catchUpTotals(null, { key: "sensors", down: 900, up: 1 }), { down: 0, up: 0, matched: true }, "first start: nothing to catch up");
    eq(U.catchUpTotals(S, { key: "proc:wlan0", down: 900, up: 1 }), { down: 0, up: 0, matched: false }, "other counters are not compared");
    eq(U.catchUpTotals({ key: "sensors", down: -5, up: "x" }, { key: "sensors", down: 70, up: 8 }), { down: 70, up: 8, matched: true }, "damaged saved position counts as zero");
    eq(U.cleanTotals({ key: "", down: 1, up: 1 }), null, "position without a key"); eq(U.cleanTotals("x"), null, "position that is no object");
    const d = new Date(2026, 10, 27, 12, 0, 0);
    let u = U.loadUsage(JSON.stringify({ day: U.dayKey(d), dayDown: 5, month: U.periodKey(d, 1), monthDown: 9, totals: S }), d, 1);
    eq(u.totals, S, "saved position survives loading");
    u = U.addUsage(u, 10, 1, d, 1); eq(u.totals, S, "and counting"); eq(u.dayDown, 15, "counting still works");
    u = U.resetUsage(u, "all", d, 1); eq(u.totals, S, "and a reset: a reset must not bring old traffic back");
    eq(U.loadUsage('{"totals":{"key":7}}', d, 1).totals, null, "damaged position is dropped");
}

// ------------------------------------------------------------ notification entry
eq(U.localPath("file:///a%20b/c.desktop"), "/a b/c.desktop", "local path from a file URL");
eq(U.localPath("/x/y"), "/x/y", "local path stays"); eq(U.localPath("qrc:/x"), "", "not a local path");
eq(U.localPath("file://%E0%A4%A"), "", "damaged URL"); eq(U.localPath("relative/x"), "", "relative path"); eq(U.localPath(""), "", "empty path");
eq(U.desktopEntryCommand("http://x/y"), "true", "entry command runs nothing for a bad path");
{
    const os = require('os'), path = require('path');
    const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "nsw-entry "));   // with a space in the path
    const src = path.join(tmp, "it's.desktop"), home = path.join(tmp, "data");
    const dest = path.join(home, "applications", U.DESKTOP_ENTRY + ".desktop");
    const env = Object.assign({}, process.env, { XDG_DATA_HOME: home, PATH: process.env.PATH });
    const runIt = () => cp.execSync(U.desktopEntryCommand("file://" + encodeURI(src)) + " # 1", { shell: '/bin/sh', env: env });
    fs.writeFileSync(src, "[Desktop Entry]\nName=A\n");
    runIt(); eq(fs.readFileSync(dest, 'utf8'), "[Desktop Entry]\nName=A\n", "entry is put in place");
    const first = fs.statSync(dest).mtimeMs; runIt(); eq(fs.statSync(dest).mtimeMs, first, "same entry is left alone");
    fs.writeFileSync(src, "[Desktop Entry]\nName=B\n"); runIt(); eq(fs.readFileSync(dest, 'utf8'), "[Desktop Entry]\nName=B\n", "changed entry is replaced");
    eq(fs.readdirSync(path.dirname(dest)).length, 1, "no temporary file is left");
    fs.unlinkSync(src); runIt(); eq(fs.existsSync(dest), true, "missing source changes nothing");
    cp.execSync(U.desktopEntryCommand(src) + " # 1", { shell: '/bin/sh', env: Object.assign({}, env, { XDG_DATA_HOME: "relative" , HOME: tmp }) });
    eq(fs.existsSync(path.join(tmp, "relative")), false, "a relative XDG_DATA_HOME is not used");
    fs.rmSync(tmp, { recursive: true, force: true });
}

// ------------------------------------------------------------ real ping, if any
if (have('ping') && have('timeout')) {
    const r = sh(U.pingCommand("127.0.0.1") + " # 1");
    if (r.status === 0) {
        const ms = U.parsePing(r.stdout);
        eq(ms >= 0 && ms < 2000, true, "real ping parsed: " + ms);
        console.log("real ping to 127.0.0.1: " + ms + " ms");
    } else {
        console.log("real ping not possible here (exit " + r.status + "), skipped");
    }
} else {
    console.log("ping not installed, real ping skipped");
}

console.log(fail ? fail + " of " + count + " FAILED" : "all " + count + " helper tests passed");
process.exit(fail ? 1 : 0);
