`timescale 1ns / 1ps
module matmul_avalon_tb;
    // DUT connections
    logic clk;
    logic reset;
    logic [7:0] address;
    logic read;
    logic write;
    logic [31:0] writedata;
    logic [31:0] readdata;

    // two variables to keep track of the pass and fail counts.
    int pass_count = 0;
    int fail_count = 0;

    // clock generation
    initial clk = 0;
    always #5 clk = ~clk; 

    matmul_avalon dut(
        .clk (clk),
        .reset (reset),
        .address (address),
        .read (read),
        .write (write),
        .writedata (writedata),
        .readdata (readdata)
    );

    task automatic avalon_write(
        input logic [7:0] addr_in,
        input logic [31:0] data_in
    );
        address = addr_in;
        writedata = data_in;
        write = 1'b1;
        @(posedge clk);
        #1;
        write = 1'b0;
    endtask

    task automatic avalon_read(
        input string name,
        input logic [7:0] addr_in,
        input logic [31:0] expected
    );
        address = addr_in;
        read = 1'b1;
        #1;
        if (readdata === expected) begin
            pass_count++;
            $display("PASS: %-20s readdata=%0d (0x%08h)", name, readdata, readdata);
        end else begin
            fail_count++;
            $display("FAIL: %-20s expected=%0d (0x%08h) got=%0d (0x%08h)", name, expected, expected, readdata, readdata);
        end
        read = 1'b0;
    endtask

    task automatic wait_for_done();
        logic [31:0] status;
        do begin
            address = 8'd0;
            read = 1'b1;
            #1;
            status = readdata;
            read = 1'b0;
            #1;
        end while (status[1] !== 1'b1);
    endtask

    integer r, c;

    initial begin
        $display("--- matmul_avalon Testbench start ----");

        // Proper reset sequence
        reset = 1;
        address = 8'd0;
        read = 0;
        write = 0;
        writedata = 32'd0;
        @(posedge clk);
        @(negedge clk);
        reset = 0;

        // write to mat_a[0][0] and read back
        avalon_write(8'd1, 32'd256); // mat_a[0][0] = 256 (Q8.8 = 1.0)
        avalon_read("mat_a_0_0", 8'd1, 32'd256);

        // write to mat_b[0][0] and read back
        avalon_write(8'd65, 32'd512); // mat_b[0][0] = 512 (Q8.8 = 2.0)
        avalon_read("mat_b_0_0", 8'd65, 32'd512);

        // check the status register (bit 0 = busy, bit 1 = done)
        avalon_read("status_idle", 8'd0, 32'd0);

        // another test to check my most recent changes (confirming that 'done' stays high after the computation is complete).
        avalon_write(8'd0, 32'd1); // pulse the start bit
        wait_for_done();
        avalon_read("done_stays_high_1", 8'd0, 32'd2); // bit 1 = done, bit 0 = busy
        @(posedge clk);
        @(posedge clk);
        avalon_read("done_stays_high_2", 8'd0, 32'd2); // bit 1 = done, bit 0 = busy
        @(posedge clk);
        @(posedge clk);
        avalon_read("done_stays_high_3", 8'd0, 32'd2); // bit 1 = done, bit 0 = busy
        avalon_write(8'd0, 32'd0); // clear the start bit (returnns to idle state)

        // zero out all other entries
        for (r = 0; r < 8; r = r + 1) begin
            for (c = 0; c < 8; c = c + 1) begin
                if (!(r == 0 && c == 0)) begin
                    avalon_write(8'(1 + r*8 + c), 32'd0); // for mat_a
                    avalon_write(8'(65 + r*8 + c), 32'd0); // for mat_b
                end
            end
        end

        // here we trigger the computation
        avalon_write(8'd0, 32'd1);

        // wait for it to finish
        wait_for_done();

        // now lets check the result calculated: 1.0 * 2.0 = 2.0 -> Q16.16 = 131072
        avalon_read("mat_c_0_0_final", 8'd129, 32'd131072);
        
        $display("---- matmul_avalon Testbench end ----");
        $display("Passed: %0d   Failed: %0d", pass_count, fail_count);
        if (fail_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("SOME TESTS FAILED");
        $finish;
    end
endmodule