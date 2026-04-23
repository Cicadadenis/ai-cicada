#!/bin/bash

set -e

LOG_FILE="$HOME/ollama_install.log"
CHAT_DIR="$HOME/.ai-cicada"

GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
MAGENTA='\033[0;35m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

detect_wsl() {
    # Check for WSL using multiple methods
    if [ -f /proc/sys/kernel/osrelease ] && grep -qi "microsoft\|wsl" /proc/sys/kernel/osrelease 2>/dev/null; then
        return 0
    fi
    if [ -f /proc/version ] && grep -qi "microsoft\|wsl" /proc/version 2>/dev/null; then
        return 0
    fi
    if [ -n "$WSL_DISTRO_NAME" ] || [ -n "$WSLENV" ]; then
        return 0
    fi
    return 1
}

detect_env() {
    # WSL check first (can also have apt)
    if detect_wsl; then
        ENV_TYPE="wsl"
        PKG_MANAGER="apt"
        SUDO="sudo"
        if [ -f /etc/hassio_supervisor ] || [ -d /config/custom_components ] 2>/dev/null; then
            # WSL with Home Assistant
            ENV_TYPE="wsl-ha"
            PKG_MANAGER="apk"
            SUDO=""
            CHAT_DIR="/config/.ai-cicada"
            LOG_FILE="/config/ai-cicada-install.log"
        fi
    elif [ -f /etc/hassio_supervisor ] || [ -f /etc/homeassistant ] || \
       [ -d /config/custom_components ] || \
       grep -qi "homeassistant\|hassio\|hassos" /proc/version 2>/dev/null || \
       grep -qi "homeassistant" /etc/os-release 2>/dev/null; then
        ENV_TYPE="homeassistant"
        PKG_MANAGER="apk"
        SUDO=""
        CHAT_DIR="/config/.ai-cicada"
        LOG_FILE="/config/ai-cicada-install.log"
    elif [ -n "$TERMUX_VERSION" ] || [ -d "/data/data/com.termux" ]; then
        ENV_TYPE="termux"
        PKG_MANAGER="pkg"
        SUDO=""
    elif command -v apt >/dev/null 2>&1; then
        ENV_TYPE="debian"
        PKG_MANAGER="apt"
        SUDO="sudo"
    elif command -v dnf >/dev/null 2>&1; then
        ENV_TYPE="fedora"
        PKG_MANAGER="dnf"
        SUDO="sudo"
    elif command -v pacman >/dev/null 2>&1; then
        ENV_TYPE="arch"
        PKG_MANAGER="pacman"
        SUDO="sudo"
    elif command -v apk >/dev/null 2>&1; then
        ENV_TYPE="alpine"
        PKG_MANAGER="apk"
        SUDO=""
    elif command -v zypper >/dev/null 2>&1; then
        ENV_TYPE="opensuse"
        PKG_MANAGER="zypper"
        SUDO="sudo"
    elif command -v xbps-install >/dev/null 2>&1; then
        ENV_TYPE="void"
        PKG_MANAGER="xbps-install"
        SUDO="sudo"
    else
        ENV_TYPE="unknown"
        PKG_MANAGER=""
        SUDO="sudo"
    fi
    log "Detected environment: $ENV_TYPE"
}

safe_tput_cols() {
    if command -v tput >/dev/null 2>&1 && tput cols >/dev/null 2>&1; then
        tput cols
    else
        echo 80
    fi
}

safe_tput_lines() {
    if command -v tput >/dev/null 2>&1 && tput lines >/dev/null 2>&1; then
        tput lines
    else
        echo 24
    fi
}

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG_FILE"
}

center_text() {
    local text="$1"
    local termwidth
    termwidth=$(safe_tput_cols)
    local clean
    clean=$(printf "%b" "$text" | sed 's/\x1b\[[0-9;]*m//g')
    local len=${#clean}
    local padding=$(( (termwidth - len) / 2 ))
    [ $padding -lt 0 ] && padding=0
    printf "%*s%b\n" "$padding" "" "$text"
}

press_any_key() {
    center_text "${YELLOW}Press any key to continue...${NC}"
    read -r dummy </dev/tty || true
}

repeat_char() {
    local char="$1"
    local count="$2"
    local i=0
    while [ $i -lt "$count" ]; do
        printf "%s" "$char"
        i=$(( i + 1 ))
    done
}

draw_box() {
    local width=60
    local termwidth
    termwidth=$(safe_tput_cols)
    local padding=$(( (termwidth - width) / 2 ))
    [ $padding -lt 0 ] && padding=0
    printf "%${padding}s+" ""
    repeat_char "-" $(( width - 2 ))
    printf "+\n"
    for line in "$@"; do
        printf "%${padding}s| %-56s |\n" "" "$line"
    done
    printf "%${padding}s+" ""
    repeat_char "-" $(( width - 2 ))
    printf "+\n"
}

spinner() {
    local pid=$1
    local spin='|/-\\'
    while kill -0 "$pid" 2>/dev/null; do
        local temp=${spin#?}
        printf "\r${BLUE}[%c] Processing...${NC}" "$spin"
        spin=$temp${spin%"$temp"}
        read -r -t 0.1 _ 2>/dev/null </dev/null || true
    done
    printf "\r%-30s\r" " "
}

timer_start() { START=$(date +%s); }
timer_end() {
    END=$(date +%s)
    printf "${GREEN}Time: %d sec${NC}\n" "$((END - START))"
}

show_logo() {
    clear
    printf "${MAGENTA}\n"
    center_text "  ####   ####  "
    center_text "  ## ##   ##   "
    center_text "  ####    ##   "
    center_text "  ## ##   ##   "
    center_text "  ## ##  ####  "
    printf "\n"
    center_text " ####  ####  ####  ####  ####  ####  "
    center_text "##    ##    ##    ##  ## ##  ## ##  ##"
    center_text "##    ####  ##    ###### ##  ## ##  ##"
    center_text "##    ##    ##    ##  ## ##  ## ##  ##"
    center_text " ####  ####  ####  ##  ## ####  ##  ##"
    printf "${NC}\n"
    local w; w=$(safe_tput_cols)
    local line=""; local i=0
    while [ $i -lt $w ]; do line="${line}-"; i=$(( i + 1 )); done
    printf "${MAGENTA}%s${NC}\n\n" "$line"
    center_text "${CYAN}* AI-CICADA INSTALLER v5.0 *${NC}"
    local display_env="$ENV_TYPE"
    case "$ENV_TYPE" in
        wsl|wsl-ha) display_env="WSL (Windows)" ;;
        homeassistant) display_env="Home Assistant" ;;
        termux) display_env="Termux (Android)" ;;
        debian) display_env="Debian/Ubuntu" ;;
        fedora) display_env="Fedora" ;;
        arch) display_env="Arch Linux" ;;
        alpine) display_env="Alpine Linux" ;;
        opensuse) display_env="openSUSE" ;;
        void) display_env="Void Linux" ;;
    esac
    center_text "${YELLOW}Platform: ${display_env}${NC}"
    if [ "$ENV_TYPE" = "homeassistant" ] || [ "$ENV_TYPE" = "wsl-ha" ]; then
        printf "\n"
        center_text "${GREEN}[Home Assistant mode] /config/.ai-cicada${NC}"
    fi
    printf "\n"
    local w2; w2=$(safe_tput_cols)
    local line2=""; local j=0
    while [ $j -lt $w2 ]; do line2="${line2}-"; j=$(( j + 1 )); done
    printf "${MAGENTA}%s${NC}\n\n" "$line2"
    press_any_key
}

draw_table_row() {
    local col1="$1"
    local col2="$2"
    local col3="$3"
    local col4="$4"
    local col5="$5"
    local color="${6:-$NC}"
    printf "${color}| ${CYAN}%-18s${NC} | ${MAGENTA}%-8s${NC} | ${YELLOW}%-10s${NC} | ${GREEN}%-8s${NC} | %-17s |\n" "$col1" "$col2" "$col3" "$col4" "$col5"
}

draw_table_separator() {
    printf "${NC}+--------------------+----------+------------+----------+-------------------+\n"
}

select_model() {
    clear
    center_text "${CYAN}Select Model:${NC}"
    printf "\n"
    
    # Print table header
    draw_table_separator
    draw_table_row "Модель" "RAM" "Скорость" "Качество" "Лучшее применение" "$NC"
    draw_table_separator
    
    if [ "$ENV_TYPE" = "homeassistant" ] || [ "$ENV_TYPE" = "wsl-ha" ]; then
        # Home Assistant optimized models
        printf "${GREEN}1)${NC} "; draw_table_row "qwen2.5-coder 1.5B" "2-4 GB" "⚡⚡⚡⚡⚡⚡" "⭐⭐⭐" "код/HA рекоменд." "$NC"
        printf "${GREEN}2)${NC} "; draw_table_row "qwen2.5-coder 3B" "4-6 GB" "🚀🚀🚀🚀🚀" "⭐⭐⭐⭐" "код (выбор)" "$NC"
        printf "${GREEN}3)${NC} "; draw_table_row "llama3.2 3B" "4-6 GB" "🚀🚀🚀🚀" "⭐⭐⭐⭐" "чат/логика" "$NC"
        printf "${GREEN}4)${NC} "; draw_table_row "phi3 mini" "2-4 GB" "⚡⚡⚡⚡⚡⚡" "⭐⭐" "слабые устр." "$NC"
        printf "${GREEN}5)${NC} "; draw_table_row "mistral 7B" "10-14 GB" "⚖️" "⭐⭐⭐⭐" "мощь (медленно)" "$NC"
        printf "${GREEN}6)${NC} "; draw_table_row "Вручную" "-" "-" "-" "другая модель" "$NC"
        draw_table_separator
        
        printf "\n${YELLOW}Выбор (1-6): ${NC}"
        read -r choice </dev/tty
        case $choice in
            1) MODEL="qwen2.5-coder:1.5b" ;;
            2) MODEL="qwen2.5-coder:3b" ;;
            3) MODEL="llama3.2:3b" ;;
            4) MODEL="phi3:mini" ;;
            5) MODEL="mistral:7b" ;;
            6) printf "${YELLOW}Enter model name: ${NC}"; read -r MODEL </dev/tty ;;
            *) printf "${RED}Invalid choice${NC}\n"; sleep 2; select_model; return ;;
        esac
    else
        # Standard models
        printf "${GREEN}1)${NC} "; draw_table_row "qwen2.5-coder 3B" "4-6 GB" "🚀🚀🚀🚀🚀" "⭐⭐⭐⭐" "код (выбор)" "$NC"
        printf "${GREEN}2)${NC} "; draw_table_row "llama3 8B" "12-16 GB" "🐢🐢" "⭐⭐⭐⭐⭐" "чат / логика" "$NC"
        printf "${GREEN}3)${NC} "; draw_table_row "mistral 7B" "10-14 GB" "⚖️" "⭐⭐⭐⭐" "универсал" "$NC"
        printf "${GREEN}4)${NC} "; draw_table_row "phi3 mini" "2-4 GB" "⚡⚡⚡⚡⚡⚡" "⭐⭐" "слабые устройства" "$NC"
        printf "${GREEN}5)${NC} "; draw_table_row "Вручную" "-" "-" "-" "другая модель" "$NC"
        draw_table_separator
        
        printf "\n${YELLOW}Выбор (1-5): ${NC}"
        read -r choice </dev/tty
        case $choice in
            1) MODEL="qwen2.5-coder:3b" ;;
            2) MODEL="llama3:8b" ;;
            3) MODEL="mistral:7b" ;;
            4) MODEL="phi3:mini" ;;
            5) printf "${YELLOW}Enter model name: ${NC}"; read -r MODEL </dev/tty ;;
            *) printf "${RED}Invalid choice${NC}\n"; sleep 2; select_model; return ;;
        esac
    fi
    log "Selected model: $MODEL"
    printf "\n${GREEN}✓ Выбрана модель: $MODEL${NC}\n"
    sleep 1
    clear
}

fix_termux_libs() {
    [ "$ENV_TYPE" != "termux" ] && return
    if ! (sleep 0 >/dev/null 2>&1); then
        printf "${YELLOW}⚠  Termux: broken libpcre2, fixing...${NC}\n"
        pkg install -y pcre2 2>&1 | tail -3 || true
        printf "${GREEN}✓ pcre2 fixed${NC}\n"
    fi
}

fix_dpkg_termux() {
    echo N | dpkg --configure -a >> "$LOG_FILE" 2>&1 || true
}

update_system() {
    printf "${BLUE}🔄 Обновление системы...${NC}\n"
    timer_start
    case $ENV_TYPE in
        termux)
            fix_dpkg_termux
            (yes N | pkg update -y >> "$LOG_FILE" 2>&1 && yes N | pkg upgrade -y >> "$LOG_FILE" 2>&1) &
            spinner $!
            ;;
        debian|wsl)
            (sudo DEBIAN_FRONTEND=noninteractive apt update -y >> "$LOG_FILE" 2>&1 && \
             sudo DEBIAN_FRONTEND=noninteractive apt upgrade -y \
               -o Dpkg::Options::="--force-confold" \
               -o Dpkg::Options::="--force-confdef" >> "$LOG_FILE" 2>&1) &
            spinner $!
            ;;
        fedora)
            (sudo dnf update -y >> "$LOG_FILE" 2>&1) &
            spinner $!
            ;;
        arch)
            (sudo pacman -Syu --noconfirm >> "$LOG_FILE" 2>&1) &
            spinner $!
            ;;
        homeassistant|alpine|wsl-ha)
            (apk update >> "$LOG_FILE" 2>&1) &
            spinner $!
            ;;
        opensuse)
            (sudo zypper refresh >> "$LOG_FILE" 2>&1 && sudo zypper update -y >> "$LOG_FILE" 2>&1) &
            spinner $!
            ;;
        void)
            (sudo xbps-install -Syu >> "$LOG_FILE" 2>&1) &
            spinner $!
            ;;
        *)
            printf "${YELLOW}⚠  Неизвестный пакетный менеджер, обновление пропущено${NC}\n"
            return
            ;;
    esac
    timer_end
}

