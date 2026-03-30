#!/bin/bash
set -e

# ============================================
# GeoBlock — блокировка стран по IP на порту
# Интерактивный скрипт установки
# ============================================

GREEN='\033[0;32m'
RED='\033[0;31m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${CYAN}╔══════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║      GeoBlock — Country IP Blocker       ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════╝${NC}"
echo ""

# --- Определение пакетного менеджера ---
install_packages() {
    if command -v apt-get &> /dev/null; then
        apt-get update -qq 2>/dev/null || true
        apt-get install -y -qq "$@" >/dev/null 2>&1
    elif command -v dnf &> /dev/null; then
        dnf install -y -q "$@" >/dev/null 2>&1
    elif command -v yum &> /dev/null; then
        yum install -y -q "$@" >/dev/null 2>&1
    elif command -v apk &> /dev/null; then
        apk add --quiet "$@" >/dev/null 2>&1
    elif command -v pacman &> /dev/null; then
        pacman -S --noconfirm --needed "$@" >/dev/null 2>&1
    elif command -v zypper &> /dev/null; then
        zypper install -y "$@" >/dev/null 2>&1
    else
        echo -e "${RED}Неизвестный пакетный менеджер. Установи вручную: ipset wget iptables${NC}"
        return 1
    fi
}

# --- Установка зависимостей ---
echo -e "${CYAN}Проверяю зависимости...${NC}"
MISSING=""
command -v ipset &> /dev/null || MISSING="$MISSING ipset"
command -v wget &> /dev/null || MISSING="$MISSING wget"
command -v iptables &> /dev/null || MISSING="$MISSING iptables"

if [ -n "$MISSING" ]; then
    echo -e "${YELLOW}Устанавливаю:${MISSING}...${NC}"
    install_packages $MISSING || {
        echo -e "${RED}Не удалось установить:${MISSING}${NC}"
        echo -e "${RED}Установи вручную и запусти скрипт снова${NC}"
        exit 1
    }
fi
echo -e "${GREEN}Все зависимости установлены (ipset, wget, iptables)${NC}"
echo ""

# --- Порт (автодетект) ---
echo -e "${CYAN}--- Какой порт защитить? ---${NC}"
echo ""

# Детект популярных сервисов
DETECTED_PORTS=""
DETECTED_HINTS=""

# MTProto proxy (mtg, mtprotoproxy)
for P in 8443 443 8080; do
    if ss -tlnp 2>/dev/null | grep -q ":${P} " && ss -tlnp 2>/dev/null | grep ":${P} " | grep -qiE "mtg|mtproto|mtproxy"; then
        DETECTED_PORTS="${P}"
        DETECTED_HINTS="MTProto proxy"
        break
    fi
done

# Xray/V2Ray/Sing-box
if [ -z "$DETECTED_PORTS" ]; then
    for P in 443 8443 2053 2083 2087; do
        if ss -tlnp 2>/dev/null | grep -q ":${P} " && ss -tlnp 2>/dev/null | grep ":${P} " | grep -qiE "xray|v2ray|sing-box|hysteria|reality"; then
            DETECTED_PORTS="${P}"
            DETECTED_HINTS="Xray/V2Ray/Sing-box"
            break
        fi
    done
fi

# Nginx/Caddy на 443
if [ -z "$DETECTED_PORTS" ]; then
    if ss -tlnp 2>/dev/null | grep -q ":443 "; then
        DETECTED_PORTS="443"
        LISTEN_PROC=$(ss -tlnp 2>/dev/null | grep ":443 " | grep -oP 'users:\(\("\K[^"]+' | head -1)
        DETECTED_HINTS="${LISTEN_PROC:-HTTPS}"
    fi
fi

# Fallback — 8443
if [ -z "$DETECTED_PORTS" ]; then
    if ss -tlnp 2>/dev/null | grep -q ":8443 "; then
        DETECTED_PORTS="8443"
        LISTEN_PROC=$(ss -tlnp 2>/dev/null | grep ":8443 " | grep -oP 'users:\(\("\K[^"]+' | head -1)
        DETECTED_HINTS="${LISTEN_PROC:-8443}"
    fi
fi

if [ -n "$DETECTED_PORTS" ]; then
    echo -e "  ${GREEN}Обнаружен:${NC} порт ${GREEN}${DETECTED_PORTS}${NC} (${DETECTED_HINTS})"
    echo ""
    read -rp "$(echo -e "${YELLOW}Порт [${DETECTED_PORTS}]: ${NC}")" PORT
    PORT=${PORT:-$DETECTED_PORTS}
else
    echo -e "  Например: 8443 для MTProto proxy, 443 для HTTPS"
    echo ""
    read -rp "$(echo -e "${YELLOW}Порт [8443]: ${NC}")" PORT
    PORT=${PORT:-8443}
