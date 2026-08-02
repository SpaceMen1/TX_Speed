#!/bin/sh

PATCHER_URL="https://raw.githubusercontent.com/4n0n4/mt7981_factory_txpwr_patch/refs/heads/main/txpwr.sh"
PATCHER_PATH="/tmp/txpwr.sh"
DUMP_FILE="/tmp/factory_dump.bin"
BACKUP_FILE="/tmp/factory_original_backup.bin"

echo "=== Финальный боевой разгон (MT7981 / OpenWrt 25.12) ==="

# 1. Скачивание оригинального патчера
echo "[1/7] Скачиваю скрипт-патчер..."
wget --no-check-certificate -O "$PATCHER_PATH" "$PATCHER_URL"

if [ $? -ne 0 ] || [ ! -s "$PATCHER_PATH" ]; then
    echo "Ошибка: Не удалось скачать txpwr.sh! Проверь доступ к сети."
    exit 1
fi

chmod +x "$PATCHER_PATH"

# 2. Модификация профиля wr3000p под идеальные 29 dBm без перекосов
echo "[2/7] Калибруем пресет wr3000p под ровные максимумы..."
sed -i 's/preset_wr3000p_2g=".*"/preset_wr3000p_2g="29 29 29 29"/' "$PATCHER_PATH"

P5G="29 29 29 29 29 29 29 29 29 29 29 29 29 29 29 29 29 29 29 29"
sed -i "s/preset_wr3000p_5g=\".*\"/preset_wr3000p_5g=\"$P5G\"/" "$PATCHER_PATH"

# 3. Поиск и бэкап MTD раздела
MTD_DEV=$(grep -i '"Factory"' /proc/mtd | cut -d: -f1)
if [ -z "$MTD_DEV" ]; then
    echo "Ошибка: Раздел Factory не найден в /proc/mtd!"
    exit 1
fi

echo "[3/7] Создаю резервную копию Factory в $BACKUP_FILE..."
dd if="/dev/$MTD_DEV" of="$BACKUP_FILE" bs=1M 2>/dev/null

if [ ! -s "$BACKUP_FILE" ]; then
    echo "Ошибка: Не удалось сделать бэкап раздела Factory!"
    exit 1
fi

cp "$BACKUP_FILE" "$DUMP_FILE"

# 4. Пропатчивание дампа
echo "[4/7] Применяю сбалансированные калибровки к дампу..."
echo "y" | sh "$PATCHER_PATH" -f "$DUMP_FILE" -p wr3000p -b all -L ru

if [ $? -ne 0 ]; then
    echo "Ошибка во время выполнения патча! Запись отменена."
    exit 1
fi

# 5. Снятие защиты записи (поддержка apk в OpenWrt 25.12 и opkg)
echo "[5/7] Разблокирую запись в флеш-память..."
if command -v apk >/dev/null 2>&1; then
    apk update && apk add kmod-mtd-rw
elif command -v opkg >/dev/null 2>&1; then
    opkg update && opkg install kmod-mtd-rw
fi

modprobe mtd-rw i_want_a_brick=1 2>/dev/null || insmod mtd-rw i_want_a_brick=1 2>/dev/null

# 6. Прошивка патченного дампа в чип
echo "[6/7] Записываю прошитый Factory в память роутера..."
mtd write "$DUMP_FILE" Factory

if [ $? -ne 0 ]; then
    echo "КРИТИЧЕСКАЯ ОШИБКА при записи в MTD! Не перезагружай роутер!"
    exit 1
fi

# 7. Комплексная оптимизация OpenWrt (UCI)
echo "[7/7] Накатываем ультимативный тюнинг сети и Wi-Fi..."

# Снятие региональных рамок (Панама)
uci set wireless.radio0.country='PA'
uci set wireless.radio1.country='PA'

# 5 ГГц: 160 МГц + автовыбор самого свободного канала из безопасного блока
uci set wireless.radio1.htmode='HE160'
uci set wireless.radio1.channel='auto'
uci set wireless.radio1.channels='36 40 44 48'

# Защита от соседских помех (BSS Coloring)
uci set wireless.radio0.he_bss_color='12'
uci set wireless.radio1.he_bss_color='12'

# Фокусировка сигнала на устройствах (Beamforming)
uci set wireless.radio0.tx_beamforming='1'
uci set wireless.radio0.rx_beamforming='1'
uci set wireless.radio1.tx_beamforming='1'
uci set wireless.radio1.rx_beamforming='1'
uci set wireless.radio1.mu_beamforming='1'

# Защита от медленных клиентов (Airtime Fairness)
uci set wireless.radio0.airtime_fairness='1'
uci set wireless.radio1.airtime_fairness='1'

# Железное ускорение WED и распределение нагрузки по ядрам
uci set firewall.@defaults[0].flow_offloading='1'
uci set firewall.@defaults[0].flow_offloading_hw='1'
uci set network.globals.packet_steering='1'

# Оптимизация интерфейсов (Multicast2Unicast + Быстрый роуминг 802.11k/v)
for iface in $(uci show wireless | grep '=wifi-iface' | cut -d'.' -f2 | cut -d'=' -f1); do
    uci set wireless.${iface}.multicast_to_unicast='1'
    uci set wireless.${iface}.ieee80211k='1'
    uci set wireless.${iface}.ieee80211v='1'
    uci set wireless.${iface}.bss_transition='1'
done

# Применение и сохранение всех параметров
uci commit wireless
uci commit firewall
uci commit network

echo "=========================================================="
echo " Все готово! Выжали 100% из железа и прошивки 25.12."
echo " Перезагружаю роутер..."
echo "=========================================================="
sleep 3
reboot
