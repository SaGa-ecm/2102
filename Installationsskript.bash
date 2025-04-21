#!/bin/bash

# Installationsskript für Projekt 2102 und seine Varianten
# Dieses Skript erkennt das angeschlossene Display und konfiguriert die Software entsprechend

# Funktion zur Erkennung des Display-Typs
detect_display() {
    # Prüfe, ob ein Waveshare-Display über GPIO angeschlossen ist
    if [ -e /dev/fb1 ]; then
        # Prüfe die Auflösung von fb1
        FB1_SIZE=$(fbset -fb /dev/fb1 | grep geometry | awk '{print $2"x"$3}')
        
        case $FB1_SIZE in
            "320x240")
                echo "2.8"
                ;;
            "480x320")
                echo "3.5"
                ;;
            *)
                # Unbekanntes GPIO-Display
                echo "unknown-gpio"
                ;;
        esac
        return
    fi
    
    # Prüfe die HDMI-Auflösung für andere Displays
    RESOLUTION=$(tvservice -s | grep -oP '\d+x\d+')
    
    case $RESOLUTION in
        "800x480")
            # Könnte entweder 5-Zoll oder 7-Zoll sein
            # Weitere Prüfung erforderlich
            if [ -e /dev/input/by-id/*FT5406* ]; then
                echo "7.0"  # Offizielles 7-Zoll-Display mit FT5406 Touchscreen
            else
                echo "5.0"  # Wahrscheinlich ein 5-Zoll-HDMI-Display
            fi
            ;;
        "320x240")
            echo "2.8"
            ;;
        "480x320")
            echo "3.5"
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

# Funktion zur Konfiguration des Displays
configure_display() {
    DISPLAY_SIZE=$1
    
    echo "Konfiguriere für Display-Größe: $DISPLAY_SIZE Zoll"
    
    # Backup der config.txt erstellen
    cp /boot/config.txt /boot/config.txt.backup
    
    # Entferne vorhandene Display-Konfigurationen
    sed -i '/^dtoverlay=waveshare/d' /boot/config.txt
    sed -i '/^hdmi_cvt=/d' /boot/config.txt
    
    # Füge die entsprechende Konfiguration hinzu
    case $DISPLAY_SIZE in
        "2.8")
            echo "dtoverlay=waveshare28a" >> /boot/config.txt
            echo "hdmi_cvt=320 240 60 6 0 0 0" >> /boot/config.txt
            ;;
        "3.5")
            echo "dtoverlay=waveshare35a" >> /boot/config.txt
            echo "hdmi_cvt=480 320 60 6 0 0 0" >> /boot/config.txt
            ;;
        "5.0"|"7.0")
            echo "hdmi_cvt=800 480 60 6 0 0 0" >> /boot/config.txt
            ;;
    esac
    
    # Stelle sicher, dass die HDMI-Grundeinstellungen vorhanden sind
    if ! grep -q "hdmi_force_hotplug=1" /boot/config.txt; then
        echo "hdmi_force_hotplug=1" >> /boot/config.txt
    fi
    
    if ! grep -q "hdmi_group=2" /boot/config.txt; then
        echo "hdmi_group=2" >> /boot/config.txt
    fi
    
    if ! grep -q "hdmi_mode=87" /boot/config.txt; then
        echo "hdmi_mode=87" >> /boot/config.txt
    fi
    
    # Konfiguriere den Touchscreen
    configure_touchscreen $DISPLAY_SIZE
    
    # Installiere die benötigten Pakete
    apt-get update
    apt-get install -y python3-tk python3-pip xinput-calibrator xscreensaver
    
    # Installiere die Python-Bibliotheken für CAN-Bus
    pip3 install python-can RPi.GPIO
    
    # Kopiere die Anwendungsdateien
    mkdir -p /opt/ecumaster-display
    cp -r ./src/* /opt/ecumaster-display/
    
    # Erstelle einen Autostart-Eintrag
    mkdir -p /home/pi/.config/autostart
    cat > /home/pi/.config/autostart/ecumaster-display.desktop << EOF
[Desktop Entry]
Type=Application
Name=Ecumaster Display
Exec=python3 /opt/ecumaster-display/main.py
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
EOF
    
    # Setze Berechtigungen
    chmod +x /opt/ecumaster-display/main.py
    chown -R pi:pi /home/pi/.config/autostart
    chown -R pi:pi /opt/ecumaster-display
    
    echo "Installation abgeschlossen. Bitte starten Sie das System neu."
}

# Funktion zur Konfiguration des Touchscreens
configure_touchscreen() {
    DISPLAY_SIZE=$1
    
    case $DISPLAY_SIZE in
        "2.8"|"3.5")
            # Resistiver Touchscreen über GPIO
            mkdir -p /etc/X11/xorg.conf.d/
            cat > /etc/X11/xorg.conf.d/99-calibration.conf << EOF
Section "InputClass"
    Identifier "calibration"
    MatchProduct "ADS7846 Touchscreen"
    Option "Calibration" "3932 300 294 3801"
    Option "SwapAxes" "1"
EndSection
EOF
            echo "Touchscreen-Konfiguration für $DISPLAY_SIZE-Zoll-Display erstellt."
            echo "Führen Sie 'sudo DISPLAY=:0 xinput_calibrator' aus, um den Touchscreen zu kalibrieren."
            ;;
        "5.0")
            # Resistiver Touchscreen über HDMI
            mkdir -p /etc/X11/xorg.conf.d/
            cat > /etc/X11/xorg.conf.d/99-calibration.conf << EOF
Section "InputClass"
    Identifier "calibration"
    MatchProduct "generic ft5x06"
    Option "Calibration" "0 800 0 480"
    Option "SwapAxes" "0"
EndSection
EOF
            echo "Touchscreen-Konfiguration für 5-Zoll-Display erstellt."
            echo "Führen Sie 'sudo DISPLAY=:0 xinput_calibrator' aus, um den Touchscreen zu kalibrieren."
            ;;
        "7.0")
            # Kapazitiver Touchscreen (offizielles RPi-Display)
            mkdir -p /etc/X11/xorg.conf.d/
            cat > /etc/X11/xorg.conf.d/40-libinput.conf << EOF
Section "InputClass"
    Identifier "libinput touchscreen catchall"
    MatchIsTouchscreen "on"
    MatchDevicePath "/dev/input/event*"
    Driver "libinput"
    Option "CalibrationMatrix" "1 0 0 0 1 0 0 0 1"
EndSection
EOF
            echo "Touchscreen-Konfiguration für 7-Zoll-Display erstellt."
            ;;
    esac
}

# Funktion zur Konfiguration des Strommanagements
configure_power_management() {
    DISPLAY_SIZE=$1
    
    # Erstelle das Strommanagement-Skript
    cat > /opt/ecumaster-display/power_management.py << EOF
#!/usr/bin/env python3
import os
import time
import datetime
import subprocess
from datetime import datetime

# Display-Größe: $DISPLAY_SIZE Zoll

# Funktion zum Ein-/Ausschalten des Displays
def set_display_power(state):
    if state:
        os.system('/usr/bin/tvservice -p')
        os.system('/bin/fbset -depth 8')
        os.system('/bin/fbset -depth 16')
        os.system('/usr/bin/xrefresh')
    else:
        os.system('/usr/bin/tvservice -o')

# Funktion zur Helligkeitssteuerung für GPIO-Displays
def set_brightness_gpio(brightness_percent):
    # Nur für GPIO-Displays (2.8 und 3.5 Zoll)
    if "$DISPLAY_SIZE" in ["2.8", "3.5"]:
        import RPi.GPIO as GPIO
        
        # GPIO-Pin für die Helligkeitssteuerung
        BACKLIGHT_PIN = 18
        
        # GPIO einrichten, falls noch nicht geschehen
        if not hasattr(set_brightness_gpio, "initialized"):
            GPIO.setmode(GPIO.BCM)
            GPIO.setup(BACKLIGHT_PIN, GPIO.OUT)
            set_brightness_gpio.pwm = GPIO.PWM(BACKLIGHT_PIN, 100)
            set_brightness_gpio.pwm.start(100)
            set_brightness_gpio.initialized = True
        
        # Helligkeit anpassen
        set_brightness_gpio.pwm.ChangeDutyCycle(brightness_percent)

# Automatische Helligkeitsanpassung basierend auf Tageszeit
def auto_brightness():
    hour = datetime.now().hour
    
    # Nachts gedimmte Helligkeit
    if hour >= 22 or hour < 6:
        return 30
    # Morgens und abends mittlere Helligkeit
    elif (hour >= 6 and hour < 9) or (hour >= 18 and hour < 22):
        return 70
    # Tagsüber volle Helligkeit
    else:
        return 100

# Hauptschleife
try:
    while True:
        # Helligkeit anpassen
        brightness = auto_brightness()
        set_brightness_gpio(brightness)
        
        # Alle 60 Sekunden prüfen
        time.sleep(60)
except KeyboardInterrupt:
    # Aufräumen beim Beenden
    if "$DISPLAY_SIZE" in ["2.8", "3.5"] and hasattr(set_brightness_gpio, "initialized"):
        import RPi.GPIO as GPIO
        set_brightness_gpio.pwm.stop()
        GPIO.cleanup()
EOF
    
    # Mache das Skript ausführbar
    chmod +x /opt/ecumaster-display/power_management.py
    
    # Erstelle einen Systemd-Service
    cat > /etc/systemd/system/display-power.service << EOF
[Unit]
Description=Display Power Management for Ecumaster EMU Display
After=multi-user.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 /opt/ecumaster-display/power_management.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    
    # Aktiviere und starte den Service
    systemctl enable display-power.service
    systemctl start display-power.service
    
    echo "Strommanagement für $DISPLAY_SIZE-Zoll-Display konfiguriert."
}

# Funktion zur Konfiguration der CAN-Bus-Schnittstelle
configure_can_interface() {
    # Prüfe, ob der CAN-Bus bereits konfiguriert ist
    if ! grep -q "dtoverlay=mcp2515" /boot/config.txt; then
        echo "dtoverlay=mcp2515-can0,oscillator=16000000,interrupt=25" >> /boot/config.txt
        echo "dtoverlay=spi-bcm2835-overlay" >> /boot/config.txt
    fi
    
    # Erstelle die CAN-Konfigurationsdatei
    cat > /etc/network/interfaces.d/can0 << EOF
auto can0
iface can0 inet manual
    pre-up /sbin/ip link set can0 type can bitrate 500000
    up /sbin/ifconfig can0 up
    down /sbin/ifconfig can0 down
EOF
    
    echo "CAN-Bus-Schnittstelle konfiguriert."
}

# Hauptprogramm
echo "Ecumaster EMU Display - Projekt 2102 Installationsskript"
echo "------------------------------------------------------"

# Erkenne das Display
DISPLAY_SIZE=$(detect_display)

if [ "$DISPLAY_SIZE" == "unknown" ] || [ "$DISPLAY_SIZE" == "unknown-gpio" ]; then
    echo "Kein bekanntes Display erkannt."
    echo "Bitte geben Sie die Display-Größe manuell ein (2.8, 3.5, 5.0 oder 7.0):"
    read DISPLAY_SIZE
fi

# Konfiguriere das System für das erkannte Display
configure_display $DISPLAY_SIZE

# Konfiguriere das Strommanagement
configure_power_management $DISPLAY_SIZE

# Konfiguriere die CAN-Bus-Schnittstelle
configure_can_interface

# Frage nach Neustart
echo "Möchten Sie das System jetzt neu starten? (j/n)"
read RESTART

if [ "$RESTART" == "j" ] || [ "$RESTART" == "J" ]; then
    reboot
fi
