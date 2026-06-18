#!/bin/sh

# Ссылка на оригинальный патчер из твоего файла
PATCHER_URL="https://raw.githubusercontent.com/4n0n4/mt7981_factory_txpwr_patch/refs/heads/main/txpwr.sh"
PATCHER_PATH="/tmp/txpwr.sh"
DUMP_FILE="/tmp/factory_dump.bin"
BACKUP_FILE="/tmp/factory_original_backup.bin"

echo "=== Накатываем сбалансированный максимум по частотам ==="

# 1. Скачиваем оригинальный скрипт
echo "Скачиваю оригинальный скрипт..."
wget --no-check-certificate -O "$PATCHER_PATH" "$PATCHER_URL"

if [ $? -ne 0 ] || [ ! -s "$PATCHER_PATH" ]; then
    echo "Ошибка: Не получилось скачать txpwr.sh!"
    exit 1
fi

# 2. Инжектим наш пресет прямо в начало файла (чтобы скрипт его точно прочитал)
echo "Добавляем пресет custom_max со стабильными максимумами..."
{
    echo 'preset_custom_max_2g="29 29 29 29"'
    echo 'preset_custom_max_5g="29 29 29 29 29 29 29 29 29 29 29 29 29 29 29 29 29 29 29 29"'
    echo 'preset_custom_max_6g="24 24 24 24 24 24 24 24 24 24 24 24 24 24 24 24 24 24 24 24 24 24 24 24 24 24 24 24 24 24 24 24"'
    cat "$PATCHER_PATH"
} > /tmp/txpwr_mod.sh

mv /tmp/txpwr_mod.sh "$PATCHER_PATH"
chmod +x "$PATCHER_PATH"

# 3. Ищем раздел Factory в памяти
MTD_DEV=$(grep -i '"Factory"' /proc/mtd | cut -d: -f1)
if [ -z "$MTD_DEV" ]; then
    echo "Ошибка: Раздел Factory не найден!"
    exit 1
fi

# 4. Делаем бэкап и копию для работы
echo "Сохраняю оригинальный бэкап в $BACKUP_FILE..."
dd if="/dev/$MTD_DEV" of="$BACKUP_FILE" bs=1M 2>/dev/null
cp "$BACKUP_FILE" "$DUMP_FILE"

# 5. Запускаем патч с нашим новым пресетом
echo "Применяю профиль custom_max..."
echo "y" | sh "$PATCHER_PATH" -f "$DUMP_FILE" -p custom_max -b all -L ru

# 6. Ставим mtd-rw для обхода защиты записи
echo "Снимаю защиту записи с чипа памяти..."
if command -v apk >/dev/null 2>&1; then
    apk update && apk add kmod-mtd-rw
elif command -v opkg >/dev/null 2>&1; then
    opkg update && opkg install kmod-mtd-rw
fi

insmod mtd-rw i_want_a_brick=1 2>/dev/null

# 7. Зашиваем измененный дамп обратно в роутер
echo "Записываю обновленный Factory обратно в память..."
mtd write "$DUMP_FILE" Factory

if [ $? -eq 0 ]; then
    echo "Выставляю регион Панама (PA) и открываю каналы..."
    
    uci set wireless.radio0.country='PA'
    uci set wireless.radio1.country='PA'
    
    uci set wireless.radio1.channel='auto'
    uci set wireless.radio1.channels='36 40 44 48 149 153 157 161'
    
    uci commit wireless
    wifi reload

    echo "==========================================="
    echo "Все готово! Роутер уходит на перезагрузку."
    echo "==========================================="
    sleep 2
    reboot
else
    echo "Что-то пошло не так при финальной записи в память!"
    exit 1
fi
