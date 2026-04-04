"""
BrunoRoque SNES Launcher
Sends snes.lua to PS5, uploads ROMs via built-in C FTP server.

  python snes_launcher.py <PS5_IP>
  python snes_launcher.py <PS5_IP> --roms-dir D:\\SNES
  python snes_launcher.py <PS5_IP> --skip-upload

Default ROM folder: compiled\\roms
"""

import argparse
import os
import socket
import subprocess
import sys
import threading
import time
from ftplib import FTP
from ftplib import error_perm

PAYLOAD_PORT = 9026
FTP_PORT = 1337
LOG_PORT = 9027


def send_payload(host, filepath, port=PAYLOAD_PORT):
    with open(filepath, "rb") as f:
        data = f.read()
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.settimeout(10)
    sock.connect((host, port))
    sock.sendall(data)
    sock.close()
    print(f"  Sent {os.path.basename(filepath)} ({len(data):,} bytes)")


def guess_local_ip(host):
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        sock.connect((host, 1))
        return sock.getsockname()[0]
    finally:
        sock.close()


def start_udp_logger(log_path, port=LOG_PORT):
    stop_event = threading.Event()

    def worker():
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        log_file = None
        try:
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            sock.bind(("", port))
            sock.settimeout(0.5)
            log_file = open(log_path, "w", encoding="utf-8", buffering=1)
        except OSError as exc:
            print(f"  [WARN] UDP log listener unavailable on {port}: {exc}")
            if log_file:
                log_file.close()
            return

        print(f"  UDP logs listening on {port}")
        print(f"  Session log: {log_path}")
        while not stop_event.is_set():
            try:
                data, addr = sock.recvfrom(2048)
            except socket.timeout:
                continue
            except OSError:
                break
            msg = data.decode("utf-8", errors="replace").strip()
            if msg:
                line = f"[PS5 {addr[0]}] {msg}"
                print(f"  {line}")
                if log_file:
                    log_file.write(line + "\n")

        try:
            sock.close()
        except OSError:
            pass
        if log_file:
            log_file.close()

    thread = threading.Thread(target=worker, daemon=False)
    thread.start()
    return stop_event, thread


def ensure_launcher(base_dir, launcher_path, pc_ip=None):
    compiled_dir = os.path.join(base_dir, "compiled")
    bin_path = os.path.join(compiled_dir, "snes_emu.bin")
    gen_script = os.path.join(base_dir, "make_snes_lua.py")
    template_path = os.path.join(base_dir, "snes_template.lua")

    if not os.path.isfile(bin_path):
        return

    needs_regen = not os.path.isfile(launcher_path)
    if not needs_regen:
        needs_regen = os.path.getmtime(bin_path) > os.path.getmtime(launcher_path)

    if pc_ip:
        needs_regen = True

    if not needs_regen:
        return

    print("  Regenerating snes.lua from snes_emu.bin...")
    cmd = [
        sys.executable,
        gen_script,
        "--bin", bin_path,
        "--template", template_path,
        "--out", launcher_path,
    ]
    if pc_ip:
        cmd += ["--pc-ip", pc_ip]
    subprocess.run(cmd, check=True)


def scan_roms(roms_dir, extensions):
    if not os.path.isdir(roms_dir):
        return []
    return sorted([
        os.path.join(roms_dir, f) for f in os.listdir(roms_dir)
        if os.path.splitext(f)[1].lower() in extensions
        and os.path.isfile(os.path.join(roms_dir, f))
    ])


def wait_for_ftp(host, port, timeout=20):
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.settimeout(timeout)
    try:
        sock.connect((host, port))
        banner = sock.recv(256)
        sock.close()
        return b"220" in banner
    except Exception:
        try:
            sock.close()
        except Exception:
            pass
        return False


def send_site_exit(host, port):
    try:
        ftp = FTP()
        ftp.connect(host, port, timeout=10)
        ftp.login("anonymous", "")
        ftp.sendcmd("SITE EXIT")
        ftp.quit()
        print("  FTP server released")
    except Exception as exc:
        print(f"  [WARN] Could not release FTP: {exc}")


def fetch_diag_log(host, port, out_path, remote_name="snes_diag.log"):
    ftp = FTP()
    tmp_path = out_path + ".part"
    try:
        ftp.connect(host, port, timeout=10)
        ftp.login("anonymous", "")
        try:
            size = ftp.size(remote_name)
        except error_perm as exc:
            msg = str(exc)
            if "550" in msg:
                print(f"  No previous {remote_name} on PS5")
                return False
            raise

        if size is not None and size <= 0:
            print(f"  Previous {remote_name} exists but is empty")
            return False

        with open(tmp_path, "wb") as f:
            ftp.retrbinary(f"RETR {remote_name}", f.write, blocksize=4096)
        if os.path.exists(out_path):
            os.remove(out_path)
        os.replace(tmp_path, out_path)
        print(f"  Retrieved {remote_name} -> {out_path}")
        return True
    except error_perm as exc:
        msg = str(exc)
        if "550" not in msg:
            print(f"  [WARN] Could not fetch {remote_name}: {exc}")
    except Exception as exc:
        print(f"  [WARN] Could not fetch {remote_name}: {exc}")
    finally:
        if os.path.exists(tmp_path):
            try:
                os.remove(tmp_path)
            except OSError:
                pass
        try:
            ftp.quit()
        except Exception:
            pass
    return False


