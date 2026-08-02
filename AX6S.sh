#!/bin/sh

echo "=== Оптимизация и разгон Xiaomi Redmi AX6S (MT7622 / OpenWrt 25.12) ==="

# 1. Снятие ограничений по региону (Панама)
echo "[1/4] Выставляем регион Панама (PA) для максимальной мощности..."
uci set wireless.radio0.country='PA'
uci set wireless.radio1.country='PA'

# 2. Настройка 5 ГГц (HE80 + 4x4 MIMO)
echo "[2/4] Настраиваем 5 ГГц на честные HE80 и открываем все каналы..."
uci set wireless.radio1.htmode='HE80'
uci set wireless.radio1.channel='auto'
# Для AX6S на HE80 доступны и нижние (36-48), и верхние мощные каналы (149-161)
uci set wireless.radio1.channels='36 40 44 48 149 153 157 161'

# 3. Фишки Wi-Fi 6 и защита от помех
echo "[3/4] Включаем Beamforming, BSS Coloring и Airtime Fairness..."
uci set wireless.radio0.he_bss_color='12'
uci set wireless.radio1.he_bss_color='12'

uci set wireless.radio0.tx_beamforming='1'
uci set wireless.radio0.rx_beamforming='1'
uci set wireless.radio1.tx_beamforming='1'
uci set wireless.radio1.rx_beamforming='1'
uci set wireless.radio1.mu_beamforming='1'

uci set wireless.radio0.airtime_fairness='1'
uci set wireless.radio1.airtime_fairness='1'

# 4. Аппаратное ускорение процессора MT7622 и роуминг
echo "[4/4] Активируем аппаратный HW Offloading и быструю коммутацию..."
uci set firewall.@defaults[0].flow_offloading='1'
uci set firewall.@defaults[0].flow_offloading_hw='1'
uci set network.globals.packet_steering='1'

# Настройка интерфейсов (Multicast2Unicast + Роуминг 802.11k/v)
for iface in $(uci show wireless | grep '=wifi-iface' | cut -d'.' -f2 | cut -d'=' -f1); do
    uci set wireless.${iface}.multicast_to_unicast='1'
    uci set wireless.${iface}.ieee80211k='1'
    uci set wireless.${iface}.ieee80211v='1'
    uci set wireless.${iface}.bss_transition='1'
done

# Применение и сохранение
uci commit wireless
uci commit firewall
uci commit network

echo "=========================================================="
echo " Настройки успешно применены! AX6S переведен на максимум."
echo " Перезагружаю роутер..."
echo "=========================================================="
sleep 3
reboot
