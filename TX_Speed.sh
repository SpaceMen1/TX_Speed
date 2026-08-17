#!/bin/sh

PATCHER_URL="https://raw.githubusercontent.com/4n0n4/mt7981_factory_txpwr_patch/refs/heads/main/txpwr.sh"
PATCHER_PATH="/tmp/txpwr.sh"
DUMP_FILE="/tmp/factory_dump.bin"
BACKUP_FILE="/tmp/factory_original_backup.bin"

echo "=== Модификация Factory: Максимальная мощность 29 HEX ==="

echo "[1/5] Скачиваю скрипт-патчер..."
wget --no-check-certificate -O "$PATCHER_PATH" "$PATCHER_URL"

if [ $? -ne 0 ] || [ ! -s "$PATCHER_PATH" ]; then
    echo "Ошибка: Не удалось скачать txpwr.sh!"
    exit 1
fi

chmod +x "$PATCHER_PATH"

echo "[2/5] Внедряем правильную бинарную запись 29 HEX..."
sed -i 's/printf "\\$oct"/printf "%b" "\\\\$oct"/' "$PATCHER_PATH"
sed -i '/# =================== MAIN ===================/i\preset_rax3000me_2g="29 29 29 29"' "$PATCHER_PATH"
sed -i '/# =================== MAIN ===================/i\preset_rax3000me_5g="29 29 29 29 29 29 29 29 29 29 29 29 29 29 29 29 29 29 29 29"' "$PATCHER_PATH"

MTD_DEV=$(grep -i '"factory"' /proc/mtd | head -n1 | cut -d: -f1)
MTD_NAME=$(grep -i '"factory"' /proc/mtd | head -n1 | cut -d'"' -f2)

if [ -z "$MTD_DEV" ]; then
    echo "Ошибка: Раздел Factory не найден!"
    exit 1
fi

[ -z "$MTD_NAME" ] && MTD_NAME="Factory"

echo "[3/5] Создаю резервную копию Factory ($MTD_DEV)..."
dd if="/dev/$MTD_DEV" of="$BACKUP_FILE" bs=64k 2>/dev/null
cp "$BACKUP_FILE" "$DUMP_FILE"

echo "[4/5] Применяем бинарные калибровки..."
echo "y" | sh "$PATCHER_PATH" -f "$DUMP_FILE" -p rax3000me -b all -L ru

echo "[5/5] Подготавливаем MTD и прошиваем Factory..."

if command -v apk >/dev/null 2>&1; then
    if ! apk info -e kmod-mtd-rw >/dev/null 2>&1; then
        echo "Устанавливаем драйвер доступа kmod-mtd-rw через apk..."
        apk update && apk add kmod-mtd-rw
    fi
elif command -v opkg >/dev/null 2>&1; then
    if ! opkg list-installed | grep -q "kmod-mtd-rw"; then
        echo "Устанавливаем драйвер доступа kmod-mtd-rw через opkg..."
        opkg update && opkg install kmod-mtd-rw
    fi
fi

modprobe mtd-rw i_want_a_brick=1 2>/dev/null || insmod mtd-rw i_want_a_brick=1 2>/dev/null
mtd unlock "$MTD_NAME" 2>/dev/null || mtd unlock "$MTD_DEV" 2>/dev/null

mtd write "$DUMP_FILE" "$MTD_NAME" 2>/dev/null || \
mtd write "$DUMP_FILE" "$MTD_DEV" 2>/dev/null || \
dd if="$DUMP_FILE" of="/dev/mtdblock${MTD_DEV#mtd}" bs=64k 2>/dev/null

if [ $? -eq 0 ]; then
    echo "=========================================================="
    echo " Успех! В Factory записаны чистые байты 29 HEX (0x29)."
    echo "=== Проверка текущей мощности Wi-Fi ==="
    iw dev | awk '/Interface/ {iface=$2} /txpower/ {print "Интерфейс " iface " -> " $2 " " $3}'
    echo "=========================================================="
else
    echo "Ошибка записи! Перезагрузи роутер и запусти скрипт заново."
    exit 1
fi
