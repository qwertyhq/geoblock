#!/bin/bash

# ============================================
# GeoBlock — блокировка стран по IP на порту
# Интерактивный скрипт установки
# https://github.com/qwertyhq/geoblock
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

# --- Проверка root ---
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}Запусти от root: sudo bash install.sh${NC}"
    exit 1
fi

# --- Установка зависимостей ---
echo -e "${CYAN}Проверяю зависимости...${NC}"

install_pkg() {
    if command -v apt-get &>/dev/null; then
        apt-get update -qq && apt-get install -y -qq "$@" >/dev/null 2>&1
    elif command -v yum &>/dev/null; then
        yum install -y -q "$@" >/dev/null 2>&1
    elif command -v dnf &>/dev/null; then
        dnf install -y -q "$@" >/dev/null 2>&1
    elif command -v apk &>/dev/null; then
        apk add --quiet "$@" >/dev/null 2>&1
    else
        echo -e "${RED}Не могу определить пакетный менеджер. Установи вручную: $@${NC}"
        exit 1
    fi
}

if ! command -v ipset &>/dev/null; then
    echo -e "${YELLOW}Устанавливаю ipset...${NC}"
    install_pkg ipset
fi

if ! command -v wget &>/dev/null && ! command -v curl &>/dev/null; then
    echo -e "${YELLOW}Устанавливаю wget...${NC}"
    install_pkg wget
fi

# Выбираем загрузчик
if command -v wget &>/dev/null; then
    DOWNLOAD="wget -q -O"
elif command -v curl &>/dev/null; then
    DOWNLOAD="curl -sSL -o"
fi

echo -e "${GREEN}Зависимости установлены${NC}"
echo ""

# --- Порт ---
echo -e "${CYAN}--- Какой порт защитить? ---${NC}"
echo -e "Например: 8443 для MTProto proxy, 443 для HTTPS"
echo ""
while true; do
    read -rp "$(echo -e "${YELLOW}Порт [8443]: ${NC}")" PORT
    PORT=${PORT:-8443}
    if [[ "$PORT" =~ ^[0-9]+$ ]] && [ "$PORT" -ge 1 ] && [ "$PORT" -le 65535 ]; then
        break
    fi
    echo -e "${RED}Некорректный порт. Введи число от 1 до 65535${NC}"
done
echo ""

# --- Страны ---
echo -e "${CYAN}--- Какие страны заблокировать? ---${NC}"
echo ""
echo -e "${CYAN}Готовые пресеты:${NC}"
echo ""
echo -e "  ${GREEN}1${NC}) Базовый       ${YELLOW}pk ir${NC}                    Пакистан, Иран"
echo -e "  ${GREEN}2${NC}) Рекомендуемый ${YELLOW}pk ir ua in cn${NC}           + Украина, Индия, Китай"
echo -e "  ${GREEN}3${NC}) Расширенный   ${YELLOW}pk ir ua in cn bd vn id${NC}  + Бангладеш, Вьетнам, Индонезия"
echo -e "  ${GREEN}4${NC}) Свой набор    Ввести коды вручную"
echo ""
read -rp "$(echo -e "${YELLOW}Выбери [1/2/3/4]: ${NC}")" PRESET

case "$PRESET" in
    1) COUNTRIES_INPUT="pk ir" ;;
    2) COUNTRIES_INPUT="pk ir ua in cn" ;;
    3) COUNTRIES_INPUT="pk ir ua in cn bd vn id" ;;
    4|*)
        echo ""
        echo -e "${CYAN}Коды стран (ISO 3166-1):${NC}"
        echo ""
        echo -e "  ${GREEN}ua${NC} Украина     ${GREEN}pk${NC} Пакистан   ${GREEN}ir${NC} Иран       ${GREEN}in${NC} Индия"
        echo -e "  ${GREEN}cn${NC} Китай       ${GREEN}bd${NC} Бангладеш  ${GREEN}vn${NC} Вьетнам    ${GREEN}id${NC} Индонезия"
        echo -e "  ${GREEN}br${NC} Бразилия    ${GREEN}ng${NC} Нигерия    ${GREEN}ph${NC} Филиппины  ${GREEN}iq${NC} Ирак"
        echo -e "  ${GREEN}ru${NC} Россия      ${GREEN}by${NC} Беларусь   ${GREEN}kz${NC} Казахстан  ${GREEN}uz${NC} Узбекистан"
        echo -e "  ${GREEN}de${NC} Германия    ${GREEN}nl${NC} Нидерланды ${GREEN}fr${NC} Франция    ${GREEN}gb${NC} Великобритания"
        echo -e "  ${GREEN}us${NC} США         ${GREEN}tr${NC} Турция     ${GREEN}il${NC} Израиль    ${GREEN}sa${NC} Сауд. Аравия"
        echo ""
        echo -e "Полный список: ${CYAN}https://www.ipdeny.com/ipblocks/data/countries/${NC}"
        echo ""
        while true; do
            read -rp "$(echo -e "${YELLOW}Коды стран (например: pk ir ua): ${NC}")" COUNTRIES_INPUT
            if [ -n "$COUNTRIES_INPUT" ]; then
                break
            fi
            echo -e "${RED}Нужно указать хотя бы одну страну${NC}"
        done
        ;;
esac

COUNTRIES=$(echo "$COUNTRIES_INPUT" | tr '[:upper:]' '[:lower:]')
echo ""

