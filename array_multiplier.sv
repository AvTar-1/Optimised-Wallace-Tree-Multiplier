`timescale 1ns / 1ps

module HA (
    input  logic A,
    input  logic B,
    output logic sum,
    output logic carry
);
    assign sum   = A ^ B;
    assign carry = A & B;
endmodule


module FA (
    input  logic A,
    input  logic B,
    input  logic cin,
    output logic sum,
    output logic carry
);
    logic s1, c1, c2;
    HA ha1 (.A(A),  .B(B),  .sum(s1), .carry(c1));
    HA ha2 (.A(s1), .B(cin), .sum(sum), .carry(c2));
    assign carry = c1 | c2;
endmodule



module array_multiplier_16bit (
    input  logic [15:0] A,
    input  logic [15:0] B,
    output logic [31:0] P
);
    
    // --- Partial Product Generation ---

    logic [15:0] partial_products [15:0];

    genvar gi, gj;
    generate
        for (gi = 0; gi < 16; gi = gi + 1) begin : pp_row
            for (gj = 0; gj < 16; gj = gj + 1) begin : pp_col
                assign partial_products[gi][gj] = A[gj] & B[gi];
            end
        end
    endgenerate


    logic [31:0] v_sum_wires   [14:0];
    logic [32:0] h_carry_wires [14:0];


    assign P[0] = partial_products[0][0];

    HA ha_0_1 (
        .A(partial_products[0][1]),
        .B(partial_products[1][0]),
        .sum(v_sum_wires[0][1]),
        .carry(h_carry_wires[0][2])
    );

    assign P[1] = v_sum_wires[0][1];
    

    assign h_carry_wires[0][1] = 1'b0; 

    
    generate
        for (gj = 2; gj < 16; gj = gj + 1) begin : row0_fa
            FA fa_r0 (
                .A(partial_products[0][gj]),
                .B(partial_products[1][gj-1]),
                .cin(h_carry_wires[0][gj]), 
                .sum(v_sum_wires[0][gj]),
                .carry(h_carry_wires[0][gj+1])
            );
        end
    endgenerate

    
    
    HA ha_0_16 (
        .A(partial_products[1][15]),
        .B(h_carry_wires[0][16]),
        .sum(v_sum_wires[0][16]),
        .carry(h_carry_wires[0][17])
    );

    
    assign v_sum_wires[0][17] = h_carry_wires[0][17];
    
    
    generate
        for (gj = 18; gj <= 31; gj = gj + 1) begin : row0_zeros
            assign v_sum_wires[0][gj] = 1'b0;
        end
    endgenerate

    //  Main Adder Array Rows 
    
    generate
        for (gi = 1; gi < 15; gi = gi + 1) begin : proc_rows
            
            HA ha_first (
                .A(v_sum_wires[gi-1][gi+1]),   
                .B(partial_products[gi+1][0]),   
                .sum(v_sum_wires[gi][gi+1]),
                .carry(h_carry_wires[gi][gi+2])
            );

            assign P[gi+1] = v_sum_wires[gi][gi+1];

            for (gj = gi + 2; gj <= gi + 16; gj = gj + 1) begin : row_mid
                FA fa_mid (
                    .A(v_sum_wires[gi-1][gj]),             
                    .B(partial_products[gi+1][gj - (gi+1)]), 
                    .cin(h_carry_wires[gi][gj]),             
                    .sum(v_sum_wires[gi][gj]),
                    .carry(h_carry_wires[gi][gj+1])        
                );
            end
            
            for (gj = gi + 17; gj <= 31; gj = gj + 1) begin : row_tail
                HA ha_tail_ripple (
                    .A(v_sum_wires[gi-1][gj]),
                    .B(h_carry_wires[gi][gj]),
                    .sum(v_sum_wires[gi][gj]),
                    .carry(h_carry_wires[gi][gj+1])
                );
            end
        end
    endgenerate

    generate
        for (gj = 16; gj <= 31; gj = gj + 1) begin : final_assign
            assign P[gj] = v_sum_wires[14][gj];
        end
    endgenerate

endmodule