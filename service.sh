#!/system/bin/sh
# ============================================================
#   Pixel Enable 5G - boot service
#
#   5G 放行由 CarrierConfig 的 carrier_nr_availabilities_int_array=[NSA(1),SA(2)]
#   决定, build props 到不了这一层。
#   注入手法参考 cxOrz/pixel_ims_module: 在 carrierconfig XML 的 </bundle> 前插入配置。
#
#   本脚本不按运营商分流: 属性与 CarrierConfig 键对国内四大运营商通用,
#   运营商代码只用于日志。好处是双卡(移动+联通/电信)不会被跳过。
# ============================================================
MODDIR=${0%/*}
LOG_FILE="$MODDIR/log.txt"

# 日志轮转: 超过 1MB 则备份
LOG_SIZE=$(stat -c %s "$LOG_FILE" 2>/dev/null)
[ -n "$LOG_SIZE" ] && [ "$LOG_SIZE" -gt 1048576 ] && mv "$LOG_FILE" "$LOG_FILE.bak"

log() { echo "$(date): $1" >> "$LOG_FILE"; }

# 防重入锁
LOCK_FILE="$MODDIR/script.lock"
if [ -f "$LOCK_FILE" ]; then
    echo "$(date): Script already running, exiting" >> "$LOG_FILE"
    exit 1
fi
touch "$LOCK_FILE"
trap 'rm -f "$LOCK_FILE"' EXIT

# 运营商代码 -> 名称 (仅日志用, 未知代码不阻塞任何流程)
carrier_name() {
    case "$1" in
        46000|46002|46004|46007|46008) echo "China Mobile" ;;
        46001|46006|46009)             echo "China Unicom" ;;
        46003|46005|46011)             echo "China Telecom" ;;
        46015)                         echo "China Broadnet" ;;
        46020)                         echo "China Tietong" ;;
        *)                             echo "" ;;
    esac
}

# ---- 1. 等待系统启动完成 ----
until [ "$(getprop sys.boot_completed)" = "1" ]; do
    sleep 1
done
log "===== Script started, boot completed ====="

# ---- 2. 解锁 5GHz/6GHz 热点 + Wi-Fi 中继 ----
cmd wifi force-country-code enabled GB && log "Wi-Fi country code forced to GB"
setprop gsm.operator.iso-country us,us
setprop gsm.sim.operator.iso-country us,us
log "SIM region spoofed (us,us)"

# ---- 3. 网络验证地址改为国内可达, 消除网络/Wi-Fi 上的感叹号 ----
# Android 靠访问 generate_204 端点判断"能否上网", 连不通谷歌就显示感叹号。
CAPTIVE_HTTP="http://connectivitycheck.gstatic.cn/generate_204"
CAPTIVE_HTTPS="https://www.google.cn/generate_204"
settings put global captive_portal_http_url "$CAPTIVE_HTTP" 2>/dev/null
settings put global captive_portal_https_url "$CAPTIVE_HTTPS" 2>/dev/null
CUR_HTTP=$(settings get global captive_portal_http_url 2>/dev/null)
CUR_HTTPS=$(settings get global captive_portal_https_url 2>/dev/null)
if [ "$CUR_HTTP" = "$CAPTIVE_HTTP" ] && [ "$CUR_HTTPS" = "$CAPTIVE_HTTPS" ]; then
    log "Captive portal URLs set (no more exclamation mark)"
else
    log "Captive portal set FAILED (http='$CUR_HTTP' https='$CUR_HTTPS')"
fi

# ---- 4. 记录运营商 (多卡时逐卡列出, 不等待, 不影响后续流程) ----
RAW_OP=$(getprop gsm.sim.operator.numeric)
case "$RAW_OP" in
    ""|","|*",,"*) RAW_OP=$(getprop gsm.operator.numeric) ;;
esac
DETECTED=""
for op in $(echo "$RAW_OP" | tr ',' ' '); do
    op=$(echo "$op" | tr -d '() ')
    [ -z "$op" ] && continue
    name=$(carrier_name "$op")
    if [ -n "$name" ]; then
        DETECTED="$DETECTED $op($name)"
    else
        DETECTED="$DETECTED $op(Unknown)"
    fi
done
if [ -n "$DETECTED" ]; then
    log "SIM operator(s):$DETECTED"
else
    log "SIM operator not readable yet (logged again after registration)"
fi

# ---- 5. VoLTE / VoWiFi 属性兜底重申 (system.prop 已设, 防止被系统重置) ----
setprop persist.dbg.volte_avail_ovr 1
setprop persist.dbg.ims_volte_enable 1
setprop persist.dbg.wfc_avail_ovr 1
setprop persist.dbg.vt_avail_ovr 0
setprop persist.radio.volte_enabled 1
setprop persist.radio.calls.on.ims 1
setprop persist.dbg.allow_ims_off 0
log "VoLTE/VoWiFi properties applied (Video Calling disabled)"

# ---- 6. CarrierConfig 注入: 5G 的真正开关 ----
# 早于电话进程初始化完成去改 XML 可能被其内存态回写覆盖, 故先等系统坐稳。
sleep 15
log "Waited 15s for telephony init"

CFG_DIR="/data/user_de/0/com.android.phone/files"
CFG_BLOCK="$MODDIR/carrierconfig_block.txt"

cat > "$CFG_BLOCK" <<'BLOCK'
<!--PIXEL_ENABLE_5G_START-->
<boolean name="carrier_volte_available_bool" value="true" />
<boolean name="editable_enhanced_4g_lte_bool" value="true" />
<boolean name="hide_enhanced_4g_lte_bool" value="false" />
<boolean name="carrier_wfc_ims_available_bool" value="true" />
<boolean name="carrier_wfc_supports_wifi_only_bool" value="true" />
<boolean name="editable_wfc_mode_bool" value="true" />
<boolean name="editable_wfc_roaming_mode_bool" value="true" />
<boolean name="carrier_supports_ss_over_ut_bool" value="true" />
<boolean name="vonr_enabled_bool" value="true" />
<boolean name="vonr_setting_visibility_bool" value="true" />
<int-array name="carrier_nr_availabilities_int_array" num="2"><item value="1" /><item value="2" /></int-array>
<int-array name="5g_nr_ssrsrp_thresholds_int_array" num="4"><item value="-128" /><item value="-118" /><item value="-108" /><item value="-98" /></int-array>
<!--PIXEL_ENABLE_5G_END-->
BLOCK

PATCHED=0
if [ -d "$CFG_DIR" ]; then
    ls "$CFG_DIR" > "$MODDIR/carrierconfig_files.txt" 2>/dev/null
    for f in "$CFG_DIR"/carrierconfig-*.xml; do
        case "$f" in *nosim*) continue ;; esac
        [ -f "$f" ] || continue
        if ! grep -q '</bundle>' "$f" 2>/dev/null; then
            log "CarrierConfig skip (no </bundle>): ${f##*/}"
            continue
        fi
        OWNER=$(stat -c '%u:%g' "$f" 2>/dev/null)
        MODE=$(stat -c '%a' "$f" 2>/dev/null)
        TMP="$f.tmppx5g"
        awk -v blockfile="$CFG_BLOCK" '
            BEGIN { while ((getline line < blockfile) > 0) blk = blk line "\n" }
            /PIXEL_ENABLE_5G_START/ { skip = 1; next }
            /PIXEL_ENABLE_5G_END/   { skip = 0; next }
            /PIXEL_CN_IMS5G_START/  { skip = 1; next }
            /PIXEL_CN_IMS5G_END/    { skip = 0; next }
            skip { next }
            /<\/bundle>/ && !done { printf "%s", blk; done = 1 }
            { print }
        ' "$f" > "$TMP" 2>/dev/null
        if [ -s "$TMP" ]; then
            [ -n "$OWNER" ] && chown "$OWNER" "$TMP" 2>/dev/null
            [ -n "$MODE" ] && chmod "$MODE" "$TMP" 2>/dev/null
            if mv "$TMP" "$f" 2>/dev/null; then
                restorecon "$f" 2>/dev/null
                PATCHED=$((PATCHED + 1))
                log "CarrierConfig patched: ${f##*/}"
            else
                rm -f "$TMP"
                log "CarrierConfig move failed: ${f##*/}"
            fi
        else
            rm -f "$TMP"
            log "CarrierConfig patch failed: ${f##*/}"
        fi
    done
