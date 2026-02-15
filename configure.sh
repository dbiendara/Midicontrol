#!/bin/bash

CONFIG_FILE="./config.txt"
MIDI_NAME="nanoKONTROL2"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

touch "$CONFIG_FILE"

echo -e "${CYAN}-----------------------------------------------------"
echo -e " MIDI Controller Setup Wizard für $MIDI_NAME"
echo -e "-----------------------------------------------------${NC}"

PORT=$(amidi -l | grep "$MIDI_NAME" | awk '{print $2}')
if [ -z "$PORT" ]; then echo -e "${RED}Fehler: $MIDI_NAME nicht gefunden.${NC}"; exit 1; fi
echo "Gerät gefunden auf Port: $PORT"

while true; do
    echo ""
    echo "#####################################################"
    echo " Bitte bewege JETZT den Regler oder drücke den Knopf..."
    echo "#####################################################"

    EVENT=$(aseqdump -p "$MIDI_NAME" | grep -m 1 "controller")
    if [ -z "$EVENT" ]; then continue; fi

    if [[ "$EVENT" =~ controller\ ([0-9]+), ]]; then
        CTRL_ID=${BASH_REMATCH[1]}
    else continue; fi

    echo -e "\n>> ${GREEN}ERKANNT: Controller ID $CTRL_ID${NC} <<"

    # Check Existing
    EXISTING_ENTRY=$(grep "^$CTRL_ID=" "$CONFIG_FILE" | cut -d'=' -f2-)
    if [ -n "$EXISTING_ENTRY" ]; then
        echo -e "${RED}⚠️  ACHTUNG: Bereits belegt mit: ${YELLOW}$EXISTING_ENTRY${NC}"
        while true; do
            read -p "   (ü)berschreiben oder (b)ehalten? " DECISION
            case $DECISION in
                [üÜyY]*) break ;;
                [bBnN]*) continue 2 ;;
                *) echo "   'ü' oder 'b' eingeben." ;;
            esac
        done
    fi

    echo "Was möchtest du steuern?"
    echo "1) Volume: Ausgang / Lautsprecher"
    echo "2) Volume: Eingang / Mikrofon"
    echo "3) Volume: Anwendung (App)"
    echo "4) Media Buttons (Play, Stop...)"
    echo "5) MUTE / TOGGLE (für Buttons)"  # <--- NEU
    echo "6) Abbrechen"
    
    read -p "Auswahl (1-6): " CHOICE
    ENTRY=""

    case "$CHOICE" in
        1) # SINK VOL
            echo -e "${CYAN}--- Verfügbare Ausgänge ---${NC}"
            mapfile -t SINKS < <(pactl list sinks short | cut -f2)
            select SINK in "${SINKS[@]}"; do
                [ -n "$SINK" ] && ENTRY="$SINK" && break
            done
            ;;
        2) # SOURCE VOL
            echo -e "${CYAN}--- Verfügbare Eingänge ---${NC}"
            mapfile -t SOURCES < <(pactl list sources short | cut -f2 | grep -v "\.monitor")
            select SRC in "${SOURCES[@]}"; do
                [ -n "$SRC" ] && ENTRY="source:$SRC" && break
            done
            ;;
        3) # APP VOL
            echo -e "${CYAN}--- Apps ---${NC}"
            mapfile -t APPS < <(pactl list sink-inputs | grep "application.name" | cut -d '"' -f2 | sort -u)
            APPS+=("Custom (Manuell)")
            select APP in "${APPS[@]}"; do
                if [ "$APP" == "Custom (Manuell)" ]; then
                    read -p "Regex: " CUSTOM_APP; ENTRY="app:$CUSTOM_APP"; break
                elif [ -n "$APP" ]; then ENTRY="app:$APP"; break; fi
            done
            ;;
        4) # COMMANDS
            select CMD in "play" "stop" "prev" "next" "defaultsink"; do
                [ -n "$CMD" ] && ENTRY="$CMD" && break
            done
            ;;
        5) # MUTE TOGGLE (NEU)
            echo -e "${CYAN}Was soll gemutet werden?${NC}"
            echo "1) Mikrofon (Source)"
            echo "2) Lautsprecher (Sink)"
            read -p "Auswahl: " MUTE_CHOICE
            
            if [ "$MUTE_CHOICE" == "1" ]; then
                echo -e "${CYAN}--- Wähle das Mikrofon zum Muten ---${NC}"
                mapfile -t SOURCES < <(pactl list sources short | cut -f2 | grep -v "\.monitor")
                select SRC in "${SOURCES[@]}"; do
                    [ -n "$SRC" ] && ENTRY="mute_source:$SRC" && break
                done
            elif [ "$MUTE_CHOICE" == "2" ]; then
                echo -e "${CYAN}--- Wähle den Lautsprecher zum Muten ---${NC}"
                mapfile -t SINKS < <(pactl list sinks short | cut -f2)
                select SINK in "${SINKS[@]}"; do
                    [ -n "$SINK" ] && ENTRY="mute_sink:$SINK" && break
                done
            fi
            ;;
        6) continue ;;
        *) echo "Ungültig."; continue ;;
    esac

    # Speichern
    if [ -n "$ENTRY" ]; then
        sed -i "/^$CTRL_ID=/d" "$CONFIG_FILE"
        echo "$CTRL_ID=$ENTRY" >> "$CONFIG_FILE"
        echo -e "✅ ${GREEN}GESPEICHERT: $CTRL_ID=$ENTRY${NC}"
        sleep 1
    fi

    # ... (nach systemctl restart ...)

        echo ""
        read -p "Drücke [ENTER] um den nächsten Regler zu belegen, oder 'q' zum Beenden: " NEXT_STEP
        if [[ "$NEXT_STEP" == "q" ]]; then
            echo "Bye!"
            exit 0
        fi
    # Hier ist das Ende der Schleife
done