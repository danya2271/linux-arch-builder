#!/bin/bash

# ================= НАСТРОЙКИ =================
# Папка, куда build-скрипт сохранял ядра
EXPORT_DIR="$HOME/kernel-exports"
# =============================================

# Цвета
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}=== Менеджер ядер Arch Linux ===${NC}"

# 1. Проверка папки
if [ ! -d "$EXPORT_DIR" ]; then
    echo -e "${RED}Ошибка: Папка $EXPORT_DIR не найдена.${NC}"
    echo "Сначала соберите и экспортируйте хотя бы одно ядро."
    exit 1
fi

cd "$EXPORT_DIR"

# 2. Поиск пакетов ядер (исключая headers и debug пакеты из списка)
# Ищем файлы, не содержащие "-headers" в имени, но заканчивающиеся на .pkg.tar.zst
mapfile -t KERNELS < <(find . -maxdepth 1 -type f -name "*.pkg.tar.zst" ! -name "*-headers-*" ! -name "*-debug-*" | sort -V -r)

if [ ${#KERNELS[@]} -eq 0 ]; then
    echo -e "${YELLOW}В папке $EXPORT_DIR нет собранных ядер.${NC}"
    exit 1
fi

echo "Доступные версии (в $EXPORT_DIR):"
echo "---------------------------------------------------"

# 3. Вывод списка
i=1
for kern in "${KERNELS[@]}"; do
    # Убираем ./ в начале
    filename="${kern#./}"

    # Пытаемся найти дату создания файла для удобства
    filedate=$(date -r "$filename" "+%Y-%m-%d %H:%M")

    # Пытаемся определить размер
    filesize=$(du -h "$filename" | cut -f1)

    echo -e "$i) ${GREEN}$filename${NC}"
    echo -e "   [Дата: $filedate] [Размер: $filesize]"

    ((i++))
done
echo "---------------------------------------------------"
echo "0) Выход"

# 4. Выбор пользователя
read -p "Выберите номер ядра для установки: " choice

if [[ ! "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "${#KERNELS[@]}" ]; then
    if [ "$choice" -eq 0 ]; then exit 0; fi
    echo -e "${RED}Неверный выбор.${NC}"
    exit 1
fi

# Получаем имя файла выбранного ядра
kernel_pkg="${KERNELS[$((choice-1))]}"
kernel_pkg_clean="${kernel_pkg#./}"

echo -e "\nВыбрано ядро: ${GREEN}$kernel_pkg_clean${NC}"

# 5. Автопоиск Headers
# Логика: если ядро называется linux-kknx-6.6.7-1.pkg.tar.zst
# То хедеры должны называться linux-kknx-headers-6.6.7-1.pkg.tar.zst
# Мы берем версию и релиз из имени файла ядра.

# Пытаемся найти файл, который отличается только добавлением "-headers"
# Или просто ищем файл headers с той же версией.
version_part=$(echo "$kernel_pkg_clean" | sed -E 's/^[a-zA-Z0-9_-]+-([0-9]+\.[0-9]+\.[0-9]+.*)-x86_64.*/\1/')

# Ищем любой файл, содержащий "headers" и эту версию
header_pkg=$(find . -maxdepth 1 -type f -name "*-headers-*${version_part}*" | head -n 1)

INSTALL_LIST=("$kernel_pkg_clean")

if [ -n "$header_pkg" ]; then
    header_pkg_clean="${header_pkg#./}"
    echo -e "Найдены заголовки: ${GREEN}$header_pkg_clean${NC}"
    INSTALL_LIST+=("$header_pkg_clean")
else
    echo -e "${YELLOW}Внимание: Пакет headers для этой версии не найден.${NC}"
    echo "Если вам нужны модули (Nvidia/VirtualBox), они не соберутся."
fi

# 6. Подтверждение и Установка
echo ""
echo "Будет выполнена команда:"
echo -e "${BLUE}sudo pacman -U ${INSTALL_LIST[*]}${NC}"
echo ""

read -p "Начать установку? (y/N): " confirm
if [[ "$confirm" =~ ^[Yy]$ ]]; then
    sudo pacman -U "${INSTALL_LIST[@]}" --overwrite='*'

    echo -e "\n${GREEN}Установка завершена!${NC}"

    # Напоминание про загрузчик
    echo "---------------------------------------------------"
    echo "Не забудьте обновить загрузчик, если это не произошло автоматически:"
    echo " -> GRUB:         sudo grub-mkconfig -o /boot/grub/grub.cfg"
    echo " -> Systemd-boot: Проверьте файлы в /boot/loader/entries/"
    echo "---------------------------------------------------"
else
    echo "Отмена."
fi
