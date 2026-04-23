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

# ===== SAFE READ (Kali NetHunter / no /dev/tty compat) =====
safe_read() {
    local __var="$1"
    local __val
    read -r __val </dev/tty 2>/dev/null || read -r __val
    eval "$__var=\$__val"
}

# ===== PRESS ANY KEY =====
press_any_key() {
    center_text "${YELLOW}Press any key to continue...${NC}"
    read -r -n 1 -s </dev/tty 2>/dev/null || read -r || true
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
    safe_read choice

    case $choice in
        1) MODEL="qwen2.5-coder:3b" ;;
        2) MODEL="llama3:8b" ;;
        3) MODEL="mistral:7b" ;;
        4) MODEL="phi3:mini" ;;
        5)
            printf "${YELLOW}Enter model name: ${NC}"
            safe_read MODEL
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

# ===== BACKEND MENU =====
select_backend() {
    clear
    center_text "${CYAN}Select Backend:${NC}"
    echo

    draw_box \
        "1) Local Ollama (offline)" \
        "2) Groq API (fast, free, online)"

    echo
    printf "${YELLOW}Choice: ${NC}"
    safe_read bchoice

    case $bchoice in
        1)
            BACKEND="ollama"
            GROQ_API_KEY=""
            ;;
        2)
            BACKEND="groq"
            echo
            printf "${YELLOW}Paste your Groq API key: ${NC}"
            safe_read GROQ_API_KEY
            if [ -z "$GROQ_API_KEY" ]; then
                echo -e "${RED}API key cannot be empty${NC}"
                sleep 2
                select_backend
                return
            fi
            echo
            center_text "${CYAN}Select Groq model:${NC}"
            echo
            draw_box \
                "1) llama-3.3-70b-versatile (recommended)" \
                "2) llama3-8b-8192 (faster)" \
                "3) mixtral-8x7b-32768"
            echo
            printf "${YELLOW}Choice: ${NC}"
            safe_read gchoice
            case $gchoice in
                1) MODEL="llama-3.3-70b-versatile" ;;
                2) MODEL="llama3-8b-8192" ;;
                3) MODEL="mixtral-8x7b-32768" ;;
                *) MODEL="llama-3.3-70b-versatile" ;;
            esac
            ;;
        *)
            echo -e "${RED}Invalid choice${NC}"
            sleep 2
            select_backend
            return
            ;;
    esac

    log "Selected backend: $BACKEND, model: $MODEL"
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
const http  = require('http');
const https = require('https');
const fs    = require('fs');
const path  = require('path');

const PORT        = 3000;
const MODEL       = process.env.AI_MODEL        || 'qwen2.5-coder:3b';
const OPENAI_KEY  = process.env.OPENAI_API_KEY  || process.env.GROQ_API_KEY || '';
const OPENAI_BASE = process.env.OPENAI_BASE_URL || 'http://localhost:11434';

const isGroq   = OPENAI_BASE.includes('groq.com');
const isOpenAI = OPENAI_BASE.includes('openai.com') || isGroq;

console.log(`\n🤖 AI-CICADA Web Chat`);
console.log(`📡 Model   : ${MODEL}`);
console.log(`🔌 Backend : ${isGroq ? 'Groq' : isOpenAI ? 'OpenAI-compatible' : 'Ollama'}`);
console.log(`🌐 Open    : http://localhost:${PORT}`);
console.log(`\nPress Ctrl+C to stop\n`);

function chatRequest(messages, onChunk, onDone, onError) {
    if (isOpenAI) {
        const payload = JSON.stringify({ model: MODEL, messages, stream: true });
        const url = new URL(OPENAI_BASE + '/chat/completions');
        const isHttps = url.protocol === 'https:';
        const lib = isHttps ? https : http;

        const options = {
            hostname: url.hostname,
            port: url.port || (isHttps ? 443 : 80),
            path: url.pathname,
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'Content-Length': Buffer.byteLength(payload),
                'Authorization': `Bearer ${OPENAI_KEY}`
            }
        };

        const req = lib.request(options, res => {
            let buffer = '';
            res.on('data', chunk => {
                buffer += chunk.toString();
                const lines = buffer.split('\n');
                buffer = lines.pop();
                lines.forEach(line => {
                    line = line.trim();
                    if (!line) return;
                    if (line === 'data: [DONE]') { onDone(); return; }
                    if (line.startsWith('data: ')) {
                        try {
                            const json = JSON.parse(line.slice(6));
                            const text = json?.choices?.[0]?.delta?.content || '';
                            if (text) onChunk(text);
                            if (json?.choices?.[0]?.finish_reason === 'stop') onDone();
                        } catch {}
                    }
                });
            });
            res.on('end', () => onDone());
        });

        req.on('error', onError);
        req.write(payload);
        req.end();

    } else {
        const payload = JSON.stringify({ model: MODEL, messages, stream: true });
        const options = {
            hostname: 'localhost',
            port: 11434,
            path: '/api/chat',
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'Content-Length': Buffer.byteLength(payload)
            }
        };

        const req = http.request(options, res => {
            res.on('data', chunk => {
                const lines = chunk.toString().split('\n').filter(Boolean);
                lines.forEach(line => {
                    try {
                        const json = JSON.parse(line);
                        const text = json?.message?.content || '';
                        if (text) onChunk(text);
                        if (json.done) onDone();
                    } catch {}
                });
            });
            res.on('end', () => onDone());
        });

        req.on('error', onError);
        req.write(payload);
        req.end();
    }
}

const server = http.createServer((req, res) => {
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader('Access-Control-Allow-Methods', 'GET,POST,OPTIONS');
    res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
    if (req.method === 'OPTIONS') { res.writeHead(204); res.end(); return; }

    if (req.method === 'GET' && (req.url === '/' || req.url === '/index.html')) {
        const html = fs.readFileSync(path.join(__dirname, 'index.html'));
        res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
        res.end(html);
        return;
    }

    if (req.method === 'GET' && req.url === '/model') {
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ model: MODEL }));
        return;
    }

    if (req.method === 'POST' && req.url === '/chat') {
        let body = '';
        req.on('data', chunk => body += chunk);
        req.on('end', () => {
            let messages;
            try { messages = JSON.parse(body).messages; }
            catch { res.writeHead(400); res.end('Bad JSON'); return; }

            res.writeHead(200, {
                'Content-Type': 'text/event-stream',
                'Cache-Control': 'no-cache',
                'Connection': 'keep-alive'
            });

            let done = false;
            chatRequest(
                messages,
                (text) => { res.write(`data: ${JSON.stringify({ text })}\n\n`); },
                () => { if (!done) { done = true; res.write('data: [DONE]\n\n'); res.end(); } },
                (err) => { res.write(`data: ${JSON.stringify({ error: err.message })}\n\n`); res.end(); }
            );
        });
        return;
    }

    res.writeHead(404);
    res.end('Not found');
});

