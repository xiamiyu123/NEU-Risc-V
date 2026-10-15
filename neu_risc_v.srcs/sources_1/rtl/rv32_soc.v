`timescale 1ns/1ps
//=============================================================================
// 模块名 : rv32_soc
// 文件   : rv32_soc.v
// 功能   : 仿真用 SoC 顶层，把 CPU 核与指令存储器（imem）、数据存储器（dmem）连接起来
// 结构   :
//     rv32_core ──┬── imem (rv32_sync_mem, 只读, 装载 IMEM_FILE)
//                 └── dmem (rv32_sync_mem, 可读写, 装载 DMEM_FILE)
// 参数   : ADDR_BITS  存储器地址位宽
//          IMEM_FILE  指令存储器初始化文件
//          DMEM_FILE  数据存储器初始化文件
// 说明   : 本模块纯做“连线 + 少量观测逻辑”，不含流水线控制，便于仿真观察。
//          result_valid/result_data：当程序向地址 0 写满一个字时，
//          视为“演示程序输出结果”，锁存起来供 testbench 检查。
//=============================================================================
module rv32_soc #(
    parameter ADDR_BITS = 8,
    parameter IMEM_FILE = "",
    parameter DMEM_FILE = ""
) (
    input  wire        clk,
    input  wire        rst,
    // ---- 异常/故障观测信号（供 testbench 检查异常处理）----
    output wire        fault,        // 发生异常并已停机
    output wire [4:0]  fault_cause,  // 异常原因编码（mcause）
    output wire [31:0] fault_pc,     // 触发异常的指令地址
    output wire [31:0] fault_tval,   // 异常相关值（mtval）
    // ---- 调试/归档观测信号 ----
    output wire [31:0] debug_pc,     // 当前 PC
    output wire        retire_valid, // 本拍有指令写回
    output wire [4:0]  retire_rd,    // 写回目标寄存器号
    output wire [31:0] retire_data,  // 写回数据
    // ---- 演示程序结果锁存（写地址 0 触发）----
    output reg         result_valid,
    output reg  [31:0] result_data
);
    // CPU <-> imem 连线
    wire [31:0] imem_addr, imem_rdata;
    wire        imem_re;
    // CPU <-> dmem 连线
    wire [31:0] dmem_addr, dmem_wdata, dmem_rdata;
    wire        dmem_re, dmem_we;
    wire [3:0]  dmem_wstrb;

    // 处理器核：对外暴露独立的指令/数据访存接口
    rv32_core #(.MEM_ADDR_BITS(ADDR_BITS)) core (
        .clk(clk),
        .rst(rst),
        .imem_addr(imem_addr),
        .imem_re(imem_re),
        .imem_rdata(imem_rdata),
        .dmem_addr(dmem_addr),
        .dmem_wdata(dmem_wdata),
        .dmem_re(dmem_re),
        .dmem_we(dmem_we),
        .dmem_wstrb(dmem_wstrb),
        .dmem_rdata(dmem_rdata),
        .fault(fault),
        .fault_cause(fault_cause),
        .fault_pc(fault_pc),
        .fault_tval(fault_tval),
        .debug_pc(debug_pc),
        .retire_valid(retire_valid),
        .retire_rd(retire_rd),
        .retire_data(retire_data)
    );

    // 指令存储器：只读（we 恒 0），由 IMEM_FILE 预装载
    rv32_sync_mem #(.ADDR_BITS(ADDR_BITS), .INIT_FILE(IMEM_FILE)) imem (
        .clk(clk),
        .re(imem_re),
        .we(1'b0),
        .wstrb(4'b0),
        .addr(imem_addr),
        .wdata(32'b0),
        .rdata(imem_rdata)
    );

    // 数据存储器：可读可写，由 DMEM_FILE 预装载
    rv32_sync_mem #(.ADDR_BITS(ADDR_BITS), .INIT_FILE(DMEM_FILE)) dmem (
        .clk(clk),
        .re(dmem_re),
        .we(dmem_we),
        .wstrb(dmem_wstrb),
        .addr(dmem_addr),
        .wdata(dmem_wdata),
        .rdata(dmem_rdata)
    );

    // 结果锁存：当 CPU 向地址 0 写满一个完整的字（wstrb=4'b1111）时，
    // 认为演示程序给出了输出，锁存该数据供 testbench 读取。
    always @(posedge clk) begin
        if (rst) begin
            result_valid <= 0;
            result_data  <= 0;
        end else if (dmem_we && dmem_addr == 0 && dmem_wstrb == 4'b1111) begin
            result_valid <= 1;
            result_data  <= dmem_wdata;
        end
    end
endmodule