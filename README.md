# VideoNewsWire

Ein ruhiger YouTube-Client für macOS – aufgebaut wie [NetNewsWire](https://netnewswire.com): **Abos links, Videos in der Mitte, Video rechts.** Keine Startseite, keine Empfehlungen, keine Kommentare, keine Shorts, kein Autoplay. Einfach den Kanälen folgen, die man ausgewählt hat.

## Funktionen

| Bereich | Umsetzung |
|---|---|
| **Seitenleiste** | Übersicht (Neu · Heute · Merkliste · Downloads), **Ordner** (z. B. Food, Tech) und alle abonnierten Kanäle mit ihrem **Kanalbild** |
| **Ordner** | ⇧⌘N oder Rechtsklick → „Neuer Ordner…“; Kanäle per Drag & Drop oder Kontextmenü einsortieren; Klick auf den Ordner zeigt alle Videos seiner Kanäle |
| **Videoliste** | Neueste Videos pro Kanal aus den öffentlichen YouTube-RSS-Feeds, „Alle als gesehen markieren“ |
| **Suche** | Durchsucht Titel, Kanalname, **Videobeschreibung** und vorhandene KI-Zusammenfassungen; mehrere Wörter müssen alle vorkommen |
| **Player** | Eingebettet über `youtube-nocookie.com`; Endscreens, Info-Karten, Pause-Empfehlungen, YouTube-Logo-Link usw. per CSS ausgeblendet; Navigation aus dem Player heraus blockiert |
| **KI-Zusammenfassung** | Auf Knopfdruck, **on-device mit Apple Foundation Models** (Apple Intelligence). Grundlage: Untertitel/Transkript via yt-dlp, ersatzweise die Videobeschreibung. Lange Videos werden abschnittsweise verdichtet (Map-Reduce), weil das lokale Modell nur ca. 4 096 Tokens Kontext hat |
| **Download** | Über yt-dlp; die App installiert und **aktualisiert yt-dlp selbst** (alle 3 Tage beim Start oder manuell). Heruntergeladene Videos werden lokal mit AVKit abgespielt |
| **Abos importieren** | Manuell (URL, @Handle, Kanal-ID), aus dem YouTube-Konto (yt-dlp liest die Abos über die Browser-Cookies) oder per Google-Takeout-`subscriptions.csv` |

### Anti-Ablenkungs-Entscheidungen

- **Keine Thumbnails** standardmäßig (in den Einstellungen zuschaltbar) – man wählt nach Titel, nicht nach Clickbait-Bild.
- **Keine Zähler** für Ungesehenes standardmäßig – keine roten Zahlen, die zum Abarbeiten drängen.
- **Shorts ausgeblendet** (zuschaltbar).
- **Kein Autoplay**, keine „nächstes Video“-Funktion, keine Kommentare, keine Empfehlungen.
- Neue Kanäle fluten „Neu“ nicht: Videos älter als 7 Tage gelten beim ersten Abruf als gesehen.
- Leere „Neu“-Liste sagt: *„Keine neuen Videos. Zeit für etwas anderes.“*
- Kein Login bei Google nötig; der Player läuft in einem nicht-persistenten Web-Datenspeicher.

## Voraussetzungen

- **macOS 26 (Tahoe)** auf **Apple Silicon** (Foundation Models)
- Apple Intelligence aktiviert (nur für die Zusammenfassungen)
- Xcode 26 bzw. Swift 6.2 zum Bauen
- Optional: `brew install ffmpeg deno`
  - **ffmpeg**: Downloads über 720p (Video- und Tonspur werden zusammengeführt)
  - **deno**: von yt-dlp inzwischen empfohlene JavaScript-Laufzeit, damit alle YouTube-Formate verfügbar sind

## Bauen & Starten

```bash
git clone https://github.com/zulu101/VideoNewsWire.git
cd VideoNewsWire

# Direkt starten (Entwicklung)
swift run

# Oder als .app bauen → build/VideoNewsWire.app
./Scripts/build-app.sh
```

Alternativ `Package.swift` in Xcode öffnen und ausführen.

Jeder Push baut die App außerdem per GitHub Actions (`macos-26`-Runner); das fertige `VideoNewsWire.zip` liegt unter *Actions → Build → Artifacts*. Da die App nur ad-hoc signiert ist, nach dem Entpacken einmalig:

```bash
xattr -dr com.apple.quarantine VideoNewsWire.app
```

## App-Icon

Quelle ist `Resources/AppIcon.svg` (entworfen in Claude Design, Konzept „Zeitung & Play“). Nach Änderungen am SVG neu erzeugen:

```bash
node Scripts/make-icon.mjs   # schreibt Resources/AppIcon.icns und PNGs nach Resources/AppIcon.iconset/
```

Das Skript braucht Playwright mit Chromium (`npm i -g playwright && npx playwright install chromium`).

## Erste Schritte

1. **Einstellungen → Downloads → „yt-dlp installieren“** (für Downloads, Transkripte und den Konto-Import).
2. **⌘N** → Kanal hinzufügen oder Abos aus dem YouTube-Konto übernehmen.
   - Für den Konto-Import über **Safari** braucht die App *Festplattenvollzugriff* (Systemeinstellungen → Datenschutz & Sicherheit), weil yt-dlp die Safari-Cookies lesen muss. Chrome/Firefox/Brave funktionieren ohne.
3. **⌘R** aktualisiert alle Kanäle.

## Aufbau des Codes

```
Sources/VideoNewsWire/
├── VideoNewsWireApp.swift      App, Menübefehle, Einstellungsfenster
├── Model/
│   ├── Models.swift            Channel, Video, VideoState, Einstellungs-Schlüssel
│   └── AppStore.swift          Datenhaltung (JSON in ~/Library/Application Support/VideoNewsWire)
├── Services/
│   ├── FeedService.swift       YouTube-RSS laden & parsen
│   ├── ChannelResolver.swift   @Handle/URL → Kanal-ID
│   ├── AvatarService.swift     Kanalbilder laden & lokal speichern
│   ├── YTDLPManager.swift      yt-dlp installieren/aktualisieren, Download, Untertitel, Konto-Abos
│   ├── ProcessRunner.swift     externe Prozesse asynchron ausführen
│   └── Summarizer.swift        Zusammenfassung mit FoundationModels (Map-Reduce)
└── Views/                      SwiftUI: Seitenleiste, Liste, Detail, Player, Sheets, Einstellungen
```

## Bekannte Grenzen

- Die YouTube-RSS-Feeds enthalten nur die **letzten 15 Videos** pro Kanal und keine Videolänge.
- YouTube-Feeds sind gelegentlich kurzzeitig nicht erreichbar; betroffene Kanäle zeigen ein ⚠️ in der Seitenleiste.
- Das Ausblenden von Player-Elementen hängt von YouTubes CSS-Klassen ab und kann nach Änderungen bei YouTube Nachbesserung brauchen.
- Viele Untertitel-Abrufe in kurzer Zeit können von YouTube gedrosselt werden (HTTP 429).
- Kanalbilder werden von der Kanalseite gelesen (`og:image`), lokal gespeichert und alle 30 Tage erneuert.
- Zusammenfassungen sind auf Deutsch; die Qualität des lokalen Modells ist gut für Überblicke, aber nicht fehlerfrei.
