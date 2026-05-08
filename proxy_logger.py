#!/usr/bin/env python3
"""
HTTP Proxy dengan logging real-time untuk debugging.
Menampilkan semua request yang lewat dengan timestamp, method, URL, dan response status.

Usage di Termux:
    python proxy_logger.py

Lalu di VPS, test dengan:
    curl -x http://127.0.0.1:18080 https://api.ipify.org
"""

import socket
import threading
import time
from datetime import datetime
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import urlparse
import ssl
import select

# Konfigurasi
PROXY_HOST = '0.0.0.0'
PROXY_PORT = 8080

# ANSI color codes untuk terminal
class Colors:
    HEADER = '\033[95m'
    OKBLUE = '\033[94m'
    OKCYAN = '\033[96m'
    OKGREEN = '\033[92m'
    WARNING = '\033[93m'
    FAIL = '\033[91m'
    ENDC = '\033[0m'
    BOLD = '\033[1m'
    UNDERLINE = '\033[4m'

def log(message, color=Colors.ENDC):
    """Print dengan timestamp dan warna"""
    timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S.%f')[:-3]
    print(f"{color}[{timestamp}] {message}{Colors.ENDC}", flush=True)

class ProxyHTTPRequestHandler(BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'
    timeout = 30
    
    def log_message(self, format, *args):
        """Override default logging"""
        pass  # Kita pakai custom logging
    
    def do_CONNECT(self):
        """Handle HTTPS CONNECT method"""
        log(f"🔐 CONNECT {self.path}", Colors.OKCYAN)
        
        try:
            # Parse host dan port
            host, port = self.path.split(':')
            port = int(port)
            
            # Connect ke target server
            target_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            target_socket.settimeout(self.timeout)
            target_socket.connect((host, port))
            
            # Send 200 Connection Established
            self.send_response(200, 'Connection Established')
            self.end_headers()
            
            log(f"✅ Tunnel established to {host}:{port}", Colors.OKGREEN)
            
            # Relay data bidirectional
            self._relay_data(self.connection, target_socket, host)
            
        except Exception as e:
            log(f"❌ CONNECT error: {e}", Colors.FAIL)
            self.send_error(502, f"Bad Gateway: {e}")
    
    def do_GET(self):
        """Handle HTTP GET"""
        self._handle_http_request()
    
    def do_POST(self):
        """Handle HTTP POST"""
        self._handle_http_request()
    
    def do_HEAD(self):
        """Handle HTTP HEAD"""
        self._handle_http_request()
    
    def do_PUT(self):
        """Handle HTTP PUT"""
        self._handle_http_request()
    
    def do_DELETE(self):
        """Handle HTTP DELETE"""
        self._handle_http_request()
    
    def _handle_http_request(self):
        """Handle regular HTTP requests"""
        log(f"📤 {self.command} {self.path}", Colors.OKBLUE)
        
        try:
            # Parse URL
            parsed = urlparse(self.path)
            host = parsed.hostname
            port = parsed.port or 80
            path = parsed.path or '/'
            if parsed.query:
                path += f'?{parsed.query}'
            
            # Connect ke target
            target_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            target_socket.settimeout(self.timeout)
            target_socket.connect((host, port))
            
            # Build request
            request_line = f"{self.command} {path} HTTP/1.1\r\n"
            headers = f"Host: {host}\r\n"
            
            # Copy headers (skip proxy-specific ones)
            skip_headers = {'proxy-connection', 'connection'}
            for header, value in self.headers.items():
                if header.lower() not in skip_headers:
                    headers += f"{header}: {value}\r\n"
            
            headers += "Connection: close\r\n\r\n"
            
            # Send request
            full_request = request_line + headers
            target_socket.sendall(full_request.encode('utf-8'))
            
            # Read body if present
            content_length = int(self.headers.get('Content-Length', 0))
            if content_length > 0:
                body = self.rfile.read(content_length)
                target_socket.sendall(body)
                log(f"  📦 Sent {content_length} bytes body", Colors.WARNING)
            
            # Read response
            response_data = b''
            while True:
                chunk = target_socket.recv(4096)
                if not chunk:
                    break
                response_data += chunk
            
            target_socket.close()
            
            # Parse response status
            response_lines = response_data.split(b'\r\n', 1)
            if response_lines:
                status_line = response_lines[0].decode('utf-8', errors='ignore')
                log(f"📥 Response: {status_line}", Colors.OKGREEN)
            
            # Send response back to client
            self.wfile.write(response_data)
            
        except Exception as e:
            log(f"❌ HTTP error: {e}", Colors.FAIL)
            self.send_error(502, f"Bad Gateway: {e}")
    
    def _relay_data(self, client_socket, target_socket, host):
        """Relay data between client and target (for CONNECT)"""
        client_socket.setblocking(False)
        target_socket.setblocking(False)
        
        bytes_sent = 0
        bytes_received = 0
        
        try:
            while True:
                # Check which sockets are ready
                readable, _, exceptional = select.select(
                    [client_socket, target_socket],
                    [],
                    [client_socket, target_socket],
                    1.0
                )
                
                if exceptional:
                    break
                
                # Client -> Target
                if client_socket in readable:
                    try:
                        data = client_socket.recv(8192)
                        if not data:
                            break
                        target_socket.sendall(data)
                        bytes_sent += len(data)
                    except (socket.error, OSError):
                        break
                
                # Target -> Client
                if target_socket in readable:
                    try:
                        data = target_socket.recv(8192)
                        if not data:
                            break
                        client_socket.sendall(data)
                        bytes_received += len(data)
                    except (socket.error, OSError):
                        break
        
        except Exception as e:
            log(f"⚠️  Relay error: {e}", Colors.WARNING)
        
        finally:
            log(f"🔌 Tunnel closed to {host} (↑{bytes_sent} ↓{bytes_received} bytes)", Colors.WARNING)
            try:
                target_socket.close()
            except:
                pass

def run_proxy():
    """Start proxy server"""
    server = HTTPServer((PROXY_HOST, PROXY_PORT), ProxyHTTPRequestHandler)
    
    log(f"🚀 Proxy server started on {PROXY_HOST}:{PROXY_PORT}", Colors.BOLD + Colors.OKGREEN)
    log(f"📊 Logging all requests in real-time...", Colors.HEADER)
    log(f"", Colors.ENDC)
    
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        log(f"\n🛑 Shutting down proxy server...", Colors.WARNING)
        server.shutdown()

if __name__ == '__main__':
    run_proxy()