server.listen(PORT, '0.0.0.0', () => {});
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
  padding: 0; align-items: stretch; justify-content: flex-start;
}

/* Сайдбар + основная область */
.app-layout {
  display: flex; height: 100dvh; width: 100%;
}

/* ── Сайдбар ── */
.sidebar {
  width: 260px; flex-shrink: 0;
  background: var(--bg2);
  border-right: 1px solid var(--border);
  display: flex; flex-direction: column;
  transition: transform .3s;
  z-index: 100;
}
.sidebar-header {
  padding: 16px;
  border-bottom: 1px solid var(--border);
  display: flex; align-items: center; gap: 10px;
  flex-shrink: 0;
}
.sidebar-logo-icon {
  width: 34px; height: 34px; border-radius: 9px;
  background: linear-gradient(135deg, var(--accent), var(--accent2));
  display: flex; align-items: center; justify-content: center;
  font-size: 16px; flex-shrink: 0;
}
.sidebar-logo-name {
  font-family: var(--font-head);
  font-size: 12px; font-weight: 900;
  color: var(--accent); letter-spacing: 2px;
}
.sidebar-logo-sub { font-size: 10px; color: var(--text2); }

.btn-new-chat {
  margin: 12px;
  padding: 10px 14px;
  background: rgba(200,255,0,0.08);
  border: 1px solid rgba(200,255,0,0.2);
  border-radius: 10px;
  color: var(--accent);
  font-family: var(--font-head);
  font-size: 11px; font-weight: 700;
  letter-spacing: 1px; cursor: pointer;
  display: flex; align-items: center; gap: 8px;
  transition: all .2s;
  flex-shrink: 0;
}
.btn-new-chat:hover { background: rgba(200,255,0,0.15); }

.sidebar-section-title {
  padding: 8px 16px 4px;
  font-size: 10px; color: var(--text3);
  text-transform: uppercase; letter-spacing: 1.5px;
  flex-shrink: 0;
}

.history-list {
  flex: 1; overflow-y: auto; padding: 4px 8px;
}
.history-list::-webkit-scrollbar { width: 3px; }
.history-list::-webkit-scrollbar-thumb { background: var(--border2); border-radius: 2px; }

.history-item {
  padding: 9px 10px;
  border-radius: 8px;
  cursor: pointer;
  display: flex; align-items: center; gap: 8px;
  transition: background .15s;
  margin-bottom: 2px;
}
.history-item:hover { background: var(--bg3); }
.history-item.active { background: rgba(200,255,0,0.08); }
.history-item-icon { font-size: 13px; flex-shrink: 0; opacity: .6; }
.history-item-text {
  font-size: 12px; color: var(--text2);
  overflow: hidden; text-overflow: ellipsis; white-space: nowrap;
  flex: 1;
}
.history-item.active .history-item-text { color: var(--accent); }
.history-item-del {
  font-size: 11px; color: var(--text3);
  opacity: 0; cursor: pointer; flex-shrink: 0;
  padding: 2px 4px; border-radius: 4px;
  transition: opacity .15s, color .15s;
}
.history-item:hover .history-item-del { opacity: 1; }
.history-item-del:hover { color: var(--accent3) !important; opacity: 1 !important; }

.history-empty {
  padding: 20px 16px;
  text-align: center;
  color: var(--text3); font-size: 12px; line-height: 1.6;
}

/* Профиль в низу сайдбара */
.sidebar-profile {
  padding: 12px 16px;
  border-top: 1px solid var(--border);
  display: flex; align-items: center; gap: 10px;
  flex-shrink: 0;
}
.profile-avatar {
  width: 32px; height: 32px; border-radius: 50%;
  background: linear-gradient(135deg, var(--accent3), var(--accent));
  display: flex; align-items: center; justify-content: center;
  font-size: 14px; flex-shrink: 0; color: #000; font-weight: 700;
  font-family: var(--font-head);
}
.profile-info { flex: 1; min-width: 0; }
.profile-name { font-size: 12px; font-weight: 500; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.profile-role { font-size: 10px; color: var(--text2); }
.btn-logout {
  background: none; border: none;
  color: var(--text3); font-size: 16px; cursor: pointer;
  padding: 4px; border-radius: 6px;
  transition: color .2s;
  flex-shrink: 0;
}
.btn-logout:hover { color: var(--accent3); }

/* ── Основная область ── */
.chat-area {
  flex: 1; display: flex; flex-direction: column;
  min-width: 0; position: relative;
}

/* Топбар */
.topbar {
  display: flex; align-items: center; gap: 10px;
  padding: 10px 16px;
  border-bottom: 1px solid var(--border);
  background: var(--bg2);
  flex-shrink: 0;
}
.btn-menu {
  display: none;
  background: none; border: none;
  color: var(--text2); font-size: 20px; cursor: pointer;
  padding: 4px; flex-shrink: 0;
}
.topbar-title {
  flex: 1; font-family: var(--font-head);
  font-size: 13px; font-weight: 700;
  color: var(--text); letter-spacing: 1px;
  overflow: hidden; text-overflow: ellipsis; white-space: nowrap;
}
.model-badge {
  background: var(--bg3);
  border: 1px solid var(--border2);
  border-radius: 20px;
  padding: 4px 10px;
  font-size: 11px; color: var(--accent2);
  white-space: nowrap; flex-shrink: 0;
}
.status-indicator {
  width: 8px; height: 8px; border-radius: 50%;
  background: var(--text3); flex-shrink: 0;
  transition: background .3s;
}
.status-indicator.online  { background: var(--accent); box-shadow: 0 0 8px var(--accent); }
.status-indicator.loading { background: var(--accent2); animation: blink 1s infinite; }
@keyframes blink { 0%,100%{opacity:1} 50%{opacity:.2} }

/* Сообщения */
#messages {
  flex: 1; overflow-y: auto;
  padding: 20px 16px;
  display: flex; flex-direction: column; gap: 16px;
  scroll-behavior: smooth;
}
#messages::-webkit-scrollbar { width: 4px; }
#messages::-webkit-scrollbar-thumb { background: var(--border); border-radius: 2px; }