fi
echo ""

# --- Страны ---
echo -e "${CYAN}--- Какие страны заблокировать? ---${NC}"
echo ""
echo -e "${CYAN}Готовые пресеты:${NC}"
echo ""
echo -e "  ${GREEN}1${NC}) Рекомендуемый    ${YELLOW}pk in ir ua cn${NC}  (Пакистан, Индия, Иран, Украина, Китай)"
echo -e "  ${GREEN}2${NC}) Расширенный      ${YELLOW}pk in ir ua cn bd vn id${NC}  (+ Бангладеш, Вьетнам, Индонезия)"
echo -e "  ${GREEN}3${NC}) Свой набор       Ввести коды вручную"
echo ""
read -rp "$(echo -e "${YELLOW}Выбери [1/2/3, по умолчанию 1]: ${NC}")" PRESET_CHOICE
PRESET_CHOICE=${PRESET_CHOICE:-1}

if [ "$PRESET_CHOICE" = "1" ]; then
    COUNTRIES_INPUT="pk in ir ua cn"
    echo -e "${GREEN}Выбран рекомендуемый пресет: ${COUNTRIES_INPUT}${NC}"
elif [ "$PRESET_CHOICE" = "2" ]; then
    COUNTRIES_INPUT="pk in ir ua cn bd vn id"
    echo -e "${GREEN}Выбран расширенный пресет: ${COUNTRIES_INPUT}${NC}"
else
    echo ""
    echo -e "${CYAN}Коды стран (ISO 3166-1 alpha-2):${NC}"
    echo ""
    echo -e "  ${GREEN}ad${NC} Андорра          ${GREEN}ae${NC} ОАЭ              ${GREEN}af${NC} Афганистан"
    echo -e "  ${GREEN}al${NC} Албания          ${GREEN}am${NC} Армения          ${GREEN}ao${NC} Ангола"
    echo -e "  ${GREEN}ar${NC} Аргентина        ${GREEN}at${NC} Австрия          ${GREEN}au${NC} Австралия"
    echo -e "  ${GREEN}az${NC} Азербайджан      ${GREEN}ba${NC} Босния           ${GREEN}bd${NC} Бангладеш"
    echo -e "  ${GREEN}be${NC} Бельгия          ${GREEN}bg${NC} Болгария         ${GREEN}bh${NC} Бахрейн"
    echo -e "  ${GREEN}br${NC} Бразилия         ${GREEN}by${NC} Беларусь         ${GREEN}ca${NC} Канада"
    echo -e "  ${GREEN}ch${NC} Швейцария        ${GREEN}cl${NC} Чили             ${GREEN}cn${NC} Китай"
    echo -e "  ${GREEN}co${NC} Колумбия         ${GREEN}cz${NC} Чехия            ${GREEN}de${NC} Германия"
    echo -e "  ${GREEN}dk${NC} Дания            ${GREEN}dz${NC} Алжир            ${GREEN}ec${NC} Эквадор"
    echo -e "  ${GREEN}ee${NC} Эстония          ${GREEN}eg${NC} Египет           ${GREEN}es${NC} Испания"
    echo -e "  ${GREEN}fi${NC} Финляндия        ${GREEN}fr${NC} Франция          ${GREEN}gb${NC} Великобритания"
    echo -e "  ${GREEN}ge${NC} Грузия           ${GREEN}gr${NC} Греция           ${GREEN}hk${NC} Гонконг"
    echo -e "  ${GREEN}hr${NC} Хорватия         ${GREEN}hu${NC} Венгрия          ${GREEN}id${NC} Индонезия"
    echo -e "  ${GREEN}ie${NC} Ирландия         ${GREEN}il${NC} Израиль          ${GREEN}in${NC} Индия"
    echo -e "  ${GREEN}iq${NC} Ирак             ${GREEN}ir${NC} Иран             ${GREEN}it${NC} Италия"
    echo -e "  ${GREEN}jp${NC} Япония           ${GREEN}kg${NC} Кыргызстан       ${GREEN}kr${NC} Южная Корея"
    echo -e "  ${GREEN}kz${NC} Казахстан        ${GREEN}lb${NC} Ливан            ${GREEN}lt${NC} Литва"
    echo -e "  ${GREEN}lv${NC} Латвия           ${GREEN}ma${NC} Марокко          ${GREEN}md${NC} Молдова"
    echo -e "  ${GREEN}mx${NC} Мексика          ${GREEN}my${NC} Малайзия         ${GREEN}ng${NC} Нигерия"
    echo -e "  ${GREEN}nl${NC} Нидерланды       ${GREEN}no${NC} Норвегия         ${GREEN}nz${NC} Новая Зеландия"
    echo -e "  ${GREEN}pe${NC} Перу             ${GREEN}ph${NC} Филиппины        ${GREEN}pk${NC} Пакистан"
    echo -e "  ${GREEN}pl${NC} Польша           ${GREEN}pt${NC} Португалия       ${GREEN}ro${NC} Румыния"
    echo -e "  ${GREEN}rs${NC} Сербия           ${GREEN}ru${NC} Россия           ${GREEN}sa${NC} Сауд. Аравия"
    echo -e "  ${GREEN}se${NC} Швеция           ${GREEN}sg${NC} Сингапур         ${GREEN}sk${NC} Словакия"
    echo -e "  ${GREEN}th${NC} Таиланд          ${GREEN}tj${NC} Таджикистан      ${GREEN}tm${NC} Туркменистан"
    echo -e "  ${GREEN}tr${NC} Турция           ${GREEN}tw${NC} Тайвань          ${GREEN}ua${NC} Украина"
    echo -e "  ${GREEN}us${NC} США              ${GREEN}uz${NC} Узбекистан       ${GREEN}ve${NC} Венесуэла"
    echo -e "  ${GREEN}vn${NC} Вьетнам          ${GREEN}za${NC} ЮАР"
    echo ""
    read -rp "$(echo -e "${YELLOW}Коды стран (например: pk ir ua): ${NC}")" COUNTRIES_INPUT
