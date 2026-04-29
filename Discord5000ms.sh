#!/bin/sh
# ══════════════════════════════════════════════════════════════
#   Discord Fix Manager для Zapret by StressOzz
#   Версия: 2.0  |  Решение проблемы 5000ms в голосовых каналах
#   Запуск: sh discord_fix.sh
# ══════════════════════════════════════════════════════════════

SCRIPT_VERSION="2.0"
GREEN="\033[1;32m"; RED="\033[1;31m"; CYAN="\033[1;36m"
YELLOW="\033[1;33m"; MAGENTA="\033[1;35m"; BLUE="\033[0;34m"
DGRAY="\033[38;5;244m"; NC="\033[0m"

CONF="/etc/config/zapret"
HOSTS_FILE="/etc/hosts"
CUSTOM_DIR="/opt/zapret/init.d/openwrt/custom.d"
BACKUP_DIR="/opt/zapret_backup/discord"
TMP_DIR="/tmp/discord_fix_tmp"
LOG_FILE="/tmp/discord_fix.log"

mkdir -p "$TMP_DIR" "$BACKUP_DIR" 2>/dev/null

PAUSE()  { echo -ne "\n${YELLOW}Нажмите Enter...${NC}"; read dummy; }
SEP()    { echo -e "${CYAN}──────────────────────────────────────────${NC}"; }
HEADER() { clear
           echo -e "╔══════════════════════════════════════════╗"
           printf  "║  ${MAGENTA}%-42s${NC}║\n" "$1"
           echo -e "╚══════════════════════════════════════════╝\n"; }

log() { echo "$(date '+%H:%M:%S') $*" >> "$LOG_FILE"; }

# ══════════════════════════════════════════════════════════════
# ПАКЕТНЫЙ МЕНЕДЖЕР
# ══════════════════════════════════════════════════════════════
if command -v opkg >/dev/null 2>&1; then
    PKG="opkg"; UPDATE="opkg update"
    INSTALL="opkg install"; DELETE="opkg remove --autoremove"
else
    PKG="apk"; UPDATE="apk update"
    INSTALL="apk add --allow-untrusted"; DELETE="apk del"
fi

# ══════════════════════════════════════════════════════════════
# ZAPRET
# ══════════════════════════════════════════════════════════════
ZAPRET_RESTART() {
    [ -x /opt/zapret/sync_config.sh ] && /opt/zapret/sync_config.sh >/dev/null 2>&1
    /etc/init.d/zapret restart >/dev/null 2>&1
    sleep 2
    log "Zapret перезапущен"
}

zapret_installed() { [ -f /etc/init.d/zapret ]; }
zapret_check() {
    if ! zapret_installed; then
        echo -e "\n${RED}Zapret не установлен!${NC}\n"; PAUSE; return 1
    fi
    return 0
}

# ══════════════════════════════════════════════════════════════
# ФИНСКИЕ IP — одна из главных причин 5000ms
# ══════════════════════════════════════════════════════════════
FIN_PATTERN="104\.25\.158\.178 finland[0-9]\{5\}\.discord\.media"

fin_status() { grep -q "$FIN_PATTERN" "$HOSTS_FILE" && return 0 || return 1; }

fin_add() {
    echo -e "${CYAN}Добавляем финские IP discord.media...${NC}"
    seq 10000 10199 \
        | awk '{print "104.25.158.178 finland"$1".discord.media"}' \
        | grep -vxFf "$HOSTS_FILE" >> "$HOSTS_FILE"
    /etc/init.d/dnsmasq restart >/dev/null 2>&1
    log "Финские IP добавлены"
    echo -e "${GREEN}Добавлено 200 записей finland****.discord.media!${NC}"
}

fin_remove() {
    echo -e "${CYAN}Удаляем финские IP...${NC}"
    sed -i "/$FIN_PATTERN/d" "$HOSTS_FILE"
    /etc/init.d/dnsmasq restart >/dev/null 2>&1
    log "Финские IP удалены"
    echo -e "${GREEN}Финские IP удалены!${NC}"
}

# ══════════════════════════════════════════════════════════════
# DISCORD HOSTS
# ══════════════════════════════════════════════════════════════
DC_MARK="#DiscordFixHosts"

dc_hosts_status() { grep -q "$DC_MARK" "$HOSTS_FILE" && return 0 || return 1; }

dc_hosts_add() {
    dc_hosts_status && { echo -e "${YELLOW}Discord hosts уже добавлены${NC}"; return; }
    cat >> "$HOSTS_FILE" << 'DCHOSTS'
#DiscordFixHosts
45.155.204.190 discord.com
45.155.204.190 www.discord.com
45.155.204.190 canary.discord.com
45.155.204.190 ptb.discord.com
45.155.204.190 discordapp.com
45.155.204.190 www.discordapp.com
45.155.204.190 discordapp.net
45.155.204.190 gateway.discord.gg
45.155.204.190 cdn.discordapp.com
45.155.204.190 media.discordapp.net
45.155.204.190 images-ext-1.discordapp.net
45.155.204.190 discord.gg
45.155.204.190 discord.media
45.155.204.190 dl.discordapp.net
DCHOSTS
    /etc/init.d/dnsmasq restart >/dev/null 2>&1
    log "Discord hosts добавлены"
    echo -e "${GREEN}Discord hosts добавлены!${NC}"
}

dc_hosts_remove() {
    echo -e "${CYAN}Удаляем Discord hosts...${NC}"
    sed -i "/$DC_MARK/,/^$/d" "$HOSTS_FILE"
    sed -i "/^45\.155\.204\.190 discord\|^45\.155\.204\.190 www\.discord\|^45\.155\.204\.190 canary\|^45\.155\.204\.190 ptb\|^45\.155\.204\.190 discordapp\|^45\.155\.204\.190 gateway\|^45\.155\.204\.190 cdn\|^45\.155\.204\.190 media\.discord\|^45\.155\.204\.190 images-ext\|^45\.155\.204\.190 discord\.gg\|^45\.155\.204\.190 discord\.media\|^45\.155\.204\.190 dl\.discord/d" "$HOSTS_FILE"
    /etc/init.d/dnsmasq restart >/dev/null 2>&1
    log "Discord hosts удалены"
    echo -e "${GREEN}Discord hosts удалены!${NC}"
}

# ══════════════════════════════════════════════════════════════
# UDP БЛОК — ключевой элемент для голосового чата
# ══════════════════════════════════════════════════════════════
UDP_MARK="##DISCORD_UDP_FIX##"