install_nodejs() {
    printf "${BLUE}Checking Node.js...${NC}\n"
    if command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1; then
        local ver; ver=$(node --version 2>/dev/null)
        printf "${GREEN}Node.js already installed (%s)${NC}\n" "$ver"
        return
    fi
    printf "${BLUE}Installing Node.js...${NC}\n"
    timer_start
    case $ENV_TYPE in
        termux)   (yes N | pkg install -y nodejs >> "$LOG_FILE" 2>&1) & spinner $! ;;
        debian|wsl)   (sudo DEBIAN_FRONTEND=noninteractive apt install -y nodejs npm >> "$LOG_FILE" 2>&1) & spinner $! ;;
        fedora)   (sudo dnf install -y nodejs npm >> "$LOG_FILE" 2>&1) & spinner $! ;;
        arch)     (sudo pacman -S --noconfirm nodejs npm >> "$LOG_FILE" 2>&1) & spinner $! ;;
        homeassistant|alpine|wsl-ha) (apk add --no-cache nodejs npm >> "$LOG_FILE" 2>&1) & spinner $! ;;
        opensuse) (sudo zypper install -y nodejs npm >> "$LOG_FILE" 2>&1) & spinner $! ;;
        void)     (sudo xbps-install -y nodejs >> "$LOG_FILE" 2>&1) & spinner $! ;;
        *) printf "${YELLOW}Please install Node.js manually${NC}\n"; return ;;
    esac
    timer_end
    if command -v node >/dev/null 2>&1; then
        printf "${GREEN}Node.js installed: %s${NC}\n" "$(node --version)"
    else
        printf "${RED}Node.js installation failed. Check %s${NC}\n" "$LOG_FILE"
        exit 1
    fi
}

install_sqlite_tools() {
    printf "${BLUE}Checking SQLite tools...${NC}\n"
    if command -v sqlite3 >/dev/null 2>&1; then
        printf "${GREEN}sqlite3 already available${NC}\n"
        return
    fi
    case $ENV_TYPE in
        termux)   (yes N | pkg install -y sqlite >> "$LOG_FILE" 2>&1) & spinner $! ;;
        debian|wsl)   (sudo apt install -y sqlite3 >> "$LOG_FILE" 2>&1) & spinner $! ;;
        fedora)   (sudo dnf install -y sqlite >> "$LOG_FILE" 2>&1) & spinner $! ;;
        arch)     (sudo pacman -S --noconfirm sqlite >> "$LOG_FILE" 2>&1) & spinner $! ;;
        homeassistant|alpine|wsl-ha) (apk add --no-cache sqlite >> "$LOG_FILE" 2>&1) & spinner $! ;;
        opensuse) (sudo zypper install -y sqlite3 >> "$LOG_FILE" 2>&1) & spinner $! ;;
        void)     (sudo xbps-install -y sqlite >> "$LOG_FILE" 2>&1) & spinner $! ;;
    esac
    printf "${GREEN}SQLite tools ready${NC}\n"
}

install_python() {
    if [ "$ENV_TYPE" != "termux" ]; then return; fi
    printf "${BLUE}Checking Python3 (Termux)...${NC}\n"
    if command -v python3 >/dev/null 2>&1; then
        printf "${GREEN}Python3 already installed (%s)${NC}\n" "$(python3 --version 2>&1)"; return
    fi
    timer_start
    (yes N | pkg install -y python >> "$LOG_FILE" 2>&1) & spinner $!
    timer_end
    command -v python3 >/dev/null 2>&1 && printf "${GREEN}Python3 ready${NC}\n" || { printf "${RED}Python3 failed${NC}\n"; exit 1; }
}

install_ollama() {
    printf "${BLUE}Checking Ollama...${NC}\n"
    if command -v ollama >/dev/null 2>&1; then
        printf "${GREEN}Ollama already installed${NC}\n"
        return
    fi
    printf "${BLUE}Installing Ollama...${NC}\n"
    timer_start
    case $ENV_TYPE in
        termux)
            if pkg show ollama >/dev/null 2>&1; then
                (yes N | pkg install -y ollama >> "$LOG_FILE" 2>&1) &
                spinner $!
            else
                printf "${YELLOW}Ollama not in pkg repos, using proot-distro...${NC}\n"
                (yes N | pkg install -y proot-distro >> "$LOG_FILE" 2>&1)
                proot-distro install ubuntu >> "$LOG_FILE" 2>&1
                proot-distro login ubuntu -- bash -c "curl -fsSL https://ollama.com/install.sh | sh" >> "$LOG_FILE" 2>&1 &
                spinner $!
                printf '#!/bin/sh\nproot-distro login ubuntu -- ollama "$@"\n' > "$PREFIX/bin/ollama"
                chmod +x "$PREFIX/bin/ollama"
            fi
            ;;
        homeassistant|wsl-ha)
            printf "${YELLOW}Home Assistant: installing Ollama binary for Alpine/musl...${NC}\n"
            ARCH=$(uname -m)
            case $ARCH in
                x86_64)  OLLAMA_BIN="ollama-linux-amd64" ;;
                aarch64) OLLAMA_BIN="ollama-linux-arm64" ;;
                armv7l)  OLLAMA_BIN="ollama-linux-arm" ;;
                *)
                    printf "${RED}Unsupported arch: %s${NC}\n" "$ARCH"
                    exit 1
                    ;;
            esac
            (curl -fsSL "https://github.com/ollama/ollama/releases/latest/download/${OLLAMA_BIN}" \
                -o /usr/local/bin/ollama >> "$LOG_FILE" 2>&1 && \
             chmod +x /usr/local/bin/ollama) &
            spinner $!
            ;;
        wsl)
            printf "${YELLOW}WSL: installing Ollama...${NC}\n"
            if ! command -v zstd >/dev/null 2>&1; then
                printf "${BLUE}Installing zstd...${NC}\n"
                sudo DEBIAN_FRONTEND=noninteractive apt install -y zstd >> "$LOG_FILE" 2>&1
            fi
            curl -fsSL https://ollama.com/install.sh | sh >> "$LOG_FILE" 2>&1 &
            spinner $!
            ;;
        *)
            curl -fsSL https://ollama.com/install.sh | sh >> "$LOG_FILE" 2>&1 &
            spinner $!
            ;;
    esac
    timer_end
    if command -v ollama >/dev/null 2>&1; then
        printf "${GREEN}Ollama installed${NC}\n"
    else
        printf "${RED}Ollama installation failed. Check %s${NC}\n" "$LOG_FILE"
        exit 1
    fi
}

start_ollama_service() {
    printf "${BLUE}Starting Ollama service...${NC}\n"
    if pgrep -x "ollama" > /dev/null 2>&1; then
        printf "${GREEN}Ollama already running${NC}\n"
        return
    fi
    case $ENV_TYPE in
        termux)
            OLLAMA_ORIGINS='*' ollama serve >> "$LOG_FILE" 2>&1 &
            ;;
        homeassistant|wsl-ha)
            OLLAMA_ORIGINS='*' ollama serve >> "$LOG_FILE" 2>&1 &
            printf "${YELLOW}Ollama running in background. After reboot run: OLLAMA_ORIGINS='*' ollama serve &${NC}\n"
            ;;
        wsl)
            if command -v systemctl >/dev/null 2>&1 && systemctl is-system-running >/dev/null 2>&1; then
                sudo systemctl enable --now ollama >> "$LOG_FILE" 2>&1 || OLLAMA_ORIGINS='*' ollama serve >> "$LOG_FILE" 2>&1 &
            else
                printf "${YELLOW}WSL: Starting Ollama in background (no systemd)${NC}\n"
                OLLAMA_ORIGINS='*' ollama serve >> "$LOG_FILE" 2>&1 &
            fi
            ;;
        *)
            if command -v systemctl >/dev/null 2>&1; then
                sudo systemctl enable --now ollama >> "$LOG_FILE" 2>&1 || OLLAMA_ORIGINS='*' ollama serve >> "$LOG_FILE" 2>&1 &
            else
                OLLAMA_ORIGINS='*' ollama serve >> "$LOG_FILE" 2>&1 &
            fi
            ;;
    esac
    sleep 3
    printf "${GREEN}Ollama service started${NC}\n"
}

install_model() {
    printf "${BLUE}Checking model: %s${NC}\n" "$MODEL"
    if ollama list 2>/dev/null | grep -q "$MODEL"; then
        printf "${GREEN}Model already installed${NC}\n"
        return
    fi
    printf "${BLUE}Downloading %s...${NC}\n" "$MODEL"
    timer_start
    log "Downloading model: $MODEL"
    ollama pull "$MODEL" 2>&1 | while IFS= read -r line; do
        if echo "$line" | grep -qE '[0-9]+%'; then
            percent=$(echo "$line" | grep -oE '[0-9]+%' | tail -1)
            printf "\r${GREEN}Downloading: %-6s${NC}" "$percent"
        fi
        echo "$line" >> "$LOG_FILE"
    done
    printf "\n"
    timer_end
    printf "${GREEN}Model %s installed${NC}\n" "$MODEL"
}

install_npm_deps() {
    printf "${BLUE}Installing npm dependencies (better-sqlite3)...${NC}\n"
    mkdir -p "$CHAT_DIR"
    cd "$CHAT_DIR"
    cat > package.json << 'PKGEOF'
{
  "name": "ai-cicada",
  "version": "5.0.0",
  "main": "server.js",
  "dependencies": {
    "better-sqlite3": "^9.4.3",
    "axios": "^1.6.0"
  }
}
PKGEOF
    (npm install --save better-sqlite3 axios >> "$LOG_FILE" 2>&1) &
    spinner $!
    if [ -d "$CHAT_DIR/node_modules/better-sqlite3" ]; then
        printf "${GREEN}better-sqlite3 installed${NC}\n"
        DB_FALLBACK=0
    else
        printf "${YELLOW}better-sqlite3 failed, using in-memory fallback${NC}\n"
        DB_FALLBACK=1
    fi
    cd - > /dev/null
}

