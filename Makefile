# =====================================================================
# Makefile - build & run the UART simulation with Icarus Verilog
#   make sim    compile + run the self-checking testbench
#   make wave   run, then open the waveform in GTKWave
#   make clean  remove build artifacts
# =====================================================================
SIM    = iverilog
VVP    = vvp
FLAGS  = -g2012
SRC    = uart_tx.sv uart_rx.sv uart_tb.sv
TOP    = uart_tb
BUILD  = sim.out

.PHONY: sim wave clean

sim: $(SRC)
	$(SIM) $(FLAGS) -o $(BUILD) $(SRC)
	$(VVP) $(BUILD)

wave: sim
	gtkwave dump.vcd &

clean:
	rm -f $(BUILD) dump.vcd
