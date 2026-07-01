#!/bin/bash
# DaVinci Resolve — Cache Audit
#
# Finds every Resolve disk database and every CacheClip render-cache folder
# on this Mac automatically — on any internal or external drive, under any
# drive name — and reports which project is using how much cache, on which
# drive, sorted by size.
#
# Key discovery: every UUID-named folder directly under a CacheClip directory
# contains a plain-text "Info.txt" file with "Database Name" / "Project Name".
# That's Resolve's own UUID→project mapping — no SQL guessing required.
#
# Read-only. This script never deletes or modifies anything — it only reads
# and reports. Safe to run at any time, even while Resolve is running.
#
# Compatible with macOS' stock bash 3.2 (no declare -A, no mapfile).

export LC_ALL=C

RED='\033[0;31m'; GRN='\033[0;32m'; YLW='\033[1;33m'
BLU='\033[0;34m'; DIM='\033[2m'; BLD='\033[1m'; NC='\033[0m'

TMP_DIR=$(mktemp -d /tmp/resolve_cache_audit.XXXXXX)
CACHE_RECORDS="$TMP_DIR/cache_records.tsv"      # size_kb \t kind \t project \t database \t drivetype \t path
CONFIG_RECORDS="$TMP_DIR/config_records.tsv"    # project \t database \t configured_path
SEARCH_BASES="$TMP_DIR/search_bases.txt"
trap 'rm -rf "$TMP_DIR"' EXIT

: > "$CACHE_RECORDS"
: > "$CONFIG_RECORDS"

echo ""
echo -e "${BLD}══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLD}  DaVinci Resolve — Cache Audit${NC}"
echo -e "${BLD}══════════════════════════════════════════════════════════════${NC}"
echo ""

# ── Where do we search? ───────────────────────────────────────────
# $HOME plus every mounted volume under /Volumes (works for any drive
# name, not just the ones on the machine this was written on).
{
    echo "$HOME"
    for v in /Volumes/*/; do
        [ -d "$v" ] || continue
        case "$v" in
            "/Volumes/Macintosh HD/") continue ;;
            *TimeMachine*|*Backups.backupdb*) continue ;;
        esac
        echo "${v%/}"
    done
} > "$SEARCH_BASES"

echo -e "${DIM}  Searching in:${NC}"
while IFS= read -r b; do echo -e "${DIM}    • $b${NC}"; done < "$SEARCH_BASES"
echo ""

# ── Helper functions ────────────────────────────────────────────────

# Determines whether a path lives on an internal or external drive.
get_drive_type() {
    local path="$1" dev loc
    [ -e "$path" ] || { echo "unknown"; return; }
    dev=$(df -P "$path" 2>/dev/null | tail -1 | awk '{print $1}')
    if [ -n "$dev" ]; then
        loc=$(diskutil info "$dev" 2>/dev/null | awk -F': *' '/Device Location/{print $2}')
    fi
    case "$loc" in
        Internal) echo "internal" ;;
        External) echo "external" ;;
        *)
            case "$path" in
                /Volumes/*) echo "external" ;;
                *) echo "internal" ;;
            esac
            ;;
    esac
}

# KB → human-readable size
human_size() {
    awk -v kb="$1" 'BEGIN{
        v = kb * 1024
        split("B KB MB GB TB", u, " ")
        i = 1
        while (v >= 1024 && i < 5) { v /= 1024; i++ }
        printf "%.1f %s", v, u[i]
    }'
}

is_uuid_dir() {
    case "$(basename "$1")" in
        [0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]-[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]-[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]-[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]-[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F])
            return 0 ;;
        *) return 1 ;;
    esac
}

# A found "CacheClip" directory only counts as "real" if it directly
# contains UUID folders or the known shared folders (audio/OptimizedMedia).
# This automatically skips pure nesting mistakes (CacheClip/CacheClip)
# without needing any path hardcoded for it.
is_real_cacheclip_root() {
    local dir="$1" entry
    for entry in "$dir"/*/; do
        [ -d "$entry" ] || continue
        entry="${entry%/}"
        if is_uuid_dir "$entry"; then return 0; fi
        case "$(basename "$entry")" in
            [Aa]udio|[Oo]ptimizedMedia) return 0 ;;
        esac
    done
    return 1
}

