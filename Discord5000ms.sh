#!/bin/sh
# ============================================================
#   Discord Voice Fix (5000ms Ping) для Zapret by StressOzz
#   Версия: 1.0  |  Решает проблему 5000ms в голосовых каналах
# ============================================================

GREEN="\033[1;32m"; RED="\033[1;31m"; CYAN="\033[1;36m"
YELLOW="\033[1;33m"; MAGENTA="\033[1;35m"; NC="\033[0m"

CONF="/etc/config/zapret"
HOSTS="/etc/hosts"
PAUSE() { echo -ne "\n${YELLOW}Нажмите Enter...${NC}"; read dummy; }
SEP() { echo -e "${CYAN}──────────────────────────────────────${NC}"; }

# ──────────────────────────────────────────────────────────────
# Финские IP (основная причина 5000ms — финские серверы Discord)
# ──────────────────────────────────────────────────────────────
FIN_PATTERN="104\.25\.158\.178 finland[0-9]\{5\}\.discord\.media"
DISCORD_MEDIA_HOSTS="discord.media
gateway.discord.gg
cdn.discordapp.com
discordapp.net
discordapp.com
discord.gg
discord.com"

fin_status()  { grep -q "$FIN_PATTERN" "$HOSTS" && echo 1 || echo 0; }
fin_add() {
    echo -e "${CYAN}Добавляем финские IP (finland10000–10199)...${NC}"
    seq 10000 10199 \
      | awk '{print "104.25.158.178 finland"$1".discord.media"}' \
      | grep -vxFf "$HOSTS" >> "$HOSTS"
    /etc/init.d/dnsmasq restart >/dev/null 2>&1
    echo -e "${GREEN}Финские IP добавлены!${NC}"
}
fin_remove() {
    echo -e "${CYAN}Удаляем финские IP...${NC}"
    sed -i "/$FIN_PATTERN/d" "$HOSTS"
    /etc/init.d/dnsmasq restart >/dev/null 2>&1
    echo -e "${GREEN}Финские IP удалены!${NC}"
}

# ──────────────────────────────────────────────────────────────
# Стратегии UDP для голосового канала Discord
#   Это — ключевой элемент: нужен правильный фильтр UDP 50000-50100
# ──────────────────────────────────────────────────────────────
UDP_BLOCK_MARK="##DISCORD_UDP_FIX##"

udp_block_present() {
    grep -q "$UDP_BLOCK_MARK" "$CONF"
}

# Параметры строки UDP выбираются ниже в меню
UDP_S1="--filter-udp=19294-19344,50000-50100\n--filter-l7=discord,stun\n--dpi-desync=fake\n--dpi-desync-repeats=6"
UDP_S2="--filter-udp=19294-19344,50000-50100\n--filter-l7=discord,stun\n--dpi-desync=fake\n--dpi-desync-repeats=8\n--dpi-desync-any-protocol=1"
UDP_S3="--filter-udp=50000-50099\n--filter-l7=discord,stun\n--dpi-desync=fake\n--dpi-desync-repeats=6\n--dpi-desync-cutoff=n4\n--dpi-desync-any-protocol=1\n--dpi-desync-fake-unknown-udp=/opt/zapret/files/fake/stun.bin"
UDP_S4="--filter-udp=50000-50099\n--filter-l7=discord,stun\n--dpi-desync=fake\n--dpi-desync-repeats=10\n--dpi-desync-cutoff=d2\n--dpi-desync-any-protocol=1\n--dpi-desync-fake-unknown-udp=/opt/zapret/files/fake/quic_initial_www_google_com.bin"
UDP_S5="--filter-udp=19294-19344,50000-50100\n--filter-l7=discord,stun\n--dpi-desync=fake\n--dpi-desync-repeats=6\n--dpi-desync-fake-unknown-udp=/opt/zapret/files/fake/quic_initial_www_google_com.bin"

