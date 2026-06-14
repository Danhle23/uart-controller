// =====================================================================
// uart_tb.sv  -  Self-checking testbench for the UART controller
// Connects uart_tx -> uart_rx in loopback, drives 46 bytes
// (10 directed + 36 random), scoreboards every result, and includes
// a SystemVerilog assertion + functional-coverage hook.
// Author: Grimm
// =====================================================================
`timescale 1ns/1ps

module uart_tb;

    // -- parameters (fast baud keeps the simulation short) -------------
    localparam int CLK_FREQ     = 50_000_000;
    localparam int BAUD_RATE    = 1_000_000;
    localparam int DATA_BITS    = 8;
    localparam time CLK_PERIOD  = 20ns;        // 50 MHz

    // -- DUT signals ---------------------------------------------------
    logic                 clk = 1'b0;
    logic                 rst_n = 1'b0;
    logic                 tx_start;
    logic [DATA_BITS-1:0] tx_data;
    logic                 tx_line, tx_busy;
    logic [DATA_BITS-1:0] rx_data;
    logic                 rx_valid;

    // -- DUTs in loopback: tx drives rx --------------------------------
    uart_tx #(.CLK_FREQ(CLK_FREQ), .BAUD_RATE(BAUD_RATE), .DATA_BITS(DATA_BITS))
    u_tx (
        .clk(clk), .rst_n(rst_n),
        .tx_start(tx_start), .tx_data(tx_data),
        .tx(tx_line), .tx_busy(tx_busy)
    );

    uart_rx #(.CLK_FREQ(CLK_FREQ), .BAUD_RATE(BAUD_RATE), .DATA_BITS(DATA_BITS))
    u_rx (
        .clk(clk), .rst_n(rst_n),
        .rx(tx_line),
        .rx_data(rx_data), .rx_valid(rx_valid)
    );

    // -- clock ---------------------------------------------------------
    always #(CLK_PERIOD/2) clk = ~clk;

    // -- scoreboard ----------------------------------------------------
    int errors = 0;
    int checks = 0;

    // -- functional coverage hook --------------------------------------
    covergroup cg_data @(posedge rx_valid);
        coverpoint rx_data {
            bins low      = {[8'h00:8'h3F]};
            bins mid_low  = {[8'h40:8'h7F]};
            bins mid_high = {[8'h80:8'hBF]};
            bins high     = {[8'hC0:8'hFF]};
        }
    endgroup
    cg_data cov = new();

    // -- assertion: line must idle high whenever tx is not busy --------
    property p_idle_high;
        @(posedge clk) disable iff (!rst_n)
        (!tx_busy) |-> (tx_line == 1'b1);
    endproperty
    assert property (p_idle_high)
        else $error("ASSERTION: tx line not high while idle");

    // -- driver/checker task -------------------------------------------
    task automatic send_and_check(input logic [DATA_BITS-1:0] data);
        @(posedge clk);
        tx_data  <= data;
        tx_start <= 1'b1;
        @(posedge clk);
        tx_start <= 1'b0;

        @(posedge rx_valid);   // wait for the receiver to finish
        @(posedge clk);
        checks++;
        if (rx_data === data) begin
            $display("[PASS] sent=0x%02h  recv=0x%02h", data, rx_data);
        end else begin
            errors++;
            $display("[FAIL] sent=0x%02h  recv=0x%02h", data, rx_data);
        end

        wait (!tx_busy);
        repeat (4) @(posedge clk);
    endtask

    // -- directed vectors ----------------------------------------------
    logic [DATA_BITS-1:0] directed [10] = '{
        8'h00, 8'hFF, 8'hAA, 8'h55, 8'h0F,
        8'hF0, 8'h01, 8'h80, 8'h7E, 8'h3C
    };

    // -- main stimulus -------------------------------------------------
    initial begin
        tx_start = 1'b0;
        tx_data  = '0;

        repeat (5) @(posedge clk);
        rst_n = 1'b1;                 // release reset
        repeat (5) @(posedge clk);

        foreach (directed[i])
            send_and_check(directed[i]);          // 10 directed

        for (int i = 0; i < 36; i++)
            send_and_check($urandom_range(0, 255)); // 36 random => 46 total

        $display("--------------------------------------------");
        $display("Total checks : %0d", checks);
        $display("Errors       : %0d", errors);
        $display("Coverage     : %0.1f%%", cov.get_coverage());
        if (errors == 0) $display("RESULT: ALL TESTS PASSED");
        else             $display("RESULT: %0d TEST(S) FAILED", errors);
        $display("--------------------------------------------");
        $finish;
    end

    // -- waveform dump (for: make wave) --------------------------------
    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, uart_tb);
    end

    // -- safety timeout ------------------------------------------------
    initial begin
        #5ms;
        $display("TIMEOUT - simulation did not finish in time");
        $finish;
    end

endmodule