/* Приветствие */
.welcome {
  flex: 1; display: flex; flex-direction: column;
  align-items: center; justify-content: center;
  text-align: center; padding: 40px 20px;
  gap: 14px;
}
.welcome-cicada {
  font-size: 56px;
  filter: drop-shadow(0 0 20px rgba(200,255,0,0.4));
  animation: float 3s ease-in-out infinite;
}
@keyframes float { 0%,100%{transform:translateY(0)} 50%{transform:translateY(-8px)} }

.welcome h1 {
  font-family: var(--font-head);
  font-size: 22px; font-weight: 900;
  background: linear-gradient(135deg, var(--accent), var(--accent2));
  -webkit-background-clip: text; -webkit-text-fill-color: transparent;
  letter-spacing: 2px;
}
.welcome p { color: var(--text2); font-size: 13px; line-height: 1.7; max-width: 300px; }

.welcome-chips {
  display: flex; flex-wrap: wrap; gap: 8px;
  justify-content: center; margin-top: 8px;
}
.chip {
  background: var(--bg3);
  border: 1px solid var(--border2);
  border-radius: 20px;
  padding: 7px 14px;
  font-size: 12px; color: var(--text2);
  cursor: pointer; transition: all .2s;
}
.chip:hover { border-color: var(--accent); color: var(--accent); background: rgba(200,255,0,0.05); }

/* Пузыри */
.msg { display: flex; gap: 10px; animation: msgIn .2s ease; }
@keyframes msgIn { from{opacity:0;transform:translateY(8px)} to{opacity:1;transform:none} }

.msg.user  { flex-direction: row-reverse; }