# Записываем server.js через python3 чтобы избежать проблем с heredoc в ash/busybox
create_server_js() {
    printf "${BLUE}Creating server.js...${NC}\n"
    python3 - "$CHAT_DIR/server.js" << 'PYEOF'
import sys

path = sys.argv[1]

code = r"""
const http   = require('http');
const fs     = require('fs');
const path   = require('path');
const crypto = require('crypto');
const https  = require('https');

const PORT       = 3000;
const MODEL      = process.env.AI_MODEL || 'qwen2.5-coder:3b';
const OLLAMA_URL = process.env.OLLAMA_HOST || 'http://localhost:11434';
const DB_PATH    = path.join(__dirname, 'cicada.db');
let axios = null;
try { axios = require('axios'); } catch(e) { console.log('axios not available, web search disabled'); }

/* ====== SQLite init ====== */
let db = null;

function initDB() {
    try {
        const Database = require('better-sqlite3');
        db = new Database(DB_PATH);
        db.pragma('journal_mode = WAL');
        db.pragma('foreign_keys = ON');
        db.exec(
            "CREATE TABLE IF NOT EXISTS users (" +
            "  id INTEGER PRIMARY KEY AUTOINCREMENT," +
            "  username TEXT UNIQUE NOT NULL," +
            "  password TEXT NOT NULL," +
            "  created_at INTEGER DEFAULT (strftime('%s','now'))," +
            "  total_msgs INTEGER DEFAULT 0," +
            "  preferences TEXT DEFAULT '{}'" +
            ");" +
            "CREATE TABLE IF NOT EXISTS chats (" +
            "  id TEXT PRIMARY KEY," +
            "  username TEXT NOT NULL," +
            "  title TEXT NOT NULL DEFAULT 'Новый чат'," +
            "  created_at INTEGER DEFAULT (strftime('%s','now'))," +
            "  updated_at INTEGER DEFAULT (strftime('%s','now'))," +
            "  FOREIGN KEY(username) REFERENCES users(username) ON DELETE CASCADE" +
            ");" +
            "CREATE TABLE IF NOT EXISTS messages (" +
            "  id INTEGER PRIMARY KEY AUTOINCREMENT," +
            "  chat_id TEXT NOT NULL," +
            "  role TEXT NOT NULL CHECK(role IN ('user','assistant','system'))," +
            "  content TEXT NOT NULL," +
            "  created_at INTEGER DEFAULT (strftime('%s','now'))," +
            "  FOREIGN KEY(chat_id) REFERENCES chats(id) ON DELETE CASCADE" +
            ");" +
            "CREATE TABLE IF NOT EXISTS memory (" +
            "  id INTEGER PRIMARY KEY AUTOINCREMENT," +
            "  username TEXT NOT NULL," +
            "  key TEXT NOT NULL," +
            "  value TEXT NOT NULL," +
            "  category TEXT DEFAULT 'general'," +
            "  created_at INTEGER DEFAULT (strftime('%s','now'))," +
            "  updated_at INTEGER DEFAULT (strftime('%s','now'))," +
            "  UNIQUE(username, key)" +
            ");" +
            "CREATE INDEX IF NOT EXISTS idx_chats_user ON chats(username);" +
            "CREATE INDEX IF NOT EXISTS idx_msgs_chat  ON messages(chat_id);" +
            "CREATE INDEX IF NOT EXISTS idx_memory_user ON memory(username);"
        );
        console.log('SQLite DB initialised: ' + DB_PATH);
    } catch(e) {
        console.warn('better-sqlite3 not available, using in-memory store:', e.message);
        db = null;
    }
}

/* ====== In-memory fallback ====== */
const mem = { users: {}, chats: {}, memory: {} };

function hashPwd(p) { return crypto.createHash('sha256').update(p).digest('hex'); }

/* ====== User API ====== */
function createUser(username, password) {
    if (db) {
        try {
            db.prepare('INSERT INTO users (username, password) VALUES (?, ?)').run(username, hashPwd(password));
            return true;
        } catch(e) { return false; }
    }
    if (mem.users[username]) return false;
    mem.users[username] = { password: hashPwd(password), created_at: Math.floor(Date.now()/1000), total_msgs: 0, preferences: {} };
    return true;
}

function getUser(username) {
    if (db) return db.prepare('SELECT * FROM users WHERE username=?').get(username) || null;
    return mem.users[username] ? Object.assign({}, mem.users[username], { username }) : null;
}

function checkPassword(username, password) {
    const u = getUser(username);
    if (!u) return false;
    return u.password === hashPwd(password);
}

function incUserMsgs(username) {
    if (db) { db.prepare('UPDATE users SET total_msgs=total_msgs+1 WHERE username=?').run(username); return; }
    if (mem.users[username]) mem.users[username].total_msgs = (mem.users[username].total_msgs || 0) + 1;
}

/* ====== Chat API ====== */
function getUserChats(username) {
    if (db) {
        return db.prepare(
            'SELECT c.*, COUNT(m.id) as msg_count FROM chats c ' +
            'LEFT JOIN messages m ON m.chat_id=c.id ' +
            'WHERE c.username=? GROUP BY c.id ORDER BY c.updated_at DESC'
        ).all(username);
    }
    return Object.values(mem.chats).filter(function(c){ return c.username === username; })
        .sort(function(a,b){ return b.updated_at - a.updated_at; });
}

function upsertChat(chatId, username, title) {
    if (db) {
        const existing = db.prepare('SELECT id FROM chats WHERE id=?').get(chatId);
        if (existing) {
            db.prepare("UPDATE chats SET title=?, updated_at=strftime('%s','now') WHERE id=?").run(title, chatId);
        } else {
            db.prepare('INSERT INTO chats (id, username, title) VALUES (?,?,?)').run(chatId, username, title);
        }
        return;
    }
    if (!mem.chats[chatId]) {
        mem.chats[chatId] = { id: chatId, username: username, title: title, messages: [], created_at: Math.floor(Date.now()/1000), updated_at: Math.floor(Date.now()/1000) };
    } else {
        mem.chats[chatId].title = title;
        mem.chats[chatId].updated_at = Math.floor(Date.now()/1000);
    }
}

function deleteChat(chatId) {
    if (db) {
        db.prepare('DELETE FROM messages WHERE chat_id=?').run(chatId);
        db.prepare('DELETE FROM chats WHERE id=?').run(chatId);
        return;
    }
    delete mem.chats[chatId];
}

function getChatMessages(chatId) {
    if (db) return db.prepare('SELECT role, content FROM messages WHERE chat_id=? ORDER BY id ASC').all(chatId);
    return mem.chats[chatId] ? mem.chats[chatId].messages : [];
}

function addMessage(chatId, role, content) {
    if (db) {
        db.prepare('INSERT INTO messages (chat_id, role, content) VALUES (?,?,?)').run(chatId, role, content);
        db.prepare("UPDATE chats SET updated_at=strftime('%s','now') WHERE id=?").run(chatId);
        return;
    }
    if (mem.chats[chatId]) {
        mem.chats[chatId].messages.push({ role: role, content: content });
        mem.chats[chatId].updated_at = Math.floor(Date.now()/1000);
    }
}

function getUserStats(username) {
    if (db) {
        const u = getUser(username);
        const chatCount = (db.prepare('SELECT COUNT(*) as n FROM chats WHERE username=?').get(username) || { n: 0 }).n;
        const msgCount  = (db.prepare(
            'SELECT COUNT(*) as n FROM messages m JOIN chats c ON c.id=m.chat_id WHERE c.username=?'
        ).get(username) || { n: 0 }).n;
        const memCount = (db.prepare('SELECT COUNT(*) as n FROM memory WHERE username=?').get(username) || { n: 0 }).n;
        return { total_msgs: (u && u.total_msgs) || 0, chat_count: chatCount, msg_count: msgCount, memory_count: memCount, created_at: u && u.created_at };
    }
    const u = mem.users[username] || {};
    const chats = Object.values(mem.chats).filter(function(c){ return c.username === username; });
    const mems = mem.memory[username] || {};
    return {
        total_msgs: u.total_msgs || 0,
        chat_count: chats.length,
        msg_count: chats.reduce(function(s,c){ return s + c.messages.length; }, 0),
        memory_count: Object.keys(mems).length,
        created_at: u.created_at
    };
}

/* ====== MEMORY SYSTEM ====== */
function setMemory(username, key, value, category) {
    category = category || 'general';
    if (db) {
        try {
            db.prepare('INSERT OR REPLACE INTO memory (username, key, value, category, updated_at) VALUES (?, ?, ?, ?, strftime("%s","now"))')
                .run(username, key, value, category);
            return true;
        } catch(e) { console.error('Memory save error:', e); return false; }
    }
    if (!mem.memory[username]) mem.memory[username] = {};
    mem.memory[username][key] = { value: value, category: category, updated_at: Math.floor(Date.now()/1000) };
    return true;
}

function getMemory(username, key) {
    if (db) {
        const row = db.prepare('SELECT value, category FROM memory WHERE username=? AND key=?').get(username, key);
        return row || null;
    }
    if (mem.memory[username] && mem.memory[username][key]) {
        return { value: mem.memory[username][key].value, category: mem.memory[username][key].category };
    }
    return null;
}

function getAllMemory(username, category) {
    if (db) {
        if (category) {
            return db.prepare('SELECT key, value, category, updated_at FROM memory WHERE username=? AND category=? ORDER BY updated_at DESC')
                .all(username, category);
        }
        return db.prepare('SELECT key, value, category, updated_at FROM memory WHERE username=? ORDER BY updated_at DESC')
            .all(username);
    }
    const userMem = mem.memory[username] || {};
    return Object.keys(userMem).map(function(k) {
        return { key: k, value: userMem[k].value, category: userMem[k].category, updated_at: userMem[k].updated_at };
    });
}

function deleteMemory(username, key) {
    if (db) {
        db.prepare('DELETE FROM memory WHERE username=? AND key=?').run(username, key);
        return;
    }
    if (mem.memory[username]) delete mem.memory[username][key];
}

function searchMemory(username, query) {
    if (db) {
        return db.prepare("SELECT key, value, category FROM memory WHERE username=? AND (key LIKE ? OR value LIKE ?)")
            .all(username, '%' + query + '%', '%' + query + '%');
    }
    const userMem = mem.memory[username] || {};
    const results = [];
    Object.keys(userMem).forEach(function(k) {
        if (k.toLowerCase().includes(query.toLowerCase()) || userMem[k].value.toLowerCase().includes(query.toLowerCase())) {
            results.push({ key: k, value: userMem[k].value, category: userMem[k].category });
        }
    });
    return results;
}

/* ====== WEB SEARCH ====== */
async function webSearch(query, maxResults) {
    maxResults = maxResults || 5;
    if (!axios) return { error: 'Web search not available (axios not installed)' };
    
    try {
        // DuckDuckGo HTML scraping approach
        const searchUrl = 'https://html.duckduckgo.com/html/?q=' + encodeURIComponent(query);
        const response = await axios.get(searchUrl, {
            headers: {
                'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
            },
            timeout: 10000
        });
        
        const html = response.data;
        const results = [];
        
        // Parse results from DuckDuckGo HTML
        const resultRegex = /<a rel="nofollow" class="result__a" href="([^"]+)"[^>]*>([^<]+)<\/a>/g;
        const snippetRegex = /<a rel="nofollow" class="result__snippet"[^>]*>([^<]+)<\/a>/g;
        
        let match;
        const titles = [];
        const urls = [];
        
        while ((match = resultRegex.exec(html)) !== null && urls.length < maxResults) {
            urls.push(match[1]);
            titles.push(match[2].replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>'));
        }
        
        for (let i = 0; i < urls.length; i++) {
            results.push({
                title: titles[i] || 'No title',
                url: urls[i],
                snippet: ''
            });
        }
        
        return { results: results, query: query };
    } catch(e) {
        console.error('Web search error:', e.message);
        return { error: 'Search failed: ' + e.message, results: [] };
    }
}

/* ====== TOOLS SYSTEM ====== */
const TOOLS = {
    web_search: {
        name: 'web_search',
        description: 'Search the web for current information',
        parameters: {
            query: { type: 'string', description: 'Search query' },
            max_results: { type: 'number', description: 'Maximum results (1-10)', default: 5 }
        }
    },
    memory_set: {
        name: 'memory_set',
        description: 'Save a fact or information to memory for later recall',
        parameters: {
            key: { type: 'string', description: 'Memory key/topic' },
            value: { type: 'string', description: 'Information to remember' },
            category: { type: 'string', description: 'Category (general, preference, fact)', default: 'general' }
        }
    },
    memory_get: {
        name: 'memory_get',
        description: 'Retrieve information from memory',
        parameters: {
            key: { type: 'string', description: 'Memory key to retrieve' }
        }
    },
    memory_search: {
        name: 'memory_search',
        description: 'Search through all stored memories',
        parameters: {
            query: { type: 'string', description: 'Search query' }
        }
    },
    calculate: {
        name: 'calculate',
        description: 'Perform mathematical calculations',
        parameters: {
            expression: { type: 'string', description: 'Mathematical expression' }
        }
    }
};

async function executeTool(toolName, args, username) {
    switch(toolName) {
        case 'web_search':
            return await webSearch(args.query, args.max_results || 5);
        case 'memory_set':
            const saved = setMemory(username, args.key, args.value, args.category || 'general');
            return { success: saved, key: args.key, message: 'Saved to memory: ' + args.key };
        case 'memory_get':
            const mem = getMemory(username, args.key);
            return mem || { error: 'Memory not found: ' + args.key };
        case 'memory_search':
            return { results: searchMemory(username, args.query) };
        case 'calculate':
            try {
                // Safe eval alternative
                const result = Function('"use strict"; return (' + args.expression + ')')();
                return { result: result, expression: args.expression };
            } catch(e) {
                return { error: 'Calculation failed: ' + e.message };
            }
        default:
            return { error: 'Unknown tool: ' + toolName };
    }
}

function formatToolsForPrompt() {
    let prompt = '\n\nYou have access to the following tools:\n';
    Object.keys(TOOLS).forEach(function(key) {
        const tool = TOOLS[key];
        prompt += '\n' + tool.name + ': ' + tool.description;
        prompt += '\n  Parameters:';
        Object.keys(tool.parameters).forEach(function(p) {
            const param = tool.parameters[p];
            prompt += '\n    - ' + p + ' (' + param.type + '): ' + param.description;
            if (param.default) prompt += ' [default: ' + param.default + ']';
        });
    });
    prompt += '\n\nTo use a tool, respond with JSON in this format:\n';
    prompt += '{"tool": "tool_name", "arguments": {"param1": "value1", ...}}\n';
    prompt += '\nThe system will execute the tool and return results.';
    return prompt;
}

/* ====== HTTP helpers ====== */
function parseBody(req) {
    return new Promise(function(resolve, reject) {
        var body = '';
        req.on('data', function(chunk) { body += chunk; });
        req.on('end', function() {
            try { resolve(JSON.parse(body)); } catch(e) { reject(new Error('Bad JSON')); }
        });
    });
}

function jsonOk(res, data) {
    res.writeHead(200, { 'Content-Type': 'application/json; charset=utf-8' });
    res.end(JSON.stringify(data));
}

function jsonErr(res, code, msg) {
    res.writeHead(code, { 'Content-Type': 'application/json; charset=utf-8' });
    res.end(JSON.stringify({ error: msg }));
}

/* ====== HTTP Server ====== */
const server = http.createServer(async function(req, res) {
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader('Access-Control-Allow-Methods', 'GET,POST,DELETE,OPTIONS');
    res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
    if (req.method === 'OPTIONS') { res.writeHead(204); res.end(); return; }

    const url = req.url.split('?')[0];

    /* Static */
    if (req.method === 'GET' && (url === '/' || url === '/index.html')) {
        const html = fs.readFileSync(path.join(__dirname, 'index.html'));
        res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
        res.end(html);
        return;
    }

    if (req.method === 'GET' && url === '/model') {
        return jsonOk(res, { model: MODEL, ollama_url: OLLAMA_URL, tools: Object.keys(TOOLS), web_search: !!axios });
    }

    /* Auth */
    if (req.method === 'POST' && url === '/api/register') {
        try {
            const body = await parseBody(req);
            const username = body.username; const password = body.password;
            if (!username || !password) return jsonErr(res, 400, 'username и password обязательны');
            if (username.length < 3) return jsonErr(res, 400, 'Логин минимум 3 символа');
            if (password.length < 4) return jsonErr(res, 400, 'Пароль минимум 4 символа');
            if (!createUser(username, password)) return jsonErr(res, 409, 'Логин уже занят');
            return jsonOk(res, { ok: true, username: username });
        } catch(e) { return jsonErr(res, 400, e.message); }
    }

    if (req.method === 'POST' && url === '/api/login') {
        try {
            const body = await parseBody(req);
            const username = body.username; const password = body.password;
            if (!username || !password) return jsonErr(res, 400, 'Заполните все поля');
            if (!getUser(username)) return jsonErr(res, 404, 'Пользователь не найден');
            if (!checkPassword(username, password)) return jsonErr(res, 401, 'Неверный пароль');
            const stats = getUserStats(username);
            return jsonOk(res, Object.assign({ ok: true, username: username }, stats));
        } catch(e) { return jsonErr(res, 400, e.message); }
    }

    if (req.method === 'GET' && url === '/api/stats') {
        const username = new URLSearchParams(req.url.split('?')[1] || '').get('user');
        if (!username) return jsonErr(res, 400, 'user required');
        return jsonOk(res, getUserStats(username));
    }

    /* Chats */
    if (req.method === 'GET' && url === '/api/chats') {
        const username = new URLSearchParams(req.url.split('?')[1] || '').get('user');
        if (!username) return jsonErr(res, 400, 'user required');
        return jsonOk(res, getUserChats(username));
    }

    if (req.method === 'POST' && url === '/api/chats') {
        try {
            const body = await parseBody(req);
            if (!body.chatId || !body.username) return jsonErr(res, 400, 'chatId и username обязательны');
            upsertChat(body.chatId, body.username, body.title || 'Новый чат');
            return jsonOk(res, { ok: true });
        } catch(e) { return jsonErr(res, 400, e.message); }
    }

    if (req.method === 'DELETE' && url.startsWith('/api/chats/')) {
        const chatId = url.slice('/api/chats/'.length);
        if (!chatId) return jsonErr(res, 400, 'chatId required');
        deleteChat(chatId);
        return jsonOk(res, { ok: true });
    }

    /* Messages */
    if (req.method === 'GET' && url.startsWith('/api/messages/')) {
        const chatId = url.slice('/api/messages/'.length);
        return jsonOk(res, getChatMessages(chatId));
    }

    if (req.method === 'POST' && url === '/api/messages') {
        try {
            const body = await parseBody(req);
            if (!body.chatId || !body.role || !body.content) return jsonErr(res, 400, 'chatId, role, content обязательны');
            addMessage(body.chatId, body.role, body.content);
            if (body.role === 'assistant' && body.username) incUserMsgs(body.username);
            return jsonOk(res, { ok: true });
        } catch(e) { return jsonErr(res, 400, e.message); }
    }

    /* Memory API */
    if (req.method === 'GET' && url === '/api/memory') {
        const username = new URLSearchParams(req.url.split('?')[1] || '').get('user');
        const category = new URLSearchParams(req.url.split('?')[1] || '').get('category');
        if (!username) return jsonErr(res, 400, 'user required');
        return jsonOk(res, { memory: getAllMemory(username, category) });
    }

    if (req.method === 'POST' && url === '/api/memory') {
        try {
            const body = await parseBody(req);
            if (!body.username || !body.key || !body.value) return jsonErr(res, 400, 'username, key, value required');
            const saved = setMemory(body.username, body.key, body.value, body.category);
            return jsonOk(res, { ok: saved, key: body.key });
        } catch(e) { return jsonErr(res, 400, e.message); }
    }

    if (req.method === 'DELETE' && url.startsWith('/api/memory/')) {
        const key = decodeURIComponent(url.slice('/api/memory/'.length));
        const username = new URLSearchParams(req.url.split('?')[1] || '').get('user');
        if (!username || !key) return jsonErr(res, 400, 'user and key required');
        deleteMemory(username, key);
        return jsonOk(res, { ok: true });
    }

    /* Web Search API */
    if (req.method === 'POST' && url === '/api/search') {
        try {
            const body = await parseBody(req);
            if (!body.query) return jsonErr(res, 400, 'query required');
            const results = await webSearch(body.query, body.max_results || 5);
            return jsonOk(res, results);
        } catch(e) { return jsonErr(res, 500, e.message); }
    }

    /* Tools API */
    if (req.method === 'POST' && url === '/api/tool') {
        try {
            const body = await parseBody(req);
            if (!body.tool || !body.username) return jsonErr(res, 400, 'tool and username required');
            const result = await executeTool(body.tool, body.arguments || {}, body.username);
            return jsonOk(res, result);
        } catch(e) { return jsonErr(res, 500, e.message); }
    }

    if (req.method === 'GET' && url === '/api/tools') {
        return jsonOk(res, { tools: TOOLS });
    }

    /* Ollama stream with tool support */
    if (req.method === 'POST' && url === '/chat') {
        var body = '';
        req.on('data', function(chunk) { body += chunk; });
        req.on('end', function() {
            var data;
            try { data = JSON.parse(body); }
            catch(e) { res.writeHead(400); res.end('Bad JSON'); return; }
            
            var messages = data.messages || [];
            var username = data.username;
            var enableTools = data.tools !== false;
            
            // Add tools info to system message if enabled
            if (enableTools) {
                var hasSystem = messages.some(function(m) { return m.role === 'system'; });
                var toolsPrompt = formatToolsForPrompt();
                if (hasSystem) {
                    messages = messages.map(function(m) {
                        if (m.role === 'system') {
                            return { role: 'system', content: m.content + toolsPrompt };
                        }
                        return m;
                    });
                } else {
                    messages.unshift({ role: 'system', content: 'You are a helpful AI assistant.' + toolsPrompt });
                }
            }

            var payload = JSON.stringify({ model: MODEL, messages: messages, stream: true });
            var ollamaHost = OLLAMA_URL.replace(/^https?:\/\//, '').split(':');
            var ollamaHostname = ollamaHost[0];
            var ollamaPort = parseInt(ollamaHost[1]) || 11434;
            var options = {
                hostname: ollamaHostname, port: ollamaPort, path: '/api/chat', method: 'POST',
                headers: { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(payload) }
            };

            res.writeHead(200, { 'Content-Type': 'text/event-stream', 'Cache-Control': 'no-cache', 'Connection': 'keep-alive' });

            var ollamaReq = http.request(options, function(ollamaRes) {
                ollamaRes.on('data', function(chunk) {
                    var lines = chunk.toString().split('\n').filter(Boolean);
                    lines.forEach(function(line) {
                        try {
                            var json = JSON.parse(line);
                            var text = (json && json.message && json.message.content) || '';
                            if (text) res.write('data: ' + JSON.stringify({ text: text }) + '\n\n');
                            if (json.done) res.write('data: [DONE]\n\n');
                        } catch(e) {}
                    });
                });
                ollamaRes.on('end', function() { res.end(); });
            });

            ollamaReq.on('error', function(err) {
                res.write('data: ' + JSON.stringify({ error: 'Ollama error: ' + err.message }) + '\n\n');
                res.end();
            });

            ollamaReq.write(payload);
            ollamaReq.end();
        });
        return;
    }

    res.writeHead(404);
    res.end('Not found');
});

initDB();
server.listen(PORT, '0.0.0.0', function() {
    console.log('\nAI-CICADA Web Chat v5.0 - With Tools, Memory & Web Search');
    console.log('Model  : ' + MODEL);
    console.log('DB     : ' + (db ? DB_PATH : 'in-memory (fallback)'));
    console.log('Tools  : ' + Object.keys(TOOLS).join(', '));
    console.log('Open   : http://localhost:' + PORT);
    console.log('\nPress Ctrl+C to stop\n');
});
process.on('uncaughtException', function(err) { console.error('[uncaughtException]', err.message); });
process.on('unhandledRejection', function(r) { console.error('[unhandledRejection]', r); });
"""

with open(path, 'w') as f:
    f.write(code.lstrip('\n'))

print("server.js written OK")
PYEOF
}

