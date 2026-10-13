# Sensor Monitor

A KDE Plasma 6 widget that shows your hardware sensors: temperatures coloured from blue
(cold) to red (hot) and fan speeds in RPM. It is read-only and needs no extra software:
it reads `/sys/class/hwmon` directly (no `lm_sensors`).

## Features

- Sensors are grouped and named automatically: CPU, P- and E-cores, GPU, memory,
  storage, motherboard, network and fans.
- Core numbering adapts to the CPU, including hybrid Intel (P/E) designs.
- Unlabeled readings from unknown chips are hidden until you enable them, and 0 RPM fans
  and bogus temperatures can be hidden.
- Per-sensor show/hide and renaming in the widget settings.
- Optional rules file to rename, regroup or hide sensors, with per-host sections so one
  file can be shared between computers.
- Desktop or panel use: standard, translucent or transparent background, adjustable size
  and temperature colour range. In a panel it shows the hottest temperature.

## Requirements

- KDE Plasma 6 (the metadata sets a minimum API version of 6.0)
- Linux with hwmon sensors under `/sys/class/hwmon`

## Install

From a `.plasmoid` file (right-click the desktop or panel, Add Widgets, Get New Widgets,
Install Widget From Local File), or from the command line:

    kpackagetool6 -t Plasma/Applet -i org.mrgeebee.sensormonitor.plasmoid

From a checkout of this repository:

    ./install.sh                 # install or update on this machine
    ./install.sh <ssh-host>      # install or update on another machine over ssh
    ./install.sh --zip           # build dist/org.mrgeebee.sensormonitor.plasmoid

Restart plasmashell to load a new version: `kquitapp6 plasmashell && kstart plasmashell`.
`systemctl --user restart plasma-plasmashell` only works if plasmashell was started by
that unit. Otherwise the new process exits at once and the old shell keeps running the
old code.

## Configuration

Right-click the widget and choose Configure. There you can set the refresh interval, the
temperature range for the colours, the background and size, and pick which sensors are
shown and what they are called. These settings are stored per computer.

### Custom rules file

For naming that follows you between machines, create `~/.config/sensormonitor.json`
(or `$XDG_CONFIG_HOME/sensormonitor.json`). It can be a symlink into a synced folder.
See `sensormonitor.example.json`.

    {
      "rules": [
        { "match": "thinkpad/temp1", "name": "CPU (EC)" },
        { "match": "thinkpad/temp10", "hide": true }
      ],
      "hosts": {
        "my-laptop": { "rules": [ { "match": "pch_*/*", "name": "PCH" } ] }
      }
    }

- `rules` are tried in order. Rules in `hosts.<hostname>` come first for that computer.
- `match` is a case-insensitive glob (`*`, `?`) on `"<chip>/<label>"`, for example
  `coretemp/Core 3`, `nvme/Composite` or `thinkpad/temp10`. Sensors without a label use
  `tempN` or `fanN`. Optional `device` is a glob on the hwmon device (such as `nvme1`).
- Optional fields: `group`, `name`, `key` (sort order inside the group) and `hide`
  (`true` or `false`). `group` and `name` may use `$1`, `$2`, ... for the text matched by
  each `*`, plus `{dev}` and `{devnum}` (the device name and its trailing number).
- The first matching rule applies as a whole. It overlays the built-in result, and fields
  it leaves out keep their built-in values.
- A file with invalid JSON is ignored, and the error is shown in the widget settings.

To see the raw sensor ids, run `sh org.mrgeebee.sensormonitor/contents/scripts/read-sensors.sh`.
Each line is `kind`, `chip/device/label`, a display text and the raw value (millidegrees
for temperatures).

## How naming works

`contents/ui/sensors.js` holds a table of built-in rules that map a chip and label to a
group and a name. Cores are numbered by their rank among the cores present, with
E-cores taken from `/sys/devices/cpu_atom/cpus`. A chip without a rule gets its own group
named after the chip. To support new hardware, add a row to the table in `sensors.js`.

## Development

    node tests/run.js

The tests check the naming against real sensor dumps in `tests/fixtures/`. To add a
machine, save the output of `read-sensors.sh` there and add expectations to
`tests/run.js`. `install.sh` also runs `qmllint` (`/usr/lib/qt6/bin/qmllint`) and aborts
on errors.

## Releasing

Bump `VERSION` and `Version` in `org.mrgeebee.sensormonitor/metadata.json` together
(`install.sh` refuses to run if they differ), then build with `./install.sh --zip` and
upload `dist/org.mrgeebee.sensormonitor.plasmoid` to the KDE Store. Tag the release in git
(`git tag v1.0.0`).

## License

GPL-3.0-or-later. See `LICENSE`.