# ── Step 1: find CacheClip directories ────────────────────────────
echo -e "${DIM}  Scanning for CacheClip folders…${NC}"

CACHECLIP_ROOTS="$TMP_DIR/cacheclip_roots.txt"
: > "$CACHECLIP_ROOTS"

while IFS= read -r base; do
    find "$base" -maxdepth 8 -type d -iname "CacheClip" \
        -not -path "*/.Trashes/*" -not -path "*/.Spotlight-V100/*" \
        -not -path "*/.fseventsd/*" -not -path "*/Backups.backupdb/*" \
        2>/dev/null
done < "$SEARCH_BASES" | sort -u > "$TMP_DIR/cacheclip_candidates.txt"

while IFS= read -r cand; do
    [ -z "$cand" ] && continue
    if is_real_cacheclip_root "$cand"; then
        echo "$cand" >> "$CACHECLIP_ROOTS"
    fi
done < "$TMP_DIR/cacheclip_candidates.txt"

sort -u "$CACHECLIP_ROOTS" -o "$CACHECLIP_ROOTS"

if [ ! -s "$CACHECLIP_ROOTS" ]; then
    echo -e "${YLW}  No CacheClip folders found.${NC}"
fi

# ── Step 2: scan every CacheClip root ─────────────────────────────
echo -e "${DIM}  Calculating cache sizes (this can take a while on external or sleeping drives)…${NC}"

while IFS= read -r root; do
    [ -z "$root" ] && continue
    drivetype=$(get_drive_type "$root")
    echo -e "${DIM}    · $root${NC}"

    for entry in "$root"/*/; do
        [ -d "$entry" ] || continue
        entry="${entry%/}"
        name=$(basename "$entry")

        if is_uuid_dir "$entry"; then
            size_kb=$(du -sk "$entry" 2>/dev/null | awk '{print $1}')
            [ -z "$size_kb" ] && size_kb=0

            dbname=""
            projname=""
            info_file="$entry/Info.txt"
            if [ -f "$info_file" ]; then
                dbname=$(sed -n 's/^Database Name: //p' "$info_file" | head -1)
                projname=$(sed -n 's/^Project Name: //p' "$info_file" | head -1)
            fi

            if [ -z "$projname" ]; then
                projname="(unknown — project possibly deleted)"
                dbname="?"
            fi

            printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
                "$size_kb" "project" "$projname" "$dbname" "$drivetype" "$entry" >> "$CACHE_RECORDS"

        else
            case "$name" in
                [Aa]udio)
                    size_kb=$(du -sk "$entry" 2>/dev/null | awk '{print $1}')
                    printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
                        "${size_kb:-0}" "shared" "Audio cache (all projects)" "—" "$drivetype" "$entry" >> "$CACHE_RECORDS"
                    ;;
                [Oo]ptimizedMedia)
                    size_kb=$(du -sk "$entry" 2>/dev/null | awk '{print $1}')
                    printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
                        "${size_kb:-0}" "shared" "Optimized Media (not render cache)" "—" "$drivetype" "$entry" >> "$CACHE_RECORDS"
                    ;;
            esac
        fi
    done
done < "$CACHECLIP_ROOTS"

# ── Step 3: find disk databases & read configured cache paths ────
echo -e "${DIM}  Scanning for Resolve databases…${NC}"

PROJECT_DBS="$TMP_DIR/project_dbs.txt"
: > "$PROJECT_DBS"

while IFS= read -r base; do
    find "$base" -maxdepth 10 -type f -iname "Project.db" -ipath "*Resolve Projects*" \
        -not -ipath "*_TEMPLATES*" -not -ipath "*ARCHIVED*" \
        -not -path "*/.Trashes/*" 2>/dev/null
done < "$SEARCH_BASES" | sort -u > "$PROJECT_DBS"

if command -v sqlite3 >/dev/null 2>&1 && [ -s "$PROJECT_DBS" ]; then
    while IFS= read -r db; do
        [ -z "$db" ] && continue
        proj=$(basename "$(dirname "$db")")
        db_label=$(echo "$db" | sed -E 's#.*/([^/]+)/Resolve Projects/.*#\1#')
        [ "$db_label" = "$db" ] && db_label="?"

        cachepath=$(sqlite3 "$db" "SELECT CachePath FROM SM_UserSetup LIMIT 1;" 2>/dev/null)

        printf '%s\t%s\t%s\n' "$proj" "$db_label" "$cachepath" >> "$CONFIG_RECORDS"
    done < "$PROJECT_DBS"
