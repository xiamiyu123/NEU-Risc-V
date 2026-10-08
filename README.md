# 课程设计 CPU

本仓库实现五级流水线的 RV32I CPU，覆盖 40 条标准 RV32I 指令，并保留课程设计的定制指令 `uadd8sat`。设计依据和路线图见 [DESIGN_ROADMAP.md](DESIGN_ROADMAP.md)。

## 运行验证

需要 Icarus Verilog；可选 Yosys 检查可综合性。macOS 上可用 `brew install icarus-verilog yosys` 安装。

```sh
make test
make synth-check
make synth-xilinx
```

`make test` 运行流水线自检、ROM 演示和 RV32I 指令及异常测试，覆盖转发优先级、load-use 停顿、`x0`、分支冲刷、字节/半字访存和定制指令。`make synth-check` 做通用综合，`make synth-xilinx` 做 Xilinx 7 系列映射；日志位于忽略跟踪的 `build/`。

## 结构与接口

工作区按 Vivado 文件集组织，源文件纳入版本管理，生成的工程和运行产物放在 `build/`：

```text
neu_risc_v.srcs/
├── sources_1/
│   ├── rtl/                 # 可综合 RTL
│   └── mem/demo.mem         # 演示程序的十六进制机器码
├── sim_1/tb/                # SystemVerilog 自检和编码辅助头文件
└── constrs_1/               # 板级 XDC 约束目录
scripts/create_project.tcl   # Vivado 工程生成脚本
build/vivado/               # 生成的 neu_risc_v.xpr 和 Vivado 产物
```

- `sources_1/rtl/rv32_core.v`：IF/ID/EX/MEM/WB 流水线、译码、转发、阻塞与冲刷。
- `sources_1/rtl/rv32_sync_mem.v`：同步读、按字节写的 32 位字存储器，可用 `$readmemh` 初始化。
- `sources_1/rtl/rv32_soc.v`：内核加分离的指令/数据存储器，默认每块 256 字。

### 创建 Vivado 工程

在安装 Vivado 的机器上，从仓库根目录运行，替换 `<准确器件型号>`：

```sh
make vivado-project PART=<准确器件型号>
# 或直接运行
vivado -mode batch -source scripts/create_project.tcl -tclargs <准确器件型号>
```

随后打开 `build/vivado/neu_risc_v.xpr`。脚本使用 `add_files` 引用仓库中的源文件；在 Vivado 中编辑它们会直接修改工作区。工程已存在时脚本会报错，不覆盖已有工程；更新已有工程可在 GUI 中添加文件，或保留所需设置后移走生成目录再重建。

综合顶层为 `rv32_soc`，工程参数 `IMEM_FILE="demo.mem"` 装入演示程序；RTL 本身仍保留空初始化文件的默认参数。默认仿真顶层为 `tb_rv32_soc`，可在 Simulation Sources 中将 `tb_demo` 或 `tb_rv32i` 设为顶层，运行 Behavioral Simulation。`.mem` 已加入设计文件集，仿真用文件名 `demo.mem` 读取；`make test` 会将它复制到 `build/`，并从该目录运行 Icarus 仿真。

确认板卡资料后，将 `.xdc` 加入 `neu_risc_v.srcs/constrs_1/`。目前没有板级时钟和引脚约束，工程创建完成不代表已能生成可上板的 bitstream。

PC 复位值为 0，地址按字节计。支持 RV32I 的整数运算、分支与跳转、`lb`/`lbu`/`lh`/`lhu`/`lw`、`sb`/`sh`/`sw`、`fence`、`ecall` 和 `ebreak`。单核、顺序、无缓存的存储器接口使 `fence` 无需额外硬件操作。`ecall` 和 `ebreak` 向外部环境报告异常。

| 类别 | 指令 |
| --- | --- |
| 寄存器运算 | `add` `sub` `sll` `slt` `sltu` `xor` `srl` `sra` `or` `and` |
| 立即数运算 | `addi` `slti` `sltiu` `xori` `ori` `andi` `slli` `srli` `srai` |
| 加载与存储 | `lb` `lh` `lw` `lbu` `lhu` `sb` `sh` `sw` |
| 分支 | `beq` `bne` `blt` `bge` `bltu` `bgeu` |
| 上位立即数与跳转 | `lui` `auipc` `jal` `jalr` |
| 内存顺序与环境 | `fence` `ecall` `ebreak` |

指令与数据存储器分离，默认各 256 个字，即各 1 KiB。配置范围之外的取指或数据访问会报告访问故障，不会按低位回绕；对齐不满足要求的跳转、半字或字访存会报告地址未对齐。异常接口由 `fault`、`fault_cause`、`fault_pc` 和 `fault_tval` 构成：先让更早的指令完成，再置位 `fault` 并停机；故障指令及其后续指令不产生副作用。`fault_cause` 使用 RISC-V 常见编码：0/1/2 为取指未对齐/访问故障/非法指令，3 为断点，4/5 为加载未对齐/访问故障，6/7 为存储未对齐/访问故障，11 为机器模式环境调用。未实现特权级、CSR 或异常入口；运行环境可用这些端口处理终止事件。

本设计只实现 RV32I 基础整数指令集，`Zicsr`、`Zifencei`、压缩指令及乘除法扩展均不在范围内。存储器容量和异常处理方式是这个 SoC 的运行环境约定；运行大型软件仍需扩展存储器及系统接口。

演示程序相当于：

```asm
lui       x1, 0x10203
ori       x1, x1, 0x0fa
lui       x2, 0x01020
ori       x2, x2, 0x414
uadd8sat  x3, x1, x2
sw        x3, 0(x0)
jal       x0, 0
```

定制指令 `uadd8sat` 使用 `custom-0` opcode `0001011`、R 型字段、`funct3=000`、`funct7=0000000`。它对两个源寄存器内的四对无符号字节分别求和并饱和到 255。演示结果为 `0x112234ff`，写入数据存储器字 0；`rv32_soc` 的 `result_valid` 和 `result_data` 保留这次写入，方便之后接板级观察逻辑。它不是标准汇编器内建的助记符，`neu_risc_v.srcs/sources_1/mem/demo.mem` 已提供机器码。

## 板级状态

RTL 已通过本地仿真和 Yosys 通用综合检查，也通过 Yosys 的 Xilinx 7 系列映射检查。已提供 Vivado 工程生成脚本；本机没有 Vivado，尚未验证实际建工程、Vivado 综合和时序。准确器件、引脚和时钟仍待板卡资料确认，实板运行尚未完成。拿到板卡资料后，需要添加板级封装和约束，再以板上可用的输出或调试接口验证 `result_data`。
