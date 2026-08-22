module matmul_core (
    input logic clk,
    input logic rst_n,
    input logic start,
    output logic busy,
    output logic done,

    input logic wr_en,
    input logic wr_sel,
    input logic [2:0] wr_row,
    input logic [2:0] wr_col,
    input logic [15:0] wr_data,

    input logic [1:0] rd_sel,
    input logic [2:0] rd_row,
    input logic [2:0] rd_col,
    output logic [31:0] rd_data
);

    logic [15:0] mat_a [0:7] [0:7]; // 8 x 8 matrix, Q8.8 (16-bits, 8 integer, 8 fractional)
    logic [15:0] mat_b [0:7] [0:7]; // 8 x 8 matrix, Q8.8 (16-bits, 8 integer, 8 fractional)
    logic [31:0] mat_c [0:7] [0:7]; // 8 x 8 result matrix, Q16.16 (32-bits, 16 integer, 16 fractional)

    always_ff @(posedge clk) begin
        if (wr_en) begin
            if (wr_sel == 1'b0)
                mat_a[wr_row][wr_col] <= wr_data;
            else
                mat_b[wr_row][wr_col] <= wr_data;
        end
    end

    always_comb begin
        case (rd_sel)
            2'b00: rd_data = {16'b0, mat_a[rd_row][rd_col]};
            2'b01: rd_data = {16'b0, mat_b[rd_row][rd_col]};
            2'b10: rd_data = mat_c[rd_row][rd_col];
            default: rd_data = 32'd0;
        endcase
    end
endmodule