#!/bin/bash

# =====================================================
#   SSH Reverse Tunnel Manager
#   Version : 2.3-beta
#   GitHub  : https://github.com/YOUR_USERNAME/ssh-tunnel-manager
#   Usage   : sudo bash setup.sh
# =====================================================

VERSION="2.3-beta"
REPO_RAW="https://raw.githubusercontent.com/YOUR_USERNAME/ssh-tunnel-manager/main/setup.sh"
REPO_VER="https://raw.githubusercontent.com/YOUR_USERNAME/ssh-tunnel-manager/main/VERSION"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'
DIM='\033[2m'

CONFIG_DIR="/etc/ssh-tunnel"
TUNNELS_FILE="$CONFIG_DIR/tunnels.conf"
AUTH_FILE="$CONFIG_DIR/auth.conf"
TUNNEL_SCRIPT="/usr/local/bin/ssh-tunnel"
SERVICE_FILE="/etc/systemd/system/ssh-tunnel.service"

# ─────────────────────────────────────────────────────
#  Print helpers
# ─────────────────────────────────────────────────────

banner() {
    clear
    echo -e "${CYAN}${BOLD}"
    echo "  ╔══════════════════════════════════════════════╗"
    echo "  ║     SSH Reverse Tunnel Manager               ║"
    printf "  ║     Version : %-31s║\n" "$VERSION"
    echo "  ║     Iran  →  VPS  (autossh + SOCKS5)        ║"
    echo "  ╚══════════════════════════════════════════════╝"
    echo -e "${NC}"
}

