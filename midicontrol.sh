#!/bin/bash

CONFIG_FILE="./config.txt"
# MIDI_OUT_PORT="hw:0,0,0"   # Stelle das ggf. auf dein Gerät/Port ein
# Port Autoerkennung
MIDI_OUT_PORT=$(amidi -l | grep "nanoKONTROL2" | awk '{print $2}')



# Liest Mapping aus config.txt je Controller
get_mapping() {
    local ctrl=$1
    grep -E "^$ctrl=" "$CONFIG_FILE" | cut -d= -f2
}

# LEDs bei Dienststart initialisieren
init_leds() {
    LEDS_LINE=$(grep "^leds=" "$CONFIG_FILE")
    if [ ! -z "$LEDS_LINE" ]; then
        LEDBTNSTR=${LEDS_LINE#leds=}
        IFS=',' read -ra LEDBTNS <<< "$LEDBTNSTR"
        for btn in "${LEDBTNS[@]}"; do
            led_on "$btn"
        done
    fi
}

# LED-Steuerung via amidi
led_on() {
    local ctrl=$1
    printf -v HEX "%02X" "$ctrl"
    amidi -p "$MIDI_OUT_PORT" -S "B0 $HEX 7F"
}

led_off() {
    local ctrl=$1
    printf -v HEX "%02X" "$ctrl"
    amidi -p "$MIDI_OUT_PORT" -S "B0 $HEX 00"
}

# Default-Sinks-Liste anhand aktueller Sinks
SINKS=($(pactl list sinks short | cut -f2))
DEFAULT_SINK_INDEX=0

switch_sink() {
  # Aktuelle Sinks neu abrufen, um Änderungen zu berücksichtigen
  SINKS=($(pactl list sinks short | cut -f2))
  DEFAULT_SINK_INDEX=$(( (DEFAULT_SINK_INDEX + 1) % ${#SINKS[@]} ))
  pactl set-default-sink "${SINKS[$DEFAULT_SINK_INDEX]}"
  echo "Default sink switched to: ${SINKS[$DEFAULT_SINK_INDEX]}"
}


# Initialisierung: LEDs an
init_leds

# MIDI-Events abarbeiten
aseqdump -p "nanoKONTROL2" | while read LINE; do
    if [[ "$LINE" =~ controller\ ([0-9]+),\ value\ ([0-9]+) ]]; then
        CTRL=${BASH_REMATCH[1]}
        VALUE=${BASH_REMATCH[2]}
        MAPPING=$(get_mapping $CTRL)

        # Media-Buttons / andere Features über Namen
        case "$MAPPING" in
            play)
                if [ "$VALUE" -gt 0 ]; then
                    xdotool key XF86AudioPlay
                    echo "Play"
                fi
                ;;
            stop)
                if [ "$VALUE" -gt 0 ]; then
                    xdotool key XF86AudioStop
                    echo "Stop"
                fi
                ;;
            prev)
                if [ "$VALUE" -gt 0 ]; then
                    xdotool key XF86AudioPrev
                    echo "Previous"
                fi
                ;;
            next)
                if [ "$VALUE" -gt 0 ]; then
                    xdotool key XF86AudioNext
                    echo "Next"
                fi
                ;;
            defaultsink)
                if [ "$VALUE" -gt 0 ]; then
                    switch_sink
                fi
                ;;
            *)
                # Wenn Mapping existiert und KEIN Aktionswort ist, dann PulseAudio Sink-Name!
                if [ ! -z "$MAPPING" ] && [[ "$VALUE" =~ ^[0-9]+$ ]]; then
                    VOL=$(echo "$VALUE * 100 / 127" | bc)
                    pactl set-sink-volume "$MAPPING" "${VOL}%"
                    echo "Controller $CTRL, Wert $VALUE => Setze Sink $MAPPING Lautstärke auf $VOL%"
                fi
                ;;
        esac
    fi
done
