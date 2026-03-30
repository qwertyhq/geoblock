# GeoBlock

Block connections from specific countries on your Linux server. Uses `ipset` + `iptables` for kernel-level filtering — zero overhead, instant blocking.

## Quick Install

```bash
bash <(curl -sSL https://raw.githubusercontent.com/qwertyhq/geoblock/main/install.sh)
```

## What it does

1. Installs `ipset` if not present
2. Asks which port to protect (default: `8443`)
3. Shows country codes — you pick which to block
4. Downloads IP ranges from [ipdeny.com](https://www.ipdeny.com/ipblocks/)
5. Loads them into kernel-level ipset
6. Adds iptables DROP rule
7. Persists across reboots via cron
8. Auto-updates IP lists weekly (Sunday 4:00 AM)

## Example

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

## How it works

```
Incoming connection
       │
       ▼
   iptables
       │
       ├── IP in ipset "geoblock"? ──► DROP
       │
       └── No ──► ACCEPT (normal flow)
```

All filtering happens in the kernel — no userspace overhead. Existing connections are not affected; only new connections from blocked countries are dropped.

## Management

```bash
# Check active rule
iptables -L INPUT -n | head -5

# Count blocked networks
ipset list geoblock | grep -c '/'

# Update IP lists manually
bash /opt/geoblock.sh

# Remove block
iptables -D INPUT -p tcp --dport 8443 -m set --match-set geoblock src -j DROP

# Add/remove countries
nano /opt/geoblock.sh    # edit COUNTRIES="pk ir ua"
bash /opt/geoblock.sh    # apply

# View logs
cat /var/log/geoblock.log
```

## Supported Countries

The script shows a full list during installation. Any country with an [ISO 3166-1 alpha-2](https://en.wikipedia.org/wiki/ISO_3166-1_alpha-2) code is supported — 200+ countries.

## Requirements

- Linux (Debian/Ubuntu/CentOS)
- Root access
- `iptables` (pre-installed on most systems)
- `ipset` (auto-installed by script)

## Use Cases

- MTProto Proxy — block unwanted regions
- Game servers — region lock
- Any TCP service — geo-restrict access

## License

MIT