step() { echo -e "${BLUE}[*]${NC} $1"; }
ok()   { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[✗]${NC} $1"; }
info() { echo -e "${DIM}    $1${NC}"; }
hr()   { echo -e "${CYAN}${BOLD}──────────────────────────────────────────────${NC}"; }

require_root() {
    [[ $EUID -ne 0 ]] && { err "Run as root: sudo bash setup.sh"; exit 1; }
}

ensure_config_dir() {
    mkdir -p "$CONFIG_DIR"
    chmod 700 "$CONFIG_DIR"
    [[ ! -f "$TUNNELS_FILE" ]] && touch "$TUNNELS_FILE"
    [[ ! -f "$AUTH_FILE"    ]] && touch "$AUTH_FILE"
    chmod 600 "$AUTH_FILE"
}

# ─────────────────────────────────────────────────────
#  Self-Update
# ─────────────────────────────────────────────────────

self_update() {
    banner
    echo -e "${BOLD}  ► Self Update${NC}"
    hr
    echo ""

    if ! command -v curl &>/dev/null; then
        err "curl is required for updates."
        info "Install: apt-get install -y curl"
        echo ""; read -rp "  [Press Enter to return]"; return 1
    fi

    local curl_opts=(-fsSL --max-time 15)
    [[ -n "${PROXY_ADDR:-}" ]] && curl_opts+=(--proxy "socks5h://${PROXY_ADDR}")

    step "Checking latest version from GitHub..."
    local remote_ver
    remote_ver=$(curl "${curl_opts[@]}" "$REPO_VER" 2>/dev/null | tr -d '[:space:]')

    if [[ -z "$remote_ver" ]]; then
        err "Cannot reach GitHub."
        echo ""
        warn "Manual update:"
        info "  curl -fsSL $REPO_RAW -o /tmp/setup_new.sh"
        info "  sudo bash /tmp/setup_new.sh"
        echo ""; read -rp "  [Press Enter to return]"; return 1
    fi

    echo -e "  Installed : ${BOLD}${VERSION}${NC}"
    echo -e "  Available : ${BOLD}${remote_ver}${NC}"
    echo ""

    if [[ "$remote_ver" == "$VERSION" ]]; then
        ok "Already up to date!"
        echo ""; read -rp "  [Press Enter to return]"; return 0
    fi

    echo -e "  ${YELLOW}New version: ${remote_ver}${NC}"
    read -rp "  Update now? [y/N]: " confirm
    [[ "${confirm,,}" != "y" ]] && { warn "Cancelled."; sleep 1; return 0; }

    step "Downloading v${remote_ver}..."
    local tmp; tmp=$(mktemp /tmp/ssh-tunnel-XXXXXX.sh)

    if curl "${curl_opts[@]}" "$REPO_RAW" -o "$tmp" 2>/dev/null && bash -n "$tmp" 2>/dev/null; then
        chmod +x "$tmp"
        local self; self=$(readlink -f "$0")
        cp "$self" "${self}.bak" && ok "Backup: ${self}.bak"
        cp "$tmp" "$self"
        rm -f "$tmp"
        ok "Updated to v${remote_ver}!"
        echo ""
        read -rp "  Restart now? [Y/n]: " restart
        [[ "${restart,,}" != "n" ]] && exec bash "$self"
    else
        err "Download failed or invalid script."
        rm -f "$tmp"
    fi

    echo ""; read -rp "  [Press Enter to return]"
}

# ─────────────────────────────────────────────────────
#  Password store — AES-256 با openssl
#  کلید رمزنگاری از /etc/machine-id (یکتا روی هر ماشین)
#  فایل: /etc/ssh-tunnel/auth.conf  chmod 600
#  فرمت هر خط: HOST:PORT:USER:BASE64(AES_ENCRYPTED)
#  اگه openssl نبود: plain:BASE64(plaintext)
# ─────────────────────────────────────────────────────

_enc_key() {
    local mid; mid=$(cat /etc/machine-id 2>/dev/null || hostname)
    printf '%s' "${mid}ssh-tunnel-key" | sha256sum | awk '{print $1}'
}

save_password() {
    local host="$1" port="$2" user="$3" pass="$4"
    local key="${host}:${port}:${user}"
    local enc

    if command -v openssl &>/dev/null; then
        enc=$(printf '%s' "$pass" \
            | openssl enc -aes-256-cbc -pbkdf2 -pass "pass:$(_enc_key)" 2>/dev/null \
            | base64 -w0)
        [[ -z "$enc" ]] && enc="plain:$(printf '%s' "$pass" | base64 -w0)"
    else
        warn "openssl not found — saving password as plaintext (chmod 600)"
        enc="plain:$(printf '%s' "$pass" | base64 -w0)"
    fi

    # حذف خط قبلی و ذخیره جدید
    sed -i "/^${host}:${port}:${user}:/d" "$AUTH_FILE" 2>/dev/null
    echo "${key}:${enc}" >> "$AUTH_FILE"
    chmod 600 "$AUTH_FILE"
    ok "Password saved to $AUTH_FILE"
}

load_password() {
    local host="$1" port="$2" user="$3"
    local line; line=$(grep "^${host}:${port}:${user}:" "$AUTH_FILE" 2>/dev/null | head -1)
    [[ -z "$line" ]] && return 1

    # چهارمین field به بعد = encrypted data (ممکنه : داشته باشه)
    local enc
    enc=$(echo "$line" | cut -d: -f4-)
    [[ -z "$enc" ]] && return 1

    if [[ "$enc" == plain:* ]]; then
        printf '%s' "${enc#plain:}" | base64 -d 2>/dev/null
    else
        printf '%s' "$enc" | base64 -d 2>/dev/null \
            | openssl enc -d -aes-256-cbc -pbkdf2 -pass "pass:$(_enc_key)" 2>/dev/null
    fi
}

delete_password() {
    local host="$1" port="$2" user="$3"
    sed -i "/^${host}:${port}:${user}:/d" "$AUTH_FILE" 2>/dev/null
}

has_password() {
    local host="$1" port="$2" user="$3"
    grep -q "^${host}:${port}:${user}:" "$AUTH_FILE" 2>/dev/null
}

# ─────────────────────────────────────────────────────
#  Restart sshd
# ─────────────────────────────────────────────────────

restart_sshd() {
    for name in ssh sshd openssh-server; do
        if systemctl list-units --full --all 2>/dev/null | grep -q "^${name}\.service"; then
            systemctl restart "$name" && ok "sshd restarted ($name)" && return 0
        fi
    done
    systemctl restart ssh  2>/dev/null && ok "sshd restarted (ssh)"  && return 0
    systemctl restart sshd 2>/dev/null && ok "sshd restarted (sshd)" && return 0
    err "Could not restart sshd — run: systemctl restart ssh"
    return 1
}

# ─────────────────────────────────────────────────────
#  Fix GatewayPorts
# ─────────────────────────────────────────────────────

fix_gateway_ports() {
    local SSHD="/etc/ssh/sshd_config"
    step "Scanning /etc/ssh/ for GatewayPorts conflicts..."
    while IFS= read -r f; do
        [[ -f "$f" ]] || continue
        sed -i "/^[[:space:]]*#*[[:space:]]*GatewayPorts\b/Id" "$f"
        ok "  Cleaned: $f"
    done < <(grep -rli "GatewayPorts" /etc/ssh/ 2>/dev/null)

    local tmp; tmp=$(mktemp)
    echo "GatewayPorts clientspecified" > "$tmp"
    cat "$SSHD" >> "$tmp"
    mv "$tmp" "$SSHD"
    ok "GatewayPorts clientspecified → top of $SSHD"

    restart_sshd; sleep 1

    local gp; gp=$(sshd -T 2>/dev/null | awk '/^gatewayports/{print $2}')
    if [[ "$gp" == "clientspecified" || "$gp" == "yes" ]]; then
        ok "Verified runtime GatewayPorts=${gp}"; return 0
    else
        err "GatewayPorts='${gp}' — fix manually:"
        info "  grep -ri gatewayports /etc/ssh/"
        info "  Add: GatewayPorts clientspecified"
        info "  systemctl restart ssh"
        return 1
    fi
}

# ─────────────────────────────────────────────────────
#  Port helpers  (/proc/net — no ss/netstat needed)
# ─────────────────────────────────────────────────────

port_on_all_interfaces() {
    local port="$1"
    local hex; hex=$(printf '%04X' "$port")
    for f in /proc/net/tcp /proc/net/tcp6; do
        [[ -r "$f" ]] || continue
        while IFS= read -r line; do
            [[ "$line" =~ ^[[:space:]]*sl ]] && continue
            local la; la=$(awk '{print $2}' <<< "$line")
            [[ "${la##*:}" == "$hex" ]] || continue
            local addr="${la%:*}"
            [[ "$addr" == "00000000" || "$addr" == "00000000000000000000000000000000" ]] \
                && return 0
        done < "$f"
    done
    return 1
}

port_bind_addr() {
    local port="$1"
    local hex; hex=$(printf '%04X' "$port")
    [[ -r /proc/net/tcp ]] || { echo "not listening"; return; }
    while IFS= read -r line; do
        [[ "$line" =~ ^[[:space:]]*sl ]] && continue
        local la; la=$(awk '{print $2}' <<< "$line")
        [[ "${la##*:}" == "$hex" ]] || continue
        case "${la%:*}" in
            00000000) echo "0.0.0.0";   return ;;
            0100007F) echo "127.0.0.1"; return ;;
            *)        echo "${la%:*}";  return ;;
        esac
    done < /proc/net/tcp
    echo "not listening"
}

