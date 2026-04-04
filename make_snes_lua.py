import argparse
import os
import re


def bin_to_hex(path):
    with open(path, "rb") as f:
        data = f.read()
    return " ".join(f"{b:02X}" for b in data)

def calc_jit_size(bin_size):
    size = 0x10000
    while size < bin_size:
        size <<= 1
    return size


def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    project_root = script_dir
    compiled_dir = os.path.join(project_root, "compiled")
    template_path = os.path.join(project_root, "snes_template.lua")

    parser = argparse.ArgumentParser(description="Generate compiled/snes.lua from compiled/snes_emu.bin")
    parser.add_argument("--bin", default=os.path.join(compiled_dir, "snes_emu.bin"), help="Path to snes_emu.bin")
    parser.add_argument("--template", default=template_path, help="Lua template to use as a base")
    parser.add_argument("--out", default=os.path.join(compiled_dir, "snes.lua"), help="Output lua file")
    parser.add_argument("--pc-ip", default=None, help="Override PC_IP inside the Lua launcher")
    args = parser.parse_args()

    if not os.path.isfile(args.bin):
        raise SystemExit(f"Missing binary: {args.bin}")
    if not os.path.isfile(args.template):
        raise SystemExit(f"Missing template: {args.template}")

    bin_size = os.path.getsize(args.bin)
    payload_hex = bin_to_hex(args.bin)
    jit_size = calc_jit_size(bin_size)

    with open(args.template, "r", encoding="utf-8", errors="replace") as f:
        text = f.read()

    updated = re.sub(r'local sc = ".*?"', f'local sc = "{payload_hex}"', text, count=1, flags=re.S)
    updated = re.sub(r'local JIT_SIZE = 0x[0-9A-Fa-f]+',
                     f'local JIT_SIZE = 0x{jit_size:X}',
                     updated, count=1)
    if args.pc_ip:
        updated = re.sub(r'local PC_IP\s*=\s*"[^"]+"',
                         f'local PC_IP    = "{args.pc_ip}"',
                         updated, count=1)
    updated = updated.replace("-- BrunoRoque NES EMU", "-- BrunoRoque SNES EMU")
    updated = updated.replace('ulog("=== BrunoRoque NES EMU")',
                              'ulog("=== BrunoRoque SNES EMU")')
    updated = updated.replace('<title>BrunoRoque NES</title>',
                              '<title>BrunoRoque SNES</title>')
    updated = updated.replace('send_notification("BrunoRoque NES EMU\\nhttp://" .. current_ip .. ":" .. WEB_PORT)',
                              'send_notification("BrunoRoque SNES EMU\\nhttp://" .. current_ip .. ":" .. WEB_PORT)')
    updated = updated.replace(
        'local frames = read32(ext+0x10)\nulog("Done! frames=" .. frames)\nsend_notification("NES done " .. frames .. "f")',
        'local status = read64(ext+0x00)\n'
        'local step = read64(ext+0x08)\n'
        'local frames = read32(ext+0x10)\n'
        'ulog("Done! status=" .. status .. " step=" .. step .. " frames=" .. frames)\n'
        'send_notification("BrunoRoque SNES done\\nstatus=" .. status .. " step=" .. step .. " frames=" .. frames)'
    )

    out_dir = os.path.dirname(os.path.abspath(args.out))
    if out_dir:
        os.makedirs(out_dir, exist_ok=True)

    with open(args.out, "w", encoding="utf-8", newline="\n") as f:
        f.write(updated)

    print(f"Wrote {args.out} with JIT_SIZE=0x{jit_size:X} for {bin_size} bytes")


if __name__ == "__main__":
    main()
