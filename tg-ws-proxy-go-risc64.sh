#!/bin/sh
# ==========================================
# TG WS Proxy Go - Installer for riscv64
# Repository: guglovich/-tg-ws-proxy-Manager-go-risc64
# ==========================================

REPO="guglovich/-tg-ws-proxy-Manager-go-risc64"
BIN_NAME="tg-ws-proxy-openwrt-riscv64"
BIN_PATH="/usr/bin/tg-ws-proxy-go"
INIT_PATH="/etc/init.d/tg-ws-proxy-go"
CONF_PATH="/etc/tg-ws-proxy-go.conf"

# Colors
GREEN="\033[1;32m"
RED="\033[1;31m"
CYAN="\033[1;36m"
YELLOW="\033[1;33m"
MAGENTA="\033[1;35m"
NC="\033[0m"

pause() { echo -ne "\n${YELLOW}Нажмите Enter...${NC}"; read dummy; }

# ==========================================
# Config management
# ==========================================
load_config() {
    HOST="127.0.0.1"
    PORT=1080
    USERNAME=""
    PASSWORD=""
    VERBOSE="false"

    if [ -f "$CONF_PATH" ]; then
        . "$CONF_PATH"
    fi
}

save_config() {
    cat > "$CONF_PATH" << EOF
HOST="${HOST}"
PORT=${PORT}
USERNAME="${USERNAME}"
PASSWORD="${PASSWORD}"
VERBOSE="${VERBOSE}"
EOF
}

# ==========================================
# Get latest version from GitHub
# ==========================================
get_latest_tag() {
    LATEST_TAG=$(curl -s "https://api.github.com/repos/${REPO}/releases/latest" | grep '"tag_name"' | head -1 | sed 's/.*"tag_name": "\(.*\)".*/\1/')
    if [ -z "$LATEST_TAG" ]; then
        # Fallback: try to get from redirect
        LATEST_TAG=$(curl -sL -o /dev/null -w '%{url_effective}' "https://github.com/${REPO}/releases/latest" | sed 's#.*/tag/##')
    fi
    if [ -z "$LATEST_TAG" ]; then
        echo ""
        return 1
    fi
    echo "$LATEST_TAG"
}

# ==========================================
# Build command line from config
# ==========================================
build_cmd() {
    CMD="${BIN_PATH} --host ${HOST} --port ${PORT}"
    if [ -n "$USERNAME" ] && [ -n "$PASSWORD" ]; then
        CMD="${CMD} --username ${USERNAME} --password ${PASSWORD}"
    fi
    if [ "$VERBOSE" = "true" ]; then
        CMD="${CMD} --verbose"
    fi
    echo "$CMD"
}

# ==========================================
# Install / Update
# ==========================================
do_install() {
    local UPDATE=$1
    
    if [ "$UPDATE" = "1" ]; then
        echo -e "\n${MAGENTA}Обновление TG WS Proxy Go${NC}"
    else
        echo -e "\n${MAGENTA}Установка TG WS Proxy Go${NC}"
    fi

    # Get latest tag
    LATEST_TAG=$(get_latest_tag)
    if [ -z "$LATEST_TAG" ]; then
        echo -e "${RED}Не удалось получить версию${NC}"
        return 1
    fi
    echo -e "${CYAN}Последняя версия: ${NC}${LATEST_TAG}"

    # Download
    DOWNLOAD_URL="https://github.com/${REPO}/releases/download/${LATEST_TAG}/${BIN_NAME}"
    echo -e "${CYAN}Скачиваем: ${NC}${BIN_NAME}"
    
    if ! curl -sL --fail -o "$BIN_PATH" "$DOWNLOAD_URL"; then
        echo -e "${RED}Ошибка скачивания!${NC}"
        echo -e "${RED}URL: ${NC}${DOWNLOAD_URL}"
        return 1
    fi
    
    chmod +x "$BIN_PATH"
    echo -e "${GREEN}Бинарник установлен: ${NC}${BIN_PATH} ($(du -h "$BIN_PATH" | cut -f1))"

    # Create config if not exists
    if [ ! -f "$CONF_PATH" ]; then
        echo -e "${CYAN}Создаём конфиг: ${NC}${CONF_PATH}"
        load_config
        save_config
    fi

    # Create init script
    echo -e "${CYAN}Создаём init-скрипт${NC}"
    cat > "$INIT_PATH" << 'INITEOF'
#!/bin/sh /etc/rc.common
START=99
USE_PROCD=1
CONF="/etc/tg-ws-proxy-go.conf"

load_conf() {
    HOST="127.0.0.1"
    PORT=1080
    USERNAME=""
    PASSWORD=""
    VERBOSE="false"
    [ -f "$CONF" ] && . "$CONF"
}

build_cmd() {
    CMD="/usr/bin/tg-ws-proxy-go --host ${HOST} --port ${PORT}"
    [ -n "$USERNAME" ] && [ -n "$PASSWORD" ] && CMD="${CMD} --username ${USERNAME} --password ${PASSWORD}"
    [ "$VERBOSE" = "true" ] && CMD="${CMD} --verbose"
    echo "$CMD"
}

start_service() {
    load_conf
    CMD=$(build_cmd)
    procd_open_instance
    procd_set_param command $CMD
    procd_set_param respawn
    procd_set_param stdout /dev/null
    procd_set_param stderr /dev/null
    procd_close_instance
}
INITEOF
    chmod +x "$INIT_PATH"

    # Enable and start
    /etc/init.d/tg-ws-proxy-go enable
    /etc/init.d/tg-ws-proxy-go restart
    sleep 1

    # Check
    if pidof tg-ws-proxy-go >/dev/null 2>&1; then
        LAN_IP=$(uci get network.lan.ipaddr 2>/dev/null | cut -d/ -f1)
        echo -e "\n${GREEN}=== УСПЕШНО! ===${NC}"
        echo -e "${YELLOW}Версия: ${NC}${LATEST_TAG}"
        echo -e "${YELLOW}SOCKS5 прокси запущен на ${CYAN}${HOST}:${PORT}${NC}"
        if [ "$HOST" = "0.0.0.0" ] || [ "$HOST" = "127.0.0.1" ]; then
            echo -e "${YELLOW}Telegram настройки: ${CYAN}${LAN_IP}:${PORT}${NC}"
        else
            echo -e "${YELLOW}Telegram настройки: ${CYAN}${HOST}:${PORT}${NC}"
        fi
        if [ -n "$USERNAME" ]; then
            echo -e "${YELLOW}Авторизация: ${CYAN}включена${NC}"
        fi
    else
        echo -e "\n${RED}=== ОШИБКА! ===${NC}"
        echo -e "${RED}Сервис не запустился${NC}"
        logread 2>/dev/null | grep tg-ws-proxy | tail -5
        return 1
    fi
}

