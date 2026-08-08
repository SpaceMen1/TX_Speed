#!/bin/sh

PATCHER_URL="https://raw.githubusercontent.com/4n0n4/mt7981_factory_txpwr_patch/refs/heads/main/txpwr.sh"
PATCHER_PATH="/tmp/txpwr.sh"
DUMP_FILE="/tmp/factory_dump.bin"
BACKUP_FILE="/tmp/factory_original_backup.bin"

echo "=== Максимальный разгон RAX3000M / RAX3000ME (MT7981 / OpenWrt 25.12) ==="

# 1. Скачивание патчера
echo "[1/7] Скачиваю скрипт-патчер..."
wget --no-check-certificate -O "$PATCHER_PATH" "$PATCHER_URL"

if [ $? -ne 0 ] || [ ! -s "$PATCHER_PATH" ]; then
    echo "Ошибка: Не удалось скачать txpwr.sh! Проверь доступ к сети."
    exit 1
fi

chmod +x "$PATCHER_PATH"

# 2. Исправление синтаксиса и внедрение 29 HEX строго перед вызовом MAIN
echo "[2/7] Внедряем максимальные значения (29 HEX) перед выполнением патчера..."

# Исправление вылета printf в txpwr.sh
sed -i 's/printf "\\$oct"/printf "%b" "\\$oct"/' "$PATCHER_PATH"

# Вставка новых значений перед блоком MAIN
sed -i '/# =================== MAIN ===================/i preset_rax3000me_2g="29 29 29 29"' "$PATCHER_PATH"
sed -i '/# =================== MAIN ===================/i preset_rax3000me_5g="29 29 29 29 29 29 29 29 29 29 29 29 29 29 29 29 29 29 29 29"' "$PATCHER_PATH"

# 3. Поиск и бэкап MTD раздела Factory
MTD_NAME=$(grep -i '"factory"' /proc/mtd | head -n1 | cut -d'"' -f2)
MTD_DEV=$(grep -i '"factory"' /proc/mtd | head -n1 | cut -d: -f1)

if [ -z "$MTD_DEV" ]; then
    echo "Ошибка: Раздел Factory не найден в /proc/mtd!"
    exit 1
fi

[ -z "$MTD_NAME" ] && MTD_NAME="Factory"

echo "[3/7] Создаю резервную копию Factory ($MTD_DEV / $MTD_NAME) в $BACKUP_FILE..."
dd if="/dev/$MTD_DEV" of="$BACKUP_FILE" bs=64k 2>/dev/null

if [ ! -s "$BACKUP_FILE" ]; then
    echo "Ошибка: Не удалось сделать бэкап раздела Factory!"
    exit 1
fi

cp "$BACKUP_FILE" "$DUMP_FILE"

# 4. Пропатчивание дампа пресетом rax3000me
echo "[4/7] Применяем калибровки к дампу..."
echo "y" | sh "$PATCHER_PATH" -f "$DUMP_FILE" -p rax3000me -b all -L ru

if [ $? -ne 0 ]; then
    echo "Ошибка во время выполнения патча! Запись отменена."
    exit 1
fi

# 5. Снятие защиты записи
echo "[5/7] Разблокирую запись во флеш-память..."
if command -v apk >/dev/null 2>&1; then
    apk update >/dev/null 2>&1 && apk add kmod-mtd-rw >/dev/null 2>&1
elif command -v opkg >/dev/null 2>&1; then
    opkg update >/dev/null 2>&1 && opkg install kmod-mtd-rw >/dev/null 2>&1
fi

# Загрузка модуля и разблокировка MTD
modprobe mtd-rw i_want_a_brick=1 2>/dev/null || insmod mtd-rw i_want_a_brick=1 2>/dev/null
mtd unlock "$MTD_NAME" 2>/dev/null || mtd unlock "$MTD_DEV" 2>/dev/null

# 6. Прошивка патченного дампа в чип (каскадная запись для предотвращения ошибок)
echo "[6/7] Записываю пропатченный Factory в память..."

mtd write "$DUMP_FILE" "$MTD_NAME" 2>/dev/null || \
mtd write "$DUMP_FILE" "$MTD_DEV" 2>/dev/null || \
dd if="$DUMP_FILE" of="/dev/mtdblock${MTD_DEV#mtd}" bs=64k 2>/dev/null

if [ $? -ne 0 ]; then
    echo "КРИТИЧЕСКАЯ ОШИБКА при записи в MTD!"
    exit 1
fi

# 7. Тюнинг сети и Wi-Fi (UCI)
echo "[7/7] Настраиваем Wi-Fi (80 МГц) и ускорение..."

# Регион Панама
uci set wireless.radio0.country='PA'
uci set wireless.radio1.country='PA'

# 2.4 ГГц
uci set wireless.radio0.channel='auto'

# 5 ГГц: HE80 + канал 36
uci set wireless.radio1.htmode='HE80'
uci set wireless.radio1.channel='36'

# BSS Coloring
uci set wireless.radio0.he_bss_color='12'
uci set wireless.radio1.he_bss_color='12'

# Beamforming
uci set wireless.radio0.tx_beamforming='1'
uci set wireless.radio0.rx_beamforming='1'
uci set wireless.radio1.tx_beamforming='1'
uci set wireless.radio1.rx_beamforming='1'
uci set wireless.radio1.mu_beamforming='1'

# Airtime Fairness
uci set wireless.radio0.airtime_fairness='1'
uci set wireless.radio1.airtime_fairness='1'

# Ускорение сети
uci set firewall.@defaults[0].flow_offloading='1'
uci set firewall.@defaults[0].flow_offloading_hw='1'
uci set network.globals.packet_steering='1'

# Оптимизация клиентов
for iface in $(uci show wireless | grep '=wifi-iface' | cut -d'.' -f2 | cut -d'=' -f1); do
    uci set wireless.${iface}.multicast_to_unicast='1'
    uci set wireless.${iface}.ieee80211k='1'
    uci set wireless.${iface}.ieee80211v='1'
    uci set wireless.${iface}.bss_transition='1'
done

# Применение конфигурации
uci commit wireless
uci commit firewall
uci commit network

echo "=========================================================="
echo " Все готово! Значения 29 HEX успешно прописаны в Factory."
echo " Перезагрузка через 3 секунды..."
echo "=========================================================="
sleep 3
reboot
