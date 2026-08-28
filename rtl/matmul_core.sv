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

    // internal storage
    logic signed [15:0] mat_a [0:7] [0:7]; // 8 x 8 matrix, Q8.8 (16-bits: 8 integer, 8 fractional)
    logic signed [15:0] mat_b [0:7] [0:7]; // 8 x 8 matrix, Q8.8 (16-bits: 8 integer, 8 fractional)
    logic signed [31:0] mat_c [0:7] [0:7]; // 8 x 8 result matrix, Q16.16 (32-bits: 16 integer, 16 fractional)

    always_ff @(posedge clk) begin
        if (wr_en) begin
            if (wr_sel == 1'b0)
                mat_a[wr_row][wr_col] <= $signed(wr_data);
            else
                mat_b[wr_row][wr_col] <= $signed(wr_data);
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

    // The FSM
    typedef enum logic [1:0] {
        ST_IDLE, // waits for start
        ST_COMPUTE, // steps through i, j, k
        ST_DONE // finished and waits for restart
    } state_e;

    state_e state, next_state;

    logic [2:0] i;
    logic [2:0] j;
    logic [2:0] k;
    logic signed [31:0] accumulator;
    logic signed [31:0] product;

    always_comb begin
        product = mat_a[i][k] * mat_b[k][j];
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_IDLE;
            i <= 3'd0;
            j <= 3'd0;
            k <= 3'd0;
            accumulator <= 32'sd0;
        end else begin
            state <= next_state;
            if (state == ST_COMPUTE) begin
                if (k == 3'd7) begin
                    // This becomes the last-multiply accumulate for this current (i, j) pair.
                    mat_c[i][j] <= accumulator + product;
                    accumulator <= 32'sd0;
                    k <= 3'd0;
                    if (j == 3'd7) begin
                        j <= 3'd0;
                        i <= i + 3'd1;
                    end else begin
                        j <= j + 3'd1;
                    end
                end else begin
                    // Still accumulating for the current (i, j) pair.
                    accumulator <= accumulator + product;
                    k <= k + 3'd1;
                end
            end else if (state == ST_IDLE && start) begin
                // We reset counters as we are about to enter the compute state.
                i <= 3'd0;
                j <= 3'd0;
                k <= 3'd0;
                accumulator <= 32'sd0;
            end
        end
    end

    always_comb begin
        next_state = state;
        case (state)
            ST_IDLE: begin
                if (start)
                    next_state = ST_COMPUTE;
            end

            ST_COMPUTE: begin
                if (i == 3'd7 && j == 3'd7 && k == 3'd7)
                    next_state = ST_DONE;
            end

            ST_DONE: begin
                if (!start)
                    next_state = ST_IDLE;
            end
            default: next_state = ST_IDLE;
        endcase
    end

    assign busy = (state == ST_COMPUTE);
    assign done = (state == ST_DONE);
endmodule