UDP_S1="--filter-udp=19294-19344,50000-50100\n--filter-l7=discord,stun\n--dpi-desync=fake\n--dpi-desync-repeats=6"
UDP_S2="--filter-udp=19294-19344,50000-50100\n--filter-l7=discord,stun\n--dpi-desync=fake\n--dpi-desync-repeats=8\n--dpi-desync-any-protocol=1"
UDP_S3="--filter-udp=50000-50099\n--filter-l7=discord,stun\n--dpi-desync=fake\n--dpi-desync-repeats=6\n--dpi-desync-cutoff=n4\n--dpi-desync-any-protocol=1\n--dpi-desync-fake-unknown-udp=/opt/zapret/files/fake/stun.bin"
UDP_S4="--filter-udp=50000-50099\n--filter-l7=discord,stun\n--dpi-desync=fake\n--dpi-desync-repeats=10\n--dpi-desync-cutoff=d2\n--dpi-desync-any-protocol=1\n--dpi-desync-fake-unknown-udp=/opt/zapret/files/fake/quic_initial_www_google_com.bin"
UDP_S5="--filter-udp=19294-19344,50000-50100\n--filter-l7=discord,stun\n--dpi-desync=fake\n--dpi-desync-repeats=6\n--dpi-desync-fake-unknown-udp=/opt/zapret/files/fake/quic_initial_www_google_com.bin"
UDP_S6="--filter-udp=50000-50099\n--filter-l7=discord,stun\n--dpi-desync=fake\n--dpi-desync-repeats=6\n--dpi-desync-cutoff=n3\n--dpi-desync-fake-unknown-udp=/opt/zapret/files/fake/stun.bin"
UDP_S7="--filter-udp=19294-19344,50000-50100\n--filter-l7=discord,stun\n--dpi-desync=fake\n--dpi-desync-repeats=4\n--dpi-desync-cutoff=d2\n--dpi-desync-any-protocol=1"

udp_block_present() { grep -q "$UDP_MARK" "$CONF" 2>/dev/null; }

udp_remove_block() {
    [ ! -f "$CONF" ] && return
    awk -v mark="$UDP_MARK" '
        $0 ~ mark { skip=1; next }
        skip && /^'"'"'$/ { skip=0; print; next }
        skip { next }
        { print }
    ' "$CONF" > /tmp/conf_udp_tmp && mv /tmp/conf_udp_tmp "$CONF"
}

udp_add_block() {
    local STRAT="$1"
    local LAST
    LAST=$(grep -n "^'$" "$CONF" | tail -n1 | cut -d: -f1)
    [ -n "$LAST" ] && sed -i "${LAST}d" "$CONF"
    printf '%s\n' "$UDP_MARK" "--new" >> "$CONF"
    printf '%b\n' "$STRAT" >> "$CONF"
    echo "'" >> "$CONF"
}

ports_udp_ensure() {
    for P in "19294-19344" "50000-50100"; do
        grep -q "NFQWS_PORTS_UDP.*$P" "$CONF" 2>/dev/null || \
            sed -i "/^[[:space:]]*option NFQWS_PORTS_UDP '/s/'$/ ,$P'/" "$CONF" 2>/dev/null
    done
    for P in "2053" "2083" "2087" "2096" "8443"; do
        grep -q "NFQWS_PORTS_TCP.*$P" "$CONF" 2>/dev/null || \
            sed -i "/^[[:space:]]*option NFQWS_PORTS_TCP '/s/'$/ ,$P'/" "$CONF" 2>/dev/null
    done
}

udp_current_info() {
    grep -A2 "$UDP_MARK" "$CONF" 2>/dev/null | grep "filter-udp" | head -n1
}

