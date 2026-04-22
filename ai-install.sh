#!/bin/bash

set -e

LOG_FILE="$HOME/ollama_install.log"
CHAT_DIR="$HOME/.ai-cicada"

# ===== COLORS =====
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
MAGENTA='\033[0;35m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

# ===== DETECT ENVIRONMENT =====
detect_env() {
    # Home Assistant OS detection
    if [ -f /etc/hassio_supervisor ] || [ -f /etc/homeassistant ] || \
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
    elif command -v apt &>/dev/null; then
        ENV_TYPE="debian"
        PKG_MANAGER="apt"
        SUDO="sudo"
    elif command -v dnf &>/dev/null; then
        ENV_TYPE="fedora"
        PKG_MANAGER="dnf"
        SUDO="sudo"
    elif command -v pacman &>/dev/null; then
        ENV_TYPE="arch"
        PKG_MANAGER="pacman"
        SUDO="sudo"
    elif command -v apk &>/dev/null; then
        ENV_TYPE="alpine"
        PKG_MANAGER="apk"
        SUDO=""
    else
        ENV_TYPE="unknown"
        PKG_MANAGER=""
        SUDO="sudo"
    fi
    log "Detected environment: $ENV_TYPE"
}

# ===== SAFE TPUT =====
safe_tput_cols() {
    if command -v tput &>/dev/null && tput cols &>/dev/null 2>&1; then
        tput cols
    else
        echo 80
    fi
}

safe_tput_lines() {
    if command -v tput &>/dev/null && tput lines &>/dev/null 2>&1; then
        tput lines
    else
        echo 24
    fi
}

# ===== LOG =====
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG_FILE"
}

