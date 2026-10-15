`timescale 1ns/1ps
module rv32_core #(
    parameter MEM_ADDR_BITS = 8
) (
    input wire clk,
    input wire rst,
    output wire [31:0] imem_addr,
    output wire imem_re,
    input wire [31:0] imem_rdata,
    output wire [31:0] dmem_addr,
    output wire [31:0] dmem_wdata,
    output wire dmem_re,
    output wire dmem_we,
    output reg [3:0] dmem_wstrb,
    input wire [31:0] dmem_rdata,
    output reg fault,
    output reg [4:0] fault_cause,
    output reg [31:0] fault_pc,
    output reg [31:0] fault_tval,
    output wire [31:0] debug_pc,
    output wire retire_valid,
    output wire [4:0] retire_rd,
    output wire [31:0] retire_data
);
    reg [31:0] pc;
    reg ifid_valid;
    reg [31:0] ifid_pc;
    wire [31:0] ifid_instr = imem_rdata;
    // ID：控制器译码，寄存器堆提供读值；流水线状态仍由 CPU 主体保存。
    wire [4:0] dec_rs1, dec_rs2, dec_rd;
    wire [2:0] dec_funct3;
    wire dec_valid, dec_regwrite, dec_memread, dec_memwrite;
    wire dec_uses_rs1, dec_uses_rs2, dec_op1_pc, dec_op2_imm;
    wire dec_branch, dec_jump, dec_jalr, dec_link, dec_system_trap;
    wire [4:0] dec_system_cause;
    wire [3:0] dec_alu_op;
    wire [31:0] dec_imm;

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

    reg memwb_valid, memwb_regwrite, memwb_memread;
    reg [4:0] memwb_rd;
    reg [2:0] memwb_funct3;
    reg [1:0] memwb_lane;
    reg [31:0] memwb_result;
    wire [31:0] wb_data;
    wire wb_we;
    wire [31:0] load_shifted = dmem_rdata >> {memwb_lane, 3'b000};
    reg [31:0] load_result;
    always @* begin
        case (memwb_funct3)
            // LB: sign-extend byte.
            3'b000: load_result = {{24{load_shifted[7]}}, load_shifted[7:0]};
            // LH: sign-extend halfword.
            3'b001: load_result = {{16{load_shifted[15]}}, load_shifted[15:0]};
            3'b010: load_result = dmem_rdata; // LW: full word.
            3'b100: load_result = {24'b0, load_shifted[7:0]}; // LBU: zero-extend byte.
            3'b101: load_result = {16'b0, load_shifted[15:0]}; // LHU: zero-extend halfword.
            default: load_result = 0;
        endcase
    end
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

    reg idex_valid, idex_regwrite, idex_memread, idex_memwrite;
    reg idex_op1_pc, idex_op2_imm, idex_branch, idex_jump, idex_jalr, idex_link;
    reg idex_exception_valid;
    reg [4:0] idex_exception_cause;
    reg [31:0] idex_exception_tval;
    reg [2:0] idex_funct3;
    reg [3:0] idex_alu_op;
    reg [4:0] idex_rs1, idex_rs2, idex_rd;
    reg [31:0] idex_pc, idex_pc4, idex_rs1_data, idex_rs2_data, idex_imm;

    reg exmem_valid, exmem_regwrite, exmem_memread, exmem_memwrite;
    reg [4:0] exmem_rd;
    reg [2:0] exmem_funct3;
    reg [31:0] exmem_result, exmem_addr, exmem_store_data;

    assign wb_data = memwb_memread ? load_result : memwb_result;
    assign wb_we = !rst && memwb_valid && memwb_regwrite && memwb_rd != 0;

    wire [31:0] ex_rs1 = idex_rs1 == 0 ? 0 :
        (exmem_valid && exmem_regwrite && !exmem_memread &&
         exmem_rd != 0 && exmem_rd == idex_rs1 ? exmem_result :
         wb_we && memwb_rd == idex_rs1 ? wb_data : idex_rs1_data);
    wire [31:0] ex_rs2 = idex_rs2 == 0 ? 0 :
        (exmem_valid && exmem_regwrite && !exmem_memread &&
         exmem_rd != 0 && exmem_rd == idex_rs2 ? exmem_result :
         wb_we && memwb_rd == idex_rs2 ? wb_data : idex_rs2_data);
    wire [31:0] alu_a = idex_op1_pc ? idex_pc : ex_rs1;
    wire [31:0] alu_b = idex_op2_imm ? idex_imm : ex_rs2;
    wire [31:0] alu_result;
    rv32_alu alu (
        .op(idex_alu_op),
        .a(alu_a),
        .b(alu_b),
        .result(alu_result)
    );

    reg branch_taken;
    always @* begin
        case (idex_funct3)
            3'b000: branch_taken = ex_rs1 == ex_rs2;
            3'b001: branch_taken = ex_rs1 != ex_rs2;
            3'b100: branch_taken = $signed(ex_rs1) < $signed(ex_rs2);
            3'b101: branch_taken = $signed(ex_rs1) >= $signed(ex_rs2);
            3'b110: branch_taken = ex_rs1 < ex_rs2;
            3'b111: branch_taken = ex_rs1 >= ex_rs2;
            default: branch_taken = 0;
        endcase
    end

    wire redirect = idex_valid && (idex_jump || (idex_branch && branch_taken));
    wire [31:0] target_pc = idex_jalr ?
        ((ex_rs1 + idex_imm) & 32'hfffffffe) : idex_pc + idex_imm;
    reg ex_exception_valid;
    reg [4:0] ex_exception_cause;
    reg [31:0] ex_exception_tval;
    always @* begin
        ex_exception_valid = idex_valid && idex_exception_valid;
        ex_exception_cause = idex_exception_cause;
        ex_exception_tval = idex_exception_tval;
        if (idex_valid && !idex_exception_valid && redirect && target_pc[1:0] != 0) begin
            ex_exception_valid = 1;
            ex_exception_cause = 0; // Instruction address misaligned
            ex_exception_tval = target_pc;
        end else if (idex_valid && !idex_exception_valid &&
                     (idex_memread || idex_memwrite)) begin
            if ((idex_funct3[1:0] == 2'b01 && alu_result[0] != 0) ||
                (idex_funct3[1:0] == 2'b10 && alu_result[1:0] != 0)) begin
                ex_exception_valid = 1;
                ex_exception_cause = idex_memread ? 4 : 6;
                ex_exception_tval = alu_result;
            end else if (|alu_result[31:MEM_ADDR_BITS+2]) begin
                ex_exception_valid = 1;
                ex_exception_cause = idex_memread ? 5 : 7;
                ex_exception_tval = alu_result;
            end
        end
    end
    wire load_stall = idex_valid && idex_memread && idex_rd != 0 && ifid_valid &&
        ((dec_uses_rs1 && dec_rs1 == idex_rd) ||
         (dec_uses_rs2 && dec_rs2 == idex_rd));
    reg trap_pending;

    assign imem_addr = pc;
    assign imem_re = !rst && !fault && !trap_pending &&
                     !load_stall && !redirect && !ex_exception_valid;
    assign dmem_addr = exmem_addr;
    assign dmem_wdata = exmem_store_data << {exmem_addr[1:0], 3'b000};
    always @* begin
        case (exmem_funct3)
            3'b000: dmem_wstrb = 4'b0001 << exmem_addr[1:0]; // SB: enable one addressed byte lane.
            3'b001: dmem_wstrb = 4'b0011 << exmem_addr[1:0]; // SH: enable two addressed byte lanes.
            3'b010: dmem_wstrb = 4'b1111; // SW: enable all four byte lanes.
            default: dmem_wstrb = 0;
        endcase
    end
    assign dmem_re = !rst && exmem_valid && exmem_memread;
    assign dmem_we = !rst && exmem_valid && exmem_memwrite;
    assign debug_pc = pc;
    assign retire_valid = wb_we;
    assign retire_rd = memwb_rd;
    assign retire_data = wb_data;

    always @(posedge clk) begin
        if (rst) begin
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
            if (ex_exception_valid) begin
                trap_pending <= 1;
                fault_cause <= ex_exception_cause;
                fault_pc <= idex_pc;
                fault_tval <= ex_exception_tval;
                ifid_valid <= 0;
                idex_valid <= 0;
            end else if (trap_pending || fault) begin
                ifid_valid <= 0;
                idex_valid <= 0;
                if (trap_pending && !exmem_valid && !memwb_valid) begin
                    trap_pending <= 0;
                    fault <= 1;
                end
            end else if (redirect) begin
                pc <= target_pc;
                ifid_valid <= 0;
                idex_valid <= 0;
            end else if (load_stall) begin
                idex_valid <= 0;
            end else begin
                pc <= pc + 4;
                ifid_pc <= pc;
                ifid_valid <= 1;
                idex_valid <= ifid_valid;
            end

            if (!ex_exception_valid && !trap_pending && !fault &&
                !redirect && !load_stall) begin
                idex_pc <= ifid_pc;
                idex_pc4 <= ifid_pc + 4;
                idex_rs1_data <= dec_rs1_data;
                idex_rs2_data <= dec_rs2_data;
                idex_rs1 <= dec_rs1;
                idex_rs2 <= dec_rs2;
                idex_rd <= dec_rd;
                idex_imm <= dec_imm;
                idex_funct3 <= dec_funct3;
                idex_alu_op <= dec_alu_op;
                idex_regwrite <= dec_regwrite;
                idex_memread <= dec_memread;
                idex_memwrite <= dec_memwrite;
                idex_op1_pc <= dec_op1_pc;
                idex_op2_imm <= dec_op2_imm;
                idex_branch <= dec_branch;
                idex_jump <= dec_jump;
                idex_jalr <= dec_jalr;
                idex_link <= dec_link;
                idex_exception_valid <= ifid_valid &&
                    ((|ifid_pc[31:MEM_ADDR_BITS+2]) || !dec_valid || dec_system_trap);
                idex_exception_cause <= (|ifid_pc[31:MEM_ADDR_BITS+2]) ? 1 :
                    (!dec_valid ? 2 : dec_system_cause);
                idex_exception_tval <= (|ifid_pc[31:MEM_ADDR_BITS+2]) ? ifid_pc :
                    (!dec_valid ? ifid_instr : 0);
            end

            exmem_valid <= idex_valid && !ex_exception_valid;
            exmem_regwrite <= idex_regwrite;
            exmem_memread <= idex_memread;
            exmem_memwrite <= idex_memwrite;
            exmem_rd <= idex_rd;
            exmem_funct3 <= idex_funct3;
            exmem_result <= idex_link ? idex_pc4 : alu_result;
            exmem_addr <= alu_result;
            exmem_store_data <= ex_rs2;

            memwb_valid <= exmem_valid;
            memwb_regwrite <= exmem_regwrite;
            memwb_memread <= exmem_memread;
            memwb_rd <= exmem_rd;
            memwb_funct3 <= exmem_funct3;
            memwb_lane <= exmem_addr[1:0];
            memwb_result <= exmem_result;
        end
    end
endmodule
