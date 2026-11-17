# Pixel Enable 5G

[简体中文](README.md) | English

A KernelSU / Magisk / APatch module that unlocks VoLTE, VoWiFi, 5G (SA+NSA), 5/6 GHz hotspot, Wi-Fi repeater and the thermometer for Google Pixel in countries not officially supported by Google. Module only — no extra app needed.


## Features

- VoLTE
- VoWiFi (Wi-Fi calling)
- 5G (SA + NSA)
- 5 GHz & 6 GHz hotspot
- Wi-Fi repeater (hotspot while connected to Wi-Fi)
- Body Temperature in Pixel Thermometer (Pro models of 8-10 series only)
- No exclamation mark on network / Wi-Fi

## Requirements

- Google Pixel 6 or higher (Tensor)
- Rooted with Magisk / KernelSU / APatch

## Installation

1. Download the zip from releases and flash it in your module manager
2. Reboot
3. Settings → Network & internet → SIM → enable VoLTE and VoWiFi
4. Toggle the hotspot on once so the 5 GHz / 6 GHz options appear

## Troubleshooting

Log: `/data/adb/modules/Pixel_Enable_5G/log.txt`. Two lines matter: `CarrierConfig files patched` (must be greater than 0) and `IMS is REGISTERED`.

Still LTE? Dial `*#*#4636#*#*` → Phone information → set preferred network type to one containing **NR**.

Do not install this alongside other IMS / 5G modules — they write the same settings.

**5G survives uninstall**: the 5G settings are written to `carrierconfig-*.xml` in the user data partition, which uninstalling the module does not clear. After removing the module and rebooting, 5G still works and will not fall back to LTE. Everything else — persist props, the captive portal fix, the thermometer, 6 GHz hotspot and Wi-Fi repeater — stops working once the module is removed.

## Credits

- [WZL203](https://github.com/WZL203/Pixel-turn-on-5G-Volte-and-automatically-register-with-IMS) — IMS registration flow
- [karina-lab / SukkaLab](https://github.com/klab7/Pixel-Regional-Restrictions-Disabler) — regional restrictions, hotspot, thermometer
- [ryfineZ](https://github.com/ryfineZ/carrier-ims-for-pixel) — the CarrierConfig keys that actually unlock 5G
- [cxOrz](https://github.com/cxOrz/pixel_ims_module) — CarrierConfig injection technique