# ===== CENTER TEXT =====
center_text() {
    local text="$1"
    local termwidth
    termwidth=$(safe_tput_cols)
    local clean
    clean=$(echo -e "$text" | sed 's/\x1b\[[0-9;]*m//g')
    local len=${#clean}
    local padding=$(( (termwidth - len) / 2 ))
    [ $padding -lt 0 ] && padding=0
    printf "%*s%b\n" "$padding" "" "$text"
}

# ===== PRESS ANY KEY =====
press_any_key() {
    center_text "${YELLOW}Press any key to continue...${NC}"
    read -r -n 1 -s </dev/tty || read -r </dev/tty || true
}

# ===== REPEAT CHAR =====
repeat_char() {
    local char="$1"
    local count="$2"
    local i=0
    while [ $i -lt "$count" ]; do
        printf "%s" "$char"
        i=$(( i + 1 ))
    done
}

# ===== BOX UI =====
draw_box() {
    local width=60
    local termwidth
    termwidth=$(safe_tput_cols)
    local padding=$(( (termwidth - width) / 2 ))
    [ $padding -lt 0 ] && padding=0

    printf "%${padding}s┌" ""
    repeat_char "─" $(( width - 2 ))
    printf "┐\n"

    for line in "$@"; do
        printf "%${padding}s│ %-56s │\n" "" "$line"
    done

    printf "%${padding}s└" ""
    repeat_char "─" $(( width - 2 ))
    printf "┘\n"
}

# ===== SPINNER =====
spinner() {
    local pid=$1
    local spin='|/-\'
    while kill -0 "$pid" 2>/dev/null; do
        local temp=${spin#?}
        printf "\r${BLUE}[%c] Processing...${NC}" "$spin"
        spin=$temp${spin%"$temp"}
        sleep 0.1
    done
    printf "\r%-30s\r" " "
}

# ===== TIMER =====
timer_start() { START=$(date +%s); }
timer_end() {
    END=$(date +%s)
    echo -e "${GREEN}⏱️  Time: $((END - START)) sec${NC}"
}

# ===== LOGO =====
show_logo() {
    clear

    echo -e "${MAGENTA}"

    center_text "  ####   ####  "
    center_text "  ## ##   ##   "
    center_text "  ####    ##   "
    center_text "  ## ##   ##   "
    center_text "  ## ##  ####  "

    echo

    center_text " ####  ####  ####  ####  ####  ####  "
    center_text "##    ##    ##    ##  ## ##  ## ##  ##"
    center_text "##    ####  ##    ###### ##  ## ##  ##"
    center_text "##    ##    ##    ##  ## ##  ## ##  ##"
    center_text " ####  ####  ####  ##  ## ####  ##  ##"

    echo -e "${NC}"

    local w
    w=$(safe_tput_cols)
    local line=""
    local i=0
    while [ $i -lt $w ]; do line="${line}─"; i=$(( i + 1 )); done
    echo -e "${MAGENTA}${line}${NC}"
    echo

    center_text "${CYAN}★  AI-CICADA INSTALLER v4.0  ★${NC}"
    center_text "${YELLOW}Platform: ${ENV_TYPE}${NC}"

    if [ "$ENV_TYPE" = "homeassistant" ]; then
        echo
        center_text "${GREEN}🏠 Home Assistant mode — /config/.ai-cicada${NC}"
    fi

    echo

    local w2
    w2=$(safe_tput_cols)
    local line2=""
    local j=0
    while [ $j -lt $w2 ]; do line2="${line2}─"; j=$(( j + 1 )); done
    echo -e "${MAGENTA}${line2}${NC}"
    echo

    press_any_key
}

# ===== MODEL MENU =====
select_model() {
    clear
    center_text "${CYAN}Select Model:${NC}"
    echo

    if [ "$ENV_TYPE" = "homeassistant" ]; then
        draw_box \
            "1) qwen2.5-coder:1.5b (HA — мало RAM)" \
            "2) qwen2.5-coder:3b   (recommended)" \
            "3) llama3.2:3b        (HA — баланс)" \
            "4) phi3:mini          (лёгкая)" \
            "5) mistral:7b         (мощная)" \
            "6) Manual input"
    else
        draw_box \
            "1) qwen2.5-coder:3b  (recommended)" \
            "2) llama3:8b" \
            "3) mistral:7b" \
            "4) phi3:mini" \
            "5) Manual input"
    fi

    echo
    printf "${YELLOW}Choice: ${NC}"
    read -r choice </dev/tty

    if [ "$ENV_TYPE" = "homeassistant" ]; then
        case $choice in
            1) MODEL="qwen2.5-coder:1.5b" ;;
            2) MODEL="qwen2.5-coder:3b" ;;
            3) MODEL="llama3.2:3b" ;;
            4) MODEL="phi3:mini" ;;
            5) MODEL="mistral:7b" ;;
            6)
                printf "${YELLOW}Enter model name: ${NC}"
                read -r MODEL </dev/tty
                ;;
            *)
                echo -e "${RED}Invalid choice${NC}"
                sleep 2
                select_model
                return
                ;;
        esac
    else
        case $choice in
            1) MODEL="qwen2.5-coder:3b" ;;
            2) MODEL="llama3:8b" ;;
            3) MODEL="mistral:7b" ;;
            4) MODEL="phi3:mini" ;;
            5)
                printf "${YELLOW}Enter model name: ${NC}"
                read -r MODEL </dev/tty
                ;;
            *)
                echo -e "${RED}Invalid choice${NC}"
                sleep 2
                select_model
                return
                ;;
        esac
    fi

    log "Selected model: $MODEL"
    clear
}

# ===== FIX BROKEN DPKG =====
fix_dpkg_termux() {
    echo -e "${YELLOW}🔧 Fixing broken dpkg state...${NC}"
    echo N | dpkg --configure -a >> "$LOG_FILE" 2>&1 || true
    log "dpkg fix attempted"
}

# ===== UPDATE SYSTEM =====
update_system() {
    echo -e "${BLUE}🔧 Updating system...${NC}"
    timer_start

    case $ENV_TYPE in
        termux)
            fix_dpkg_termux
            (yes N | pkg update -y 2>>"$LOG_FILE" && yes N | pkg upgrade -y 2>>"$LOG_FILE") &
            spinner $!
            ;;
        debian)
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
        homeassistant|alpine)
            (apk update >> "$LOG_FILE" 2>&1) &
            spinner $!
            ;;
        *)
            echo -e "${YELLOW}⚠️  Unknown package manager, skipping update${NC}"
            return
            ;;
    esac

    timer_end
}