# ─────────────────────────────────────────────────────
#  SERVER SETUP (VPS side)
# ─────────────────────────────────────────────────────

setup_server() {
    banner
    echo -e "${BOLD}  ► Server Setup  (VPS / Kharej)${NC}"
    hr

    fix_gateway_ports; local gp_ok=$?

    local SSHD="/etc/ssh/sshd_config"
    _set_sshd() {
        sed -i "/^[[:space:]]*#*[[:space:]]*${1}\b/Id" "$SSHD"
        echo "${1} ${2}" >> "$SSHD"
    }
    _set_sshd "AllowTcpForwarding"  "yes"
    _set_sshd "ClientAliveInterval" "10"
    _set_sshd "ClientAliveCountMax" "3"
    restart_sshd

    echo ""
    read -rp "  How many tunnel ports? (1–20, default 1): " PORT_COUNT
    PORT_COUNT=${PORT_COUNT:-1}
    [[ ! "$PORT_COUNT" =~ ^[0-9]+$ || "$PORT_COUNT" -lt 1 || "$PORT_COUNT" -gt 20 ]] \
        && { err "Invalid number"; exit 1; }

    local PORTS=()
    for (( i=1; i<=PORT_COUNT; i++ )); do
        local def=$(( 20000 + i - 1 ))
        read -rp "  Port #${i} [default ${def}]: " p; p=${p:-$def}
        [[ ! "$p" =~ ^[0-9]+$ || "$p" -lt 1024 || "$p" -gt 65535 ]] \
            && { err "Invalid port: $p"; exit 1; }
        PORTS+=("$p")
    done

    step "Opening firewall ports: ${PORTS[*]}"
    for p in "${PORTS[@]}"; do
        if command -v ufw &>/dev/null && ufw status | grep -q "active"; then
            ufw allow "${p}/tcp" &>/dev/null && ok "ufw: $p/tcp"
        elif command -v firewall-cmd &>/dev/null; then
            firewall-cmd --permanent --add-port="${p}/tcp" &>/dev/null
            firewall-cmd --reload &>/dev/null && ok "firewalld: $p/tcp"
        else
            iptables -A INPUT -p tcp --dport "$p" -j ACCEPT 2>/dev/null && ok "iptables: $p/tcp"
        fi
    done

    hr; ok "Server ready! Ports: ${PORTS[*]}"; echo ""
    [[ $gp_ok -ne 0 ]] && warn "GatewayPorts not set automatically — fix manually (see above)"
    info "Now run setup.sh on the Iran server → Client Setup"
    echo ""

    echo -e "  ${BOLD}Waiting for Iran client...${NC}  ${DIM}(Ctrl+C to skip)${NC}"
    echo ""
    local max_wait=300 elapsed=0 all_up=0
    while [[ $elapsed -lt $max_wait ]]; do
        all_up=1
        for p in "${PORTS[@]}"; do port_on_all_interfaces "$p" || { all_up=0; break; }; done
        if [[ $all_up -eq 1 ]]; then
            echo ""; ok "All tunnel ports up on 0.0.0.0!"
            for p in "${PORTS[@]}"; do ok "  0.0.0.0:${p} ✓"; done
            echo ""; break
        fi
        local sl="  [${elapsed}s]"
        for p in "${PORTS[@]}"; do
            port_on_all_interfaces "$p" && sl+=" ${p}[UP]" || sl+=" ${p}[wait]"
        done
        printf "\r%-70s" "$sl"
        sleep 2; (( elapsed += 2 ))
    done

    if [[ $all_up -eq 0 ]]; then
        echo ""; echo ""; warn "Iran client did not connect within ${max_wait}s"; echo ""
        for p in "${PORTS[@]}"; do
            case "$(port_bind_addr "$p")" in
                "0.0.0.0")       ok   "Port $p: 0.0.0.0 ✓" ;;
                "127.0.0.1")     err  "Port $p: 127.0.0.1 only — GatewayPorts broken"
                                  info "  Fix: GatewayPorts clientspecified → systemctl restart ssh" ;;
                "not listening") warn "Port $p: not listening yet" ;;
                *)               warn "Port $p: unknown bind" ;;
            esac
        done
    fi

    echo ""; read -rp "  [Press Enter to return to menu]"
}

# ─────────────────────────────────────────────────────
#  SOCKS5 proxy ask
# ─────────────────────────────────────────────────────