else
    log "CarrierConfig dir not found: $CFG_DIR"
fi
log "CarrierConfig files patched: $PATCHED"
if [ "$PATCHED" -eq 0 ]; then
    log "!! CarrierConfig 未注入: 若目录下没有 carrierconfig-*.xml, 需先用一次 Carrier IMS(勾选持久化) 生成种子文件, 之后本模块自动接管"
fi

# ---- 7. 重启电话栈, 让 CarrierConfig 重新加载 ----
if setprop ctl.restart vendor.imsd 2>/dev/null; then
    log "Restarted vendor.imsd"
else
    log "vendor.imsd not present (normal on Pixel), fallback: restart com.android.phone"
    PHONE_PID=$(pidof com.android.phone)
    if [ -n "$PHONE_PID" ]; then
        kill $PHONE_PID && log "com.android.phone killed (system auto-restarts it)"
    else
        log "com.android.phone not running yet, rely on natural reload"
    fi
fi

if setprop ctl.restart ril-daemon 2>/dev/null; then
    log "Restarted ril-daemon"
else
    log "Failed to restart ril-daemon"
fi

# ---- 8. 后台校验 (不阻塞): IMS 注册状态 + NR 可用性 + 注册后的运营商 ----
log "Settling 20s after telephony restart..."
sleep 20
IMS_RESULT_FILE="$MODDIR/ims_check.txt"
NR_RESULT_FILE="$MODDIR/nr_availability.txt"
rm -f "$IMS_RESULT_FILE" "$NR_RESULT_FILE"
( timeout -k 5 15 dumpsys telephony.registry 2>/dev/null | grep -i "imsregistered" > "$IMS_RESULT_FILE"; \
  echo "$(date): IMS check finished -> $(head -1 "$IMS_RESULT_FILE" 2>/dev/null)" >> "$LOG_FILE" ) &
( timeout -k 5 15 dumpsys carrier_config 2>/dev/null | grep -i "nr_availab" > "$NR_RESULT_FILE"; \
  echo "$(date): NR availability check finished -> $(head -1 "$NR_RESULT_FILE" 2>/dev/null)" >> "$LOG_FILE" ) &
( FINAL_OP=$(getprop gsm.sim.operator.numeric); \
  echo "$(date): SIM operator after registration: '$FINAL_OP'" >> "$LOG_FILE" ) &
log "Checks dispatched to background"
sleep 10
if [ -s "$IMS_RESULT_FILE" ]; then
    if grep -q "true" "$IMS_RESULT_FILE"; then
        log "IMS is REGISTERED"
    else
        log "IMS is NOT registered ($(head -1 "$IMS_RESULT_FILE"))"
    fi
else
    log "IMS check still running (telephony busy); see ims_check.txt"
fi
if [ -s "$NR_RESULT_FILE" ]; then
    log "NR availability present: $(head -1 "$NR_RESULT_FILE")"
else
    log "NR availability not found yet; see nr_availability.txt"
fi

log "Script finished"
