# TG WS Proxy Go

Это Go версия `tg-ws-proxy` без Python GUI и без desktop обвязки

Проект нужен для запуска минимального Telegram `SOCKS5` proxy core на слабом устройстве вроде OpenWrt роутера

Главная идея простая

- убрать тяжёлый Python runtime
- оставить только нужное proxy ядро
- запускать всё одним Go бинарником

## Что умеет

- поднимает локальный `SOCKS5` прокси
- распознаёт Telegram трафик
- достаёт `DC` из `MTProto init`
- пытается перевести Telegram трафик в `TLS + WebSocket`
- если не вышло идёт в прямой `TCP fallback`
- умеет `WS pool`
- умеет `cooldown` и `blacklist`
- пишет runtime stats

## Текущее состояние

Сейчас проект уже рабочий

- есть сборка под `OpenWrt`
- есть `GitHub Actions` для тестов и сборки

Целевой роутер под который всё и делалось

- `Xiaomi Mi Router 4A Gigabit Edition v2`
- `OpenWrt 24.10.5`
- `ramips/mt7621`
- `mipsel_24kc`

Целевая сборка такая

```bash
GOOS=linux GOARCH=mipsle GOMIPS=softfloat
```

## Как это работает

```text
Telegram client -> SOCKS5 -> tg-ws-proxy -> WSS or TCP -> Telegram DC
```

Если запускать бинарник руками локально то он по умолчанию слушает `127.0.0.1:1080`

Для роутера нормальный дефолт это `0.0.0.0:1080`

В `tg-ws-proxy-go.sh` для роутера это уже стоит по умолчанию

## Быстрый старт локально

Собрать

```bash
go build ./cmd/tg-ws-proxy
```

Запустить

```bash
./tg-ws-proxy --host 127.0.0.1 --port 1080 --verbose
```

Что поставить в Telegram

- тип `SOCKS5`
- host `127.0.0.1`
- port `1080`
- username пусто
- password пусто

## Быстрый старт на роутере

Поставить manager script на роутер

```bash
wget -O /tmp/tg-ws-proxy-go.sh https://raw.githubusercontent.com/d0mhate/-tg-ws-proxy-Manager-go/main/tg-ws-proxy-go.sh
sh /tmp/tg-ws-proxy-go.sh
```

Дальше внутри script можно просто выбрать `Install or update binary`

Если нужен запуск без меню

```bash
wget -O /tmp/tg-ws-proxy-go.sh https://raw.githubusercontent.com/d0mhate/-tg-ws-proxy-Manager-go/main/tg-ws-proxy-go.sh
sh /tmp/tg-ws-proxy-go.sh install
sh /tmp/tg-ws-proxy-go.sh start
```

Во время `start` прокси работает в foreground

Логи идут прямо в терминал

Остановка через `Ctrl+C`

`install` сначала ищет локальный binary в `/tmp/tg-ws-proxy-openwrt`

Если файла нет, script сам пробует скачать готовый OpenWrt binary из `latest release`

## Что делает tg-ws-proxy-go.sh

`tg-ws-proxy-go.sh` это простой manager script для роутера

По умолчанию он поднимает прокси на `0.0.0.0:1080`

Он

- берёт локальный binary из `/tmp/tg-ws-proxy-openwrt`
- если локального файла нет, скачивает binary из GitHub Release
- копирует его в `/tmp/tg-ws-proxy-go/tg-ws-proxy`
- умеет `install`
- умеет `start`
- умеет `stop`
- умеет `restart`
- умеет показывать настройки для Telegram

Команды такие

```bash
sh tg-ws-proxy-go.sh install
sh tg-ws-proxy-go.sh start
sh tg-ws-proxy-go.sh stop
sh tg-ws-proxy-go.sh restart
sh tg-ws-proxy-go.sh status
sh tg-ws-proxy-go.sh quick
sh tg-ws-proxy-go.sh telegram
sh tg-ws-proxy-go.sh remove
```

## Флаги CLI

Основные флаги

| flag | default | meaning |
|---|---|---|
| `--host` | `127.0.0.1` | где слушать `SOCKS5` |
| `--port` | `1080` | порт `SOCKS5` |
| `--verbose` | `false` | подробные логи |
| `--buf-kb` | `256` | socket buffer в KB |
| `--pool-size` | `1` | idle `WS` connections на bucket |
| `--dial-timeout` | `10s` | timeout TCP dial |
| `--init-timeout` | `15s` | timeout чтения `MTProto init` |
| `--dc-ip` | built-in defaults | override target IP for DC |

Пример

```bash
./tg-ws-proxy --host 0.0.0.0 --port 1080 --verbose
```

## Встроенные default DC IP

По умолчанию используются

```text
1 -> 149.154.175.205
2 -> 149.154.167.220
4 -> 149.154.167.220
5 -> 91.108.56.100
```

Если нужно их можно переопределить через `--dc-ip`

Пример

```bash
./tg-ws-proxy --dc-ip 2:149.154.167.220 --dc-ip 4:149.154.167.220
```

## Тесты

Запуск

```bash
go test ./...
```

В репозитории уже есть CI

- `go test ./...`
- `go build ./cmd/tg-ws-proxy`
- кросс сборка `linux/mipsle`

## Releases

В репозитории есть release workflow

Он срабатывает по тегу вида `v*`

Например

```bash
git tag v0.1.0
git push origin v0.1.0
```

После этого в GitHub Release появится asset

```text
tg-ws-proxy-openwrt
```

Именно его `tg-ws-proxy-go.sh` и скачивает при установке с репозитория

## Что было раньше

Раньше это был Python desktop проект

Сейчас репозиторий это Go only версия вокруг минимального proxy core для роутера

## Лицензия

[MIT License](LICENSE)
