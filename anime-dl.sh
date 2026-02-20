#!/usr/bin/env bash
# =============================================================================
# anime-dl.sh — Téléchargeur Anime-Sama (style animenu)
# Compatible BusyBox (pas de grep -P)
# =============================================================================

set -euo pipefail

AS_BASE="https://anime-sama.tv/catalogue"

LANG="vostfr"
QUALITY="bestvideo[height<=1080]+bestaudio/best"
UA="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/120.0 Safari/537.36"
SEASON=1
EP_START=1
EP_END=9999
LECTEUR=0
DL_DIR="/downloads"
DRY_RUN=false
VERBOSE=false
LIST_ONLY=false
BEST_ORDER=()

# ─── Couleurs & styles ────────────────────────────────────
RESET="\033[0m";    BOLD="\033[1m";      DIM="\033[2m"
CYAN="\033[38;5;51m";    MAGENTA="\033[38;5;201m"; YELLOW="\033[38;5;226m"
GREEN="\033[38;5;118m";  RED="\033[38;5;196m";     BLUE="\033[38;5;39m"
ORANGE="\033[38;5;208m"; WHITE="\033[38;5;255m";   GREY="\033[38;5;240m"
BG_SEL="\033[48;5;236m"

# ─── Utilitaires terminal ─────────────────────────────────
hide_cursor()  { printf "\033[?25l"; }
show_cursor()  { printf "\033[?25h"; }
clear_screen() { printf "\033[2J\033[H"; }
move_to()      { printf "\033[%d;%dH" "$1" "$2"; }

