# FPGA Matrix Multiplier Accelerator

An 8×8 signed fixed-point matrix multiplication accelerator implemented in SystemVerilog and deployed on the Terasic DE10-Standard Cyclone V SoC FPGA.

The accelerator uses an **8-way parallel dot-product datapath** to compute one output matrix element per clock cycle, communicates with the ARM HPS through an Avalon-MM interface over the lightweight HPS-to-FPGA bridge, and is controlled by a C application running under embedded Linux.

The design was developed incrementally from a serial single-MAC implementation to the current parallel architecture, allowing direct measurement of the **area/performance tradeoff of hardware parallelism on real FPGA hardware**.

## Status: Fully Working End-to-End on Real Hardware

The accelerator is designed, simulated, synthesized, integrated into a complete SoC system, and driven by a real C program running on Linux.

Current status:

- SystemVerilog RTL synthesized and timing-verified in Quartus
- Integrated into the DE10-Standard HPS+FPGA system using Platform Designer
- Accessible from Linux through the lightweight HPS-to-FPGA bridge
- Signed Q8.8 input and Q16.16 output arithmetic
- Verified with positive, negative, and fractional fixed-point test cases
- FPGA results match the independent ARM CPU reference with `0.000000` maximum error
- Optimized FPGA implementation achieves approximately **4.3× lower HPS-visible latency than the original serial FPGA implementation**
- Optimized FPGA achieves approximately **1.8–2.0× lower latency than the ARM software reference** for the tested 8×8 workload

## Performance

Two FPGA architectures were implemented and benchmarked on the same DE10-Standard platform.

| Metric | Serial 1-MAC | 8-Way Parallel | Improvement |
|---|---:|---:|---:|
| Datapath parallelism | 1 multiply/cycle | 8 multiplies/cycle | 8× |
| Compute cycles | ~512 | ~64 | ~8× theoretical reduction |
| HPS-visible latency | ~11.7 µs | ~2.7 µs | **~4.3× faster** |
| Equivalent 50 MHz cycles* | ~586 | ~135 | **~4.3× reduction** |
| CPU reference latency | ~5 µs | ~5 µs | — |
| FPGA vs CPU | ~2× slower | **~1.8–2.0× faster** | Crossed CPU baseline |
| Numerical error | 0.000000 | 0.000000 | No loss of correctness |

\*Equivalent cycles are calculated from HPS-observed wall-clock latency and therefore include software-visible control, polling, and interconnect overhead. They are not pure core cycle counts.

### Representative Optimized Hardware Benchmark

~~~text
Positive integers:
CPU matrix multiply latency:  5.35 us
FPGA HPS-visible latency:     2.71 us
CPU / FPGA latency ratio:     1.97x

Signed integers:
CPU matrix multiply latency:  5.04 us
FPGA HPS-visible latency:     2.68 us
CPU / FPGA latency ratio:     1.88x

Signed fractional Q8.8:
CPU matrix multiply latency:  4.79 us
FPGA HPS-visible latency:     2.67 us
CPU / FPGA latency ratio:     1.79x
~~~

All three tests produced:

~~~text
Verification: PASS
Maximum error: 0.000000
~~~

The approximately 8× reduction in theoretical compute cycles results in a smaller ~4.3× reduction in HPS-visible latency because the measured FPGA time also includes start-register access, HPS-to-FPGA interconnect latency, and software polling overhead that is not reduced by datapath parallelism.

## Architecture

The accelerator was developed in two major architectural stages: an initial serial implementation used to establish a functional and performance baseline, followed by the current 8-way parallel implementation.

### Version 1 — Serial Single-MAC Baseline

The original implementation used a three-counter FSM (`i`, `j`, `k`) and evaluated one term of the matrix dot product per clock cycle:

~~~text
C[i][j] += A[i][k] × B[k][j]
~~~

Each output required eight multiply-accumulate iterations:

~~~text
8 rows × 8 columns × 8 terms = 512 MAC iterations
~~~

At 50 MHz, the 512 compute cycles alone correspond to approximately:

~~~text
512 × 20 ns = 10.24 us
~~~

The measured HPS-visible latency was approximately:

~~~text
11.7 us
~~~

The ARM software reference required approximately:

~~~text
5 us
~~~

Therefore, the original FPGA implementation was roughly 2× slower than the ARM CPU for this small workload.

Rather than hiding this result, the serial implementation was retained as a baseline. Its measured performance identified insufficient datapath parallelism as the primary architectural bottleneck and motivated the next version of the accelerator.

### Version 2 — 8-Way Parallel Dot Product

The current implementation eliminates the sequential `k` iteration and performs all eight products needed for a single output element simultaneously.

Conceptually:

