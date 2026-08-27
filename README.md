# FPGA Matrix Multiplier Accelerator

An 8×8 fixed-point (Q8.8) matrix multiplier accelerator, designed in SystemVerilog, integrated into a Terasic DE10-Standard's HPS+FPGA system via an Avalon-MM memory-mapped interface, and driven from embedded Linux running on the ARM HPS.

## Status: Fully working, end-to-end, on real hardware

The accelerator is designed, simulated, synthesized, integrated into a complete SoC system, and driven by a real C program running on Linux — with results numerically verified against an independent CPU-computed reference.

## Architecture

A sequential (non-parallel) design: a single multiply-accumulate unit stepped through the full computation by a 3-counter FSM (`i`, `j`, `k`), computing `mat_c[i][j] = Σ mat_a[i][k] * mat_b[k][j]` for `k = 0..7`, one term per clock cycle. A full 8×8 result takes `8×8×8 = 512` cycles.

This was a deliberate choice over a parallel (e.g., 8-MAC-unit) architecture, to get a complete, working, hardware-verified accelerator sooner — parallelizing further is a natural next step, not something the current design forecloses.

## Modules

| File | Description | Tests |
|---|---|---|
| `matmul_core.sv` | The compute core: `mat_a`/`mat_b`/`mat_c` storage, write/read ports, and the FSM that performs the multiply-accumulate sequence | 69/69 ✅ |
| `matmul_avalon.sv` | Avalon-MM slave wrapper: decodes a memory-mapped register interface (control/status + 3 matrix regions) into `matmul_core`'s native signals | 4/4 ✅ |
| `software/matmul_driver.c` | HPS-side C driver: loads matrices via `mmap()`, triggers computation, polls for completion, reads back and verifies the result against a CPU-computed reference | Verified on hardware ✅ |

## Register map

| Address (word) | Region |
|---|---|
| `0` | Control/status (write bit 0 = start; read bit 0 = busy, bit 1 = done) |
| `1` – `64` | `mat_a` (`row*8 + col + 1`) |
| `65` – `128` | `mat_b` (`row*8 + col + 65`) |
| `129` – `192` | `mat_c`, read-only (`row*8 + col + 129`) |

Mapped into the HPS's lightweight bridge at physical address `0xFF200000 + 0x00040000 = 0xFF240000`.

## Verification

**Simulation** (Icarus Verilog): `matmul_core_tb.sv` verifies write/read plumbing, multi-term accumulation (proving the k-summation genuinely works, not just a single multiply), and a full 8×8 multiply with all-distinct values, cross-checked against a Python-computed reference (69/69 passing). `matmul_avalon_tb.sv` verifies the Avalon-MM register interface end-to-end, including a regression test confirming `done` stays asserted across multiple cycles rather than reverting after one (4/4 passing).

**Hardware**: `software/matmul_driver.c` loads real matrices via `/dev/mem` + `mmap()`, triggers a real computation, and independently computes the same multiplication in software on the ARM CPU to numerically verify the FPGA's result (max error: `0.000000`).

**First real hardware benchmark**:
```
CPU matrix multiply latency: 5.69 us
FPGA HPS-visible latency: 11.70 us
CPU / FPGA latency ratio: 0.49x
```
The CPU is faster here, which is expected and worth understanding rather than hiding: the accelerator's own compute time (`512 cycles @ 50MHz = 10.24us` theoretical minimum) is already close to the CPU's entire runtime for this workload, since the ARM core executes this small, cache-resident 8×8×8 multiply on a much faster, deeply pipelined processor with no memory-mapped I/O overhead. A hardware accelerator's value shows at larger, more parallel, or more frequently-repeated workloads — not a single small fixed-size multiply — so this result is an honest characterization of the current design's scope, not a shortcoming to be corrected without also changing the workload or architecture.

## Hardware integration: HPS + FPGA on the DE10-Standard

Getting this accelerator genuinely usable from Linux (not just simulated, and not just visible via JTAG-based register pokes) required integrating it into a full HPS+FPGA SoC system, based on Terasic's DE10-Standard GHRD (Golden Hardware Reference Design):

- Added `matmul_avalon` as a custom Platform Designer component, connected to the HPS's lightweight HPS-to-FPGA bridge (`h2f_lw_axi_master`)
- Resolved several real address-map conflicts with existing GHRD components during integration
- Synthesized the complete system (HPS configuration, DDR3 controller, existing GHRD peripherals, and the accelerator) — 0 errors, ~5,660 ALMs, positive timing slack across every clock domain