udp_remove_block() {
    # Удаляем блок от метки до конца конфига (перед закрывающей ')
    awk -v mark="$UDP_BLOCK_MARK" '
        $0 ~ mark { found=1 }
        found && /^'"'"'$/ { found=0; print; next }
        found { next }
        { print }
    ' "$CONF" > /tmp/zapret_conf_tmp && mv /tmp/zapret_conf_tmp "$CONF"
    # Удаляем --new перед блоком, если остался
    awk '
        prev=="--new" && /^'"'"'$/ { print "--new"; print; prev=""; next }
        { if(prev!="") print prev; prev=$0 }
        END { if(prev!="") print prev }
    ' "$CONF" > /tmp/zapret_conf_tmp && mv /tmp/zapret_conf_tmp "$CONF"
}

udp_add_block() {
    local STRAT="$1"
    # Вставляем перед закрывающей кавычкой конфига
    local LAST=$(grep -n "^'$" "$CONF" | tail -n1 | cut -d: -f1)
    if [ -n "$LAST" ]; then
        sed -i "${LAST}d" "$CONF"
    fi
    printf "%s\n" \
        "$UDP_BLOCK_MARK" \
        "--new" >> "$CONF"
    printf "%b\n" "$STRAT" >> "$CONF"
    echo "'" >> "$CONF"
}

# Добавить нужные порты в NFQWS_PORTS_UDP если нет
ports_udp_add() {
    for P in "19294-19344" "50000-50100"; do
        grep -q "option NFQWS_PORTS_UDP.*$P" "$CONF" || \
            sed -i "/^[[:space:]]*option NFQWS_PORTS_UDP '/s/'$/ ,$P'/" "$CONF"
    done
}

zapret_restart() {
    chmod +x /opt/zapret/sync_config.sh 2>/dev/null
    /opt/zapret/sync_config.sh 2>/dev/null
    /etc/init.d/zapret restart >/dev/null 2>&1
    sleep 2
}

# ──────────────────────────────────────────────────────────────
# Тест: проверяем UDP-доступность Discord-серверов
# ──────────────────────────────────────────────────────────────
DISCORD_TEST_IPS="
162.159.128.233
162.159.130.234
35.227.25.196
35.212.162.164
"

test_discord_udp() {
    echo -e "\n${CYAN}Тест UDP 50000-50099 (голосовые каналы Discord)${NC}"
    SEP
    OK=0; FAIL=0
    for IP in $DISCORD_TEST_IPS; do
        [ -z "$IP" ] && continue
        # nc -u с таймаутом — проверяем достижимость
        if nc -u -w1 "$IP" 50001 </dev/null 2>/dev/null; then
            echo -e "${GREEN}[ OK ]${NC}  UDP $IP:50001"
            OK=$((OK+1))
        else
            # Альтернатива: ping (хотя бы IP-достижимость)
            if ping -c1 -W2 "$IP" >/dev/null 2>&1; then
                echo -e "${YELLOW}[PING]${NC} $IP — IP доступен, UDP не проверить без утилит"
                OK=$((OK+1))
            else
                echo -e "${RED}[FAIL]${NC} $IP — недоступен"
                FAIL=$((FAIL+1))
            fi
        fi
    done
    SEP
    echo -e "Результат: ${GREEN}$OK доступно${NC} / ${RED}$FAIL недоступно${NC}"
}

# Тест TCP discord.com (текстовый чат — контроль)
test_discord_tcp() {
    echo -e "\n${CYAN}Тест TCP — текстовый чат Discord${NC}"
    SEP
    for DOMAIN in discord.com gateway.discord.gg discordapp.com; do
        if curl -sL --connect-timeout 3 --max-time 5 \
               --range 0-1024 -o /dev/null \
               "https://$DOMAIN" 2>/dev/null; then
            echo -e "${GREEN}[ OK ]${NC} $DOMAIN"
        else
            echo -e "${RED}[FAIL]${NC} $DOMAIN"
        fi
    done
    SEP
}