.avatar {
  width: 30px; height: 30px; border-radius: 9px;
  flex-shrink: 0; margin-top: 2px;
  display: flex; align-items: center; justify-content: center;
  font-size: 14px; font-weight: 700;
  font-family: var(--font-head);
}
.msg.user .avatar {
  background: linear-gradient(135deg, var(--accent3), var(--accent));
  color: #000; font-size: 12px;
}
.msg.ai .avatar {
  background: linear-gradient(135deg, #0a1a3a, #0a1a2a);
  border: 1px solid rgba(0,229,255,0.3);
  font-size: 15px;
}

.bubble {
  max-width: min(80%, 520px);
  padding: 11px 15px;
  border-radius: var(--r);
  line-height: 1.65; word-break: break-word;
  font-size: 13.5px;
}
.msg.user .bubble {
  background: var(--user-bg);
  border: 1px solid rgba(200,255,0,0.15);
  border-bottom-right-radius: 4px;
  color: #d8ffaa;
}
.msg.ai .bubble {
  background: var(--ai-bg);
  border: 1px solid rgba(0,229,255,0.1);
  border-bottom-left-radius: 4px;
}

/* Код */
.bubble code {
  background: rgba(0,229,255,0.08);
  border: 1px solid rgba(0,229,255,0.15);
  border-radius: 4px; padding: 2px 5px;
  font-size: 12px; color: var(--accent2);
}
.bubble pre {
  background: #05080f;
  border: 1px solid rgba(0,229,255,0.12);
  border-radius: 10px; padding: 12px 14px;
  overflow-x: auto; margin: 8px 0;
  font-size: 12px; line-height: 1.5; position: relative;
}
.bubble pre code { background: none; border: none; padding: 0; color: #8ecfff; }
.copy-btn {
  position: absolute; top: 8px; right: 8px;
  background: var(--bg3); border: 1px solid var(--border2);
  border-radius: 5px; padding: 3px 8px;
  font-size: 10px; color: var(--text2); cursor: pointer;
  font-family: var(--font-mono);
  transition: all .15s;
}
.copy-btn:hover { color: var(--accent); border-color: var(--accent); }

/* Typing */
.typing-wrap { display: flex; gap: 10px; }
.typing-bubble {
  background: var(--ai-bg);
  border: 1px solid rgba(0,229,255,0.1);
  border-radius: var(--r); border-bottom-left-radius: 4px;
  padding: 14px 16px; display: flex; gap: 5px; align-items: center;
}
.typing-bubble span {
  width: 6px; height: 6px; border-radius: 50%;
  background: var(--accent2); opacity: .3;
  animation: typingDot .9s infinite;
}
.typing-bubble span:nth-child(2) { animation-delay: .2s; }
.typing-bubble span:nth-child(3) { animation-delay: .4s; }
@keyframes typingDot { 0%,100%{opacity:.3;transform:scale(1)} 50%{opacity:1;transform:scale(1.3)} }

/* Дата-разделитель */
.date-divider {
  display: flex; align-items: center; gap: 10px;
  color: var(--text3); font-size: 11px; letter-spacing: 1px;
}
.date-divider::before, .date-divider::after {
  content: ''; flex: 1; height: 1px; background: var(--border);
}

/* ── Поле ввода ── */
.input-wrap {
  padding: 12px 16px;
  border-top: 1px solid var(--border);
  background: var(--bg2); flex-shrink: 0;
}
.input-row {
  display: flex; gap: 8px; align-items: flex-end;
  background: var(--bg3);
  border: 1px solid var(--border2);
  border-radius: var(--r2);
  padding: 8px 8px 8px 16px;
  transition: border-color .2s, box-shadow .2s;
}
.input-row:focus-within {
  border-color: rgba(200,255,0,0.4);
  box-shadow: 0 0 0 3px rgba(200,255,0,0.06);
}
#input {
  flex: 1; background: none; border: none; outline: none;
  color: var(--text); font-family: var(--font-mono);
  font-size: 14px; line-height: 1.5;
  resize: none; max-height: 120px; overflow-y: auto;
  padding: 4px 0;
}
#input::placeholder { color: var(--text3); }
#sendBtn {
  width: 38px; height: 38px; border-radius: 12px;
  background: linear-gradient(135deg, var(--accent), #aadd00);
  border: none; color: #000; font-size: 16px;
  cursor: pointer; flex-shrink: 0;
  display: flex; align-items: center; justify-content: center;
  transition: all .2s; box-shadow: 0 2px 12px rgba(200,255,0,0.3);
}
#sendBtn:hover   { transform: scale(1.05); box-shadow: 0 4px 20px rgba(200,255,0,0.4); }
#sendBtn:active  { transform: scale(.95); }
#sendBtn:disabled { opacity: .3; cursor: not-allowed; transform: none; box-shadow: none; }

.input-hint {
  text-align: center; font-size: 10px; color: var(--text3);
  margin-top: 6px; letter-spacing: .5px;
}

/* ══════════════════════════════════════
   ОВЕРЛЕЙ САЙДБАРА НА МОБИЛЕ
══════════════════════════════════════ */
.sidebar-overlay {
  display: none; position: fixed; inset: 0;
  background: rgba(0,0,0,.6); z-index: 99;
}

/* ══════════════════════════════════════
   ЛИЧНЫЙ КАБИНЕТ
══════════════════════════════════════ */
#profilePage {
  background: var(--bg);
}
.profile-page-inner {
  width: 100%; max-width: 480px;
  background: var(--bg2);
  border: 1px solid var(--border2);
  border-radius: var(--r2);
  overflow: hidden;
  box-shadow: 0 40px 80px rgba(0,0,0,.6), var(--glow);
}
.profile-hero {
  padding: 32px 28px 24px;
  background: linear-gradient(135deg, #0a1a0a, #0a0a1a);
  border-bottom: 1px solid var(--border);
  display: flex; align-items: center; gap: 18px;
  position: relative;
}
.profile-hero::before {
  content: ''; position: absolute; top: 0; left: 0; right: 0; height: 2px;
  background: linear-gradient(90deg, var(--accent3), var(--accent), var(--accent2));
}
.profile-hero-avatar {
  width: 64px; height: 64px; border-radius: 50%;
  background: linear-gradient(135deg, var(--accent3), var(--accent));
  display: flex; align-items: center; justify-content: center;
  font-size: 26px; font-weight: 900; color: #000;
  font-family: var(--font-head); flex-shrink: 0;
  box-shadow: 0 0 0 3px rgba(200,255,0,0.2), var(--glow);
}
.profile-hero-info h2 {
  font-family: var(--font-head);
  font-size: 18px; font-weight: 700; margin-bottom: 4px;
}
.profile-hero-info p { font-size: 12px; color: var(--text2); }
.profile-hero-badge {
  margin-top: 8px; display: inline-block;
  background: rgba(200,255,0,0.1);
  border: 1px solid rgba(200,255,0,0.3);
  border-radius: 20px; padding: 3px 10px;
  font-size: 10px; color: var(--accent); letter-spacing: 1px;
}

.profile-stats {
  display: grid; grid-template-columns: repeat(3,1fr);
  border-bottom: 1px solid var(--border);
}
.stat-item {
  padding: 16px; text-align: center;
  border-right: 1px solid var(--border);
}
.stat-item:last-child { border-right: none; }
.stat-value {
  font-family: var(--font-head);
  font-size: 22px; font-weight: 900;
  color: var(--accent); line-height: 1;
}
.stat-label { font-size: 10px; color: var(--text2); margin-top: 4px; letter-spacing: 1px; }

.profile-section { padding: 20px 24px; border-bottom: 1px solid var(--border); }
.profile-section:last-child { border-bottom: none; }
.profile-section h3 {
  font-family: var(--font-head);
  font-size: 11px; font-weight: 700;
  color: var(--text2); letter-spacing: 2px;
  text-transform: uppercase; margin-bottom: 14px;
}

.info-row {
  display: flex; align-items: center; gap: 10px;
  padding: 10px 0; border-bottom: 1px solid var(--border);
}
.info-row:last-child { border-bottom: none; }
.info-row-icon { font-size: 16px; width: 24px; text-align: center; flex-shrink: 0; }
.info-row-content { flex: 1; }
.info-row-label { font-size: 10px; color: var(--text3); letter-spacing: 1px; margin-bottom: 2px; }
.info-row-value { font-size: 13px; }

.btn-back {
  margin: 20px 24px;
  padding: 12px;
  background: transparent;
  border: 1px solid var(--border2);
  border-radius: var(--r);
  color: var(--text2);
  font-family: var(--font-head);
  font-size: 11px; font-weight: 700;
  letter-spacing: 1px; cursor: pointer;
  display: flex; align-items: center; justify-content: center; gap: 8px;
  transition: all .2s; width: calc(100% - 48px);
}
.btn-back:hover { border-color: var(--accent2); color: var(--accent2); }

/* ══════════════════════════════════════
   МОБИЛЬНАЯ АДАПТАЦИЯ
══════════════════════════════════════ */
@media (max-width: 600px) {
  .sidebar {
    position: fixed; left: 0; top: 0; bottom: 0;
    transform: translateX(-100%);
  }
  .sidebar.open { transform: translateX(0); }
  .sidebar-overlay.show { display: block; }
  .btn-menu { display: flex; }
  .bubble { max-width: 90%; }
}
</style>
</head>
<body>

<!-- ══════════════════════════════════════
     СТРАНИЦА ВХОДА
══════════════════════════════════════ -->
<div class="page" id="loginPage">
  <div class="card">
    <div class="card-logo">
      <div class="card-logo-icon">🦟</div>
      <div class="card-logo-text">
        <div class="card-logo-name">AI-CICADA</div>
        <div class="card-logo-sub">Локальный ИИ-ассистент</div>
      </div>
    </div>
    <h2>Добро пожаловать</h2>
    <p>Войдите в аккаунт чтобы начать работу с ИИ</p>
    <div class="error-msg" id="loginError"></div>
    <div class="field">
      <label>Имя пользователя</label>
      <input type="text" id="loginUser" placeholder="введите логин" autocomplete="off">
    </div>
    <div class="field">
      <label>Пароль</label>
      <input type="password" id="loginPass" placeholder="введите пароль">
    </div>
    <button class="btn btn-primary" onclick="login()">ВОЙТИ →</button>
    <button class="btn btn-ghost" onclick="showPage('registerPage')">Создать аккаунт</button>
    <div class="switch-link">
      Нет аккаунта? <a onclick="showPage('registerPage')">Зарегистрироваться</a>
    </div>
  </div>
</div>

<!-- ══════════════════════════════════════
     СТРАНИЦА РЕГИСТРАЦИИ
══════════════════════════════════════ -->
<div class="page hidden" id="registerPage">
  <div class="card">
    <div class="card-logo">
      <div class="card-logo-icon">🦟</div>
      <div class="card-logo-text">
        <div class="card-logo-name">AI-CICADA</div>
        <div class="card-logo-sub">Создание аккаунта</div>
      </div>
    </div>
    <h2>Регистрация</h2>
    <p>Создайте аккаунт для сохранения истории чатов</p>
    <div class="error-msg" id="regError"></div>
    <div class="field">
      <label>Имя пользователя</label>
      <input type="text" id="regUser" placeholder="минимум 3 символа" autocomplete="off">
    </div>
    <div class="field">
      <label>Пароль</label>
      <input type="password" id="regPass" placeholder="минимум 4 символа">
    </div>
    <div class="field">
      <label>Подтвердите пароль</label>
      <input type="password" id="regPass2" placeholder="повторите пароль">
    </div>
    <button class="btn btn-primary" onclick="register()">СОЗДАТЬ АККАУНТ →</button>
    <div class="switch-link">
      Уже есть аккаунт? <a onclick="showPage('loginPage')">Войти</a>
    </div>
  </div>
</div>

<!-- ══════════════════════════════════════
     ГЛАВНЫЙ ЧАТ
══════════════════════════════════════ -->
<div class="page hidden" id="chatPage">
  <div class="app-layout">

    <!-- Оверлей -->
    <div class="sidebar-overlay" id="sidebarOverlay" onclick="closeSidebar()"></div>

    <!-- Сайдбар -->
    <div class="sidebar" id="sidebar">
      <div class="sidebar-header">
        <div class="sidebar-logo-icon">🦟</div>
        <div>
          <div class="sidebar-logo-name">AI-CICADA</div>
          <div class="sidebar-logo-sub">Локальный ИИ</div>
        </div>
      </div>

      <button class="btn-new-chat" onclick="newChat()">
        <span>＋</span> Новый чат
      </button>

      <div class="sidebar-section-title">История чатов</div>
      <div class="history-list" id="historyList">
        <div class="history-empty">Нет сохранённых чатов.<br>Начните новый диалог!</div>
      </div>

      <div class="sidebar-profile">
        <div class="profile-avatar" id="sidebarAvatar">А</div>
        <div class="profile-info">
          <div class="profile-name" id="sidebarName">Аноним</div>
          <div class="profile-role">Пользователь</div>
        </div>
        <button class="btn-logout" title="Выйти" onclick="showPage('profilePage'); renderProfile()">⚙</button>
        <button class="btn-logout" title="Выйти" onclick="logout()">⏻</button>
      </div>
    </div>

    <!-- Область чата -->
    <div class="chat-area">
      <div class="topbar">
        <button class="btn-menu" onclick="openSidebar()">☰</button>
        <div class="topbar-title" id="chatTitle">AI-CICADA</div>
        <div class="model-badge" id="modelBadge">—</div>
        <div class="status-indicator" id="statusDot"></div>
      </div>

      <div id="messages">
        <div class="welcome" id="welcomeBlock">
          <div class="welcome-cicada">🦟</div>
          <h1>AI-CICADA</h1>
          <p>Локальный ИИ работает прямо на вашем устройстве. Спрашивайте всё — код, задачи, вопросы.</p>
          <div class="welcome-chips">
            <div class="chip" onclick="useChip(this)">Напиши скрипт на Python</div>
            <div class="chip" onclick="useChip(this)">Объясни как работает</div>
            <div class="chip" onclick="useChip(this)">Найди ошибку в коде</div>
            <div class="chip" onclick="useChip(this)">Помоги с задачей</div>
          </div>
        </div>
      </div>

      <div class="input-wrap">
        <div class="input-row">
          <textarea id="input" rows="1" placeholder="Напишите сообщение..."></textarea>
          <button id="sendBtn" onclick="send()">➤</button>
        </div>
        <div class="input-hint">Enter — отправить &nbsp;·&nbsp; Shift+Enter — новая строка</div>
      </div>
    </div>
  </div>
</div>

<!-- ══════════════════════════════════════
     ЛИЧНЫЙ КАБИНЕТ
══════════════════════════════════════ -->
<div class="page hidden" id="profilePage">
  <div class="profile-page-inner">
    <div class="profile-hero">
      <div class="profile-hero-avatar" id="profileAvatar">А</div>
      <div class="profile-hero-info">
        <h2 id="profileName">Пользователь</h2>
        <p id="profileSub">Локальный аккаунт</p>
        <div class="profile-hero-badge">ACTIVE</div>
      </div>
    </div>

    <div class="profile-stats">
      <div class="stat-item">
        <div class="stat-value" id="statChats">0</div>
        <div class="stat-label">Чатов</div>
      </div>
      <div class="stat-item">
        <div class="stat-value" id="statMsgs">0</div>
        <div class="stat-label">Сообщений</div>
      </div>
      <div class="stat-item">
        <div class="stat-value" id="statDays">0</div>
        <div class="stat-label">Дней</div>
      </div>
    </div>

    <div class="profile-section">
      <h3>Информация</h3>
      <div class="info-row">
        <div class="info-row-icon">👤</div>
        <div class="info-row-content">
          <div class="info-row-label">ИМЯ ПОЛЬЗОВАТЕЛЯ</div>
          <div class="info-row-value" id="infoUser">—</div>
        </div>
      </div>
      <div class="info-row">
        <div class="info-row-icon">📅</div>
        <div class="info-row-content">
          <div class="info-row-label">ДАТА РЕГИСТРАЦИИ</div>
          <div class="info-row-value" id="infoDate">—</div>
        </div>
      </div>
      <div class="info-row">
        <div class="info-row-icon">🤖</div>
        <div class="info-row-content">
          <div class="info-row-label">ТЕКУЩАЯ МОДЕЛЬ</div>
          <div class="info-row-value" id="infoModel">—</div>
        </div>
      </div>
      <div class="info-row">
        <div class="info-row-icon">💾</div>
        <div class="info-row-content">
          <div class="info-row-label">ХРАНИЛИЩЕ</div>
          <div class="info-row-value">Локально на устройстве</div>
        </div>
      </div>
    </div>

    <div class="profile-section">
      <h3>Опасная зона</h3>
      <div class="info-row" style="cursor:pointer" onclick="clearAllHistory()">
        <div class="info-row-icon">🗑</div>
        <div class="info-row-content">
          <div class="info-row-label">ДЕЙСТВИЕ</div>
          <div class="info-row-value" style="color:var(--accent3)">Очистить всю историю чатов</div>
        </div>
      </div>
      <div class="info-row" style="cursor:pointer" onclick="deleteAccount()">
        <div class="info-row-icon">⚠️</div>
        <div class="info-row-content">
          <div class="info-row-label">ДЕЙСТВИЕ</div>
          <div class="info-row-value" style="color:var(--accent3)">Удалить аккаунт</div>
        </div>
      </div>
    </div>

    <button class="btn-back" onclick="showPage('chatPage')">← Вернуться к чату</button>
  </div>
</div>

<script>
/* ══════════════════════════════════════
   СОСТОЯНИЕ
══════════════════════════════════════ */
let currentUser = null;    // { username, password, createdAt, totalMsgs }
let currentModel = '';
let currentChatId = null;
let chatHistory   = [];    // [{role,content}] — текущий диалог
let generating    = false;

/* ══════════════════════════════════════
   ХРАНИЛИЩЕ (localStorage)
══════════════════════════════════════ */
const DB = {
  getUsers: () => JSON.parse(localStorage.getItem('ac_users') || '{}'),
  saveUsers: u => localStorage.setItem('ac_users', JSON.stringify(u)),
  getChats: usr => JSON.parse(localStorage.getItem(`ac_chats_${usr}`) || '[]'),
  saveChats: (usr, chats) => localStorage.setItem(`ac_chats_${usr}`, JSON.stringify(chats)),
  getSession: () => localStorage.getItem('ac_session'),
  saveSession: u => localStorage.setItem('ac_session', u),
  clearSession: () => localStorage.removeItem('ac_session'),
};

/* ══════════════════════════════════════
   СТРАНИЦЫ
══════════════════════════════════════ */
function showPage(id) {
  document.querySelectorAll('.page').forEach(p => p.classList.add('hidden'));
  document.getElementById(id).classList.remove('hidden');
}

/* ══════════════════════════════════════
   АВТОРИЗАЦИЯ
══════════════════════════════════════ */
function showError(id, msg) {
  const el = document.getElementById(id);
  el.textContent = msg; el.classList.add('show');
  setTimeout(() => el.classList.remove('show'), 3000);
}

function login() {
  const u = document.getElementById('loginUser').value.trim();
  const p = document.getElementById('loginPass').value;
  if (!u || !p) return showError('loginError', 'Заполните все поля');
  const users = DB.getUsers();
  if (!users[u]) return showError('loginError', 'Пользователь не найден');
  if (users[u].password !== btoa(p)) return showError('loginError', 'Неверный пароль');
  currentUser = { ...users[u], username: u };
  DB.saveSession(u);
  enterChat();
}

function register() {
  const u = document.getElementById('regUser').value.trim();
  const p = document.getElementById('regPass').value;
  const p2 = document.getElementById('regPass2').value;
  if (!u || !p || !p2) return showError('regError', 'Заполните все поля');
  if (u.length < 3) return showError('regError', 'Логин минимум 3 символа');
  if (p.length < 4) return showError('regError', 'Пароль минимум 4 символа');
  if (p !== p2) return showError('regError', 'Пароли не совпадают');
  const users = DB.getUsers();
  if (users[u]) return showError('regError', 'Логин уже занят');
  users[u] = { password: btoa(p), createdAt: Date.now(), totalMsgs: 0 };
  DB.saveUsers(users);
  currentUser = { ...users[u], username: u };
  DB.saveSession(u);
  enterChat();
}

function logout() {
  DB.clearSession(); currentUser = null;
  currentChatId = null; chatHistory = [];
  document.getElementById('loginUser').value = '';
  document.getElementById('loginPass').value = '';
  showPage('loginPage');
}

/* ══════════════════════════════════════
   ИНИЦИАЛИЗАЦИЯ ЧАТА
══════════════════════════════════════ */
function enterChat() {
  updateSidebarProfile();
  renderHistoryList();
  newChat();
  showPage('chatPage');
  // Загружаем модель
  fetch('/model').then(r => r.json()).then(d => {
    currentModel = d.model;
    document.getElementById('modelBadge').textContent = d.model;
    document.getElementById('statusDot').className = 'status-indicator online';
  }).catch(() => {
    document.getElementById('modelBadge').textContent = 'Офлайн';
  });
}

function updateSidebarProfile() {
  if (!currentUser) return;
  const first = currentUser.username[0].toUpperCase();
  document.getElementById('sidebarAvatar').textContent = first;
  document.getElementById('sidebarName').textContent   = currentUser.username;
}

/* ══════════════════════════════════════
   УПРАВЛЕНИЕ ЧАТАМИ
══════════════════════════════════════ */
function newChat() {
  currentChatId = 'chat_' + Date.now();
  chatHistory = [];
  resetMessages();
  document.getElementById('chatTitle').textContent = 'Новый чат';
  renderHistoryList();
}

function resetMessages() {
  const m = document.getElementById('messages');
  m.innerHTML = `
    <div class="welcome" id="welcomeBlock">
      <div class="welcome-cicada">🦟</div>
      <h1>AI-CICADA</h1>
      <p>Локальный ИИ работает прямо на вашем устройстве. Спрашивайте всё — код, задачи, вопросы.</p>
      <div class="welcome-chips">
        <div class="chip" onclick="useChip(this)">Напиши скрипт на Python</div>
        <div class="chip" onclick="useChip(this)">Объясни как работает</div>
        <div class="chip" onclick="useChip(this)">Найди ошибку в коде</div>
        <div class="chip" onclick="useChip(this)">Помоги с задачей</div>
      </div>
    </div>`;
}

function useChip(el) {
  document.getElementById('input').value = el.textContent;
  send();
}

/* Сохранение чата */
function saveCurrentChat(firstMsg) {
  if (!currentUser) return;
  const chats = DB.getChats(currentUser.username);
  const idx = chats.findIndex(c => c.id === currentChatId);
  const entry = {
    id: currentChatId,
    title: firstMsg.slice(0, 40) + (firstMsg.length > 40 ? '…' : ''),
    messages: chatHistory,
    updatedAt: Date.now()
  };
  if (idx >= 0) chats[idx] = entry;
  else chats.unshift(entry);
  DB.saveChats(currentUser.username, chats);
  renderHistoryList();
}

function loadChat(id) {
  const chats = DB.getChats(currentUser.username);
  const chat = chats.find(c => c.id === id);
  if (!chat) return;
  currentChatId = id;
  chatHistory = chat.messages;
  resetMessages();
  const wb = document.getElementById('welcomeBlock');
  if (wb) wb.remove();
  document.getElementById('chatTitle').textContent = chat.title;
  // Рендерим сообщения
  chat.messages.forEach(m => {
    addMsg(m.role, m.content);
  });
  renderHistoryList();
  closeSidebar();
}

function deleteChat(id, e) {
  e.stopPropagation();
  const chats = DB.getChats(currentUser.username).filter(c => c.id !== id);
  DB.saveChats(currentUser.username, chats);
  if (currentChatId === id) newChat();
  else renderHistoryList();
}

function renderHistoryList() {
  const list = document.getElementById('historyList');
  if (!currentUser) return;
  const chats = DB.getChats(currentUser.username);
  if (!chats.length) {
    list.innerHTML = '<div class="history-empty">Нет сохранённых чатов.<br>Начните новый диалог!</div>';
    return;
  }
  list.innerHTML = chats.map(c => `
    <div class="history-item ${c.id === currentChatId ? 'active' : ''}" onclick="loadChat('${c.id}')">
      <div class="history-item-icon">💬</div>
      <div class="history-item-text">${escHtml(c.title)}</div>
      <div class="history-item-del" onclick="deleteChat('${c.id}',event)">✕</div>
    </div>`).join('');
}

/* ══════════════════════════════════════
   ОТПРАВКА
══════════════════════════════════════ */
async function send() {
  const text = document.getElementById('input').value.trim();
  if (!text || generating) return;
  generating = true;
  document.getElementById('sendBtn').disabled = true;
  document.getElementById('input').value = '';
  document.getElementById('input').style.height = 'auto';

  const wb = document.getElementById('welcomeBlock');
  if (wb) wb.remove();

  addMsg('user', text);
  chatHistory.push({ role: 'user', content: text });

  // Обновляем заголовок при первом сообщении
  if (chatHistory.length === 1) {
    document.getElementById('chatTitle').textContent = text.slice(0, 30) + (text.length > 30 ? '…' : '');
    saveCurrentChat(text);
  }

  document.getElementById('statusDot').className = 'status-indicator loading';
  const typingEl = addTyping();

  let fullText = '';
  let aiBubble = null;

  try {
    const res = await fetch('/chat', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ messages: chatHistory })
    });

    const reader = res.body.getReader();
    const dec = new TextDecoder();

    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      const lines = dec.decode(value).split('\n').filter(l => l.startsWith('data: '));
      for (const line of lines) {
        const data = line.slice(6);
        if (data === '[DONE]') break;
        try {
          const json = JSON.parse(data);
          if (json.error) throw new Error(json.error);
          if (json.text) {
            fullText += json.text;
            if (!aiBubble) {
              typingEl.remove();
              const msgEl = addMsg('ai', '');
              aiBubble = msgEl;
            }
            const bubble = aiBubble.querySelector('.bubble');
            bubble.innerHTML = '';
            bubble.appendChild(renderMd(fullText));
            document.getElementById('messages').scrollTop = 999999;
          }
        } catch {}
      }
    }
  } catch(err) {
    typingEl.remove();
    addMsg('ai', '❌ Ошибка: ' + err.message);
  }

  if (fullText) {
    chatHistory.push({ role: 'assistant', content: fullText });
    // Обновляем статистику
    if (currentUser) {
      const users = DB.getUsers();
      users[currentUser.username].totalMsgs = (users[currentUser.username].totalMsgs || 0) + 1;
      DB.saveUsers(users);
      currentUser.totalMsgs = users[currentUser.username].totalMsgs;
    }
    saveCurrentChat(chatHistory[0]?.content || 'Чат');
  }

  generating = false;
  document.getElementById('sendBtn').disabled = false;
  document.getElementById('statusDot').className = 'status-indicator online';
  document.getElementById('input').focus();
}

