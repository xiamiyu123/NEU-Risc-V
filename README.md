# 课程设计 CPU

本仓库实现五级流水线的 RV32I CPU，覆盖 40 条标准 RV32I 指令，并保留课程设计的定制指令 `uadd8sat`。设计依据和路线图见 [DESIGN_ROADMAP.md](DESIGN_ROADMAP.md)。

CPU 的数据通路、流水线控制、存储器接口、异常行为和验证范围见 [CPU_DESIGN.md](CPU_DESIGN.md)。

## 运行验证

需要 Icarus Verilog；可选 Yosys 检查可综合性。macOS 上可用 `brew install icarus-verilog yosys` 安装。

```sh
make test
make synth-check
make synth-xilinx
```

`make test` 运行十三套自检：八套模块/集成测试，以及 `review/` 下五套独立复核测试（53 项检查）。覆盖 ALU、译码、寄存器堆、同步存储器、流水线、ROM 演示、RV32I 指令/异常和流水线边界。每套输出保存到 `build/<测试台名>.log`，断言失败会令 Make 返回非零退出码。覆盖范围见 [设计书的验证说明](CPU_DESIGN.md#10-验证方式与当前证据)。

可单独运行一套，例如 `make test-tb_alu` 或 `make test-tb_review3`；`make test-review` 仅运行五套独立复核。`make synth-check` 做通用综合，`make synth-xilinx` 做 Xilinx 7 系列映射；所有日志位于忽略跟踪的 `build/`。

### 导出与查看测试波形

普通 `make test` 只输出自检日志。增加波形导出时，自检仍会运行，失败仍返回非零退出码：

```sh
make wave                      # 综合场景：流水线、转发、停顿、跳转
make wave-tb_pipeline_edges     # 边界场景：异常、冲刷、中途复位
make wave-tb_demo               # ROM 演示
make wave-tb_review8            # load→store、load 地址依赖
```

全部十三套测试均支持 `make wave-<测试台名>`，生成 `build/<测试台名>.vcd`，日志仍保存为 `.log`。安装 GTKWave 后，例如执行 `gtkwave build/tb_rv32_soc.vcd` 即可查看；VCD 来自真实 RTL 仿真，不是示意图。导出包括层次中的标量和向量信号，不保证展开寄存器、RAM 等数组的全部元素，可通过写回和访存接口观察它们的变化。

在波形查看器中展开 `tb_rv32_soc/dut/core`，建议按以下顺序添加信号，多位数据设为十六进制：

| 观察内容 | 信号 | 重点 |
| --- | --- | --- |
| 时钟与取指 | `clk`、`rst`、`pc`、`imem_re`、`ifid_pc`、`ifid_instr` | 顺序取指时 PC 加 4，停顿时保持 |
| 流水推进 | `ifid_valid`、`idex_valid`、`exmem_valid`、`memwb_valid` | 有效位为 0 的项是气泡，数据字段可能仍保留旧值 |
| 转发 | `idex_rs1_data`、`idex_rs2_data`、`ex_rs1`、`ex_rs2`、`exmem_result`、`wb_data` | EX 使用的值可能来自前级结果，而不是 ID 原读值 |
| load-use | `load_stall`、`idex_memread`、`idex_rd` | 停顿时 PC/IF-ID 保持，ID/EX 插入气泡，后端继续推进 |
| 跳转与冲刷 | `redirect`、`target_pc`、`idex_pc`、`branch_taken` | 命中跳转后 PC 改为目标，前端有效位清零 |
| 访存与写回 | `dmem_re`、`dmem_we`、`dmem_addr`、`dmem_wdata`、`wb_we`、`memwb_rd`、`wb_data` | 检查实际读写地址、数据和目标寄存器 |
| 异常 | `ex_exception_valid`、`trap_pending`、`fault`、`fault_cause`、`fault_pc` | 故障指令取消，老指令排空后 `fault` 置位 |

先看 `tb_rv32_soc` 的停顿与跳转，再看 `tb_pipeline_edges` 的异常和复位；它们包含多个独立场景，`rst` 再次拉高表示新场景开始。`tb_demo` 的最终演示结果位于 `dut/result_valid` 和 `dut/result_data`。

Vivado/XSim 可按下文直接添加内部信号查看原生波形；ModelSim/Questa 的 `scripts/run_modelsim.do` 已加入层次信号记录和波形显示命令，仍待在对应工具中实测。

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

- `sources_1/rtl/rv32_core.v`：CPU 主体，连接子模块，管理 IF/ID/EX/MEM/WB 流水线、转发、阻塞、冲刷与异常。
- `sources_1/rtl/rv32_control.v`：指令译码、立即数与控制信号生成。
- `sources_1/rtl/rv32_alu.v`：算术、逻辑、移位及定制饱和加法。
- `sources_1/rtl/rv32_regfile.v`：通用寄存器堆、`x0` 保护与 WB 到 ID 旁路。
- `sources_1/rtl/rv32_alu_ops.vh`：译码器和 ALU 共用的内部操作编号。
- `sources_1/rtl/rv32_sync_mem.v`：同步读、按字节写的 32 位字存储器，可用 `$readmemh` 初始化。
- `sources_1/rtl/rv32_soc.v`：内核加分离的指令/数据存储器，默认每块 256 字。

## 从零开始在 Vivado 中打开与仿真

教师已确认验收只需仿真，不要求上板。下面以 Windows、仓库路径 `D:/Projects/NEU-Risc-V` 为例；Linux 使用相同的 Tcl 命令，只需替换路径。

### 1. 准备工具

安装 Git 和 Vivado，或使用学校已有的 Vivado 环境。Vivado 安装时需包含所选器件系列的支持；下面示例使用 Artix-7 器件。运行 Vivado 自带的 XSim 无需另外安装 Icarus Verilog、Yosys 或 Make。

### 2. Clone 仓库

在 PowerShell、Git Bash 或 Linux 终端中，进入准备存放项目的目录后执行：

```sh
git clone https://github.com/xiamiyu123/NEU-Risc-V.git
cd NEU-Risc-V
```

确认仓库内有 `scripts/create_project.tcl` 和 `neu_risc_v.srcs/`。`.xpr` 是本地生成文件，clone 后暂时没有该文件是正常的。若已有本地仓库，先处理自己的改动，再用 `git pull` 获取更新。

### 3. 首次创建并打开工程

启动 Vivado，在底部 **Tcl Console** 中依次执行：

```tcl
cd {D:/Projects/NEU-Risc-V}
set argc 1
set argv [list xc7a35tcpg236-1]
source scripts/create_project.tcl
```

将 `D:/Projects/NEU-Risc-V` 替换为实际 clone 路径。Windows 路径使用 `/`，外层 `{}` 可处理路径中的空格。`argc` 和 `argv` 用来向脚本传递一个器件型号。

`xc7a35tcpg236-1` 只是仿真工程的示例器件，不代表指定开发板。若 Vivado 提示不支持该器件，选择当前安装支持的完整器件型号，并替换 `argv` 中的值。行为仿真不要求该型号对应实际板卡。

成功后 Tcl Console 会输出 `Project created: .../neu_risc_v.xpr`，工程会在当前 Vivado 中打开。工程文件位于：

```text
NEU-Risc-V/build/vivado/neu_risc_v.xpr
```

**Sources** 中应包含设计顶层 `rv32_soc`、仿真顶层 `tb_rv32_soc` 和初始化文件 `demo.mem`。脚本使用 `add_files` 引用仓库源文件，在 Vivado 中编辑它们会直接修改工作区。

### 4. 运行行为仿真

在左侧 **Flow Navigator** 中选择 **Simulation → Run Simulation → Run Behavioral Simulation**。脚本已设置运行到测试台结束；若仿真停在中途，在仿真的 Tcl Console 中执行 `run all`。

默认测试台为 `tb_rv32_soc`。在 **Sources → Simulation Sources** 中右键其他测试台，选择 **Set as Top** 即可切换；切换前关闭当前仿真，再重新运行 Behavioral Simulation。原有三个集成测试台的成功输出如下；新增五套测试台也分别运行到 `PASS`：

| 测试台 | 检查内容 | 成功输出 |
| --- | --- | --- |
| `tb_rv32_soc` | 流水线、冒险、分支、定制指令和存储器 | `PASS: instruction, hazard, branch, custom and memory tests` |
| `tb_demo` | ROM 初始化和演示程序 | `PASS: initialized ROM demo produced 112234ff` |
| `tb_rv32i` | RV32I 指令和异常 | `PASS: complete RV32I instruction and trap tests` |

新增测试台为 `tb_alu`、`tb_control`、`tb_regfile`、`tb_memory`、`tb_pipeline_edges`。ALU 测试包含 65,536 对字节输入，仿真时间约为 78 μs，使用 `run all` 等待其自行结束。工程脚本会收集所有 `.sv` 测试文件；旧工程需刷新文件集或按重建流程重新创建工程。

工程脚本也会加入 `review/tb_review{3,4,6,7,8}.sv` 五个独立复核测试台，可同样设为仿真顶层运行。

演示程序结束时应有 `result_valid=1`、`result_data=0x112234ff`。`.mem` 已加入工程，测试台使用文件名 `demo.mem` 读取，无需手动改成绝对路径。综合顶层的工程参数为 `IMEM_FILE="demo.mem"`；RTL 本身仍保留空初始化文件的默认参数。

查看内部波形时，在 **Scope** 中选择 `dut` 或 `dut/core`，在 **Objects** 中选中所需信号并使用 **Add to Wave Window**。若信号在首次运行后才加入，执行 **Restart**，再 **Run All**，以记录从复位开始的波形。保存自检日志和关键波形用于验收。

### 5. 后续重新打开

选择 Vivado 的 **Open Project**，打开 `build/vivado/neu_risc_v.xpr`，无需重复执行创建脚本。脚本不会覆盖已有工程；若需要重建，先关闭工程并保存所需日志、波形和设置，再移走 `build/vivado/` 后重新执行脚本。

若工程创建于模块拆分之前，需要按上述方式重建，使新增的 `rv32_control`、`rv32_alu`、`rv32_regfile` 及共享头文件纳入工程。

### 可选：从命令行生成工程

如果终端已配置 Vivado 命令，在仓库根目录执行：

```sh
vivado -mode batch -source scripts/create_project.tcl -tclargs xc7a35tcpg236-1
```

安装了 Make 时，也可以执行 `make vivado-project PART=xc7a35tcpg236-1`。命令结束后，使用 Vivado 的 **Open Project** 打开生成的 `.xpr`。

流程参考 AMD 官方的 [Tcl 创建工程说明](https://docs.amd.com/r/2021.1-English/ug895-vivado-system-level-design-entry/Creating-a-Project-Using-a-Tcl-Script)、[工程打开说明](https://docs.amd.com/r/2020.2-English/ug895-vivado-system-level-design-entry/Opening-a-Project)和 [XSim 命令说明](https://docs.amd.com/r/en-US/ug900-vivado-logic-simulation/Vivado-Simulator-Quick-Reference-Guide)。本机没有 Vivado，工程脚本及上述流程尚未经过实际 Vivado 验证。

## CPU 行为与指令

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

## 验收状态

2026-10-08，用户转述教师确认验收只需仿真，不要求上板。RTL 已通过本地 Icarus 仿真、Yosys 通用综合及 Xilinx 7 系列映射检查。已提供 Vivado 工程生成脚本；本机没有 Vivado，实际建工程和 Vivado 行为仿真尚未验证。

验收准备包括运行十三套测试台的行为仿真，保存自检通过的日志，并整理流水线转发、load-use 停顿、分支冲刷、异常和定制指令的关键波形。演示程序预期结果为 `result_valid=1`、`result_data=0x112234ff`。板级封装、引脚约束、bitstream 和实板运行作为可选扩展。

ModelSim/Questa 的交互式入口为 `scripts/run_modelsim.do`：在其 Transcript 中执行 `do {D:/Projects/NEU-Risc-V/scripts/run_modelsim.do}`，替换实际路径即可。脚本默认运行 `tb_rv32_soc`，可修改 `testbench` 选择其他测试台。此入口已按当前目录结构整理，但尚未经实际 ModelSim/Questa 运行验证。
