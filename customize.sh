chooseport() {
  while true; do
    local event=$(/system/bin/getevent -lc 1 2>&1)
    if echo "$event" | grep -q "KEY_VOLUMEUP"; then
      return 0
    elif echo "$event" | grep -q "KEY_VOLUMEDOWN"; then
      return 1
    fi
  done
}

ask_user() {
  ui_print "- $1"
  ui_print "  音量+ = 是 / 音量- = 否"
  if chooseport; then
    ui_print "  已选择: 是"
    sleep 0.5
    ui_print " "
    return 0
  else
    ui_print "  已选择: 否"
    sleep 0.5
    ui_print " "
    return 1
  fi
}

ui_print "********************************************"
ui_print "   Pixel Enable 5G v1.0.0"
ui_print "   VoLTE / VoWiFi / 5G (SA+NSA)"
ui_print "   5&6GHz hotspot / Wi-Fi repeater / Thermometer"
ui_print "   移动 / 联通 / 电信 / 广电"
ui_print "********************************************"
ui_print " "

DEVICE_MODEL=$(getprop ro.product.device)
ui_print "- 设备代号: $DEVICE_MODEL"
ui_print " "

# ---- 机型检查 (Tensor Pixel 6~11 系列) ----
case "$DEVICE_MODEL" in
    raven|oriole|bluejay|panther|cheetah|lynx|felix|tangorpro) SUPPORTED=1 ;;
    shiba|husky|akita) SUPPORTED=1 ;;
    tokay|komodo|caiman|teak) SUPPORTED=1 ;;
    blazer|mustang|grizzly|kodiak) SUPPORTED=1 ;;
    comet) SUPPORTED=1 ;;
    rango|yogi) SUPPORTED=1 ;;
    *) SUPPORTED=0 ;;
esac

if [ "$SUPPORTED" != "1" ]; then
    ui_print "! 未识别到 Tensor Pixel 设备"
    ui_print "  继续安装可能无效甚至引起异常"
    if ! ask_user "仍然继续安装?"; then
        abort "已取消安装"
    fi
fi

# ---- 冲突检查: 已安装的其他 IMS/5G 模块 ----
CONFLICTS=""
for MOD in /data/adb/modules/* /data/adb/modules_update/*; do
    case "${MOD##*/}" in
        wzl02|BypassRegionalPixel|pixel_ims_module|pixel_cn_ims5g)
            CONFLICTS="$CONFLICTS ${MOD##*/}" ;;
    esac
done
if [ -n "$CONFLICTS" ]; then
    ui_print "! 检测到其他 IMS/5G 模块:$CONFLICTS"
    ui_print "  同时启用会互相冲突, 建议先在管理器中卸载"
    if ! ask_user "忽略警告继续安装?"; then
        abort "已取消安装, 请先移除冲突模块"
    fi
fi

# ---- 体温计: 仅 8/9/10 系列 Pro 型号 (源: RRD 上游逻辑) ----
case "$DEVICE_MODEL" in
    husky|komodo|caiman|mustang|blazer)
        THERMO_SUPPORT="true" ;;
    *)
        THERMO_SUPPORT="false"
        ui_print "- 当前机型不支持体温计, 跳过"
        ui_print " " ;;
esac

if [ "$THERMO_SUPPORT" = "true" ]; then
    APP_DATA="/data/data/com.google.android.apps.pixel.health"
    if [ -d "$APP_DATA" ]; then
        if ask_user "启用 Pixel 温度计的体温功能?"; then
            THERMO_DIR="$APP_DATA/shared_prefs"
            mkdir -p "$THERMO_DIR"
            unzip -o "$ZIPFILE" "thermometer/*" -d "$TMPDIR" >&2
            if [ -f "$TMPDIR/thermometer/thermometer.xml" ]; then
                cp -af "$TMPDIR/thermometer/thermometer.xml" "$THERMO_DIR/"
                USER_ID=$(stat -c '%u' "$APP_DATA")
                GROUP_ID=$(stat -c '%g' "$APP_DATA")
                chown -R $USER_ID:$GROUP_ID "$THERMO_DIR"
                chmod 771 "$THERMO_DIR"
                chmod 660 "$THERMO_DIR/thermometer.xml"
                chcon --reference="$APP_DATA" "$THERMO_DIR/thermometer.xml" 2>/dev/null
                am force-stop com.google.android.apps.pixel.health
                ui_print "- 体温计功能已启用"
                ui_print " "
            else
                ui_print "- 错误: ZIP 内找不到 thermometer.xml"
                ui_print " "
            fi
        fi
    else
        ui_print "- 未找到 Pixel 温度计应用, 跳过"
        ui_print " "
    fi
fi

# ---- 体温计文件不随模块常驻 (已写入应用数据, 移出模块目录) ----
rm -rf "$MODPATH/thermometer" 2>/dev/null

ui_print "- VoLTE / VoWiFi / 5G(SA+NSA) 属性: 已安装 (移动/联通/电信/广电通用)"
ui_print "- 5GHz/6GHz 热点 / Wi-Fi 中继: 重启后生效"
ui_print " "
ui_print "- 重启后请检查:"
ui_print "  1. 设置 -> SIM -> 打开 VoLTE/VoWiFi 开关"
ui_print "  2. 打开一次热点, 让新频段选项出现"
ui_print "  3. IMS 是否注册: 查看模块目录 log.txt"
ui_print " "
ui_print "- 安装完成, 请重启设备"