create_index_html() {
    printf "${BLUE}Creating index.html...${NC}\n"
    python3 - "$CHAT_DIR/index.html" << 'PYEOF'
import sys
path = sys.argv[1]

html = r"""<!DOCTYPE html>
<html lang="ru">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
<title>AI-CICADA v5</title>
<link href="https://fonts.googleapis.com/css2?family=Unbounded:wght@400;700;900&family=IBM+Plex+Mono:wght@400;500&display=swap" rel="stylesheet">
<style>
*,*::before,*::after{box-sizing:border-box;margin:0;padding:0}
:root{
  --bg:#070708;--bg2:#0e0e10;--bg3:#161618;--bg4:#1e1e22;
  --border:rgba(255,255,255,0.06);--border2:rgba(255,255,255,0.12);
  --accent:#c8ff00;--accent2:#00e5ff;--accent3:#ff3cac;
  --text:#f0f0f0;--text2:#888;--text3:#555;
  --user-bg:#1a1f0a;--ai-bg:#0a0f1a;
  --r:16px;--r2:24px;
  --font-head:'Unbounded',sans-serif;--font-mono:'IBM Plex Mono',monospace;
  --glow:0 0 30px rgba(200,255,0,0.15);
}
html,body{height:100%;background:var(--bg);color:var(--text);font-family:var(--font-mono);font-size:14px;overflow:hidden}
body::before{content:'';position:fixed;inset:0;z-index:0;background-image:linear-gradient(rgba(200,255,0,0.025) 1px,transparent 1px),linear-gradient(90deg,rgba(200,255,0,0.025) 1px,transparent 1px);background-size:40px 40px;pointer-events:none}
body::after{content:'';position:fixed;width:600px;height:600px;border-radius:50%;background:radial-gradient(circle,rgba(200,255,0,0.06) 0%,transparent 70%);top:-200px;right:-200px;pointer-events:none;z-index:0}
.page{position:fixed;inset:0;z-index:10;display:flex;align-items:center;justify-content:center;padding:20px;transition:opacity .3s,transform .3s}
.page.hidden{opacity:0;pointer-events:none;transform:translateY(10px)}
.card{width:100%;max-width:420px;background:var(--bg2);border:1px solid var(--border2);border-radius:var(--r2);padding:36px 28px;box-shadow:0 40px 80px rgba(0,0,0,0.6),var(--glow);position:relative;overflow:hidden}
.card::before{content:'';position:absolute;top:0;left:0;right:0;height:2px;background:linear-gradient(90deg,var(--accent3),var(--accent),var(--accent2))}
.card-logo{display:flex;align-items:center;gap:12px;margin-bottom:28px}
.card-logo-icon{width:44px;height:44px;border-radius:12px;background:linear-gradient(135deg,var(--accent),var(--accent2));display:flex;align-items:center;justify-content:center;font-size:20px;flex-shrink:0}
.card-logo-name{font-family:var(--font-head);font-size:15px;font-weight:900;color:var(--accent);letter-spacing:2px}
.card-logo-sub{font-size:11px;color:var(--text2);margin-top:2px}
.card h2{font-family:var(--font-head);font-size:20px;font-weight:700;margin-bottom:6px;letter-spacing:1px}
.card p{color:var(--text2);font-size:13px;margin-bottom:24px;line-height:1.5}
.field{margin-bottom:14px}
.field label{display:block;font-size:11px;color:var(--text2);letter-spacing:1px;text-transform:uppercase;margin-bottom:6px}
.field input, .field select, .field textarea{width:100%;background:var(--bg3);border:1px solid var(--border2);border-radius:var(--r);color:var(--text);font-family:var(--font-mono);font-size:14px;padding:12px 14px;outline:none;transition:border-color .2s,box-shadow .2s}
.field input:focus, .field select:focus, .field textarea:focus{border-color:var(--accent);box-shadow:0 0 0 3px rgba(200,255,0,0.1)}
.field input::placeholder, .field textarea::placeholder{color:var(--text3)}
.btn{width:100%;padding:14px;border:none;border-radius:var(--r);font-family:var(--font-head);font-size:13px;font-weight:700;letter-spacing:1px;cursor:pointer;transition:all .2s;margin-top:4px}
.btn-primary{background:linear-gradient(135deg,var(--accent),#aadd00);color:#000;box-shadow:0 4px 20px rgba(200,255,0,0.3)}
.btn-primary:hover{transform:translateY(-1px);box-shadow:0 8px 30px rgba(200,255,0,0.4)}
.btn-secondary{background:linear-gradient(135deg,var(--accent2),#00aadd);color:#000;box-shadow:0 4px 20px rgba(0,229,255,0.3)}
.btn-secondary:hover{transform:translateY(-1px);box-shadow:0 8px 30px rgba(0,229,255,0.4)}
.btn-ghost{background:transparent;border:1px solid var(--border2);color:var(--text2);margin-top:10px}
.btn-ghost:hover{border-color:var(--accent2);color:var(--accent2)}
.btn-icon{width:36px;height:36px;border-radius:10px;border:none;background:var(--bg3);color:var(--text2);font-size:14px;cursor:pointer;display:flex;align-items:center;justify-content:center;flex-shrink:0;transition:all .2s}
.btn-icon:hover{background:var(--accent);color:#000}
.btn-icon.active{background:var(--accent);color:#000}
.error-msg{background:rgba(255,60,172,0.1);border:1px solid rgba(255,60,172,0.3);border-radius:8px;color:var(--accent3);padding:10px 12px;font-size:12px;margin-bottom:14px;display:none}
.error-msg.show{display:block}
.success-msg{background:rgba(200,255,0,0.1);border:1px solid rgba(200,255,0,0.3);border-radius:8px;color:var(--accent);padding:10px 12px;font-size:12px;margin-bottom:14px;display:none}
.success-msg.show{display:block}
#chatPage{flex-direction:column;padding:0;align-items:stretch;justify-content:flex-start}
.app-layout{display:flex;height:100dvh;width:100%}
.sidebar{width:260px;flex-shrink:0;background:var(--bg2);border-right:1px solid var(--border);display:flex;flex-direction:column;transition:transform .3s;z-index:100}
.sidebar-header{padding:16px;border-bottom:1px solid var(--border);display:flex;align-items:center;gap:10px;flex-shrink:0}
.sidebar-logo-icon{width:34px;height:34px;border-radius:9px;background:linear-gradient(135deg,var(--accent),var(--accent2));display:flex;align-items:center;justify-content:center;font-size:16px;flex-shrink:0}
.sidebar-logo-name{font-family:var(--font-head);font-size:12px;font-weight:900;color:var(--accent);letter-spacing:2px}
.sidebar-logo-sub{font-size:10px;color:var(--text2)}
.btn-new-chat{margin:12px;padding:10px 14px;background:rgba(200,255,0,0.08);border:1px solid rgba(200,255,0,0.2);border-radius:10px;color:var(--accent);font-family:var(--font-head);font-size:11px;font-weight:700;letter-spacing:1px;cursor:pointer;display:flex;align-items:center;gap:8px;transition:all .2s;flex-shrink:0}
.btn-new-chat:hover{background:rgba(200,255,0,0.15)}
.sidebar-section-title{padding:8px 16px 4px;font-size:10px;color:var(--text3);text-transform:uppercase;letter-spacing:1.5px;flex-shrink:0}
.history-list{flex:1;overflow-y:auto;padding:4px 8px}
.history-list::-webkit-scrollbar{width:3px}
.history-list::-webkit-scrollbar-thumb{background:var(--border2);border-radius:2px}
.history-item{padding:9px 10px;border-radius:8px;cursor:pointer;display:flex;align-items:center;gap:8px;transition:background .15s;margin-bottom:2px}
.history-item:hover{background:var(--bg3)}
.history-item.active{background:rgba(200,255,0,0.08)}
.history-item-icon{font-size:13px;flex-shrink:0;opacity:.6}
.history-item-text{font-size:12px;color:var(--text2);overflow:hidden;text-overflow:ellipsis;white-space:nowrap;flex:1}
.history-item.active .history-item-text{color:var(--accent)}
.history-item-del{font-size:11px;color:var(--text3);opacity:0;cursor:pointer;flex-shrink:0;padding:2px 4px;border-radius:4px;transition:opacity .15s,color .15s}
.history-item:hover .history-item-del{opacity:1}
.history-item-del:hover{color:var(--accent3)!important;opacity:1!important}
.history-empty{padding:20px 16px;text-align:center;color:var(--text3);font-size:12px;line-height:1.6}
.sidebar-nav{display:flex;gap:4px;padding:8px 16px;border-top:1px solid var(--border)}
.sidebar-nav-btn{flex:1;padding:8px;background:var(--bg3);border:1px solid var(--border);border-radius:8px;color:var(--text2);font-family:var(--font-mono);font-size:10px;cursor:pointer;transition:all .2s}
.sidebar-nav-btn:hover{border-color:var(--accent);color:var(--accent)}
.sidebar-nav-btn.active{background:rgba(200,255,0,0.1);border-color:var(--accent);color:var(--accent)}
.sidebar-panel{flex:1;overflow-y:auto;padding:8px 16px;display:none}
.sidebar-panel.active{display:block}
.memory-item{padding:10px;background:var(--bg3);border:1px solid var(--border);border-radius:8px;margin-bottom:8px;cursor:pointer;transition:all .2s}
.memory-item:hover{border-color:var(--accent2)}
.memory-item-key{font-size:11px;color:var(--accent);margin-bottom:4px}
.memory-item-value{font-size:12px;color:var(--text);overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.memory-item-cat{font-size:9px;color:var(--text3);text-transform:uppercase;letter-spacing:1px;margin-top:4px}
.memory-form{display:flex;flex-direction:column;gap:8px;margin-top:12px}
.memory-form input{background:var(--bg3);border:1px solid var(--border2);border-radius:8px;padding:10px 12px;color:var(--text);font-family:var(--font-mono);font-size:12px}
.memory-form button{padding:10px;background:var(--accent);color:#000;border:none;border-radius:8px;font-family:var(--font-head);font-size:11px;font-weight:700;cursor:pointer}
.search-result{padding:10px;background:var(--bg3);border:1px solid var(--border);border-radius:8px;margin-bottom:8px}
.search-result-title{font-size:12px;color:var(--accent2);margin-bottom:4px}
.search-result-url{font-size:10px;color:var(--text3);margin-bottom:4px}
.search-result-snippet{font-size:11px;color:var(--text)}
.tool-badge{display:inline-flex;align-items:center;gap:4px;padding:3px 8px;background:var(--bg3);border:1px solid var(--border2);border-radius:12px;font-size:10px;color:var(--accent2);margin-right:4px;margin-bottom:4px}
.tool-badge.active{background:rgba(0,229,255,0.1);border-color:var(--accent2)}
.sidebar-profile{padding:12px 16px;border-top:1px solid var(--border);display:flex;align-items:center;gap:10px;flex-shrink:0}
.profile-avatar{width:32px;height:32px;border-radius:50%;background:linear-gradient(135deg,var(--accent3),var(--accent));display:flex;align-items:center;justify-content:center;font-size:14px;flex-shrink:0;color:#000;font-weight:700;font-family:var(--font-head)}
.profile-info{flex:1;min-width:0}
.profile-name{font-size:12px;font-weight:500;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.profile-role{font-size:10px;color:var(--text2)}
.btn-logout{background:none;border:none;color:var(--text3);font-size:16px;cursor:pointer;padding:4px;border-radius:6px;transition:color .2s;flex-shrink:0}
.btn-logout:hover{color:var(--accent3)}
.chat-area{flex:1;display:flex;flex-direction:column;min-width:0;position:relative}
.topbar{display:flex;align-items:center;gap:10px;padding:10px 16px;border-bottom:1px solid var(--border);background:var(--bg2);flex-shrink:0}
.btn-menu{display:none;background:none;border:none;color:var(--text2);font-size:20px;cursor:pointer;padding:4px;flex-shrink:0}
.topbar-title{flex:1;font-family:var(--font-head);font-size:13px;font-weight:700;color:var(--text);letter-spacing:1px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.model-badge{background:var(--bg3);border:1px solid var(--border2);border-radius:20px;padding:4px 10px;font-size:11px;color:var(--accent2);white-space:nowrap;flex-shrink:0}
.tools-bar{display:flex;gap:6px;flex-wrap:wrap;align-items:center}
.status-indicator{width:8px;height:8px;border-radius:50%;background:var(--text3);flex-shrink:0;transition:background .3s}
.status-indicator.online{background:var(--accent);box-shadow:0 0 8px var(--accent)}
.status-indicator.loading{background:var(--accent2);animation:blink 1s infinite}
@keyframes blink{0%,100%{opacity:1}50%{opacity:.2}}
#messages{flex:1;overflow-y:auto;padding:20px 16px;display:flex;flex-direction:column;gap:16px;scroll-behavior:smooth}
#messages::-webkit-scrollbar{width:4px}
#messages::-webkit-scrollbar-thumb{background:var(--border);border-radius:2px}
.welcome{flex:1;display:flex;flex-direction:column;align-items:center;justify-content:center;text-align:center;padding:40px 20px;gap:14px}
.welcome-cicada{font-size:56px;filter:drop-shadow(0 0 20px rgba(200,255,0,0.4));animation:float 3s ease-in-out infinite}
@keyframes float{0%,100%{transform:translateY(0)}50%{transform:translateY(-8px)}}
.welcome h1{font-family:var(--font-head);font-size:22px;font-weight:900;background:linear-gradient(135deg,var(--accent),var(--accent2));-webkit-background-clip:text;-webkit-text-fill-color:transparent;letter-spacing:2px}
.welcome p{color:var(--text2);font-size:13px;line-height:1.7;max-width:300px}
.welcome-chips{display:flex;flex-wrap:wrap;gap:8px;justify-content:center;margin-top:8px}
.chip{background:var(--bg3);border:1px solid var(--border2);border-radius:20px;padding:7px 14px;font-size:12px;color:var(--text2);cursor:pointer;transition:all .2s}
.chip:hover{border-color:var(--accent);color:var(--accent);background:rgba(200,255,0,0.05)}
.msg{display:flex;gap:10px;animation:msgIn .2s ease}
@keyframes msgIn{from{opacity:0;transform:translateY(8px)}to{opacity:1;transform:none}}
.msg.user{flex-direction:row-reverse}
.avatar{width:30px;height:30px;border-radius:9px;flex-shrink:0;margin-top:2px;display:flex;align-items:center;justify-content:center;font-size:14px;font-weight:700;font-family:var(--font-head)}
.msg.user .avatar{background:linear-gradient(135deg,var(--accent3),var(--accent));color:#000;font-size:12px}
.msg.ai .avatar{background:linear-gradient(135deg,#0a1a3a,#0a1a2a);border:1px solid rgba(0,229,255,0.3);font-size:15px}
.bubble{max-width:min(80%,520px);padding:11px 15px;border-radius:var(--r);line-height:1.65;word-break:break-word;font-size:13.5px}
.msg.user .bubble{background:var(--user-bg);border:1px solid rgba(200,255,0,0.15);border-bottom-right-radius:4px;color:#d8ffaa}
.msg.ai .bubble{background:var(--ai-bg);border:1px solid rgba(0,229,255,0.1);border-bottom-left-radius:4px}
.bubble code{background:rgba(0,229,255,0.08);border:1px solid rgba(0,229,255,0.15);border-radius:4px;padding:2px 5px;font-size:12px;color:var(--accent2)}
.bubble pre{background:#05080f;border:1px solid rgba(0,229,255,0.12);border-radius:10px;padding:12px 14px;overflow-x:auto;margin:8px 0;font-size:12px;line-height:1.5;position:relative}
.bubble pre code{background:none;border:none;padding:0;color:#8ecfff}
.copy-btn{position:absolute;top:8px;right:8px;background:var(--bg3);border:1px solid var(--border2);border-radius:5px;padding:3px 8px;font-size:10px;color:var(--text2);cursor:pointer;font-family:var(--font-mono);transition:all .15s}
.copy-btn:hover{color:var(--accent);border-color:var(--accent)}
.typing-bubble{background:var(--ai-bg);border:1px solid rgba(0,229,255,0.1);border-radius:var(--r);border-bottom-left-radius:4px;padding:14px 18px;display:flex;gap:5px;align-items:center}
.typing-bubble span{width:6px;height:6px;background:var(--accent2);border-radius:50%;animation:dot 1.2s infinite}
.typing-bubble span:nth-child(2){animation-delay:.2s}
.typing-bubble span:nth-child(3){animation-delay:.4s}
@keyframes dot{0%,80%,100%{opacity:.2;transform:scale(.8)}40%{opacity:1;transform:scale(1)}}
.typing-wrap{display:flex;gap:10px}
.input-area{padding:12px 16px;border-top:1px solid var(--border);background:var(--bg2);flex-shrink:0}
.input-toolbar{display:flex;gap:8px;margin-bottom:8px;align-items:center;flex-wrap:wrap}
.input-wrap{display:flex;align-items:flex-end;gap:10px;background:var(--bg3);border:1px solid var(--border2);border-radius:14px;padding:10px 10px 10px 16px;transition:border-color .2s}
.input-wrap:focus-within{border-color:rgba(200,255,0,0.3)}
#input{flex:1;background:none;border:none;color:var(--text);font-family:var(--font-mono);font-size:14px;resize:none;outline:none;max-height:120px;line-height:1.5}
#input::placeholder{color:var(--text3)}
#sendBtn{width:36px;height:36px;border-radius:10px;border:none;background:var(--accent);color:#000;font-size:16px;cursor:pointer;display:flex;align-items:center;justify-content:center;flex-shrink:0;transition:all .2s}
#sendBtn:hover{background:#aadd00;transform:scale(1.05)}
#sendBtn:disabled{background:var(--bg);color:var(--text3);cursor:not-allowed;transform:none}
.sidebar-overlay{display:none;position:fixed;inset:0;background:rgba(0,0,0,.5);z-index:99}
.sidebar-overlay.show{display:block}
#profilePage{flex-direction:column;padding:0;align-items:stretch;justify-content:flex-start}
.profile-page{max-width:520px;width:100%;margin:0 auto;padding:30px 20px;overflow-y:auto;height:100dvh}
.profile-header{display:flex;align-items:center;gap:16px;margin-bottom:28px}
.profile-big-avatar{width:64px;height:64px;border-radius:20px;background:linear-gradient(135deg,var(--accent3),var(--accent));display:flex;align-items:center;justify-content:center;font-size:28px;color:#000;font-family:var(--font-head);font-weight:900}
.profile-big-name{font-family:var(--font-head);font-size:20px;font-weight:700}
.profile-big-sub{font-size:12px;color:var(--text2);margin-top:3px}
.stats-grid{display:grid;grid-template-columns:repeat(4,1fr);gap:10px;margin-bottom:24px}
.stat-card{background:var(--bg2);border:1px solid var(--border);border-radius:14px;padding:16px 8px;text-align:center}
.stat-value{font-family:var(--font-head);font-size:22px;font-weight:900;color:var(--accent)}
.stat-label{font-size:10px;color:var(--text3);margin-top:3px;text-transform:uppercase;letter-spacing:1px}
.info-section{background:var(--bg2);border:1px solid var(--border);border-radius:16px;overflow:hidden;margin-bottom:16px}
.info-row{display:flex;align-items:center;gap:14px;padding:14px 16px;border-bottom:1px solid var(--border)}
.info-row:last-child{border-bottom:none}
.info-row-icon{font-size:18px;flex-shrink:0}
.info-row-label{font-size:10px;color:var(--text3);text-transform:uppercase;letter-spacing:1px}
.info-row-value{font-size:13px;color:var(--text);margin-top:1px}
.info-row-content{flex:1}
.btn-back{display:block;width:100%;padding:14px;background:var(--bg2);border:1px solid var(--border2);border-radius:var(--r);font-family:var(--font-head);font-size:12px;color:var(--text2);cursor:pointer;transition:all .2s;text-align:center;letter-spacing:1px}
.btn-back:hover{border-color:var(--accent);color:var(--accent)}
.db-badge{display:inline-flex;align-items:center;gap:5px;font-size:10px;color:var(--accent2);background:rgba(0,229,255,0.08);border:1px solid rgba(0,229,255,0.2);border-radius:20px;padding:3px 10px;margin-top:6px}
.search-overlay{position:fixed;inset:0;background:rgba(0,0,0,0.8);z-index:200;display:none;align-items:center;justify-content:center;padding:20px}
.search-overlay.show{display:flex}
.search-modal{width:100%;max-width:600px;background:var(--bg2);border:1px solid var(--border2);border-radius:var(--r2);padding:24px;max-height:80vh;overflow-y:auto}
.search-modal h3{margin-bottom:16px;font-family:var(--font-head);color:var(--accent)}
.search-input-wrap{display:flex;gap:8px;margin-bottom:16px}
.search-input{flex:1;background:var(--bg3);border:1px solid var(--border2);border-radius:var(--r);padding:12px 16px;color:var(--text);font-family:var(--font-mono);font-size:14px}
.search-btn{padding:12px 20px;background:var(--accent);color:#000;border:none;border-radius:var(--r);font-family:var(--font-head);font-size:12px;font-weight:700;cursor:pointer}
.memory-modal{width:100%;max-width:500px;background:var(--bg2);border:1px solid var(--border2);border-radius:var(--r2);padding:24px;max-height:80vh;overflow-y:auto}
.memory-modal h3{margin-bottom:16px;font-family:var(--font-head);color:var(--accent)}
@media(max-width:600px){.sidebar{position:fixed;top:0;left:0;height:100%;transform:translateX(-100%)}.sidebar.open{transform:translateX(0)}.btn-menu{display:block}.stats-grid{grid-template-columns:repeat(2,1fr)}}
</style>
</head>
<body>

<div class="search-overlay" id="searchOverlay" onclick="closeSearch(event)">
  <div class="search-modal" onclick="event.stopPropagation()">
    <h3>&#128270; Web Search</h3>
    <div class="search-input-wrap">
      <input type="text" class="search-input" id="searchInput" placeholder="Введите поисковый запрос..." onkeydown="if(event.key==='Enter')doSearch()">
      <button class="search-btn" onclick="doSearch()">Поиск</button>
    </div>
    <div id="searchResults"></div>
  </div>
</div>

<div class="search-overlay" id="memoryOverlay" onclick="closeMemory(event)">
  <div class="memory-modal" onclick="event.stopPropagation()">
    <h3>&#129504; Memory / Память</h3>
    <div id="memoryList" style="margin-bottom:16px"></div>
    <div class="memory-form">
      <input type="text" id="memKey" placeholder="Ключ (например: любимый_цвет)">
      <input type="text" id="memValue" placeholder="Значение (например: синий)">
      <input type="text" id="memCat" placeholder="Категория (general, preference, fact)">
      <button onclick="saveMemory()">Сохранить в память</button>
    </div>
  </div>
</div>

<div class="page" id="loginPage">
  <div class="card">
    <div class="card-logo">
      <div class="card-logo-icon">&#129432;</div>
      <div><div class="card-logo-name">AI-CICADA</div><div class="card-logo-sub">v5.0 +Tools +Memory +Search</div></div>
    </div>
    <h2>Вход</h2>
    <p>Войдите в аккаунт для начала работы</p>
    <div id="loginError" class="error-msg"></div>
    <div class="field"><label>Логин</label><input id="loginUser" type="text" placeholder="username"></div>
    <div class="field"><label>Пароль</label><input id="loginPass" type="password" placeholder="&#9679;&#9679;&#9679;&#9679;&#9679;&#9679;"></div>
    <button class="btn btn-primary" onclick="login()">Войти</button>
    <button class="btn btn-ghost" onclick="showPage('registerPage')">Нет аккаунта? Зарегистрироваться</button>
  </div>
</div>

<div class="page hidden" id="registerPage">
  <div class="card">
    <div class="card-logo">
      <div class="card-logo-icon">&#129432;</div>
      <div><div class="card-logo-name">AI-CICADA</div><div class="card-logo-sub">Регистрация</div></div>
    </div>
    <h2>Регистрация</h2>
    <p>Данные хранятся локально в SQLite</p>
    <div id="regError" class="error-msg"></div>
    <div id="regSuccess" class="success-msg"></div>
    <div class="field"><label>Логин</label><input id="regUser" type="text" placeholder="username"></div>
    <div class="field"><label>Пароль</label><input id="regPass" type="password" placeholder="минимум 4 символа"></div>
    <div class="field"><label>Повтор пароля</label><input id="regPass2" type="password" placeholder="повторите пароль"></div>
    <button class="btn btn-primary" onclick="register()">Создать аккаунт</button>
    <button class="btn btn-ghost" onclick="showPage('loginPage')">Уже есть аккаунт? Войти</button>
  </div>
</div>

<div class="page hidden" id="chatPage">
  <div class="app-layout">
    <div class="sidebar" id="sidebar">
      <div class="sidebar-header">
        <div class="sidebar-logo-icon">&#129432;</div>
        <div><div class="sidebar-logo-name">AI-CICADA</div><div class="sidebar-logo-sub">v5.0</div></div>
      </div>
      <button class="btn-new-chat" onclick="newChat()">+ Новый чат</button>
      <div class="sidebar-nav">
        <button class="sidebar-nav-btn active" onclick="showPanel('chats')" id="navChats">Чаты</button>
        <button class="sidebar-nav-btn" onclick="showPanel('memory')" id="navMemory">Память</button>
      </div>
      <div class="sidebar-panel active" id="panelChats">
        <div class="sidebar-section-title">История</div>
        <div class="history-list" id="historyList"></div>
      </div>
      <div class="sidebar-panel" id="panelMemory">
        <div class="sidebar-section-title">Моя память</div>
        <div id="memorySidebar"></div>
      </div>
      <div class="sidebar-profile">
        <div class="profile-avatar" id="sidebarAvatar">?</div>
        <div class="profile-info">
          <div class="profile-name" id="sidebarName">—</div>
          <div class="profile-role" id="sidebarRole">SQLite</div>
        </div>
        <button class="btn-logout" onclick="showProfilePage()" title="Профиль">&#128100;</button>
        <button class="btn-logout" onclick="logout()" title="Выйти">&#x21E5;</button>
      </div>
    </div>
    <div class="sidebar-overlay" id="sidebarOverlay" onclick="closeSidebar()"></div>
    <div class="chat-area">
      <div class="topbar">
        <button class="btn-menu" onclick="openSidebar()">&#9776;</button>
        <div class="topbar-title" id="chatTitle">AI-CICADA</div>
        <div class="tools-bar">
          <button class="btn-icon" id="webSearchBtn" onclick="openSearch()" title="Web Search">&#128270;</button>
          <button class="btn-icon" id="memoryBtn" onclick="openMemory()" title="Memory">&#129504;</button>
          <button class="btn-icon" id="toolsBtn" onclick="toggleTools()" title="Tools">&#129522;</button>
        </div>
        <div class="model-badge" id="modelBadge">загрузка...</div>
        <div class="status-indicator" id="statusDot"></div>
      </div>
      <div id="toolBar" style="display:none;padding:8px 16px;background:var(--bg2);border-bottom:1px solid var(--border)">
        <div style="font-size:11px;color:var(--text3);margin-bottom:8px">Доступные инструменты:</div>
        <div id="toolBadges"></div>
      </div>
      <div id="messages"></div>
      <div class="input-area">
        <div class="input-toolbar">
          <span class="tool-badge" id="webSearchBadge" style="display:none">&#128270; Web Search</span>
          <span class="tool-badge" id="memoryBadge" style="display:none">&#129504; Memory</span>
        </div>
        <div class="input-wrap">
          <textarea id="input" rows="1" placeholder="Спросите что угодно... (ИИ может использовать инструменты автоматически)"></textarea>
          <button id="sendBtn" onclick="send()">&#10148;</button>
        </div>
      </div>
    </div>
  </div>
</div>

<div class="page hidden" id="profilePage">
  <div class="profile-page">
    <div class="profile-header">
      <div class="profile-big-avatar" id="profileAvatar">?</div>
      <div>
        <div class="profile-big-name" id="profileName">—</div>
        <div class="profile-big-sub" id="profileSub">Локальный аккаунт</div>
        <div class="db-badge">&#129504; SQLite + Tools + Memory</div>
      </div>
    </div>
    <div class="stats-grid">
      <div class="stat-card"><div class="stat-value" id="statChats">0</div><div class="stat-label">Чатов</div></div>
      <div class="stat-card"><div class="stat-value" id="statMsgs">0</div><div class="stat-label">Сообщений</div></div>
      <div class="stat-card"><div class="stat-value" id="statMemory">0</div><div class="stat-label">Память</div></div>
      <div class="stat-card"><div class="stat-value" id="statDays">0</div><div class="stat-label">Дней</div></div>
    </div>
    <div class="info-section">
      <div class="info-row"><div class="info-row-icon">&#128100;</div><div class="info-row-content"><div class="info-row-label">Пользователь</div><div class="info-row-value" id="infoUser">—</div></div></div>
      <div class="info-row"><div class="info-row-icon">&#129302;</div><div class="info-row-content"><div class="info-row-label">Модель</div><div class="info-row-value" id="infoModel">—</div></div></div>
      <div class="info-row"><div class="info-row-icon">&#128197;</div><div class="info-row-content"><div class="info-row-label">Регистрация</div><div class="info-row-value" id="infoDate">—</div></div></div>
      <div class="info-row"><div class="info-row-icon">&#128190;</div><div class="info-row-content"><div class="info-row-label">Хранилище</div><div class="info-row-value">SQLite · cicada.db</div></div></div>
    </div>
    <div class="info-section">
      <div class="info-row" style="cursor:pointer" onclick="clearAllHistory()"><div class="info-row-icon">&#128465;</div><div class="info-row-content"><div class="info-row-label">ДЕЙСТВИЕ</div><div class="info-row-value" style="color:var(--accent2)">Очистить историю чатов</div></div></div>
      <div class="info-row" style="cursor:pointer" onclick="deleteAccount()"><div class="info-row-icon">&#9888;</div><div class="info-row-content"><div class="info-row-label">ДЕЙСТВИЕ</div><div class="info-row-value" style="color:var(--accent3)">Удалить аккаунт</div></div></div>
    </div>
    <button class="btn-back" onclick="showPage('chatPage')">&larr; Вернуться к чату</button>
  </div>
</div>

<script>
var currentUser  = null;
var currentModel = '';
var currentChatId = null;
var chatHistory   = [];
var generating    = false;
var availableTools = [];
var toolsEnabled  = false;

var API = {
    _post: function(url, data) {
        return fetch(url, { method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify(data) }).then(function(r){ return r.json(); });
    },
    _get: function(url) { return fetch(url).then(function(r){ return r.json(); }); },
    _del: function(url) { return fetch(url, { method:'DELETE' }).then(function(r){ return r.json(); }); },
    register: function(u,p)    { return API._post('/api/register', { username:u, password:p }); },
    login:    function(u,p)    { return API._post('/api/login',    { username:u, password:p }); },
    stats:    function(u)      { return API._get('/api/stats?user=' + encodeURIComponent(u)); },
    getChats: function(u)      { return API._get('/api/chats?user=' + encodeURIComponent(u)); },
    upsertChat: function(id,u,t){ return API._post('/api/chats', { chatId:id, username:u, title:t }); },
    deleteChat: function(id)   { return API._del('/api/chats/' + encodeURIComponent(id)); },
    getMsgs:  function(id)     { return API._get('/api/messages/' + encodeURIComponent(id)); },
    addMsg:   function(id,r,c,u){ return API._post('/api/messages', { chatId:id, role:r, content:c, username:u }); },
    // Memory API
    getMemory: function(u)     { return API._get('/api/memory?user=' + encodeURIComponent(u)); },
    setMemory: function(u,k,v,cat){ return API._post('/api/memory', { username:u, key:k, value:v, category:cat }); },
    delMemory: function(u,k)    { return API._del('/api/memory/' + encodeURIComponent(k) + '?user=' + encodeURIComponent(u)); },
    // Search & Tools API
    search:   function(q, max) { return API._post('/api/search', { query:q, max_results:max||5 }); },
    tools:    function()       { return API._get('/api/tools'); },
    execTool: function(name,u,args){ return API._post('/api/tool', { tool:name, username:u, arguments:args }); }
};

var Session = {
    get:   function() { return sessionStorage.getItem('ac_user'); },
    set:   function(u){ sessionStorage.setItem('ac_user', u); },
    clear: function() { sessionStorage.removeItem('ac_user'); }
};

function showPage(id) {
    document.querySelectorAll('.page').forEach(function(p){ p.classList.add('hidden'); });
    document.getElementById(id).classList.remove('hidden');
}

function showPanel(panel) {
    document.querySelectorAll('.sidebar-panel').forEach(function(p){ p.classList.remove('active'); });
    document.querySelectorAll('.sidebar-nav-btn').forEach(function(b){ b.classList.remove('active'); });
    document.getElementById('panel' + panel.charAt(0).toUpperCase() + panel.slice(1)).classList.add('active');
    document.getElementById('nav' + panel.charAt(0).toUpperCase() + panel.slice(1)).classList.add('active');
    if (panel === 'memory') loadMemorySidebar();
}

function showError(id, msg) {
    var el = document.getElementById(id);
    if (el) { el.textContent = msg; el.classList.add('show'); setTimeout(function(){ el.classList.remove('show'); }, 3000); }
}

function showSuccess(id, msg) {
    var el = document.getElementById(id);
    if (el) { el.textContent = msg; el.classList.add('show'); setTimeout(function(){ el.classList.remove('show'); }, 2000); }
}

function login() {
    var u = document.getElementById('loginUser').value.trim();
    var p = document.getElementById('loginPass').value;
    if (!u || !p) return showError('loginError', 'Заполните все поля');
    API.login(u, p).then(function(res) {
        if (res.error) return showError('loginError', res.error);
        currentUser = res;
        Session.set(u);
        enterChat();
    });
}

function register() {
    var u  = document.getElementById('regUser').value.trim();
    var p  = document.getElementById('regPass').value;
    var p2 = document.getElementById('regPass2').value;
    if (!u || !p || !p2) return showError('regError', 'Заполните все поля');
    if (p !== p2) return showError('regError', 'Пароли не совпадают');
    API.register(u, p).then(function(res) {
        if (res.error) return showError('regError', res.error);
        showSuccess('regSuccess', 'Аккаунт создан! Вход...');
        setTimeout(function(){
            API.login(u, p).then(function(r2) {
                if (r2.error) return showPage('loginPage');
                currentUser = r2; Session.set(u); enterChat();
            });
        }, 1000);
    });
}

function logout() {
    Session.clear(); currentUser = null; currentChatId = null; chatHistory = [];
    document.getElementById('loginUser').value = '';
    document.getElementById('loginPass').value = '';
    showPage('loginPage');
}

function enterChat() {
    updateSidebarProfile();
    renderHistoryList();
    loadMemorySidebar();
    newChat();
    showPage('chatPage');
    fetch('/model').then(function(r){ return r.json(); }).then(function(d){
        currentModel = d.model;
        availableTools = d.tools || [];
        document.getElementById('modelBadge').textContent = d.model;
        document.getElementById('statusDot').className = 'status-indicator online';
        document.getElementById('sidebarRole').textContent = d.web_search ? 'SQLite + Web' : 'SQLite';
        renderToolBadges();
    }).catch(function(){
        document.getElementById('modelBadge').textContent = 'Офлайн';
    });
}

function updateSidebarProfile() {
    if (!currentUser) return;
    document.getElementById('sidebarAvatar').textContent = currentUser.username[0].toUpperCase();
    document.getElementById('sidebarName').textContent   = currentUser.username;
}

function newChat() {
    currentChatId = 'chat_' + Date.now();
    chatHistory = [];
    resetMessages();
    document.getElementById('chatTitle').textContent = 'Новый чат';
    renderHistoryList();
}

function resetMessages() {
    var m = document.getElementById('messages');
    m.innerHTML = '<div class="welcome" id="welcomeBlock">' +
        '<div class="welcome-cicada">&#129432;</div>' +
        '<h1>AI-CICADA v5</h1>' +
        '<p>Локальный ИИ с памятью, поиском и инструментами</p>' +
        '<div class="welcome-chips">' +
        '<div class="chip" onclick="useChip(this)">Найди в интернете...</div>' +
        '<div class="chip" onclick="useChip(this)">Запомни: мне нравится...</div>' +
        '<div class="chip" onclick="useChip(this)">Сколько будет 15 * 23?</div>' +
        '<div class="chip" onclick="useChip(this)">Напиши скрипт</div>' +
        '</div></div>';
}

function useChip(el) { document.getElementById('input').value = el.textContent; send(); }

function saveCurrentChat(firstMsg) {
    if (!currentUser) return;
    var title = firstMsg.slice(0, 40) + (firstMsg.length > 40 ? '...' : '');
    API.upsertChat(currentChatId, currentUser.username, title).then(function(){ renderHistoryList(); });
}

function loadChat(id) {
    API.getMsgs(id).then(function(msgs) {
        currentChatId = id;
        chatHistory = msgs.map(function(m){ return { role: m.role, content: m.content }; });
        resetMessages();
        var wb = document.getElementById('welcomeBlock');
        if (wb) wb.remove();
        API.getChats(currentUser.username).then(function(chats) {
            var chat = chats.find(function(c){ return c.id === id; });
            document.getElementById('chatTitle').textContent = chat ? chat.title : id;
        });
        msgs.forEach(function(m){ addMsg(m.role, m.content); });
        renderHistoryList();
        closeSidebar();
    });
}

function deleteChat(id, e) {
    e.stopPropagation();
    API.deleteChat(id).then(function() {
        if (currentChatId === id) newChat();
        else renderHistoryList();
    });
}

function renderHistoryList() {
    if (!currentUser) return;
    API.getChats(currentUser.username).then(function(chats) {
        var list = document.getElementById('historyList');
        if (!chats || !chats.length) {
            list.innerHTML = '<div class="history-empty">Нет сохранённых чатов.<br>Начните новый диалог!</div>';
            return;
        }
        list.innerHTML = chats.map(function(c) {
            return '<div class="history-item ' + (c.id === currentChatId ? 'active' : '') + '" onclick="loadChat(\'' + c.id + '\')">' +
                '<div class="history-item-icon">&#128172;</div>' +
                '<div class="history-item-text">' + escHtml(c.title) + '</div>' +
                '<div class="history-item-del" onclick="deleteChat(\'' + c.id + '\',event)">&#10005;</div>' +
                '</div>';
        }).join('');
    });
}

// ====== WEB SEARCH ======
function openSearch() {
    document.getElementById('searchOverlay').classList.add('show');
    document.getElementById('searchInput').focus();
}
function closeSearch(e) {
    if (e && e.target.id !== 'searchOverlay') return;
    document.getElementById('searchOverlay').classList.remove('show');
}
function doSearch() {
    var q = document.getElementById('searchInput').value.trim();
    if (!q) return;
    var resultsDiv = document.getElementById('searchResults');
    resultsDiv.innerHTML = '<div style="text-align:center;padding:20px;color:var(--text2)">Поиск...</div>';
    API.search(q, 5).then(function(res) {
        if (res.error) {
            resultsDiv.innerHTML = '<div style="color:var(--accent3)">' + res.error + '</div>';
            return;
        }
        if (!res.results || !res.results.length) {
            resultsDiv.innerHTML = '<div style="color:var(--text2)">Ничего не найдено</div>';
            return;
        }
        resultsDiv.innerHTML = res.results.map(function(r) {
            return '<div class="search-result">' +
                '<div class="search-result-title">' + escHtml(r.title) + '</div>' +
                '<div class="search-result-url">' + escHtml(r.url) + '</div>' +
                '<div class="search-result-snippet">' + (r.snippet || '') + '</div>' +
                '</div>';
        }).join('');
        // Add search results to context
        var searchContext = 'Результаты поиска по запросу "' + q + '":\n' + res.results.map(function(r, i) {
            return (i+1) + '. ' + r.title + ' - ' + r.url;
        }).join('\n');
        document.getElementById('input').value = 'На основе этой информации: ' + q;
    });
}

// ====== MEMORY ======
function openMemory() {
    document.getElementById('memoryOverlay').classList.add('show');
    loadMemoryList();
}
function closeMemory(e) {
    if (e && e.target.id !== 'memoryOverlay') return;
    document.getElementById('memoryOverlay').classList.remove('show');
}
function saveMemory() {
    var k = document.getElementById('memKey').value.trim();
    var v = document.getElementById('memValue').value.trim();
    var c = document.getElementById('memCat').value.trim() || 'general';
    if (!k || !v) return alert('Заполните ключ и значение');
    if (!currentUser) return;
    API.setMemory(currentUser.username, k, v, c).then(function(res) {
        if (res.ok) {
            document.getElementById('memKey').value = '';
            document.getElementById('memValue').value = '';
            loadMemoryList();
            loadMemorySidebar();
        }
    });
}
function loadMemoryList() {
    if (!currentUser) return;
    API.getMemory(currentUser.username).then(function(res) {
        var list = document.getElementById('memoryList');
        if (!res.memory || !res.memory.length) {
            list.innerHTML = '<div style="color:var(--text3);text-align:center;padding:20px">Нет сохранённых воспоминаний</div>';
            return;
        }
        list.innerHTML = res.memory.map(function(m) {
            return '<div class="memory-item" onclick="useMemory(\'' + m.key + '\')">' +
                '<div class="memory-item-key">' + escHtml(m.key) + '</div>' +
                '<div class="memory-item-value">' + escHtml(m.value) + '</div>' +
                '<div class="memory-item-cat">' + (m.category || 'general') + '</div>' +
                '</div>';
        }).join('');
    });
}
function loadMemorySidebar() {
    if (!currentUser) return;
    API.getMemory(currentUser.username).then(function(res) {
        var sidebar = document.getElementById('memorySidebar');
        if (!res.memory || !res.memory.length) {
            sidebar.innerHTML = '<div style="color:var(--text3);text-align:center;padding:20px;font-size:12px">Нет воспоминаний</div>';
            return;
        }
        sidebar.innerHTML = res.memory.slice(0, 10).map(function(m) {
            return '<div class="memory-item" onclick="useMemory(\'' + m.key + '\')">' +
                '<div class="memory-item-key">' + escHtml(m.key) + '</div>' +
                '<div class="memory-item-value">' + escHtml(m.value.slice(0, 50)) + (m.value.length > 50 ? '...' : '') + '</div>' +
                '</div>';
        }).join('');
    });
}
function useMemory(key) {
    document.getElementById('input').value = 'Что ты помнишь про: ' + key;
    closeMemory();
}

// ====== TOOLS ======
function toggleTools() {
    var bar = document.getElementById('toolBar');
    bar.style.display = bar.style.display === 'none' ? 'block' : 'none';
}
function renderToolBadges() {
    var badges = document.getElementById('toolBadges');
    badges.innerHTML = availableTools.map(function(t) {
        return '<span class="tool-badge">' + t + '</span>';
    }).join('');
}

// ====== CHAT WITH TOOLS ======
function send() {
    var text = document.getElementById('input').value.trim();
    if (!text || generating) return;
    generating = true;
    document.getElementById('sendBtn').disabled = true;
    document.getElementById('input').value = '';
    document.getElementById('input').style.height = 'auto';
    var wb = document.getElementById('welcomeBlock');
    if (wb) wb.remove();
    addMsg('user', text);
    chatHistory.push({ role: 'user', content: text });
    if (chatHistory.length === 1) {
        document.getElementById('chatTitle').textContent = text.slice(0, 30) + (text.length > 30 ? '...' : '');
        saveCurrentChat(text);
    }
    if (currentUser) API.addMsg(currentChatId, 'user', text, currentUser.username);
    document.getElementById('statusDot').className = 'status-indicator loading';
    var typingEl = addTyping();
    var fullText = '';
    var aiBubble = null;
    var toolCalls = [];
    
    var abortCtrl = new AbortController();
    var abortTimer = setTimeout(function() { abortCtrl.abort(); }, 120000); // 2 min timeout

    fetch('/chat', { method:'POST', headers:{'Content-Type':'application/json'}, signal: abortCtrl.signal, body: JSON.stringify({ 
        messages: chatHistory, 
        username: currentUser ? currentUser.username : null,
        tools: toolsEnabled 
    }) })
    .then(function(res) {
        var reader = res.body.getReader();
        var dec = new TextDecoder();
        function read() {
            return reader.read().then(function(x) {
                if (x.done) return;
                var lines = dec.decode(x.value).split('\n').filter(function(l){ return l.indexOf('data: ') === 0; });
                lines.forEach(function(line) {
                    var data = line.slice(6);
                    if (data === '[DONE]') return;
                    try {
                        var json = JSON.parse(data);
                        if (json.error) throw new Error(json.error);
                        if (json.text) {
                            fullText += json.text;
                            var trimmed = fullText.trim();
                            if (trimmed.startsWith('{') && trimmed.includes('"tool":')) {
                                try {
                                    var toolCall = JSON.parse(trimmed);
                                    if (toolCall.tool && toolCall.arguments) {
                                        toolCalls.push(toolCall);
                                        fullText = '';
                                        if (aiBubble) {
                                            aiBubble.querySelector('.bubble').innerHTML = '<div style="color:var(--accent2)">&#129518; Выполняю: ' + toolCall.tool + '...</div>';
                                        }
                                    }
                                } catch(e) {}
                            }
                            if (!aiBubble) { typingEl.remove(); aiBubble = addMsg('ai', ''); }
                            var bubble = aiBubble.querySelector('.bubble');
                            if (!toolCalls.length) {
                                bubble.innerHTML = '';
                                if (fullText.trim().startsWith('{')) {
                                    bubble.innerHTML = '<div style="color:var(--accent2)">&#129518; Обрабатываю...</div>';
                                } else {
                                    bubble.appendChild(renderMd(fullText));
                                }
                            }
                            document.getElementById('messages').scrollTop = 999999;
                        }
                    } catch(e) {}
                });
                return read();
            });
        }
        return read();
    })
    .then(function() {
        // Execute any tool calls
        if (toolCalls.length && currentUser) {
            var lastTool = toolCalls[toolCalls.length - 1];
            return API.execTool(lastTool.tool, currentUser.username, lastTool.arguments);
        }
    })
    .then(function(toolResult) {
        if (toolResult) {
            // Add tool result to chat
            var resultText = JSON.stringify(toolResult, null, 2);
            if (toolResult.results) {
                resultText = toolResult.results.map(function(r) { return r.title + ': ' + r.url; }).join('\n');
            } else if (toolResult.message) {
                resultText = toolResult.message;
            } else if (toolResult.result !== undefined) {
                resultText = 'Результат: ' + toolResult.result;
            }
            chatHistory.push({ role: 'system', content: 'Результат инструмента: ' + resultText });
            // Continue chat with tool result
            return fetch('/chat', { method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify({ 
                messages: chatHistory,
                username: currentUser ? currentUser.username : null,
                tools: false
            })});
        }
    })
    .then(function(contRes) {
        if (contRes && contRes.body) {
            var reader = contRes.body.getReader();
            var dec = new TextDecoder();
            var contText = '';
            var contBubble = null;
            function readCont() {
                return reader.read().then(function(x) {
                    if (x.done) return;
                    var lines = dec.decode(x.value).split('\n').filter(function(l){ return l.indexOf('data: ') === 0; });
                    lines.forEach(function(line) {
                        var data = line.slice(6);
                        if (data === '[DONE]') return;
                        try {
                            var json = JSON.parse(data);
                            if (json.text) {
                                contText += json.text;
                                if (!contBubble) { contBubble = addMsg('ai', ''); }
                                var bubble = contBubble.querySelector('.bubble');
                                bubble.innerHTML = '';
                                bubble.appendChild(renderMd(contText));
                                document.getElementById('messages').scrollTop = 999999;
                            }
                        } catch(e) {}
                    });
                    return readCont();
                });
            }
            return readCont();
        }
    })
    .catch(function(err) { 
        if (!aiBubble) typingEl.remove(); 
        if (err.message && err.message !== 'AbortError') addMsg('ai', 'Ошибка: ' + err.message); 
    })
    .finally(function() {
        clearTimeout(abortTimer);
        // If bubble is stuck on "Обрабатываю..." (JSON that never became a tool call), show real text
        if (aiBubble && !toolCalls.length && fullText) {
            var bubble = aiBubble.querySelector('.bubble');
            bubble.innerHTML = '';
            bubble.appendChild(renderMd(fullText));
        }
        if (fullText && currentUser && !toolCalls.length) {
            chatHistory.push({ role: 'assistant', content: fullText });
            API.addMsg(currentChatId, 'assistant', fullText, currentUser.username);
            saveCurrentChat(chatHistory[0] ? chatHistory[0].content : 'Чат');
        }
        generating = false;
        document.getElementById('sendBtn').disabled = false;
        document.getElementById('statusDot').className = 'status-indicator online';
        document.getElementById('input').focus();
    });
}

function addMsg(role, text) {
    var m = document.getElementById('messages');
    var div = document.createElement('div');
    div.className = 'msg ' + (role === 'user' ? 'user' : 'ai');
    var av = document.createElement('div');
    av.className = 'avatar';
    av.textContent = role === 'user' ? (currentUser ? currentUser.username[0].toUpperCase() : 'Я') : (role === 'system' ? '&#129522;' : '&#129432;');
    var bubble = document.createElement('div');
    bubble.className = 'bubble';
    if (text) bubble.appendChild(renderMd(text));
    div.appendChild(av); div.appendChild(bubble);
    m.appendChild(div); m.scrollTop = 999999;
    return div;
}

function addTyping() {
    var m = document.getElementById('messages');
    var div = document.createElement('div');
    div.className = 'typing-wrap';
    div.innerHTML = '<div class="avatar">&#129432;</div><div class="typing-bubble"><span></span><span></span><span></span></div>';
    m.appendChild(div); m.scrollTop = 999999;
    return div;
}

function renderMd(text) {
    var wrap = document.createElement('div');
    var BT = '\x60';
    var BT3 = BT+BT+BT;
    var parts = text.split(new RegExp('(' + BT3 + '[\\s\\S]*?' + BT3 + ')', 'g'));
    parts.forEach(function(part) {
        if (part.indexOf(BT3) === 0) {
            var code = part.replace(new RegExp('^' + BT3 + '\\w*\\n?'), '').replace(new RegExp(BT3 + '$'), '');
            var pre = document.createElement('pre');
            var btn = document.createElement('button');
            btn.className = 'copy-btn'; btn.textContent = 'копировать';
            btn.onclick = function() {
                navigator.clipboard.writeText(code);
                btn.textContent = 'скопировано';
                setTimeout(function(){ btn.textContent = 'копировать'; }, 2000);
            };
            var c = document.createElement('code'); c.textContent = code;
            pre.appendChild(btn); pre.appendChild(c); wrap.appendChild(pre);
        } else {
            var subs = part.split(new RegExp('(' + BT + '[^' + BT + ']+' + BT + ')', 'g'));
            subs.forEach(function(s) {
                if (s.charAt(0) === BT && s.charAt(s.length-1) === BT) {
                    var c = document.createElement('code'); c.textContent = s.slice(1,-1);
                    wrap.appendChild(c);
                } else {
                    wrap.appendChild(document.createTextNode(s));
                }
            });
        }
    });
    return wrap;
}

function escHtml(t) { return t.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;'); }

function showProfilePage() {
    if (!currentUser) return;
    API.stats(currentUser.username).then(function(stats) {
        document.getElementById('profileAvatar').textContent = currentUser.username[0].toUpperCase();
        document.getElementById('profileName').textContent   = currentUser.username;
        document.getElementById('profileSub').textContent    = 'AI-CICADA v5 · +Tools +Memory';
        document.getElementById('infoUser').textContent      = currentUser.username;
        document.getElementById('infoModel').textContent     = currentModel || '—';
        var d = stats.created_at ? new Date(stats.created_at * 1000) : new Date();
        document.getElementById('infoDate').textContent = d.toLocaleDateString('ru-RU', {day:'numeric',month:'long',year:'numeric'});
        var days = Math.max(1, Math.floor((Date.now() - d.getTime()) / 86400000));
        document.getElementById('statChats').textContent = stats.chat_count || 0;
        document.getElementById('statMsgs').textContent  = stats.msg_count  || 0;
        document.getElementById('statMemory').textContent = stats.memory_count || 0;
        document.getElementById('statDays').textContent  = days;
        showPage('profilePage');
        closeSidebar();
    });
}

function clearAllHistory() {
    if (!confirm('Удалить всю историю чатов?')) return;
    API.getChats(currentUser.username).then(function(chats) {
        var ps = chats.map(function(c){ return API.deleteChat(c.id); });
        Promise.all(ps).then(function(){ newChat(); showPage('chatPage'); });
    });
}

function deleteAccount() {
    if (!confirm('Удалить аккаунт и все данные? Нельзя отменить!')) return;
    API.getChats(currentUser.username).then(function(chats) {
        var ps = chats.map(function(c){ return API.deleteChat(c.id); });
        Promise.all(ps).then(function(){ logout(); });
    });
}

function openSidebar()  { document.getElementById('sidebar').classList.add('open'); document.getElementById('sidebarOverlay').classList.add('show'); }
function closeSidebar() { document.getElementById('sidebar').classList.remove('open'); document.getElementById('sidebarOverlay').classList.remove('show'); }

document.getElementById('input').addEventListener('input', function() {
    this.style.height = 'auto';
    this.style.height = Math.min(this.scrollHeight, 120) + 'px';
});
document.getElementById('input').addEventListener('keydown', function(e) {
    if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); send(); }
});

(function init() {
    var username = Session.get();
    if (username) {
        API.stats(username).then(function(stats) {
            if (!stats.error) {
                currentUser = Object.assign({ username: username }, stats);
                enterChat();
            } else {
                showPage('loginPage');
            }
        }).catch(function(){ showPage('loginPage'); });
    } else {
        showPage('loginPage');
    }
})();
</script>
</body>
</html>"""

with open(path, 'w') as f:
    f.write(html.lstrip('\n'))

print("index.html written OK")
PYEOF
}