# ══════════════════════════════════════════════════════════════
# Dv СТРАТЕГИИ (discord.media, TCP 2053,2083,2087,2096,8443)
# ══════════════════════════════════════════════════════════════
Dv1='--filter-tcp=2053,2083,2087,2096,8443\n--hostlist-domains=discord.media\n--dpi-desync=multisplit\n--dpi-desync-split-seqovl=652\n--dpi-desync-split-pos=2\n--dpi-desync-split-seqovl-pattern=/opt/zapret/files/fake/tls_clienthello_www_google_com.bin'
Dv2='--filter-tcp=2053,2083,2087,2096,8443\n--hostlist-domains=discord.media\n--dpi-desync=fake,multisplit\n--dpi-desync-split-seqovl=681\n--dpi-desync-split-pos=1\n--dpi-desync-fooling=ts\n--dpi-desync-repeats=8\n--dpi-desync-split-seqovl-pattern=/opt/zapret/files/fake/tls_clienthello_www_google_com.bin\n--dpi-desync-fake-tls-mod=rnd,dupsid,sni=www.google.com'
Dv3='--filter-tcp=2053,2083,2087,2096,8443\n--hostlist-domains=discord.media\n--dpi-desync=fake\n--dpi-desync-repeats=6\n--dpi-desync-fooling=ts\n--dpi-desync-fake-tls=/opt/zapret/files/fake/tls_clienthello_www_google_com.bin\n--dpi-desync-fake-tls-mod=none'
Dv4='--filter-tcp=2053,2083,2087,2096,8443\n--hostlist-domains=discord.media\n--dpi-desync=fake,multisplit\n--dpi-desync-split-seqovl=652\n--dpi-desync-split-pos=2\n--dpi-desync-split-seqovl-pattern=/opt/zapret/files/fake/tls_clienthello_www_google_com.bin'
Dv5='--filter-tcp=2053,2083,2087,2096,8443\n--hostlist-domains=discord.media\n--dpi-desync=fake,multisplit\n--dpi-desync-repeats=6\n--dpi-desync-fooling=badseq\n--dpi-desync-badseq-increment=1000\n--dpi-desync-fake-tls=/opt/zapret/files/fake/tls_clienthello_www_google_com.bin'
Dv6='--filter-tcp=2053,2083,2087,2096,8443\n--hostlist-domains=discord.media\n--dpi-desync=multisplit\n--dpi-desync-split-seqovl=681\n--dpi-desync-split-pos=1\n--dpi-desync-split-seqovl-pattern=/opt/zapret/files/fake/tls_clienthello_www_google_com.bin'
Dv7='--filter-tcp=2053,2083,2087,2096,8443\n--hostlist-domains=discord.media\n--dpi-desync=multisplit\n--dpi-desync-split-pos=2,sniext+1\n--dpi-desync-split-seqovl=679\n--dpi-desync-split-seqovl-pattern=/opt/zapret/files/fake/tls_clienthello_www_google_com.bin'
Dv8='--filter-tcp=2053,2083,2087,2096,8443\n--hostlist-domains=discord.media\n--dpi-desync=fake\n--dpi-desync-fake-tls-mod=none\n--dpi-desync-repeats=6\n--dpi-desync-fooling=badseq\n--dpi-desync-badseq-increment=2'
Dv9='--filter-tcp=2053,2083,2087,2096,8443\n--hostlist-domains=discord.media\n--dpi-desync=fake,fakedsplit\n--dpi-desync-split-pos=1\n--dpi-desync-fooling=badseq\n--dpi-desync-badseq-increment=2\n--dpi-desync-repeats=8\n--dpi-desync-fake-tls-mod=rnd,dupsid,sni=www.google.com'
Dv10='--filter-tcp=2053,2083,2087,2096,8443\n--hostlist-domains=discord.media\n--dpi-desync=fake,multisplit\n--dpi-desync-split-seqovl=681\n--dpi-desync-split-pos=1\n--dpi-desync-fooling=badseq\n--dpi-desync-badseq-increment=10000000\n--dpi-desync-repeats=8\n--dpi-desync-split-seqovl-pattern=/opt/zapret/files/fake/tls_clienthello_www_google_com.bin\n--dpi-desync-fake-tls-mod=rnd,dupsid,sni=www.google.com'
Dv11='--filter-tcp=2053,2083,2087,2096,8443\n--hostlist-domains=discord.media\n--dpi-desync=fake,multisplit\n--dpi-desync-split-seqovl=681\n--dpi-desync-split-pos=1\n--dpi-desync-fooling=ts\n--dpi-desync-repeats=8\n--dpi-desync-split-seqovl-pattern=/opt/zapret/files/fake/tls_clienthello_www_google_com.bin\n--dpi-desync-fake-tls-mod=rnd,dupsid,sni=www.google.com'
Dv12='--filter-tcp=2053,2083,2087,2096,8443\n--hostlist-domains=discord.media\n--dpi-desync=fake\n--dpi-desync-repeats=6\n--dpi-desync-fooling=badseq\n--dpi-desync-badseq-increment=2\n--dpi-desync-fake-tls=/opt/zapret/files/fake/tls_clienthello_www_google_com.bin'
Dv13='--filter-tcp=2053,2083,2087,2096,8443\n--hostlist-domains=discord.media\n--dpi-desync=fake\n--dpi-desync-repeats=6\n--dpi-desync-fooling=ts\n--dpi-desync-fake-tls=/opt/zapret/files/fake/tls_clienthello_www_google_com.bin'
Dv14='--filter-tcp=2053,2083,2087,2096,8443\n--hostlist-domains=discord.media\n--dpi-desync=fake,fakedsplit\n--dpi-desync-repeats=6\n--dpi-desync-fooling=ts\n--dpi-desync-fakedsplit-pattern=0x00\n--dpi-desync-fake-tls=/opt/zapret/files/fake/tls_clienthello_www_google_com.bin'
Dv15='--filter-tcp=2053,2083,2087,2096,8443\n--hostlist-domains=discord.media\n--dpi-desync=fake,multidisorder\n--dpi-desync-split-pos=1,midsld\n--dpi-desync-repeats=11\n--dpi-desync-fooling=badseq\n--dpi-desync-fake-tls=0x00000000\n--dpi-desync-fake-tls=/opt/zapret/files/fake/tls_clienthello_www_google_com.bin\n--dpi-desync-fake-tls-mod=rnd,dupsid,sni=www.google.com'
Dv16='--filter-tcp=2053,2083,2087,2096,8443\n--hostlist-domains=discord.media\n--dpi-desync=fake,hostfakesplit\n--dpi-desync-fake-tls-mod=rnd,dupsid,sni=www.google.com\n--dpi-desync-hostfakesplit-mod=host=www.google.com,altorder=1\n--dpi-desync-fooling=ts'
Dv17='--filter-tcp=2053,2083,2087,2096,8443\n--hostlist-domains=discord.media\n--dpi-desync=hostfakesplit\n--dpi-desync-repeats=4\n--dpi-desync-fooling=ts\n--dpi-desync-hostfakesplit-mod=host=www.google.com'
DV_TOTAL=17

dv_current() {
    grep -o '#Dv[0-9]*' "$CONF" 2>/dev/null | head -n1 | sed 's/#Dv//'
}

dv_remove_block() {
    [ ! -f "$CONF" ] && return
    sed -i '/^#Dv[0-9]*/d' "$CONF"
    START=$(grep -n -E '^[[:space:]]*--filter-tcp=2053,2083,2087,2096,8443' "$CONF" | head -n1 | cut -d: -f1)
    [ -z "$START" ] && return
    END=$(tail -n +"$START" "$CONF" | grep -n -m1 -E "^--new$|^'$" | cut -d: -f1)
    END=$((START + END - 1))
    [ "$END" -ge "$START" ] && sed -i "${START},$((END-1))d" "$CONF"
}

dv_apply() {
    local NUM="$1"
    eval "local STRAT=\$Dv$NUM"
    [ -z "$STRAT" ] && echo -e "${RED}Dv$NUM не найдена!${NC}" && return 1
    dv_remove_block
    local LAST
    LAST=$(grep -n "^'$" "$CONF" | tail -n1 | cut -d: -f1)
    [ -n "$LAST" ] && sed -i "${LAST}d" "$CONF"
    printf '%s\n' "#Dv$NUM" >> "$CONF"
    printf '%b\n' "$STRAT" >> "$CONF"
    echo "'" >> "$CONF"
    log "Dv$NUM применена"
}

# ══════════════════════════════════════════════════════════════
# 50-SCRIPT.SH
# ══════════════════════════════════════════════════════════════
script50_current() {
    [ -f "$CUSTOM_DIR/50-script.sh" ] || { echo "нет"; return; }
    local line
    line=$(head -n1 "$CUSTOM_DIR/50-script.sh")
    case "$line" in
        *QUIC*)              echo "50-quic4all" ;;
        *stun*)              echo "50-stun4all" ;;
        *"discord media"*)   echo "50-discord-media" ;;
        *"discord subnets"*) echo "50-discord" ;;
        *)                   echo "другой" ;;
    esac
}

script50_install() {
    local NAME="$1" URL="$2"
    mkdir -p "$CUSTOM_DIR"
    echo -e "${CYAN}Скачиваем $NAME...${NC}"
    if wget -q -U "Mozilla/5.0" -O "$CUSTOM_DIR/50-script.sh" "$URL"; then
        sed -i "/DISABLE_CUSTOM/s/'1'/'0'/" "$CONF" 2>/dev/null
        ZAPRET_RESTART
        log "50-script $NAME установлен"
        echo -e "${GREEN}Скрипт $NAME установлен!${NC}"
    else
        echo -e "${RED}Ошибка загрузки $NAME!${NC}"
    fi
}

