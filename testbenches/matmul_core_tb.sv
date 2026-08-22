`timescale 1ns / 1ps

module matmul_core_tb;
    // DUT connections
    logic clk;
    logic rst_n;
    logic start;
    logic busy;
    logic done;
    logic wr_en;
    logic wr_sel;
    logic [2:0] wr_row;
    logic [2:0] wr_col;
    logic [15:0] wr_data;
    logic [1:0] rd_sel;
    logic [2:0] rd_row;
    logic [2:0] rd_col;
    logic [31:0] rd_data;

    // two variables to keep track of the pass and fail counts.
    int pass_count = 0;
    int fail_count = 0;

    // clock generation
    initial clk = 0;
    always #5 clk = ~clk;

    // DUT instantiation
    matmul_core dut (
        .clk (clk),
        .rst_n (rst_n),
        .start (start),
        .busy (busy),
        .done (done),
        .wr_en (wr_en),
        .wr_sel (wr_sel),
        .wr_row (wr_row),
        .wr_col (wr_col),
        .wr_data (wr_data),
        .rd_sel (rd_sel),
        .rd_row (rd_row),
        .rd_col (rd_col),
        .rd_data (rd_data)
    );

    // This performs a write and waits for a clock edge so the write actually lands.
    task automatic do_write (
        input logic wr_sel_in,
        input logic [2:0] wr_row_in,
        input logic [2:0] wr_col_in,
        input logic [15:0] wr_data_in
    );
        wr_sel = wr_sel_in;
        wr_row = wr_row_in;
        wr_col = wr_col_in;
        wr_data = wr_data_in;
        wr_en = 1'b1;
        @(posedge clk);
        #1;
        wr_en = 1'b0;
    endtask

    // This performs a read and checks it against an expected value, this is combinational so no clock wait.
    task automatic do_read (
        input string name,
        input logic [1:0] rd_sel_in,
        input logic [2:0] rd_row_in,
        input logic [2:0] rd_col_in,
        input logic [31:0] expected
    );

        rd_sel = rd_sel_in;
        rd_row = rd_row_in;
        rd_col = rd_col_in;
        #1;
        if (expected === rd_data) begin
            pass_count++;
            $display("PASS: %-15s rd_data: %0d (0x%08h)", name, rd_data, rd_data);
        end else begin
            fail_count++;
            $display("FAIL: %-15s expected: %0d (0x%08h) got: %0d (0x%08h)", name, expected, expected, rd_data, rd_data);
        end
    endtask

    initial begin
        $display("---- matmul_core Testbench ----");
        // writing to mat_a[2][3] and reading from it.
        do_write(1'b0, 3'd2, 3'd3, 16'hABCD);
        do_read("mat_a_readback", 2'b00, 3'd2, 3'd3, 32'h0000ABCD);

        // write to mat_b[5][1] and reading from it.
        do_write(1'b1, 3'd5, 3'd1, 16'h1234);
        do_read("mat_b_readback", 2'b01, 3'd5, 3'd1, 32'h00001234);

        // confirming independence.
        do_write(1'b0, 3'd0, 3'd0, 16'hAAAA); // mat_a[0][0] = AAAA
        do_write(1'b1, 3'd0, 3'd0, 16'hBBBB); // mat_b[0][0] = BBBB
        do_read("mat_a_independence", 2'b00, 3'd0, 3'd0, 32'h0000AAAA);
        do_read("mat_b_independence", 2'b01, 3'd0, 3'd0, 32'h0000BBBB);
        $display("---- matmul_core Testbench end ----");
        if (fail_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("SOME TESTS FAILED");
        $finish;
    end
endmodule