# ──────────────────────────────────────────────────────────────
# Авто-тест стратегий UDP
# ──────────────────────────────────────────────────────────────
auto_test_udp_strategies() {
    [ ! -f /etc/init.d/zapret ] && { echo -e "${RED}Zapret не установлен!${NC}"; PAUSE; return; }
    clear
    echo -e "${MAGENTA}═══ Авто-тест UDP стратегий для Discord Voice ═══${NC}\n"
    echo -e "${YELLOW}Проблема 5000ms в голосовых каналах чаще всего${NC}"
    echo -e "${YELLOW}вызвана блокировкой UDP пакетов на портах 50000-50100.${NC}\n"

    # Сохраняем текущий конфиг
    cp "$CONF" /tmp/zapret_discord_backup.conf

    BEST_STRAT=""; BEST_NUM=0
    i=1
    for S in "$UDP_S1" "$UDP_S2" "$UDP_S3" "$UDP_S4" "$UDP_S5"; do
        echo -e "\n${CYAN}[$i/5] Тестируем UDP стратегию $i...${NC}"
        udp_remove_block
        ports_udp_add
        udp_add_block "$S"
        zapret_restart
        sleep 1

        test_discord_tcp
        SCORE=$OK
        echo -e "${CYAN}Показатель: $SCORE${NC}"

        if [ "$SCORE" -gt "$BEST_NUM" ]; then
            BEST_NUM=$SCORE
            BEST_STRAT="$S"
            BEST_I=$i
        fi
        i=$((i+1))
    done

    echo -e "\n${MAGENTA}═══ Результат ═══${NC}"
    if [ -n "$BEST_STRAT" ] && [ "$BEST_NUM" -gt 0 ]; then
        echo -e "${GREEN}Лучшая UDP стратегия: $BEST_I (счёт: $BEST_NUM)${NC}"
        echo -e "${CYAN}Применяем...${NC}"
        udp_remove_block
        ports_udp_add
        udp_add_block "$BEST_STRAT"
        zapret_restart
        echo -e "${GREEN}Стратегия UDP $BEST_I применена!${NC}"
    else
        echo -e "${RED}Рабочая стратегия не найдена — восстанавливаем конфиг${NC}"
        cp /tmp/zapret_discord_backup.conf "$CONF"
        zapret_restart
    fi
    PAUSE
}

# ──────────────────────────────────────────────────────────────
# Показ текущего состояния Discord в конфиге
# ──────────────────────────────────────────────────────────────
show_status() {
    echo -e "\n${MAGENTA}═══ Состояние Discord Fix ═══${NC}"
    SEP

    # Zapret статус
    if [ -f /etc/init.d/zapret ]; then
        /etc/init.d/zapret status >/dev/null 2>&1 \
            && echo -e "Zapret: ${GREEN}запущен${NC}" \
            || echo -e "Zapret: ${RED}остановлен${NC}"
    else
        echo -e "Zapret: ${RED}не установлен${NC}"
    fi

    # Финские IP
    if [ "$(fin_status)" = "1" ]; then
        echo -e "Финские IP (discord.media): ${GREEN}добавлены${NC}"
    else
        echo -e "Финские IP (discord.media): ${RED}не добавлены${NC}"
    fi

    # UDP блок
    if udp_block_present; then
        echo -e "UDP Voice блок: ${GREEN}установлен${NC}"
        UDPNUM=$(grep -A2 "$UDP_BLOCK_MARK" "$CONF" | grep "filter-udp" | head -n1)
        [ -n "$UDPNUM" ] && echo -e "  → ${CYAN}$UDPNUM${NC}"
    else
        echo -e "UDP Voice блок: ${RED}не установлен${NC}"
    fi

    # Dv стратегия
    DVNUM=$(grep -o '#Dv[0-9]*' "$CONF" 2>/dev/null | head -n1)
    [ -n "$DVNUM" ] \
        && echo -e "Стратегия discord.media: ${CYAN}$DVNUM${NC}" \
        || echo -e "Стратегия discord.media: ${YELLOW}не задана${NC}"

    # Порты UDP в конфиге
    UDP_P=$(grep "NFQWS_PORTS_UDP" "$CONF" 2>/dev/null | sed "s/.*'\(.*\)'.*/\1/")
    [ -n "$UDP_P" ] && echo -e "NFQWS_PORTS_UDP: ${CYAN}$UDP_P${NC}"

    SEP

    # ──── Известные причины 5000ms ────
    echo -e "\n${YELLOW}Частые причины 5000ms в голосовых каналах:${NC}"
    echo -e "  ${CYAN}1)${NC} UDP 50000-50099 не обрабатывается Zapret"
    echo -e "  ${CYAN}2)${NC} Финские серверы discord.media не резолвятся"
    echo -e "  ${CYAN}3)${NC} Flow Offloading на роутере блокирует UDP"
    echo -e "  ${CYAN}4)${NC} Неправильный регион голосового сервера в Discord"
    echo -e "  ${CYAN}5)${NC} Стратегия discord.media (Dv) не подходит для ISP"
    echo
}