script50_remove() {
    rm -f "$CUSTOM_DIR/50-script.sh"
    sed -i "/DISABLE_CUSTOM/s/'0'/'1'/" "$CONF" 2>/dev/null
    ZAPRET_RESTART
    log "50-script удалён"
    echo -e "${GREEN}Скрипт удалён!${NC}"
}

# ══════════════════════════════════════════════════════════════
# ТЕСТЫ
# ══════════════════════════════════════════════════════════════
DISCORD_VOICE_IPS="162.159.128.233 162.159.130.234 162.159.129.234 35.227.25.196"

test_tcp() {
    local URLS="discord.com discordapp.com gateway.discord.gg cdn.discordapp.com discordstatus.com"
    echo -e "\n${CYAN}Тест TCP (текстовый чат, API)${NC}"; SEP
    for D in $URLS; do
        if curl -sL --connect-timeout 4 --max-time 6 \
               --range 0-512 -o /dev/null "https://$D" 2>/dev/null; then
            echo -e "  ${GREEN}[ OK ]${NC} $D"
        else
            echo -e "  ${RED}[FAIL]${NC} $D"
        fi
    done
    SEP
}

test_voice_ping() {
    echo -e "\n${CYAN}Ping Discord Voice серверов${NC}"; SEP
    for IP in $DISCORD_VOICE_IPS; do
        local MS
        MS=$(ping -c2 -W2 "$IP" 2>/dev/null | grep -E 'rtt|round-trip' | awk -F'/' '{printf "%.0f", $5}')
        if [ -n "$MS" ]; then
            echo -e "  ${GREEN}[ OK ]${NC} $IP — ${CYAN}${MS}ms${NC}"
        else
            echo -e "  ${RED}[FAIL]${NC} $IP — недоступен"
        fi
    done
    SEP
}

test_config() {
    echo -e "\n${CYAN}Проверка конфигурации${NC}"; SEP
    if grep -q "50000" "$CONF" 2>/dev/null; then
        echo -e "  ${GREEN}[ OK ]${NC} UDP 50000-50100 в NFQWS_PORTS_UDP"
    else
        echo -e "  ${RED}[!!]${NC}  UDP 50000-50100 ${RED}ОТСУТСТВУЕТ${NC} — голос не пройдёт!"
    fi
    if grep -q "19294" "$CONF" 2>/dev/null; then
        echo -e "  ${GREEN}[ OK ]${NC} UDP 19294-19344 (STUN) в NFQWS_PORTS_UDP"
    else
        echo -e "  ${YELLOW}[~~]${NC}  UDP 19294-19344 не задан (опционально)"
    fi
    if udp_block_present; then
        echo -e "  ${GREEN}[ OK ]${NC} UDP блок стратегии установлен"
        echo -e "           ${DGRAY}$(udp_current_info)${NC}"
    else
        echo -e "  ${RED}[!!]${NC}  UDP блок ${RED}ОТСУТСТВУЕТ${NC} — причина 5000ms!"
    fi
    if grep -q "2053\|8443" "$CONF" 2>/dev/null; then
        echo -e "  ${GREEN}[ OK ]${NC} Порты discord.media (2053/8443) в NFQWS_PORTS_TCP"
    else
        echo -e "  ${RED}[!!]${NC}  Порты discord.media ${RED}ОТСУТСТВУЮТ${NC}"
    fi
    local DV_N
    DV_N=$(dv_current)
    if [ -n "$DV_N" ]; then
        echo -e "  ${GREEN}[ OK ]${NC} Dv стратегия: ${CYAN}Dv$DV_N${NC}"
    else
        echo -e "  ${YELLOW}[~~]${NC}  Dv стратегия не задана"
    fi
    fin_status \
        && echo -e "  ${GREEN}[ OK ]${NC} Финские IP в hosts" \
        || echo -e "  ${RED}[!!]${NC}  Финские IP ${RED}ОТСУТСТВУЮТ${NC} — причина 5000ms!"
    local NFQ_RUN
    NFQ_RUN=$(pgrep -f nfqws 2>/dev/null | wc -l)
    if [ "$NFQ_RUN" -ge 1 ]; then
        echo -e "  ${GREEN}[ OK ]${NC} nfqws запущен ($NFQ_RUN процессов)"
    else
        echo -e "  ${RED}[!!]${NC}  nfqws ${RED}не запущен!${NC}"
    fi
    SEP
}

full_test() {
    HEADER "Полный тест Discord"
    test_tcp
    test_voice_ping
    test_config
    PAUSE
}

# ══════════════════════════════════════════════════════════════
# АВТО-ТЕСТ Dv СТРАТЕГИЙ
# ══════════════════════════════════════════════════════════════
auto_test_dv() {
    zapret_check || return
    HEADER "Авто-тест Dv стратегий (discord.media)"
    echo -e "${YELLOW}Перебираем все $DV_TOTAL стратегий.${NC}"
    echo -e "${YELLOW}При успехе — предложим применить.${NC}\n"
    cp "$CONF" /tmp/dv_backup.conf

    BEST_DV=""; BEST_OK=0
    i=1
    while [ "$i" -le "$DV_TOTAL" ]; do
        echo -e "${CYAN}[$i/$DV_TOTAL] Dv$i...${NC}"
        cp /tmp/dv_backup.conf "$CONF"
        dv_apply "$i"
        ZAPRET_RESTART

        OK=0
        for D in discord.com discordapp.com gateway.discord.gg; do
            curl -sL --connect-timeout 3 --max-time 5 \
                 --range 0-512 -o /dev/null "https://$D" 2>/dev/null \
                 && OK=$((OK+1))
        done

        if [ "$OK" -ge 2 ]; then
            echo -e "  ${GREEN}Dv$i — работает! ($OK/3)${NC}"
            [ "$OK" -gt "$BEST_OK" ] && { BEST_OK=$OK; BEST_DV=$i; }
            echo -ne "  ${YELLOW}Enter — применить, N — продолжить тест: ${NC}"
            read -r ANS </dev/tty
            case "$ANS" in n|N) ;; *) break ;; esac
        else
            echo -e "  ${RED}Dv$i — нет ($OK/3)${NC}"
        fi
        i=$((i+1))
    done

    cp /tmp/dv_backup.conf "$CONF"
    if [ -n "$BEST_DV" ]; then
        echo -e "\n${GREEN}Применяем Dv$BEST_DV...${NC}"
        dv_apply "$BEST_DV"
        ZAPRET_RESTART
        echo -e "${GREEN}Dv$BEST_DV применена!${NC}"
    else
        ZAPRET_RESTART
        echo -e "\n${RED}Рабочая Dv стратегия не найдена.${NC}"
    fi
    PAUSE
}

