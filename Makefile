# Makefile — Synthesizable UART & AMBA APB3 SoC IP Verification
IVERILOG ?= iverilog
VVP      ?= vvp
FLAGS    := -g2012 -Wall

RTL_CORE := uart_tx.sv uart_rx.sv
RTL_SOC  := sync_fifo.sv $(RTL_CORE) apb_uart.sv

.PHONY: all sim sim_core sim_apb wave clean

all: sim

sim: sim_core sim_apb

sim_core:
	$(IVERILOG) $(FLAGS) -o sim_core.vvp $(RTL_CORE) uart_tb.sv
	$(VVP) sim_core.vvp

sim_apb:
	$(IVERILOG) $(FLAGS) -o sim_apb.vvp $(RTL_SOC) apb_uart_tb.sv
	$(VVP) sim_apb.vvp

wave: sim_core
	gtkwave uart_core.vcd &

clean:
	rm -f *.vvp *.vcd
