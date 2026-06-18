#!/bin/sh

# Ссылка на оригинальный патчер от 4n0n4
PATCHER_URL="https://raw.githubusercontent.com/4n0n4/mt7981_factory_txpwr_patch/refs/heads/main/txpwr.sh"
PATCHER_PATH="/tmp/txpwr.sh"
DUMP_FILE="/tmp/factory_dump.bin"
BACKUP_FILE="/tmp/factory_original_backup.bin"

echo "=== Автоматический буст Wi-Fi на максимум ==="

# 1. Скачиваем оригинальный скрипт-патчер
echo "Скачиваю оригинальный патчер..."
# Добавили игнорирование сертификатов, так как на роутерах часто сбито время после перезагрузки
wget --no-check-certificate -O "$PATCHER_PATH" "$PATCHER_URL"

if [ $? -ne 0 ] || [ ! -s "$PATCHER_PATH" ]; then
    echo "Ошибка: Не получилось скачать оригинальный файл txpwr.sh!"
    echo "Возможные причины:"
    echo "1. На роутере нет интернета."
    echo "2. Не установлен пакет для поддержки HTTPS (нужен libustream-ssl)."
    echo "3. Сильно сбито системное время устройства."
    exit 1
fi

chmod +x "$PATCHER_PATH"
echo "Оригинальный скрипт успешно скачан."

# 2. Ищем раздел Factory в памяти роутера
MTD_DEV=$(grep -i '"Factory"' /proc/mtd | cut -d: -f1)
if [ -z "$MTD_DEV" ]; then
    echo "Ошибка: Раздел Factory не найден в системе роутера!"
    exit 1
fi
echo "Нашли целевой раздел памяти: /dev/$MTD_DEV"

# 3. Делаем безопасный заводской бэкап
echo "Сохраняю оригинальный бэкап в $BACKUP_FILE..."
dd if="/dev/$MTD_DEV" of="$BACKUP_FILE" bs=1M 2>/dev/null

# Копируем файл для проведения модификации
cp "$BACKUP_FILE" "$DUMP_FILE"

# 4. Запускаем патч с самым мощным пресетом wr3000p
echo "Применяю самый мощный профиль wr3000p на максимум..."
# Отправляем букву 'y', чтобы скрипт автоматически со всем согласился
echo "y" | sh "$PATCHER_PATH" -f "$DUMP_FILE" -p wr3000p -b all -L ru

# 5. Зашиваем прокачанный файл обратно в чип памяти
echo "Записываю измененный Factory обратно в роутер..."
mtd write "$DUMP_FILE" Factory

if [ $? -eq 0 ]; then
    echo "==========================================="
    echo "=== ВСЁ ПРОШЛО УСПЕШНО! ==="
    echo "Максимальная мощность успешно прошита."
    echo "Перезагружаю роутер для активации настроек..."
    echo "==========================================="
    sleep 3
    reboot
else
    echo "Блин, что-то пошло не так при финальной записи в память роутера!"
    exit 1
fi
