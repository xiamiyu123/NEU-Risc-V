`timescale 1ns/1ps
//=============================================================================
// 模块名 : rv32_core
// 文件   : rv32_core.v
// 功能   : RV32I 五级流水线处理器核（IF / ID / EX / MEM / WB）
// 特性   :
//   - 五级流水：取指 → 译码 → 执行 → 访存 → 写回，四级流水寄存器
//     (IF/ID、ID/EX、EX/MEM、MEM/WB) 保存级间状态
//   - 数据冒险：EX/MEM→EX 与 MEM/WB→EX 两级前递（forwarding）
//              + load-use 专用停顿（load_stall，插入 1 拍气泡）
//   - 控制冒险：分支/跳转在 EX 级解析，命中即 redirect（清空已取错指令）
//   - 访存    ：同步存储器；支持子字访问（LB/LH/LW/LBU/LHU/SB/SH/SW）
//   - 异常    ：非法指令、取指地址错位/越界、访存地址错位/越界、
//              ecall/ebreak；异常发生时停止取指并锁存 mcause/mtval
// 说明   : 存储器接口为“同步读” 1 拍延迟，故 IF 级用 imem_rdata 直接作为
//          IF/ID 段的指令（ifid_instr = imem_rdata）
//=============================================================================
module rv32_core #(
    parameter MEM_ADDR_BITS = 8     // 存储器地址位宽（决定合法访存地址范围）
) (
    input  wire        clk,
    input  wire        rst,
    // ---- 指令存储器接口 ----
    output wire [31:0] imem_addr,   // 取指地址（= 当前 PC）
    output wire        imem_re,     // 取指读使能
    input  wire [31:0] imem_rdata,  // 取回指令
    // ---- 数据存储器接口 ----
    output wire [31:0] dmem_addr,   // 数据地址
    output wire [31:0] dmem_wdata,  // 写数据（已按字节通道对齐）
    output wire        dmem_re,     // 读使能
    output wire        dmem_we,     // 写使能
    output reg  [3:0]  dmem_wstrb,  // 字节写使能
    input  wire [31:0] dmem_rdata,  // 读回数据
    // ---- 异常观测 ----
    output reg         fault,        // 已停机于异常状态
    output reg  [4:0]  fault_cause,  // mcause 编码
    output reg  [31:0] fault_pc,     // 出错指令 PC
    output reg  [31:0] fault_tval,   // mtval
    // ---- 调试观测 ----
    output wire [31:0] debug_pc,
    output wire        retire_valid,
    output wire [4:0]  retire_rd,
    output wire [31:0] retire_data
);
    //=========================================================================
    // 1) IF：取指级状态
    //=========================================================================
    reg [31:0] pc;                    // 程序计数器：当前取指地址
    reg        ifid_valid;            // IF/ID 流水寄存器有效位
    reg [31:0] ifid_pc;               // IF/ID：该指令的 PC
    wire [31:0] ifid_instr = imem_rdata; // 同步存储器本拍返回的指令，直接送入 ID

    //=========================================================================
    // 2) ID：译码器（组合）+ 寄存器堆
    //   译码结果先为 wire，待 IF/ID→ID/EX 时锁存
    //=========================================================================
    wire [4:0] dec_rs1, dec_rs2, dec_rd;      // 译码得到的寄存器索引
    wire [2:0] dec_funct3;                    // funct3
    wire dec_valid, dec_regwrite, dec_memread, dec_memwrite;
    wire dec_uses_rs1, dec_uses_rs2, dec_op1_pc, dec_op2_imm;
    wire dec_branch, dec_jump, dec_jalr, dec_link, dec_system_trap;
    wire [4:0] dec_system_cause;
    wire [3:0] dec_alu_op;
    wire [31:0] dec_imm;

    // 译码器实例：输入当前 IF/ID 段指令，输出全部控制信号与立即数
    rv32_control control (
        .instr(ifid_instr),
        .rs1(dec_rs1),
        .rs2(dec_rs2),
        .rd(dec_rd),
        .funct3(dec_funct3),
        .valid(dec_valid),
        .regwrite(dec_regwrite),
        .memread(dec_memread),
        .memwrite(dec_memwrite),
        .uses_rs1(dec_uses_rs1),
        .uses_rs2(dec_uses_rs2),
        .op1_pc(dec_op1_pc),
        .op2_imm(dec_op2_imm),
        .branch(dec_branch),
        .jump(dec_jump),
        .jalr(dec_jalr),
        .link(dec_link),
        .system_trap(dec_system_trap),
        .system_cause(dec_system_cause),
        .alu_op(dec_alu_op),
        .imm(dec_imm)
    );

    //=========================================================================
    // 3) MEM/WB 级流水寄存器 + 写回
    //=========================================================================
    reg        memwb_valid, memwb_regwrite, memwb_memread;
    reg [4:0]  memwb_rd;               // 写回目标寄存器
    reg [2:0]  memwb_funct3;           // 用于选择 load 的数据宽度/符号
    reg [1:0]  memwb_lane;             // 访存地址低 2 位（子字 load 的字节通道）
    reg [31:0] memwb_result;           // 非 load 指令的 ALU/链接结果
    wire [31:0] wb_data;               // 最终写回数据
    wire        wb_we;                 // 最终写回使能

    // 子字 load：先把读回字右移到目标字节所在的最低位置，再按 funct3 扩展
    wire [31:0] load_shifted = dmem_rdata >> {memwb_lane, 3'b000};
    reg  [31:0] load_result;
    always @* begin
        case (memwb_funct3)
            3'b000: load_result = {{24{load_shifted[7]}},  load_shifted[7:0]};  // LB  符号扩展字节
            3'b001: load_result = {{16{load_shifted[15]}}, load_shifted[15:0]}; // LH  符号扩展半字
            3'b010: load_result = dmem_rdata;                                   // LW  整字
            3'b100: load_result = {24'b0, load_shifted[7:0]};                   // LBU 零扩展字节
            3'b101: load_result = {16'b0, load_shifted[15:0]};                  // LHU 零扩展半字
            default: load_result = 0;
        endcase
    end

    // 寄存器堆：读口接译码索引；写口接 MEM/WB 段的写回信号
    wire [31:0] dec_rs1_data, dec_rs2_data;
    rv32_regfile regfile (
        .clk(clk),
        .rst(rst),
        .rs1(dec_rs1),
        .rs2(dec_rs2),
        .we(wb_we),
        .rd(memwb_rd),
        .wdata(wb_data),
        .rdata1(dec_rs1_data),
        .rdata2(dec_rs2_data)
    );

    //=========================================================================
    // 4) ID/EX、EX/MEM 级流水寄存器
    //=========================================================================
    // ---- ID/EX ----
    reg idex_valid, idex_regwrite, idex_memread, idex_memwrite;
    reg idex_op1_pc, idex_op2_imm, idex_branch, idex_jump, idex_jalr, idex_link;
    reg idex_exception_valid;
    reg [4:0] idex_exception_cause;
    reg [31:0] idex_exception_tval;
    reg [2:0] idex_funct3;
    reg [3:0] idex_alu_op;
    reg [4:0] idex_rs1, idex_rs2, idex_rd;
    reg [31:0] idex_pc, idex_pc4, idex_rs1_data, idex_rs2_data, idex_imm;

    // ---- EX/MEM ----
    reg exmem_valid, exmem_regwrite, exmem_memread, exmem_memwrite;
    reg [4:0] exmem_rd;
    reg [2:0] exmem_funct3;
    reg [31:0] exmem_result, exmem_addr, exmem_store_data;

    //=========================================================================
    // 5) WB：写回数据/使能
    //   load 取扩展后的 load_result，其余取 exmem_result（或链接值）
    //   x0 不写；复位期间不写
    //=========================================================================
    assign wb_data = memwb_memread ? load_result : memwb_result;
    assign wb_we   = !rst && memwb_valid && memwb_regwrite && memwb_rd != 0;

    //=========================================================================
    // 6) 前递（forwarding）：解决数据冒险
    //   优先级：EX/MEM 段结果 > MEM/WB 段写回值 > 寄存器堆原值
    //   注意：EX/MEM 前递要求 !exmem_memread —— load 结果在 EX 时不就绪，
    //         load 的消费者需靠 load_stall 停顿，而非前递。
    //   源为 x0 时直接取 0。
    //=========================================================================
    wire [31:0] ex_rs1 = idex_rs1 == 0 ? 0 :
        (exmem_valid && exmem_regwrite && !exmem_memread &&
         exmem_rd != 0 && exmem_rd == idex_rs1 ? exmem_result :      // EX/MEM 前递
         wb_we && memwb_rd == idex_rs1 ? wb_data : idex_rs1_data);  // MEM/WB 前递
    wire [31:0] ex_rs2 = idex_rs2 == 0 ? 0 :
        (exmem_valid && exmem_regwrite && !exmem_memread &&
         exmem_rd != 0 && exmem_rd == idex_rs2 ? exmem_result :      // EX/MEM 前递
         wb_we && memwb_rd == idex_rs2 ? wb_data : idex_rs2_data);  // MEM/WB 前递

    // ALU 操作数：A 端可选 PC（AUIPC）或 rs1；B 端可选立即数或 rs2
    wire [31:0] alu_a = idex_op1_pc ? idex_pc  : ex_rs1;
    wire [31:0] alu_b = idex_op2_imm ? idex_imm : ex_rs2;
    wire [31:0] alu_result;
    rv32_alu alu (
        .op(idex_alu_op),
        .a(alu_a),
        .b(alu_b),
        .result(alu_result)
    );

    //=========================================================================
    // 7) 分支判定（EX 级，组合）：根据 funct3 比较经前递后的两个源操作数
    //=========================================================================
    reg branch_taken;
    always @* begin
        case (idex_funct3)
            3'b000: branch_taken = ex_rs1 == ex_rs2;                      // BEQ
            3'b001: branch_taken = ex_rs1 != ex_rs2;                      // BNE
            3'b100: branch_taken = $signed(ex_rs1) <  $signed(ex_rs2);    // BLT
            3'b101: branch_taken = $signed(ex_rs1) >= $signed(ex_rs2);    // BGE
            3'b110: branch_taken = ex_rs1 <  ex_rs2;                      // BLTU
            3'b111: branch_taken = ex_rs1 >= ex_rs2;                      // BGEU
            default: branch_taken = 0;
        endcase
    end

    // 跳转/分支命中：需要改变取指方向的信号
    wire redirect = idex_valid && (idex_jump || (idex_branch && branch_taken));
    // 目标地址：JALR 用 (rs1+imm)&~1 并强制低位对齐；其余用 PC+imm
    wire [31:0] target_pc = idex_jalr ?
        ((ex_rs1 + idex_imm) & 32'hfffffffe) : idex_pc + idex_imm;

    //=========================================================================
    // 8) 异常判定（EX 级，组合）：在 ID/EX 已带异常的基础上，补充运行时异常
    //   处理优先级：已标记的异常 > 跳转地址错位(0) > 访存错位(4/6)/越界(5/7)
    //=========================================================================
    reg ex_exception_valid;
    reg [4:0] ex_exception_cause;
    reg [31:0] ex_exception_tval;
    always @* begin
        ex_exception_valid = idex_valid && idex_exception_valid;
        ex_exception_cause = idex_exception_cause;
        ex_exception_tval  = idex_exception_tval;
        if (idex_valid && !idex_exception_valid && redirect && target_pc[1:0] != 0) begin
            // 跳转目标未 4 字节对齐 → mcause=0（指令地址错位）
            ex_exception_valid = 1;
            ex_exception_cause = 0;
            ex_exception_tval  = target_pc;
        end else if (idex_valid && !idex_exception_valid &&
                     (idex_memread || idex_memwrite)) begin
            if ((idex_funct3[1:0] == 2'b01 && alu_result[0] != 0) ||
                (idex_funct3[1:0] == 2'b10 && alu_result[1:0] != 0)) begin
                // 半字/字访问地址未按自然对齐 → load=4 / store=6（访存地址错位）
                ex_exception_valid = 1;
                ex_exception_cause = idex_memread ? 4 : 6;
                ex_exception_tval  = alu_result;
            end else if (|alu_result[31:MEM_ADDR_BITS+2]) begin
                // 访存地址越界（超出 MEM_ADDR_BITS 位范围）→ load=5 / store=7
                ex_exception_valid = 1;
                ex_exception_cause = idex_memread ? 5 : 7;
                ex_exception_tval  = alu_result;
            end
        end
    end

    //=========================================================================
    // 9) load-use 冒险检测：EX 级是 load，且 ID 段指令要读它的目的寄存器
    //    → 停顿 1 拍并插入气泡（load 结果要下一拍才可用）
    //    uses_rs1/uses_rs2 由译码器给出，避免对不使用该寄存器的指令误停顿
    //=========================================================================
    wire load_stall = idex_valid && idex_memread && idex_rd != 0 && ifid_valid &&
        ((dec_uses_rs1 && dec_rs1 == idex_rd) ||
         (dec_uses_rs2 && dec_rs2 == idex_rd));
    reg trap_pending;                  // 异常已发生、等待流水线排空后停机

    //=========================================================================
    // 10) 存储器接口与调试信号的组合赋值
    //=========================================================================
    assign imem_addr = pc;
    // 以下任一情况停止取指：复位、已停机、异常待停机、停顿、跳转重定向、异常
    assign imem_re   = !rst && !fault && !trap_pending &&
                       !load_stall && !redirect && !ex_exception_valid;
    assign dmem_addr  = exmem_addr;
    // 写数据按地址低 2 位左移，对齐到相应字节通道
    assign dmem_wdata = exmem_store_data << {exmem_addr[1:0], 3'b000};
    always @* begin
        case (exmem_funct3)
            3'b000:  dmem_wstrb = 4'b0001 << exmem_addr[1:0]; // SB：1 个字节通道
            3'b001:  dmem_wstrb = 4'b0011 << exmem_addr[1:0]; // SH：2 个字节通道
            3'b010:  dmem_wstrb = 4'b1111;                    // SW：4 个字节通道
            default: dmem_wstrb = 0;
        endcase
    end
    assign dmem_re = !rst && exmem_valid && exmem_memread;
    assign dmem_we = !rst && exmem_valid && exmem_memwrite;
    assign debug_pc     = pc;
    assign retire_valid = wb_we;
    assign retire_rd    = memwb_rd;
    assign retire_data  = wb_data;

    //=========================================================================
    // 11) 时序主逻辑：每个时钟上升沿推进流水线
    //   分支优先级（互斥）：复位 > 异常 > 停机 > 重定向 > 停顿 > 正常推进
    //=========================================================================
    always @(posedge clk) begin
        if (rst) begin
            // ---- 复位：清空所有流水有效位与 PC ----
            pc <= 0;
            ifid_valid <= 0;
            idex_valid <= 0;
            exmem_valid <= 0;
            memwb_valid <= 0;
            fault <= 0;
            fault_cause <= 0;
            fault_pc <= 0;
            fault_tval <= 0;
            trap_pending <= 0;
            idex_exception_valid <= 0;
        end else begin
            //-----------------------------------------------------------------
            // 11.1 PC / 流水有效位更新
            //-----------------------------------------------------------------
            if (ex_exception_valid) begin
                // 异常：锁存 mcause/mtval/pc，清空 IF、ID 段（错误路径作废）
                trap_pending <= 1;
                fault_cause <= ex_exception_cause;
                fault_pc    <= idex_pc;
                fault_tval  <= ex_exception_tval;
                ifid_valid  <= 0;
                idex_valid  <= 0;
            end else if (trap_pending || fault) begin
                // 停机中：停止取指，等 EX/MEM、MEM/WB 排空后置 fault
                ifid_valid <= 0;
                idex_valid <= 0;
                if (trap_pending && !exmem_valid && !memwb_valid) begin
                    trap_pending <= 0;
                    fault <= 1;
                end
            end else if (redirect) begin
                // 分支/跳转命中：PC 跳到目标，作废已取入的 IF、ID 指令
                pc <= target_pc;
                ifid_valid <= 0;
                idex_valid <= 0;
            end else if (load_stall) begin
                // load-use 停顿：冻结 PC 与 IF/ID，向 EX 段插入一个气泡
                idex_valid <= 0;
            end else begin
                // 正常推进：PC+4，指令由 IF 进入 ID，再由 ID 进入 EX
                pc <= pc + 4;
                ifid_pc <= pc;
                ifid_valid <= 1;
                idex_valid <= ifid_valid;
            end

            //-----------------------------------------------------------------
            // 11.2 ID/EX 写入：仅在无异常/停机/重定向/停顿时，接受新指令
            //-----------------------------------------------------------------
            if (!ex_exception_valid && !trap_pending && !fault &&
                !redirect && !load_stall) begin
                idex_pc       <= ifid_pc;
                idex_pc4      <= ifid_pc + 4;
                idex_rs1_data <= dec_rs1_data;
                idex_rs2_data <= dec_rs2_data;
                idex_rs1      <= dec_rs1;
                idex_rs2      <= dec_rs2;
                idex_rd       <= dec_rd;
                idex_imm      <= dec_imm;
                idex_funct3   <= dec_funct3;
                idex_alu_op   <= dec_alu_op;
                idex_regwrite <= dec_regwrite;
                idex_memread  <= dec_memread;
                idex_memwrite <= dec_memwrite;
                idex_op1_pc   <= dec_op1_pc;
                idex_op2_imm  <= dec_op2_imm;
                idex_branch   <= dec_branch;
                idex_jump     <= dec_jump;
                idex_jalr     <= dec_jalr;
                idex_link     <= dec_link;
                // ID 级可判定的异常：取指地址越界(1)、非法指令(2)、ecall/ebreak
                idex_exception_valid <= ifid_valid &&
                    ((|ifid_pc[31:MEM_ADDR_BITS+2]) || !dec_valid || dec_system_trap);
                idex_exception_cause <= (|ifid_pc[31:MEM_ADDR_BITS+2]) ? 1 :
                    (!dec_valid ? 2 : dec_system_cause);
                idex_exception_tval  <= (|ifid_pc[31:MEM_ADDR_BITS+2]) ? ifid_pc :
                    (!dec_valid ? ifid_instr : 0);
            end

            //-----------------------------------------------------------------
            // 11.3 EX/MEM 写入：结果在 link 时取 PC+4，否则取 ALU 结果
            //-----------------------------------------------------------------
            exmem_valid      <= idex_valid && !ex_exception_valid;
            exmem_regwrite   <= idex_regwrite;
            exmem_memread    <= idex_memread;
            exmem_memwrite   <= idex_memwrite;
            exmem_rd         <= idex_rd;
            exmem_funct3     <= idex_funct3;
            exmem_result     <= idex_link ? idex_pc4 : alu_result;
            exmem_addr       <= alu_result;
            exmem_store_data <= ex_rs2;

            //-----------------------------------------------------------------
            // 11.4 MEM/WB 写入：记录 lane（供子字 load 对齐）
            //-----------------------------------------------------------------
            memwb_valid    <= exmem_valid;
            memwb_regwrite <= exmem_regwrite;
            memwb_memread  <= exmem_memread;
            memwb_rd       <= exmem_rd;
            memwb_funct3   <= exmem_funct3;
            memwb_lane     <= exmem_addr[1:0];
            memwb_result   <= exmem_result;
        end
    end
endmodule