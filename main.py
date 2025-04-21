#!/usr/bin/env python3
"""
Projekt 2102: Ecumaster EMU Display
Hauptanwendung für alle Display-Varianten

Diese Anwendung stellt eine Benutzeroberfläche für die Anzeige von Daten
aus der Ecumaster EMU Black über CAN-Bus bereit. Die Benutzeroberfläche
passt sich automatisch an verschiedene Displaygrößen an.
"""

import os
import sys
import time
import threading
import tkinter as tk
from tkinter import ttk
import json
import can
import subprocess

class EcumasterDisplay:
    def __init__(self, root):
        self.root = root
        self.root.title("Ecumaster EMU Display")
        
        # Ermittle die Bildschirmauflösung
        self.screen_width = root.winfo_screenwidth()
        self.screen_height = root.winfo_screenheight()
        
        # Bestimme die Display-Variante
        self.display_variant = self.detect_display_variant()
        
        # Konfiguriere die Benutzeroberfläche basierend auf der Display-Variante
        self.configure_ui()
        
        # Starte den CAN-Bus-Thread
        self.can_data = {
            "RPM": 0,
            "TPS": 0,
            "MAP": 0,
            "IAT": 0,
            "ECT": 0,
            "BATT": 0,
            "GEAR": 0,
            "SPEED": 0,
            "LAMBDA": 0
        }
        self.can_thread = threading.Thread(target=self.can_reader, daemon=True)
        self.can_thread.start()
        
        # Starte den UI-Update-Thread
        self.update_ui()
    
    def detect_display_variant(self):
        """Erkennt die Display-Variante basierend auf der Bildschirmauflösung"""
        if self.screen_width == 320 and self.screen_height == 240:
            return "2.8"
        elif self.screen_width == 480 and self.screen_height == 320:
            return "3.5"
        elif self.screen_width == 800 and self.screen_height == 480:
            if os.path.exists("/dev/input/by-id/*FT5406*"):
                return "7.0"
            else:
                return "5.0"
        else:
            return "unknown"
    
    def configure_ui(self):
        """Konfiguriert die Benutzeroberfläche basierend auf der Display-Variante"""
        # Vollbildmodus aktivieren
        self.root.attributes('-fullscreen', True)
        
        # Schriftgröße und Layout basierend auf der Display-Variante anpassen
        if self.display_variant == "2.8":
            title_font_size = 12
            value_font_size = 18
            label_font_size = 10
            button_font_size = 10
            padding = 2
            rows = 2
            cols = 2
        elif self.display_variant == "3.5":
            title_font_size = 14
            value_font_size = 24
            label_font_size = 12
            button_font_size = 12
            padding = 5
            rows = 3
            cols = 2
        else:  # 5.0 oder 7.0
            title_font_size = 18
            value_font_size = 36
            label_font_size = 14
            button_font_size = 14
            padding = 10
            rows = 3
            cols = 3
        
        # Hauptrahmen erstellen
        self.main_frame = tk.Frame(self.root, bg="black")
        self.main_frame.pack(fill=tk.BOTH, expand=True)
        
        # Titelleiste
        title_frame = tk.Frame(self.main_frame, bg="#333333", height=title_font_size*2)
        title_frame.pack(fill=tk.X, padx=padding, pady=padding)
        
        title_label = tk.Label(title_frame, text="Ecumaster EMU Display", 
                              font=("Arial", title_font_size, "bold"),
                              fg="white", bg="#333333")
        title_label.pack(side=tk.LEFT, padx=padding)
        
        # Anzeigenbereich
        gauges_frame = tk.Frame(self.main_frame, bg="black")
        gauges_frame.pack(fill=tk.BOTH, expand=True, padx=padding, pady=padding)
        
        # Konfiguriere das Raster
        for i in range(cols):
            gauges_frame.columnconfigure(i, weight=1)
        for i in range(rows):
            gauges_frame.rowconfigure(i, weight=1)
        
        # Erstelle die Anzeigen
        self.gauges = {}
        parameters = [
            {"name": "RPM", "unit": "rpm", "min": 0, "max": 8000},
            {"name": "TPS", "unit": "%", "min": 0, "max": 100},
            {"name": "MAP", "unit": "kPa", "min": 0, "max": 250},
            {"name": "IAT", "unit": "°C", "min": 0, "max": 100},
            {"name": "ECT", "unit": "°C", "min": 0, "max": 120},
            {"name": "BATT", "unit": "V", "min": 8, "max": 16},
            {"name": "GEAR", "unit": "", "min": 0, "max": 6},
            {"name": "SPEED", "unit": "km/h", "min": 0, "max": 300},
            {"name": "LAMBDA", "unit": "", "min": 0.7, "max": 1.3}
        ]
        
        # Begrenzen Sie die Anzahl der Parameter basierend auf dem verfügbaren Platz
        max_params = rows * cols
        parameters = parameters[:max_params]
        
        for i, param in enumerate(parameters):
            row = i // cols
            col = i % cols
            
            # Erstelle einen Rahmen für jeden Parameter
            gauge_frame = tk.Frame(gauges_frame, bd=2, relief=tk.RAISED, bg="#222222")
            gauge_frame.grid(row=row, column=col, sticky="nsew", padx=padding, pady=padding)
            
            # Parametername
            name_label = tk.Label(gauge_frame, text=param["name"], 
                                 font=("Arial", label_font_size),
                                 fg="white", bg="#222222")
            name_label.pack(pady=(padding, 0))
            
            # Wertanzeige
            value_label = tk.Label(gauge_frame, text="0", 
                                  font=("Arial", value_font_size, "bold"),
                                  fg="#00FF00", bg="#222222")
            value_label.pack(fill=tk.BOTH, expand=True)
            
            # Einheit
            unit_label = tk.Label(gauge_frame, text=param["unit"], 
                                 font=("Arial", label_font_size),
                                 fg="white", bg="#222222")
            unit_label.pack(pady=(0, padding))
            
            # Speichere die Referenzen
            self.gauges[param["name"]] = {
                "value_label": value_label,
                "min": param["min"],
                "max": param["max"]
            }
        
        # Statusleiste
        status_frame = tk.Frame(self.main_frame, bg="#333333", height=button_font_size*2)
        status_frame.pack(fill=tk.X, padx=padding, pady=padding)
        
        self.status_label = tk.Label(status_frame, text="Verbinde mit CAN-Bus...", 
                                    font=("Arial", button_font_size),
                                    fg="yellow", bg="#333333")
        self.status_label.pack(side=tk.LEFT, padx=padding)
        
        exit_button = tk.Button(status_frame, text="Beenden", 
                               font=("Arial", button_font_size),
                               command=self.root.quit)
        exit_button.pack(side=tk.RIGHT, padx=padding)
    
    def can_reader(self):
        """Liest Daten vom CAN-Bus"""
        try:
            # Versuche, den CAN-Bus zu öffnen
            bus = can.interface.Bus(channel='can0', bustype='socketcan')
            self.status_label.config(text="Verbunden mit CAN-Bus", fg="green")
            
            while True:
                message = bus.recv(1)
                if message is None:
                    continue
                
                # Verarbeite die CAN-Nachrichten basierend auf der ID
                if message.arbitration_id == 0x600:  # RPM und TPS
                    rpm = (message.data[0] << 8) | message.data[1]
                    tps = message.data[2]
                    self.can_data["RPM"] = rpm
                    self.can_data["TPS"] = tps
                
                elif message.arbitration_id == 0x601:  # MAP und Temperaturen
                    map_kpa = (message.data[0] << 8) | message.data[1]
                    iat = message.data[2] - 40  # Offset für Temperatur
                    ect = message.data[3] - 40  # Offset für Temperatur
                    self.can_data["MAP"] = map_kpa / 10.0  # Skalierung
                    self.can_data["IAT"] = iat
                    self.can_data["ECT"] = ect
                
                elif message.arbitration_id == 0x602:  # Batterie, Gang, Geschwindigkeit
                    batt = ((message.data[0] << 8) | message.data[1]) / 100.0
                    gear = message.data[2]
                    speed = (message.data[3] << 8) | message.data[4]
                    self.can_data["BATT"] = batt
                    self.can_data["GEAR"] = gear
                    self.can_data["SPEED"] = speed
                
                elif message.arbitration_id == 0x603:  # Lambda
                    lambda_value = ((message.data[0] << 8) | message.data[1]) / 1000.0
                    self.can_data["LAMBDA"] = lambda_value
        
        except can.CanError as e:
            self.status_label.config(text=f"CAN-Bus-Fehler: {str(e)}", fg="red")
            time.sleep(5)
            # Versuche, den CAN-Bus neu zu starten
            try:
                subprocess.run(["sudo", "ip", "link", "set", "can0", "down"])
                time.sleep(1)
                subprocess.run(["sudo", "ip", "link", "set", "can0", "up", "type", "can", "bitrate", "500000"])
                time.sleep(1)
            except Exception as e:
                self.status_label.config(text=f"CAN-Bus-Neustart fehlgeschlagen: {str(e)}", fg="red")
            
            # Starte den CAN-Reader neu
            time.sleep(5)
            self.can_reader()
    
    def update_ui(self):
        """Aktualisiert die Benutzeroberfläche mit den neuesten CAN-Daten"""
        for param, gauge in self.gauges.items():
            if param in self.can_data:
                value = self.can_data[param]
                
                # Formatiere den Wert
                if param == "RPM":
                    formatted_value = f"{int(value)}"
                elif param == "BATT" or param == "LAMBDA":
                    formatted_value = f"{value:.2f}"
                elif param == "GEAR":
                    if value == 0:
                        formatted_value = "N"
                    else:
                        formatted_value = f"{int(value)}"
                else:
                    formatte
