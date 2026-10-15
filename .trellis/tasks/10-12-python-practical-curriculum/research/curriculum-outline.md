# Python curriculum outline — 120 lessons (progressive)

Stable ids: `python-tutorial-001..120` (each with exactly one lesson
`python-tutorial-NNN-lesson`) and `python-example-001..120`
(`sourceLessonId: python-tutorial-NNN-lesson`). 120 tutorial + 120 example
records, 1:1 paired, in the aggregate `assets/content/{tutorials,examples}.json`
under `language: "python"` / `type: "python"`.

Levels: `beginner` (001–040), `intermediate` (041–080), `advanced` (081–120).

Every lesson carries: `objective`, `prerequisites`, `concepts`, Chinese
`explain` (substantive prose), a complete runnable `code`, real `output`,
`pitfalls`, and `exercises` (prompt/hint/answer). Every example is the runnable
companion of its lesson, executed against the embedded MicroPython runtime.

Legend for the "Runtime" column: **EMB** = runs in the bundled embedded
MicroPython runtime and is verified there; **EXT** = CPython-only topic,
explicitly labeled as requiring an external CPython environment (its runnable
code, if any, is verified in CPython, never claimed to pass embedded).

## Chapter 1 — 起步 (Beginner 001–008)

| # | Title | Concepts | Runtime |
|---|---|---|---|
| 001 | 第一个 Python 程序 | print, 字符串, 缩进 | EMB |
| 002 | 变量与动态类型 | 赋值, type(), int/float/str/bool | EMB |
| 003 | 数值与运算符 | 算术, 整除, 取余, 幂, 优先级 | EMB |
| 004 | 字符串入门 | 拼接, 索引, 切片, len | EMB |
| 005 | f-string 格式化 | f-string, 格式说明符, 对齐 | EMB |
| 006 | 布尔与比较 | bool, and/or/not, 短路 | EMB |
| 007 | 类型转换 | int()/float()/str(), 隐式与显式 | EMB |
| 008 | 输入 input() 与 input.txt | input, split, 类型转换 | EMB |

## Chapter 2 — 流程控制 (Beginner 009–016)

| # | Title | Concepts | Runtime |
|---|---|---|---|
| 009 | if / elif / else | 条件分支, 缩进 | EMB |
| 010 | while 循环 | 循环条件, 计数器, break | EMB |
| 011 | for 与 range | 遍历, range 三参数 | EMB |
| 012 | 嵌套循环 | 九九乘法表, 嵌套 | EMB |
| 013 | break 与 continue | 循环控制, else 子句 | EMB |
| 014 | 循环模式：累加、计数、最值 | 累加器, 哨兵 | EMB |
| 015 | 综合：数字金字塔与图形 | 字符串乘法, 嵌套 | EMB |
| 016 | 综合：猜数字（确定性版） | random.seed, 循环+分支 | EMB |

## Chapter 3 — 容器 (Beginner 017–028)

| # | Title | Concepts | Runtime |
|---|---|---|---|
| 017 | 列表基础 | list, 索引, 切片, append | EMB |
| 018 | 列表方法与原地修改 | append/insert/remove/pop/sort | EMB |
| 019 | 列表推导式 | comprehension, 条件过滤 | EMB |
| 020 | 元组与解包 | tuple, 解包, 不可变 | EMB |
| 021 | 字典基础 | dict, get, items | EMB |
| 022 | 字典进阶：计数与分组 | 累加计数, setdefault 模式 | EMB |
| 023 | 集合 set | 去重, 交并差 | EMB |
| 024 | 字符串进阶：split/join/strip | 文本处理 | EMB |
| 025 | 排序与 key 函数 | sorted, key=, reverse | EMB |
| 026 | enumerate / zip | 下标遍历, 并行遍历 | EMB |
| 027 | 切片进阶 | 步长, 反转, 复制语义 | EMB |
| 028 | 综合：词频统计 | dict + 循环 + 排序 | EMB |

## Chapter 4 — 函数 (Beginner 029–040)

