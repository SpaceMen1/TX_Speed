#!/bin/sh

PATCHER_URL="https://raw.githubusercontent.com/4n0n4/mt7981_factory_txpwr_patch/refs/heads/main/txpwr.sh"
PATCHER_PATH="/tmp/txpwr.sh"
DUMP_FILE="/tmp/factory_dump.bin"
BACKUP_FILE="/tmp/factory_original_backup.bin"

echo "=== Модификация Factory: Максимальная мощность 29 HEX ==="

# 1. Скачивание патчера
echo "[1/5] Скачиваю скрипт-патчер..."
wget --no-check-certificate -O "$PATCHER_PATH" "$PATCHER_URL"

if [ $? -ne 0 ] || [ ! -s "$PATCHER_PATH" ]; then
    echo "Ошибка: Не удалось скачать txpwr.sh! Проверь доступ к сети."
    exit 1
fi

chmod +x "$PATCHER_PATH"

# 2. Фикс синтаксиса и безопасное внедрение 29 HEX
echo "[2/5] Внедряем максимальные значения мощности (29 HEX)..."

# Гарантированный фикс printf для BusyBox
sed -i 's/printf.*\\$oct.*/    printf "%b" "\\$oct" >> "$file"/' "$PATCHER_PATH"

# Безопасная вставка перед MAIN с поддержкой всех версий BusyBox sed
sed -i '/# =================== MAIN ===================/i\preset_rax3000me_2g="29 29 29 29"' "$PATCHER_PATH"
sed -i '/# =================== MAIN ===================/i\preset_rax3000me_5g="29 29 29 29 29 29 29 29 29 29 29 29 29 29 29 29 29 29 29 29"' "$PATCHER_PATH"

# 3. Бэкап Factory
MTD_DEV=$(grep -i '"factory"' /proc/mtd | head -n1 | cut -d: -f1)
MTD_NAME=$(grep -i '"factory"' /proc/mtd | head -n1 | cut -d'"' -f2)

if [ -z "$MTD_DEV" ]; then
    echo "Ошибка: Раздел Factory не найден в /proc/mtd!"
    exit 1
fi

[ -z "$MTD_NAME" ] && MTD_NAME="Factory"

echo "[3/5] Создаю бэкап Factory ($MTD_DEV) в $BACKUP_FILE..."
dd if="/dev/$MTD_DEV" of="$BACKUP_FILE" bs=64k 2>/dev/null

if [ ! -s "$BACKUP_FILE" ]; then
    echo "Ошибка: Не удалось сделать бэкап раздела Factory!"
    exit 1
fi

cp "$BACKUP_FILE" "$DUMP_FILE"

# 4. Пропатчивание дампа
echo "[4/5] Применяем максимальные калибровки к дампу..."
echo "y" | sh "$PATCHER_PATH" -f "$DUMP_FILE" -p rax3000me -b all -L ru

if [ $? -ne 0 ]; then
    echo "Ошибка во время патчинга дампа! Запись отменена."
    exit 1
fi

# 5. Разблокировка MTD и прошивка
echo "[5/5] Разблокируем флеш-память и записываем пропатченный Factory..."
if command -v apk >/dev/null 2>&1; then
    apk update >/dev/null 2>&1
    apk add kmod-mtd-rw >/dev/null 2>&1
elif command -v opkg >/dev/null 2>&1; then
    opkg update >/dev/null 2>&1
    opkg install kmod-mtd-rw >/dev/null 2>&1
fi

modprobe mtd-rw i_want_a_brick=1 2>/dev/null || insmod mtd-rw i_want_a_brick=1 2>/dev/null
mtd unlock "$MTD_NAME" 2>/dev/null || mtd unlock "$MTD_DEV" 2>/dev/null

mtd write "$DUMP_FILE" "$MTD_NAME" 2>/dev/null || \
mtd write "$DUMP_FILE" "$MTD_DEV" 2>/dev/null || \
dd if="$DUMP_FILE" of="/dev/mtdblock${MTD_DEV#mtd}" bs=64k 2>/dev/null

if [ $? -ne 0 ]; then
    echo "КРИТИЧЕСКАЯ ОШИБКА при записи в MTD!"
    exit 1
fi

echo "=========================================================="
echo " Калибровки мощности (29 HEX) успешно записаны!"
echo " Перезагрузка через 3 секунды..."
echo "=========================================================="
sleep 3
reboot