~~~text
A[i][0] × B[0][j] ─┐
A[i][1] × B[1][j] ─┤
A[i][2] × B[2][j] ─┤
A[i][3] × B[3][j] ─┤
A[i][4] × B[4][j] ─┼──> Balanced Adder Tree ──> C[i][j]
A[i][5] × B[5][j] ─┤
A[i][6] × B[6][j] ─┤
A[i][7] × B[7][j] ─┘
~~~

The eight signed Q8.8 multiplications are reduced using a balanced three-level adder tree:

~~~text
8 products
    ↓
4 partial sums
    ↓
2 partial sums
    ↓
1 dot product
~~~

The internal reduction signals are widened through each level of the adder tree to preserve the intermediate signed arithmetic.

The resulting datapath produces one complete `C[i][j]` result during each compute cycle.

The output sequence is therefore approximately:

~~~text
Cycle 1  -> C[0][0]
Cycle 2  -> C[0][1]
...
Cycle 8  -> C[0][7]

Cycle 9  -> C[1][0]
...
Cycle 64 -> C[7][7]
~~~

This reduces the core computation from approximately 512 serial MAC iterations to approximately 64 output cycles.

The Avalon-MM interface and software-visible register map remained unchanged during this optimization. This allowed the same Linux driver and regression suite to verify the optimized architecture without modifying the HPS/FPGA communication protocol.

## FPGA Resource Utilization

Quartus reports the following resource utilization for the current `matmul_core` hierarchy:

| Resource | 8-Way Core | Device Capacity | Approx. Device Usage |
|---|---:|---:|---:|
| ALMs | **1,903** | 41,910 | **4.5%** |
| Combinational ALUTs | **1,695** | — | — |
| Dedicated logic registers | **4,348** | 83,820 | **5.2%** |
| DSP blocks | **4** | 112 | **3.6%** |
| M10K blocks | **0** | 553 | **0%** |

The complete `matmul_avalon` hierarchy, including both the Avalon-MM wrapper and compute core, uses approximately:

~~~text
ALMs:                 2,403
Combinational ALUTs:  2,420
Dedicated registers:  4,349
DSP blocks:           4
M10K blocks:          0
~~~

The full DE10-Standard GHRD system, including the HPS configuration and other existing peripherals, uses:

| Resource | Full SoC Design | Device Capacity |
|---|---:|---:|
| ALMs | 5,942 | 41,910 |
| Dedicated logic registers | 9,532 | 83,820 |
| M10K blocks | 7 | 553 |
| DSP blocks | 4 | 112 |

Although the RTL describes eight simultaneous signed 16×16 multiplications, Quartus maps the datapath into four Cyclone V DSP blocks.

### Register-Based Matrix Storage

The relatively high register count inside `matmul_core` is primarily caused by storing all three matrices directly in FPGA registers:

~~~text
Matrix A: 64 × 16 bits = 1,024 bits
Matrix B: 64 × 16 bits = 1,024 bits
Matrix C: 64 × 32 bits = 2,048 bits
                         ----------
                         4,096 bits
~~~

This register-based architecture also provides the parallel read bandwidth required by the eight-way datapath without introducing multi-port block-RAM constraints.

## Timing

The accelerator operates from the DE10-Standard's 50 MHz FPGA clock domain:

~~~text
Operating frequency: 50.00 MHz
Clock period:         20.00 ns
~~~

Quartus TimeQuest reports the following maximum frequency for `CLOCK_50` at the Slow 1100 mV / 85°C timing corner:

~~~text
CLOCK_50 Fmax: 65.77 MHz
~~~

The current unpipelined parallel datapath therefore meets the 50 MHz operating requirement.

The main compute path conceptually contains:

~~~text
16×16 multiplication
        ↓
adder-tree level 1
        ↓
adder-tree level 2
        ↓
adder-tree level 3
        ↓
result register
~~~

The current implementation intentionally performs this reduction without intermediate pipeline registers.

Pipelining the reduction tree is a future optimization opportunity that could increase achievable Fmax while maintaining approximately one output result per cycle after the pipeline fills.

## Modules

| File | Description | Verification |
|---|---|---|
| `rtl/matmul_core.sv` | Compute core containing matrix storage, signed Q8.8 arithmetic, eight parallel multipliers, balanced adder tree, result storage, and FSM control | 69/69 simulation tests + 3/3 hardware regression tests ✅ |
| `rtl/matmul_avalon.sv` | Avalon-MM slave wrapper that maps control/status and matrix regions into `matmul_core` signals | 4/4 simulation tests + hardware verified ✅ |
| `software/matmul_driver.c` | Linux userspace driver that loads matrices, starts the accelerator, polls completion, reads results, benchmarks latency, and compares against an ARM CPU reference | 3/3 hardware regression tests ✅ |