create_chat_html() {
    printf "${BLUE}Creating ollama-chat.html (no Node.js required)...${NC}\n"
    mkdir -p "$CHAT_DIR"
    cat > "$CHAT_DIR/ollama-chat.html" << 'HTMLEOF'
<!DOCTYPE html>
<html lang="ru">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
<title>Ollama Chat</title>
<style>
@import url('https://fonts.googleapis.com/css2?family=IBM+Plex+Mono:wght@400;500&display=swap');
*,*::before,*::after{box-sizing:border-box;margin:0;padding:0}
:root{--bg:#080809;--bg2:#0f0f11;--bg3:#18181c;--bg4:#222228;--acc:#c8f135;--acc2:#3bffc0;--txt:#e8e8ec;--dim:#666672;--err:#ff4c6a;--font:'IBM Plex Mono',monospace}
html,body{height:100%;background:var(--bg);color:var(--txt);font-family:var(--font);font-size:14px}
#app{display:flex;flex-direction:column;height:100vh}
#header{display:flex;align-items:center;gap:10px;padding:10px 14px;border-bottom:1px solid var(--bg4);background:var(--bg2);flex-shrink:0}
#header .logo{color:var(--acc);font-weight:500;font-size:13px;letter-spacing:.05em}
#model-badge{margin-left:auto;background:var(--bg4);color:var(--acc2);padding:3px 9px;border-radius:20px;font-size:11px;cursor:pointer;border:1px solid transparent;transition:border-color .2s}
#model-badge:hover{border-color:var(--acc2)}
#status-dot{width:7px;height:7px;border-radius:50%;background:var(--dim);flex-shrink:0;transition:background .3s}
#status-dot.ok{background:var(--acc)}
#status-dot.err{background:var(--err)}
#status-dot.busy{background:var(--acc2);animation:pulse 1s infinite}
@keyframes pulse{0%,100%{opacity:1}50%{opacity:.3}}
#settings{display:none;flex-direction:column;gap:10px;padding:14px;border-bottom:1px solid var(--bg4);background:var(--bg2)}
#settings.open{display:flex}
#settings label{font-size:11px;color:var(--dim);margin-bottom:3px;display:block}
#settings input{width:100%;background:var(--bg3);color:var(--txt);border:1px solid var(--bg4);border-radius:6px;padding:7px 10px;font-family:var(--font);font-size:13px;outline:none}
#settings input:focus{border-color:var(--acc2)}
#settings .row{display:flex;gap:8px}
#settings .row>div{flex:1}
#btn-save{background:var(--acc);color:#000;border:none;padding:8px 16px;border-radius:6px;font-family:var(--font);font-size:12px;font-weight:500;cursor:pointer;align-self:flex-start}
#btn-save:hover{opacity:.85}
#messages{flex:1;overflow-y:auto;padding:14px;display:flex;flex-direction:column;gap:10px;scroll-behavior:smooth}
#messages::-webkit-scrollbar{width:4px}
#messages::-webkit-scrollbar-thumb{background:var(--bg4);border-radius:2px}
.msg{display:flex;gap:10px;animation:fadeIn .15s ease}
@keyframes fadeIn{from{opacity:0;transform:translateY(4px)}to{opacity:1;transform:none}}
.msg.user{flex-direction:row-reverse}
.msg.system-msg{justify-content:center}
.bubble{max-width:82%;padding:10px 13px;border-radius:14px;line-height:1.55;white-space:pre-wrap;word-break:break-word;font-size:13px}
.msg.user .bubble{background:var(--bg4);border-bottom-right-radius:4px}
.msg.assistant .bubble{background:var(--bg2);border:1px solid var(--bg3);border-bottom-left-radius:4px}
.msg.system-msg .bubble{background:transparent;color:var(--dim);font-size:11px;border:none;padding:0}
.msg.error .bubble{color:var(--err);background:transparent;border:none;padding:0;font-size:12px}
.avatar{width:28px;height:28px;border-radius:50%;display:flex;align-items:center;justify-content:center;font-size:13px;flex-shrink:0;margin-top:2px}
.msg.user .avatar{background:var(--bg4)}
.msg.assistant .avatar{background:var(--bg2);border:1px solid var(--bg3)}
.cursor::after{content:'▋';animation:blink .7s step-end infinite}
@keyframes blink{0%,100%{opacity:1}50%{opacity:0}}
#inputbar{display:flex;gap:8px;padding:10px 14px;border-top:1px solid var(--bg4);background:var(--bg2);flex-shrink:0}
#input{flex:1;background:var(--bg3);color:var(--txt);border:1px solid var(--bg4);border-radius:10px;padding:9px 12px;font-family:var(--font);font-size:13px;outline:none;resize:none;max-height:120px;line-height:1.4;transition:border-color .2s}
#input:focus{border-color:var(--acc2)}
#input::placeholder{color:var(--dim)}
#btn-send{width:40px;height:40px;border-radius:10px;background:var(--acc);color:#000;border:none;cursor:pointer;font-size:18px;flex-shrink:0;display:flex;align-items:center;justify-content:center;transition:opacity .15s,transform .1s;align-self:flex-end}
#btn-send:active{transform:scale(.92)}
#btn-send:disabled{background:var(--bg4);color:var(--dim);cursor:not-allowed;transform:none}
</style>
</head>
<body>
<div id="app">
  <div id="header">
    <span class="logo">◈ OLLAMA</span>
    <div id="status-dot"></div>
    <div id="model-badge" onclick="toggleSettings()">⚙ <span id="model-label">...</span></div>
  </div>
  <div id="settings">
    <div class="row">
      <div><label>Ollama URL</label><input id="s-url" value="http://localhost:11434"/></div>
      <div><label>Модель</label><input id="s-model" placeholder="llama3:8b"/></div>
    </div>
    <button id="btn-save" onclick="saveSettings()">Применить</button>
  </div>
  <div id="messages"></div>
  <div id="inputbar">
    <textarea id="input" rows="1" placeholder="Напишите сообщение..."></textarea>
    <button id="btn-send" onclick="send()">➤</button>
  </div>
</div>
<script>
const $=id=>document.getElementById(id);
let cfg={url:localStorage.getItem('ol_url')||'http://localhost:11434',model:localStorage.getItem('ol_model')||'qwen2.5-coder:3b'};
let history=[],busy=false;
function applyConfig(){$('s-url').value=cfg.url;$('s-model').value=cfg.model;$('model-label').textContent=cfg.model;}
function saveSettings(){cfg.url=$('s-url').value.trim().replace(/\/$/,'');cfg.model=$('s-model').value.trim();localStorage.setItem('ol_url',cfg.url);localStorage.setItem('ol_model',cfg.model);applyConfig();toggleSettings();ping();}
function toggleSettings(){$('settings').classList.toggle('open');}
async function ping(){const dot=$('status-dot');try{const r=await fetch(cfg.url+'/api/tags',{signal:AbortSignal.timeout(4000)});dot.className=r.ok?'ok':'err';}catch{dot.className='err';}}
function addMsg(role,text){const wrap=document.createElement('div');wrap.className='msg '+role;if(role!=='system-msg'){const av=document.createElement('div');av.className='avatar';av.textContent=role==='user'?'T':'🐸';wrap.appendChild(av);}const bub=document.createElement('div');bub.className='bubble';bub.textContent=text;wrap.appendChild(bub);$('messages').appendChild(wrap);wrap.scrollIntoView({block:'end'});return bub;}
function sysMsg(text){addMsg('system-msg',text);}
async function send(){if(busy)return;const txt=$('input').value.trim();if(!txt)return;$('input').value='';$('input').style.height='auto';addMsg('user',txt);history.push({role:'user',content:txt});busy=true;$('btn-send').disabled=true;$('status-dot').className='busy';const bub=addMsg('assistant','');bub.classList.add('cursor');try{const res=await fetch(cfg.url+'/api/chat',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({model:cfg.model,messages:history,stream:true})});if(!res.ok)throw new Error('HTTP '+res.status);const reader=res.body.getReader();const dec=new TextDecoder();let full='';while(true){const{done,value}=await reader.read();if(done)break;const lines=dec.decode(value).split('\n').filter(Boolean);for(const line of lines){try{const j=JSON.parse(line);const chunk=j?.message?.content||'';if(chunk){full+=chunk;bub.textContent=full;bub.parentElement.scrollIntoView({block:'end'});}}catch{}}}bub.classList.remove('cursor');history.push({role:'assistant',content:full});}catch(e){bub.classList.remove('cursor');bub.parentElement.className='msg error';bub.textContent='✗ '+(e.message||'Ошибка соединения');history.pop();}busy=false;$('btn-send').disabled=false;$('status-dot').className='ok';$('input').focus();}
$('input').addEventListener('input',function(){this.style.height='auto';this.style.height=Math.min(this.scrollHeight,120)+'px';});
$('input').addEventListener('keydown',function(e){if(e.key==='Enter'&&!e.shiftKey){e.preventDefault();send();}});
applyConfig();ping();sysMsg('Ollama: '+cfg.url);
</script>
</body>
</html>
HTMLEOF
    printf "${GREEN}ollama-chat.html created: %s/ollama-chat.html${NC}\n" "$CHAT_DIR"
    log "ollama-chat.html created"
}

