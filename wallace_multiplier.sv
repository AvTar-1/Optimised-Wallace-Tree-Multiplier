`timescale 1ns/1ps

module HA (
    input  logic in_x,
    input  logic in_y,
    output logic sum_out,
    output logic carry_out
);
    assign sum_out   = in_x ^ in_y;
    assign carry_out = in_x & in_y;
endmodule


module FA (
    input  logic in_a,
    input  logic in_b,
    input  logic carry_in,
    output logic sum_out,
    output logic carry_out
);
    assign sum_out   = in_a ^ in_b ^ carry_in;
    assign carry_out = (in_a & in_b) | (in_b & carry_in) | (carry_in & in_a);
endmodule


module compressor_4_2 (
    input  logic in0, in1, in2, in3, c_in,
    output logic sum_out,
    output logic carry_local,
    output logic carry_next
);
    logic s_internal, c_internal;
    FA fa1 (
        .in_a(in0), .in_b(in1), .carry_in(in2),
        .sum_out(s_internal), .carry_out(c_internal)
    );
    FA fa2 (
        .in_a(s_internal), .in_b(in3), .carry_in(c_in),
        .sum_out(sum_out), .carry_out(carry_local)
    );
    assign carry_next = c_internal;
endmodule


module kogge_stone_adder_32 (
    input  logic [31:0] A,
    input  logic [31:0] B,
    input  logic C_in,
    output logic [31:0] Sum_out,
    output logic C_out
);
    logic [31:0] gen_sig [0:5];
    logic [31:0] prop_sig[0:5];
    genvar idx;
    generate
        for (idx = 0; idx < 32; idx++) begin
            assign gen_sig[0][idx]  = A[idx] & B[idx];
            assign prop_sig[0][idx] = A[idx] ^ B[idx];
        end
    endgenerate
    genvar stage;
    generate
        for (stage = 1; stage <= 5; stage++) begin : prefix_network_stages
            localparam int DIST = 1 << (stage - 1);
            for (idx = 0; idx < 32; idx++) begin : prefix_network_bits
                if (idx >= DIST) begin
                    assign gen_sig[stage][idx]  = gen_sig[stage-1][idx] | (prop_sig[stage-1][idx] & gen_sig[stage-1][idx-DIST]);
                    assign prop_sig[stage][idx] = prop_sig[stage-1][idx] & prop_sig[stage-1][idx-DIST];
                end else begin
                    assign gen_sig[stage][idx]  = gen_sig[stage-1][idx];
                    assign prop_sig[stage][idx] = prop_sig[stage-1][idx];
                end
            end
        end
    endgenerate
    logic [32:0] carry_vector;
    assign carry_vector[0] = C_in;
    generate
        for (idx = 0; idx < 32; idx++) begin
            assign carry_vector[idx+1] = gen_sig[5][idx] | (prop_sig[5][idx] & C_in);
            assign Sum_out[idx]        = prop_sig[0][idx] ^ carry_vector[idx];
        end
    endgenerate
    assign C_out = carry_vector[32];
endmodule


module wallace_multiplier_16bit (
    input  logic  clock,
    input  logic [15:0] A,
    input  logic [15:0] B,
    output logic [31:0] P
);


    // Partial Product Generation

    logic [31:0] partial_products [15:0];
    
    genvar row_idx, col_idx;
    generate
        for (row_idx = 0; row_idx < 16; row_idx++) begin : gen_partial_prod_rows
            logic [15:0] p_prod_row;
            for (col_idx = 0; col_idx < 16; col_idx++) begin : gen_partial_prod_cols
                assign p_prod_row[col_idx] = B[col_idx] & A[row_idx];
            end
            assign partial_products[row_idx] = {16'b0, p_prod_row} << row_idx;
        end
    endgenerate
    
    logic [31:0] partial_products_reg [15:0];

    // Stage-1 Register 

    always_ff @(posedge clock) begin
        partial_products_reg <= partial_products;
    end


    // Reduction Level 1

    logic [31:0] stage1_out [7:0];
    logic [31:0] stage1_carry [3:0];
    logic [31:0] stage1_out_reg [7:0];
    assign stage1_out[0][0] = partial_products_reg[0][0];

    HA s1_h_0_1(partial_products_reg[0][1], partial_products_reg[1][1], stage1_out[0][1], stage1_out[0][2]);
    FA s1_f_0_2(partial_products_reg[0][2], partial_products_reg[1][2], partial_products_reg[2][2], stage1_out[1][2], stage1_out[0][3]);
    assign stage1_carry[0][2] = 0;
    

    genvar s1_gen_k;
    generate
        for(s1_gen_k = 3; s1_gen_k <= 15; s1_gen_k++) begin : compressor_s1_row_1
            compressor_4_2 s1_c42_row1(
                .in0(partial_products_reg[0][s1_gen_k]),
                .in1(partial_products_reg[1][s1_gen_k]),
                .in2(partial_products_reg[2][s1_gen_k]),
                .in3(partial_products_reg[3][s1_gen_k]),
                .c_in(stage1_carry[0][s1_gen_k-1]),
                .sum_out(stage1_out[1][s1_gen_k]),
                .carry_local(stage1_out[0][s1_gen_k+1]),
                .carry_next(stage1_carry[0][s1_gen_k])
            );
        end
    endgenerate
    
    assign partial_products_reg[0][16] = 0;
    
    compressor_4_2 s1_c42_1_16(partial_products_reg[0][16], partial_products_reg[1][16], partial_products_reg[2][16], partial_products_reg[3][16], stage1_carry[0][15], stage1_out[1][16], stage1_out[0][17], stage1_carry[0][16]);
    
    FA s1_f_1_17(partial_products_reg[2][17], partial_products_reg[3][17], stage1_carry[0][16], stage1_out[1][17], stage1_out[0][18]);
    
    assign stage1_out[1][18] = partial_products_reg[3][18];
    assign stage1_out[2][4] = partial_products_reg[4][4];
    
    HA s1_h_4_5(partial_products_reg[4][5], partial_products_reg[5][5], stage1_out[2][5], stage1_out[2][6]);
    
    FA s1_f_4_6(partial_products_reg[4][6], partial_products_reg[5][6], partial_products_reg[6][6], stage1_out[3][6], stage1_out[2][7]);
    
    assign stage1_carry[1][6] = 0;
    
    
    genvar s1_gen_l;
    generate
        for(s1_gen_l = 7; s1_gen_l <= 19; s1_gen_l++) begin : compressor_s1_row_2
            compressor_4_2 s1_c42_row2(
                .in0(partial_products_reg[4][s1_gen_l]),
                .in1(partial_products_reg[5][s1_gen_l]),
                .in2(partial_products_reg[6][s1_gen_l]),
                .in3(partial_products_reg[7][s1_gen_l]),
                .c_in(stage1_carry[1][s1_gen_l-1]),
                .sum_out(stage1_out[3][s1_gen_l]),
                .carry_local(stage1_out[2][s1_gen_l+1]),
                .carry_next(stage1_carry[1][s1_gen_l])
            );
        end
    endgenerate
    
    assign partial_products_reg[4][20] = 0;
    
    compressor_4_2 s1_c42_2_20(partial_products_reg[4][20], partial_products_reg[5][20], partial_products_reg[6][20], partial_products_reg[7][20], stage1_carry[1][19], stage1_out[3][20], stage1_out[2][21], stage1_carry[1][20]);
    
    FA s1_f_5_21(partial_products_reg[6][21], partial_products_reg[7][21], stage1_carry[1][20], stage1_out[3][21], stage1_out[2][22]);
    
    assign stage1_out[3][22] = partial_products_reg[7][22];
    assign stage1_out[4][8] = partial_products_reg[8][8];
    
    HA s1_h_8_9(partial_products_reg[8][9], partial_products_reg[9][9], stage1_out[4][9], stage1_out[4][10]);
    
    FA s1_f_8_10(partial_products_reg[8][10], partial_products_reg[9][10], partial_products_reg[10][10], stage1_out[5][10], stage1_out[4][11]);
    
    assign stage1_carry[2][10] = 0;
    
    
    genvar s1_gen_m;
    generate
        for(s1_gen_m = 11; s1_gen_m <= 23; s1_gen_m++) begin : compressor_s1_row_3
            compressor_4_2 s1_c42_row3(
                .in0(partial_products_reg[8][s1_gen_m]),
                .in1(partial_products_reg[9][s1_gen_m]),
                .in2(partial_products_reg[10][s1_gen_m]),
                .in3(partial_products_reg[11][s1_gen_m]),
                .c_in(stage1_carry[2][s1_gen_m-1]),
                .sum_out(stage1_out[5][s1_gen_m]),
                .carry_local(stage1_out[4][s1_gen_m+1]),
                .carry_next(stage1_carry[2][s1_gen_m])
            );
        end
    endgenerate
    
    assign partial_products_reg[8][24] = 0;
    
    compressor_4_2 s1_c42_3_24(partial_products_reg[8][24], partial_products_reg[9][24], partial_products_reg[10][24], partial_products_reg[11][24], stage1_carry[2][23], stage1_out[5][24], stage1_out[4][25], stage1_carry[2][24]);
    
    FA s1_f_9_25(partial_products_reg[10][25], partial_products_reg[11][25], stage1_carry[2][24], stage1_out[5][25], stage1_out[4][26]);
    
    assign stage1_out[5][26] = partial_products_reg[11][26];
    assign stage1_out[6][12] = partial_products_reg[12][12];
    
    HA s1_h_12_13(partial_products_reg[12][13], partial_products_reg[13][13], stage1_out[6][13], stage1_out[6][14]);
    
    FA s1_f_12_14(partial_products_reg[12][14], partial_products_reg[13][14], partial_products_reg[14][14], stage1_out[7][14], stage1_out[6][15]);
    
    assign stage1_carry[3][14] = 0;
    
    
    genvar s1_gen_n;
    generate
        for(s1_gen_n = 15; s1_gen_n <= 27; s1_gen_n++) begin : compressor_s1_row_4
            compressor_4_2 s1_c42_row4(
                .in0(partial_products_reg[12][s1_gen_n]),
                .in1(partial_products_reg[13][s1_gen_n]),
                .in2(partial_products_reg[14][s1_gen_n]),
                .in3(partial_products_reg[15][s1_gen_n]),
                .c_in(stage1_carry[3][s1_gen_n-1]),
                .sum_out(stage1_out[7][s1_gen_n]),
                .carry_local(stage1_out[6][s1_gen_n+1]),
                .carry_next(stage1_carry[3][s1_gen_n])
            );
        end
    endgenerate
    
    assign partial_products_reg[12][28] = 0;
    
    compressor_4_2 s1_c42_4_28(partial_products_reg[12][28], partial_products_reg[13][28], partial_products_reg[14][28], partial_products_reg[15][28], stage1_carry[3][27], stage1_out[7][28], stage1_out[6][29], stage1_carry[3][28]);
    
    FA s1_f_13_29(partial_products_reg[14][29], partial_products_reg[15][29], stage1_carry[3][28], stage1_out[7][29], stage1_out[6][30]);
    
    assign stage1_out[7][30] = partial_products_reg[15][30];
    
    
    // Stage 1 Register 

    always_ff @(posedge clock) begin
        stage1_out_reg <= stage1_out;
    end
    
    
    
    // Reduction Level 2 
    
    logic [31:0] stage2_out [3:0];
    logic [31:0] stage2_carry [1:0];
    logic [31:0] stage2_out_reg [3:0];
    
    
    assign stage2_out[0][0] = stage1_out_reg[0][0];
    assign stage2_out[0][1] = stage1_out_reg[0][1];
    
    HA s2_h_0_2(stage1_out_reg[0][2], stage1_out_reg[1][2], stage2_out[0][2], stage2_out[1][3]);
    HA s2_h_0_3(stage1_out_reg[0][3], stage1_out_reg[1][3], stage2_out[0][3], stage2_out[1][4]);
    
    FA s2_f_0_4(stage1_out_reg[0][4], stage1_out_reg[1][4], stage1_out_reg[2][4], stage2_out[0][4], stage2_out[1][5]);
    FA s2_f_0_5(stage1_out_reg[0][5], stage1_out_reg[1][5], stage1_out_reg[2][5], stage2_out[0][5], stage2_out[1][6]);
    
    assign stage2_carry[0][5] = 0;
    
    
    genvar s2_gen_q;
    generate
        for(s2_gen_q = 6; s2_gen_q <= 18; s2_gen_q++) begin : compressor_s2_row_1
            compressor_4_2 s2_c42_row1(
                .in0(stage1_out_reg[0][s2_gen_q]),
                .in1(stage1_out_reg[1][s2_gen_q]),
                .in2(stage1_out_reg[2][s2_gen_q]),
                .in3(stage1_out_reg[3][s2_gen_q]),
                .c_in(stage2_carry[0][s2_gen_q-1]),
                .sum_out(stage2_out[0][s2_gen_q]),
                .carry_local(stage2_out[1][s2_gen_q+1]),
                .carry_next(stage2_carry[0][s2_gen_q])
            );
        end
    endgenerate
    
    FA s2_f_1_19(stage1_out_reg[2][19], stage1_out_reg[3][19], stage2_carry[0][18], stage2_out[0][19], stage2_out[1][20]);
    
    HA s2_h_2_20(stage1_out_reg[2][20], stage1_out_reg[3][20], stage2_out[0][20], stage2_out[1][21]);
    HA s2_h_2_21(stage1_out_reg[2][21], stage1_out_reg[3][21], stage2_out[0][21], stage2_out[1][22]);
    HA s2_h_2_22(stage1_out_reg[2][22], stage1_out_reg[3][22], stage2_out[0][22], stage2_out[1][23]);
    
    
    assign stage2_out[2][8] = stage1_out_reg[4][8];
    assign stage2_out[2][9] = stage1_out_reg[4][9];
    
    HA s2_h_4_10(stage1_out_reg[4][10], stage1_out_reg[5][10], stage2_out[2][10], stage2_out[3][11]);
    HA s2_h_4_11(stage1_out_reg[4][11], stage1_out_reg[5][11], stage2_out[2][11], stage2_out[3][12]);
    
    FA s2_f_4_12(stage1_out_reg[4][12], stage1_out_reg[5][12], stage1_out_reg[6][12], stage2_out[2][12], stage2_out[3][13]);
    FA s2_f_4_13(stage1_out_reg[4][13], stage1_out_reg[5][13], stage1_out_reg[6][13], stage2_out[2][13], stage2_out[3][14]);
    
    assign stage2_carry[1][13] = 0;
    
    
    
    genvar s2_gen_r;
    generate
        for(s2_gen_r = 14; s2_gen_r <= 26; s2_gen_r++) begin : compressor_s2_row_2
            compressor_4_2 s2_c42_row2(
                .in0(stage1_out_reg[4][s2_gen_r]),
                .in1(stage1_out_reg[5][s2_gen_r]),
                .in2(stage1_out_reg[6][s2_gen_r]),
                .in3(stage1_out_reg[7][s2_gen_r]),
                .c_in(stage2_carry[1][s2_gen_r-1]),
                .sum_out(stage2_out[2][s2_gen_r]),
                .carry_local(stage2_out[3][s2_gen_r+1]),
                .carry_next(stage2_carry[1][s2_gen_r])
            );
        end
    endgenerate
    
    FA s2_f_5_27(stage1_out_reg[6][27], stage1_out_reg[7][27], stage2_carry[1][26], stage2_out[2][27], stage2_out[3][28]);
    
    HA s2_h_6_28(stage1_out_reg[6][28], stage1_out_reg[7][28], stage2_out[2][28], stage2_out[3][29]);
    HA s2_h_6_29(stage1_out_reg[6][29], stage1_out_reg[7][29], stage2_out[2][29], stage2_out[3][30]);
    HA s2_h_6_30(stage1_out_reg[6][30], stage1_out_reg[7][30], stage2_out[2][30], stage2_out[3][31]);
    
    // Stage 2 Register
    always_ff @(posedge clock) begin
        stage2_out_reg <= stage2_out;
    end
    


    // Reduction Level 3

    logic [31:0] stage3_out [1:0];
    logic [31:0] stage3_out_reg [1:0];
    logic [31:0] stage3_carry [0:0];
    
    assign stage3_out[0][0] = stage2_out_reg[0][0];
    assign stage3_out[0][1] = stage2_out_reg[0][1];
    assign stage3_out[0][2] = stage2_out_reg[0][2];
    assign stage3_out[1][0] = 1'b0;
    assign stage3_out[1][1] = 1'b0;
    assign stage3_out[1][2] = 1'b0;
    assign stage3_out[1][3] = 1'b0;
    
    HA s3_h_0_3(stage2_out_reg[0][3], stage2_out_reg[1][3], stage3_out[0][3], stage3_out[1][4]);
    HA s3_h_0_4(stage2_out_reg[0][4], stage2_out_reg[1][4], stage3_out[0][4], stage3_out[1][5]);
    HA s3_h_0_5(stage2_out_reg[0][5], stage2_out_reg[1][5], stage3_out[0][5], stage3_out[1][6]);
    HA s3_h_0_6(stage2_out_reg[0][6], stage2_out_reg[1][6], stage3_out[0][6], stage3_out[1][7]);
    HA s3_h_0_7(stage2_out_reg[0][7], stage2_out_reg[1][7], stage3_out[0][7], stage3_out[1][8]);
    
    FA s3_f_0_8(stage2_out_reg[0][8], stage2_out_reg[1][8], stage2_out_reg[2][8], stage3_out[0][8], stage3_out[1][9]);
    FA s3_f_0_9(stage2_out_reg[0][9], stage2_out_reg[1][9], stage2_out_reg[2][9], stage3_out[0][9], stage3_out[1][10]);
    FA s3_f_0_10(stage2_out_reg[0][10], stage2_out_reg[1][10], stage2_out_reg[2][10], stage3_out[0][10], stage3_out[1][11]);
    
    assign stage3_carry[0][10] = 0;
    
    
    genvar s3_gen_s;
    generate
        for(s3_gen_s = 11; s3_gen_s <= 22; s3_gen_s++) begin : compressor_s3_row_1
            compressor_4_2 s3_c42_row1(
                .in0(stage2_out_reg[0][s3_gen_s]),
                .in1(stage2_out_reg[1][s3_gen_s]),
                .in2(stage2_out_reg[2][s3_gen_s]),
                .in3(stage2_out_reg[3][s3_gen_s]),
                .c_in(stage3_carry[0][s3_gen_s-1]),
                .sum_out(stage3_out[0][s3_gen_s]),
                .carry_local(stage3_out[1][s3_gen_s+1]),
                .carry_next(stage3_carry[0][s3_gen_s])
            );
        end
    endgenerate
    
    
    
    compressor_4_2 s3_c42_1_23(
        .in0(1'b0),
        .in1(stage2_out_reg[1][23]),
        .in2(stage2_out_reg[2][23]),
        .in3(stage2_out_reg[3][23]),
        .c_in(stage3_carry[0][22]),
        .sum_out(stage3_out[0][23]),
        .carry_local(stage3_out[1][24]),
        .carry_next(stage3_carry[0][23])
    );
    
    
    FA s3_f_2_24(stage2_out_reg[2][24], stage2_out_reg[3][24], stage3_carry[0][23], stage3_out[0][24], stage3_out[1][25]);
    
    HA s3_h_2_25(stage2_out_reg[2][25], stage2_out_reg[3][25], stage3_out[0][25], stage3_out[1][26]);
    HA s3_h_2_26(stage2_out_reg[2][26], stage2_out_reg[3][26], stage3_out[0][26], stage3_out[1][27]);
    HA s3_h_2_27(stage2_out_reg[2][27], stage2_out_reg[3][27], stage3_out[0][27], stage3_out[1][28]);
    HA s3_h_2_28(stage2_out_reg[2][28], stage2_out_reg[3][28], stage3_out[0][28], stage3_out[1][29]);
    HA s3_h_2_29(stage2_out_reg[2][29], stage2_out_reg[3][29], stage3_out[0][29], stage3_out[1][30]);
    HA s3_h_2_30(stage2_out_reg[2][30], stage2_out_reg[3][30], stage3_out[0][30], stage3_out[1][31]);
    
    
    assign stage3_out[0][31] = stage2_out_reg[3][31];
    
    
    // Stage 3 register 
    always_ff @(posedge clock) begin
        stage3_out_reg <= stage3_out;
    end


    logic        final_carry_out;
    logic [31:0] final_sum;

    kogge_stone_adder_32 final_stage_adder (
        .A    (stage3_out_reg[0]),
        .B    (stage3_out_reg[1]),
        .C_in (1'b0),
        .Sum_out (P),
        .C_out   (final_carry_out)
    );

//    always_ff @(posedge clock) begin
//        P <= final_sum;
//    end
endmodule
