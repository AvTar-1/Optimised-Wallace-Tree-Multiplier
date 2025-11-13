`timescale 1ns / 1ps

module tb_array_multiplier;
    logic [15:0] A;
    logic [15:0] B;
    logic [31:0] P;
    logic [31:0] P_expected;
    assign P_expected = A * B; 

    array_multiplier_16bit dut (
        .A(A),
        .B(B),
        .P(P)
    );
    
    
    initial begin
    
        $monitor("Time=%0t | A=%h | B=%h | P=%h | Expected=%h | %s",
                 $time, A, B, P, P_expected, (P == P_expected) ? "PASS" : "FAIL");
                         
        $display("--- Determininistic test vectors ---");
        
        A = 16'h0000; B = 16'h0000; #10;
        A = 16'h0001; B = 16'h0001; #10;
        A = 16'h0002; B = 16'h0003; #10;
        A = 16'h0010; B = 16'h0010; #10;
        A = 16'h1234; B = 16'h5678; #10;
        A = 16'hAAAA; B = 16'h5555; #10;
        A = 16'hFFFF; B = 16'hFFFF; #10;
        A = 16'h8000; B = 16'h8000; #10;
        A = 16'hFFFF; B = 16'h8000; #10;
        A = 16'h0FFF; B = 16'h0FFF; #10;
        A = 16'h7FFF; B = 16'h7FFF; #10;
        A = 16'hFFFE; B = 16'hFFFF; #10;
        
        $display("--- Running 20 random test vectors ---");
        repeat (20) begin 
            A = $urandom(); 
            B = $urandom();
            #10; 
        end
        
        $display("--- Random testing complete ---");
        
        #10; 
        $stop;
    end

endmodule