def upload_roms(host, roms, port=FTP_PORT):
    total = len(roms)
    total_size = sum(os.path.getsize(r) for r in roms)
    print(f"  {total} files ({total_size / 1048576:.1f} MB)")

    ftp = FTP()
    ftp.connect(host, port, timeout=15)
    ftp.login("anonymous", "")
    ftp.sendcmd("TYPE I")

    existing = set()
    try:
        existing = set(ftp.nlst())
    except Exception:
        pass

    to_upload = 0
    for rom_path in roms:
        fn = os.path.basename(rom_path)
        sz = os.path.getsize(rom_path)
        if fn in existing:
            try:
                if ftp.size(fn) == sz:
                    continue
            except Exception:
                pass
        to_upload += 1

    try:
        ftp.sendcmd(f"SITE TOTAL {to_upload}")
    except Exception:
        pass

    uploaded = 0
    skipped = 0
    bytes_sent = 0
    t0 = time.time()

    for i, rom_path in enumerate(roms, 1):
        fn = os.path.basename(rom_path)
        sz = os.path.getsize(rom_path)

        if fn in existing:
            try:
                if ftp.size(fn) == sz:
                    skipped += 1
                    if skipped % 50 == 0 or i == total:
                        print(f"  [{i * 100 // total:3d}%] Skipped {fn}")
                    continue
            except Exception:
                pass

        try:
            with open(rom_path, "rb") as f:
                ftp.storbinary(f"STOR {fn}", f, blocksize=8192)
            uploaded += 1
            bytes_sent += sz
        except Exception as exc:
            print(f"  [ERR] {fn}: {exc}")
            continue

        if uploaded <= 5 or uploaded == to_upload or uploaded % 25 == 0:
            elapsed = time.time() - t0
            speed = bytes_sent / elapsed / 1024 if elapsed > 0 else 0
            pct = i * 100 // total
            print(f"  {pct:3d}% | {uploaded}/{to_upload} | {speed:.0f} KB/s | {fn}")

    elapsed = time.time() - t0
    print(f"  Done: {uploaded} uploaded, {skipped} skipped "
          f"({bytes_sent / 1048576:.1f} MB in {elapsed:.1f}s)")

    try:
        ftp.sendcmd("SITE EXIT")
    except Exception:
        pass
    try:
        ftp.quit()
    except Exception:
        pass


def main():
    parser = argparse.ArgumentParser(description="BrunoRoque SNES Launcher")
    parser.add_argument("ps5_ip", help="PS5 IP address")
    parser.add_argument("--roms-dir", default=None)
    parser.add_argument("--launcher", default=None, help="Lua launcher (default: compiled/snes.lua)")
    parser.add_argument("--skip-upload", action="store_true")
    parser.add_argument("--ext", nargs="+", default=[".sfc", ".smc"])
    parser.add_argument("--ftp-wait", type=int, default=10,
                        help="Max seconds to wait for FTP server (default: 10)")
    args = parser.parse_args()

    base = os.path.dirname(os.path.abspath(__file__))
    compiled_dir = os.path.join(base, "compiled")
    roms_dir = args.roms_dir or os.path.join(compiled_dir, "roms")
    launcher = args.launcher or os.path.join(compiled_dir, "snes.lua")
    extensions = {e if e.startswith(".") else "." + e for e in args.ext}
    os.makedirs(compiled_dir, exist_ok=True)
    os.makedirs(roms_dir, exist_ok=True)
    local_ip = None
    try:
        local_ip = guess_local_ip(args.ps5_ip)
    except OSError as exc:
        print(f"  [WARN] Could not detect local IP for UDP logs: {exc}")

    try:
        ensure_launcher(base, launcher, local_ip)
    except Exception as exc:
        print(f"  [WARN] Could not regenerate launcher: {exc}")

    print("BrunoRoque SNES Launcher")
    print(f"  PS5: {args.ps5_ip}  ROMs: {roms_dir}")
    if local_ip:
        print(f"  PC IP for logs: {local_ip}:{LOG_PORT}")
    print()

    session_log = os.path.join(compiled_dir, "snes_session.log")
    stop_logs, log_thread = start_udp_logger(session_log)

    roms = []
    if not args.skip_upload:
        print("[1] Scanning ROMs...")
        roms = scan_roms(roms_dir, extensions)
        if not roms:
            print(f"  No files in {roms_dir}")
            print("  Will launch emulator without uploading.")
        else:
            print(f"  Found {len(roms)} ROM(s)")
        print()

    print("[2] Launching emulator...")
    if not os.path.isfile(launcher):
        print(f"  [FAIL] Not found: {launcher}")
        print("  Build snes_emu.bin and run: python make_snes_lua.py")
        return
    send_payload(args.ps5_ip, launcher)
    print()

    print("[3] Waiting for FTP server on PS5...")
    if wait_for_ftp(args.ps5_ip, FTP_PORT, args.ftp_wait):
        print("  FTP server ready")
        diag_copy = os.path.join(compiled_dir, "snes_diag_last.log")
        print("  Checking previous crash log...")
        fetch_diag_log(args.ps5_ip, FTP_PORT, diag_copy)
        if roms and not args.skip_upload:
            print()
            print("[4] Uploading ROMs...")
            try:
                upload_roms(args.ps5_ip, roms)
            except Exception as exc:
                print(f"  FTP error: {exc}")
                send_site_exit(args.ps5_ip, FTP_PORT)
        else:
            print("  Releasing FTP server...")
            send_site_exit(args.ps5_ip, FTP_PORT)
    else:
        print(f"  FTP server not responding after {args.ftp_wait}s")
        print()

    print("Done!")
    print("  Waiting for PS5 runtime logs. Press Ctrl+C to exit.")

    try:
        while True:
            time.sleep(0.2)
    except KeyboardInterrupt:
        print()
        print("Stopping log listener...")
    finally:
        stop_logs.set()
        log_thread.join(timeout=2)


if __name__ == "__main__":
    main()