## Fixed-Point Representation

Input matrices `A` and `B` use signed 16-bit Q8.8 fixed-point values.

~~~text
Q8.8:
16 total bits
8 integer/sign bits
8 fractional bits
~~~

The multiplication of two Q8.8 values produces a Q16.16 product:

~~~text
Q8.8 × Q8.8 -> Q16.16
~~~

The result matrix `C` therefore uses signed 32-bit Q16.16 values.

The Linux driver performs the required conversion when transferring data between floating-point software values and the FPGA:

~~~c
static inline int16_t to_q8_8(double val)
{
    return (int16_t)(val * 256.0);
}

static inline double from_q16_16(int32_t val)
{
    return (double)val / 65536.0;
}
~~~

## Register Map

The accelerator exposes a memory-mapped Avalon-MM slave interface.

| Address (word) | Region |
|---|---|
| `0` | Control/status |
| `1` – `64` | `mat_a` |
| `65` – `128` | `mat_b` |
| `129` – `192` | `mat_c`, read-only |

Control/status behavior:

~~~text
Write bit 0 = start

Read bit 0 = busy
Read bit 1 = done
~~~

Matrix address calculations:

~~~text
A[row][col] -> row*8 + col + 1
B[row][col] -> row*8 + col + 65
C[row][col] -> row*8 + col + 129
~~~

The accelerator is mapped into the HPS lightweight bridge at:

~~~text
Lightweight bridge base: 0xFF200000
Accelerator offset:      0x00040000
Accelerator base:        0xFF240000
~~~

Therefore:

~~~text
Control/status: 0xFF240000
A[0][0]:        0xFF240004
B[0][0]:        0xFF240104
C[0][0]:        0xFF240204
~~~

## Verification

Verification is performed at both the RTL simulation level and on physical FPGA hardware.

### RTL Simulation

`matmul_core_tb.sv` verifies the compute core, including matrix storage, read/write behavior, signed arithmetic, and complete 8×8 matrix multiplication against independently generated reference results.

`matmul_avalon_tb.sv` verifies the Avalon-MM register interface end-to-end, including control/status behavior and the registered `start` signal required to keep `done` asserted long enough for Linux software polling.

After replacing the serial MAC datapath with the 8-way parallel dot-product architecture, the complete RTL regression suite was rerun unchanged and passed **73/73 tests (69/69 core + 4/4 Avalon)**, confirming that the optimization preserved the existing functional and interface behavior.

### Hardware Regression Suite

The Linux C driver performs three complete end-to-end hardware tests:

1. Positive integer matrices
2. Mixed positive/negative integer matrices
3. Signed fractional Q8.8 matrices

For every test, the driver performs:

~~~text
Generate A and B
      ↓
Compute C on ARM
      ↓
Convert A/B to Q8.8
      ↓
Write A/B through Avalon-MM
      ↓
Start FPGA accelerator
      ↓
Poll DONE
      ↓
Read Q16.16 C
      ↓
Compare every element against CPU reference
~~~

The current parallel implementation passes all three regression tests:

~~~text
Positive integers:       PASS
Signed integers:         PASS
Signed fractional Q8.8:  PASS

Maximum error: 0.000000
~~~

The fractional regression test includes exactly representable fixed-point values such as `0.25` and `0.50`, as well as signed variants. This verifies actual fractional fixed-point arithmetic rather than only integer-valued Q8.8 operands.

## Hardware Integration: HPS + FPGA on the DE10-Standard

Getting the accelerator genuinely usable from Linux required integrating it into a complete HPS+FPGA SoC system based on Terasic's DE10-Standard GHRD (Golden Hardware Reference Design).

The integration includes:

- Added `matmul_avalon` as a custom Platform Designer component
- Connected the accelerator to the HPS lightweight HPS-to-FPGA bridge (`h2f_lw_axi_master`)
- Assigned the accelerator a lightweight-bridge address region
- Integrated the accelerator into the existing GHRD Avalon/AXI interconnect
- Regenerated the Platform Designer system
- Synthesized and fitted the complete Cyclone V SoC design
- Programmed the FPGA fabric through Quartus Programmer
- Accessed the accelerator from embedded Linux through `/dev/mem` and `mmap()`

### Debugging the HPS-to-FPGA Interface

Several real integration issues were encountered and resolved during development.

#### Avalon Interconnect Stall

A disconnected Avalon-MM slave port (`sysid_qsys.control_slave`) on a pre-existing GHRD component caused the shared Merlin interconnect fabric's address-decode logic to malfunction.

The result was that memory-mapped reads could stall across the shared interconnect rather than only at the accelerator's address.

Connecting the slave correctly in Platform Designer restored normal lightweight-bridge operation.

#### One-Cycle `done` Visibility Bug

