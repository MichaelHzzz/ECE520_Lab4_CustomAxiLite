# ECE 520 Lab 4: Custom AXI-Lite FIFO IP

## Hardware Design

This lab integrates a custom AXI-Lite FIFO IP with a Zynq processing system in Vivado.

The Block Design includes:

- Zynq processing system
- AXI interconnect
- Custom multiplier AXI IP
- Custom FIFO AXI IP
- AXI BRAM controller
- Block RAM

## AXI Base Addresses

| Peripheral | Base Address |
| BRAM | `0x40000000` |
| Multiplier AXI IP | `0x43C00000` |
| FIFO AXI IP | `0x43C10000` |

## FIFO Verification

The FIFO AXI IP was verified with a Verilog AXI transaction testbench named `tb_sc_fifo_axi.v`.

The testbench verified:

- AXI-Lite register reads and writes
- FIFO reset
- FIFO ordering
- Full and empty conditions
- Almost-full and almost-empty thresholds
- Byte strobes
- Software reset
- Pointer wraparound
- AXI reset

All AXI FIFO test groups passed.

The FIFO was also tested on the Zybo board using a C program in Vitis.

## Software Test

The Vitis C program:

1. Reads the FIFO revision and configuration registers.
2. Resets the FIFO.
3. Writes and reads FIFO values to verify ordering.
4. Fills the FIFO to 32 entries.
5. Verifies the full flag.
6. Verifies that an extra write is rejected.
7. Performs a software reset.
8. Tests multiplier values from 1 through 32.
9. Stores the multiplier results in BRAM.
10. Reads the BRAM values back.