| # | Title | Concepts | Runtime |
|---|---|---|---|
| 029 | 定义函数与返回值 | def, return, None | EMB |
| 030 | 参数：默认值、关键字 | 默认参数, 关键字实参 | EMB |
| 031 | 可变参数 *args / **kwargs | 打包解包 | EMB |
| 032 | 作用域与 LEGB | 局部/全局, global | EMB |
| 033 | 递归入门 | 递归, 基线条件 | EMB |
| 034 | 递归进阶：汉诺塔与斐波那契 | 递归树, 记忆化 | EMB |
| 035 | lambda 与高阶函数 | lambda, map/filter | EMB |
| 036 | 闭包 | 嵌套函数, nonlocal | EMB |
| 037 | 装饰器入门 | 函数即对象, @语法 | EMB |
| 038 | 装饰器进阶：带参数与堆叠 | 装饰器工厂, wraps 手写 | EMB |
| 039 | 生成器入门 | yield, 惰性求值 | EMB |
| 040 | 生成器表达式与管道 | genexpr, 链式处理 | EMB |

## Chapter 5 — 模块、异常、文件 (Intermediate 041–052)

| # | Title | Concepts | Runtime |
|---|---|---|---|
| 041 | 模块与 import | import, from, as, __name__ | EMB |
| 042 | 包与相对导入 | __init__ 包, sys.path | EMB |
| 043 | 异常基础 | try/except, 异常类型 | EMB |
| 044 | 异常进阶：else/finally/raise | 清理, 自定义异常 | EMB |
| 045 | 常见异常辨析 | IndexError/KeyError/ValueError/TypeError | EMB |
| 046 | 文件读写 | open, with, 模式 | EMB |
| 047 | 文件进阶：逐行处理 | 迭代文件, 大文件 | EMB |
| 048 | 文本编码与处理 | 编码, 换行, strip | EMB |
| 049 | json 模块基础 | json.loads/dumps | EMB |
| 050 | json 模块进阶：读写配置 | 序列化, 嵌套结构 | EMB |
| 051 | 标准库概览：math / random / heapq | 分类, 常用函数 | EMB |
| 052 | 综合：一个迷你待办清单 | 文件 + json + 函数 | EMB |

## Chapter 6 — 面向对象 (Intermediate 053–068)

| # | Title | Concepts | Runtime |
|---|---|---|---|
| 053 | 类与对象 | class, __init__, self | EMB |
| 054 | 属性与方法 | 实例属性, 方法 | EMB |
| 055 | 封装与命名约定 | 下划线约定, property | EMB |
| 056 | @property 计算属性 | getter, 只读属性 | EMB |
| 057 | 继承与 super | 继承, 方法重写 | EMB |
| 058 | 多态 | 统一接口, 鸭子类型 | EMB |
| 059 | 类方法与静态方法 | @classmethod, @staticmethod | EMB |
| 060 | 魔术方法：__str__/__repr__ | 打印协议 | EMB |
| 061 | 魔术方法：__eq__/__lt__ | 比较协议, 排序 | EMB |
| 062 | 魔术方法：__len__/__getitem__ | 容器协议 | EMB |
| 063 | 运算符重载 | __add__/__mul__ 等 | EMB |
| 064 | __slots__ 与内存 | 属性限制 | EMB |
| 065 | 组合优于继承 | 组合模式 | EMB |
| 066 | 数据类：手写实现 | 用类模拟 dataclass | EMB |
| 067 | 综合：图书管理系统 | 类设计, 集合管理 | EMB |
| 068 | 综合：银行账户 | 封装, 事务式操作 | EMB |

## Chapter 7 — 迭代器、异常设计、函数式 (Intermediate 069–080)

| # | Title | Concepts | Runtime |
|---|---|---|---|
| 069 | 迭代器协议 | __iter__/__next__, StopIteration | EMB |
| 070 | 自定义可迭代对象 | 迭代器类 | EMB |
| 071 | 生成器进阶：send/状态机 | 协程式生成器 | EMB |
| 072 | 惰性管道与内存 | 惰性求值, 大数据流 | EMB |
| 073 | 异常设计模式 | 异常层次, 语义化异常 | EMB |
| 074 | 上下文管理器类 | __enter__/__exit__ | EMB |
| 075 | 装饰器实战：计时与缓存 | 记忆化手写 | EMB |
| 076 | 装饰器实战：日志与重试 | 参数化装饰器 | EMB |
| 077 | 高阶函数模式 | 函数组合, partial 手写 | EMB |
| 078 | reduce 与聚合 | 手写 reduce, 聚合模式 | EMB |
| 079 | 柯里化与工厂函数 | 函数工厂 | EMB |
| 080 | 综合：函数式数据处理管道 | 组合生成器与装饰器 | EMB |

## Chapter 8 — 算法与数据结构 (Advanced 081–096)