create_web_chat() {
    printf "${BLUE}Creating web chat files...${NC}\n"
    mkdir -p "$CHAT_DIR"
    create_server_js
    create_index_html
    printf "${GREEN}Web chat created in %s${NC}\n" "$CHAT_DIR"
    log "Web chat created"
}

setup_alias() {
    printf "${BLUE}Setting up commands...${NC}\n"
    local SHELLRC="$HOME/.bashrc"
    if [ "$ENV_TYPE" = "homeassistant" ] || [ "$ENV_TYPE" = "alpine" ] || [ "$ENV_TYPE" = "wsl-ha" ]; then
        if [ -f "$HOME/.bashrc" ]; then SHELLRC="$HOME/.bashrc";
        else SHELLRC="$HOME/.profile"; fi
    fi
    if grep -q "# AI-CICADA" "$SHELLRC" 2>/dev/null; then
        sed -i '/# AI-CICADA/,/# END AI-CICADA/d' "$SHELLRC"
    fi
    cat >> "$SHELLRC" << ALIASEOF

# AI-CICADA
export AI_MODEL="$MODEL"
export AI_CICADA_DIR="$CHAT_DIR"

ai() {
    set +e
    if ! pgrep -x "ollama" > /dev/null 2>&1; then
        printf "Starting Ollama...\n"
        ollama serve > /dev/null 2>&1 &
        sleep 3
    fi
    ollama run \$AI_MODEL
    set -e 2>/dev/null || true
}

web() {
    set +e
    if ! pgrep -x "ollama" > /dev/null 2>&1; then
        printf "Starting Ollama...\n"
        OLLAMA_ORIGINS='*' ollama serve > /dev/null 2>&1 &
        sleep 3
    fi
    CHAT_IP=\$(ip route get 1 2>/dev/null | awk '{for(i=1;i<=NF;i++)if(\$i=="src"){print \$(i+1);exit}}' || hostname -I 2>/dev/null | awk '{print \$1}' || echo "localhost")
    printf "Model  : \${AI_MODEL}\n"
    printf "Web    : http://\${CHAT_IP}:3000\n"
    OLLAMA_ORIGINS='*' AI_MODEL=\$AI_MODEL node \$AI_CICADA_DIR/server.js || {
        printf "Error: server crashed. Check logs.\n"
    }
    set -e 2>/dev/null || true
}

aidb() {
    printf "DB: \$AI_CICADA_DIR/cicada.db\n"
    if command -v sqlite3 >/dev/null 2>&1; then
        sqlite3 "\$AI_CICADA_DIR/cicada.db" "SELECT username, total_msgs, datetime(created_at,'unixepoch') as reg FROM users;"
    fi
}
# END AI-CICADA
ALIASEOF
    printf "${GREEN}Commands ready: 'ai', 'web', 'aidb'${NC}\n"
}

