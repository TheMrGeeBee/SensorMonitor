// Run: node tests/run.js   (checks sensors.js against real sensor dumps from both machines)
const fs = require("fs"), path = require("path"), assert = require("assert")
const src = fs.readFileSync(path.join(__dirname, "../org.mrgeebee.sensormonitor/contents/ui/sensors.js"), "utf8")
const S = new Function(src.replace(".pragma library", "") + "; return {parseOutput, describeAll, compare}")()
const fx = n => fs.readFileSync(path.join(__dirname, "fixtures", n + ".txt"), "utf8")

function view(text, user) {
    const p = S.parseOutput(text)
    if (user !== undefined) p.user = user
    const d = S.describeAll(p).sort(S.compare)
    return d.map(x => `${x.group}|${x.label}${x.defaultHidden ? "|hidden" : ""}${x.stopped ? "|stopped" : ""}`)
}
const has = (list, s) => assert(list.includes(s), `missing "${s}"\n` + list.join("\n"))

const pc = view(fx("desktop"))
console.log("== desktop\n" + pc.join("\n"))
for (let i = 1; i <= 8; i++) has(pc, `CPU P-Cores|P-Core ${i}`)
has(pc, "Storage|NVMe 0"); assert(pc.indexOf("Storage|NVMe 0") < pc.indexOf("Storage|NVMe 1"), "NVMe order")
for (let i = 1; i <= 4; i++) has(pc, `CPU E-Cores|E-Core ${i}`)
assert(!pc.some(x => x.includes("P-Core 9")), "too many P-cores")

const tp = view(fx("thinkpad"))
console.log("\n== thinkpad\n" + tp.join("\n"))
for (let i = 1; i <= 4; i++) has(tp, `CPU P-Cores|P-Core ${i}`)
assert(!tp.some(x => x.startsWith("CPU E-Cores")), "laptop has no E-cores")
has(tp, "Fans|Fan 1"); has(tp, "Network|Wi-Fi"); has(tp, "Motherboard|Chipset (PCH)")
has(tp, "Motherboard|EC Sensor 10|stopped")   // 4 °C: bogus, hidden by the "stopped" filter

// user file: overlay, host-specific rule wins over global, bad rules ignored
const u = view(fx("thinkpad"), { rules: [{ match: "thinkpad/temp1", name: "CPU Die", group: "CPU" },
                                          { match: "iwlwifi*", hide: true }, { nomatch: 1 }],
                                 hosts: { "laptop": { rules: [{ match: "thinkpad/temp1", name: "Host wins" }] } } })
has(u, "Motherboard|Host wins")   // first matching rule wins as a whole (host rules come first); has(u, "Network|Wi-Fi|hidden")
const bad = S.parseOutput(fx("thinkpad") + "meta\tuserfile\t-\t{ not json\n")
assert(bad.error && bad.user === null, "bad JSON should set error and be ignored")

// unknown chip: grouped by its own name, unlabeled readings hidden by default
const unk = view("meta\thost\t-\tx\ntemp\tfoo_bar/d/temp1\tfoo_bar temp1\t40000\ntemp\tfoo_bar/d/temp2\tfoo_bar CPU Tdie\t41000\n")
has(unk, "Foo bar|Temp 1|hidden"); has(unk, "Foo bar|CPU Tdie")
console.log("\nall tests passed")