# ══════════════════════════════════════════════════════════════
# АВТО-ТЕСТ UDP СТРАТЕГИЙ
# ══════════════════════════════════════════════════════════════
auto_test_udp() {
    zapret_check || return
    HEADER "Авто-тест UDP стратегий (голосовой чат)"
    echo -e "${YELLOW}Тестируем 7 UDP стратегий.${NC}\n"
    cp "$CONF" /tmp/udp_backup.conf

    BEST_S=""; BEST_OK=0; BEST_I=0
    i=1
    for S in "$UDP_S1" "$UDP_S2" "$UDP_S3" "$UDP_S4" "$UDP_S5" "$UDP_S6" "$UDP_S7"; do
        echo -e "${CYAN}[$i/7] UDP стратегия $i...${NC}"
        cp /tmp/udp_backup.conf "$CONF"
        udp_remove_block
        ports_udp_ensure
        udp_add_block "$S"
        ZAPRET_RESTART

        OK=0
        for D in discord.com discordapp.com; do
            curl -sL --connect-timeout 3 --max-time 5 \
                 --range 0-512 -o /dev/null "https://$D" 2>/dev/null \
                 && OK=$((OK+1))
        done
        echo -e "  ${CYAN}TCP-тест: $OK/2${NC}"
        [ "$OK" -gt "$BEST_OK" ] && { BEST_OK=$OK; BEST_S="$S"; BEST_I=$i; }
        i=$((i+1))
    done

    cp /tmp/udp_backup.conf "$CONF"
    if [ -n "$BEST_S" ]; then
        echo -e "\n${GREEN}Лучшая: стратегия $BEST_I (счёт: $BEST_OK/2)${NC}"
        udp_remove_block; ports_udp_ensure; udp_add_block "$BEST_S"
        ZAPRET_RESTART
        echo -e "${GREEN}UDP стратегия $BEST_I применена!${NC}"
    else
        ZAPRET_RESTART
        echo -e "\n${RED}Ни одна стратегия не сработала.${NC}"
    fi
    PAUSE
}

# ══════════════════════════════════════════════════════════════
# БЫСТРЫЙ ФИКС
# ══════════════════════════════════════════════════════════════
quick_fix() {
    zapret_check || return
    HEADER "Быстрый фикс Discord 5000ms"
    cp "$CONF"       "$BACKUP_DIR/zapret.bak"  2>/dev/null
    cp "$HOSTS_FILE" "$BACKUP_DIR/hosts.bak"   2>/dev/null

    echo -e "${CYAN}[1/5]${NC} Финские IP"
    fin_status || fin_add

    echo -e "\n${CYAN}[2/5]${NC} Discord hosts"
    dc_hosts_status || dc_hosts_add

    echo -e "\n${CYAN}[3/5]${NC} UDP блок (стратегия 1)"
    udp_remove_block; ports_udp_ensure; udp_add_block "$UDP_S1"

    echo -e "\n${CYAN}[4/5]${NC} Dv1 для discord.media"
    dv_apply 1

    echo -e "\n${CYAN}[5/5]${NC} Перезапуск Zapret"
    ZAPRET_RESTART

    echo -e "\n${GREEN}══ Быстрый фикс применён! ══${NC}\n"
    echo -e "  ✓ Финские IP (finland10000-10199.discord.media)"
    echo -e "  ✓ Discord hosts (45.155.204.190)"
    echo -e "  ✓ UDP: filter-udp=19294-19344,50000-50100 + fake×6"
    echo -e "  ✓ Dv1 стратегия для discord.media"
    echo -e "  ✓ Порты 19294-19344,50000-50100,2053,8443 добавлены\n"
    echo -e "${YELLOW}Если 5000ms остался — используйте авто-тест стратегий.${NC}"
    log "Быстрый фикс применён"
    PAUSE
}

# ══════════════════════════════════════════════════════════════
# РЕЗЕРВНАЯ КОПИЯ
# ══════════════════════════════════════════════════════════════
backup_save() {
    cp "$CONF"       "$BACKUP_DIR/zapret.bak" 2>/dev/null
    cp "$HOSTS_FILE" "$BACKUP_DIR/hosts.bak"  2>/dev/null
    date '+%d.%m.%Y %H:%M' > "$BACKUP_DIR/date.txt"
    log "Бэкап сохранён"
    echo -e "\n${GREEN}Резервная копия сохранена!${NC}\n"; PAUSE
}

backup_restore() {
    [ ! -f "$BACKUP_DIR/zapret.bak" ] && {
        echo -e "\n${RED}Резервная копия не найдена!${NC}\n"; PAUSE; return; }
    cp "$BACKUP_DIR/zapret.bak" "$CONF"
    [ -f "$BACKUP_DIR/hosts.bak" ] && cp "$BACKUP_DIR/hosts.bak" "$HOSTS_FILE"
    /etc/init.d/dnsmasq restart >/dev/null 2>&1
    ZAPRET_RESTART
    log "Бэкап восстановлен"
    echo -e "\n${GREEN}Настройки восстановлены!${NC}\n"; PAUSE
}

# ══════════════════════════════════════════════════════════════
# FLOW OFFLOADING
# ══════════════════════════════════════════════════════════════
fo_get() {
    FO=$(uci get firewall.@defaults[0].flow_offloading 2>/dev/null)
    FOHW=$(uci get firewall.@defaults[0].flow_offloading_hw 2>/dev/null)
    FIX_ON=$(grep -q 'ct original packets ge 30' \
        /usr/share/firewall4/templates/ruleset.uc 2>/dev/null && echo 1 || echo 0)
}

fo_toggle_fix() {
    fo_get
    if [ "$FIX_ON" = "1" ]; then
        sed -i 's/ct original packets ge 30 flow offload @ft;/meta l4proto { tcp, udp } flow offload @ft;/' \
            /usr/share/firewall4/templates/ruleset.uc 2>/dev/null
        fw4 restart >/dev/null 2>&1
        echo -e "${GREEN}FIX для Flow Offloading отключён!${NC}"
    else
        sed -i 's/meta l4proto { tcp, udp } flow offload @ft;/meta l4proto { tcp, udp } ct original packets ge 30 flow offload @ft;/' \
            /usr/share/firewall4/templates/ruleset.uc 2>/dev/null
        fw4 restart >/dev/null 2>&1
        echo -e "${GREEN}FIX для Flow Offloading применён!${NC}"
    fi
    log "Flow Offloading FIX изменён"
}

