module matmul_avalon (
    input logic clk,
    input logic reset,
    
    // The avalon-MM slave interface
    input logic [7:0] address,
    input logic read,
    input logic write,
    input logic [31:0] writedata,
    output logic [31:0] readdata
);
    // Internal signals that will drive matmul_core ports
    logic core_start;
    logic core_busy;
    logic core_done;
    logic core_wr_en;
    logic core_wr_sel;
    logic [2:0] core_wr_row;
    logic [2:0] core_wr_col;
    logic [15:0] core_wr_data;
    logic [1:0] core_rd_sel;
    logic [2:0] core_rd_row;
    logic [2:0] core_rd_col;
    logic [31:0] core_rd_data;
    logic [7:0] wr_offset;
    logic [7:0] rd_offset;

    matmul_core core_inst (
        .clk (clk),
        .rst_n (~reset), // active high reset for avalon, but matmul_core wants low
        .start (core_start),
        .busy (core_busy),
        .done (core_done),
        .wr_en (core_wr_en),
        .wr_sel (core_wr_sel),
        .wr_row (core_wr_row),
        .wr_col (core_wr_col),
        .wr_data (core_wr_data),
        .rd_sel (core_rd_sel),
        .rd_row (core_rd_row),
        .rd_col (core_rd_col),
        .rd_data (core_rd_data)
    );

    always_ff @(posedge clk) begin
        if (reset) begin
            core_start <= 1'b0;
        end else if (write && address == 8'd0) begin
            core_start <= writedata[0];
        end
    end

    always_comb begin
        core_wr_en = 1'b0;
        core_wr_sel = 1'b0;
        core_wr_row = 3'd0;
        core_wr_col = 3'd0;
        core_wr_data = 16'd0;
        wr_offset = 8'd0;

        if (write) begin
            if (address >= 8'd1 && address <= 8'd64) begin
                // mat_a write
                core_wr_en = 1'b1;
                core_wr_sel = 1'b0;
                wr_offset = address - 8'd1;
                core_wr_row = wr_offset[5:3];
                core_wr_col = wr_offset[2:0];
                core_wr_data = writedata[15:0];
            end else if (address >= 8'd65 && address <= 8'd128) begin
                // mat_b write
                core_wr_en = 1'b1;
                core_wr_sel = 1'b1;
                wr_offset = address - 8'd65;
                core_wr_row = wr_offset[5:3];
                core_wr_col = wr_offset[2:0];
                core_wr_data = writedata[15:0];
            end
        end
    end

    always_comb begin
        readdata = 32'd0; //default
        core_rd_sel = 2'd0;
        core_rd_row = 3'd0;
        core_rd_col = 3'd0;
        rd_offset = 8'd0;
        if (read) begin
            if (address == 8'd0) begin
                // The status register read (bit 0 = busy, bit 1 = done)
                readdata = {30'd0, core_done, core_busy};
            end else if (address >= 8'd1 && address <= 8'd64) begin
                // mat_a read
                core_rd_sel = 2'd0;
                rd_offset = address - 8'd1;
                core_rd_row = rd_offset[5:3];
                core_rd_col = rd_offset[2:0];
                readdata = core_rd_data;
            end else if (address >= 8'd65 && address <= 8'd128) begin
                // mat_b read
                core_rd_sel = 2'd1;
                rd_offset = address - 8'd65;
                core_rd_row = rd_offset[5:3];
                core_rd_col = rd_offset[2:0];
                readdata = core_rd_data;
            end else if (address >= 8'd129 && address <= 8'd192) begin
                // mat_c read
                core_rd_sel = 2'd2;
                rd_offset = address - 8'd129;
                core_rd_row = rd_offset[5:3];
                core_rd_col = rd_offset[2:0];
                readdata = core_rd_data;
            end
        end
    end
endmodule