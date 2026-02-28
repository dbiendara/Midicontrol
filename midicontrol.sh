#!/bin/bash

CONFIG_FILE="./config.txt"
MIDI_OUT_PORT=$(amidi -l | grep "nanoKONTROL2" | awk '{print $2}')

# ---------------------------------------------------------
# 1. Config in den RAM laden (Assoziatives Array)
# ---------------------------------------------------------
declare -A MAPPINGS
while IFS='=' read -r key value; do
    [[ "$key" =~ ^#.* ]] || [[ -z "$key" ]] && continue
    MAPPINGS["$key"]="$value"
done < "$CONFIG_FILE"

# Array für den letzten Wert (Jitter-Schutz)
declare -A LAST_VALUES

# ---------------------------------------------------------
# Helper Funktionen (Minimale Subshells)
# ---------------------------------------------------------

led_on() {
    [ -n "$MIDI_OUT_PORT" ] && printf -v HEX "%02X" "$1" && amidi -p "$MIDI_OUT_PORT" -S "B0 $HEX 7F"
}

led_off() {
    [ -n "$MIDI_OUT_PORT" ] && printf -v HEX "%02X" "$1" && amidi -p "$MIDI_OUT_PORT" -S "B0 $HEX 00"
}

update_mute_led() {
    local ctrl=$1
    local mapping=$2
    local status
    
    if [[ "$mapping" == mute_source:* ]]; then
        status=$(LC_ALL=C pactl get-source-mute "${mapping#mute_source:}" 2>/dev/null)
        [[ "$status" == *"yes"* ]] && led_on "$ctrl" || led_off "$ctrl"
        qdbus6 org.kde.plasmashell /org/kde/osdService org.kde.osdService.microphoneMuted >/dev/null 2>&1
    elif [[ "$mapping" == mute_sink:* ]]; then
        status=$(LC_ALL=C pactl get-sink-mute "${mapping#mute_sink:}" 2>/dev/null)
        [[ "$status" == *"yes"* ]] && led_on "$ctrl" || led_off "$ctrl"
    fi
}

# ---------------------------------------------------------
# Main Loop mit Jitter-Filter
# ---------------------------------------------------------

# Initial LED Sync
for key in "${!MAPPINGS[@]}"; do
    [[ "$key" == "leds" ]] && IFS=',' read -ra LEDS <<< "${MAPPINGS[$key]}" && for b in "${LEDS[@]}"; do led_on "$b"; done
    [[ "${MAPPINGS[$key]}" == mute_* ]] && update_mute_led "$key" "${MAPPINGS[$key]}"
done

aseqdump -p "nanoKONTROL2" | while read -r LINE; do
    if [[ "$LINE" =~ controller\ ([0-9]+),\ value\ ([0-9]+) ]]; then
        CTRL=${BASH_REMATCH[1]}
        VALUE=${BASH_REMATCH[2]}
        MAPPING=${MAPPINGS[$CTRL]}

        # Jitter Filter: Nur reagieren, wenn Wert sich geändert hat
        [[ "${LAST_VALUES[$CTRL]}" == "$VALUE" ]] && continue
        LAST_VALUES[$CTRL]="$VALUE"

        [[ -z "$MAPPING" ]] && continue

        case "$MAPPING" in
            play) [ "$VALUE" -gt 0 ] && xdotool key XF86AudioPlay ;;
            stop) [ "$VALUE" -gt 0 ] && xdotool key XF86AudioStop ;;
            prev) [ "$VALUE" -gt 0 ] && xdotool key XF86AudioPrev ;;
            next) [ "$VALUE" -gt 0 ] && xdotool key XF86AudioNext ;;
            
            mute_source:*|mute_sink:*)
                [ "$VALUE" -gt 0 ] && {
                    type=${MAPPING%%:*}
                    target=${MAPPING#*:}
                    [[ "$type" == "mute_source" ]] && pactl set-source-mute "$target" toggle || pactl set-sink-mute "$target" toggle
                    update_mute_led "$CTRL" "$MAPPING"
                }
                ;;
            
            *)
                if [[ "$VALUE" =~ ^[0-9]+$ ]]; then
                    VOL=$(( VALUE * 100 / 127 ))
                    
                    if [[ "$MAPPING" == source:* ]]; then
                        target=${MAPPING#source:}
                        pactl set-source-volume "$target" "${VOL}%"
                        pactl set-source-mute "$target" 0
                        qdbus6 org.kde.plasmashell /org/kde/osdService org.kde.osdService.microphoneVolumeChanged "$VOL"
                    elif [[ "$MAPPING" == app:* ]]; then
                        search=${MAPPING#app:}
                        pids=$(pactl list sink-inputs | awk -v app="$search" 'BEGIN {IGNORECASE=1} /^Sink Input/ {id=$3} /application.name/ && $0 ~ app {print id} /media.name/ && $0 ~ app {print id}' | tr -d '#')
                        for pid in $pids; do pactl set-sink-input-volume "$pid" "${VOL}%"; done
                    else
                        pactl set-sink-volume "$MAPPING" "${VOL}%"
                        pactl set-sink-mute "$MAPPING" 0
                        qdbus6 org.kde.plasmashell /org/kde/osdService org.kde.osdService.volumeChanged "$VOL"
                    fi
                fi
                ;;
        esac
    fi
done