# ===== INSTALL NODEJS =====
install_nodejs() {
    echo -e "${BLUE}🔎 Checking Node.js...${NC}"

    if command -v node &>/dev/null && command -v npm &>/dev/null; then
        local ver
        ver=$(node --version 2>/dev/null)
        echo -e "${GREEN}✔️  Node.js already installed ($ver)${NC}"
        log "Node.js already installed: $ver"
        return
    fi

    echo -e "${BLUE}📥 Installing Node.js...${NC}"
    timer_start

    case $ENV_TYPE in
        termux)
            (yes N | pkg install -y nodejs 2>>"$LOG_FILE") &
            spinner $!
            ;;
        debian)
            (sudo DEBIAN_FRONTEND=noninteractive apt install -y nodejs npm \
               -o Dpkg::Options::="--force-confold" >> "$LOG_FILE" 2>&1) &
            spinner $!
            ;;
        fedora)
            (sudo dnf install -y nodejs npm >> "$LOG_FILE" 2>&1) &
            spinner $!
            ;;
        arch)
            (sudo pacman -S --noconfirm nodejs npm >> "$LOG_FILE" 2>&1) &
            spinner $!
            ;;
        homeassistant|alpine)
            (apk add --no-cache nodejs npm >> "$LOG_FILE" 2>&1) &
            spinner $!
            ;;
        *)
            echo -e "${YELLOW}⚠️  Please install Node.js manually${NC}"
            return
            ;;
    esac

    timer_end

    if command -v node &>/dev/null; then
        echo -e "${GREEN}✔️  Node.js installed $(node --version)${NC}"
        log "Node.js installed successfully"
    else
        echo -e "${RED}❌ Node.js installation failed. Check $LOG_FILE${NC}"
        exit 1
    fi
}

# ===== INSTALL SQLITE3 CLI (опционально для отладки) =====
install_sqlite_tools() {
    echo -e "${BLUE}🔎 Checking SQLite tools...${NC}"
    case $ENV_TYPE in
        termux)
            command -v sqlite3 &>/dev/null || (yes N | pkg install -y sqlite 2>>"$LOG_FILE") &
            ;;
        debian)
            command -v sqlite3 &>/dev/null || (sudo apt install -y sqlite3 >> "$LOG_FILE" 2>&1) &
            ;;
        fedora)
            command -v sqlite3 &>/dev/null || (sudo dnf install -y sqlite >> "$LOG_FILE" 2>&1) &
            ;;
        arch)
            command -v sqlite3 &>/dev/null || (sudo pacman -S --noconfirm sqlite >> "$LOG_FILE" 2>&1) &
            ;;
        homeassistant|alpine)
            command -v sqlite3 &>/dev/null || (apk add --no-cache sqlite >> "$LOG_FILE" 2>&1) &
            ;;
    esac
    spinner $! 2>/dev/null || true
    echo -e "${GREEN}✔️  SQLite tools ready${NC}"
}

# ===== INSTALL OLLAMA =====
install_ollama() {
    echo -e "${BLUE}🔎 Checking Ollama...${NC}"

    if command -v ollama &>/dev/null; then
        echo -e "${GREEN}✔️  Ollama already installed${NC}"
        log "Ollama already installed"
        return
    fi

    echo -e "${BLUE}📥 Installing Ollama...${NC}"
    timer_start

    case $ENV_TYPE in
        termux)
            if pkg show ollama &>/dev/null 2>&1; then
                (yes N | pkg install -y ollama >> "$LOG_FILE" 2>&1) &
                spinner $!
            else
                echo -e "${YELLOW}⚠️  Ollama not in pkg repos, using proot-distro...${NC}"
                (yes N | pkg install -y proot-distro >> "$LOG_FILE" 2>&1)
                proot-distro install ubuntu >> "$LOG_FILE" 2>&1
                proot-distro login ubuntu -- bash -c \
                    "curl -fsSL https://ollama.com/install.sh | sh" \
                    >> "$LOG_FILE" 2>&1 &
                spinner $!
                cat > "$PREFIX/bin/ollama" << 'EOF'
#!/bin/bash
proot-distro login ubuntu -- ollama "$@"
EOF
                chmod +x "$PREFIX/bin/ollama"
            fi
            ;;
        homeassistant)
            echo -e "${YELLOW}🏠 Home Assistant: installing Ollama for Alpine/musl...${NC}"
            # HA OS использует Alpine, Ollama нужно ставить через бинарник
            ARCH=$(uname -m)
            case $ARCH in
                x86_64)  OLLAMA_BIN="ollama-linux-amd64" ;;
                aarch64) OLLAMA_BIN="ollama-linux-arm64" ;;
                armv7l)  OLLAMA_BIN="ollama-linux-arm" ;;
                *)
                    echo -e "${RED}❌ Unsupported arch: $ARCH${NC}"
                    exit 1
                    ;;
            esac
            (curl -fsSL "https://github.com/ollama/ollama/releases/latest/download/${OLLAMA_BIN}" \
                -o /usr/local/bin/ollama >> "$LOG_FILE" 2>&1 && \
             chmod +x /usr/local/bin/ollama) &
            spinner $!
            ;;
        *)
            curl -fsSL https://ollama.com/install.sh | sh >> "$LOG_FILE" 2>&1 &
            spinner $!
            ;;
    esac

    timer_end

    if command -v ollama &>/dev/null; then
        echo -e "${GREEN}✔️  Ollama installed${NC}"
        log "Ollama installed successfully"
    else
        echo -e "${RED}❌ Ollama installation failed. Check $LOG_FILE${NC}"
        exit 1
    fi
}