# --- Подтверждение ---
echo -e "${CYAN}Настройки:${NC}"
echo -e "  Порт:   ${GREEN}${PORT}${NC}"
echo -e "  Страны: ${GREEN}${COUNTRIES}${NC}"
echo ""
read -rp "$(echo -e "${YELLOW}Продолжить? [Y/n]: ${NC}")" CONFIRM
CONFIRM=${CONFIRM:-Y}
if [[ ! "$CONFIRM" =~ ^[Yy] ]]; then
    echo "Отменено."
    exit 0
fi
echo ""

# --- Предупреждение при повторной установке ---
if ipset list geoblock &>/dev/null; then
    echo -e "${YELLOW}Обнаружен существующий geoblock. Пересоздаю...${NC}"
    iptables -D INPUT -p tcp --dport ${PORT} -m set --match-set geoblock src -j DROP 2>/dev/null || true
    ipset destroy geoblock 2>/dev/null || true
fi

# --- Скачивание и загрузка ---
echo -e "${CYAN}Скачиваю списки IP...${NC}"

ipset create geoblock hash:net hashsize 8192 2>/dev/null || {
    echo -e "${RED}Не удалось создать ipset. Проверь что модуль ядра загружен: modprobe ip_set${NC}"
    exit 1
}

TOTAL=0
FAILED=""
for CC in $COUNTRIES; do
    FILE="/tmp/${CC}.zone"
    $DOWNLOAD "$FILE" "https://www.ipdeny.com/ipblocks/data/countries/${CC}.zone" 2>/dev/null

    if [ ! -s "$FILE" ]; then
        echo -e "${RED}  ${CC} — не найден, пропускаю${NC}"
        FAILED="${FAILED} ${CC}"
        continue
    fi

    COUNT=0
    while IFS= read -r cidr; do
        [ -z "$cidr" ] && continue
        ipset add geoblock "$cidr" 2>/dev/null && COUNT=$((COUNT + 1))
    done < "$FILE"

    TOTAL=$((TOTAL + COUNT))
    echo -e "${GREEN}  ${CC} — ${COUNT} подсетей${NC}"
done

if [ "$TOTAL" -eq 0 ]; then
    echo -e "${RED}Не удалось загрузить ни одной подсети. Проверь интернет и коды стран.${NC}"
    ipset destroy geoblock 2>/dev/null
    exit 1
fi

echo ""
echo -e "${GREEN}Загружено ${TOTAL} подсетей${NC}"
if [ -n "$FAILED" ]; then
    echo -e "${YELLOW}Не найдены:${FAILED}${NC}"
fi
echo ""

# --- iptables ---
echo -e "${CYAN}Добавляю правило iptables...${NC}"
iptables -D INPUT -p tcp --dport ${PORT} -m set --match-set geoblock src -j DROP 2>/dev/null || true
iptables -I INPUT -p tcp --dport ${PORT} -m set --match-set geoblock src -j DROP || {
    echo -e "${RED}Не удалось добавить правило iptables${NC}"
    exit 1
}
echo -e "${GREEN}Правило добавлено${NC}"
echo ""

# --- Скрипт для автозагрузки ---
echo -e "${CYAN}Создаю скрипт автозагрузки...${NC}"

cat > /opt/geoblock.sh << GEOEOF
#!/bin/bash
# GeoBlock — auto-restore after reboot
# Port: ${PORT}
# Countries: ${COUNTRIES}
# Generated: $(date -u +"%Y-%m-%d %H:%M:%S UTC")

PORT=${PORT}
COUNTRIES="${COUNTRIES}"

# Загрузчик
if command -v wget &>/dev/null; then
    DL="wget -q -O"
elif command -v curl &>/dev/null; then
    DL="curl -sSL -o"
else
    echo "\$(date): ERROR — wget/curl not found"
    exit 1
fi

# Пересоздаём ipset
iptables -D INPUT -p tcp --dport \$PORT -m set --match-set geoblock src -j DROP 2>/dev/null
ipset destroy geoblock 2>/dev/null
ipset create geoblock hash:net hashsize 8192

TOTAL=0
for CC in \$COUNTRIES; do
    FILE="/tmp/\${CC}.zone"
    \$DL "\$FILE" "https://www.ipdeny.com/ipblocks/data/countries/\${CC}.zone" 2>/dev/null
    if [ -s "\$FILE" ]; then
        while IFS= read -r cidr; do
            [ -z "\$cidr" ] && continue
            ipset add geoblock "\$cidr" 2>/dev/null && TOTAL=\$((TOTAL + 1))
        done < "\$FILE"
    fi
done

iptables -I INPUT -p tcp --dport \$PORT -m set --match-set geoblock src -j DROP

echo "\$(date): GeoBlock restored — \$TOTAL networks blocked on port \$PORT (\$COUNTRIES)"
GEOEOF

chmod +x /opt/geoblock.sh

# --- Cron (без дублирования) ---
TEMP_CRON=$(mktemp)
crontab -l 2>/dev/null | grep -v "geoblock" > "$TEMP_CRON" || true
echo "@reboot /opt/geoblock.sh >> /var/log/geoblock.log 2>&1" >> "$TEMP_CRON"
echo "0 4 * * 0 /opt/geoblock.sh >> /var/log/geoblock.log 2>&1" >> "$TEMP_CRON"
crontab "$TEMP_CRON"
rm -f "$TEMP_CRON"

echo -e "${GREEN}Автозагрузка настроена${NC}"
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
echo -e "  Добавить страну:      ${GREEN}nano /opt/geoblock.sh  # измени COUNTRIES и запусти${NC}"
echo -e "  Логи:                 ${GREEN}cat /var/log/geoblock.log${NC}"
echo ""
echo -e "${YELLOW}Списки IP обновляются автоматически каждое воскресенье в 4:00${NC}"
echo ""
echo -e "${GREEN}Готово!${NC}"