# ==========================================
# Start
# ==========================================
do_start() {
    if pidof tg-ws-proxy-go >/dev/null 2>&1; then
        echo -e "${YELLOW}Прокси уже запущен${NC} (PID: $(pidof tg-ws-proxy-go))"
        return 0
    fi
    echo -e "${MAGENTA}Запуск TG WS Proxy Go${NC}"
    /etc/init.d/tg-ws-proxy-go start
    sleep 1
    if pidof tg-ws-proxy-go >/dev/null 2>&1; then
        echo -e "${GREEN}Прокси запущен!${NC}"
    else
        echo -e "${RED}Ошибка запуска!${NC}"
        return 1
    fi
}

# ==========================================
# Stop
# ==========================================
do_stop() {
    if ! pidof tg-ws-proxy-go >/dev/null 2>&1; then
        echo -e "${YELLOW}Прокси не запущен${NC}"
        return 0
    fi
    echo -e "${MAGENTA}Остановка TG WS Proxy Go${NC}"
    /etc/init.d/tg-ws-proxy-go stop
    sleep 1
    if ! pidof tg-ws-proxy-go >/dev/null 2>&1; then
        echo -e "${GREEN}Прокси остановлен!${NC}"
    else
        echo -e "${RED}Ошибка остановки!${NC}"
        return 1
    fi
}

# ==========================================
# Status
# ==========================================
do_status() {
    echo -e "\n${MAGENTA}=== Статус TG WS Proxy Go ===${NC}"
    
    if [ -f "$BIN_PATH" ]; then
        echo -e "${YELLOW}Бинарник: ${GREEN}установлен${NC} ($(du -h "$BIN_PATH" | cut -f1))"
    else
        echo -e "${YELLOW}Бинарник: ${RED}не установлен${NC}"
    fi
    
    if pidof tg-ws-proxy-go >/dev/null 2>&1; then
        echo -e "${YELLOW}Сервис: ${GREEN}запущен${NC} (PID: $(pidof tg-ws-proxy-go))"
    else
        echo -e "${YELLOW}Сервис: ${RED}остановлен${NC}"
    fi
    
    if [ -f "$CONF_PATH" ]; then
        load_config
        echo -e "${YELLOW}Конфиг: ${CONF_PATH}"
        echo -e "  Host: ${CYAN}${HOST}${NC}"
        echo -e "  Port: ${CYAN}${PORT}${NC}"
        if [ -n "$USERNAME" ]; then
            echo -e "  Auth: ${CYAN}включена${NC}"
        else
            echo -e "  Auth: ${CYAN}выключена${NC}"
        fi
    fi
    
    if [ -f "$INIT_PATH" ]; then
        echo -e "${YELLOW}Init-скрипт: ${GREEN}есть${NC}"
    else
        echo -e "${YELLOW}Init-скрипт: ${RED}нет${NC}"
    fi
    
    LAN_IP=$(uci get network.lan.ipaddr 2>/dev/null | cut -d/ -f1)
    echo -e "${YELLOW}Telegram SOCKS5: ${CYAN}${LAN_IP}:${PORT}${NC}\n"
}

