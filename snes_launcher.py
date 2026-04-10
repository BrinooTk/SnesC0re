"""
BrunoRoque SNES Launcher
Sends snes.lua to PS5, uploads ROMs via built-in C FTP server.

  python source\\snes_launcher.py <PS5_IP>
  python source\\snes_launcher.py <PS5_IP> --roms-dir D:\\SNES
  python source\\snes_launcher.py <PS5_IP> --mode usb

Default ROM folder: ..\\compiled\\roms
"""

import argparse
import os
import socket
import struct
import subprocess
import sys
import threading
import time
from ftplib import FTP
from ftplib import error_perm

PAYLOAD_PORT = 9026
FTP_PORT = 1337
LOG_PORT = 9027
SAVE_PORT = 9028
SAVE_MAGIC = b"SSV1"
SAVE_HEADER = struct.Struct("<4sHI")
MAX_SAVE_SIZE = 0x20000


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


def recv_exact(sock, size, stop_event=None):
    chunks = []
    received = 0
    while received < size:
        try:
            chunk = sock.recv(size - received)
        except socket.timeout:
            if stop_event and stop_event.is_set():
                return None
            continue
        except OSError:
            return None
        if not chunk:
            return None
        chunks.append(chunk)
        received += len(chunk)
    return b"".join(chunks)


def sanitize_sync_name(name):
    safe = os.path.basename(name.replace("\\", "/").strip())
    if not safe or safe in {".", ".."}:
        return None
    if "\x00" in safe or "/" in safe or "\\" in safe:
        return None
    return safe


def start_save_server(save_dir, port=SAVE_PORT):
    stop_event = threading.Event()
    ready_event = threading.Event()
    state = {"error": None}
    os.makedirs(save_dir, exist_ok=True)

    def worker():
        server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        try:
            server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            server.bind(("", port))
            server.listen(1)
            server.settimeout(0.5)
            ready_event.set()
        except OSError as exc:
            state["error"] = exc
            ready_event.set()
            try:
                server.close()
            except OSError:
                pass
            return

        while not stop_event.is_set():
            try:
                conn, addr = server.accept()
            except socket.timeout:
                continue
            except OSError:
                break

            print(f"  Save sync connected: {addr[0]}:{addr[1]}")
            with conn:
                conn.settimeout(0.5)
                while not stop_event.is_set():
                    header = recv_exact(conn, SAVE_HEADER.size, stop_event)
                    if not header:
                        break
                    magic, name_len, data_size = SAVE_HEADER.unpack(header)
                    if magic != SAVE_MAGIC or name_len == 0 or name_len > 240:
                        print("  [WARN] Invalid save sync header")
                        break
                    if data_size <= 0 or data_size > MAX_SAVE_SIZE:
                        print(f"  [WARN] Invalid save sync size: {data_size}")
                        break

                    name_data = recv_exact(conn, name_len, stop_event)
                    payload = recv_exact(conn, data_size, stop_event)
                    if name_data is None or payload is None:
                        break

                    name = sanitize_sync_name(name_data.decode("utf-8", errors="replace"))
                    if not name:
                        print("  [WARN] Invalid save filename from sync channel")
                        break

                    out_path = os.path.join(save_dir, name)
                    tmp_path = out_path + ".part"
                    try:
                        with open(tmp_path, "wb") as f:
                            f.write(payload)
                        if os.path.exists(out_path):
                            os.remove(out_path)
                        os.replace(tmp_path, out_path)
                        print(f"  Save synced -> {out_path}")
                    finally:
                        if os.path.exists(tmp_path):
                            try:
                                os.remove(tmp_path)
                            except OSError:
                                pass

        try:
            server.close()
        except OSError:
            pass

    thread = threading.Thread(target=worker, daemon=False)
    thread.start()
    ready_event.wait(2.0)
    return stop_event, thread, state["error"]


def ensure_launcher(base_dir, launcher_path, pc_ip=None):
    project_root = os.path.dirname(base_dir)
    compiled_dir = os.path.join(project_root, "compiled")
    bin_path = os.path.join(compiled_dir, "snes_emu.bin")
    gen_script = os.path.join(base_dir, "make_snes_lua.py")

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
    cmd = [sys.executable, gen_script, "--bin", bin_path, "--out", launcher_path]
    if pc_ip:
        cmd += ["--pc-ip", pc_ip]
    subprocess.run(cmd, check=True)


def scan_files(base_dir, extensions):
    if not os.path.isdir(base_dir):
        return []
    return sorted([
        os.path.join(base_dir, f) for f in os.listdir(base_dir)
        if os.path.splitext(f)[1].lower() in extensions
        and os.path.isfile(os.path.join(base_dir, f))
    ])


def scan_roms(roms_dir, extensions):
    return scan_files(roms_dir, extensions)


def scan_saves(saves_dir):
    return scan_files(saves_dir, {".sav"})


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


def open_ftp_session(host, port=FTP_PORT, timeout=15):
    ftp = FTP()
    ftp.connect(host, port, timeout=timeout)
    ftp.login("anonymous", "")
    ftp.sendcmd("TYPE I")
    return ftp


def send_site_exit(ftp):
    try:
        ftp.sendcmd("SITE EXIT")
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