/* ══════════════════════════════════════
   РЕНДЕР СООБЩЕНИЙ
══════════════════════════════════════ */
function addMsg(role, text) {
  const m = document.getElementById('messages');
  const div = document.createElement('div');
  div.className = 'msg ' + (role === 'user' ? 'user' : 'ai');

  const av = document.createElement('div');
  av.className = 'avatar';
  if (role === 'user') {
    av.textContent = currentUser ? currentUser.username[0].toUpperCase() : 'Я';
  } else {
    av.textContent = '🦟';
  }

  const bubble = document.createElement('div');
  bubble.className = 'bubble';
  if (text) bubble.appendChild(renderMd(text));

  div.appendChild(av); div.appendChild(bubble);
  m.appendChild(div);
  m.scrollTop = 999999;
  return div;
}

function addTyping() {
  const m = document.getElementById('messages');
  const div = document.createElement('div');
  div.className = 'typing-wrap';
  const av = document.createElement('div');
  av.className = 'avatar'; av.textContent = '🦟';
  div.innerHTML = `
    <div class="avatar">🦟</div>
    <div class="typing-bubble">
      <span></span><span></span><span></span>
    </div>`;
  m.appendChild(div); m.scrollTop = 999999;
  return div;
}

function renderMd(text) {
  const wrap = document.createElement('div');
  const parts = text.split(/(```[\s\S]*?```)/g);
  parts.forEach(part => {
    if (part.startsWith('```')) {
      const lang = part.match(/^```(\w*)/)?.[1] || '';
      const code = part.replace(/^```\w*\n?/, '').replace(/```$/, '');
      const pre = document.createElement('pre');
      const btn = document.createElement('button');
      btn.className = 'copy-btn';
      btn.textContent = 'копировать';
      btn.onclick = () => { navigator.clipboard.writeText(code); btn.textContent = '✓ скопировано'; setTimeout(() => btn.textContent = 'копировать', 2000); };
      const c = document.createElement('code');
      c.textContent = code;
      pre.appendChild(btn); pre.appendChild(c);
      wrap.appendChild(pre);
    } else {
      const subs = part.split(/(`[^`]+`)/g);
      subs.forEach(s => {
        if (s.startsWith('`') && s.endsWith('`')) {
          const c = document.createElement('code');
          c.textContent = s.slice(1,-1);
          wrap.appendChild(c);
        } else {
          wrap.appendChild(document.createTextNode(s));
        }
      });
    }
  });
  return wrap;
}

