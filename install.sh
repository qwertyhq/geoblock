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

# --- Установка зависимостей ---
echo -e "${CYAN}Проверяю зависимости...${NC}"
if ! command -v ipset &> /dev/null; then
    echo -e "${YELLOW}Устанавливаю ipset...${NC}"
    apt-get update -qq && apt-get install -y -qq ipset wget >/dev/null 2>&1
fi
echo -e "${GREEN}ipset и wget установлены${NC}"
echo ""

# --- Порт ---
echo -e "${CYAN}--- Какой порт защитить? ---${NC}"
echo -e "Например: 8443 для MTProto proxy, 443 для HTTPS"
echo ""
read -rp "$(echo -e "${YELLOW}Порт [8443]: ${NC}")" PORT
PORT=${PORT:-8443}
echo ""

# --- Страны ---
echo -e "${CYAN}--- Какие страны заблокировать? ---${NC}"
echo -e "Введи коды стран через пробел (ISO 3166-1 alpha-2)"
echo ""
echo -e "${CYAN}Коды стран:${NC}"
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

ipset destroy geoblock 2>/dev/null || true
ipset create geoblock hash:net hashsize 8192

TOTAL=0
for CC in $COUNTRIES; do
    FILE="/tmp/${CC}.zone"
    wget -q "https://www.ipdeny.com/ipblocks/data/countries/${CC}.zone" -O "$FILE" 2>/dev/null

    if [ ! -s "$FILE" ]; then
        echo -e "${RED}  ${CC} — не найден или пустой, пропускаю${NC}"
        continue
    fi

    COUNT=$(wc -l < "$FILE")
    while read cidr; do
        ipset add geoblock "$cidr" 2>/dev/null
    done < "$FILE"

    TOTAL=$((TOTAL + COUNT))
    echo -e "${GREEN}  ${CC} — ${COUNT} подсетей${NC}"
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

# --- Cron ---
EXISTING_CRON=$(crontab -l 2>/dev/null | grep -v geoblock || true)
echo "$EXISTING_CRON" | { cat; echo "@reboot /opt/geoblock.sh >> /var/log/geoblock.log 2>&1"; echo "0 4 * * 0 /opt/geoblock.sh >> /var/log/geoblock.log 2>&1"; } | crontab -

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
echo -e "  Добавить страну:      ${GREEN}Редактируй COUNTRIES в /opt/geoblock.sh и запусти его${NC}"
echo -e "  Логи:                 ${GREEN}cat /var/log/geoblock.log${NC}"
echo ""
echo -e "${YELLOW}Списки IP обновляются автоматически каждое воскресенье в 4:00${NC}"
echo ""
echo -e "${GREEN}Готово!${NC}"
