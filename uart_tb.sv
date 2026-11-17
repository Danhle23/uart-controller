// =====================================================================
// uart_tb.sv - Self-checking Testbench for UART TX/RX Core
// Verifies directed corner patterns, randomized bytes, even/odd parity,
// parity error detection, and framing error detection.
// Compatible with Icarus Verilog 11/12, Verilator, Questa, and VCS.
// Author: Le Thanh Danh (Danhle23)
// =====================================================================
`timescale 1ns/1ps

module uart_tb;

    localparam int CLK_FREQ   = 50_000_000;
    localparam int BAUD_RATE  = 1_000_000;
    localparam int DATA_BITS  = 8;
    localparam time CLK_PERIOD = 20ns;

    logic                 clk       = 1'b0;
    logic                 rst_n     = 1'b0;
    logic                 tx_start  = 1'b0;
    logic [DATA_BITS-1:0] tx_data   = '0;
    logic [15:0]          clk_div   = 16'd0;
    logic                 tx_par_en = 1'b0;
    logic                 tx_par_odd= 1'b0;
    logic                 rx_par_en = 1'b0;
    logic                 rx_par_odd= 1'b0;
    logic                 tx_line, tx_busy;
    logic                 force_break = 1'b0;
    wire                  rx_line = force_break ? 1'b0 : tx_line;

    logic [DATA_BITS-1:0] rx_data;
    logic                 rx_valid, parity_err, framing_err;

    uart_tx #(
        .CLK_FREQ (CLK_FREQ),
        .BAUD_RATE(BAUD_RATE),
        .DATA_BITS(DATA_BITS)
    ) u_tx (
        .clk        (clk),
        .rst_n      (rst_n),
        .tx_start   (tx_start),
        .tx_data    (tx_data),
        .cfg_clk_div(clk_div),
        .parity_en  (tx_par_en),
        .parity_odd (tx_par_odd),
        .tx         (tx_line),
        .tx_busy    (tx_busy)
    );

    uart_rx #(
        .CLK_FREQ (CLK_FREQ),
        .BAUD_RATE(BAUD_RATE),
        .DATA_BITS(DATA_BITS)
    ) u_rx (
        .clk        (clk),
        .rst_n      (rst_n),
        .rx         (rx_line),
        .cfg_clk_div(clk_div),
        .parity_en  (rx_par_en),
        .parity_odd (rx_par_odd),
        .rx_data    (rx_data),
        .rx_valid   (rx_valid),
        .parity_err (parity_err),
        .framing_err(framing_err)
    );

    always #(CLK_PERIOD/2) clk = ~clk;

    int errors = 0;
    int checks = 0;
    logic [3:0] cov_bins = 4'b0000;

    // Continuous cycle-level protocol assertion: TX idles high when not busy
    always @(posedge clk) begin
        if (rst_n && !tx_busy && !tx_start) begin
            if (tx_line !== 1'b1) begin
                $display("[ASSERT FAIL] tx_line low while idle at %0t", $time);
                errors = errors + 1;
            end
        end
    end

    task automatic send_and_check(
        input logic [7:0] data,
        input logic       exp_par_err
    );
        @(posedge clk);
        tx_data  <= data;
        tx_start <= 1'b1;
        @(posedge clk);
        tx_start <= 1'b0;

        @(posedge rx_valid);
        checks = checks + 1;

        if (rx_data[7:6] == 2'b00) cov_bins[0] = 1'b1;
        if (rx_data[7:6] == 2'b01) cov_bins[1] = 1'b1;
        if (rx_data[7:6] == 2'b10) cov_bins[2] = 1'b1;
        if (rx_data[7:6] == 2'b11) cov_bins[3] = 1'b1;

        if ((rx_data === data) && (parity_err === exp_par_err) && (framing_err === 1'b0)) begin
            $display("[PASS] sent=0x%02h recv=0x%02h par_err=%0b", data, rx_data, parity_err);
        end else begin
            errors = errors + 1;
            $display("[FAIL] sent=0x%02h recv=0x%02h par_err=%0b(exp %0b) frm_err=%0b",
                     data, rx_data, parity_err, exp_par_err, framing_err);
        end

        wait (!tx_busy);
        repeat (4) @(posedge clk);
    endtask

    logic [7:0] directed [0:9];
    int i;

    initial begin
        directed[0] = 8'h00; directed[1] = 8'hFF;
        directed[2] = 8'hAA; directed[3] = 8'h55;
        directed[4] = 8'h0F; directed[5] = 8'hF0;
        directed[6] = 8'h01; directed[7] = 8'h80;
        directed[8] = 8'h7E; directed[9] = 8'h3C;

        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (5) @(posedge clk);

        // 1. 10 Directed Corner Cases (8N1)
        for (i = 0; i < 10; i = i + 1)
            send_and_check(directed[i], 1'b0);

        // 2. 30 Randomized Vectors (8N1)
        for (i = 0; i < 30; i = i + 1)
            send_and_check($urandom_range(0, 255), 1'b0);

        // 3. Even Parity (8E1) & Odd Parity (8O1) Verification
        tx_par_en = 1'b1; rx_par_en = 1'b1;
        tx_par_odd = 1'b0; rx_par_odd = 1'b0;
        send_and_check(8'hA5, 1'b0);
        send_and_check(8'h37, 1'b0);

        tx_par_odd = 1'b1; rx_par_odd = 1'b1;
        send_and_check(8'hC3, 1'b0);

        // 4. Injected Parity Mismatch Error Detection
        tx_par_odd = 1'b0; rx_par_odd = 1'b1;
        send_and_check(8'h5A, 1'b1);

        // 5. Framing Error Injection (Break condition holding stop bit low)
        tx_par_en = 1'b0; rx_par_en = 1'b0;
        @(posedge clk);
        force_break = 1'b1;
        @(posedge rx_valid);
        checks = checks + 1;
        if (framing_err === 1'b1) begin
            $display("[PASS] Framing error detected cleanly on break condition");
        end else begin
            errors = errors + 1;
            $display("[FAIL] Framing error missed on break condition");
        end
        force_break = 1'b0;
        repeat (60) @(posedge clk);

        $display("--------------------------------------------");
        $display("Total checks : %0d", checks);
        $display("Errors       : %0d", errors);
        $display("Quadrant Cov : %0d / 4 bins hit",
                 cov_bins[0] + cov_bins[1] + cov_bins[2] + cov_bins[3]);
        if (errors == 0) begin
            $display("RESULT: ALL UART CORE TESTS PASSED");
            $finish;
        end else begin
            $display("RESULT: %0d TEST(S) FAILED", errors);
            $fatal(1);
        end
    end

    initial begin
        $dumpfile("uart_core.vcd");
        $dumpvars(0, uart_tb);
    end

    initial begin
        #10ms;
        $display("TIMEOUT - simulation exceeded limit");
        $fatal(1);
    end

endmodule