A separate RTL bug existed in the original `matmul_avalon` control path.

The accelerator's `start` signal was initially generated directly from the Avalon write transaction. This meant `start` remained asserted for only a single FPGA clock cycle.

As a result, `matmul_core` could enter `ST_DONE`, but on the next cycle it observed `!start` and immediately returned to `ST_IDLE`.

At 50 MHz, the `done` indication was therefore visible for only approximately:

~~~text
20 ns
~~~

This worked in the fast RTL simulation environment but was far too short for Linux software polling to observe reliably.

The issue was fixed by implementing `core_start` as a registered control signal. Software writes `1` to begin computation and explicitly writes `0` after observing `done`.

This keeps the `done` state asserted until software acknowledges completion.

A regression test was added to verify the corrected behavior.

### System Console Debugging

Quartus System Console was used to perform direct JTAG-to-Avalon reads and writes independently of Linux.

This made it possible to separate:

~~~text
RTL problems
     vs.
Avalon interconnect problems
     vs.
HPS/Linux bridge problems
~~~

during hardware bring-up.

The FPGA fabric is currently programmed through standard JTAG using Quartus Programmer for each development session.

## Running the Simulation Tests

Requires Icarus Verilog.

~~~bash
iverilog -g2012 -o sim_core rtl/matmul_core.sv testbenches/matmul_core_tb.sv
vvp sim_core

iverilog -g2012 -o sim_avalon rtl/matmul_core.sv rtl/matmul_avalon.sv testbenches/matmul_avalon_tb.sv
vvp sim_avalon
~~~

## Running the Hardware Driver

Program the FPGA fabric using Quartus Programmer and boot embedded Linux on the DE10-Standard.

The SD card boot partition contains the Linux boot files and `matmul_driver.c`.

On the board:

~~~bash
mkdir -p /mnt/boot
mount /dev/mmcblk0p1 /mnt/boot
gcc -std=gnu99 -O2 -o matmul_driver /mnt/boot/matmul_driver.c -lrt -lm
./matmul_driver
~~~

The driver reports:

- FPGA result matrix
- ARM CPU reference matrix
- PASS/FAIL verification
- Maximum numerical error
- ARM CPU matrix multiplication latency
- HPS-visible FPGA latency
- Equivalent FPGA clock periods
- CPU/FPGA latency ratio

## Optimization Progression

The project intentionally preserves the performance evolution of the accelerator rather than presenting only the final implementation.

~~~text
Serial single-MAC architecture
        |
        | 512 MAC iterations
        | ~11.7 us HPS-visible
        | FPGA slower than ARM
        v
Identify insufficient parallelism
        |
        v
8-way parallel dot-product architecture
        |
        | ~64 compute output cycles
        | ~2.7 us HPS-visible
        | ~4.3x faster than serial FPGA
        | ~1.8-2.0x faster than ARM
        v
Current implementation
~~~

This provides a direct hardware demonstration of the tradeoff between resource utilization and execution latency.

The optimized compute core currently consumes only approximately:

~~~text
4.5% of device ALMs
3.6% of device DSP blocks
5.2% of device registers
~~~

leaving substantial FPGA resources available for further architectural experimentation.

## Known Limitations / Future Work

- **Fixed 8×8 matrix size** — the current implementation is optimized specifically for 8×8 matrix multiplication and is not yet parameterized for arbitrary matrix dimensions.
- **Fixed Q8.8/Q16.16 precision** — signed inputs use Q8.8 and externally visible results use Q16.16.
- **Unpipelined adder tree** — the eight multipliers and three reduction levels currently form a single-cycle combinational datapath. The design meets the current 50 MHz clock requirement with a reported `CLOCK_50` Fmax of 65.77 MHz, but pipelining could enable a higher operating frequency.
- **Register-based matrix storage** — this provides sufficient parallel read bandwidth for the eight-way datapath but would scale poorly to much larger matrices.
- **No DMA or burst transfers** — matrices are transferred using individual memory-mapped Avalon-MM accesses.
- **Polling-based completion** — the ARM CPU busy-waits on the `done` status bit rather than using an interrupt.
- **No explicit saturation logic** — arithmetic is widened internally through the adder tree, but the externally visible result remains 32-bit Q16.16.
- **Further parallelism is possible** — potential future architectures include a pipelined dot-product engine or a larger systolic/MAC array.

## Project Structure

~~~text
rtl/
    matmul_core.sv
    matmul_avalon.sv

testbenches/
    matmul_core_tb.sv
    matmul_avalon_tb.sv

software/
    matmul_driver.c
~~~

## Reference

DE10-Standard GHRD and Linux Console image:

[Terasic DE10-Standard System CD](https://download.terasic.com/downloads/cd-rom/de10-standard/)