# ==========================================
# Configure
# ==========================================
do_configure() {
    load_config
    echo -e "\n${MAGENTA}Настройка TG WS Proxy Go${NC}"
    echo -e "${YELLOW}Текущие настройки:${NC}"
    echo -e "  Host: ${CYAN}${HOST}${NC}"
    echo -e "  Port: ${CYAN}${PORT}${NC}"
    echo -e "  Username: ${CYAN}${USERNAME}${NC}"
    echo -e "  Password: ${CYAN}****${NC}"
    echo -e "  Verbose: ${CYAN}${VERBOSE}${NC}"
    echo ""
    
    echo -ne "  Host [${HOST}]: "; read NEW_HOST
    [ -n "$NEW_HOST" ] && HOST="$NEW_HOST"
    
    echo -ne "  Port [${PORT}]: "; read NEW_PORT
    [ -n "$NEW_PORT" ] && PORT="$NEW_PORT"
    
    echo -ne "  Username (пусто = без auth) [${USERNAME}]: "; read NEW_USER
    if [ -n "$NEW_USER" ] || [ "$NEW_USER" = "" -a "$USERNAME" = "" ]; then
        USERNAME="$NEW_USER"
    fi
    
    if [ -n "$USERNAME" ]; then
        echo -ne "  Password: "; read NEW_PASS
        [ -n "$NEW_PASS" ] && PASSWORD="$NEW_PASS"
    else
        PASSWORD=""
    fi
    
    echo -ne "  Verbose [${VERBOSE}]: "; read NEW_VERB
    [ -n "$NEW_VERB" ] && VERBOSE="$NEW_VERB"
    
    save_config
    echo -e "\n${GREEN}Конфиг сохранён!${NC}"
    
    # Restart if running
    if pidof tg-ws-proxy-go >/dev/null 2>&1; then
        echo -e "${CYAN}Перезапуск...${NC}"
        /etc/init.d/tg-ws-proxy-go restart
        sleep 1
        if pidof tg-ws-proxy-go >/dev/null 2>&1; then
            echo -e "${GREEN}Перезапуск успешен!${NC}"
        else
            echo -e "${RED}Ошибка перезапуска!${NC}"
        fi
    fi
}

# ==========================================
# Uninstall
# ==========================================
do_uninstall() {
    echo -e "\n${MAGENTA}Удаление TG WS Proxy Go${NC}"
    
    /etc/init.d/tg-ws-proxy-go stop 2>/dev/null
    /etc/init.d/tg-ws-proxy-go disable 2>/dev/null
    
    rm -f "$BIN_PATH" "$INIT_PATH"
    
    echo -ne "${YELLOW}Удалить конфиг ${CONF_PATH}? [y/N]: "; read ANSWER
    if [ "$ANSWER" = "y" ] || [ "$ANSWER" = "Y" ]; then
        rm -f "$CONF_PATH"
        echo -e "${GREEN}Конфиг удалён${NC}"
    fi
    
    echo -e "${GREEN}TG WS Proxy Go удалён!${NC}\n"
}

# ==========================================
# Interactive menu
# ==========================================
show_menu() {
    while true; do
        clear
        echo -e "╔═══════════════════════════════════╗"
        echo -e "║  ${CYAN}TG WS Proxy Go - riscv64${NC}         ║"
        echo -e "╚═══════════════════════════════════╝"
        echo ""
        
        # Status line
        if pidof tg-ws-proxy-go >/dev/null 2>&1; then
            echo -e "  Сервис: ${GREEN}запущен${NC} (PID: $(pidof tg-ws-proxy-go))"
        else
            echo -e "  Сервис: ${RED}остановлен${NC}"
        fi
        
        if [ -f "$CONF_PATH" ]; then
            load_config
            echo -e "  Настройки: ${HOST}:${PORT}"
            [ -n "$USERNAME" ] && echo -e "  Auth: ${GREEN}включена${NC}"
        fi
        echo ""
        
        echo -e "${CYAN}1) ${GREEN}Установить / Обновить${NC}"
        echo -e "${CYAN}2) ${GREEN}Запустить${NC}"
        echo -e "${CYAN}3) ${GREEN}Остановить${NC}"
        echo -e "${CYAN}4) ${GREEN}Статус${NC}"
        echo -e "${CYAN}5) ${GREEN}Настройка (host, port, auth)${NC}"
        echo -e "${CYAN}6) ${GREEN}Удалить${NC}"
        echo -e "${CYAN}Enter) ${YELLOW}Выход${NC}"
        echo ""
        echo -ne "  Выбор: "
        
        read CHOICE
        case "$CHOICE" in
            1) do_install 0; pause;;
            2) do_start; pause;;
            3) do_stop; pause;;
            4) do_status; pause;;
            5) do_configure; pause;;
            6) do_uninstall; pause;;
            *) echo -e "\n${GREEN}Выход${NC}"; return;;
        esac
    done
}

# ==========================================
# Main
# ==========================================
case "${1}" in
    install)   do_install 0;;
    update)    do_install 1;;
    start)     do_start;;
    stop)      do_stop;;
    status)    do_status;;
    configure) do_configure;;
    uninstall) do_uninstall;;
    *)         show_menu;;
esac
