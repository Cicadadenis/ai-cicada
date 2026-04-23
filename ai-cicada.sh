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
    if [ -n "$TERMUX_VERSION" ] || [ -d "/data/data/com.termux" ]; then
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

    # Рисуем логотип чистыми ASCII # — одна ширина символа, идеальная центровка
    echo -e "${MAGENTA}"

    # AI
    center_text "  ####   ####  "
    center_text "  ## ##   ##   "
    center_text "  ####    ##   "
    center_text "  ## ##   ##   "
    center_text "  ## ##  ####  "

    echo

    # CICADA
    center_text " ####  ####  ####  ####  ####  ####  "
    center_text "##    ##    ##    ##  ## ##  ## ##  ##"
    center_text "##    ####  ##    ###### ##  ## ##  ##"
    center_text "##    ##    ##    ##  ## ##  ## ##  ##"
    center_text " ####  ####  ####  ##  ## ####  ##  ##"

    echo -e "${NC}"

    # Горизонтальная линия по ширине терминала
    local w
    w=$(safe_tput_cols)
    local line=""
    local i=0
    while [ $i -lt $w ]; do line="${line}─"; i=$(( i + 1 )); done
    echo -e "${MAGENTA}${line}${NC}"
    echo

    center_text "${CYAN}★  AI-CICADA INSTALLER v3.0  ★${NC}"
    center_text "${YELLOW}Platform: ${ENV_TYPE}${NC}"
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

    draw_box \
        "1) qwen2.5-coder:3b  (recommended)" \
        "2) llama3:8b" \
        "3) mistral:7b" \
        "4) phi3:mini" \
        "5) Manual input"

    echo
    printf "${YELLOW}Choice: ${NC}"
    read -r choice </dev/tty

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

