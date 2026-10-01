    function automatic [31:0] rtype(
        input [6:0] funct7, input [4:0] rs2, input [4:0] rs1,
        input [2:0] funct3, input [4:0] rd, input [6:0] opcode
    );
        rtype = {funct7, rs2, rs1, funct3, rd, opcode};
    endfunction

    function automatic [31:0] itype(
        input integer imm, input [4:0] rs1, input [2:0] funct3,
        input [4:0] rd, input [6:0] opcode
    );
        itype = {imm[11:0], rs1, funct3, rd, opcode};
    endfunction

    function automatic [31:0] storetype(
        input integer imm, input [4:0] rs2, input [4:0] rs1,
        input [2:0] funct3
    );
        storetype = {imm[11:5], rs2, rs1, funct3,
                     imm[4:0], 7'b0100011};
    endfunction

    function automatic [31:0] stype(
        input integer imm, input [4:0] rs2, input [4:0] rs1
    );
        stype = storetype(imm, rs2, rs1, 3'b010);
    endfunction

    function automatic [31:0] btype(
        input integer imm, input [4:0] rs2, input [4:0] rs1,
        input [2:0] funct3
    );
        btype = {imm[12], imm[10:5], rs2, rs1, funct3,
                 imm[4:1], imm[11], 7'b1100011};
    endfunction

    function automatic [31:0] utype(input [19:0] imm, input [4:0] rd,
                                    input [6:0] opcode);
        utype = {imm, rd, opcode};
    endfunction

    function automatic [31:0] jtype(input integer imm, input [4:0] rd);
        jtype = {imm[20], imm[10:1], imm[11], imm[19:12], rd, 7'b1101111};
    endfunction