| # | Title | Concepts | Runtime |
|---|---|---|---|
| 081 | 复杂度与计时 | 时间复杂度, time.sleep_ms 计时 | EMB |
| 082 | 线性查找与二分查找 | 搜索算法, 边界 | EMB |
| 083 | 冒泡、选择、插入排序 | 排序原理 | EMB |
| 084 | 归并排序 | 分治, 递归合并 | EMB |
| 085 | 快速排序 | 分治, 枢轴 | EMB |
| 086 | 用 heapq 实现优先队列 | 堆, 优先队列 | EMB |
| 087 | 链表 | 节点, 指针式结构 | EMB |
| 088 | 栈与队列 | LIFO/FIFO, collections.deque | EMB |
| 089 | 哈希表原理与 dict | 散列, 冲突 | EMB |
| 090 | 二叉树与遍历 | BST, 前中后序 | EMB |
| 091 | 图与 DFS/BFS | 邻接表, 搜索 | EMB |
| 092 | 动态规划入门 | 记忆化, 递推 | EMB |
| 093 | 动态规划进阶：背包 | 状态定义, 转移 | EMB |
| 094 | 贪心算法 | 贪心策略, 反例 | EMB |
| 095 | 递归回溯：N 皇后 | 回溯, 剪枝 | EMB |
| 096 | 综合：迷宫求解 | BFS/DFS 应用 | EMB |

## Chapter 9 — 测试、调试、工程实践 (Advanced 097–108)

| # | Title | Concepts | Runtime |
|---|---|---|---|
| 097 | 断言与自检 | assert, 契约 | EMB |
| 098 | 手写测试框架 | 测试函数, 汇总 | EMB |
| 099 | 边界与异常测试 | 边界值, 异常断言 | EMB |
| 100 | 调试技巧 | 打印调试, 二分定位 | EMB |
| 101 | 错误处理最佳实践 | 早失败, 语义异常 | EMB |
| 102 | 模块化与分层 | 职责划分 | EMB |
| 103 | 配置与常量管理 | 常量集中, const | EMB |
| 104 | 输入校验 | 防御式编程 | EMB |
| 105 | 日志式输出设计 | 分级输出 | EMB |
| 106 | 性能优化基础 | 缓存, 避免重复计算 | EMB |
| 107 | 代码风格与可读性 | 命名, 结构 | EMB |
| 108 | 综合：可测试的小工具库 | 模块 + 测试 | EMB |

## Chapter 10 — 综合项目与 CPython 生态 (Advanced 109–120)

| # | Title | Concepts | Runtime |
|---|---|---|---|
| 109 | 综合项目：命令行记账程序 | 文件 + json + 类 | EMB |
| 110 | 综合项目：学生成绩分析 | 数据 + 统计 + 排序 | EMB |
| 111 | 综合项目：文本冒险游戏 | 状态机 + 字典 | EMB |
| 112 | 综合项目：矩阵与线性代数入门 | 嵌套列表 + 算法 | EMB |
| 113 | 综合项目：简易正则日志分析 | re 子集 + 统计 | EMB |
| 114 | 综合项目：股票/数值模拟 | random + 序列建模 | EMB |
| 115 | 综合项目：JSON 数据 API 模拟 | 数据建模 + 序列化 | EMB |
| 116 | 编程范式总览 | 过程/面向对象/函数式 | EMB |
| 117 | 通往 CPython：标准库生态 | pypi, venv, pip（介绍） | EXT |
| 118 | 通往 CPython：类型注解与 dataclasses | typing, dataclasses | EXT |
| 119 | 通往 CPython：os/路径/时间 | os, datetime, pathlib | EXT |
| 120 | 通往 CPython：并发与异步概览 | threading, asyncio | EXT |

## Coverage check against the PRD list

- 语言基础: 001–016. 数据结构: 017–028, 087–091.
- 函数: 029–040, 077–079. 模块: 041–042, 102–103. 异常: 043–045, 073, 101.
- 文件: 046–050. OOP: 053–068. 迭代器/生成器: 039–040, 069–072.
- 装饰器: 037–038, 075–076. 算法: 081–096. 测试/调试: 097–104.
- 工程实践: 100–108. 综合项目: 052, 067–068, 109–115.
- 高级 CPython 专属: 117–120, explicitly marked EXT.

Totals: 120 tutorials, 120 examples, 120 EM B lessons + 4 EXT lessons
(116 embedded-verified + 4 externally-labeled).
