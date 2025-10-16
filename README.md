# Uniswap V3 Move

[![Move](https://img.shields.io/badge/Move-2024.beta-blue)](https://docs.sui.io/)
[![Sui](https://img.shields.io/badge/Sui-Testnet-orange)](https://sui.io/)

一个基于 Move 语言实现的 Uniswap V3 核心协议，运行在 Sui 区块链上。这是一个学习项目，通过将 Uniswap V3 的核心逻辑翻译为 Move 语言，帮助开发者深入理解去中心化交易所的设计原理和 Move 语言的特性。

## 📋 目录

- [项目简介](#项目简介)
- [核心特性](#核心特性)
- [项目架构](#项目架构)
- [模块说明](#模块说明)
- [快速开始](#快速开始)
- [测试](#测试)
- [技术栈](#技术栈)
- [学习路径](#学习路径)
- [参考资料](#参考资料)

## 🎯 项目简介

v3_core_move 是 Uniswap V3 协议在 Sui 区块链上的核心实现版本。该项目采用 Move 语言开发，旨在为 Sui 生态系统提供高性能、安全可靠的去中心化交易所基础设施。

### 设计目标

- **性能优化**：针对 Sui 区块链的并行执行模型进行优化
- **安全性保障**：利用 Move 语言的内存安全特性
- **可扩展性**：支持多种代币对和费率配置
- **易用性**：提供简洁直观的 API 接口

## ✨ 核心特性

### 集中流动性

- ✅ 支持用户在指定价格区间内提供流动性
- ✅ 通过 Tick 系统实现精确的价格控制
- ✅ 提高资本效率，降低滑点

### 多级手续费

- ✅ 支持 0.05%、0.3%、1% 等多种费率配置
- ✅ 灵活的协议费用管理
- ✅ 动态的费率启用/禁用机制

### 高精度数学计算

- ✅ Q64.64 定点数格式确保价格精度
- ✅ 完整的 Tick 与价格转换逻辑
- ✅ 优化的流动性计算算法

### 权限控制

- ✅ 基于 ACL 的角色权限模型
- ✅ 细粒度的操作权限管理
- ✅ 安全的合约升级机制

## 🏗️ 项目架构

```
v3_core_move/
├── sources/                    # 核心源代码
│   ├── config.move            # 配置管理模块
│   ├── factory.move           # 工厂模块 - 池子创建
│   ├── pool.move              # 流动性池核心逻辑
│   ├── position.move          # 头寸管理
│   ├── router.move            # 路由模块 - 交易执行
│   ├── ticks.move             # Tick 数据管理
│   ├── lib/                   # 核心库
│   │   ├── acl.move          # 权限控制
│   │   ├── bit_math.move     # 位运算
│   │   ├── liquidity_math.move   # 流动性计算
│   │   ├── sqrt_price_math.move  # 价格计算
│   │   ├── swap_math.move    # 交易数学
│   │   ├── tick_bitmap.move  # Tick 位图
│   │   └── tick_math.move    # Tick 数学计算
│   └── math/                  # 基础数学库
│       ├── full_math_u128.move
│       ├── full_math_u64.move
│       ├── i128.move         # 128位有符号整数
│       ├── i16.move          # 16位有符号整数
│       ├── i32.move          # 32位有符号整数
│       ├── i64.move          # 64位有符号整数
│       ├── math_u128.move    # 128位无符号整数运算
│       ├── math_u256.move    # 256位无符号整数运算
│       └── math_u64.move     # 64位无符号整数运算
├── tests/                     # 测试代码
│   └── router_test.move      # 路由测试
├── Move.toml                  # 项目配置文件
└── README.md                  # 项目文档
```

## 📦 模块说明

### 核心模块

#### Factory（工厂模块）
负责创建和管理流动性池，主要功能包括：
- 为不同的代币对和费率组合创建新的流动性池
- 费率管理：支持多种预设费率配置（0.05%、0.3%、1%）
- 池子键生成：为每个独特的池子生成唯一标识符

#### Pool（流动性池模块）
系统的核心组件，提供：
- 流动性管理：添加、移除和查询流动性
- 价格跟踪：维护当前市场价格和 Tick 信息
- 交易执行：处理代币交换和手续费收取
- 事件系统：记录关键操作的事件

#### Position（头寸管理模块）
负责用户头寸的生命周期管理：
- 头寸开仓：在指定的 Tick 范围内建立流动性头寸
- 头寸关闭：移除头寸并提取相应的代币
- 头寸查询：获取头寸的详细信息和收益情况

#### Router（路由模块）
提供高级交易接口：
- 单跳交易执行
- 多跳路径优化（规划中）
- 滑点保护

#### Config（配置管理）
管理协议的全局配置：
- 手续费率配置
- Tick 间距设置
- 协议费用管理
- 版本控制

### 数学计算库

#### Tick Math
- Tick 与价格的双向转换
- 支持的价格范围：2^-64 到 2^64
- 高精度的对数计算

#### 价格数学（sqrt_price_math）
- 基于 Q64.64 定点数格式的价格计算
- 流动性变动导致的价格更新
- 价格滑点计算

#### 流动性数学（liquidity_math）
- 流动性增减的安全操作
- 支持有符号的流动性变化
- 数值溢出保护

#### 交易数学（swap_math）
- 单步交易计算
- 手续费计算和分配
- 价格影响计算

### 工具库

#### ACL（访问控制列表）
- 角色权限模型
- 权限的授予与撤销
- 权限继承机制

#### Tick Bitmap
- 高效的 Tick 索引
- 位图压缩存储
- 快速查找下一个初始化的 Tick

## 🚀 快速开始

### 环境准备

1. 安装 Sui CLI
```bash
cargo install --locked --git https://github.com/MystenLabs/sui.git --branch testnet sui
```

2. 克隆项目
```bash
git clone github.com/happlins/uniswap-v3-core-move
cd uniswap-v3-core-move
```

### 构建项目

```bash
sui move build
```

### 发布到测试网

```bash
sui client publish --gas-budget 100000000
```

## 🧪 测试

### 运行所有测试

```bash
sui move test
```

### 运行特定测试

```bash
sui move test --filter router_test
```

### 测试覆盖

项目包含全面的测试套件，包括：
- ✅ 路由模块测试
- ⏳ 池子模块测试（规划中）
- ⏳ 数学库测试（规划中）
- ⏳ 集成测试（规划中）

## 🛠️ 技术栈

- **语言**：Move 2024.beta
- **区块链**：Sui Testnet
- **框架**：Sui Framework
- **开发工具**：Sui CLI

### Move 语言特性应用

- **所有权系统**：确保资产的安全转移
- **能力系统**：精确控制对象的操作权限
- **泛型**：实现通用的代币池逻辑
- **事件**：记录链上活动
- **共享对象**：支持并发访问的池子状态

## 📖 参考资料

### Uniswap V3
- [Uniswap V3 官方白皮书](https://uniswap.org/whitepaper-v3.pdf)
- [Uniswap V3 源码](https://github.com/Uniswap/v3-core)
- [Uniswap V3 详解（中文）](https://paco0x.org/uniswap-v3-1/)

### Move 语言
- [Sui 官方文档](https://docs.sui.io/)
- [Move 语言书](https://move-book.com/)

### 数学原理
- [Solidity 对数计算](https://paco0x.org/logarithm-in-solidity/)
- [定点数运算](https://en.wikipedia.org/wiki/Fixed-point_arithmetic)

## ⚠️ 免责声明

这是一个学习项目，仅用于教育目的。代码未经过完整的安全审计，请勿在生产环境中使用。


---

⭐ 如果这个项目对你有帮助，请给个 Star！
