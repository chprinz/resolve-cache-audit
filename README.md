# DaVinci Resolve — Cache Audit

Ein Tool für macOS, das zeigt, welches Projekt wie viel Cache auf welchem
Laufwerk belegt — Render-Cache, Optimized Media und Audio-Cache zusammen,
inklusive Cache von Projekten, die es in deiner Bibliothek gar nicht mehr
gibt.

Resolves Cache (`CacheClip`) speichert jeden gecachten Clip in einem Ordner,
der nach einer kryptischen UUID benannt ist, z. B.
`eee02c2c-325d-460f-9aeb-0e28aac8b45f`. Wer mehrere Disk-Datenbanken über
interne und externe Laufwerke verteilt hat, sammelt schnell Dutzende
anonyme UUID-Ordner an.

## Im Vergleich zu Resolves eigenem Cache-Manager

Resolve ist hier nicht komplett blind — seit Version **18.5** zeigt
`Playback → Delete Render Cache → Manage Cache Data` eine projekt- und
bibliotheksübergreifende Übersicht über den **Render-Cache**: Projektname,
Speicherort und Größe, sortierbar, über alle Bibliotheken hinweg, die
Resolve findet. Für Render-Cache allein löst das native Tool schon einen
Großteil des "wem gehört dieser UUID-Ordner"-Problems.

Was es nicht kann:

- **Optimized Media und Audio-Cache** lassen sich zwar in Resolve löschen
  (`Playback → Delete Optimized Media` oder von Hand), aber — anders als
  beim Render-Cache — zeigt Resolve dabei nicht, welchem Projekt oder
  welchen Dateien das gehört. Dieses Tool ordnet alle drei Cache-Arten
  (Render, Optimized Media, Audio) auf die gleiche Weise Projekten zu.
- **Verwaister Cache** — ein UUID-Ordner eines Projekts, das längst aus der
  Bibliothek gelöscht wurde — taucht in Resolves Cache-Manager gar nicht
  mehr auf, weil es keinen Projekteintrag mehr gibt, dem er zugeordnet
  werden könnte. Dieses Tool findet ihn trotzdem über die `Info.txt`, die
  Resolve selbst neben die Cache-Dateien schreibt (siehe unten), und
  markiert ihn als "vermutlich gelöscht".
- Resolves eigener Cache-Manager löscht sofort, **ohne Warnung oder Undo**.
  Die native App-Version dieses Tools (weiter unten) verschiebt Cache
  stattdessen in den Papierkorb — wiederherstellbar, falls man sich
  vertan hat.
- Dieses Tool funktioniert auch, ohne Resolve überhaupt zu öffnen —
  praktisch für einen schnellen "wie viel Platz belegt das eigentlich
  wirklich"-Check.

## Wie Cache zu Projekten zugeordnet wird

Keine SQL-Tabelle nötig. Jeder UUID-Ordner direkt unter einem
`CacheClip`-Verzeichnis enthält eine simple Textdatei `Info.txt`:

```
Database Name: X9Pro
User Name: guest
Project Name: My Project Name
```

Das war's schon — Resolve schreibt seine eigene UUID-zu-Projekt-Zuordnung
direkt neben die Cache-Dateien. Kein SQLite-Parsing, keine
BLOB-Spalten-Kopfschmerzen. Dieses Tool liest einfach diese Dateien.

## Was das Skript macht

1. Durchsucht dein Home-Verzeichnis und jedes eingebundene Laufwerk nach
   Resolve-Disk-Datenbanken (`Resolve Projects`) und Render-Cache-Ordnern
   (`CacheClip`) — automatisch, ohne fest codierte Pfade oder
   Laufwerksnamen.
2. Liest aus jedem UUID-Ordner die `Info.txt`, um Projekt- und
   Datenbankname zu ermitteln.
3. Misst den tatsächlichen Speicherverbrauch pro Projekt-Cache.
4. Stellt fest, ob der Cache auf einem internen oder externen Laufwerk
   liegt (über `diskutil`, nicht per Pfad-Raterei).
5. Gibt eine sortierte Tabelle aus: Projekt → Laufwerk → Größe → Pfad,
   größte zuerst.
6. Zusätzlich: der *konfigurierte* Cache-Pfad jedes Projekts (aus
   `SM_UserSetup.CachePath` in `Project.db`) — so erkennst du Projekte,
   die auf ein nicht mehr angeschlossenes Laufwerk zeigen.

Verschachtelte/doppelte `CacheClip`-Ordner (ein häufiger Fehler bei
manueller Einrichtung) werden automatisch erkannt und übersprungen: Ein
`CacheClip`-Ordner zählt nur, wenn er direkt UUID-Ordner oder die
gemeinsamen `audio`/`OptimizedMedia`-Ordner enthält — ein Ordner, der nur
einen weiteren `CacheClip`-Ordner enthält, gilt als Wrapper und wird
ignoriert.

