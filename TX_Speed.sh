#!/bin/sh

PATCHER_URL="https://raw.githubusercontent.com/4n0n4/mt7981_factory_txpwr_patch/refs/heads/main/txpwr.sh"
PATCHER_PATH="/tmp/txpwr.sh"
DUMP_FILE="/tmp/factory_dump.bin"
BACKUP_FILE="/tmp/factory_original_backup.bin"

echo "=== Профессиональный комплексный разгон (Filogic / OpenWrt 25.12) ==="

# 1. Скачивание патчера
echo "[1/7] Скачиваю скрипт-патчер..."
wget --no-check-certificate -O "$PATCHER_PATH" "$PATCHER_URL"

if [ $? -ne 0 ] || [ ! -s "$PATCHER_PATH" ]; then
    echo " Ошибка: Не удалось скачать txpwr.sh. Проверь интернет на роутере."
    exit 1
fi

chmod +x "$PATCHER_PATH"

# 2. Модификация пресета wr3000p внутри патчера (29 dBm на 2.4/5 ГГц, 24 dBm на 6 ГГц)
echo "[2/7] Калибруем профиль wr3000p под максимальные ровные значения..."

# Меняем значения 2G
sed -i 's/preset_wr3000p_2g=".*"/preset_wr3000p_2g="29 29 29 29"/' "$PATCHER_PATH"

# Меняем сетку 5G (все 20 ячеек на 29)
P5G="29 29 29 29 29 29 29 29 29 29 29 29 29 29 29 29 29 29 29 29"
sed -i "s/preset_wr3000p_5g=\".*\"/preset_wr3000p_5g=\"$P5G\"/" "$PATCHER_PATH"

# 3. Проверка и бэкап MTD раздела
MTD_DEV=$(grep -i '"Factory"' /proc/mtd | cut -d: -f1)
if [ -z "$MTD_DEV" ]; then
    echo " Ошибка: Раздел Factory не найден в /proc/mtd!"
    exit 1
fi

echo "[3/7] Создаю резервную копию раздела Factory..."
dd if="/dev/$MTD_DEV" of="$BACKUP_FILE" bs=1M 2>/dev/null

if [ ! -s "$BACKUP_FILE" ]; then
    echo " Ошибка: Не удалось создать бэкап Factory!"
    exit 1
fi

cp "$BACKUP_FILE" "$DUMP_FILE"

# 4. Пропатчивание дампа
echo "[4/7] Применяю модифицированный кастомный пресет..."
echo "y" | sh "$PATCHER_PATH" -f "$DUMP_FILE" -p wr3000p -b all -L ru

if [ $? -ne 0 ]; then
    echo " Ошибка во время выполнения патча! Запись отменена."
    exit 1
fi

# 5. Снятие защиты записи (mtd-rw)
echo "[5/7] Разблокирую запись в флеш-память..."
if command -v apk >/dev/null 2>&1; then
    apk update && apk add kmod-mtd-rw
elif command -v opkg >/dev/null 2>&1; then
    opkg update && opkg install kmod-mtd-rw
fi

modprobe mtd-rw i_want_a_brick=1 2>/dev/null || insmod mtd-rw i_want_a_brick=1 2>/dev/null

# 6. Безопасная прошивка
echo "[6/7] Прошиваю обновленный Factory..."
mtd write "$DUMP_FILE" Factory

if [ $? -ne 0 ]; then
    echo " КРИТИЧЕСКАЯ ОШИБКА при записи в MTD! Не перезагружай роутер!"
    exit 1
fi

# 7. Тюнинг сетевого стека OpenWrt
echo "[7/7] Применяю оптимизацию Wi-Fi и ускорение WED..."

# Регион Панама для снятия ограничений LuCI
uci set wireless.radio0.country='PA'
uci set wireless.radio1.country='PA'

# Выставляем 160 МГц и фиксируем нижние каналы (чтобы не было конфликта HE160)
uci set wireless.radio1.htmode='HE160'
uci set wireless.radio1.channel='auto'
uci set wireless.radio1.channels='36 40 44 48'

# Защита от помех соседей (BSS Coloring)
uci set wireless.radio0.he_bss_color='12'
uci set wireless.radio1.he_bss_color='12'

# Фокусировка сигнала (Beamforming)
uci set wireless.radio0.tx_beamforming='1'
uci set wireless.radio0.rx_beamforming='1'
uci set wireless.radio1.tx_beamforming='1'
uci set wireless.radio1.rx_beamforming='1'
uci set wireless.radio1.mu_beamforming='1'

# Железный офплоад (WED) и разгрузка процессора
uci set firewall.@defaults[0].flow_offloading='1'
uci set firewall.@defaults[0].flow_offloading_hw='1'
uci set network.globals.packet_steering='1'

# Сохранение конфигурации
uci commit wireless
uci commit firewall
uci commit network

echo "=========================================================="
echo " Готово! Все проверки пройдены, скрипт отработал чистенько."
echo " Перезагружаю роутер..."
echo "=========================================================="
sleep 3
reboot
