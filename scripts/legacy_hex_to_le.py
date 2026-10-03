#!/usr/bin/env python3
"""One-time conversion of the legacy program image to little-endian.

The original instruction_mem was big-endian: the byte at the lowest
address held instruction bits [31:24]. The core is now little-endian
(RISC-V), so each 4-byte instruction in the one-byte-per-line image is
reversed. Run once on tests/legacy/program.hex (in place); running it
again would undo the conversion, so it refuses unless --force is given.

    python3 scripts/legacy_hex_to_le.py tests/legacy/program.hex
"""
import sys

path = sys.argv[1]
lines = [l.strip() for l in open(path) if l.strip()]
# Sanity check: the first legacy instruction is addi x1,x0,100 = 0x06400093.
first = "".join(lines[0:4]).lower()
if first == "06400093":
    pass                                  # big-endian: convert
elif first == "93004006" and "--force" not in sys.argv:
    sys.exit(f"{path} is already little-endian; not converting again")
assert len(lines) % 4 == 0, "image is not a whole number of 32-bit words"
out = []
for i in range(0, len(lines), 4):
    out += reversed(lines[i:i + 4])
open(path, "w").write("\n".join(out) + "\n")
print(f"converted {len(lines) // 4} words in {path} to little-endian")