ask_proxy() {
    echo ""
    echo -e "  ${BOLD}Proxy Configuration${NC}"
    echo -e "  ${DIM}Required if outbound SSH is blocked on this server${NC}"
    echo ""
    echo "    1) Yes — I have a SOCKS5 proxy"
    echo "    2) No  — connect directly"
    echo ""
    read -rp "  Choice [1/2, default 2]: " PROXY_CHOICE
    PROXY_CHOICE=${PROXY_CHOICE:-2}

    PROXY_CMD=""; PROXY_ADDR=""; APT_PROXY_ARGS=""

    if [[ "$PROXY_CHOICE" == "1" ]]; then
        echo ""
        read -rp "  SOCKS5 address (e.g. 127.0.0.1:1080): " PROXY_ADDR
        [[ -z "$PROXY_ADDR" ]] && { err "Proxy address required"; exit 1; }
        local ph="${PROXY_ADDR%:*}" pp="${PROXY_ADDR##*:}"
        [[ -z "$ph" || -z "$pp" ]] && { err "Format: host:port"; exit 1; }
        PROXY_CMD="ProxyCommand=nc -x ${ph}:${pp} -X 5 %h %p"
        APT_PROXY_ARGS="-o Acquire::http::proxy=\"socks5h://${PROXY_ADDR}\" -o Acquire::https::proxy=\"socks5h://${PROXY_ADDR}\""
        ok "SOCKS5 proxy: $PROXY_ADDR"
    fi
}

# ─────────────────────────────────────────────────────
#  Install deps — nc, sshpass, autossh
# ─────────────────────────────────────────────────────