# ===== START OLLAMA SERVICE =====
start_ollama_service() {
    echo -e "${BLUE}🚀 Starting Ollama service...${NC}"

    if pgrep -x "ollama" > /dev/null 2>&1; then
        echo -e "${GREEN}✔️  Ollama already running${NC}"
        return
    fi

    case $ENV_TYPE in
        termux)
            ollama serve >> "$LOG_FILE" 2>&1 &
            ;;
        homeassistant)
            # HA не имеет systemd — запускаем фоном, создаём rc.local hook
            ollama serve >> "$LOG_FILE" 2>&1 &
            echo -e "${YELLOW}ℹ️  Ollama запущен в фоне. После перезагрузки HA запустите вручную: ollama serve &${NC}"
            ;;
        *)
            if command -v systemctl &>/dev/null; then
                sudo systemctl enable --now ollama >> "$LOG_FILE" 2>&1 || \
                    ollama serve >> "$LOG_FILE" 2>&1 &
            else
                ollama serve >> "$LOG_FILE" 2>&1 &
            fi
            ;;
    esac

    sleep 3
    echo -e "${GREEN}✔️  Ollama service started${NC}"
}

# ===== INSTALL MODEL =====
install_model() {
    echo -e "${BLUE}🔎 Checking model: $MODEL${NC}"

    if ollama list 2>/dev/null | grep -q "$MODEL"; then
        echo -e "${GREEN}✔️  Model already installed${NC}"
        log "Model $MODEL already installed"
        return
    fi

    echo -e "${BLUE}📦 Downloading $MODEL...${NC}"
    timer_start
    log "Downloading model: $MODEL"

    ollama pull "$MODEL" 2>&1 | while IFS= read -r line; do
        if echo "$line" | grep -qE '[0-9]+%'; then
            percent=$(echo "$line" | grep -oE '[0-9]+%' | tail -1)
            printf "\r${GREEN}📥 Progress: %-6s${NC}" "$percent"
        fi
        echo "$line" >> "$LOG_FILE"
    done

    echo
    timer_end
    echo -e "${GREEN}✔️  Model $MODEL installed${NC}"
    log "Model $MODEL installed successfully"
}

# ===== INSTALL NPM DEPS (better-sqlite3) =====
install_npm_deps() {
    echo -e "${BLUE}📦 Installing npm dependencies (better-sqlite3)...${NC}"
    mkdir -p "$CHAT_DIR"

    cd "$CHAT_DIR"

    # package.json
    cat > package.json << 'PKGEOF'
{
  "name": "ai-cicada",
  "version": "4.0.0",
  "description": "AI-CICADA local chat server with SQLite",
  "main": "server.js",
  "dependencies": {
    "better-sqlite3": "^9.4.3"
  }
}
PKGEOF

    (npm install --save better-sqlite3 >> "$LOG_FILE" 2>&1) &
    spinner $!

    if [ -d "$CHAT_DIR/node_modules/better-sqlite3" ]; then
        echo -e "${GREEN}✔️  better-sqlite3 installed${NC}"
    else
        echo -e "${YELLOW}⚠️  better-sqlite3 failed, falling back to в памяти${NC}"
        DB_FALLBACK=1
    fi

    cd - > /dev/null
}

