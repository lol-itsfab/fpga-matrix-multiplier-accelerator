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

    integer r, c;

    initial begin
        $display("---- matmul_core Testbench ----");

        // proper reset sequence
        rst_n = 0;
        start = 0;
        @(posedge clk);
        @(negedge clk);
        rst_n = 1;

        // This is the zeroing loop
        for (r = 0; r < 8; r = r + 1) begin
            for (c = 0; c < 8; c = c + 1) begin
                do_write(1'b0, r[2:0], c[2:0], 16'd0);
                do_write(1'b1, r[2:0], c[2:0], 16'd0);
            end
        end

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

        for (c = 0; c < 8; c = c + 1) begin
            for (r = 0; r < 8; r = r + 1) begin
                do_write(1'b0, r[2:0], c[2:0], 16'd0);
                do_write(1'b1, r[2:0], c[2:0], 16'd0);
            end
        end

        do_write(1'b0, 3'd0, 3'd0, 16'd256);
        do_write(1'b1, 3'd0, 3'd0, 16'd256);
        do_write(1'b0, 3'd0, 3'd1, 16'd512);
        do_write(1'b1, 3'd1, 3'd0, 16'd256);
        do_write(1'b0, 3'd0, 3'd2, 16'd256);
        do_write(1'b1, 3'd2, 3'd0, 16'd768);

        start = 1'b1;
        @(posedge clk);
        #1;
        start = 1'b0;
        wait (done == 1'b1);

        do_read("mat_c_multiterm", 2'b10, 3'd0, 3'd0, 32'd393216);

        // full 8 x 8 multiplication with all distinct values.
        for (r = 0; r < 8; r = r + 1) begin
            for (c = 0; c < 8; c = c + 1) begin
                do_write(1'b0, r[2:0], c[2:0], 16'd0);
                do_write(1'b1, r[2:0], c[2:0], 16'd0);
            end
        end

        // loading mat_a entry values
         do_write(1'b0, 3'd0, 3'd0, 16'd256);
        do_write(1'b0, 3'd0, 3'd1, 16'd512);
        do_write(1'b0, 3'd0, 3'd2, 16'd768);
        do_write(1'b0, 3'd0, 3'd3, 16'd1024);
        do_write(1'b0, 3'd0, 3'd4, 16'd1280);
        do_write(1'b0, 3'd0, 3'd5, 16'd1536);
        do_write(1'b0, 3'd0, 3'd6, 16'd1792);
        do_write(1'b0, 3'd0, 3'd7, 16'd2048);
        do_write(1'b0, 3'd1, 3'd0, 16'd512);
        do_write(1'b0, 3'd1, 3'd1, 16'd768);
        do_write(1'b0, 3'd1, 3'd2, 16'd1024);
        do_write(1'b0, 3'd1, 3'd3, 16'd1280);
        do_write(1'b0, 3'd1, 3'd4, 16'd1536);
        do_write(1'b0, 3'd1, 3'd5, 16'd1792);
        do_write(1'b0, 3'd1, 3'd6, 16'd2048);
        do_write(1'b0, 3'd1, 3'd7, 16'd256);
        do_write(1'b0, 3'd2, 3'd0, 16'd768);
        do_write(1'b0, 3'd2, 3'd1, 16'd1024);
        do_write(1'b0, 3'd2, 3'd2, 16'd1280);
        do_write(1'b0, 3'd2, 3'd3, 16'd1536);
        do_write(1'b0, 3'd2, 3'd4, 16'd1792);
        do_write(1'b0, 3'd2, 3'd5, 16'd2048);
        do_write(1'b0, 3'd2, 3'd6, 16'd256);
        do_write(1'b0, 3'd2, 3'd7, 16'd512);
        do_write(1'b0, 3'd3, 3'd0, 16'd1024);
        do_write(1'b0, 3'd3, 3'd1, 16'd1280);
        do_write(1'b0, 3'd3, 3'd2, 16'd1536);
        do_write(1'b0, 3'd3, 3'd3, 16'd1792);
        do_write(1'b0, 3'd3, 3'd4, 16'd2048);
        do_write(1'b0, 3'd3, 3'd5, 16'd256);
        do_write(1'b0, 3'd3, 3'd6, 16'd512);
        do_write(1'b0, 3'd3, 3'd7, 16'd768);
        do_write(1'b0, 3'd4, 3'd0, 16'd1280);
        do_write(1'b0, 3'd4, 3'd1, 16'd1536);
        do_write(1'b0, 3'd4, 3'd2, 16'd1792);
        do_write(1'b0, 3'd4, 3'd3, 16'd2048);
        do_write(1'b0, 3'd4, 3'd4, 16'd256);
        do_write(1'b0, 3'd4, 3'd5, 16'd512);
        do_write(1'b0, 3'd4, 3'd6, 16'd768);
        do_write(1'b0, 3'd4, 3'd7, 16'd1024);
        do_write(1'b0, 3'd5, 3'd0, 16'd1536);
        do_write(1'b0, 3'd5, 3'd1, 16'd1792);
        do_write(1'b0, 3'd5, 3'd2, 16'd2048);
        do_write(1'b0, 3'd5, 3'd3, 16'd256);
        do_write(1'b0, 3'd5, 3'd4, 16'd512);
        do_write(1'b0, 3'd5, 3'd5, 16'd768);
        do_write(1'b0, 3'd5, 3'd6, 16'd1024);
        do_write(1'b0, 3'd5, 3'd7, 16'd1280);
        do_write(1'b0, 3'd6, 3'd0, 16'd1792);
        do_write(1'b0, 3'd6, 3'd1, 16'd2048);
        do_write(1'b0, 3'd6, 3'd2, 16'd256);
        do_write(1'b0, 3'd6, 3'd3, 16'd512);
        do_write(1'b0, 3'd6, 3'd4, 16'd768);
        do_write(1'b0, 3'd6, 3'd5, 16'd1024);
        do_write(1'b0, 3'd6, 3'd6, 16'd1280);
        do_write(1'b0, 3'd6, 3'd7, 16'd1536);
        do_write(1'b0, 3'd7, 3'd0, 16'd2048);
        do_write(1'b0, 3'd7, 3'd1, 16'd256);
        do_write(1'b0, 3'd7, 3'd2, 16'd512);
        do_write(1'b0, 3'd7, 3'd3, 16'd768);
        do_write(1'b0, 3'd7, 3'd4, 16'd1024);
        do_write(1'b0, 3'd7, 3'd5, 16'd1280);
        do_write(1'b0, 3'd7, 3'd6, 16'd1536);
        do_write(1'b0, 3'd7, 3'd7, 16'd1792);

        // loading mat_b entry values
        do_write(1'b1, 3'd0, 3'd0, 16'd256);
        do_write(1'b1, 3'd0, 3'd1, 16'd512);
        do_write(1'b1, 3'd0, 3'd2, 16'd768);
        do_write(1'b1, 3'd0, 3'd3, 16'd1024);
        do_write(1'b1, 3'd0, 3'd4, 16'd1280);
        do_write(1'b1, 3'd0, 3'd5, 16'd1536);
        do_write(1'b1, 3'd0, 3'd6, 16'd1792);
        do_write(1'b1, 3'd0, 3'd7, 16'd2048);
        do_write(1'b1, 3'd1, 3'd0, 16'd768);
        do_write(1'b1, 3'd1, 3'd1, 16'd1024);
        do_write(1'b1, 3'd1, 3'd2, 16'd1280);
        do_write(1'b1, 3'd1, 3'd3, 16'd1536);
        do_write(1'b1, 3'd1, 3'd4, 16'd1792);
        do_write(1'b1, 3'd1, 3'd5, 16'd2048);
        do_write(1'b1, 3'd1, 3'd6, 16'd256);
        do_write(1'b1, 3'd1, 3'd7, 16'd512);
        do_write(1'b1, 3'd2, 3'd0, 16'd1280);
        do_write(1'b1, 3'd2, 3'd1, 16'd1536);
        do_write(1'b1, 3'd2, 3'd2, 16'd1792);
        do_write(1'b1, 3'd2, 3'd3, 16'd2048);
        do_write(1'b1, 3'd2, 3'd4, 16'd256);
        do_write(1'b1, 3'd2, 3'd5, 16'd512);
        do_write(1'b1, 3'd2, 3'd6, 16'd768);
        do_write(1'b1, 3'd2, 3'd7, 16'd1024);
        do_write(1'b1, 3'd3, 3'd0, 16'd1792);
        do_write(1'b1, 3'd3, 3'd1, 16'd2048);
        do_write(1'b1, 3'd3, 3'd2, 16'd256);
        do_write(1'b1, 3'd3, 3'd3, 16'd512);
        do_write(1'b1, 3'd3, 3'd4, 16'd768);
        do_write(1'b1, 3'd3, 3'd5, 16'd1024);
        do_write(1'b1, 3'd3, 3'd6, 16'd1280);
        do_write(1'b1, 3'd3, 3'd7, 16'd1536);
        do_write(1'b1, 3'd4, 3'd0, 16'd256);
        do_write(1'b1, 3'd4, 3'd1, 16'd512);
        do_write(1'b1, 3'd4, 3'd2, 16'd768);
        do_write(1'b1, 3'd4, 3'd3, 16'd1024);
        do_write(1'b1, 3'd4, 3'd4, 16'd1280);
        do_write(1'b1, 3'd4, 3'd5, 16'd1536);
        do_write(1'b1, 3'd4, 3'd6, 16'd1792);
        do_write(1'b1, 3'd4, 3'd7, 16'd2048);
        do_write(1'b1, 3'd5, 3'd0, 16'd768);
        do_write(1'b1, 3'd5, 3'd1, 16'd1024);
        do_write(1'b1, 3'd5, 3'd2, 16'd1280);
        do_write(1'b1, 3'd5, 3'd3, 16'd1536);
        do_write(1'b1, 3'd5, 3'd4, 16'd1792);
        do_write(1'b1, 3'd5, 3'd5, 16'd2048);
        do_write(1'b1, 3'd5, 3'd6, 16'd256);
        do_write(1'b1, 3'd5, 3'd7, 16'd512);
        do_write(1'b1, 3'd6, 3'd0, 16'd1280);
        do_write(1'b1, 3'd6, 3'd1, 16'd1536);
        do_write(1'b1, 3'd6, 3'd2, 16'd1792);
        do_write(1'b1, 3'd6, 3'd3, 16'd2048);
        do_write(1'b1, 3'd6, 3'd4, 16'd256);
        do_write(1'b1, 3'd6, 3'd5, 16'd512);
        do_write(1'b1, 3'd6, 3'd6, 16'd768);
        do_write(1'b1, 3'd6, 3'd7, 16'd1024);
        do_write(1'b1, 3'd7, 3'd0, 16'd1792);
        do_write(1'b1, 3'd7, 3'd1, 16'd2048);
        do_write(1'b1, 3'd7, 3'd2, 16'd256);
        do_write(1'b1, 3'd7, 3'd3, 16'd512);
        do_write(1'b1, 3'd7, 3'd4, 16'd768);
        do_write(1'b1, 3'd7, 3'd5, 16'd1024);
        do_write(1'b1, 3'd7, 3'd6, 16'd1280);
        do_write(1'b1, 3'd7, 3'd7, 16'd1536);

        // multiply
        start = 1'b1;
        @(posedge clk);
        #1;
        start = 1'b0;
        wait (done == 1'b1);

        // check all 64 outputs
        do_read("mat_c_0_0", 2'b10, 3'd0, 3'd0, 32'd10747904);
        do_read("mat_c_0_1", 2'b10, 3'd0, 3'd1, 32'd13107200);
        do_read("mat_c_0_2", 2'b10, 3'd0, 3'd2, 32'd9175040);
        do_read("mat_c_0_3", 2'b10, 3'd0, 3'd3, 32'd11534336);
        do_read("mat_c_0_4", 2'b10, 3'd0, 3'd4, 32'd8650752);
        do_read("mat_c_0_5", 2'b10, 3'd0, 3'd5, 32'd11010048);
        do_read("mat_c_0_6", 2'b10, 3'd0, 3'd6, 32'd9175040);
        do_read("mat_c_0_7", 2'b10, 3'd0, 3'd7, 32'd11534336);
        do_read("mat_c_1_0", 2'b10, 3'd1, 3'd0, 32'd9175040);
        do_read("mat_c_1_1", 2'b10, 3'd1, 3'd1, 32'd11534336);
        do_read("mat_c_1_2", 2'b10, 3'd1, 3'd2, 32'd10747904);
        do_read("mat_c_1_3", 2'b10, 3'd1, 3'd3, 32'd13107200);
        do_read("mat_c_1_4", 2'b10, 3'd1, 3'd4, 32'd9175040);
        do_read("mat_c_1_5", 2'b10, 3'd1, 3'd5, 32'd11534336);
        do_read("mat_c_1_6", 2'b10, 3'd1, 3'd6, 32'd8650752);
        do_read("mat_c_1_7", 2'b10, 3'd1, 3'd7, 32'd11010048);
        do_read("mat_c_2_0", 2'b10, 3'd2, 3'd0, 32'd8650752);
        do_read("mat_c_2_1", 2'b10, 3'd2, 3'd1, 32'd11010048);
        do_read("mat_c_2_2", 2'b10, 3'd2, 3'd2, 32'd9175040);
        do_read("mat_c_2_3", 2'b10, 3'd2, 3'd3, 32'd11534336);
        do_read("mat_c_2_4", 2'b10, 3'd2, 3'd4, 32'd10747904);
        do_read("mat_c_2_5", 2'b10, 3'd2, 3'd5, 32'd13107200);
        do_read("mat_c_2_6", 2'b10, 3'd2, 3'd6, 32'd9175040);
        do_read("mat_c_2_7", 2'b10, 3'd2, 3'd7, 32'd11534336);
        do_read("mat_c_3_0", 2'b10, 3'd3, 3'd0, 32'd9175040);
        do_read("mat_c_3_1", 2'b10, 3'd3, 3'd1, 32'd11534336);
        do_read("mat_c_3_2", 2'b10, 3'd3, 3'd2, 32'd8650752);
        do_read("mat_c_3_3", 2'b10, 3'd3, 3'd3, 32'd11010048);
        do_read("mat_c_3_4", 2'b10, 3'd3, 3'd4, 32'd9175040);
        do_read("mat_c_3_5", 2'b10, 3'd3, 3'd5, 32'd11534336);
        do_read("mat_c_3_6", 2'b10, 3'd3, 3'd6, 32'd10747904);
        do_read("mat_c_3_7", 2'b10, 3'd3, 3'd7, 32'd13107200);
        do_read("mat_c_4_0", 2'b10, 3'd4, 3'd0, 32'd10747904);
        do_read("mat_c_4_1", 2'b10, 3'd4, 3'd1, 32'd13107200);
        do_read("mat_c_4_2", 2'b10, 3'd4, 3'd2, 32'd9175040);
        do_read("mat_c_4_3", 2'b10, 3'd4, 3'd3, 32'd11534336);
        do_read("mat_c_4_4", 2'b10, 3'd4, 3'd4, 32'd8650752);
        do_read("mat_c_4_5", 2'b10, 3'd4, 3'd5, 32'd11010048);
        do_read("mat_c_4_6", 2'b10, 3'd4, 3'd6, 32'd9175040);
        do_read("mat_c_4_7", 2'b10, 3'd4, 3'd7, 32'd11534336);
        do_read("mat_c_5_0", 2'b10, 3'd5, 3'd0, 32'd9175040);
        do_read("mat_c_5_1", 2'b10, 3'd5, 3'd1, 32'd11534336);
        do_read("mat_c_5_2", 2'b10, 3'd5, 3'd2, 32'd10747904);
        do_read("mat_c_5_3", 2'b10, 3'd5, 3'd3, 32'd13107200);
        do_read("mat_c_5_4", 2'b10, 3'd5, 3'd4, 32'd9175040);
        do_read("mat_c_5_5", 2'b10, 3'd5, 3'd5, 32'd11534336);
        do_read("mat_c_5_6", 2'b10, 3'd5, 3'd6, 32'd8650752);
        do_read("mat_c_5_7", 2'b10, 3'd5, 3'd7, 32'd11010048);
        do_read("mat_c_6_0", 2'b10, 3'd6, 3'd0, 32'd8650752);
        do_read("mat_c_6_1", 2'b10, 3'd6, 3'd1, 32'd11010048);
        do_read("mat_c_6_2", 2'b10, 3'd6, 3'd2, 32'd9175040);
        do_read("mat_c_6_3", 2'b10, 3'd6, 3'd3, 32'd11534336);
        do_read("mat_c_6_4", 2'b10, 3'd6, 3'd4, 32'd10747904);
        do_read("mat_c_6_5", 2'b10, 3'd6, 3'd5, 32'd13107200);
        do_read("mat_c_6_6", 2'b10, 3'd6, 3'd6, 32'd9175040);
        do_read("mat_c_6_7", 2'b10, 3'd6, 3'd7, 32'd11534336);
        do_read("mat_c_7_0", 2'b10, 3'd7, 3'd0, 32'd9175040);
        do_read("mat_c_7_1", 2'b10, 3'd7, 3'd1, 32'd11534336);
        do_read("mat_c_7_2", 2'b10, 3'd7, 3'd2, 32'd8650752);
        do_read("mat_c_7_3", 2'b10, 3'd7, 3'd3, 32'd11010048);
        do_read("mat_c_7_4", 2'b10, 3'd7, 3'd4, 32'd9175040);
        do_read("mat_c_7_5", 2'b10, 3'd7, 3'd5, 32'd11534336);
        do_read("mat_c_7_6", 2'b10, 3'd7, 3'd6, 32'd10747904);
        do_read("mat_c_7_7", 2'b10, 3'd7, 3'd7, 32'd13107200);

        $display("---- matmul_core Testbench end ----");
        $display("Passed: %0d   Failed: %0d", pass_count, fail_count);
        if (fail_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("SOME TESTS FAILED");
        $finish;
    end
endmodule