fi

# ══ OUTPUT ════════════════════════════════════════════════════════

echo ""
echo -e "${BLD}Part 1 — Cache usage per project, sorted by size${NC}"
echo ""

if [ -s "$CACHE_RECORDS" ]; then
    printf "  %-42s  %-8s  %8s  %s\n" "Project" "Drive" "Size" "Path"
    printf "  %-42s  %-8s  %8s  %s\n" "──────────────────────────────────────────" "────────" "────────" "────"

    sort -t"$(printf '\t')" -k1,1nr "$CACHE_RECORDS" | while IFS=$'\t' read -r size_kb kind proj db drive path; do
        human=$(human_size "$size_kb")
        proj_short="${proj:0:42}"

        if [ "$drive" = "internal" ]; then
            drive_disp="${RED}internal${NC}"
        elif [ "$drive" = "external" ]; then
            drive_disp="${GRN}external${NC}"
        else
            drive_disp="${DIM}?${NC}       "
        fi

        if [ "$kind" = "shared" ]; then
            printf "  ${DIM}%-42s${NC}  %b  %8s  ${DIM}%s${NC}\n" "$proj_short" "$drive_disp" "$human" "$path"
        else
            printf "  ${BLD}%-42s${NC}  %b  %8s  ${DIM}%s${NC}\n" "$proj_short" "$drive_disp" "$human" "$path"
        fi
    done
else
    echo -e "${YLW}  No cache data found.${NC}"
fi

echo ""
TOTAL_LOCAL=$(awk -F'\t' '$5=="internal"{s+=$1} END{print s+0}' "$CACHE_RECORDS")
TOTAL_EXT=$(awk -F'\t' '$5=="external"{s+=$1} END{print s+0}' "$CACHE_RECORDS")
echo -e "  ${BLD}Total internal:${NC} $(human_size "$TOTAL_LOCAL")"
echo -e "  ${BLD}Total external:${NC} $(human_size "$TOTAL_EXT")"

echo ""
echo -e "${BLD}Part 2 — Configured cache path per project (from SM_UserSetup)${NC}"
echo ""

if [ -s "$CONFIG_RECORDS" ]; then
    printf "  %-42s  %-9s  %s\n" "Project" "Database" "Configured cache path"
    printf "  %-42s  %-9s  %s\n" "──────────────────────────────────────────" "─────────" "──────────────────────"

    while IFS=$'\t' read -r proj db cachepath; do
        proj_short="${proj:0:42}"
        if [ -z "$cachepath" ]; then
            printf "  %-42s  %-9s  ${YLW}%s${NC}\n" "$proj_short" "$db" "Default (follows Media Storage priority)"
        elif [ -e "$cachepath" ]; then
            printf "  %-42s  %-9s  %s\n" "$proj_short" "$db" "$cachepath"
        else
            printf "  %-42s  %-9s  ${RED}%s${NC}\n" "$proj_short" "$db" "$cachepath (drive not connected)"
        fi
    done < "$CONFIG_RECORDS"
else
    echo -e "${DIM}  No databases found, or sqlite3 is not available.${NC}"
fi

echo ""
echo -e "${BLD}══════════════════════════════════════════════════════════════${NC}"
echo -e "${DIM}  Close Resolve before deleting any cache folders manually.${NC}"
echo -e "${DIM}  Safer route: Resolve → Playback → Delete Render Cache → All${NC}"
echo -e "${BLD}══════════════════════════════════════════════════════════════${NC}"
echo ""

read -n 1 -s -r -p "Press any key to close this window…"
echo ""
