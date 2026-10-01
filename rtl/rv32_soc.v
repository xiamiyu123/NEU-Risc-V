module rv32_soc #(
    parameter ADDR_BITS = 8,
    parameter IMEM_FILE = "",
    parameter DMEM_FILE = ""
) (
    input wire clk,
    input wire rst,
    output wire fault,
    output wire [4:0] fault_cause,
    output wire [31:0] fault_pc,
    output wire [31:0] fault_tval,
    output wire [31:0] debug_pc,
    output wire retire_valid,
    output wire [4:0] retire_rd,
    output wire [31:0] retire_data,
    output reg result_valid,
    output reg [31:0] result_data
);
    wire [31:0] imem_addr, imem_rdata;
    wire imem_re;
    wire [31:0] dmem_addr, dmem_wdata, dmem_rdata;
    wire dmem_re, dmem_we;
    wire [3:0] dmem_wstrb;

    rv32_core #(.MEM_ADDR_BITS(ADDR_BITS)) core (
        .clk(clk), .rst(rst),
        .imem_addr(imem_addr), .imem_re(imem_re), .imem_rdata(imem_rdata),
        .dmem_addr(dmem_addr), .dmem_wdata(dmem_wdata),
        .dmem_re(dmem_re), .dmem_we(dmem_we), .dmem_wstrb(dmem_wstrb),
        .dmem_rdata(dmem_rdata),
        .fault(fault), .fault_cause(fault_cause), .fault_pc(fault_pc),
        .fault_tval(fault_tval), .debug_pc(debug_pc), .retire_valid(retire_valid),
        .retire_rd(retire_rd), .retire_data(retire_data)
    );

    rv32_sync_mem #(.ADDR_BITS(ADDR_BITS), .INIT_FILE(IMEM_FILE)) imem (
        .clk(clk), .re(imem_re), .we(1'b0), .wstrb(4'b0), .addr(imem_addr),
        .wdata(32'b0), .rdata(imem_rdata)
    );

    rv32_sync_mem #(.ADDR_BITS(ADDR_BITS), .INIT_FILE(DMEM_FILE)) dmem (
        .clk(clk), .re(dmem_re), .we(dmem_we), .wstrb(dmem_wstrb), .addr(dmem_addr),
        .wdata(dmem_wdata), .rdata(dmem_rdata)
    );

    always @(posedge clk) begin
        if (rst) begin
            result_valid <= 0;
            result_data <= 0;
        end else if (dmem_we && dmem_addr == 0 && dmem_wstrb == 4'b1111) begin
            result_valid <= 1;
            result_data <= dmem_wdata;
        end
    end
endmodule
