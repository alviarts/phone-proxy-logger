#!/data/data/com.termux/files/usr/bin/bash
#
# Auto Phone Proxy Tunnel - Keep SSH tunnel alive 24/7
# 
# Usage:
#   bash auto_tunnel.sh
#
# To run in background:
#   nohup bash auto_tunnel.sh > ~/tunnel.log 2>&1 &
#
# To stop:
#   pkill -f auto_tunnel.sh

set -euo pipefail

# Konfigurasi
VPS_HOST="103.74.5.44"
VPS_USER="phoneproxy"
VPS_PORT="22"
LOCAL_PROXY_PORT="8080"
REMOTE_PROXY_PORT="18080"
SSH_KEY="$HOME/.ssh/phoneproxy"
CHECK_INTERVAL=30  # detik
LOG_FILE="$HOME/tunnel.log"

# Warna untuk log
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] SUCCESS:${NC} $1" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1" | tee -a "$LOG_FILE"
}

# Cek apakah pproxy jalan
check_pproxy() {
    if pgrep -f "pproxy.*:$LOCAL_PROXY_PORT" > /dev/null; then
        return 0
    else
        return 1
    fi
}

# Start pproxy
start_pproxy() {
    log "Starting pproxy on port $LOCAL_PROXY_PORT..."
    
    # Kill existing pproxy
    pkill -f "pproxy.*:$LOCAL_PROXY_PORT" 2>/dev/null || true
    sleep 1
    
    # Start pproxy in background
    nohup pproxy -l "http://:$LOCAL_PROXY_PORT" < /dev/null > "$HOME/pproxy.log" 2>&1 &
    sleep 2
    
    if check_pproxy; then
        log_success "pproxy started (PID: $(pgrep -f "pproxy.*:$LOCAL_PROXY_PORT"))"
        return 0
    else
        log_error "Failed to start pproxy"
        return 1
    fi
}

# Cek apakah SSH tunnel aktif
check_tunnel() {
    # Cek process SSH dengan port forwarding
    if pgrep -f "ssh.*$REMOTE_PROXY_PORT:127.0.0.1:$LOCAL_PROXY_PORT" > /dev/null; then
        # Cek apakah tunnel benar-benar bisa dipakai (test dari VPS)
        # Kita skip test ini karena butuh SSH ke VPS lagi
        return 0
    else
        return 1
    fi
}

# Start SSH tunnel
start_tunnel() {
    log "Starting SSH tunnel to $VPS_USER@$VPS_HOST:$REMOTE_PROXY_PORT..."
    
    # Kill existing tunnel
    pkill -f "ssh.*$REMOTE_PROXY_PORT:127.0.0.1:$LOCAL_PROXY_PORT" 2>/dev/null || true
    sleep 1
    
    # Start tunnel
    ssh -i "$SSH_KEY" \
        -f -N \
        -o StrictHostKeyChecking=no \
        -o ServerAliveInterval=30 \
        -o ServerAliveCountMax=3 \
        -o ExitOnForwardFailure=yes \
        -R "0.0.0.0:$REMOTE_PROXY_PORT:127.0.0.1:$LOCAL_PROXY_PORT" \
        "$VPS_USER@$VPS_HOST"
    
    sleep 2
    
    if check_tunnel; then
        log_success "SSH tunnel started (PID: $(pgrep -f "ssh.*$REMOTE_PROXY_PORT:127.0.0.1:$LOCAL_PROXY_PORT"))"
        return 0
    else
        log_error "Failed to start SSH tunnel"
        return 1
    fi
}

# Get current IP
get_current_ip() {
    # Coba beberapa service untuk get IP
    curl -s --max-time 5 https://api.ipify.org 2>/dev/null || \
    curl -s --max-time 5 https://ifconfig.me 2>/dev/null || \
    curl -s --max-time 5 https://icanhazip.com 2>/dev/null || \
    echo "unknown"
}

# Main loop
main() {
    log_success "=== Auto Phone Proxy Tunnel Started ==="
    log "VPS: $VPS_USER@$VPS_HOST"
    log "Local proxy port: $LOCAL_PROXY_PORT"
    log "Remote proxy port: $REMOTE_PROXY_PORT"
    log "Check interval: ${CHECK_INTERVAL}s"
    log "SSH key: $SSH_KEY"
    
    # Get initial IP
    CURRENT_IP=$(get_current_ip)
    log "Current IP: $CURRENT_IP"
    
    # Initial setup
    if ! check_pproxy; then
        start_pproxy || exit 1
    else
        log "pproxy already running (PID: $(pgrep -f "pproxy.*:$LOCAL_PROXY_PORT"))"
    fi
    
    if ! check_tunnel; then
        start_tunnel || exit 1
    else
        log "SSH tunnel already running (PID: $(pgrep -f "ssh.*$REMOTE_PROXY_PORT:127.0.0.1:$LOCAL_PROXY_PORT"))"
    fi
    
    log_success "Initial setup complete. Entering monitor loop..."
    echo ""
    
    # Monitor loop
    while true; do
        sleep "$CHECK_INTERVAL"
        
        # Check IP change
        NEW_IP=$(get_current_ip)
        if [ "$NEW_IP" != "$CURRENT_IP" ] && [ "$NEW_IP" != "unknown" ]; then
            log_warning "IP changed: $CURRENT_IP -> $NEW_IP"
            CURRENT_IP="$NEW_IP"
            
            # Restart tunnel on IP change
            log "Restarting tunnel due to IP change..."
            start_tunnel
        fi
        
        # Check pproxy
        if ! check_pproxy; then
            log_error "pproxy died, restarting..."
            start_pproxy
        fi
        
        # Check tunnel
        if ! check_tunnel; then
            log_error "SSH tunnel died, restarting..."
            start_tunnel
        fi
        
        # Heartbeat log setiap 5 menit
        if [ $(($(date +%s) % 300)) -lt "$CHECK_INTERVAL" ]; then
            log "Heartbeat: pproxy ✓ | tunnel ✓ | IP: $CURRENT_IP"
        fi
    done
}

# Trap untuk cleanup
cleanup() {
    log_warning "Received signal, cleaning up..."
    pkill -f "pproxy.*:$LOCAL_PROXY_PORT" 2>/dev/null || true
    pkill -f "ssh.*$REMOTE_PROXY_PORT:127.0.0.1:$LOCAL_PROXY_PORT" 2>/dev/null || true
    log_success "Cleanup complete. Exiting."
    exit 0
}

trap cleanup SIGINT SIGTERM

# Run
main
