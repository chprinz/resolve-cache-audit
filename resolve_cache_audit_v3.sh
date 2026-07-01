#!/bin/bash
# resolve_cache_audit_v3.sh — bash 3.2 kompatibel (macOS default)

RED='\033[0;31m'; GRN='\033[0;32m'; YLW='\033[1;33m'
BLU='\033[0;34m'; DIM='\033[2m'; BLD='\033[1m'; NC='\033[0m'

# ── Datenbank-Roots ───────────────────────────────────────────────
DB_ROOT_MAC="$HOME/Movies/Da Vinci Resolve/Resolve Projects/Users/guest/Projects"
DB_ROOT_X9="/Volumes/X9 Pro/DaVinci/Resolve Projects/Users/guest/Projects"
DB_ROOT_T7="/Volumes/T7/DaVinci/Resolve Projects/Users/guest/Projects"

# ── CacheClip-Ordner ──────────────────────────────────────────────
CACHE_LOCAL_1="$HOME/Movies/Da Vinci Resolve/CacheClip"
CACHE_LOCAL_2="$HOME/Movies/Da Vinci Resolve/Local Cache/CacheClip"
CACHE_EXT_1="/Volumes/X9 Pro/DaVinci/CacheClip/CacheClip"   # das echte

# ── UUID aus Project.db extrahieren ───────────────────────────────
# Resolve speichert die UUID des Projekts in SM_UserSetup.CacheIndices
# oder als freistehende UUID in einer der Spalten — wir suchen breit
get_project_uuid() {
    local db="$1"
    local uuid=""

    # Alle Textspalten von SM_UserSetup durchsuchen
    uuid=$(sqlite3 "$db" "SELECT * FROM SM_UserSetup LIMIT 1;" 2>/dev/null \
        | tr '|' '\n' \
        | grep -oiE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' \
        | head -1)

    # Fallback: alle Tabellen durchsuchen
    if [ -z "$uuid" ]; then
        uuid=$(sqlite3 "$db" \
            "SELECT name FROM sqlite_master WHERE type='table';" 2>/dev/null \
            | while read tbl; do
                sqlite3 "$db" "SELECT * FROM \"$tbl\" LIMIT 5;" 2>/dev/null \
                | tr '|' '\n' \
                | grep -oiE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'
              done | head -1)
    fi

    echo "$uuid"
}

get_cache_path() {
    local db="$1"
    sqlite3 "$db" "SELECT CachePath FROM SM_UserSetup LIMIT 1;" 2>/dev/null
}

is_local_path() {
    local p="$1"
    [[ "$p" == /Users/* ]] || [[ "$p" == ~/Movies/* ]] || [[ "$p" == *"Local Cache"* ]]
}

# ══ HEADER ════════════════════════════════════════════════════════
echo ""
echo -e "${BLD}══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLD}  DaVinci Resolve — Cache Audit v3${NC}"
echo -e "${BLD}══════════════════════════════════════════════════════════════${NC}"
echo ""

# ══ SCHRITT 1: UUID-Map aufbauen ══════════════════════════════════
# Wir bauen eine Lookup-Tabelle: UUID → Projektname
# Gespeichert als Textdatei im /tmp

UUID_MAP="/tmp/resolve_uuid_map_$$.txt"
> "$UUID_MAP"

echo -e "${DIM}  Lese Projektdatenbanken…${NC}"

for root_label_pair in \
    "Mac|$DB_ROOT_MAC" \
    "X9 Pro|$DB_ROOT_X9" \
    "T7|$DB_ROOT_T7"; do

    label="${root_label_pair%%|*}"
    root="${root_label_pair#*|}"

    [ -d "$root" ] || continue

    while IFS= read -r db; do
        proj=$(basename "$(dirname "$db")")
        [[ "$proj" == _TEMPLATES* ]] && continue

        uuid=$(get_project_uuid "$db")
        cache=$(get_cache_path "$db")

        # Absoluten Cache-Pfad bestimmen
        if [ -z "$cache" ]; then
            cache_resolved="DEFAULT"
        elif [[ "$cache" == /* ]]; then
            cache_resolved="$cache"
        else
            # Relativer Pfad → relativ zum Datenbank-Root
            db_drive=$(echo "$root" | sed 's|/Resolve Projects.*||')
            cache_resolved="$db_drive/$cache"
        fi

        # In UUID-Map schreiben: uuid|projektname|db-label|cache-pfad
        if [ -n "$uuid" ]; then
            echo "${uuid}|${proj}|${label}|${cache_resolved}" >> "$UUID_MAP"
        else
            echo "NO-UUID|${proj}|${label}|${cache_resolved}" >> "$UUID_MAP"
        fi

    done < <(find "$root" -name "Project.db" ! -path "*/_TEMPLATES/*" ! -path "*/ARCHIVED/*" 2>/dev/null | sort)
done

# ══ TEIL 1: Projekte mit Cache-Status ════════════════════════════
echo ""
echo -e "${BLD}Teil 1 — Cache-Pfad je Projekt${NC}"
echo ""

for db_label in "Mac" "X9 Pro" "T7"; do
    projects=$(grep "|${db_label}|" "$UUID_MAP" 2>/dev/null)
    [ -z "$projects" ] && continue

    echo -e "  ${BLU}${BLD}── Datenbank: $db_label${NC}"
    printf "  %-38s  %-9s  %s\n" "Projekt" "Status" "Cache-Pfad"
    printf "  %-38s  %-9s  %s\n" "─────────────────────────────────────" "─────────" "──────────────────────────────"

    echo "$projects" | while IFS='|' read -r uuid proj label cache; do
        proj_short="${proj:0:36}"
        if [ "$cache" = "DEFAULT" ]; then
            echo -e "  $(printf '%-38s' "$proj_short")  ${YLW}DEFAULT  ${NC}  ${DIM}folgt Media Storage Priorität${NC}"
        elif is_local_path "$cache"; then
            echo -e "  $(printf '%-38s' "$proj_short")  ${RED}✗ LOKAL ${NC}  $cache"
        else
            echo -e "  $(printf '%-38s' "$proj_short")  ${GRN}✓ EXTERN${NC}  $cache"
        fi
    done
    echo ""
done

# ══ TEIL 2: CacheClip-Ordner mit Projektnamen ════════════════════
echo -e "${BLD}Teil 2 — CacheClip-Ordner nach Größe, mit Projektnamen${NC}"
echo ""

scan_cache_dir() {
    local dir="$1"
    local drive_label="$2"
    local is_local="$3"

    [ -d "$dir" ] || return

    if [ "$is_local" = "1" ]; then
        label="${RED}[LOKAL — intern]${NC}"
    else
        label="${GRN}[EXTERN]${NC}"
    fi

    total=$(du -sh "$dir" 2>/dev/null | cut -f1)
    echo -e "  ${BLD}📁 $dir${NC}  $label"
    echo -e "     ${BLD}Gesamt: $total${NC}"
    echo ""

    # UUID-Ordner: einmalig auflisten mit du, dann sortieren
    du -sh "$dir"/*/ 2>/dev/null \
        | grep -vE '/(audio|OptimizedMedia)/' \
        | sort -rh \
        | while IFS=$'\t' read -r size path; do
            uuid=$(basename "$path")
            # UUID-Format prüfen
            if echo "$uuid" | grep -qiE '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'; then
                # Projektname aus UUID-Map
                proj=$(grep -i "^${uuid}|" "$UUID_MAP" 2>/dev/null | cut -d'|' -f2 | head -1)
                if [ -n "$proj" ]; then
                    printf "     %8s  ${BLD}%-35s${NC}  ${DIM}%s${NC}\n" "$size" "$proj" "$uuid"
                else
                    printf "     %8s  ${DIM}%-35s  %s${NC}\n" "$size" "(Projekt nicht gefunden)" "$uuid"
                fi
            else
                # CacheClip-Unterordner oder andere
                printf "     %8s  ${DIM}%s${NC}\n" "$size" "$uuid"
            fi
          done

    # Audio und OptimizedMedia separat
    for special in audio OptimizedMedia; do
        if [ -d "$dir/$special" ]; then
            s=$(du -sh "$dir/$special" 2>/dev/null | cut -f1)
            printf "     %8s  ${DIM}%s  ← kein Render-Cache, separat löschbar${NC}\n" "$s" "$special"
        fi
    done
    echo ""
}

scan_cache_dir "$CACHE_LOCAL_1"  "Mac" "1"
scan_cache_dir "$CACHE_LOCAL_2"  "Mac" "1"
scan_cache_dir "$CACHE_EXT_1"    "X9 Pro" "0"

# ══ ZUSAMMENFASSUNG ═══════════════════════════════════════════════
echo -e "${BLD}══════════════════════════════════════════════════════════════${NC}"
LOCAL=$(grep -c "✗\|LOKAL" "$UUID_MAP" 2>/dev/null || echo 0)
echo -e "${DIM}  UUID-Map: $(wc -l < "$UUID_MAP") Projekte gelesen${NC}"
echo -e "${DIM}  Resolve SCHLIESSEN bevor du Cache-Ordner manuell löschst.${NC}"
echo -e "${DIM}  Sicher löschen: Resolve → Playback → Delete Render Cache → All${NC}"
echo -e "${BLD}══════════════════════════════════════════════════════════════${NC}"
echo ""

rm -f "$UUID_MAP"