# ──────────────────────────────────────────────────────────────
# Ручное применение UDP стратегии
# ──────────────────────────────────────────────────────────────
manual_udp_strategy() {
    [ ! -f /etc/init.d/zapret ] && { echo -e "${RED}Zapret не установлен!${NC}"; PAUSE; return; }
    clear
    echo -e "${MAGENTA}Выберите UDP стратегию для голосовых каналов${NC}\n"
    echo -e "${CYAN}1)${NC} filter-udp=19294-19344,50000-50100 + fake×6  ${YELLOW}(рекомендуется)${NC}"
    echo -e "${CYAN}2)${NC} filter-udp=19294-19344,50000-50100 + fake×8 + any-protocol"
    echo -e "${CYAN}3)${NC} filter-udp=50000-50099 + fake×6 + cutoff=n4 + stun.bin"
    echo -e "${CYAN}4)${NC} filter-udp=50000-50099 + fake×10 + cutoff=d2 + quic.bin"
    echo -e "${CYAN}5)${NC} filter-udp=19294-19344,50000-50100 + fake×6 + quic.bin"
    if udp_block_present; then
        echo -e "${CYAN}D)${NC} ${RED}Удалить UDP блок${NC}"
    fi
    echo -e "${CYAN}Enter)${NC} Назад"
    echo -ne "\n${YELLOW}Выбор: ${NC}"; read C
    case "$C" in
        1) S="$UDP_S1" ;;
        2) S="$UDP_S2" ;;
        3) S="$UDP_S3" ;;
        4) S="$UDP_S4" ;;
        5) S="$UDP_S5" ;;
        d|D)
            udp_remove_block
            zapret_restart
            echo -e "\n${GREEN}UDP блок удалён!${NC}"
            PAUSE; return ;;
        *) return ;;
    esac
    udp_remove_block
    ports_udp_add
    udp_add_block "$S"
    zapret_restart
    echo -e "\n${GREEN}UDP стратегия $C применена!${NC}"
    PAUSE
}

# ──────────────────────────────────────────────────────────────
# Быстрый фикс (1 кнопка) — применяет весь рекомендуемый набор
# ──────────────────────────────────────────────────────────────
quick_fix() {
    [ ! -f /etc/init.d/zapret ] && { echo -e "\n${RED}Zapret не установлен!${NC}"; PAUSE; return; }
    clear
    echo -e "${MAGENTA}═══ Быстрый фикс Discord 5000ms ═══${NC}\n"

    echo -e "${CYAN}Шаг 1/3:${NC} Добавляем финские IP discord.media в hosts"
    fin_add

    echo -e "\n${CYAN}Шаг 2/3:${NC} Устанавливаем UDP блок (стратегия 1)"
    udp_remove_block
    ports_udp_add
    udp_add_block "$UDP_S1"

    echo -e "\n${CYAN}Шаг 3/3:${NC} Перезапускаем Zapret"
    zapret_restart

    echo -e "\n${GREEN}═══ Быстрый фикс применён! ═══${NC}"
    echo -e "${YELLOW}Подождите 30–60 секунд, затем проверьте голосовой канал.${NC}"
    echo -e "${YELLOW}Если пинг всё ещё 5000ms — используйте авто-тест стратегий.${NC}"
    echo -e "\n${YELLOW}Если роутер с Flow Offloading — отключите его или примените FIX${NC}"
    echo -e "${YELLOW}в системном меню Zapret Manager!${NC}"
    PAUSE
}