function escHtml(t) {
  return t.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
}

/* ══════════════════════════════════════
   ЛИЧНЫЙ КАБИНЕТ
══════════════════════════════════════ */
function renderProfile() {
  if (!currentUser) return;
  const u = currentUser;
  const first = u.username[0].toUpperCase();
  document.getElementById('profileAvatar').textContent = first;
  document.getElementById('profileName').textContent   = u.username;
  document.getElementById('profileSub').textContent    = 'Локальный аккаунт · AI-CICADA';
  document.getElementById('infoUser').textContent      = u.username;
  document.getElementById('infoModel').textContent     = currentModel || '—';
  document.getElementById('infoDate').textContent      = new Date(u.createdAt).toLocaleDateString('ru-RU', {day:'numeric',month:'long',year:'numeric'});

  const chats = DB.getChats(u.username);
  const totalMsgs = chats.reduce((a,c) => a + c.messages.length, 0);
  const days = Math.max(1, Math.floor((Date.now() - u.createdAt) / 86400000));

  document.getElementById('statChats').textContent = chats.length;
  document.getElementById('statMsgs').textContent  = totalMsgs;
  document.getElementById('statDays').textContent  = days;
}

function clearAllHistory() {
  if (!confirm('Удалить всю историю чатов?')) return;
  DB.saveChats(currentUser.username, []);
  newChat();
  showPage('chatPage');
}