# ══════════════════════════════════════════════════════════════
# ПОКАЗ СОСТОЯНИЯ
# ══════════════════════════════════════════════════════════════
show_status() {
    fo_get
    # Zapret
    if zapret_installed; then
        /etc/init.d/zapret status >/dev/null 2>&1 \
            && ZST="${GREEN}запущен${NC}" || ZST="${RED}остановлен${NC}"
        NFQ=$(pgrep -f nfqws 2>/dev/null | wc -l)
        echo -e "${YELLOW}Zapret:${NC}              $ZST ${DGRAY}[nfqws: $NFQ]${NC}"
    else
        echo -e "${YELLOW}Zapret:${NC}              ${RED}не установлен${NC}"
    fi

    # Dv
    local DV_N; DV_N=$(dv_current)
    [ -n "$DV_N" ] \
        && echo -e "${YELLOW}Dv стратегия:${NC}        ${CYAN}Dv$DV_N${NC}" \
        || echo -e "${YELLOW}Dv стратегия:${NC}        ${RED}не задана${NC}"

    # UDP
    if udp_block_present; then
        echo -e "${YELLOW}UDP voice блок:${NC}      ${GREEN}установлен${NC} ${DGRAY}($(udp_current_info))${NC}"
    else
        echo -e "${YELLOW}UDP voice блок:${NC}      ${RED}ОТСУТСТВУЕТ${NC} ${YELLOW}← причина 5000ms!${NC}"
    fi

    # Финские IP
    fin_status \
        && echo -e "${YELLOW}Финские IP:${NC}          ${GREEN}добавлены${NC}" \
        || echo -e "${YELLOW}Финские IP:${NC}          ${RED}не добавлены${NC} ${YELLOW}← причина 5000ms!${NC}"

    # Discord hosts
    dc_hosts_status \
        && echo -e "${YELLOW}Discord hosts:${NC}       ${GREEN}добавлены${NC}" \
        || echo -e "${YELLOW}Discord hosts:${NC}       ${YELLOW}не добавлены${NC}"

    # 50-script
    local SC; SC=$(script50_current)
    [ "$SC" != "нет" ] \
        && echo -e "${YELLOW}50-script:${NC}           ${GREEN}$SC${NC}" \
        || echo -e "${YELLOW}50-script:${NC}           ${YELLOW}не установлен${NC}"

    # Flow Offloading
    if [ "$FO" = "1" ] || [ "$FOHW" = "1" ]; then
        [ "$FIX_ON" = "1" ] \
            && echo -e "${YELLOW}Flow Offloading:${NC}     ${RED}включён${NC} + ${GREEN}FIX применён${NC}" \
            || echo -e "${YELLOW}Flow Offloading:${NC}     ${RED}включён — возможная причина 5000ms!${NC}"
    fi

    # Бэкап
    [ -f "$BACKUP_DIR/date.txt" ] \
        && echo -e "${YELLOW}Резервная копия:${NC}     ${GREEN}$(cat "$BACKUP_DIR/date.txt")${NC}"
    echo
}

# ══════════════════════════════════════════════════════════════
# МЕНЮ UDP
# ══════════════════════════════════════════════════════════════
menu_udp() {
    zapret_check || return
    while true; do
        HEADER "UDP стратегии — голосовые каналы"
        local CUR; CUR=$(udp_current_info)
        [ -n "$CUR" ] && echo -e "${YELLOW}Текущая:${NC} ${CYAN}$CUR${NC}\n"

        echo -e "${CYAN}1)${NC} udp=19294-19344,50000-50100 + fake×6           ${YELLOW}[рекомендуется]${NC}"
        echo -e "${CYAN}2)${NC} udp=19294-19344,50000-50100 + fake×8 + any-protocol"
        echo -e "${CYAN}3)${NC} udp=50000-50099 + fake×6 + cutoff=n4 + stun.bin"
        echo -e "${CYAN}4)${NC} udp=50000-50099 + fake×10 + cutoff=d2 + quic.bin"
        echo -e "${CYAN}5)${NC} udp=19294-19344,50000-50100 + fake×6 + quic.bin"
        echo -e "${CYAN}6)${NC} udp=50000-50099 + fake×6 + cutoff=n3 + stun.bin"
        echo -e "${CYAN}7)${NC} udp=19294-19344,50000-50100 + fake×4 + cutoff=d2"
        echo -e "${CYAN}8)${NC} ${GREEN}Авто-тест всех UDP стратегий${NC}"
        udp_block_present && echo -e "${CYAN}D)${NC} ${RED}Удалить UDP блок${NC}"
        echo -e "${CYAN}Enter)${NC} Назад"
        echo -ne "\n${YELLOW}Выбор: ${NC}"; read -r C

        local S=""
        case "$C" in
            1) S="$UDP_S1" ;; 2) S="$UDP_S2" ;; 3) S="$UDP_S3" ;;
            4) S="$UDP_S4" ;; 5) S="$UDP_S5" ;; 6) S="$UDP_S6" ;;
            7) S="$UDP_S7" ;; 8) auto_test_udp; continue ;;
            d|D)
                udp_remove_block; ZAPRET_RESTART
                echo -e "\n${GREEN}UDP блок удалён!${NC}"; PAUSE; continue ;;
            '') return ;;
            *) continue ;;
        esac
        echo -e "\n${CYAN}Применяем UDP стратегию $C...${NC}"
        udp_remove_block; ports_udp_ensure; udp_add_block "$S"
        ZAPRET_RESTART
        echo -e "${GREEN}UDP стратегия $C применена!${NC}"
        PAUSE
    done
}

# ══════════════════════════════════════════════════════════════
# МЕНЮ Dv
# ══════════════════════════════════════════════════════════════
menu_dv() {
    zapret_check || return
    while true; do
        HEADER "Dv стратегии — discord.media"
        local DV_N; DV_N=$(dv_current)
        [ -n "$DV_N" ] \
            && echo -e "${YELLOW}Текущая Dv:${NC} ${CYAN}Dv$DV_N${NC}\n" \
            || echo -e "${YELLOW}Текущая Dv:${NC} ${RED}не задана${NC}\n"

        echo -e "${CYAN}1-$DV_TOTAL)${NC} Применить Dv1–Dv$DV_TOTAL"
        echo -e "${CYAN}A)${NC} ${GREEN}Авто-тест всех Dv стратегий${NC}"
        [ -n "$DV_N" ] && echo -e "${CYAN}D)${NC} ${RED}Удалить Dv блок${NC}"
        echo -e "${CYAN}Enter)${NC} Назад"
        echo -ne "\n${YELLOW}Введите номер (1-$DV_TOTAL): ${NC}"; read -r C

        case "$C" in
            a|A) auto_test_dv; continue ;;
            d|D)
                dv_remove_block; ZAPRET_RESTART
                echo -e "\n${GREEN}Dv блок удалён!${NC}"; PAUSE; continue ;;
            '') return ;;
            *[!0-9]*) return ;;
        esac
        if [ "$C" -ge 1 ] 2>/dev/null && [ "$C" -le "$DV_TOTAL" ] 2>/dev/null; then
            echo -e "\n${CYAN}Применяем Dv$C...${NC}"
            dv_apply "$C"; ZAPRET_RESTART
            echo -e "${GREEN}Dv$C применена!${NC}"
        else
            echo -e "${RED}Неверный номер!${NC}"
        fi
        PAUSE
    done
}

