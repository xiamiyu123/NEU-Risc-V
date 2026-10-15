// 测试程序的机器码编码辅助函数；只在测试台内部包含。
    // R 型：funct7 | rs2 | rs1 | funct3 | rd | opcode。
    function automatic [31:0] rtype(
        input [6:0] funct7, input [4:0] rs2, input [4:0] rs1,
        input [2:0] funct3, input [4:0] rd, input [6:0] opcode
    );
        rtype = {funct7, rs2, rs1, funct3, rd, opcode};
    endfunction

    // I 型：有符号立即数取低 12 位，与 rs1/funct3/rd/opcode 拼接。
    function automatic [31:0] itype(
        input integer imm, input [4:0] rs1, input [2:0] funct3,
        input [4:0] rd, input [6:0] opcode
    );
        itype = {imm[11:0], rs1, funct3, rd, opcode};
    endfunction

    // S 型：立即数分散在 [31:25] 和 [11:7]；funct3 选择 SB/SH/SW。
    function automatic [31:0] storetype(
        input integer imm, input [4:0] rs2, input [4:0] rs1,
        input [2:0] funct3
    );
        storetype = {imm[11:5], rs2, rs1, funct3,
                     imm[4:0], 7'b0100011};
    endfunction

    // SW 的便捷编码，等价于 storetype(..., funct3=010)。
    function automatic [31:0] stype(
        input integer imm, input [4:0] rs2, input [4:0] rs1
    );
        stype = storetype(imm, rs2, rs1, 3'b010);
    endfunction

    // B 型：分支偏移最低位隐含为零，其余位按标准位置重排。
    function automatic [31:0] btype(
        input integer imm, input [4:0] rs2, input [4:0] rs1,
        input [2:0] funct3
    );
        btype = {imm[12], imm[10:5], rs2, rs1, funct3,
                 imm[4:1], imm[11], 7'b1100011};
    endfunction

    // U 型：20 位立即数置于指令高位，执行时低 12 位补零。
    function automatic [31:0] utype(input [19:0] imm, input [4:0] rd,
                                    input [6:0] opcode);
        utype = {imm, rd, opcode};
    endfunction

    // J 型：JAL 偏移分散在多个字段，最低位隐含为零。
    function automatic [31:0] jtype(input integer imm, input [4:0] rd);
        jtype = {imm[20], imm[10:1], imm[11], imm[19:12], rd, 7'b1101111};
    endfunction
