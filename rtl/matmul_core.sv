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
    logic signed [31:0] product [0:7];
    // here we widened the adder-tree signals since adding multiple signed 32-bit products can require extra bits.
    logic signed [32:0] sum_level1 [0:3];
    logic signed [33:0] sum_level2 [0:1];
    logic signed [34:0] dot_product;

    always_comb begin
        for (int n = 0; n < 8; n++) begin
            product[n] = mat_a[i][n] * mat_b[n][j];
        end

        // first adder tree level
        sum_level1[0] = $signed(product[0]) + $signed(product[1]);
        sum_level1[1] = $signed(product[2]) + $signed(product[3]);
        sum_level1[2] = $signed(product[4]) + $signed(product[5]);
        sum_level1[3] = $signed(product[6]) + $signed(product[7]);

        // second adder tree level
        sum_level2[0] = $signed(sum_level1[0]) + $signed(sum_level1[1]);
        sum_level2[1] = $signed(sum_level1[2]) + $signed(sum_level1[3]);
        dot_product = $signed(sum_level2[0]) + $signed(sum_level2[1]);
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_IDLE;
            i <= 3'd0;
            j <= 3'd0;
        end else begin
            state <= next_state;
            if (state == ST_COMPUTE) begin
                // Here we have one complete dot product for the current (i, j) pair, so we can store it in mat_c.
                mat_c[i][j] <= dot_product[31:0]; // store the lower 32 bits of the dot product
                if (j == 3'd7) begin
                    j <= 3'd0;
                    if (i < 3'd7) begin
                        i <= i + 3'd1;
                    end
                end else begin
                    j <= j + 3'd1;
                end
            end else if (state == ST_IDLE && start) begin
                // We reset counters as we are about to enter the compute state.
                i <= 3'd0;
                j <= 3'd0;
            end
        end
    end

    // Next state logic
    always_comb begin
        next_state = state;
        case (state)
            ST_IDLE: begin
                if (start)
                    next_state = ST_COMPUTE;
            end

            ST_COMPUTE: begin
                if (i == 3'd7 && j == 3'd7)
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