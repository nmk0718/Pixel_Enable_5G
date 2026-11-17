# Pixel Enable 5G

简体中文 | [English](README_EN.md)

一个 KernelSU / Magisk / APatch 模块，为非官方支持地区的 Google Pixel 解锁 VoLTE、VoWiFi、5G（SA+NSA）、5/6 GHz 热点、Wi-Fi 中继和体温计。纯模块，不需要额外装 App。


## 支持的功能

- VoLTE
- VoWiFi（Wi-Fi 通话）
- 5G（SA + NSA）
- 5 GHz & 6 GHz 热点
- Wi-Fi 中继（连着 Wi-Fi 时也能开热点）
- 体温计（Pixel Thermometer，仅 8/9/10 系列 Pro 机型）
- 去掉网络 / Wi-Fi 上的感叹号

## 要求

- Google Pixel 6 及以上（Tensor）
- 已 root：Magisk / KernelSU / APatch

## 安装

1. 从 release 下载 zip，在模块管理器里刷入
2. 重启手机
3. 设置 → 网络与互联网 → SIM → 打开 VoLTE、VoWiFi
4. 开一次热点，让 5 GHz / 6 GHz 选项出现

## 排查

日志在 `/data/adb/modules/Pixel_Enable_5G/log.txt`，重点看两行：`CarrierConfig files patched`（必须大于 0）和 `IMS is REGISTERED`。

还是显示 LTE？拨号盘输入 `*#*#4636#*#*` → 手机信息 → 首选网络类型选带 **NR** 的档位。

不要和其他 IMS / 5G 模块同时安装，它们改的是同一批配置。

**卸载后 5G 不会消失**：5G 配置写在 `carrierconfig-*.xml`（用户数据分区），卸载模块不会清除它，所以卸载重启后 5G 依旧可用、不会自动退回 LTE。其余项目（persist 属性、感叹号修复、体温计、6 GHz 热点、Wi-Fi 中继）都会随卸载失效。

## 致谢

- [WZL203](https://github.com/WZL203/Pixel-turn-on-5G-Volte-and-automatically-register-with-IMS) — IMS 注册流程
- [karina-lab / SukkaLab](https://github.com/klab7/Pixel-Regional-Restrictions-Disabler) — 区域限制解除、热点、体温计
- [ryfineZ](https://github.com/ryfineZ/carrier-ims-for-pixel) — 真正能解锁 5G 的 CarrierConfig 键
- [cxOrz](https://github.com/cxOrz/pixel_ims_module) — CarrierConfig 注入手法