# ══════════════════════════════════════════════════════════════
# МЕНЮ 50-SCRIPT
# ══════════════════════════════════════════════════════════════
menu_50script() {
    zapret_check || return
    local BASE="https://raw.githubusercontent.com/bol-van/zapret/master/init.d/custom.d.examples.linux"
    local DC_URL="https://raw.githubusercontent.com/bol-van/zapret/v70.5/init.d/custom.d.examples.linux/50-discord"
    while true; do
        HEADER "50-script (custom.d)"
        local SC; SC=$(script50_current)
        echo -e "${YELLOW}Установлен:${NC} ${CYAN}$SC${NC}\n"
        echo -e "${CYAN}1)${NC} ${GREEN}50-stun4all${NC}       — обход STUN ${YELLOW}[рекомендуется для голоса]${NC}"
        echo -e "${CYAN}2)${NC} ${GREEN}50-quic4all${NC}       — обход QUIC"
        echo -e "${CYAN}3)${NC} ${GREEN}50-discord-media${NC}  — обход discord.media"
        echo -e "${CYAN}4)${NC} ${GREEN}50-discord${NC}        — обход Discord subnets"
        [ "$SC" != "нет" ] && echo -e "${CYAN}D)${NC} ${RED}Удалить скрипт${NC}"
        echo -e "${CYAN}Enter)${NC} Назад"
        echo -ne "\n${YELLOW}Выбор: ${NC}"; read -r C
        case "$C" in
            1) script50_install "50-stun4all"      "$BASE/50-stun4all" ;;
            2) script50_install "50-quic4all"      "$BASE/50-quic4all" ;;
            3) script50_install "50-discord-media" "$BASE/50-discord-media" ;;
            4) script50_install "50-discord"       "$DC_URL" ;;
            d|D) script50_remove ;;
            '') return ;;
        esac
        PAUSE
    done
}

# ══════════════════════════════════════════════════════════════
# МЕНЮ HOSTS
# ══════════════════════════════════════════════════════════════
menu_hosts() {
    while true; do
        HEADER "Управление hosts"
        fin_status      && FIN_TXT="${RED}Удалить${NC}" || FIN_TXT="${GREEN}Добавить${NC}"
        dc_hosts_status && DC_TXT="${RED}Удалить${NC}"  || DC_TXT="${GREEN}Добавить${NC}"
        echo -e "${CYAN}1)${NC} $FIN_TXT финские IP (finland*****.discord.media → 104.25.158.178)"
        echo -e "${CYAN}2)${NC} $DC_TXT Discord hosts (discord.com, discordapp.com, gateway...)"
        echo -e "${CYAN}3)${NC} ${GREEN}Показать Discord-записи в hosts${NC}"
        echo -e "${CYAN}4)${NC} ${RED}Сбросить hosts к стандартному виду${NC}"
        echo -e "${CYAN}Enter)${NC} Назад"
        echo -ne "\n${YELLOW}Выбор: ${NC}"; read -r C
        case "$C" in
            1) echo; fin_status      && fin_remove   || fin_add;    PAUSE ;;
            2) echo; dc_hosts_status && dc_hosts_remove || dc_hosts_add; PAUSE ;;
            3)
                HEADER "Discord-записи в hosts"
                grep -iE "discord|45\.155\.204\.190|104\.25\.158" "$HOSTS_FILE" | head -40 \
                    || echo "(нет)"
                PAUSE ;;
            4)
                echo -ne "\n${RED}Сбросить hosts? (y/N): ${NC}"; read -r A
                case "$A" in y|Y)
                    printf '%s\n' "127.0.0.1 localhost" "" \
                        "::1 localhost ip6-localhost ip6-loopback" \
                        "ff02::1 ip6-allnodes" "ff02::2 ip6-allrouters" \
                        > "$HOSTS_FILE"
                    /etc/init.d/dnsmasq restart >/dev/null 2>&1
                    log "hosts сброшен"
                    echo -e "${GREEN}hosts сброшен!${NC}"; PAUSE ;;
                esac ;;
            '') return ;;
        esac
    done
}

# ══════════════════════════════════════════════════════════════
# МЕНЮ ДИАГНОСТИКИ
# ══════════════════════════════════════════════════════════════
menu_diag() {
    while true; do
        HEADER "Диагностика Discord"
        echo -e "${CYAN}1)${NC} Полный тест соединения"
        echo -e "${CYAN}2)${NC} Проверка конфигурации Zapret"
        echo -e "${CYAN}3)${NC} Ping Discord Voice серверов"
        echo -e "${CYAN}4)${NC} Показать текущий конфиг Discord"
        echo -e "${CYAN}5)${NC} Flow Offloading — статус и FIX"
        echo -e "${CYAN}6)${NC} Системная информация"
        echo -e "${CYAN}7)${NC} Просмотр лога"
        echo -e "${CYAN}Enter)${NC} Назад"
        echo -ne "\n${YELLOW}Выбор: ${NC}"; read -r C
        case "$C" in
            1) full_test ;;
            2) HEADER "Конфигурация Zapret"; test_config; PAUSE ;;
            3) HEADER "Ping"; test_voice_ping; PAUSE ;;
            4)
                HEADER "Discord-часть конфига Zapret"
                echo -e "${CYAN}PORTS_UDP:${NC}"
                grep "NFQWS_PORTS_UDP" "$CONF" 2>/dev/null | sed "s/.*'\(.*\)'.*/  \1/" || echo "  (нет)"
                echo -e "\n${CYAN}PORTS_TCP:${NC}"
                grep "NFQWS_PORTS_TCP" "$CONF" 2>/dev/null | sed "s/.*'\(.*\)'.*/  \1/" || echo "  (нет)"
                echo -e "\n${CYAN}Блок Dv (discord.media):${NC}"
                grep -A12 "#Dv" "$CONF" 2>/dev/null | head -14 || echo "  (нет)"
                echo -e "\n${CYAN}UDP блок:${NC}"
                grep -A10 "$UDP_MARK" "$CONF" 2>/dev/null | head -10 || echo "  (нет)"
                PAUSE ;;
            5)
                HEADER "Flow Offloading"
                fo_get
                if [ "$FO" = "1" ] || [ "$FOHW" = "1" ]; then
                    echo -e "${RED}Flow Offloading ВКЛЮЧЁН!${NC}"
                    echo -e "${YELLOW}Это мешает корректной работе nfqws и UDP.${NC}"
                    [ "$FIX_ON" = "1" ] \
                        && echo -e "FIX: ${GREEN}применён${NC}" \
                        || echo -e "FIX: ${RED}не применён!${NC}"
                    echo -ne "\n${YELLOW}Применить/убрать FIX? (y/N): ${NC}"; read -r A
                    case "$A" in y|Y) fo_toggle_fix ;; esac
                else
                    echo -e "${GREEN}Flow Offloading выключен. OK.${NC}"
                fi
                PAUSE ;;
            6)
                HEADER "Системная информация"
                MODEL=$(cat /tmp/sysinfo/model 2>/dev/null || echo "?")
                ARCH=$(grep DISTRIB_ARCH /etc/openwrt_release 2>/dev/null | cut -d"'" -f2)
                OWRT=$(grep DISTRIB_RELEASE /etc/openwrt_release 2>/dev/null | cut -d"'" -f2)
                echo -e "Модель:   $MODEL"
                echo -e "Архит.:   $ARCH"
                echo -e "OpenWrt:  $OWRT"
                echo -e "PKG:      $PKG\n"
                df -h /tmp / 2>/dev/null | awk 'NR>1{printf "%-6s used:%-6s free:%s\n",$6,$3,$4}'
                PAUSE ;;
            7)
                HEADER "Лог"
                [ -s "$LOG_FILE" ] && cat "$LOG_FILE" || echo "(пусто)"
                echo -e "\n${CYAN}nfqws/zapret из logread:${NC}"
                logread 2>/dev/null | grep -iE "nfqws|discord|zapret" | tail -25 \
                    || echo "(logread недоступен)"
                PAUSE ;;
            '') return ;;
        esac
    done
}

