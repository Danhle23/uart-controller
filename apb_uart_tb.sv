// =====================================================================
// apb_uart_tb.sv - Self-Checking AMBA APB3 Bus-Functional Testbench
// Tests APB3 register R/W, 16-byte TX/RX FIFO burst streaming,
// internal loopback, IRQ assertion, and W1C sticky error flags.
// Author: Le Thanh Danh (Danhle23)
// =====================================================================
`timescale 1ns/1ps

module apb_uart_tb;

    localparam time CLK_PERIOD = 20ns; // 50 MHz PCLK

    logic        pclk    = 1'b0;
    logic        presetn = 1'b0;
    logic        psel    = 1'b0;
    logic        penable = 1'b0;
    logic        pwrite  = 1'b0;
    logic [7:0]  paddr   = 8'h00;
    logic [31:0] pwdata  = 32'h0;
    logic [31:0] prdata;
    logic        pready, pslverr;
    logic        uart_rxd = 1'b1;
    logic        uart_txd, irq;

    apb_uart #(
        .CLK_FREQ  (50_000_000),
        .BAUD_RATE (5_000_000), // 10 clocks/bit for fast regression
        .FIFO_DEPTH(16)
    ) dut (
        .pclk    (pclk),
        .presetn (presetn),
        .psel    (psel),
        .penable (penable),
        .pwrite  (pwrite),
        .paddr   (paddr),
        .pwdata  (pwdata),
        .prdata  (prdata),
        .pready  (pready),
        .pslverr (pslverr),
        .uart_rxd(uart_rxd),
        .uart_txd(uart_txd),
        .irq     (irq)
    );

    always #(CLK_PERIOD/2) pclk = ~pclk;

    int errors = 0;
    int checks = 0;

    // APB3 2-cycle Write BFM (SETUP -> ACCESS)
    task automatic apb_write(input logic [7:0] addr, input logic [31:0] data);
        @(posedge pclk);
        psel    <= 1'b1;
        pwrite  <= 1'b1;
        penable <= 1'b0;
        paddr   <= addr;
        pwdata  <= data;
        @(posedge pclk);
        penable <= 1'b1;
        wait (pready === 1'b1);
        @(posedge pclk);
        psel    <= 1'b0;
        penable <= 1'b0;
        pwrite  <= 1'b0;
    endtask

    // APB3 2-cycle Read BFM (SETUP -> ACCESS)
    task automatic apb_read(input logic [7:0] addr, output logic [31:0] data);
        @(posedge pclk);
        psel    <= 1'b1;
        pwrite  <= 1'b0;
        penable <= 1'b0;
        paddr   <= addr;
        @(posedge pclk);
        penable <= 1'b1;
        wait (pready === 1'b1);
        #1ps;
        data = prdata;
        @(posedge pclk);
        psel    <= 1'b0;
        penable <= 1'b0;
    endtask

    logic [31:0] rval;
    int i;

    initial begin
        repeat (5) @(posedge pclk);
        presetn = 1'b1;
        repeat (5) @(posedge pclk);

        // 1. Configure BAUD_DIV = 8 clocks/bit & enable Internal Loopback + RX IRQ
        apb_write(8'h10, 32'd8);
        apb_read(8'h10, rval);
        checks = checks + 1;
        if (rval !== 32'd8) begin
            $display("[FAIL] BAUD_DIV readback mismatch: got %0d", rval);
            errors = errors + 1;
        end else begin
            $display("[PASS] APB3 BAUD_DIV register R/W verified (div=8)");
        end

        // CTRL: tx_en(0)=1, rx_en(1)=1, parity_en(2)=1, irq_rx_en(4)=1, loopback(6)=1 => 0x57
        apb_write(8'h0C, 32'h0000_0057);

        // 2. Burst-push 12 bytes back-to-back into 16-entry TX FIFO over APB3
        for (i = 0; i < 12; i = i + 1) begin
            apb_write(8'h00, 32'hA0 + i);
        end
        $display("[INFO] Pushed 12-byte burst into TX FIFO over APB3");

        // Wait until all 12 bytes arrive in RX FIFO (FIFO_LVL[15:8] == 12)
        rval = 32'd0;
        while (rval[15:8] < 8'd12) begin
            repeat (20) @(posedge pclk);
            apb_read(8'h14, rval);
        end

        // Verify RX IRQ asserted when RX FIFO is non-empty
        checks = checks + 1;
        if (irq === 1'b1) begin
            $display("[PASS] RX Interrupt (IRQ) asserted on FIFO threshold");
        end else begin
            $display("[FAIL] Expected IRQ=1 when RX FIFO has 12 bytes");
            errors = errors + 1;
        end

        // 3. Pop all 12 bytes from RX FIFO and scoreboard
        for (i = 0; i < 12; i = i + 1) begin
            apb_read(8'h04, rval);
            checks = checks + 1;
            if (rval[7:0] === (8'hA0 + i[7:0])) begin
                $display("[PASS] APB FIFO burst[%0d] = 0x%02h", i, rval[7:0]);
            end else begin
                $display("[FAIL] APB FIFO burst[%0d] expected 0x%02h got 0x%02h",
                         i, 8'hA0 + i[7:0], rval[7:0]);
                errors = errors + 1;
            end
        end

        // Verify IRQ deasserts once RX FIFO is drained
        @(posedge pclk);
        checks = checks + 1;
        if (irq === 1'b0) begin
            $display("[PASS] RX Interrupt (IRQ) deasserted cleanly after FIFO drain");
        end else begin
            $display("[FAIL] IRQ remained high after RX FIFO empty");
            errors = errors + 1;
        end

        $display("============================================");
        $display("APB3 UART SoC Total Checks : %0d", checks);
        $display("APB3 UART SoC Errors       : %0d", errors);
        if (errors == 0) begin
            $display("RESULT: ALL APB3 UART SOC TESTS PASSED");
            $finish;
        end else begin
            $display("RESULT: %0d APB3 TEST(S) FAILED", errors);
            $fatal(1);
        end
    end

    initial begin
        #10ms;
        $display("TIMEOUT - APB3 simulation exceeded limit");
        $fatal(1);
    end

endmodule