log()   { echo -e "${CYAN}[INFO]${RESET}  $*"; }
ok()    { echo -e "${GREEN}[ OK ]${RESET}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
err()   { echo -e "${RED}[ERR ]${RESET}  $*" >&2; }
debug() { $VERBOSE && echo -e "${DIM}[DBG ]  $*${RESET}" >&2 || true; }
sep()   { echo -e "  ${GREY}$(printf '─%.0s' {1..56})${RESET}"; }
hdr()   { echo -e "\n${BOLD}$*${RESET}"; sep; }

# ─── Spinner ──────────────────────────────────────────────
spinner() {
    local pid=$1 msg="$2"
    local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local i=0
    while kill -0 "$pid" 2>/dev/null; do
        printf "\r  ${CYAN}${frames[$i]}${RESET}  ${WHITE}%s${RESET}  " "$msg"
        i=$(( (i+1) % ${#frames[@]} ))
        sleep 0.08
    done
    printf "\r  ${GREEN}✓${RESET}  ${WHITE}%s${RESET}\n" "$msg"
}

# ─── Banner ───────────────────────────────────────────────
print_banner() {
    echo -e "${MAGENTA}${BOLD}"
    echo "  ░█████╗░███╗░░██╗██╗███╗░░░███╗███████╗"
    echo "  ██╔══██╗████╗░██║██║████╗░████║██╔════╝"
    echo "  ███████║██╔██╗██║██║██╔████╔██║█████╗░░"
    echo "  ██╔══██║██║╚████║██║██║╚██╔╝██║██╔══╝░░"
    echo "  ██║░░██║██║░╚███║██║██║░╚═╝░██║███████╗"
    echo "  ╚═╝░░╚═╝╚═╝░░╚══╝╚═╝╚═╝░░░░╚═╝╚══════╝"
    echo -e "${RESET}"
    echo -e "  ${CYAN}▸${RESET} ${DIM}${WHITE}Anime-Sama Downloader${RESET}  ${GREY}[bash edition]${RESET}"
    echo ""
}

# ─── Nettoyage à la sortie ────────────────────────────────
cleanup() {
    show_cursor
    tput rmcup 2>/dev/null || true
    echo -e "${CYAN}Sayonara! またね ✦${RESET}"
    exit 0
}
trap cleanup EXIT INT TERM

usage() {
cat <<'EOF'
anime-dl.sh — Téléchargeur Anime-Sama

Usage : anime-dl.sh [OPTIONS] "Nom Anime"
        anime-dl.sh           (menu interactif)

  -i        Info : épisodes & lecteurs (pas de DL)
  -s N      Saison  (défaut: 1)
  -l LANG   vostfr | vf | vj ...  (défaut: vostfr)
  -L N      Forcer lecteur 1-8
  -e N      Épisode début  (défaut: 1)
  -E N      Épisode fin    (défaut: auto)
  -q QUAL   Qualité yt-dlp  (défaut: bestvideo[height<=1080]+bestaudio/best)
  -o DIR    Dossier de sortie  (défaut: ./downloads)
  -n        Dry-run
  -v        Verbose
  -h        Aide

Exemples :
  anime-dl.sh -i "Hell Mode"
  anime-dl.sh "Hell Mode"
  anime-dl.sh -L 2 "Hell Mode"
  anime-dl.sh -s 2 -l vf "Sword Art Online"
EOF
exit 0
}

check_deps() {
    local missing=()
    for cmd in curl python3 yt-dlp; do
        command -v "$cmd" &>/dev/null || missing+=("$cmd")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        err "Manquant : ${missing[*]}"
        err "  sudo apt install curl python3 && pip install -U yt-dlp"
        exit 1
    fi
}

fetch() {
    curl -sL -A "$UA" \
        -H "Accept: text/html,*/*" \
        -H "Accept-Language: fr-FR,fr;q=0.9" \
        --connect-timeout 15 --max-time 30 \
        --retry 2 --retry-delay 3 "$1"
}

page_exists() {
    local code
    code=$(curl -sL -A "$UA" -o /dev/null -w "%{http_code}" --max-time 10 "$1" 2>/dev/null || echo "000")
    debug "HTTP $code → $1"
    [[ "$code" == "200" ]]
}

make_slug_as() {
    python3 -c "
import sys, re, unicodedata
s = sys.argv[1].strip()
s = s.replace('&', 'and')
s = re.sub(r'^#+\s*', '', s)
s = re.sub(r\"['\u2018\u2019\`]\", '', s)
s = re.sub(r'[\"\u201c\u201d]', '', s)
s = re.sub(r'(?<!\d)\.(?!\d)', '-', s)
s = re.sub(r'[:;,!?(){}\[\]]', '', s)
s = s.lower()
s = unicodedata.normalize('NFD', s)
s = ''.join(c for c in s if unicodedata.category(c) != 'Mn')
s = re.sub(r'[^a-z0-9.\-]', '-', s)
s = re.sub(r'-+', '-', s)
print(s.strip('-'))
" "$1"
}

# ==============================================================================
# ANIME-SAMA
# ==============================================================================

_as_find_js_url_from_html() {
    local base_url="$1"
    python3 -c "
import sys, re
from urllib.parse import urljoin
base = sys.argv[1]
html = sys.stdin.read()
m = re.search(r\"src=[\\\"'']([^\\\"'']*episodes\\.js[^\\\"'']*)[\\\"'']\", html)
if m:
    url = m.group(1)
    print(urljoin(base, url))
" "$base_url"
}

as_get_js_url() {
    local slug="$1" season="$2" lang="$3"
    local page_url="${AS_BASE}/${slug}/saison${season}/${lang}/"
    local js_url
    js_url=$(fetch "$page_url" | _as_find_js_url_from_html "$page_url")
    if [[ -n "$js_url" ]]; then
        debug "episodes.js trouvé dans HTML: $js_url"
        echo "$js_url"
    else
        local direct="${page_url}episodes.js"
        debug "episodes.js non trouvé dans HTML → fallback: $direct"
        echo "$direct"
    fi
}

_as_parse_js() {
    python3 -c "
import sys, re
content = sys.stdin.read()
for n in range(1, 9):
    m = re.search(rf'var\s+eps{n}\s*=\s*\[([^\]]*)\]', content, re.DOTALL)
    if m:
        urls = re.findall(r'https?://[^\s\x27\"<>]+', m.group(1))
        for i, url in enumerate(urls):
            print(f'{n}|{i}|{url}')
"
}

_as_host_label() {
    python3 -c "
import sys, re
url = sys.stdin.read().strip()
m = re.search(r'(?<=://)[^/]+', url)
h = m.group(0) if m else url
names = {
    'vidmoly': 'Vidmoly (~720p)',
    'sibnet' : 'Sibnet (~480p)',
    'sendvid': 'Sendvid (~720p)',
    'embed4me': 'embed4me (~720p)',
    'lpayer':  'lpayer (~720p)',
    'dingtez': 'dingtezuni (~720p)',
}
for k, v in names.items():
    if k in h: print(v); exit()
print(h)
"
}

_as_test_lecteur() {
    local url="$1"
    local t_start t_end t_diff result
    t_start=$(date +%s%3N)
    if yt-dlp --get-url --no-warnings --socket-timeout 8 --retries 1 "$url" &>/dev/null; then
        result="ok"
    else
        result="fail"
    fi
    t_end=$(date +%s%3N)
    t_diff=$(( t_end - t_start ))
    local secs
    secs=$(python3 -c "import sys; print(f'{int(sys.argv[1])/1000:.1f}')" "$t_diff")
    if [[ "$result" == "ok" ]]; then
        echo -e "${GREEN}✓${RESET} (${secs}s)"
    else
        echo -e "${RED}✗${RESET} (${secs}s)"
    fi
}

# Teste tous les lecteurs sur l'ep1, retourne l'ordre optimal (lecteurs OK en premier)
_as_find_best_order() {
    local -n _eps_ref=$1   # tableau associatif all_eps passé par référence
    local ep_idx=0         # tester sur épisode 1

    log "Détection du meilleur lecteur sur l'ep.1…"
    local working=() failing=()

    for L in 4 1 2 5 6 7 8 3; do
        local u="${_eps_ref["${L}_${ep_idx}"]:-}"
        [[ -z "$u" ]] && continue
        printf "  ${DIM}Test L${L}…${RESET} "
        local t_start t_end t_diff
        t_start=$(date +%s%3N)
        if yt-dlp --get-url --no-warnings --socket-timeout 8 --retries 1 "$u" &>/dev/null; then
            t_end=$(date +%s%3N)
            t_diff=$(( t_end - t_start ))
            local secs
            secs=$(python3 -c "import sys; print(f'{int(sys.argv[1])/1000:.1f}')" "$t_diff")
            echo -e "${GREEN}✓${RESET} (${secs}s)"
            working+=("$L")
        else
            t_end=$(date +%s%3N)
            t_diff=$(( t_end - t_start ))
            local secs
            secs=$(python3 -c "import sys; print(f'{int(sys.argv[1])/1000:.1f}')" "$t_diff")
            echo -e "${RED}✗${RESET} (${secs}s)"
            failing+=("$L")
        fi
    done

    # Retourner l'ordre : working en premier, failing en fallback
    echo "${working[@]} ${failing[@]}"
}


as_info() {
    local slug="$1" season="$2" lang="$3"
    local page_url="${AS_BASE}/${slug}/saison${season}/${lang}/"

    echo -e "\n${BLUE}${BOLD}▶ ANIME-SAMA${RESET}"
    sep
    echo -e "  ${DIM}${page_url}${RESET}"

    if ! page_exists "$page_url"; then
        echo -e "  ${RED}✗ Page introuvable (slug: $slug)${RESET}"
        return 1
    fi

    local js_url
    js_url="$(as_get_js_url "$slug" "$season" "$lang")"
    debug "Fetch: $js_url"

    local js_content
    js_content="$(fetch "$js_url")"

    local ep_count
    ep_count=$(echo "$js_content" | _as_parse_js | wc -l)

    if [[ "$ep_count" -eq 0 ]]; then
        echo -e "  ${RED}✗ episodes.js vide ou inaccessible${RESET}"
        debug "Contenu JS reçu (100 chars): ${js_content:0:100}"
        return 1
    fi

    local info_data
    info_data=$(echo "$js_content" | python3 -c "
import sys, re

content = sys.stdin.read()
qual = {1:'~720p', 2:'~720p HD', 3:'~480p SD', 4:'~720p', 5:'~720p', 6:'?', 7:'?', 8:'?'}
names = {1:'embed4me/lpayer', 2:'Vidmoly', 3:'Sibnet', 4:'Sendvid', 5:'dingtezuni',
         6:'L6', 7:'L7', 8:'L8'}

counts = {}
ep1_urls = {}
max_ep = 0
for n in range(1, 9):
    m = re.search(rf'var\s+eps{n}\s*=\s*\[([^\]]*)\]', content, re.DOTALL)
    if m:
        urls = re.findall(r'https?://[^\s\x27\"<>]+', m.group(1))
        if urls:
            counts[n] = len(urls)
            ep1_urls[n] = urls[0]
            if len(urls) > max_ep:
                max_ep = len(urls)

if counts:
    print(f'MAX|{max_ep}')
    for n in sorted(counts):
        print(f'{n}|{names.get(n,f\"L{n}\")}|{qual.get(n,\"?\")}|{counts[n]}|{ep1_urls[n]}')
else:
    print('NONE')
")

    if [[ "$info_data" == "NONE" ]]; then
        echo -e "  Aucun épisode trouvé"
        return 1
    fi

    local max_ep
    max_ep=$(echo "$info_data" | grep '^MAX|' | cut -d'|' -f2)
    echo -e "  ${GREEN}✓ ${max_ep} épisodes${RESET}"
    echo -e "  ${DIM}Test yt-dlp sur ep.1 de chaque lecteur…${RESET}"
    echo

    printf "  %-4s %-18s %-12s %-4s %s\n" "L" "Lecteur" "Qualité" "Eps" "Test"
    printf "  %-4s %-18s %-12s %-4s %s\n" "────" "──────────────────" "────────────" "────" "──────────"

    BEST_ORDER=()
    local _info_working=() _info_failing=()
    while IFS='|' read -r n name qual count ep1_url; do
        [[ "$n" == "MAX" ]] && continue
        printf "  L%-3s %-18s %-12s %-4s " "$n" "$name" "$qual" "$count"
        local t_start t_end t_diff secs
        t_start=$(date +%s%3N)
        if yt-dlp --get-url --no-warnings --socket-timeout 8 --retries 1 "$ep1_url" &>/dev/null; then
            t_end=$(date +%s%3N); t_diff=$(( t_end - t_start ))
            secs=$(python3 -c "import sys; print(f'{int(sys.argv[1])/1000:.1f}')" "$t_diff")
            echo -e "${GREEN}✓${RESET} (${secs}s)"
            _info_working+=("$n")
        else
            t_end=$(date +%s%3N); t_diff=$(( t_end - t_start ))
            secs=$(python3 -c "import sys; print(f'{int(sys.argv[1])/1000:.1f}')" "$t_diff")
            echo -e "${RED}✗${RESET} (${secs}s)"
            _info_failing+=("$n")
        fi
    done <<< "$info_data"
    BEST_ORDER=("${_info_working[@]}" "${_info_failing[@]}")
    if [[ ${#_info_working[@]} -gt 0 ]]; then
        echo ""
        ok "Ordre mémorisé pour DL : L${_info_working[*]} en priorité"
    fi
}

as_download() {
    local anime_name="$1"
    local slug
    slug="$(make_slug_as "$anime_name")"
    local page_url="${AS_BASE}/${slug}/saison${SEASON}/${LANG}/"

    hdr "ANIME-SAMA — $anime_name"
    log "URL : $page_url"

    if ! page_exists "$page_url"; then
        err "Page introuvable : $page_url"
        err "→ Slug: '$slug'"
        return 1
    fi

    local js_url
    js_url="$(as_get_js_url "$slug" "$SEASON" "$LANG")"
    debug "episodes.js: $js_url"

    local js_content
    js_content="$(fetch "$js_url")"

    local tmpfile
    tmpfile=$(mktemp /tmp/animedl_eps.XXXXXX)
    echo "$js_content" | _as_parse_js > "$tmpfile"

    local ep_count
    ep_count=$(wc -l < "$tmpfile")

    if [[ "$ep_count" -eq 0 ]]; then
        err "episodes.js vide — aucune URL extraite"
        rm -f "$tmpfile"
        return 1
    fi

    declare -A all_eps
    local max_ep=0
    while IFS='|' read -r L idx url_val; do
        [[ -z "$L" || -z "$url_val" ]] && continue
        all_eps["${L}_${idx}"]="$url_val"
        local n=$(( idx + 1 ))
        [[ $n -gt $max_ep ]] && max_ep=$n
    done < "$tmpfile"
    rm -f "$tmpfile"

    # ── Ordre des lecteurs ─────────────────────────────────────
    local best_order
    if [[ $LECTEUR -gt 0 ]]; then
        best_order=("$LECTEUR")
    elif [[ ${#BEST_ORDER[@]} -gt 0 ]]; then
        best_order=("${BEST_ORDER[@]}")
        ok "Ordre mémorisé depuis Infos : L${BEST_ORDER[*]}"
        sep
    else
        log "Détection du meilleur lecteur sur l'ep.1…"
        sep
        local working=() failing=()
        for L in 4 1 2 5 6 7 8 3; do
            local u="${all_eps["${L}_0"]:-}"
            [[ -z "$u" ]] && continue
            printf "  ${DIM}Test L${L}…${RESET} "
            local t_start t_end t_diff secs
            t_start=$(date +%s%3N)
            if yt-dlp --get-url --no-warnings --socket-timeout 8 --retries 1 "$u" &>/dev/null; then
                t_end=$(date +%s%3N); t_diff=$(( t_end - t_start ))
                secs=$(python3 -c "import sys; print(f'{int(sys.argv[1])/1000:.1f}')" "$t_diff")
                echo -e "${GREEN}✓${RESET} (${secs}s)"
                working+=("$L")
            else
                t_end=$(date +%s%3N); t_diff=$(( t_end - t_start ))
                secs=$(python3 -c "import sys; print(f'{int(sys.argv[1])/1000:.1f}')" "$t_diff")
                echo -e "${RED}✗${RESET} (${secs}s)"
                failing+=("$L")
            fi
        done
        if [[ ${#working[@]} -gt 0 ]]; then
            best_order=("${working[@]}" "${failing[@]}")
            ok "Ordre optimal : L${working[*]} (fallback: ${failing[*]:-aucun})"
        else
            warn "Aucun lecteur fonctionnel — tentative quand même"
            best_order=(4 1 2 5 6 7 8 3)
        fi
        sep
    fi
    # ──────────────────────────────────────────────────────────

    local ep_end=$(( EP_END > max_ep ? max_ep : EP_END ))
    log "$max_ep épisodes | DL: ${EP_START}→${ep_end}"
    $DRY_RUN && warn "DRY-RUN actif"
    sep

    local success=0 fail=0

    for ep_num in $(seq "$EP_START" "$ep_end"); do
        local ep_idx=$(( ep_num - 1 ))
        local chosen_l=0 chosen_url=""

        if [[ $LECTEUR -gt 0 ]]; then
            chosen_url="${all_eps["${LECTEUR}_${ep_idx}"]:-}"
            chosen_l=$LECTEUR
        else
            for L in "${best_order[@]}"; do
                local u="${all_eps["${L}_${ep_idx}"]:-}"
                if [[ -n "$u" ]]; then
                    chosen_l=$L; chosen_url="$u"; break
                fi
            done
        fi

        if [[ -z "$chosen_url" ]]; then
            warn "Ep.$ep_num : aucune URL disponible"
            ((fail++)); continue
        fi

        local host_label
        host_label=$(echo "$chosen_url" | _as_host_label)

        _dl "AS/L${chosen_l}(${host_label})" "$ep_num" "$anime_name" "$chosen_url" \
            && { success=$((success+1)); } || {
                local recovered=false
                for L in "${best_order[@]}"; do
                    [[ $L -eq $chosen_l ]] && continue
                    local fb="${all_eps["${L}_${ep_idx}"]:-}"
                    [[ -z "$fb" ]] && continue
                    local fhost; fhost=$(echo "$fb" | _as_host_label)
                    warn "  → Fallback L$L ($fhost)"
                    _dl "AS/L${L}(${fhost})" "$ep_num" "$anime_name" "$fb" \
                        && { recovered=true; ((success++)); break; }
                done
                $recovered || ((fail++))
            }
        sleep 1
    done
    curl -s -X POST "http://localhost:8096/Library/Refresh?api_key=71adae0196d64c378fafb4deea2522eb"
    sep
    ok "Anime-sama : $success téléchargés, $fail échoués"
    [[ $success -gt 0 ]] && \
        echo -e "  Dossier : ${DL_DIR}/${anime_name}/Saison $(printf '%02d' "$SEASON")/"
}

# ==============================================================================
# yt-dlp wrapper
# ==============================================================================

_dl() {
    local source="$1" ep_num="$2" anime_name="$3" url="$4"
    local out_dir="${DL_DIR}/${anime_name}/Season $(printf '%02d' "$SEASON")"
    mkdir -p "$out_dir"
    local out_tpl="${out_dir}/${anime_name} S$(printf "%02d" "$SEASON")E$(printf "%02d" "$ep_num").%(ext)s"

    if $DRY_RUN; then
        echo -e "  ${DIM}[DRY] Ep.$(printf '%03d' "$ep_num") | $source${RESET}"
        echo -e "  ${DIM}      $url${RESET}"
        return 0
    fi

    local host
    host=$(python3 -c "
import sys, re
m = re.search(r'(?<=://)[^/]+', sys.argv[1])
print(m.group() if m else '?')
" "$url" 2>/dev/null || echo "?")
    log "  ↳ $source | $host"

    yt-dlp -f "$QUALITY" -o "$out_tpl" --downloader aria2c --downloader-args "aria2c:-x 16 -s 16 -k 1M" \
        --merge-output-format mkv \
        --no-warnings --progress --no-continue \
        --add-metadata --no-playlist --retries 3 \
        "$url" 2>/dev/null \
    && { ok "Ep.$(printf '%03d' "$ep_num") ✓"; return 0; }

    warn "  Fallback 'best'…"
    yt-dlp -f "best" -o "$out_tpl" --downloader aria2c --downloader-args "aria2c:-x 16 -s 16 -k 1M" \
        --no-warnings --progress --no-playlist --retries 3 \
        "$url" 2>/dev/null \
    && { ok "Ep.$(printf '%03d' "$ep_num") ✓ (best)"; return 0; }

    err "Ep.$(printf '%03d' "$ep_num") : échec"
    return 1
}

# ==============================================================================
# MENU INTERACTIF (fzf)
# ==============================================================================

print_banner_plain() {
    echo "  ██╗░░██╗██╗██╗░░██╗██╗      █████╗░███╗░░██╗██╗███╗░░░███╗███████╗"
    echo "  ██║░██╔╝██║██║░██╔╝██║     ██╔══██╗████╗░██║██║████╗░████║██╔════╝"
    echo "  █████═╝░██║█████═╝░██║     ███████║██╔██╗██║██║██╔████╔██║█████╗░░"
    echo "  ██╔═██╗░██║██╔═██╗░██║     ██╔══██║██║╚████║██║██║╚██╔╝██║██╔══╝░░"
    echo "  ██║░╚██╗██║██║░╚██╗██║     ██║░░██║██║░╚███║██║██║░╚═╝░██║███████╗"
    echo "  ╚═╝░░╚═╝╚═╝╚═╝░░╚═╝╚═╝     ╚═╝░░╚═╝╚═╝░░╚══╝╚═╝╚═╝░░░░╚═╝╚══════╝"
    echo ""
    echo "  Langue: ${LANG}  |  Saison: ${SEASON}  |  Lecteur: ${LECTEUR:-auto}  |  Ep: ${EP_START}→${EP_END}"
    echo ""
}

launcher() {
    local prompt="$1"
    fzf --reverse --cycle --prompt "$prompt" \
        --header "$(print_banner_plain)" \
        --header-first \
        --color "prompt:51,pointer:201,hl:118,hl+:118,header:201" \
        --border rounded \
        --margin 1,2 \
        --info hidden
}

menu_action_download() {
    clear_screen
    echo ""
    echo -e "  ${CYAN}${BOLD}╔══ TÉLÉCHARGER UN ANIME ══╗${RESET}"
    echo ""
    printf "  ${WHITE}Titre de l'anime : ${RESET}"
    read -r anime_input
    echo ""
    if [[ -z "$anime_input" ]]; then
        echo -e "  ${RED}✗ Aucun titre saisi.${RESET}"
        sleep 1
        return
    fi
    ANIME_NAME="$anime_input"
    as_download "$ANIME_NAME"
    echo ""
    printf "  ${GREY}[Entrée pour revenir au menu]${RESET}"
    read -r
}

menu_action_info() {
    clear_screen
    echo ""
    echo -e "  ${MAGENTA}${BOLD}╔══ INFOS & LECTEURS ══╗${RESET}"
    echo ""
    printf "  ${WHITE}Titre de l'anime : ${RESET}"
    read -r anime_input
    echo ""
    if [[ -z "$anime_input" ]]; then
        echo -e "  ${RED}✗ Aucun titre saisi.${RESET}"
        sleep 1
        return
    fi
    local slug
    slug="$(make_slug_as "$anime_input")"
    echo -e "  ${BOLD}═══ ${anime_input} ═══${RESET}"
    echo -e "  Langue: ${LANG}  |  Saison: ${SEASON}"
    as_info "$slug" "$SEASON" "$LANG"
    echo ""
    printf "  ${GREY}[Entrée pour revenir au menu]${RESET}"
    read -r
}

menu_action_settings() {
    clear_screen
    echo ""
    echo -e "  ${GREY}${BOLD}╔══ PARAMÈTRES DE SESSION ══╗${RESET}"
    echo ""
    sep
    echo -e "  ${DIM}Laisser vide = garder la valeur actuelle${RESET}"
    echo ""
    printf "  ${WHITE}Langue         ${GREY}[${LANG}]${RESET} : "; read -r v; [[ -n "$v" ]] && LANG="$v"
    printf "  ${WHITE}Saison         ${GREY}[${SEASON}]${RESET} : "; read -r v; [[ -n "$v" ]] && SEASON="$v"
    printf "  ${WHITE}Lecteur (0=auto) ${GREY}[${LECTEUR}]${RESET} : "; read -r v; [[ -n "$v" ]] && LECTEUR="$v"
    printf "  ${WHITE}Épisode début  ${GREY}[${EP_START}]${RESET} : "; read -r v; [[ -n "$v" ]] && EP_START="$v"
    printf "  ${WHITE}Épisode fin    ${GREY}[${EP_END}]${RESET} : "; read -r v; [[ -n "$v" ]] && EP_END="$v"
    printf "  ${WHITE}Dossier sortie ${GREY}[${DL_DIR}]${RESET} : "; read -r v; [[ -n "$v" ]] && DL_DIR="$v"
    echo ""
    sep
    echo -e "  ${GREEN}✓ Paramètres mis à jour.${RESET}"
    sleep 1
}

run_menu() {
    while true; do
        cmd=$(printf "🔍  Télécharger un anime\n📋  Infos & lecteurs\n⚙️   Paramètres de session\n❌  Quitter" \
            | launcher "Menu > ") || cleanup
        case "$cmd" in
            "🔍"*) menu_action_download ;;
            "📋"*) menu_action_info     ;;
            "⚙️"*) menu_action_settings  ;;
            "❌"*) cleanup              ;;
        esac
    done
}


# ==============================================================================
# MAIN
# ==============================================================================

# Si des arguments → mode CLI direct (comportement original)
if [[ $# -gt 0 ]]; then
    while getopts ":s:e:E:l:L:q:o:nivh" opt; do
        case $opt in
            s) SEASON="$OPTARG" ;;
            e) EP_START="$OPTARG" ;;
            E) EP_END="$OPTARG" ;;
            l) LANG="$OPTARG" ;;
            L) LECTEUR="$OPTARG" ;;
            q) QUALITY="$OPTARG" ;;
            o) DL_DIR="$OPTARG" ;;
            n) DRY_RUN=true ;;
            i) LIST_ONLY=true ;;
            v) VERBOSE=true ;;
            h) usage ;;
            :) err "-$OPTARG nécessite un argument"; exit 1 ;;
            \?) err "Option inconnue : -$OPTARG"; exit 1 ;;
        esac
    done
    shift $((OPTIND - 1))

    [[ $# -eq 0 ]] && { err "Nom de l'anime manquant"; echo; usage; }
    ANIME_NAME="$*"
    check_deps

    if $LIST_ONLY; then
        slug_as="$(make_slug_as "$ANIME_NAME")"
        echo -e "\n${BOLD}═══ $ANIME_NAME ═══${RESET}"
        echo -e "  Langue: $LANG | Saison: $SEASON"
        as_info "$slug_as" "$SEASON" "$LANG"
        echo
        exit 0
    fi

    as_download "$ANIME_NAME"
else
    # Aucun argument → menu interactif
    check_deps
    run_menu
fi
