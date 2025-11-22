# Midicontrol

**Konfigurierbare PulseAudio-Sink-Steuerung mit Korg NanoKontrol2**

## Übersicht

Midicontrol ermöglicht es, mit einem Korg NanoKontrol2 MIDI-Controller verschiedene PulseAudio-Sinks (z.B. Lautsprecher, Kopfhörer, virtuelle Geräte) direkt und individuell über die Fader und Buttons zu steuern. Ziel ist eine flexible Integration des Controllers, vor allem für Streaming, Home-Studios und das produktive Arbeiten mit mehreren Audioquellen.

## Features

- Steuerung beliebiger PulseAudio-Sinks mittels Fader, Knöpfen etc.
- Flexible Konfiguration per Textdatei
- Schnelle Integration in bestehende Systeme


## Voraussetzungen

- Linux mit PulseAudio
- bash (Shell)
- Korg NanoKontrol2 (oder kompatibler MIDI-Controller)
- `pactl` im Systempfad
- Optional: `aconnect`/`amidi`/`mididings` je nach Routingbedarf


## Installation

Kopiere das Skript (`midicontrol.sh`) und die Konfigurationsdatei (`midicontrol.conf`) in ein geeignetes Verzeichnis, z.B. `~/.local/bin/` bzw. `~/.config/midicontrol/`.

Mache das Skript ausführbar:

```sh
chmod +x ~/.local/bin/midicontrol.sh
```


## Konfiguration

Die Datei `midicontrol.conf` enthält die Zuweisung der MIDI-Controller-Elemente zu PulseAudio-Sinks. Die genaue Syntax ist im Kopf der Datei erläutert. Beispiel:

```ini
# midicontrol.conf
# Format: <MIDI-CC-Nummer>=<Sink-Name>
7=alsa_output.pci-0000_00_1b.0.analog-stereo
8=alsa_output.usb-Generic_USB_Audio-00.analog-stereo
...
```

**Wichtige Hinweise:**

- Die Control Change (CC)-Nummern findest du im MIDI-Datenblatt deines Controllers oder mit einem MIDI-Monitor heraus.
- Der `Sink-Name` muss exakt mit dem PulseAudio-Sink übereinstimmen (siehe nächster Abschnitt).


## PulseAudio Sink-Namen herausfinden

Führe folgendes Kommando im Terminal aus, um alle verfügbaren Sinks aufzulisten:

```sh
pactl list sinks short
```

Oder:

```sh
pacmd list-sinks | grep -e 'name:' -e 'index:'
```

Beispielausgabe:

```
0	alsa_output.pci-0000_00_1b.0.analog-stereo
1	alsa_output.usb-Generic_USB_Audio-00.analog-stereo
```

Den Namen aus der zweiten Spalte (z. B. `alsa_output.pci-0000_00_1b.0.analog-stereo`) verwendest du in der `midicontrol.conf`.[^1][^2][^3]

## Autostart mit systemd (user service)

Lege eine Dienstdatei an, z.B. `~/.config/systemd/user/midicontrol.service`:

```ini
Unit]
Description=MIDI PulseAudio Volume Control
After=sound.target

[Service]
ExecStartPre=/bin/sleep 10
ExecStart=/home/[USER]/scripts/midicontrol/midicontrol.sh
Restart=always
WorkingDirectory=/home/[USER]/scripts/midicontrol

[Install]
WantedBy=default.target

```

Aktiviere und starte den Dienst:

```sh
systemctl --user enable midicontrol.service
systemctl --user start midicontrol.service
```

Der Dienst startet dann automatisch nach dem Login.[^4]

**Tipp:** Überprüfe den Status falls etwas nicht funktioniert:

```sh
systemctl --user status midicontrol.service
journalctl --user -u midicontrol.service
```


## Anpassung/MIDI-Zuordnung

Viele Controller erlauben das Customizing der CCs über einen Editor wie den Korg Kontrol Editor. Stelle sicher, dass dein Mapping den Einträgen in der Konfigurationsdatei entspricht.[^5][^6]

## Fehlerbehebung

- Prüfe mit `aconnect -l` oder `amidi -l`, ob das Gerät erkannt wird.
- Prüfe, dass dein Benutzer PulseAudio steuern darf (idR. gegeben bei normalen Desktopnutzern).
- Prüfe die systemd-Logs auf Fehlerausgaben, falls der Autostartdienst nicht arbeitet.

***
