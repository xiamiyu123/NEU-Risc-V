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
    localparam [3:0] ALU_ADD = 0, ALU_SLT = 1, ALU_SLTU = 2,
                     ALU_OR = 3, ALU_LUI = 4, ALU_SLL = 5,
                     ALU_SRL = 6, ALU_SRA = 7, ALU_UADD8SAT = 8,
                     ALU_SUB = 9, ALU_XOR = 10, ALU_AND = 11;

    reg [31:0] pc;
    reg ifid_valid;
    reg [31:0] ifid_pc;
    wire [31:0] ifid_instr = imem_rdata;
    wire [4:0] dec_rs1 = ifid_instr[19:15];
    wire [4:0] dec_rs2 = ifid_instr[24:20];
    wire [4:0] dec_rd = ifid_instr[11:7];
    wire [2:0] dec_funct3 = ifid_instr[14:12];
    wire [6:0] dec_funct7 = ifid_instr[31:25];

    reg dec_valid, dec_regwrite, dec_memread, dec_memwrite;
    reg dec_uses_rs1, dec_uses_rs2, dec_op1_pc, dec_op2_imm;
    reg dec_branch, dec_jump, dec_jalr, dec_link, dec_system_trap;
    reg [4:0] dec_system_cause;
    reg [3:0] dec_alu_op;
    reg [31:0] dec_imm;

    always @* begin
        dec_valid = 0;
        dec_regwrite = 0;
        dec_memread = 0;
        dec_memwrite = 0;
        dec_uses_rs1 = 0;
        dec_uses_rs2 = 0;
        dec_op1_pc = 0;
        dec_op2_imm = 0;
        dec_branch = 0;
        dec_jump = 0;
        dec_jalr = 0;
        dec_link = 0;
        dec_system_trap = 0;
        dec_system_cause = 0;
        dec_alu_op = ALU_ADD;
        dec_imm = 0;
        case (ifid_instr[6:0])
            7'b0110011: begin
                dec_uses_rs1 = 1;
                dec_uses_rs2 = 1;
                case ({dec_funct7, dec_funct3})
                    {7'b0000000, 3'b000}: begin dec_valid = 1; dec_alu_op = ALU_ADD; end
                    {7'b0100000, 3'b000}: begin dec_valid = 1; dec_alu_op = ALU_SUB; end
                    {7'b0000000, 3'b010}: begin dec_valid = 1; dec_alu_op = ALU_SLT; end
                    {7'b0000000, 3'b011}: begin dec_valid = 1; dec_alu_op = ALU_SLTU; end
                    {7'b0000000, 3'b001}: begin dec_valid = 1; dec_alu_op = ALU_SLL; end
                    {7'b0000000, 3'b101}: begin dec_valid = 1; dec_alu_op = ALU_SRL; end
                    {7'b0100000, 3'b101}: begin dec_valid = 1; dec_alu_op = ALU_SRA; end
                    {7'b0000000, 3'b100}: begin dec_valid = 1; dec_alu_op = ALU_XOR; end
                    {7'b0000000, 3'b110}: begin dec_valid = 1; dec_alu_op = ALU_OR; end
                    {7'b0000000, 3'b111}: begin dec_valid = 1; dec_alu_op = ALU_AND; end
                endcase
                dec_regwrite = dec_valid;
            end
            7'b0010011: begin
                dec_uses_rs1 = 1;
                dec_op2_imm = 1;
                dec_imm = {{20{ifid_instr[31]}}, ifid_instr[31:20]};
                case (dec_funct3)
                    3'b000: begin dec_valid = 1; dec_alu_op = ALU_ADD; end
                    3'b010: begin dec_valid = 1; dec_alu_op = ALU_SLT; end
                    3'b011: begin dec_valid = 1; dec_alu_op = ALU_SLTU; end
                    3'b100: begin dec_valid = 1; dec_alu_op = ALU_XOR; end
                    3'b110: begin dec_valid = 1; dec_alu_op = ALU_OR; end
                    3'b111: begin dec_valid = 1; dec_alu_op = ALU_AND; end
                    3'b001: if (dec_funct7 == 0) begin
                        dec_valid = 1; dec_alu_op = ALU_SLL;
                    end
                    3'b101: begin
                        if (dec_funct7 == 0) begin
                            dec_valid = 1; dec_alu_op = ALU_SRL;
                        end else if (dec_funct7 == 7'b0100000) begin
                            dec_valid = 1; dec_alu_op = ALU_SRA;
                        end
                    end
                endcase
                dec_regwrite = dec_valid;
            end
            7'b0110111: begin
                dec_valid = 1;
                dec_regwrite = 1;
                dec_op2_imm = 1;
                dec_alu_op = ALU_LUI;
                dec_imm = {ifid_instr[31:12], 12'b0};
            end
            7'b0010111: begin
                dec_valid = 1;
                dec_regwrite = 1;
                dec_op1_pc = 1;
                dec_op2_imm = 1;
                dec_imm = {ifid_instr[31:12], 12'b0};
            end
            7'b0000011: if (dec_funct3 == 3'b000 || dec_funct3 == 3'b001 ||
                           dec_funct3 == 3'b010 || dec_funct3 == 3'b100 ||
                           dec_funct3 == 3'b101) begin
                dec_valid = 1;
                dec_regwrite = 1;
                dec_memread = 1;
                dec_uses_rs1 = 1;
                dec_op2_imm = 1;
                dec_imm = {{20{ifid_instr[31]}}, ifid_instr[31:20]};
            end
            7'b0100011: if (dec_funct3 == 3'b000 || dec_funct3 == 3'b001 ||
                           dec_funct3 == 3'b010) begin
                dec_valid = 1;
                dec_memwrite = 1;
                dec_uses_rs1 = 1;
                dec_uses_rs2 = 1;
                dec_op2_imm = 1;
                dec_imm = {{20{ifid_instr[31]}}, ifid_instr[31:25], ifid_instr[11:7]};
            end
            7'b1100011: if (dec_funct3 == 3'b000 || dec_funct3 == 3'b001 ||
                           dec_funct3 == 3'b100 || dec_funct3 == 3'b101 ||
                           dec_funct3 == 3'b110 || dec_funct3 == 3'b111) begin
                dec_valid = 1;
                dec_branch = 1;
                dec_uses_rs1 = 1;
                dec_uses_rs2 = 1;
                dec_imm = {{19{ifid_instr[31]}}, ifid_instr[31], ifid_instr[7],
                           ifid_instr[30:25], ifid_instr[11:8], 1'b0};
            end
            7'b1101111: begin
                dec_valid = 1;
                dec_regwrite = 1;
                dec_jump = 1;
                dec_link = 1;
                dec_imm = {{11{ifid_instr[31]}}, ifid_instr[31], ifid_instr[19:12],
                           ifid_instr[20], ifid_instr[30:21], 1'b0};
            end
            7'b1100111: if (dec_funct3 == 0) begin
                dec_valid = 1;
                dec_regwrite = 1;
                dec_uses_rs1 = 1;
                dec_op2_imm = 1;
                dec_jump = 1;
                dec_jalr = 1;
                dec_link = 1;
                dec_imm = {{20{ifid_instr[31]}}, ifid_instr[31:20]};
            end
            7'b0001111: if (dec_funct3 == 0)
                dec_valid = 1; // FENCE: memory accesses already retire in order.
            7'b1110011: begin
                if (ifid_instr == 32'h00000073) begin
                    dec_valid = 1;
                    dec_system_trap = 1;
                    dec_system_cause = 11; // ECALL from machine mode
                end else if (ifid_instr == 32'h00100073) begin
                    dec_valid = 1;
                    dec_system_trap = 1;
                    dec_system_cause = 3; // EBREAK
                end
            end
            7'b0001011: if (dec_funct3 == 0 && dec_funct7 == 0) begin
                dec_valid = 1;
                dec_regwrite = 1;
                dec_uses_rs1 = 1;
                dec_uses_rs2 = 1;
                dec_alu_op = ALU_UADD8SAT;
            end
        endcase
    end

    reg [31:0] regs [0:31];
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
            3'b000: load_result = {{24{load_shifted[7]}}, load_shifted[7:0]};
            3'b001: load_result = {{16{load_shifted[15]}}, load_shifted[15:0]};
            3'b010: load_result = dmem_rdata;
            3'b100: load_result = {24'b0, load_shifted[7:0]};
            3'b101: load_result = {16'b0, load_shifted[15:0]};
            default: load_result = 0;
        endcase
    end
    wire [31:0] dec_rs1_data = dec_rs1 == 0 ? 0 :
        (wb_we && memwb_rd == dec_rs1 ? wb_data : regs[dec_rs1]);
    wire [31:0] dec_rs2_data = dec_rs2 == 0 ? 0 :
        (wb_we && memwb_rd == dec_rs2 ? wb_data : regs[dec_rs2]);

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
    reg [31:0] alu_result;
    reg [31:0] sat_result;
    reg [8:0] byte_sum;
    integer byte_i;

    always @* begin
        sat_result = 0;
        byte_sum = 0;
        for (byte_i = 0; byte_i < 4; byte_i = byte_i + 1) begin
            byte_sum = {1'b0, ex_rs1[byte_i*8 +: 8]} +
                       {1'b0, ex_rs2[byte_i*8 +: 8]};
            sat_result[byte_i*8 +: 8] = byte_sum[8] ? 8'hff : byte_sum[7:0];
        end
        case (idex_alu_op)
            ALU_ADD: alu_result = alu_a + alu_b;
            ALU_SUB: alu_result = alu_a - alu_b;
            ALU_SLT: alu_result = $signed(alu_a) < $signed(alu_b);
            ALU_SLTU: alu_result = alu_a < alu_b;
            ALU_XOR: alu_result = alu_a ^ alu_b;
            ALU_OR: alu_result = alu_a | alu_b;
            ALU_AND: alu_result = alu_a & alu_b;
            ALU_LUI: alu_result = alu_b;
            ALU_SLL: alu_result = alu_a << alu_b[4:0];
            ALU_SRL: alu_result = alu_a >> alu_b[4:0];
            ALU_SRA: alu_result = $signed(alu_a) >>> alu_b[4:0];
            ALU_UADD8SAT: alu_result = sat_result;
            default: alu_result = 0;
        endcase
    end

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
            3'b000: dmem_wstrb = 4'b0001 << exmem_addr[1:0];
            3'b001: dmem_wstrb = 4'b0011 << exmem_addr[1:0];
            3'b010: dmem_wstrb = 4'b1111;
            default: dmem_wstrb = 0;
        endcase
    end
    assign dmem_re = !rst && exmem_valid && exmem_memread;
    assign dmem_we = !rst && exmem_valid && exmem_memwrite;
    assign debug_pc = pc;
    assign retire_valid = wb_we;
    assign retire_rd = memwb_rd;
    assign retire_data = wb_data;

    integer reg_i;
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
            for (reg_i = 0; reg_i < 32; reg_i = reg_i + 1)
                regs[reg_i] <= 0;
        end else begin
            if (wb_we)
                regs[memwb_rd] <= wb_data;

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
