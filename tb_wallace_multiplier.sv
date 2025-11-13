`timescale 1ns/1ps
// Negative Slack obtained is 1.377 in Zynq-7000 xc7z020clg484-1

module tb_wallace_multiplier;

    localparam real CLK_PERIOD_NS  = 4.0; // 4ns clock period (250 MHz)
    localparam int  LATENCY_STAGES = 4.0;  

    logic           clk;
    logic [15:0]    A, B;       
    logic [31:0]    P;          

    logic [31:0]    expected_P;
    
    logic [15:0]    A_delay [LATENCY_STAGES];
    logic [15:0]    B_delay [LATENCY_STAGES];
    logic [31:0]    expected_delay [LATENCY_STAGES];

    integer cycles = 0;

    
    wallace_multiplier_16bit dut (
        .clock(clk),
        .A(A),
        .B(B),
        .P(P)
    );

    initial begin
        clk = 0;
        forever #(CLK_PERIOD_NS / 2.0) clk = ~clk;
    end
    
    logic reset;
    initial begin
        reset = 1; 
        A = 0;
        B = 0;
        repeat (2) @(posedge clk); 
        reset = 0; 
    end

    assign expected_P = A * B; // unsigned multiply reference

    always_ff @(posedge clk) begin
        if (reset) begin
            cycles <= 0;
            for (int s = 0; s < LATENCY_STAGES; s++) begin
                A_delay[s]        <= 0;
                B_delay[s]        <= 0;
                expected_delay[s] <= 0;
            end
        end 
        
        else begin
            cycles <= cycles + 1;
            
            A_delay[0]        <= A;
            B_delay[0]        <= B;
            expected_delay[0] <= expected_P;
            
            for (int s = 1; s < LATENCY_STAGES; s++) begin
                A_delay[s]        <= A_delay[s-1];
                B_delay[s]        <= B_delay[s-1];
                expected_delay[s] <= expected_delay[s-1];
            
            end
        end
    end

    always_ff @(posedge clk) begin
        if (!reset && cycles > LATENCY_STAGES) begin
            $display("cycles=%0d | A=%h | B=%h | P=%h | Expected=%h | %s",
                     cycles, // Approximate time of input
                     A_delay[LATENCY_STAGES-1],
                     B_delay[LATENCY_STAGES-1],
                     P,
                     expected_delay[LATENCY_STAGES-1],
                     (P == expected_delay[LATENCY_STAGES-1]) ? "PASS" : "FAIL");
        end
    end

    initial begin
    
        @(negedge reset);
        @(posedge clk);

        $display("========================================");
        $display(" Optimsed Wallace Multiplier(4:2) 16x16 ");
        $display("  Pipeline Latency: %0d stages", LATENCY_STAGES);
        $display("========================================");

        // --- Test Cases from Array TB ---
        A = 16'h0000;   B = 16'h0000;   @(posedge clk);
        A = 16'h0001;   B = 16'h0001;   @(posedge clk);
        A = 16'h0002;   B = 16'h0003;   @(posedge clk);
        A = 16'h0010;   B = 16'h0010;   @(posedge clk);
        A = 16'h1234;   B = 16'h5678;   @(posedge clk);
        A = 16'hAAAA;   B = 16'h5555;   @(posedge clk);
        A = 16'hFFFF;   B = 16'hFFFF;   @(posedge clk);
        A = 16'h8000;   B = 16'h8000;   @(posedge clk);
        A = 16'hFFFF;   B = 16'h8000;   @(posedge clk);
        A = 16'h0FFF;   B = 16'h0FFF;   @(posedge clk);
        A = 16'h7FFF;   B = 16'h7FFF;   @(posedge clk);
        A = 16'hFFFE;   B = 16'hFFFF;   @(posedge clk);
        

        for (int i = 0; i < 20; i++) begin
            A = $urandom();
            B = $urandom();
            @(posedge clk);
        end

        // flush remaining pipeline results 
        repeat (LATENCY_STAGES+3) @(posedge clk);
        
        $display("All test cases completed.");
        $finish;
    end

endmodule