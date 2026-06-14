# UART Controller — SystemVerilog (RTL & Verification)

A parameterized **UART transmitter + receiver** written in SystemVerilog, with a
self-checking testbench that drives 46 transactions in loopback and scoreboards
every result. Built as a digital-design / verification portfolio project.

**Result:** `46 / 46` tests pass on Icarus Verilog 12.0.

---

## What's inside

| File          | Description                                                          |
|---------------|----------------------------------------------------------------------|
| `uart_tx.sv`  | Transmitter. FSM `IDLE → START → DATA → STOP`, parameterized baud.    |
| `uart_rx.sv`  | Receiver. 2-flop synchronizer + mid-bit sampling for noise immunity. |
| `uart_tb.sv`  | Self-checking testbench: loopback, scoreboard, assertion, coverage.  |
| `Makefile`    | `make sim` to compile + run, `make wave` to view the waveform.       |

## Design highlights (the details interviewers ask about)

- **Clean finite state machine** in both TX and RX (`IDLE → START → DATA → STOP`).
- **Parameterized** `CLK_FREQ`, `BAUD_RATE`, `DATA_BITS` — `CLKS_PER_BIT` is
  derived, so the same RTL retargets to any clock/baud.
- **Two-flop synchronizer** on the asynchronous `rx` line to defend against
  metastability.
- **Mid-bit sampling**: the receiver samples each bit at its centre, the standard
  technique for tolerating clock drift and noise.
- **`rx_valid`** is a clean one-clock data-ready strobe.

## Verification highlights

- **Loopback** — `uart_tx.tx` is wired straight into `uart_rx.rx`.
- **Scoreboard** — every received byte is compared against what was sent;
  pass/fail is counted and summarized.
- **Directed + random stimulus** — 10 directed corner cases (`0x00`, `0xFF`,
  `0xAA`, `0x55`, …) plus 36 randomized bytes = 46 transactions.
- **SystemVerilog Assertion (SVA)** — checks the line idles high whenever the
  transmitter is not busy.
- **Functional coverage** — a covergroup bins the received data across its range.

## How to run

```bash
# Ubuntu/Linux
sudo apt install iverilog gtkwave
make sim      # compile + run, prints [PASS]/[FAIL] and a summary
make wave     # open the waveform in GTKWave

# macOS
brew install icarus-verilog gtkwave
make sim
```

No simulator installed? Paste the sources into
[EDA Playground](https://edaplayground.com) (pick *Icarus Verilog 12.0*) and Run.

Expected tail of the log:

```
--------------------------------------------
Total checks : 46
Errors       : 0
RESULT: ALL TESTS PASSED
--------------------------------------------
```

## Skills demonstrated

`SystemVerilog` · `RTL design` · `FSM` · `clock-domain synchronization` ·
`self-checking testbench` · `scoreboard` · `SVA assertions` ·
`functional coverage` · `Icarus Verilog` · `Makefile`

## For your CV

> **UART Controller — SystemVerilog (RTL & Verification).** Designed a
> parameterized UART TX/RX (FSM, 2-flop metastability synchronizer, mid-bit
> sampling). Built a self-checking testbench with scoreboard, directed + random
> stimulus, an SVA assertion and a functional-coverage group; **46/46** tests
> pass on Icarus Verilog. *github.com/&lt;you&gt;/uart-controller*

## Roadmap (each step = one more commit)

1. Add a **parity bit** (odd/even) to TX and RX, plus a parity-error flag.
2. Add **TX and RX FIFOs** so the core can stream bytes back-to-back.
3. Wrap the core in an **APB / AXI-Lite register interface**.
4. Rebuild the testbench as a small **UVM** environment (driver, monitor,
   scoreboard, coverage).
