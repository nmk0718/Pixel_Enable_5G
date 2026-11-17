#!/system/bin/sh
# ============================================================
# 说明: persist.* 属性一旦设置会残留在 /data/property 中,
#       普通卸载不会清除。本脚本把它们和体温计配置一起清理干净。
# ============================================================

# 清理本模块写入的 persist 属性 (不存在则跳过)
for p in \
    persist.dbg.volte_avail_ovr \
    persist.dbg.ims_volte_enable \
    persist.dbg.vt_avail_ovr \
    persist.dbg.wfc_avail_ovr \
    persist.dbg.allow_ims_off \
    persist.radio.volte_enabled \
    persist.radio.calls.on.ims \
    persist.radio.nr.volte \
    persist.radio.volte.dan_support \
    persist.radio.rat_on \
    persist.radio.data_ltd_sys_ind \
    persist.radio.data_con_rprt \
    persist.radio.dynamic_sar \
    persist.radio.force_on_dc \
    persist.radio.NO_STAPA \
    persist.sys.cust.lte_config \
    persist.rcs.supported \
    persist.data.iwlan \
    persist.data.iwlan.enable \
    persist.data.iwlan.ipsec.ap \
    persist.vendor.radio.5g \
    persist.vendor.radio.5g_mode_pref \
    persist.vendor.radio.5g_mode_pref_0 \
    persist.vendor.radio.5g_mode_pref_1 \
    persist.vendor.radio.calls.on.ims \
    persist.vendor.radio.data_con_rprt \
    persist.vendor.radio.data_ltd_sys_ind \
    persist.vendor.radio.enable_temp_dds \
    persist.vendor.radio.force_ltd_sys_ind \
    persist.vendor.radio.force_on_dc \
    persist.vendor.radio.manual_nw_rej_ct \
    persist.vendor.radio.mbn_load_flag \
    persist.vendor.radio.mbn_wait_s \
    persist.vendor.radio.redir_party_num \
    ; do
    resetprop --delete "$p" 2>/dev/null
done

# 还原网络验证地址为系统默认 (否则卸载后感叹号修复依然生效)
settings delete global captive_portal_http_url 2>/dev/null
settings delete global captive_portal_https_url 2>/dev/null

# ---- 移除 CarrierConfig 注入 ----
# 开启 5G 的配置写在用户数据分区, 不在模块目录里, 卸载模块不会自动删掉。
# 注意两点:
#   1) 不靠标记判断, 按"键名"清除 —— 别的 IMS 工具(如 Carrier IMS 的持久化)
#      可能写过同样的键, 只删自己的标记会漏。
#   2) 改完必须杀掉 com.android.phone, 否则它内存里的旧配置会回写磁盘, 清理作废。
LOG=/data/adb/Pixel_Enable_5G-uninstall.log
CFG_DIR="/data/user_de/0/com.android.phone/files"
KEY_RE='carrier_nr_availabilities_int_array|5g_nr_ssrsrp_thresholds_int_array|carrier_volte_available_bool|carrier_wfc_ims_available_bool|carrier_wfc_supports_wifi_only_bool|editable_wfc_mode_bool|editable_wfc_roaming_mode_bool|carrier_supports_ss_over_ut_bool|vonr_enabled_bool|vonr_setting_visibility_bool|editable_enhanced_4g_lte_bool|hide_enhanced_4g_lte_bool'

echo "$(date): uninstall.sh started" > "$LOG"
if [ -d "$CFG_DIR" ]; then
    echo "$(date): files: $(ls "$CFG_DIR" 2>/dev/null | tr '\n' ' ')" >> "$LOG"
else
    echo "$(date): 目录不存在: $CFG_DIR" >> "$LOG"
fi

CLEANED=0
for f in "$CFG_DIR"/carrierconfig-*.xml; do
    [ -f "$f" ] || continue
    case "$f" in *nosim*) continue ;; esac
    grep -qE "$KEY_RE|PIXEL_.*_START" "$f" 2>/dev/null || continue
    OWNER=$(stat -c '%u:%g' "$f" 2>/dev/null)
    MODE=$(stat -c '%a' "$f" 2>/dev/null)
    TMP="$f.tmpclean"
    awk -v re="$KEY_RE" '
        /PIXEL_ENABLE_5G_START/ { skip = 1; next }
        /PIXEL_ENABLE_5G_END/   { skip = 0; next }
        /PIXEL_CN_IMS5G_START/  { skip = 1; next }
        /PIXEL_CN_IMS5G_END/    { skip = 0; next }
        skip { next }
        $0 ~ re { next }
        { print }
    ' "$f" > "$TMP" 2>/dev/null
    # 安全校验: 结果必须完整 (含 </bundle>), 否则保留原文件不冒险
    if [ -s "$TMP" ] && grep -q '</bundle>' "$TMP"; then
        [ -n "$OWNER" ] && chown "$OWNER" "$TMP" 2>/dev/null
        [ -n "$MODE" ] && chmod "$MODE" "$TMP" 2>/dev/null
        if mv "$TMP" "$f" 2>/dev/null; then
            restorecon "$f" 2>/dev/null
            CLEANED=$((CLEANED + 1))
            echo "$(date): cleaned ${f##*/}" >> "$LOG"
        else
            rm -f "$TMP"
            echo "$(date): move failed ${f##*/}" >> "$LOG"
        fi
    else
        rm -f "$TMP"
        echo "$(date): skipped (结构校验未过) ${f##*/}" >> "$LOG"
    fi
done
echo "$(date): cleaned files: $CLEANED" >> "$LOG"

# 让电话进程重新读盘; 不杀掉的话它会拿内存态把清理结果覆盖回去
PHONE_PID=$(pidof com.android.phone)
if [ -n "$PHONE_PID" ]; then
    echo "$(date): killing com.android.phone ($PHONE_PID)" >> "$LOG"
    kill $PHONE_PID 2>/dev/null
    i=0
    while [ $i -lt 20 ]; do
        sleep 1
        [ -n "$(pidof com.android.phone)" ] && break
        i=$((i + 1))
    done
    echo "$(date): com.android.phone restarted, pid=$(pidof com.android.phone)" >> "$LOG"
else
    echo "$(date): com.android.phone 未运行 (开机早期), 无需处理" >> "$LOG"
fi

# 复查: 电话进程重启后重新扫一遍, 确认没有被内存态写回
sleep 5
STILL=0
STILL_FILES=""
for f in "$CFG_DIR"/carrierconfig-*.xml; do
    [ -f "$f" ] || continue
    case "$f" in *nosim*) continue ;; esac
    if grep -qE "$KEY_RE" "$f" 2>/dev/null; then
        STILL=$((STILL + 1))
        STILL_FILES="$STILL_FILES ${f##*/}"
    fi
done
if [ "$STILL" -eq 0 ]; then
    echo "$(date): recheck OK, no injected keys left" >> "$LOG"
else
    echo "$(date): recheck FAILED, still present in:$STILL_FILES" >> "$LOG"
fi

# 清理体温计配置文件
THERMO="/data/data/com.google.android.apps.pixel.health/shared_prefs/thermometer.xml"
[ -f "$THERMO" ] && rm -f "$THERMO"

echo "已清理模块残留属性与体温计配置, 请重启手机 (清理详情: $LOG)" >&2