fi

if [ -z "$COUNTRIES_INPUT" ]; then
    echo -e "${RED}Нужно указать хотя бы одну страну${NC}"
    exit 1
fi

# Приводим к нижнему регистру
COUNTRIES=$(echo "$COUNTRIES_INPUT" | tr '[:upper:]' '[:lower:]')
echo ""

# --- Подтверждение ---
echo -e "${CYAN}Настройки:${NC}"
echo -e "  Порт: ${GREEN}${PORT}${NC}"
echo -e "  Страны: ${GREEN}${COUNTRIES}${NC}"
echo ""
read -rp "$(echo -e "${YELLOW}Продолжить? [Y/n]: ${NC}")" CONFIRM
CONFIRM=${CONFIRM:-Y}
if [[ ! "$CONFIRM" =~ ^[Yy] ]]; then
    echo "Отменено."
    exit 0
fi
echo ""

# --- Скачивание и загрузка ---
echo -e "${CYAN}Скачиваю списки IP...${NC}"

ipset flush geoblock 2>/dev/null || true
ipset destroy geoblock 2>/dev/null || true
ipset create geoblock hash:net hashsize 8192 || ipset flush geoblock 2>/dev/null || { echo -e "${RED}Не удалось создать ipset${NC}"; exit 1; }

TOTAL=0
COUNTRY_COUNT=$(echo $COUNTRIES | wc -w)
CURRENT=0
for CC in $COUNTRIES; do
    CURRENT=$((CURRENT + 1))
    CC_UPPER=$(echo "$CC" | tr '[:lower:]' '[:upper:]')
    FILE="/tmp/${CC}.zone"

    # Скачивание
    printf "\r  [${CURRENT}/${COUNTRY_COUNT}] ${CYAN}${CC_UPPER}${NC} — скачиваю...          "
    wget -q "https://www.ipdeny.com/ipblocks/data/countries/${CC}.zone" -O "$FILE" 2>/dev/null || true

    if [ ! -s "$FILE" ]; then
        printf "\r  [${CURRENT}/${COUNTRY_COUNT}] ${RED}${CC_UPPER} — не найден, пропускаю${NC}\n"
        continue
    fi

    COUNT=$(wc -l < "$FILE")
    LOADED=0

    # Загрузка в ipset с прогрессом
    while IFS= read -r cidr; do
        [ -z "$cidr" ] && continue
        ipset add geoblock "$cidr" 2>/dev/null || true
        LOADED=$((LOADED + 1))
        if [ $((LOADED % 500)) -eq 0 ]; then
            PCT=$((LOADED * 100 / COUNT))
            printf "\r  [${CURRENT}/${COUNTRY_COUNT}] ${CYAN}${CC_UPPER}${NC} — загрузка ${GREEN}${PCT}%%${NC} (${LOADED}/${COUNT})    "
        fi
    done < "$FILE"

    TOTAL=$((TOTAL + COUNT))
    printf "\r  [${CURRENT}/${COUNTRY_COUNT}] ${GREEN}${CC_UPPER} — ${COUNT} подсетей ✓${NC}              \n"
done
echo ""
echo -e "${GREEN}Загружено ${TOTAL} подсетей${NC}"
echo ""