def upload_files(ftp, paths, skip_same_size=True):
    total = len(paths)
    total_size = sum(os.path.getsize(path) for path in paths)
    print(f"  {total} files ({total_size / 1048576:.1f} MB)")

    existing = set()
    try:
        existing = set(ftp.nlst())
    except Exception:
        pass

    to_upload = 0
    for path in paths:
        fn = os.path.basename(path)
        sz = os.path.getsize(path)
        if skip_same_size and fn in existing:
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

    for i, path in enumerate(paths, 1):
        fn = os.path.basename(path)
        sz = os.path.getsize(path)

        if skip_same_size and fn in existing:
            try:
                if ftp.size(fn) == sz:
                    skipped += 1
                    if skipped % 50 == 0 or i == total:
                        print(f"  [{i * 100 // total:3d}%] Skipped {fn}")
                    continue
            except Exception:
                pass

        try:
            with open(path, "rb") as f:
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


def upload_roms(ftp, roms):
    upload_files(ftp, roms, skip_same_size=True)


def upload_saves(ftp, saves):
    upload_files(ftp, saves, skip_same_size=False)


def main():
    parser = argparse.ArgumentParser(description="BrunoRoque SNES Launcher")
    parser.add_argument("ps5_ip", help="PS5 IP address")
    parser.add_argument("--roms-dir", default=None)
    parser.add_argument("--saves-dir", default=None)
    parser.add_argument("--launcher", default=None, help="Lua launcher (default: ../compiled/snes.lua)")
    parser.add_argument("--mode", choices=["ftp", "usb"], default="ftp",
                        help="ftp = upload ROMs from PC, usb = search ROMs on pendrive/HD (default: ftp)")
    parser.add_argument("--skip-upload", action="store_true")
    parser.add_argument("--ext", nargs="+", default=[".sfc", ".smc"])
    parser.add_argument("--ftp-wait", type=int, default=10,
                        help="Max seconds to wait for FTP server (default: 10)")
    args = parser.parse_args()

    base = os.path.dirname(os.path.abspath(__file__))
    project_root = os.path.dirname(base)
    compiled_dir = os.path.join(project_root, "compiled")
    roms_dir = args.roms_dir or os.path.join(compiled_dir, "roms")
    saves_dir = args.saves_dir or os.path.join(compiled_dir, "saves")
    launcher = args.launcher or os.path.join(compiled_dir, "snes.lua")
    extensions = {e if e.startswith(".") else "." + e for e in args.ext}
    os.makedirs(compiled_dir, exist_ok=True)
    os.makedirs(roms_dir, exist_ok=True)
    os.makedirs(saves_dir, exist_ok=True)
    upload_mode = "usb" if args.skip_upload else args.mode
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
    print(f"  Saves: {saves_dir}")
    print(f"  Mode: {upload_mode.upper()}")
    if local_ip:
        print(f"  PC IP for logs: {local_ip}:{LOG_PORT}")
        print(f"  PC IP for saves: {local_ip}:{SAVE_PORT}")
    print()

    if not os.path.isfile(launcher):
        print(f"  [FAIL] Not found: {launcher}")
        print("  Build snes_emu.bin and run: python make_snes_lua.py")
        return

    session_log = os.path.join(compiled_dir, "snes_session.log")
    stop_logs, log_thread = start_udp_logger(session_log)
    stop_saves = None
    save_thread = None
    if local_ip:
        stop_saves, save_thread, save_err = start_save_server(saves_dir)
        if save_err:
            print(f"  [WARN] Save sync listener unavailable on {SAVE_PORT}: {save_err}")
            stop_saves = None
            save_thread = None
    else:
        print("  [WARN] Save sync disabled because local IP could not be detected")

    roms = []
    if upload_mode == "ftp":
        print("[1] Scanning ROMs...")
        roms = scan_roms(roms_dir, extensions)
        if not roms:
            print(f"  No files in {roms_dir}")
            print("  Will launch emulator without uploading.")
        else:
            print(f"  Found {len(roms)} ROM(s)")
        print()
    else:
        print("[1] USB mode selected")
        print("  ROM upload disabled; emulator will search pendrive/HD, FTP cache and /savedata0/")
        print()

    print("[2] Scanning local saves...")
    saves = scan_saves(saves_dir)
    if saves:
        print(f"  Found {len(saves)} save file(s)")
    else:
        print(f"  No save files in {saves_dir}")
    print()

    print("[3] Launching emulator...")
    send_payload(args.ps5_ip, launcher)
    print()

    print("[4] Waiting for FTP server on PS5...")
    if wait_for_ftp(args.ps5_ip, FTP_PORT, args.ftp_wait):
        print("  FTP server ready")
        diag_copy = os.path.join(compiled_dir, "snes_diag_last.log")
        print("  Checking previous crash log...")
        fetch_diag_log(args.ps5_ip, FTP_PORT, diag_copy)
        ftp = None
        try:
            ftp = open_ftp_session(args.ps5_ip, FTP_PORT, timeout=15)
            if roms and upload_mode == "ftp":
                print()
                print("[5] Uploading ROMs...")
                upload_roms(ftp, roms)
            if saves:
                print()
                print("[6] Uploading saves...")
                upload_saves(ftp, saves)
            print("  Releasing FTP server...")
            send_site_exit(ftp)
        except Exception as exc:
            print(f"  FTP error: {exc}")
            if ftp:
                send_site_exit(ftp)
        finally:
            if ftp:
                try:
                    ftp.quit()
                except Exception:
                    pass
    else:
        print(f"  FTP server not responding after {args.ftp_wait}s")
        print()

    print("Done!")
    print("  Waiting for PS5 runtime logs and live save sync. Press Ctrl+C to exit.")

    try:
        while True:
            time.sleep(0.2)
    except KeyboardInterrupt:
        print()
        print("Stopping log listener...")
    finally:
        stop_logs.set()
        log_thread.join(timeout=2)
        if stop_saves and save_thread:
            stop_saves.set()
            save_thread.join(timeout=2)


if __name__ == "__main__":
    main()
