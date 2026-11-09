#!/usr/bin/env python3
"""Create and validate a standard 80-track, double-sided TR-DOS image."""
import argparse
from pathlib import Path
SECTOR, SPT, TRACKS = 256, 16, 160
IMAGE_SIZE = SECTOR * SPT * TRACKS
LOAD_ADDRESS = 0x6000
TOK_LOAD, TOK_CODE, TOK_RANDOMIZE, TOK_USR, TOK_VAL = 0xEF, 0xAF, 0xF9, 0xC0, 0xB0

def le16(n):
    if not 0 <= n <= 0xFFFF:
        raise ValueError("16-bit value out of range")
    return bytes((n & 255, n >> 8))

def basic_loader():
    # Spectrum BASIC numeric source is kept inside VAL strings to avoid
    # malformed numeric-literal markers in the tokenized program.
    # OUT 239,value writes each progress character to ATM debug port #EF.
    # No CLEAR is used, so the current RAMTOP is left untouched.
    address = bytes([TOK_VAL]) + b' "24576"'

    def debug_text(message):
        statements = []
        for value in message.encode("ascii"):
            statements.append(bytes([TOK_OUT]) + b' ' +
                              bytes([TOK_VAL]) + b' "239",' +
                              bytes([TOK_VAL]) + b' "' + str(value).encode("ascii") + b'"')
        return b":".join(statements)

    body = (debug_text("[P127] BASIC START\r\n") + b":" +
            bytes([TOK_LOAD]) + b' "P127BOOT" ' + bytes([TOK_CODE]) +
            b" " + address + b":" +
            debug_text("[P127] LOAD OK\r\n") + b":" +
            debug_text("[P127] CALL 6000\r\n") + b":" +
            bytes([TOK_RANDOMIZE]) + b" " + bytes([TOK_USR]) + b" " + address)
    line = bytes([0, 10]) + le16(len(body) + 1) + body + b"\x0d"
    area = line + b"\x80"
    return area + b"\xaa\x0a\x00", len(area)

def offset(track, sector):
    if not 0 <= track < TRACKS or not 0 <= sector < SPT:
        raise ValueError("TR-DOS track/sector out of range")
    return (track * SPT + sector) * SECTOR

def build_trd(code, label="P127DISK"):
    if not code:
        raise ValueError("Stage-2 code is empty")
    if len(code) > 0xFFFF or LOAD_ADDRESS + len(code) > 0x10000:
        raise ValueError("Stage-2 code does not fit the 16-bit load window")
    if not label.isascii() or len(label) > 8:
        raise ValueError("Disk label must be at most 8 ASCII characters")
    image = bytearray(IMAGE_SIZE)
    track, sector, count, used = 1, 0, 0, 0

    def add(name, kind, p1, p2, payload):
        nonlocal track, sector, count, used
        nsec = (len(payload) + SECTOR - 1) // SECTOR
        if not 1 <= nsec <= 255:
            raise ValueError("Invalid TR-DOS file sector count")
        st, ss = track, sector
        padded = payload + bytes(nsec * SECTOR - len(payload))
        for i in range(nsec):
            absolute = st * SPT + ss + i
            t, s = divmod(absolute, SPT)
            pos = offset(t, s)
            image[pos:pos + SECTOR] = padded[i * SECTOR:(i + 1) * SECTOR]
        entry = bytearray(16)
        entry[:8] = name.encode("ascii").ljust(8, b" ")
        entry[8] = kind
        entry[9:11], entry[11:13] = le16(p1), le16(p2)
        entry[13], entry[14], entry[15] = nsec, ss, st
        image[count * 16:(count + 1) * 16] = entry
        track, sector = divmod(st * SPT + ss + nsec, SPT)
        count += 1
        used += nsec

    basic, basic_len = basic_loader()
    add("boot", ord("B"), 10, basic_len, basic)
    add("P127BOOT", ord("C"), LOAD_ADDRESS, len(code), code)
    info = offset(0, 8)
    image[info + 225] = sector
    image[info + 226] = track
    image[info + 227] = 0x16
    image[info + 228] = count
    image[info + 229:info + 231] = le16(TRACKS * SPT - SPT - used)
    image[info + 231] = 0x10
    image[info + 244] = 0
    image[info + 245:info + 253] = label.upper().encode("ascii").ljust(8, b" ")
    result = bytes(image)
    verify_trd(result, code)
    return result

def verify_trd(image, expected_code=None):
    if len(image) != IMAGE_SIZE:
        raise ValueError("Wrong TR-DOS image size")
    info = offset(0, 8)
    if image[info + 227] != 0x16 or image[info + 228] != 2 or image[info + 231] != 0x10:
        raise ValueError("Invalid TR-DOS disk descriptor")
    boot, code = image[:16], image[16:32]
    if boot[:9] != b"boot    B" or code[:9] != b"P127BOOTC":
        raise ValueError("Invalid boot directory entry (expected 'boot    B')")
    if int.from_bytes(boot[9:11], "little") != 10:
        raise ValueError("Wrong BASIC autostart line (expected 10)")
    if int.from_bytes(boot[11:13], "little") == 0:
        raise ValueError("Empty BASIC loader file")
    if int.from_bytes(code[9:11], "little") != LOAD_ADDRESS:
        raise ValueError("Wrong P127BOOT load address")
    if expected_code is not None:
        n = int.from_bytes(code[11:13], "little")
        pos = offset(code[15], code[14])
        if image[pos:pos + n] != expected_code:
            raise ValueError("Stored code differs from assembled code")
    n = int.from_bytes(boot[11:13], "little")
    pos = offset(boot[15], boot[14])
    basic = image[pos:pos + n + 3]
    if not basic.endswith(b"\x80\xaa\x0a\x00"):
        raise ValueError("Invalid BASIC/TR-DOS run-line terminator")
    for token in (TOK_LOAD, TOK_CODE, TOK_RANDOMIZE, TOK_USR, TOK_VAL):
        if token not in basic:
            raise ValueError("BASIC loader token missing")
    if 0xFD in basic:
        raise ValueError("BASIC loader must not execute CLEAR/RAMTOP")

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--code", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--label", default="P127DISK")
    args = parser.parse_args()
    code = args.code.read_bytes()
    image = build_trd(code, args.label)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(image)
    verify_trd(args.output.read_bytes(), code)
    print("[P127 TRD] FORMAT=80T_DOUBLE_SIDED")
    print(f"[P127 TRD] FILES=2 CODE_BYTES={len(code)} IMAGE_BYTES={len(image)}")
    print("[P127 TRD] BOOT_FILENAME=boot TYPE=B")
    print("[P127 TRD] BASIC_AUTOSTART_LINE=10")
    print("[P127 TRD] BASIC_ADDRESS=VAL_STRING_24576")
    print(f"[P127 TRD] OUTPUT={args.output}")
    print("[P127 TRD] VERIFY OK")

if __name__ == "__main__":
    main()