show_ha_tips() {
    if [ "$ENV_TYPE" != "homeassistant" ] && [ "$ENV_TYPE" != "wsl-ha" ]; then return; fi
    clear
    center_text "${GREEN}Home Assistant - советы${NC}"
    printf "\n"
    draw_box \
        "Данные: /config/.ai-cicada/" \
        "БД:     /config/.ai-cicada/cicada.db" \
        "" \
        "Автозапуск Ollama:" \
        "  ollama serve &" \
        "" \
        "Веб-чат: http://<HA-IP>:3000" \
        "" \
        "Просмотр БД: команда 'aidb'"
    printf "\n"
    press_any_key
}

final_screen() {
    clear
    # Cross-platform IP detection
    local CHAT_HOST
    CHAT_HOST=$(ip route get 1 2>/dev/null | awk '{for(i=1;i<=NF;i++)if($i=="src"){print $(i+1);exit}}' || hostname -I 2>/dev/null | awk '{print $1}' || echo "localhost")
    local display_env="$ENV_TYPE"
    case "$ENV_TYPE" in
        wsl|wsl-ha) display_env="WSL (Windows)" ;;
        homeassistant) display_env="Home Assistant" ;;
        termux) display_env="Termux (Android)" ;;
        debian) display_env="Debian/Ubuntu" ;;
        fedora) display_env="Fedora" ;;
        arch) display_env="Arch Linux" ;;
        alpine) display_env="Alpine Linux" ;;
        opensuse) display_env="openSUSE" ;;
        void) display_env="Void Linux" ;;
    esac
    draw_box \
        "INSTALLATION COMPLETE" \
        "" \
        "Platform : $display_env" \
        "Model    : $MODEL" \
        "DB       : $CHAT_DIR/cicada.db" \
        "Features : +Tools +Memory +WebSearch" \
        "" \
        "  web   -- http://${CHAT_HOST}:3000" \
        "  chat  -- $CHAT_DIR/ollama-chat.html" \
        "  ai    -- terminal agent" \
        "  aidb  -- view database" \
        "" \
        "Log: $LOG_FILE"
    printf "\n"
    center_text "${CYAN}Restart terminal or: source ~/.bashrc${NC}"
    printf "\n"
    press_any_key
}

