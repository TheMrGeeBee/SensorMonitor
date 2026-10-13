.pragma library

var ORDER = ["CPU", "CPU P-Cores", "CPU E-Cores", "GPU", "Memory", "Storage",
             "Motherboard", "Network", "Fans", "Other"]

// Built-in rules, tried in order against "<chip>/<label>" (e.g. "coretemp/Core 3").
// group/name/key are templates: $1.. are regex captures, {dev} is the hwmon device
// (e.g. "nvme0") and {devnum} its trailing digits. `core` rules are numbered by rank
// among the coretemp cores present (see describeAll), so they need no per-CPU tuning.
var BUILTIN = [
    { re: /^coretemp\/Package/, group: "CPU", name: "CPU Package" },
    { re: /^coretemp\/Core (\d+)$/, core: true },
    { re: /^coretemp\/(.*)$/, group: "CPU", name: "$1" },
    { re: /^k10temp\/Tctl$/, group: "CPU", name: "CPU Package" },
    { re: /^k10temp\/(.*)$/, group: "CPU", name: "CPU $1" },

    { re: /^xe\/pkg$/, group: "GPU", name: "GPU Temp" },
    { re: /^xe\/vram$/, group: "GPU", name: "GPU VRAM" },
    { re: /^xe\/fan(\d+)$/, group: "GPU", name: "GPU Fan $1" },
    { re: /^xe\/(.*)$/, group: "GPU", name: "GPU $1" },
    { re: /^amdgpu\/edge$/, group: "GPU", name: "GPU Temp" },
    { re: /^amdgpu\/junction$/, group: "GPU", name: "GPU Hotspot" },
    { re: /^amdgpu\/mem$/, group: "GPU", name: "GPU VRAM" },
    { re: /^amdgpu\/fan(\d+)$/, group: "GPU", name: "GPU Fan $1" },

    { re: /^nvme\/Composite$/, group: "Storage", name: "NVMe {devnum}", key: "{devnum}" },
    { re: /^nvme\/(.*)$/, group: "Storage", name: "NVMe {devnum} $1", key: "{devnum}" },
    { re: /^spd5118\//, group: "Memory", name: "DIMM ({dev})" },

    { re: /^iwlwifi[^\/]*\//, group: "Network", name: "Wi-Fi" },
    { re: /^r8169[^\/]*\//, group: "Network", name: "Network Chip" },

    { re: /^nct[^\/]*\/fan(\d+)$/, group: "Fans", name: "Fan $1" },
    { re: /^nct[^\/]*\/PECI/, group: "CPU", name: "CPU (PECI)" },
    { re: /^nct[^\/]*\/SYSTIN$/, group: "Motherboard", name: "System" },
    { re: /^nct[^\/]*\/CPUTIN$/, group: "Motherboard", name: "CPU Socket" },
    { re: /^nct[^\/]*\/AUXTIN(\d+)$/, group: "Motherboard", name: "Aux Probe $1" },
    { re: /^nct[^\/]*\/(.*)$/, group: "Motherboard", name: "$1" },

    // ThinkPad embedded controller: sensors are unlabeled and model-specific
    { re: /^thinkpad\/fan(\d+)$/, group: "Fans", name: "Fan $1" },
    { re: /^thinkpad\/temp(\d+)$/, group: "Motherboard", name: "EC Sensor $1", key: "$1" },
    { re: /^acpitz\//, group: "Motherboard", name: "ACPI Thermal Zone" },
    { re: /^pch_[^\/]*\//, group: "Motherboard", name: "Chipset (PCH)" }
]

function globToRegex(g) {
    var re = String(g).replace(/[.+^${}()|[\]\\]/g, "\\$&").replace(/\*/g, "(.*)").replace(/\?/g, ".")
    return new RegExp("^" + re + "$", "i")
}

function fill(t, caps, dev) {
    return String(t)
        .replace(/\$(\d)/g, function (m, i) { return caps[i] === undefined ? "" : caps[i] })
        .replace(/\{devnum\}/g, dev.replace(/^\D+/, ""))
        .replace(/\{dev\}/g, dev)
}

function prettify(s) {
    return String(s).replace(/_/g, " ").replace(/^([a-z])/, function (c) { return c.toUpperCase() })
        .replace(/^(Temp|Fan)(\d+)$/, "$1 $2")
}

// Split the helper script's output into {host, ecores, user, userPath, error, sensors}.
function parseOutput(text) {
    var out = { host: "", ecores: [], user: null, userPath: "", error: "", sensors: [] }
    var lines = String(text).split("\n")
    for (var i = 0; i < lines.length; i++) {
        var f = lines[i].split("\t")
        if (f.length < 4) continue
        if (f[0] === "meta") {
            if (f[1] === "host") out.host = f[3].trim()
            else if (f[1] === "userpath") out.userPath = f[3].trim()
            else if (f[1] === "ecores") out.ecores = f[3].split(",").filter(function (x) { return x !== "" }).map(Number)
            else if (f[1] === "userfile") {
                try { out.user = JSON.parse(f[3]) } catch (e) { out.error = String(e.message || e) }
            }
            continue
        }
        var raw = parseFloat(f[3])
        if (isNaN(raw)) continue
        out.sensors.push({ kind: f[0], sid: f[1], text: f[2], raw: raw, idx: i })
    }
    return out
}

// User overlay rules (per-host rules first, then global). Each may set group, name, key, hide.
function userRules(parsed) {
    var u = parsed.user, out = []
    if (!u || typeof u !== "object") return out
    var lists = []
    if (u.hosts && u.hosts[parsed.host] && Array.isArray(u.hosts[parsed.host].rules)) lists.push(u.hosts[parsed.host].rules)
    if (Array.isArray(u.rules)) lists.push(u.rules)
    lists.forEach(function (l) {
        l.forEach(function (r) {
            if (!r || typeof r.match !== "string") return
            out.push({ re: globToRegex(r.match), devRe: typeof r.device === "string" ? globToRegex(r.device) : null,
                       group: r.group, name: r.name, key: r.key, hide: r.hide })
        })
    })
    return out
}

function firstMatch(rules, it) {
    for (var i = 0; i < rules.length; i++) {
        var r = rules[i]
        var m = r.re.exec(it.subject)
        if (!m) continue
        if (r.devRe && !r.devRe.test(it.dev)) continue
        return { rule: r, caps: m }
    }
    return null
}

// One descriptor per sensor: {sid, kind, label, group, order, key, idx, value, defaultHidden, stopped}.
function describeAll(parsed) {
    var user = userRules(parsed)
    var eset = {}
    parsed.ecores.forEach(function (n) { eset[n] = true })
    var pcores = [], ecores = []

    var items = parsed.sensors.map(function (s) {
        var parts = s.sid.split("/"), chip = parts[0]
        var it = { s: s, chip: chip, dev: parts[1] || "" }
        it.raw = s.text.indexOf(chip + " ") === 0 ? s.text.substring(chip.length + 1) : s.text
        it.subject = chip + "/" + it.raw
        it.value = s.kind === "temp" ? s.raw / 1000 : s.raw
        it.hit = firstMatch(BUILTIN, it)
        if (it.hit && it.hit.rule.core) {
            it.core = parseInt(it.hit.caps[1])
            ;(eset[it.core] ? ecores : pcores).push(it.core)
        }
        return it
    })
    pcores.sort(function (a, b) { return a - b })
    ecores.sort(function (a, b) { return a - b })

    return items.map(function (it) {
        var group, name, key = 0, hidden
        if (it.hit && it.hit.rule.core) {
            var isE = !!eset[it.core]
            group = isE ? "CPU E-Cores" : "CPU P-Cores"
            name = (isE ? "E-Core " : "P-Core ") + ((isE ? ecores : pcores).indexOf(it.core) + 1)
            key = it.core
            hidden = false
        } else if (it.hit) {
            var r = it.hit.rule
            group = fill(r.group, it.hit.caps, it.dev)
            name = fill(r.name, it.hit.caps, it.dev)
            key = r.key ? parseInt(fill(r.key, it.hit.caps, it.dev)) || 0 : 0
            hidden = false
        } else {
            // Unknown chip: group under its own name; unlabeled readings stay hidden until enabled
            group = prettify(it.chip)
            name = prettify(it.raw)
            hidden = /^(temp|fan)\d+$/.test(it.raw)
        }
        var u = firstMatch(user, it)
        if (u) {
            if (typeof u.rule.group === "string") group = fill(u.rule.group, u.caps, it.dev)
            if (typeof u.rule.name === "string") name = fill(u.rule.name, u.caps, it.dev)
            if (u.rule.key !== undefined) key = parseInt(fill(u.rule.key, u.caps, it.dev)) || 0
            if (typeof u.rule.hide === "boolean") hidden = u.rule.hide
        }
        var g = ORDER.indexOf(group)
        var isTemp = it.s.kind === "temp"
        return { sid: it.s.sid, kind: it.s.kind, label: name, group: group,
                 order: g < 0 ? ORDER.length : g, key: key, idx: it.s.idx, value: it.value,
                 defaultHidden: hidden,
                 // 0 RPM fans and temperatures no real sensor reports (unpopulated / bogus)
                 stopped: isTemp ? (it.value <= 5 || it.value >= 125) : it.value <= 0 }
    })
}

// Sort descriptors by group, then key, then original order.
function compare(a, b) {
    return (a.order - b.order) || (a.group < b.group ? -1 : a.group > b.group ? 1 : 0)
        || (a.key - b.key) || (a.idx - b.idx)
}
