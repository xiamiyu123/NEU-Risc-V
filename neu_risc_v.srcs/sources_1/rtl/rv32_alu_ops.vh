//=============================================================================
// 文件   : rv32_alu_ops.vh
// 功能   : ALU 操作码编号定义（被 rv32_alu.v 与 rv32_control.v 共同 include）
// 说明   : 使用 localparam，仅在包含它的模块内部可见，不会污染全局命名空间。
//          编号本身无外部意义，只需两个模块保持一致即可。
//=============================================================================
    localparam [3:0] ALU_ADD      = 4'd0;  // 加法
    localparam [3:0] ALU_SLT      = 4'd1;  // 有符号比较：a < b ? 1 : 0
    localparam [3:0] ALU_SLTU     = 4'd2;  // 无符号比较：a < b ? 1 : 0
    localparam [3:0] ALU_OR       = 4'd3;  // 按位或
    localparam [3:0] ALU_LUI      = 4'd4;  // LUI 透传（结果 = b）
    localparam [3:0] ALU_SLL      = 4'd5;  // 逻辑左移
    localparam [3:0] ALU_SRL      = 4'd6;  // 逻辑右移
    localparam [3:0] ALU_SRA      = 4'd7;  // 算术右移
    localparam [3:0] ALU_UADD8SAT = 4'd8;  // 定制指令：4 路字节饱和加法
    localparam [3:0] ALU_SUB      = 4'd9;  // 减法
    localparam [3:0] ALU_XOR      = 4'd10; // 按位异或
    localparam [3:0] ALU_AND      = 4'd11; // 按位与