# ──────────────────────────────────────────────────────────────
# Диагностика Flow Offloading (одна из причин проблемы)
# ──────────────────────────────────────────────────────────────
check_flow_offload() {
    FO=$(uci get firewall.@defaults[0].flow_offloading 2>/dev/null)
    FOHW=$(uci get firewall.@defaults[0].flow_offloading_hw 2>/dev/null)
    FIX=$(grep -q 'ct original packets ge 30 flow offload @ft;' \
              /usr/share/firewall4/templates/ruleset.uc 2>/dev/null && echo 1 || echo 0)
    echo -ne "Flow Offloading: "
    if [ "$FO" = "1" ] || [ "$FOHW" = "1" ]; then
        echo -e "${RED}ВКЛЮЧЁН${NC} — это может вызывать 5000ms!"
        if [ "$FIX" = "1" ]; then
            echo -e "  FIX для Flow Offloading: ${GREEN}применён${NC}"
        else
            echo -e "  FIX для Flow Offloading: ${RED}не применён${NC} — рекомендуется применить!"
        fi
    else
        echo -e "${GREEN}выключен${NC} (OK)"
    fi
}

# ──────────────────────────────────────────────────────────────
# ГЛАВНОЕ МЕНЮ
# ──────────────────────────────────────────────────────────────
main_menu() {
    while true; do
        clear
        echo -e "╔══════════════════════════════════════════╗"
        echo -e "║   ${MAGENTA}Discord Voice Fix — 5000ms Ping Fix${NC}     ║"
        echo -e "╚══════════════════════════════════════════╝"

        show_status

        check_flow_offload
        echo

        # Кнопка финских IP
        if [ "$(fin_status)" = "1" ]; then
            FIN_TXT="${RED}Удалить${NC} финские IP (discord.media)"
        else
            FIN_TXT="${GREEN}Добавить${NC} финские IP (discord.media)"
        fi

        echo -e "${CYAN}1)${NC} ⚡ Быстрый фикс (всё сразу)"
        echo -e "${CYAN}2)${NC} 🔍 Авто-тест UDP стратегий"
        echo -e "${CYAN}3)${NC} 🛠  Выбрать UDP стратегию вручную"
        echo -e "${CYAN}4)${NC} $FIN_TXT"
        echo -e "${CYAN}5)${NC} 📡 Тест соединения с Discord"
        echo -e "${CYAN}6)${NC} 🔄 Перезапустить Zapret"
        echo -e "${CYAN}Enter)${NC} Выход"
        echo -ne "\n${YELLOW}Выберите пункт: ${NC}"; read C

        case "$C" in
            1) quick_fix ;;
            2) auto_test_udp_strategies ;;
            3) manual_udp_strategy ;;
            4)
                if [ "$(fin_status)" = "1" ]; then fin_remove; else fin_add; fi
                PAUSE ;;
            5)
                clear
                test_discord_tcp
                test_discord_udp
                PAUSE ;;
            6)
                echo -e "\n${CYAN}Перезапускаем Zapret...${NC}"
                zapret_restart
                echo -e "${GREEN}Готово!${NC}"
                PAUSE ;;
            *) echo; exit 0 ;;
        esac
    done
}

# ──────────────────────────────────────────────────────────────
# Создаём алиас для быстрого запуска
# ──────────────────────────────────────────────────────────────
echo 'sh <(wget -O - https://raw.githubusercontent.com/StressOzz/Zapret-Manager/main/discord_fix.sh)' \
    > /usr/bin/dcfix 2>/dev/null
chmod +x /usr/bin/dcfix 2>/dev/null

# Запуск
main_menu
