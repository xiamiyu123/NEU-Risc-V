# 板级约束

确认开发板的准确器件、时钟频率和引脚后，将 `.xdc` 文件放在此目录。
`scripts/create_project.tcl` 会将这些文件加入 `constrs_1`。

当前顶层为 `rv32_soc`，尚未添加板级封装或引脚、时钟约束。