function deleteAccount() {
  if (!confirm('Удалить аккаунт и все данные? Это нельзя отменить!')) return;
  const users = DB.getUsers();
  delete users[currentUser.username];
  DB.saveUsers(users);
  localStorage.removeItem(`ac_chats_${currentUser.username}`);
  logout();
}

/* ══════════════════════════════════════
   САЙДБАР (мобиле)
══════════════════════════════════════ */
function openSidebar()  { document.getElementById('sidebar').classList.add('open'); document.getElementById('sidebarOverlay').classList.add('show'); }
function closeSidebar() { document.getElementById('sidebar').classList.remove('open'); document.getElementById('sidebarOverlay').classList.remove('show'); }

/* ══════════════════════════════════════
   TEXTAREA АВТОРАСШИРЕНИЕ
══════════════════════════════════════ */
document.getElementById('input').addEventListener('input', function() {
  this.style.height = 'auto';
  this.style.height = Math.min(this.scrollHeight, 120) + 'px';
});
document.getElementById('input').addEventListener('keydown', e => {
  if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); send(); }
});

/* ══════════════════════════════════════
   АВТОВХОД
══════════════════════════════════════ */
(function init() {
  const session = DB.getSession();
  if (session) {
    const users = DB.getUsers();
    if (users[session]) {
      currentUser = { ...users[session], username: session };
      enterChat();
      return;
    }
  }
  showPage('loginPage');
})();
</script>
</body>
</html>

