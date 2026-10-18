// 模块内共用的 ALU 操作编号。
    localparam [3:0] ALU_ADD      = 4'd0;
    localparam [3:0] ALU_SLT      = 4'd1; // 有符号小于
    localparam [3:0] ALU_SLTU     = 4'd2; // 无符号小于
    localparam [3:0] ALU_OR       = 4'd3;
    localparam [3:0] ALU_LUI      = 4'd4;
    localparam [3:0] ALU_SLL      = 4'd5;
    localparam [3:0] ALU_SRL      = 4'd6;
    localparam [3:0] ALU_SRA      = 4'd7;
    localparam [3:0] ALU_UADD8SAT = 4'd8; // 四路字节饱和加法
    localparam [3:0] ALU_SUB      = 4'd9;
    localparam [3:0] ALU_XOR      = 4'd10;
    localparam [3:0] ALU_AND      = 4'd11;