launch_choice() {
    clear
    center_text "${YELLOW}What to launch now?${NC}"
    printf "\n"
    draw_box "1) Browser chat (web)" "2) Terminal agent (ai)" "3) Exit"
    printf "\n${YELLOW}Choice: ${NC}"
    read -r ch </dev/tty
    # Cross-platform IP detection
    local CHAT_HOST
    CHAT_HOST=$(ip route get 1 2>/dev/null | awk '{for(i=1;i<=NF;i++)if($i=="src"){print $(i+1);exit}}' || hostname -I 2>/dev/null | awk '{print $1}' || echo "localhost")
    case $ch in
        1)
            if ! pgrep -x "ollama" > /dev/null 2>&1; then OLLAMA_ORIGINS='*' ollama serve >> "$LOG_FILE" 2>&1 & sleep 3; fi
            printf "${GREEN}Open: http://%s:3000${NC}\n" "$CHAT_HOST"
            printf "${YELLOW}Press Ctrl+C to stop${NC}\n"
            AI_MODEL="$MODEL" node "$CHAT_DIR/server.js"
            ;;
        2)
            if ! pgrep -x "ollama" > /dev/null 2>&1; then OLLAMA_ORIGINS='*' ollama serve >> "$LOG_FILE" 2>&1 & sleep 3; fi
            ollama run "$MODEL"
            ;;
        *) printf "${GREEN}Done! Run 'ai' or 'web' anytime.${NC}\n" ;;
    esac
}

main() {
    echo "===== AI-CICADA INSTALL $(date) =====" > "$LOG_FILE"
    detect_env
    fix_termux_libs
    show_logo
    select_model
    update_system; clear
    install_nodejs; printf "\n"
    install_sqlite_tools; printf "\n"
    install_python; printf "\n"
    install_ollama; printf "\n"
    start_ollama_service
    install_model; clear
    install_npm_deps; printf "\n"
    create_web_chat; printf "\n"
    create_chat_html; printf "\n"
    setup_alias; printf "\n"
    show_ha_tips
    final_screen
    launch_choice
}

main "$@"