HTMLEOF

    echo -e "${GREEN}✔️  Web chat created in $CHAT_DIR${NC}"
    log "Web chat created"
}

# ===== SETUP ALIASES =====
setup_alias() {
    echo -e "${BLUE}⚙️  Setting up commands...${NC}"

    local BASHRC="$HOME/.bashrc"

    # Удаляем старый блок
    if grep -q "# AI-CICADA" "$BASHRC" 2>/dev/null; then
        sed -i '/# AI-CICADA/,/# END AI-CICADA/d' "$BASHRC"
    fi

    if [ "$BACKEND" = "groq" ]; then
        cat >> "$BASHRC" << EOF

# AI-CICADA
export AI_MODEL="$MODEL"
export AI_BACKEND="groq"
export GROQ_API_KEY="$GROQ_API_KEY"

# Веб-чат в браузере (Groq)
web() {
    echo "🌐 Web chat: http://localhost:3000"
    echo "   Press Ctrl+C to stop"
    OPENAI_API_KEY=\$GROQ_API_KEY \\
    OPENAI_BASE_URL=https://api.groq.com/openai/v1 \\
    AI_MODEL=\$AI_MODEL node \$HOME/.ai-cicada/server.js
}
# END AI-CICADA
EOF
    else
        cat >> "$BASHRC" << EOF

# AI-CICADA
export AI_MODEL="$MODEL"
export AI_BACKEND="ollama"

# Веб-чат в браузере (Ollama)
web() {
    if ! pgrep -x "ollama" > /dev/null 2>&1; then
        echo "🚀 Starting Ollama..."
        ollama serve > /dev/null 2>&1 &
        sleep 3
    fi
    echo "🌐 Web chat: http://localhost:3000"
    echo "   Press Ctrl+C to stop"
    AI_MODEL=\$AI_MODEL node \$HOME/.ai-cicada/server.js
}
# END AI-CICADA
EOF
    fi

    echo -e "${GREEN}✔️  Commands ready: 'ai' and 'web'${NC}"
    log "Aliases set up"
}

# ===== FINAL SCREEN =====
final_screen() {
    clear
    local lines
    lines=$(safe_tput_lines)

    local i=0
    while [ $i -lt $(( lines / 2 - 10 )) ]; do echo; i=$(( i + 1 )); done

    draw_box \
        "✅ INSTALLATION COMPLETE" \
        "" \
        "Platform : $ENV_TYPE" \
        "Model    : $MODEL" \
        "" \
        "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" \
        "  ai   — terminal agent (OpenClaude)" \
        "  web  — browser chat  http://localhost:3000" \
        "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" \
        "" \
        "Log: $LOG_FILE"

    echo
    center_text "${CYAN}Restart terminal or: source ~/.bashrc${NC}"
    echo
    press_any_key
}

# ===== LAUNCH CHOICE =====
launch_choice() {
    clear
    center_text "${YELLOW}What to launch now?${NC}"
    echo
    draw_box \
        "1) Browser chat  (web)" \
        "2) Terminal agent (ai)" \
        "3) Exit"
    echo
    printf "${YELLOW}Choice: ${NC}"
    safe_read ch

    case $ch in
        1)
            echo -e "${GREEN}🌐 Open in browser: http://localhost:3000${NC}"
            echo -e "${YELLOW}   Press Ctrl+C to stop${NC}"
            if [ "$BACKEND" = "groq" ]; then
                OPENAI_API_KEY="$GROQ_API_KEY" \
                OPENAI_BASE_URL=https://api.groq.com/openai/v1 \
                AI_MODEL="$MODEL" node "$CHAT_DIR/server.js"
            else
                if ! pgrep -x "ollama" > /dev/null 2>&1; then
                    ollama serve >> "$LOG_FILE" 2>&1 &
                    sleep 3
                fi
                AI_MODEL="$MODEL" node "$CHAT_DIR/server.js"
            fi
            ;;
        2)
            echo -e "${GREEN}Done! Run 'web' anytime.${NC}"
            ;;
        *) echo -e "${GREEN}Done! Run 'web' anytime.${NC}" ;;
    esac
}

# ===== MAIN =====
main() {
    echo "===== AI-CICADA INSTALL $(date) =====" > "$LOG_FILE"

    detect_env
    show_logo
    select_model
    select_backend

    update_system
    clear

    install_nodejs
    echo

    install_ollama
    echo

    start_ollama_service

    install_model
    clear

    install_nodejs  # уже проверит что установлен
    echo

    create_web_chat
    echo

    setup_alias
    echo

    final_screen

    launch_choice
}

main "$@"