# ===== CREATE WEB CHAT SERVER =====
create_web_chat() {
    echo -e "${BLUE}🌐 Creating web chat...${NC}"
    mkdir -p "$CHAT_DIR"

    # ── server.js ──
    cat > "$CHAT_DIR/server.js" << 'SERVEREOF'
const http   = require('http');
const fs     = require('fs');
const path   = require('path');
const crypto = require('crypto');

const PORT       = 3000;
const OLLAMA_URL = 'http://localhost:11434';
const MODEL      = process.env.AI_MODEL || 'qwen2.5-coder:3b';
const DB_PATH    = path.join(__dirname, 'cicada.db');

/* ══════════════════════════════════════
   SQLite (лучше-sqlite3 или встроенный fallback)
══════════════════════════════════════ */
let db = null;

function initDB() {
    try {
        const Database = require('better-sqlite3');
        db = new Database(DB_PATH);
        db.pragma('journal_mode = WAL');
        db.pragma('foreign_keys = ON');

        db.exec(`
            CREATE TABLE IF NOT EXISTS users (
                id        INTEGER PRIMARY KEY AUTOINCREMENT,
                username  TEXT UNIQUE NOT NULL,
                password  TEXT NOT NULL,
                created_at INTEGER DEFAULT (strftime('%s','now')),
                total_msgs INTEGER DEFAULT 0
            );

            CREATE TABLE IF NOT EXISTS chats (
                id         TEXT PRIMARY KEY,
                username   TEXT NOT NULL,
                title      TEXT NOT NULL DEFAULT 'Новый чат',
                created_at INTEGER DEFAULT (strftime('%s','now')),
                updated_at INTEGER DEFAULT (strftime('%s','now')),
                FOREIGN KEY(username) REFERENCES users(username) ON DELETE CASCADE
            );

            CREATE TABLE IF NOT EXISTS messages (
                id         INTEGER PRIMARY KEY AUTOINCREMENT,
                chat_id    TEXT NOT NULL,
                role       TEXT NOT NULL CHECK(role IN ('user','assistant','system')),
                content    TEXT NOT NULL,
                created_at INTEGER DEFAULT (strftime('%s','now')),
                FOREIGN KEY(chat_id) REFERENCES chats(id) ON DELETE CASCADE
            );

            CREATE INDEX IF NOT EXISTS idx_chats_user ON chats(username);
            CREATE INDEX IF NOT EXISTS idx_msgs_chat  ON messages(chat_id);
        `);

        console.log('✅ SQLite DB initialised:', DB_PATH);
    } catch(e) {
        console.warn('⚠️  better-sqlite3 not available, using in-memory store:', e.message);
        db = null;
    }
}

/* In-memory fallback (если SQLite недоступен) */
const memStore = { users: {}, chats: {} };

/* ── helpers ── */
function hashPwd(p) { return crypto.createHash('sha256').update(p).digest('hex'); }

/* ── USER API ── */
function createUser(username, password) {
    if (db) {
        try {
            db.prepare('INSERT INTO users (username, password) VALUES (?, ?)')
              .run(username, hashPwd(password));
            return true;
        } catch { return false; }
    }
    if (memStore.users[username]) return false;
    memStore.users[username] = { password: hashPwd(password), created_at: Date.now()/1000|0, total_msgs: 0 };
    return true;
}

function getUser(username) {
    if (db) return db.prepare('SELECT * FROM users WHERE username=?').get(username) || null;
    return memStore.users[username] ? { ...memStore.users[username], username } : null;
}

function checkPassword(username, password) {
    const u = getUser(username);
    if (!u) return false;
    return u.password === hashPwd(password);
}

function incUserMsgs(username) {
    if (db) { db.prepare('UPDATE users SET total_msgs=total_msgs+1 WHERE username=?').run(username); return; }
    if (memStore.users[username]) memStore.users[username].total_msgs++;
}

/* ── CHAT API ── */
function getUserChats(username) {
    if (db) {
        return db.prepare(`
            SELECT c.*, COUNT(m.id) as msg_count
            FROM chats c LEFT JOIN messages m ON m.chat_id=c.id
            WHERE c.username=? GROUP BY c.id ORDER BY c.updated_at DESC
        `).all(username);
    }
    return Object.values(memStore.chats)
        .filter(c => c.username === username)
        .sort((a,b) => b.updated_at - a.updated_at);
}

function getChat(chatId) {
    if (db) return db.prepare('SELECT * FROM chats WHERE id=?').get(chatId) || null;
    return memStore.chats[chatId] || null;
}

function upsertChat(chatId, username, title) {
    if (db) {
        const existing = db.prepare('SELECT id FROM chats WHERE id=?').get(chatId);
        if (existing) {
            db.prepare('UPDATE chats SET title=?, updated_at=strftime(\'%s\',\'now\') WHERE id=?')
              .run(title, chatId);
        } else {
            db.prepare('INSERT INTO chats (