# ══════════════════════════════════════════════════════════════
# СБРОС
# ══════════════════════════════════════════════════════════════
reset_all() {
    HEADER "Сброс всех настроек Discord Fix"
    echo -e "${RED}Будет удалено:${NC}"
    echo -e "  — финские IP из hosts"
    echo -e "  — Discord hosts из hosts"
    echo -e "  — UDP блок из конфига Zapret"
    echo -e "  — Dv блок из конфига Zapret"
    echo -e "  — 50-script.sh"
    echo -ne "\n${YELLOW}Продолжить? (y/N): ${NC}"; read -r A
    case "$A" in y|Y) ;; *) return ;; esac

    cp "$CONF" "$BACKUP_DIR/before_reset.bak" 2>/dev/null

    fin_status      && fin_remove
    dc_hosts_status && dc_hosts_remove
    udp_remove_block
    dv_remove_block
    [ -f "$CUSTOM_DIR/50-script.sh" ] && script50_remove
    ZAPRET_RESTART
    log "Полный сброс Discord Fix"
    echo -e "\n${GREEN}Все настройки сброшены!${NC}\n"; PAUSE
}

# ══════════════════════════════════════════════════════════════
# ГЛАВНОЕ МЕНЮ
# ══════════════════════════════════════════════════════════════
# Установка как утилиты
cp "$0" /usr/bin/discord_fix.sh 2>/dev/null && chmod +x /usr/bin/discord_fix.sh 2>/dev/null
printf '#!/bin/sh\nsh /usr/bin/discord_fix.sh\n' > /usr/bin/dcfix 2>/dev/null
chmod +x /usr/bin/dcfix 2>/dev/null

main_menu() {
    while true; do
        clear
        echo -e "╔══════════════════════════════════════════════╗"
        echo -e "║  ${MAGENTA}Discord Voice Fix Manager ${DGRAY}v$SCRIPT_VERSION by StressOzz${NC}  ║"
        echo -e "║  ${DGRAY}Решение 5000ms ping в голосовых каналах${NC}       ║"
        echo -e "╚══════════════════════════════════════════════╝"
        SEP
        show_status
        SEP
        echo -e "${CYAN}1)${NC} ⚡ ${GREEN}Быстрый фикс${NC}         (всё сразу — рекомендуется)"
        echo -e "${CYAN}2)${NC} 🎤 ${GREEN}UDP стратегии${NC}         (голосовые каналы)"
        echo -e "${CYAN}3)${NC} 🎯 ${GREEN}Dv стратегии${NC}          (discord.media, TCP 2053/8443)"
        echo -e "${CYAN}4)${NC} 📜 ${GREEN}50-script${NC}             (stun4all / quic4all / discord)"
        echo -e "${CYAN}5)${NC} 🗺  ${GREEN}hosts${NC}                 (финские IP, Discord домены)"
        echo -e "${CYAN}6)${NC} 🔍 ${GREEN}Диагностика и тесты${NC}"
        echo -e "${CYAN}7)${NC} 💾 ${GREEN}Резервная копия${NC}        / восстановление"
        if zapret_installed; then
            pgrep -f /opt/zapret >/dev/null 2>&1 \
                && echo -e "${CYAN}8)${NC} ⏹  ${RED}Остановить${NC} Zapret" \
                || echo -e "${CYAN}8)${NC} ▶  ${GREEN}Запустить${NC} Zapret"
        fi
        echo -e "${CYAN}9)${NC} 🔄 ${GREEN}Перезапустить${NC} Zapret"
        echo -e "${CYAN}0)${NC} 🗑  ${RED}Сбросить${NC} все настройки Discord Fix"
        echo -e "${CYAN}Enter)${NC} Выход"
        SEP
        echo -ne "${YELLOW}Выберите пункт: ${NC}"; read -r C

        case "$C" in
            1) quick_fix ;;
            2) menu_udp ;;
            3) menu_dv ;;
            4) menu_50script ;;
            5) menu_hosts ;;
            6) menu_diag ;;
            7)
                HEADER "Резервная копия"
                echo -e "${CYAN}1)${NC} Сохранить"
                echo -e "${CYAN}2)${NC} Восстановить"
                echo -e "${CYAN}Enter)${NC} Назад"
                echo -ne "\n${YELLOW}Выбор: ${NC}"; read -r BC
                case "$BC" in 1) backup_save;; 2) backup_restore;; esac ;;
            8)
                if pgrep -f /opt/zapret >/dev/null 2>&1; then
                    /etc/init.d/zapret stop >/dev/null 2>&1
                    echo -e "\n${GREEN}Zapret остановлен!${NC}"; PAUSE
                else
                    ZAPRET_RESTART
                    echo -e "\n${GREEN}Zapret запущен!${NC}"; PAUSE
                fi ;;
            9)
                echo -e "\n${CYAN}Перезапускаем Zapret...${NC}"
                ZAPRET_RESTART
                echo -e "${GREEN}Готово!${NC}"; PAUSE ;;
            0) reset_all ;;
            '') echo; exit 0 ;;
        esac
    done
}

main_menu