# --- iptables ---
echo -e "${CYAN}Добавляю правило iptables...${NC}"
iptables -D INPUT -p tcp --dport ${PORT} -m set --match-set geoblock src -j DROP 2>/dev/null || true
iptables -I INPUT -p tcp --dport ${PORT} -m set --match-set geoblock src -j DROP
echo -e "${GREEN}Правило добавлено${NC}"
echo ""

# --- Скрипт для автозагрузки ---
echo -e "${CYAN}Создаю скрипт автозагрузки...${NC}"

cat > /opt/geoblock.sh << SCRIPT
#!/bin/bash
# GeoBlock — auto-restore after reboot
# Port: ${PORT}
# Countries: ${COUNTRIES}
# Generated: $(date -u +"%Y-%m-%d %H:%M:%S UTC")

PORT=${PORT}
COUNTRIES="${COUNTRIES}"

ipset destroy geoblock 2>/dev/null
ipset create geoblock hash:net hashsize 8192

for CC in \$COUNTRIES; do
    FILE="/tmp/\${CC}.zone"
    wget -q "https://www.ipdeny.com/ipblocks/data/countries/\${CC}.zone" -O "\$FILE" 2>/dev/null
    if [ -s "\$FILE" ]; then
        while read cidr; do
            ipset add geoblock "\$cidr" 2>/dev/null
        done < "\$FILE"
    fi
done

iptables -D INPUT -p tcp --dport \$PORT -m set --match-set geoblock src -j DROP 2>/dev/null
iptables -I INPUT -p tcp --dport \$PORT -m set --match-set geoblock src -j DROP

echo "\$(date): GeoBlock restored — \$(ipset list geoblock | grep -c '/') networks blocked on port \$PORT"
SCRIPT

chmod +x /opt/geoblock.sh

# --- Автозагрузка ---
if command -v crontab &> /dev/null; then
    EXISTING_CRON=$(crontab -l 2>/dev/null | grep -v geoblock || true)
    echo "$EXISTING_CRON" | { cat; echo "@reboot /opt/geoblock.sh >> /var/log/geoblock.log 2>&1"; echo "0 4 * * 0 /opt/geoblock.sh >> /var/log/geoblock.log 2>&1"; } | crontab -
    echo -e "${GREEN}Автозагрузка настроена (cron)${NC}"
elif command -v systemctl &> /dev/null; then
    # Создаём systemd service + timer как альтернативу cron
    cat > /etc/systemd/system/geoblock.service << EOF
[Unit]
Description=GeoBlock IP filter restore
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/opt/geoblock.sh
StandardOutput=append:/var/log/geoblock.log
StandardError=append:/var/log/geoblock.log

[Install]
WantedBy=multi-user.target
EOF

    cat > /etc/systemd/system/geoblock.timer << EOF
[Unit]
Description=GeoBlock weekly IP list update

[Timer]
OnCalendar=Sun *-*-* 04:00:00
Persistent=true

[Install]
WantedBy=timers.target
EOF

    systemctl daemon-reload
    systemctl enable --now geoblock.service geoblock.timer >/dev/null 2>&1
    echo -e "${GREEN}Автозагрузка настроена (systemd service + weekly timer)${NC}"
else
    echo -e "${YELLOW}crontab и systemd не найдены — добавь /opt/geoblock.sh в автозагрузку вручную${NC}"
fi
echo ""

# --- Результат ---
echo -e "${CYAN}╔══════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║              GeoBlock Ready               ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════╝${NC}"
echo ""
echo -e "${GREEN}Заблокировано: ${TOTAL} подсетей${NC}"
echo -e "${GREEN}Порт: ${PORT}${NC}"
echo -e "${GREEN}Страны: ${COUNTRIES}${NC}"
echo ""
echo -e "${CYAN}Команды:${NC}"
echo -e "  Проверить правило:     ${GREEN}iptables -L INPUT -n | head -5${NC}"
echo -e "  Кол-во подсетей:      ${GREEN}ipset list geoblock | grep -c '/'${NC}"
echo -e "  Обновить списки:      ${GREEN}bash /opt/geoblock.sh${NC}"
echo -e "  Убрать блокировку:    ${GREEN}iptables -D INPUT -p tcp --dport ${PORT} -m set --match-set geoblock src -j DROP${NC}"
echo -e "  Добавить страну:      ${GREEN}Редактируй COUNTRIES в /opt/geoblock.sh и запусти его${NC}"
echo -e "  Логи:                 ${GREEN}cat /var/log/geoblock.log${NC}"
echo ""
echo -e "${YELLOW}Списки IP обновляются автоматически каждое воскресенье в 4:00${NC}"
echo ""
echo -e "${GREEN}Готово!${NC}"
