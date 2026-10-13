#!/bin/sh
# Read-only. Prints tab-separated lines:
#   meta<TAB>key<TAB>-<TAB>value                 host name, hybrid E-core ids, user rules file
#   kind<TAB>id<TAB>label<TAB>raw                every hwmon temp/fan input (kind = temp|fan)
printf 'meta\thost\t-\t%s\n' "$(cat /proc/sys/kernel/hostname 2>/dev/null)"

# Core ids (as coretemp labels them) of the E-cores on hybrid Intel CPUs; absent otherwise.
atom=/sys/devices/cpu_atom/cpus
if [ -r "$atom" ]; then
    ids=$(for r in $(tr ',' ' ' < "$atom"); do
        case $r in *-*) s=${r%-*}; e=${r#*-} ;; *) s=$r; e=$r ;; esac
        for c in $(seq "$s" "$e"); do cat "/sys/devices/system/cpu/cpu$c/topology/core_id" 2>/dev/null; done
    done | sort -nu | tr '\n' ',')
    printf 'meta\tecores\t-\t%s\n' "$ids"
fi

# Optional user rules; newlines/tabs are only whitespace in JSON, so flattening is safe.
uf="${XDG_CONFIG_HOME:-$HOME/.config}/sensormonitor.json"
printf 'meta\tuserpath\t-\t%s\n' "$uf"
[ -r "$uf" ] && printf 'meta\tuserfile\t-\t%s\n' "$(tr '\n\t\r' '   ' < "$uf")"

for h in /sys/class/hwmon/hwmon*; do
    [ -d "$h" ] || continue
    chip=$(cat "$h/name" 2>/dev/null) || continue
    dev=$(basename "$(readlink -f "$h/device" 2>/dev/null)" 2>/dev/null)
    for kind in temp fan; do
        for f in "$h"/${kind}*_input; do
            [ -r "$f" ] || continue
            b=${f##*/}; n=${b%_input}
            v=$(cat "$f" 2>/dev/null) || continue
            l=$(cat "$h/${n}_label" 2>/dev/null) || l=$n
            printf '%s\t%s/%s/%s\t%s %s\t%s\n' "$kind" "$chip" "$dev" "$n" "$chip" "$l" "$v"
        done
    done
done