# ===== CREATE WEB CHAT SERVER =====
create_web_chat() {
    echo -e "${BLUE}🌐 Creating web chat...${NC}"

    mkdir -p "$CHAT_DIR"

    # ── server.js ──
    cat > "$CHAT_DIR/server.js" << 'SERVEREOF'
const http = require('http');
const fs   = require('fs');
const path = require('path');

const PORT       = 3000;
const OLLAMA_URL = 'http://localhost:11434';
const MODEL      = process.env.AI_MODEL || 'qwen2.5-coder:3b';

const server = http.createServer(async (req, res) => {

    // CORS
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader('Access-Control-Allow-Methods', 'GET,POST,OPTIONS');
    res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
    if (req.method === 'OPTIONS') { res.writeHead(204); res.end(); return; }

    // Отдаём index.html
    if (req.method === 'GET' && (req.url === '/' || req.url === '/index.html')) {
        const html = fs.readFileSync(path.join(__dirname, 'index.html'));
        res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
        res.end(html);
        return;
    }

    // GET /model — возвращаем текущую модель
    if (req.method === 'GET' && req.url === '/model') {
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ model: MODEL }));
        return;
    }

    // POST /chat — стриминг ответа от Ollama
    if (req.method === 'POST' && req.url === '/chat') {
        let body = '';
        req.on('data', chunk => body += chunk);
        req.on('end', () => {
            let messages;
            try { messages = JSON.parse(body).messages; }
            catch { res.writeHead(400); res.end('Bad JSON'); return; }

            const payload = JSON.stringify({ model: MODEL, messages, stream: true });

            const options = {
                hostname: 'localhost',
                port: 11434,
                path: '/api/chat',
                method: 'POST',
                headers: { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(payload) }
            };

            res.writeHead(200, {
                'Content-Type': 'text/event-stream',
                'Cache-Control': 'no-cache',
                'Connection': 'keep-alive'
            });

            const ollamaReq = http.request(options, ollamaRes => {
                ollamaRes.on('data', chunk => {
                    const lines = chunk.toString().split('\n').filter(Boolean);
                    lines.forEach(line => {
                        try {
                            const json = JSON.parse(line);
                            const text = json?.message?.content || '';
                            if (text) res.write(`data: ${JSON.stringify({ text })}\n\n`);
                            if (json.done) res.write('data: [DONE]\n\n');
                        } catch {}
                    });
                });
                ollamaRes.on('end', () => res.end());
            });

            ollamaReq.on('error', err => {
                res.write(`data: ${JSON.stringify({ error: 'Ollama error: ' + err.message })}\n\n`);
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

server.listen(PORT, '0.0.0.0', () => {
    console.log(`\n🤖 AI-CICADA Web Chat`);
    console.log(`📡 Model : ${MODEL}`);
    console.log(`🌐 Open  : http://localhost:${PORT}`);
    console.log(`\nPress Ctrl+C to stop\n`);
});
SERVEREOF

    # ── index.html ──
    cat > "$CHAT_DIR/index.html" << 'HTMLEOF'
<!DOCTYPE html>
<html lang="ru">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
<title>AI-CICADA — Локальный ИИ</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link href="https://fonts.googleapis.com/css2?family=Unbounded:wght@400;700;900&family=IBM+Plex+Mono:wght@400;500&display=swap" rel="stylesheet">
<style>
/* ══════════════════════════════════════
   ПЕРЕМЕННЫЕ И СБРОС
══════════════════════════════════════ */
*, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }

:root {
  --bg:        #070708;
  --bg2:       #0e0e10;
  --bg3:       #161618;
  --border:    rgba(255,255,255,0.06);
  --border2:   rgba(255,255,255,0.12);
  --accent:    #c8ff00;
  --accent2:   #00e5ff;
  --accent3:   #ff3cac;
  --text:      #f0f0f0;
  --text2:     #888;
  --text3:     #555;
  --user-bg:   #1a1f0a;
  --ai-bg:     #0a0f1a;
  --r:         16px;
  --r2:        24px;
  --font-head: 'Unbounded', sans-serif;
  --font-mono: 'IBM Plex Mono', monospace;
  --glow:      0 0 30px rgba(200,255,0,0.15);
  --glow2:     0 0 30px rgba(0,229,255,0.15);
}

html, body {
  height: 100%;
  background: var(--bg);
  color: var(--text);
  font-family: var(--font-mono);
  font-size: 14px;
  overflow: hidden;
}

/* ══════════════════════════════════════
   ФОН — сетка + свечение
══════════════════════════════════════ */
body::before {
  content: '';
  position: fixed; inset: 0; z-index: 0;
  background-image:
    linear-gradient(rgba(200,255,0,0.025) 1px, transparent 1px),
    linear-gradient(90deg, rgba(200,255,0,0.025) 1px, transparent 1px);
  background-size: 40px 40px;
  pointer-events: none;
}
body::after {
  content: '';
  position: fixed;
  width: 600px; height: 600px;
  border-radius: 50%;
  background: radial-gradient(circle, rgba(200,255,0,0.06) 0%, transparent 70%);
  top: -200px; right: -200px;
  pointer-events: none; z-index: 0;
}

/* ══════════════════════════════════════
   СТРАНИЦЫ
══════════════════════════════════════ */
.page {
  position: fixed; inset: 0; z-index: 10;
  display: flex; align-items: center; justify-content: center;
  padding: 20px;
  transition: opacity .3s, transform .3s;
}
.page.hidden { opacity: 0; pointer-events: none; transform: translateY(10px); }

/* ══════════════════════════════════════
   КАРТОЧКА (логин / регистрация)
══════════════════════════════════════ */
.card {
  width: 100%; max-width: 420px;
  background: var(--bg2);
  border: 1px solid var(--border2);
  border-radius: var(--r2);
  padding: 36px 28px;
  box-shadow: 0 40px 80px rgba(0,0,0,0.6), var(--glow);
  position: relative; overflow: hidden;
}
.card::before {
  content: '';
  position: absolute; top: 0; left: 0; right: 0; height: 2px;
  background: linear-gradient(90deg, var(--accent3), var(--accent), var(--accent2));
}

.card-logo {
  display: flex; align-items: center; gap: 12px;
  margin-bottom: 28px;
}
.card-logo-icon {
  width: 44px; height: 44px; border-radius: 12px;
  background: linear-gradient(135deg, var(--accent), var(--accent2));
  display: flex; align-items: center; justify-content: center;
  font-size: 20px; flex-shrink: 0;
  box-shadow: var(--glow);
}
.card-logo-text { line-height: 1.2; }
.card-logo-name {
  font-family: var(--font-head);
  font-size: 15px; font-weight: 900;
  color: var(--accent);
  letter-spacing: 2px;
}
.card-logo-sub { font-size: 11px; color: var(--text2); margin-top: 2px; }

.card h2 {
  font-family: var(--font-head);
  font-size: 20px; font-weight: 700;
  margin-bottom: 6px;
  letter-spacing: 1px;
}
.card p { color: var(--text2); font-size: 13px; margin-bottom: 24px; line-height: 1.5; }

/* Поля ввода */
.field { margin-bottom: 14px; }
.field label {
  display: block; font-size: 11px;
  color: var(--text2); letter-spacing: 1px;
  text-transform: uppercase; margin-bottom: 6px;
}
.field input {
  width: 100%;
  background: var(--bg3);
  border: 1px solid var(--border2);
  border-radius: var(--r);
  color: var(--text);
  font-family: var(--font-mono);
  font-size: 14px;
  padding: 12px 14px;
  outline: none;
  transition: border-color .2s, box-shadow .2s;
}
.field input:focus {
  border-color: var(--accent);
  box-shadow: 0 0 0 3px rgba(200,255,0,0.1);
}
.field input::placeholder { color: var(--text3); }

/* Кнопки */
.btn {
  width: 100%; padding: 14px;
  border: none; border-radius: var(--r);
  font-family: var(--font-head);
  font-size: 13px; font-weight: 700;
  letter-spacing: 1px; cursor: pointer;
  transition: all .2s;
  margin-top: 4px;
}
.btn-primary {
  background: linear-gradient(135deg, var(--accent), #aadd00);
  color: #000;
  box-shadow: 0 4px 20px rgba(200,255,0,0.3);
}
.btn-primary:hover { transform: translateY(-1px); box-shadow: 0 8px 30px rgba(200,255,0,0.4); }
.btn-primary:active { transform: translateY(0); }
.btn-ghost {
  background: transparent;
  border: 1px solid var(--border2);
  color: var(--text2);
  margin-top: 10px;
}
.btn-ghost:hover { border-color: var(--accent2); color: var(--accent2); }

.switch-link {
  text-align: center; margin-top: 20px;
  font-size: 13px; color: var(--text2);
}
.switch-link a { color: var(--accent); text-decoration: none; cursor: pointer; }
.switch-link a:hover { text-decoration: underline; }

.error-msg {
  background: rgba(255,60,172,0.1);
  border: 1px solid rgba(255,60,172,0.3);
  border-radius: 8px;
  color: var(--accent3);
  padding: 10px 12px;
  font-size: 12px;
  margin-bottom: 14px;
  display: none;
}
.error-msg.show { display: block; }

/* ══════════════════════════════════════
   ГЛАВНЫЙ ЧАТ
══════════════════════════════════════ */
#chatPage {
  flex-direction: column;
  padding: 0; align-items: stretch; justify-content: flex-st