## Beispielausgabe

```
Part 1 — Cache usage per project, sorted by size

  Project                                     Drive      Size  Path
  ──────────────────────────────────────────  ────────  ────────  ────
  Feature Film Rough Cut                       external  48.4 GB  /Volumes/Drive2/DaVinci/CacheClip/CacheClip/eee02c2c-...
  Optimized Media (not render cache)           internal  22.3 GB  /Users/you/Movies/Da Vinci Resolve/CacheClip/OptimizedMedia
  Audio cache (all projects)                   external   5.0 GB  /Volumes/Drive2/DaVinci/CacheClip/CacheClip/audio
  Corporate Video Edit                         external   1.2 GB  /Volumes/Drive2/DaVinci/CacheClip/CacheClip/d47c9bdd-...
  ...

  Total internal: 23.7 GB
  Total external: 56.0 GB
```

## Voraussetzungen

- macOS (nutzt `diskutil`, `sqlite3` — beides vorinstalliert, keine
  Installation nötig)
- DaVinci Resolve mit einer **Disk-Database**-Projektbibliothek. Bei
  Resolves Standard-Cloud/Postgres-Bibliothek gibt es keinen
  `Resolve Projects`-Ordner zu finden, und Teil 2 bleibt leer — Teil 1
  (der CacheClip-Scan) funktioniert trotzdem, da die
  Cache-Ordnerstruktur gleich ist.

## Native App

`CacheAudit/` enthält eine native macOS-App (SwiftUI), die denselben Scan
in einem Fenster statt im Terminal macht, plus eine Fähigkeit, die das
Skript nicht hat: Cache-Einträge auswählen und in den Papierkorb
verschieben (nie unwiderruflich löschen) — direkt im Dashboard. Sie zeigt
außerdem dieselbe Tabelle konfigurierter Cache-Pfade wie Teil 2, gruppiert
nach Disk-Datenbank, falls mehrere vorhanden sind.

**Download:** `Cache Audit.app` von der [Releases](../../releases)-Seite
laden, DMG öffnen, in den Programme-Ordner ziehen.

**Selbst bauen:** `CacheAudit/CacheAudit.xcodeproj` in Xcode öffnen und
starten, oder vorher `xcodegen generate` in `CacheAudit/` ausführen, falls
die `.xcodeproj` fehlt (`brew install xcodegen`).

### Erster Start (unsignierter Build)

Dieser Build ist nicht von Apple notarisiert (dafür bräuchte es eine
kostenpflichtige Apple-Developer-Mitgliedschaft) — er ist ad-hoc signiert,
üblich für kleine, kostenlose Tools außerhalb des App Store. Gatekeeper
verweigert beim ersten Doppelklick das Öffnen. Einmalig nötig:

1. Rechtsklick (oder Control-Klick) auf `Cache Audit.app` im
   Programme-Ordner → **Öffnen**.
2. Im Dialog nochmal **Öffnen** klicken.

Danach lässt sich die App normal öffnen, wie jede andere App auch. Das ist
ein einmaliger Schritt pro Mac — Gatekeeper wird dabei nicht deaktiviert,
nur diese eine App freigegeben.

## Verwendung (Skript)

Doppelklick auf `DaVinci Cache Audit.command`. Es öffnet ein
Terminal-Fenster, scannt deine Laufwerke und gibt den Bericht aus.
Beliebige Taste drücken, um das Fenster danach zu schließen.

Alternativ direkt im Terminal:

```sh
./"DaVinci Cache Audit.command"
```

**Der erste Durchlauf auf einem großen oder eingeschlafenen externen
Laufwerk kann dauern** — die Größenberechnung muss den Cache-Ordner
tatsächlich durchlaufen, und macOS startet danach oft eine
Spotlight-Indizierung, nachdem tausende kleiner Cache-Dateien auf einem
externen Laufwerk angefasst wurden. Das Tool gibt währenddessen
Fortschrittszeilen aus, damit ein langsamer Durchlauf nicht wie ein
Hänger aussieht.

## Sicherheit

Das Skript ist **rein lesend**. Es löscht oder verändert nichts — es führt
nur `find`, `du` und lesende `SELECT`-Abfragen aus. Sicher, jederzeit
auszuführen, auch während Resolve läuft.

Um Render-Cache tatsächlich zu leeren: nicht von Hand löschen — entweder
vorher Resolve schließen, oder besser Resolves eigenes Tool nutzen:
**Playback → Delete Render Cache → All**.

## Lizenz

MIT — siehe [LICENSE](LICENSE).