install_deps() {
    step "Checking dependencies..."
    local pkgs=()
    command -v nc      &>/dev/null || pkgs+=(netcat-openbsd)
    command -v sshpass &>/dev/null || pkgs+=(sshpass)
    command -v autossh &>/dev/null || pkgs+=(autossh)

    if [[ ${#pkgs[@]} -gt 0 ]]; then
        step "Installing: ${pkgs[*]}"
        if command -v apt-get &>/dev/null; then
            eval apt-get install -y -q "${pkgs[@]}" ${APT_PROXY_ARGS:-} 2>/dev/null
        elif command -v yum &>/dev/null; then
            [[ -n "${PROXY_ADDR:-}" ]] \
                && http_proxy="socks5h://${PROXY_ADDR}" yum install -y -q "${pkgs[@]}" 2>/dev/null \
                || yum install -y -q "${pkgs[@]}" 2>/dev/null
        else
            warn "Cannot auto-install ${pkgs[*]} — install manually"
        fi
    fi

    if command -v autossh &>/dev/null; then
        ok "autossh ready: $(autossh -V 2>&1 | head -1)"
    else
        warn "autossh not available — will use ssh fallback (brief reconnect gap possible)"
    fi
}

# ─────────────────────────────────────────────────────
#  CLIENT SETUP (Iran side)
# ─────────────────────────────────────────────────────

ask_auth() {
    # نیاز داره: REMOTE_HOST, SSH_PORT, REMOTE_USER ست شده باشن
    echo ""
    echo -e "  ${BOLD}Authentication${NC}"
    echo ""
    echo "    1) Password  — copies SSH key automatically + saves password"
    echo "    2) Key-based — key already installed on remote"
    echo ""
    read -rp "  Choice [1/2, default 1]: " AUTH_CHOICE
    AUTH_CHOICE=${AUTH_CHOICE:-1}

    REMOTE_PASS=""
    if [[ "$AUTH_CHOICE" == "1" ]]; then
        # بررسی رمز ذخیره‌شده
        if has_password "$REMOTE_HOST" "$SSH_PORT" "$REMOTE_USER"; then
            echo ""
            echo -e "  ${DIM}Saved password found for ${REMOTE_USER}@${REMOTE_HOST}:${SSH_PORT}${NC}"
            read -rp "  Use saved password? [Y/n]: " use_saved
            if [[ "${use_saved,,}" != "n" ]]; then
                REMOTE_PASS=$(load_password "$REMOTE_HOST" "$SSH_PORT" "$REMOTE_USER")
                ok "Using saved password."; return
            fi
        fi
        read -rsp "  SSH password for ${REMOTE_USER}@${REMOTE_HOST}: " REMOTE_PASS
        echo ""
        [[ -z "$REMOTE_PASS" ]] && { err "Password required"; exit 1; }
        ok "Password received"
    else
        ok "Key-based — no password needed"
    fi
}

copy_ssh_key() {
    local RU="$1" RH="$2" SP="$3" PC="$4" PASS="$5"

    [[ ! -f ~/.ssh/id_rsa ]] && {
        step "Generating SSH key..."
        ssh-keygen -t rsa -b 4096 -N "" -f ~/.ssh/id_rsa -q && ok "SSH key created"
    } || ok "SSH key: ~/.ssh/id_rsa"

    if [[ -n "$PASS" ]] && ! command -v sshpass &>/dev/null; then
        install_deps
        if ! command -v sshpass &>/dev/null; then
            err "sshpass unavailable — add key manually:"
            echo -e "  ${YELLOW}$(cat ~/.ssh/id_rsa.pub)${NC}"
            read -rp "  Press Enter after adding key: "; return
        fi
    fi

    step "Copying SSH key to ${RU}@${RH}..."
    local args=(); [[ -n "$PC" ]] && args+=(-o "$PC")
    args+=(-o "StrictHostKeyChecking=no" -p "$SP")

    local ok_flag=0
    if [[ -n "$PASS" ]]; then
        SSHPASS="$PASS" sshpass -e ssh-copy-id "${args[@]}" "${RU}@${RH}" && ok_flag=1
    else
        ssh-copy-id "${args[@]}" "${RU}@${RH}" && ok_flag=1
    fi

    if [[ $ok_flag -eq 1 ]]; then
        ok "SSH key installed — passwordless login active"
        if [[ -n "$PASS" ]]; then
            read -rp "  Save password for future use? [Y/n]: " sv
            [[ "${sv,,}" != "n" ]] && save_password "$RH" "$SP" "$RU" "$PASS"
        fi
    else
        warn "ssh-copy-id failed — add key manually:"
        echo -e "  ${YELLOW}$(cat ~/.ssh/id_rsa.pub)${NC}"
        read -rp "  Press Enter after adding key: "
    fi
}

wait_for_connection() {
    local RH="$1" SP="$2" PC="$3" RU="$4"
    step "Testing SSH to ${RH}:${SP}..."
    for (( i=1; i<=60; i++ )); do
        local args=(); [[ -n "$PC" ]] && args+=(-o "$PC")
        args+=(-o "StrictHostKeyChecking=no" -o "ConnectTimeout=5" -o "BatchMode=yes" -p "$SP")
        ssh "${args[@]}" "${RU}@${RH}" "exit" 2>/dev/null \
            && { echo ""; ok "Connected to ${RH}!"; return 0; }
        printf "\r  Attempt %d/60..." "$i"; sleep 1
    done
    echo ""; err "Cannot connect to ${RH}:${SP}"; return 1
}

# ─────────────────────────────────────────────────────
#  Tunnel runner — autossh با fallback کامل
# ─────────────────────────────────────────────────────

generate_tunnel_script() {
    step "Generating tunnel runner..."
    cat > "$TUNNEL_SCRIPT" << 'SCRIPT_EOF'
#!/bin/bash
# Auto-generated by SSH Reverse Tunnel Manager — do not edit manually
CONFIG_DIR="/etc/ssh-tunnel"
TUNNELS_FILE="$CONFIG_DIR/tunnels.conf"
AUTH_FILE="$CONFIG_DIR/auth.conf"
LOG_FILE="$CONFIG_DIR/tunnel.log"
MAX_LOG=2000

log() {
    local msg="$(date '+%Y-%m-%d %H:%M:%S') $1"
    echo "$msg" | tee -a "$LOG_FILE"
    local cnt; cnt=$(wc -l < "$LOG_FILE" 2>/dev/null || echo 0)
    if (( cnt > MAX_LOG )); then
        tail -n $((MAX_LOG/2)) "$LOG_FILE" > "${LOG_FILE}.tmp" \
            && mv "${LOG_FILE}.tmp" "$LOG_FILE"
    fi
}

# همان تابع رمزخوانی از auth.conf
_enc_key() {
    local mid; mid=$(cat /etc/machine-id 2>/dev/null || hostname)
    printf '%s' "${mid}ssh-tunnel-key" | sha256sum | awk '{print $1}'
}

load_password() {
    local host="$1" port="$2" user="$3"
    local line; line=$(grep "^${host}:${port}:${user}:" "$AUTH_FILE" 2>/dev/null | head -1)
    [[ -z "$line" ]] && return 1
    local enc; enc=$(echo "$line" | cut -d: -f4-)
    [[ -z "$enc" ]] && return 1
    if [[ "$enc" == plain:* ]]; then
        printf '%s' "${enc#plain:}" | base64 -d 2>/dev/null
    else
        printf '%s' "$enc" | base64 -d 2>/dev/null \
            | openssl enc -d -aes-256-cbc -pbkdf2 -pass "pass:$(_enc_key)" 2>/dev/null
    fi
}

run_tunnel() {
    # فرمت: ID|REMOTE_USER|REMOTE_HOST|SSH_PORT|TUNNEL_PORT|LOCAL_PORT|PROXY_CMD
    IFS='|' read -r ID RU RH SP TP LP PC <<< "$1"

    # monitoring port منحصربه‌فرد برای autossh
    local MON=$(( 20100 + (TP % 900) ))

    local BASE_OPTS=(
        -o "ServerAliveInterval=10"
        -o "ServerAliveCountMax=3"
        -o "ExitOnForwardFailure=yes"
        -o "StrictHostKeyChecking=no"
        -o "ConnectTimeout=15"
        -o "TCPKeepAlive=yes"
        -o "BatchMode=yes"
        -p "$SP"
        -R "0.0.0.0:${TP}:127.0.0.1:${LP}"
    )
    [[ -n "$PC" ]] && BASE_OPTS+=(-o "$PC")

    # یه بار وصل شو — اول key، بعد رمز
    _ssh_once() {
        ssh -N "${BASE_OPTS[@]}" "${RU}@${RH}" 2>/dev/null && return 0
        local pass; pass=$(load_password "$RH" "$SP" "$RU" 2>/dev/null)
        if [[ -n "$pass" ]] && command -v sshpass &>/dev/null; then
            SSHPASS="$pass" sshpass -e ssh -N "${BASE_OPTS[@]}" "${RU}@${RH}" 2>/dev/null \
                && return 0
        fi
        return 1
    }

    if command -v autossh &>/dev/null; then
        log "[T${ID}] autossh → ${RH}:${TP} (mon:${MON})"
        while true; do
            AUTOSSH_GATETIME=0 \
            AUTOSSH_POLL=10 \
            AUTOSSH_FIRST_POLL=30 \
            AUTOSSH_MAXSTART=0 \
            AUTOSSH_LOGFILE="" \
                autossh -M "$MON" -N "${BASE_OPTS[@]}" "${RU}@${RH}" 2>/dev/null
            log "[T${ID}] autossh exited — retry in 3s..."
            sleep 3
        done
    else
        log "[T${ID}] ssh fallback loop → ${RH}:${TP}"
        while true; do
            log "[T${ID}] Connecting..."
            _ssh_once
            log "[T${ID}] Disconnected — retry in 5s..."
            sleep 5
        done
    fi
}

# اجرای همه tunnelها به صورت موازی
while IFS= read -r line; do
    [[ -z "$line" || "$line" == \#* ]] && continue
    run_tunnel "$line" &
done < "$TUNNELS_FILE"

log "All tunnels launched (PID $$)"
wait
SCRIPT_EOF
    chmod +x "$TUNNEL_SCRIPT"
    ok "Tunnel runner: $TUNNEL_SCRIPT"
}

# ─────────────────────────────────────────────────────
#  systemd service
# ─────────────────────────────────────────────────────

generate_service() {
    step "Installing systemd service..."
    cat > "$SERVICE_FILE" << 'SVC_EOF'
[Unit]
Description=SSH Reverse Tunnel Manager
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/ssh-tunnel
Restart=always
RestartSec=5
StartLimitIntervalSec=0
KillMode=process
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SVC_EOF
    systemctl daemon-reload
    systemctl enable ssh-tunnel &>/dev/null
    ok "Service enabled (Restart=always, StartLimitIntervalSec=0)"
}

setup_client() {
    banner
    echo -e "${BOLD}  ► Client Setup  (Iran / restricted server)${NC}"
    hr
    ensure_config_dir

    ask_proxy
    install_deps

    echo ""
    echo -e "  ${BOLD}Remote VPS${NC}"
    read -rp "  SSH host (IP or domain): " REMOTE_HOST
    [[ -z "$REMOTE_HOST" ]] && { err "Host required"; exit 1; }
    read -rp "  SSH user [default root]: " REMOTE_USER
    REMOTE_USER=${REMOTE_USER:-root}
    read -rp "  SSH port [default 22]: " SSH_PORT
    SSH_PORT=${SSH_PORT:-22}

    ask_auth

    echo ""
    echo -e "  ${BOLD}Tunnel Ports${NC}"
    read -rp "  How many tunnels? (1–20, default 1): " TUNNEL_COUNT
    TUNNEL_COUNT=${TUNNEL_COUNT:-1}
    [[ ! "$TUNNEL_COUNT" =~ ^[0-9]+$ || "$TUNNEL_COUNT" -lt 1 || "$TUNNEL_COUNT" -gt 20 ]] \
        && { err "Invalid"; exit 1; }

    local ENTRIES=()
    for (( i=1; i<=TUNNEL_COUNT; i++ )); do
        echo ""
        echo -e "  ${CYAN}── Tunnel #${i} ──${NC}"
        local def=$(( 20000 + i - 1 ))
        read -rp "  Remote port on VPS  [default ${def}]: " TP; TP=${TP:-$def}
        read -rp "  Local port to fwd   [default ${TP}]: "  LP; LP=${LP:-$TP}
        ENTRIES+=("${i}|${REMOTE_USER}|${REMOTE_HOST}|${SSH_PORT}|${TP}|${LP}|${PROXY_CMD}")
        ok "Tunnel #${i}: local:${LP} → ${REMOTE_HOST}:${TP}"
    done

    copy_ssh_key "$REMOTE_USER" "$REMOTE_HOST" "$SSH_PORT" "$PROXY_CMD" "$REMOTE_PASS"
    wait_for_connection "$REMOTE_HOST" "$SSH_PORT" "$PROXY_CMD" "$REMOTE_USER" \
        || { err "Connection failed — aborting"; exit 1; }

    step "Saving tunnel config..."
    for entry in "${ENTRIES[@]}"; do
        echo "$entry" >> "$TUNNELS_FILE"
    done
    ok "Config: $TUNNELS_FILE"

    generate_tunnel_script
    generate_service
    systemctl restart ssh-tunnel
    sleep 3

    hr
    if systemctl is-active ssh-tunnel &>/dev/null; then
        echo -e "${GREEN}${BOLD}  ✓ Setup complete! ${TUNNEL_COUNT} tunnel(s) active.${NC}"
    else
        warn "Service may have issues — check: journalctl -u ssh-tunnel -f"
    fi
    echo ""
    info "Status : systemctl status ssh-tunnel"
    info "Logs   : journalctl -u ssh-tunnel -f"
    echo ""; read -rp "  [Press Enter to return to menu]"
}

# ─────────────────────────────────────────────────────
#  Tunnel management
# ─────────────────────────────────────────────────────

list_tunnels() {
    echo ""
    if [[ ! -s "$TUNNELS_FILE" ]]; then
        warn "No tunnels configured."; return 1
    fi
    echo -e "  ${BOLD}Configured Tunnels:${NC}"
    hr
    printf "  %-4s %-22s %-10s %-13s %-12s %-8s %-6s %s\n" \
        "#" "Remote Host" "SSH Port" "Tunnel Port" "Local Port" "Proxy" "PW" "Status"
    hr
    local i=1
    while IFS='|' read -r ID RU RH SP TP LP PC; do
        [[ -z "$ID" || "$ID" == \#* ]] && continue
        local proxy="none"; [[ -n "$PC" ]] && proxy="socks5"
        local pw_st; has_password "$RH" "$SP" "$RU" && pw_st="${GREEN}yes${NC}" || pw_st="${DIM}no${NC}"
        local svc_st
        systemctl is-active ssh-tunnel &>/dev/null \
            && svc_st="${GREEN}active${NC}" || svc_st="${RED}stopped${NC}"
        printf "  %-4s %-22s %-10s %-13s %-12s %-8s " "$i" "$RH" "$SP" "$TP" "$LP" "$proxy"
        echo -e "${pw_st}  ${svc_st}"
        (( i++ ))
    done < "$TUNNELS_FILE"
    echo ""
}

delete_tunnel() {
    list_tunnels || return
    read -rp "  Tunnel # to delete (0=cancel): " N
    [[ "$N" == "0" || -z "$N" ]] && return
    local i=1 NEW=""
    while IFS='|' read -r ID RU RH SP TP LP PC; do
        [[ -z "$ID" || "$ID" == \#* ]] && continue
        if [[ "$i" -eq "$N" ]]; then
            ok "Tunnel #${N} removed"
            read -rp "  Also delete saved password for ${RU}@${RH}? [y/N]: " dp
            [[ "${dp,,}" == "y" ]] && delete_password "$RH" "$SP" "$RU" && ok "Password removed"
        else
            NEW+="${ID}|${RU}|${RH}|${SP}|${TP}|${LP}|${PC}\n"
        fi
        (( i++ ))
    done < "$TUNNELS_FILE"
    printf "%b" "$NEW" > "$TUNNELS_FILE"
    generate_tunnel_script
    systemctl restart ssh-tunnel && ok "Service restarted"
}

edit_tunnel() {
    list_tunnels || return
    read -rp "  Tunnel # to edit (0=cancel): " N
    [[ "$N" == "0" || -z "$N" ]] && return
    local i=1 FOUND=0 NEW=""
    while IFS='|' read -r ID RU RH SP TP LP PC; do
        [[ -z "$ID" || "$ID" == \#* ]] && continue
        if [[ "$i" -eq "$N" ]]; then
            FOUND=1; echo ""
            echo -e "  ${BOLD}Edit Tunnel #${N}${NC}  (Enter = keep current)"
            local OLD_RH="$RH" OLD_SP="$SP" OLD_RU="$RU"
            read -rp "  Remote host  [${RH}]: " v; RH=${v:-$RH}
            read -rp "  SSH user     [${RU}]: " v; RU=${v:-$RU}
            read -rp "  SSH port     [${SP}]: " v; SP=${v:-$SP}
            read -rp "  Tunnel port  [${TP}]: " v; TP=${v:-$TP}
            read -rp "  Local port   [${LP}]: " v; LP=${v:-$LP}

            # ویرایش رمز
            has_password "$OLD_RH" "$OLD_SP" "$OLD_RU" \
                && echo -e "  ${DIM}Password: saved ✓${NC}" \
                || echo -e "  ${DIM}Password: not saved${NC}"
            read -rsp "  New password (Enter=keep, type 'clear'=remove): " new_pw; echo ""
            if [[ "$new_pw" == "clear" ]]; then
                delete_password "$OLD_RH" "$OLD_SP" "$OLD_RU"; ok "Password cleared"
            elif [[ -n "$new_pw" ]]; then
                # اگه host تغییر کرد، قدیمی رو پاک کن
                [[ "$OLD_RH$OLD_SP$OLD_RU" != "$RH$SP$RU" ]] \
                    && delete_password "$OLD_RH" "$OLD_SP" "$OLD_RU"
                save_password "$RH" "$SP" "$RU" "$new_pw"
            fi

            # ویرایش proxy
            local cur_p="none"; [[ -n "$PC" ]] && cur_p="$PC"
            echo -e "  Current proxy: ${DIM}${cur_p}${NC}"
            read -rp "  New SOCKS5 (host:port), 'none'=clear, Enter=keep: " NP
            if   [[ "$NP" == "none" ]]; then PC=""
            elif [[ -n "$NP" ]]; then PC="ProxyCommand=nc -x ${NP%:*}:${NP##*:} -X 5 %h %p"
            fi

            NEW+="${N}|${RU}|${RH}|${SP}|${TP}|${LP}|${PC}\n"
            ok "Tunnel #${N} updated"
        else
            NEW+="${ID}|${RU}|${RH}|${SP}|${TP}|${LP}|${PC}\n"
        fi
        (( i++ ))
    done < "$TUNNELS_FILE"
    [[ $FOUND -eq 0 ]] && { err "Not found"; return; }
    printf "%b" "$NEW" > "$TUNNELS_FILE"
    generate_tunnel_script
    systemctl restart ssh-tunnel && ok "Service restarted"
}

manage_passwords() {
    banner
    echo -e "${BOLD}  ► Password Manager${NC}"
    hr; echo ""

    if [[ ! -s "$AUTH_FILE" ]]; then
        warn "No saved passwords."; echo ""; read -rp "  [Press Enter]"; return
    fi

    echo -e "  ${BOLD}Saved credentials (in $AUTH_FILE):${NC}"; echo ""
    local i=1
    declare -a ENTRIES
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local host port user
        IFS=':' read -r host port user _ <<< "$line"
        local pass; pass=$(load_password "$host" "$port" "$user" 2>/dev/null)
        if [[ -n "$pass" ]]; then
            printf "  ${GREEN}%2d)${NC} %-20s  %s@%s  ${DIM}[OK]${NC}\n" \
                "$i" "${host}:${port}" "$user" "$host"
        else
            printf "  ${YELLOW}%2d)${NC} %-20s  %s@%s  ${DIM}[decrypt failed]${NC}\n" \
                "$i" "${host}:${port}" "$user" "$host"
        fi
        ENTRIES+=("${host}:${port}:${user}")
        (( i++ ))
    done < "$AUTH_FILE"

    echo ""
    echo "  d) Delete a saved password"
    echo "  0) Back"
    echo ""
    read -rp "  Choice: " ch
    if [[ "$ch" == "d" ]]; then
        read -rp "  Entry # to delete: " dn
        local idx=$(( dn - 1 ))
        if [[ -n "${ENTRIES[$idx]:-}" ]]; then
            IFS=':' read -r dh dp du <<< "${ENTRIES[$idx]}"
            delete_password "$dh" "$dp" "$du"
            ok "Deleted: ${du}@${dh}:${dp}"
        else
            err "Invalid selection"
        fi
    fi
    echo ""; read -rp "  [Press Enter to return]"
}

uninstall_all() {
    banner
    echo -e "${BOLD}  ► Uninstall${NC}"; hr; echo ""
    warn "This will remove: service, script, tunnel config, and saved passwords."
    read -rp "  Type 'yes' to confirm: " C
    [[ "$C" != "yes" ]] && { warn "Cancelled."; sleep 1; return; }
    systemctl stop    ssh-tunnel 2>/dev/null; ok "Service stopped"
    systemctl disable ssh-tunnel 2>/dev/null; ok "Service disabled"
    rm -f  "$SERVICE_FILE"  && ok "Unit file removed"
    rm -f  "$TUNNEL_SCRIPT" && ok "Runner script removed"
    rm -rf "$CONFIG_DIR"    && ok "Config dir removed (tunnels + passwords)"
    systemctl daemon-reload
    echo ""; ok "Uninstall complete!"; echo ""; exit 0
}

# ─────────────────────────────────────────────────────
#  MAIN MENU
# ─────────────────────────────────────────────────────

main() {
    require_root
    ensure_config_dir
    PROXY_ADDR=""  # global — برای self_update

    while true; do
        banner

        if systemctl is-active ssh-tunnel &>/dev/null; then
            echo -e "  Service : ${GREEN}${BOLD}RUNNING${NC}"
        else
            echo -e "  Service : ${RED}${BOLD}STOPPED${NC}"
        fi
        local tcnt; tcnt=$(grep -c "^[^#]" "$TUNNELS_FILE" 2>/dev/null || echo 0)
        echo -e "  Tunnels : ${BOLD}${tcnt}${NC} configured"

        echo ""; hr; echo ""
        echo "  1)  Client Setup    — Iran server creates tunnel to VPS"
        echo "  2)  Server Setup    — VPS receives tunnel"
        echo "  3)  List tunnels"
        echo "  4)  Edit tunnel"
        echo "  5)  Delete tunnel"
        echo "  6)  Password manager"
        echo "  7)  Restart service"
        echo "  8)  View live logs"
        echo "  9)  Update script"
        echo "  10) Uninstall"
        echo "  0)  Exit"
        echo ""; hr
        read -rp "  Choice: " CHOICE
        case "$CHOICE" in
            1)  setup_client ;;
            2)  setup_server ;;
            3)  list_tunnels;  read -rp "  [Enter to continue]" ;;
            4)  edit_tunnel;   read -rp "  [Enter to continue]" ;;
            5)  delete_tunnel; read -rp "  [Enter to continue]" ;;
            6)  manage_passwords ;;
            7)  systemctl restart ssh-tunnel && ok "Restarted"; sleep 1 ;;
            8)  echo -e "  ${DIM}Ctrl+C to exit${NC}"; journalctl -u ssh-tunnel -f ;;
            9)  self_update ;;
            10) uninstall_all ;;
            0)  echo ""; exit 0 ;;
            *)  warn "Invalid choice"; sleep 1 ;;
        esac
    done
}

main
