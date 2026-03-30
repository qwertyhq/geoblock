# GeoBlock

Блокировка подключений из определённых стран на Linux-сервере. Использует `ipset` + `iptables` — фильтрация на уровне ядра, нулевая нагрузка, мгновенная блокировка.

## Установка

```bash
bash <(curl -sSL https://raw.githubusercontent.com/qwertyhq/geoblock/main/install.sh)
```

## Что делает

1. Устанавливает `ipset` если нет
2. Спрашивает какой порт защитить (по умолчанию `8443`)
3. Показывает список стран — выбираешь какие заблокировать
4. Скачивает IP-диапазоны с [ipdeny.com](https://www.ipdeny.com/ipblocks/)
5. Загружает в ipset (kernel-level)
6. Добавляет правило iptables DROP
7. Сохраняет после перезагрузки через cron
8. Автообновление списков IP каждое воскресенье в 4:00

## Пример

```
$ bash install.sh

╔══════════════════════════════════════════╗
║      GeoBlock — Country IP Blocker       ║
╚══════════════════════════════════════════╝

--- Какой порт защитить? ---
Порт [8443]: 8443

--- Какие страны заблокировать? ---

  pk Пакистан        ir Иран
  ua Украина          in Индия
  cn Китай            ...

Коды стран: pk ir

  pk — 774 подсетей
  ir — 1920 подсетей

Загружено 2694 подсетей
Правило добавлено
Автозагрузка настроена

Готово!
```

## Как работает

```
Входящее подключение
       │
       ▼
   iptables
       │
       ├── IP в списке "geoblock"? ──► DROP (заблокировано)
       │
       └── Нет ──► ACCEPT (пропущено)
```

Фильтрация в ядре — без нагрузки на сервер. Уже установленные соединения не затрагиваются — блокируются только новые подключения.

## Управление

```bash
# Проверить правило
iptables -L INPUT -n | head -5

# Количество заблокированных подсетей
ipset list geoblock | grep -c '/'

# Обновить списки IP вручную
bash /opt/geoblock.sh

# Убрать блокировку
iptables -D INPUT -p tcp --dport 8443 -m set --match-set geoblock src -j DROP

# Добавить/убрать страны
nano /opt/geoblock.sh    # измени COUNTRIES="pk ir ua"
bash /opt/geoblock.sh    # примени

# Логи
cat /var/log/geoblock.log
```

## Поддерживаемые страны

Скрипт показывает полный список при установке. Поддерживаются все страны с кодом [ISO 3166-1 alpha-2](https://en.wikipedia.org/wiki/ISO_3166-1_alpha-2) — 200+ стран.

## Требования

- Linux (Debian / Ubuntu / CentOS)
- Root-доступ
- `iptables` (есть на большинстве систем)
- `ipset` (устанавливается скриптом)

## Применение

- MTProto Proxy — блокировка нежелательных регионов
- Игровые серверы — региональная блокировка
- Любой TCP-сервис — гео-ограничение доступа

---

# GeoBlock (English)

Block connections from specific countries on your Linux server. Uses `ipset` + `iptables` for kernel-level filtering — zero overhead, instant blocking.

## Quick Install

```bash
bash <(curl -sSL https://raw.githubusercontent.com/qwertyhq/geoblock/main/install.sh)
```

## How it works

1. Installs `ipset` if not present
2. Asks which port to protect (default: `8443`)
3. Shows country codes — you pick which to block
4. Downloads IP ranges from [ipdeny.com](https://www.ipdeny.com/ipblocks/)
5. Loads them into kernel-level ipset
6. Adds iptables DROP rule
7. Persists across reboots via cron
8. Auto-updates IP lists weekly (Sunday 4:00 AM)

## Management

```bash
iptables -L INPUT -n | head -5        # check rule
ipset list geoblock | grep -c '/'     # count blocked networks
bash /opt/geoblock.sh                 # update lists
cat /var/log/geoblock.log             # view logs
```

## Requirements

- Linux (Debian/Ubuntu/CentOS), root access
- `iptables` + `ipset` (auto-installed)

## License

MIT
