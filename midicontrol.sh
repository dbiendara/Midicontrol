#!/bin/bash

CONFIG_FILE="./config.txt"
# Automatische Erkennung des nanoKONTROL2 Ports
MIDI_OUT_PORT=$(amidi -l | grep "nanoKONTROL2" | awk '{print $2}')

# Liest Mapping aus config.txt
get_mapping() {
    local ctrl=$1
    grep -E "^$ctrl=" "$CONFIG_FILE" | cut -d= -f2
}

# LEDs initialisieren (aus config.txt)
init_leds() {
    LEDS_LINE=$(grep "^leds=" "$CONFIG_FILE")
    if [ ! -z "$LEDS_LINE" ]; then
        LEDBTNSTR=${LEDS_LINE#leds=}
        IFS=',' read -ra LEDBTNS <<< "$LEDBTNSTR"
        for btn in "${LEDBTNS[@]}"; do
            printf -v HEX "%02X" "$btn"
            amidi -p "$MIDI_OUT_PORT" -S "B0 $HEX 7F"
        done
    fi
}

# Default-Sink Switcher Logik
DEFAULT_SINK_INDEX=0
switch_sink() {
  SINKS=($(pactl list sinks short | cut -f2))
  DEFAULT_SINK_INDEX=$(( (DEFAULT_SINK_INDEX + 1) % ${#SINKS[@]} ))
  pactl set-default-sink "${SINKS[$DEFAULT_SINK_INDEX]}"
  echo "Default Sink: ${SINKS[$DEFAULT_SINK_INDEX]}"
}

# Start: LEDs an
init_leds

# MIDI-Events überwachen
aseqdump -p "nanoKONTROL2" | while read LINE; do
    if [[ "$LINE" =~ controller\ ([0-9]+),\ value\ ([0-9]+) ]]; then
        CTRL=${BASH_REMATCH[1]}
        VALUE=${BASH_REMATCH[2]}
        MAPPING=$(get_mapping $CTRL)

        # 1. Buttons / Aktionen
        case "$MAPPING" in
            play) [ "$VALUE" -gt 0 ] && xdotool key XF86AudioPlay ;;
            stop) [ "$VALUE" -gt 0 ] && xdotool key XF86AudioStop ;;
            prev) [ "$VALUE" -gt 0 ] && xdotool key XF86AudioPrev ;;
            next) [ "$VALUE" -gt 0 ] && xdotool key XF86AudioNext ;;
            defaultsink) [ "$VALUE" -gt 0 ] && switch_sink ;;
            
            # 2. Slider / Drehregler
            *)
                if [ ! -z "$MAPPING" ] && [[ "$VALUE" =~ ^[0-9]+$ ]]; then
                    # Skaliere 0-127 auf 0-100%
                    VOL=$(echo "$VALUE * 100 / 127" | bc)
                    
                    # A) MIKROFON (Source)
                    if [[ "$MAPPING" == source:* ]]; then
                        REAL_SOURCE=${MAPPING#source:}
                        pactl set-source-volume "$REAL_SOURCE" "${VOL}%"
                        # echo "Mic: $REAL_SOURCE -> $VOL%"

                    # B) APP-GRUPPEN (Sink Inputs via Regex)
                    elif [[ "$MAPPING" == app:* ]]; then
                        APP_SEARCH=${MAPPING#app:}
                        # Suche IDs via Regex (Case-Insensitive), entferne Duplikate
                        PIDS=$(pactl list sink-inputs | awk -v app="$APP_SEARCH" '
                            BEGIN {IGNORECASE=1} 
                            /^Sink Input/ {id=$3} 
                            /application.name/ && $0 ~ app {print id}
                            /media.name/ && $0 ~ app {print id}
                        ' | tr -d '#' | sort -u)

                        if [ ! -z "$PIDS" ]; then
                            for PID in $PIDS; do
                                pactl set-sink-input-volume "$PID" "${VOL}%"
                            done
                            # echo "App ($APP_SEARCH) -> $VOL%"
                        fi

                    # C) LAUTSPRECHER (Sink Direct)
                    else
                        pactl set-sink-volume "$MAPPING" "${VOL}%"
                        # echo "Sink: $MAPPING -> $VOL%"
                    fi
                fi
                ;;
        esac
    fi
done