**Getting the HPS to actually see the accelerator over the memory-mapped bridge required working through several genuine, non-obvious issues** — documented here rather than glossed over, since they were real engineering problems, and because the debugging path itself is worth being honest about (including a detour that turned out not to be the actual fix):

- **Early investigation suspected the HPS-to-FPGA bridges were disabled** (since bridges are disabled by default until enabled at boot time), leading to building a `soc_system.rbf` via `quartus_cpf` and modifying the SD card's boot flow so U-Boot's own `fpga load` command would configure the FPGA before `bridge_enable_handoff` ran. **In hindsight, this was very likely not the actual fix**: `/sys/class/fpga_bridge/*/state` had already been reporting `enabled` (and `/sys/class/fpga_manager/fpga0/state` reporting `operating`) in earlier tests, using only JTAG programming followed by an HPS-only reset (the `KEY5` button) — meaning the bridges were probably enabled correctly the whole time. The `.rbf`/boot-script route is left working and in place (and the SD card's boot partition does *not* currently contain a `soc_system.rbf` — only `socfpga.dtb`, `u-boot.scr`, `zImage`, and the driver), but the two fixes below are what actually resolved the observed failures.
- **A disconnected Avalon-MM slave port** (`sysid_qsys.control_slave`, a pre-existing GHRD component, left unconnected during initial integration) caused the shared Merlin interconnect fabric's address-decode logic to malform, stalling *all* reads on that fabric — not just the accelerator's own address. This fully explains the indefinite hang observed even at the very base of the lightweight bridge address range, independent of bridge-enable status. Fixed by connecting it properly in Platform Designer.
- **A real RTL bug**: `matmul_avalon`'s `start` signal was purely combinational, reflecting the Avalon write pulse for only a single clock cycle. This meant `matmul_core`'s `done` state was visible for only one 20ns cycle before the FSM saw `!start` and reverted to idle — far too narrow a window for real software polling (via `mmap`-based reads with genuine OS/syscall overhead) to reliably catch, even though Icarus Verilog's fast testbench polling in simulation never revealed the problem. Fixed by making `core_start` a registered signal that holds its value until explicitly cleared, with a regression test added to confirm `done` now stays asserted across multiple cycles.

Diagnosing the interconnect stall specifically required SignalTap (Quartus's embedded logic analyzer) to observe live bus signals inside the running FPGA fabric, since the failure wasn't reproducible from the register-level checks available from Linux alone. The FPGA fabric is programmed via standard JTAG (Quartus Programmer) for each session; no `.rbf`-based boot-time configuration is currently required.

## Running the tests

Requires [Icarus Verilog](http://iverilog.icarus.com/).

```bash
iverilog -g2012 -o sim_core rtl/matmul_core.sv testbenches/matmul_core_tb.sv
vvp sim_core

iverilog -g2012 -o sim_avalon rtl/matmul_core.sv rtl/matmul_avalon.sv testbenches/matmul_avalon_tb.sv
vvp sim_avalon
```

## Running the hardware driver

On the DE10-Standard: program the FPGA fabric via Quartus Programmer (JTAG), boot Linux from the SD card (containing `socfpga.dtb`, `u-boot.scr`, `zImage`, and the driver source), then on the board:
```bash
gcc -std=gnu99 -O2 -o matmul_driver matmul_driver.c -lrt -lm
./matmul_driver
```

## Known limitations / scope notes

- **Sequential, not parallel**: a single MAC unit computes one term per cycle (512 cycles per 8×8 result). A parallel architecture (e.g., one MAC unit per output row, or a systolic array) would trade area for significant speedup, and is a natural next step.
- **Fixed 8×8 size, Q8.8/Q16.16 precision**: not parameterized for other matrix sizes or bit widths.
- **No burst transfers**: the HPS loads/reads one 32-bit register at a time; a production design might batch transfers to reduce per-access bridge overhead, which is a meaningful fraction of the measured hardware latency at this workload size.
- **Polling-based completion**, not interrupt-driven — simpler to implement and verify, but not ideal for CPU efficiency at scale (the current benchmark's ARM core spins in a busy-wait loop rather than sleeping while the accelerator computes).

## Reference

DE10-Standard GHRD and Linux Console image: [Terasic DE10-Standard System CD](https://download.terasic.com/downloads/cd-rom/de10-standard/). Bridge-enable and boot-flow details cross-referenced against Intel/Altera SoC FPGA HPS technical documentation and community-documented fixes for the same class of issue.

## Project structure
```
rtl/            SystemVerilog source (matmul_core, matmul_avalon)
testbenches/    Self-checking testbenches for both modules
software/       HPS-side C driver (matmul_driver.c)
```
