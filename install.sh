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

echo -e "${BLUE}=== Менеджер ядер (Arch & Ubuntu/Debian) ===${NC}"

# 0. Определение ОС и пакетного менеджера
if command -v pacman &> /dev/null; then
    OS_TYPE="arch"
    echo -e "Обнаружена система: ${GREEN}Arch Linux (pacman)${NC}"
elif command -v dpkg &> /dev/null; then
    OS_TYPE="debian"
    echo -e "Обнаружена система: ${GREEN}Ubuntu/Debian (dpkg)${NC}"
else
    echo -e "${RED}Ошибка: Не поддерживаемый пакетный менеджер (pacman или dpkg не найдены).${NC}"
    exit 1
fi

# 1. Проверка папки
if [ ! -d "$EXPORT_DIR" ]; then
    echo -e "${RED}Ошибка: Папка $EXPORT_DIR не найдена.${NC}"
    echo "Сначала соберите и экспортируйте хотя бы одно ядро."
    exit 1
fi

cd "$EXPORT_DIR" || exit 1

# 2. Поиск пакетов ядер в зависимости от ОС
if [ "$OS_TYPE" == "arch" ]; then
    # Ищем файлы Arch (.pkg.tar.zst), исключая headers и debug
    mapfile -t KERNELS < <(find . -maxdepth 1 -type f -name "*.pkg.tar.zst" ! -name "*-headers-*" ! -name "*-debug-*" | sort -V -r)
elif [ "$OS_TYPE" == "debian" ]; then
    # Ищем файлы Debian/Ubuntu (.deb), начинающиеся с linux-image
    mapfile -t KERNELS < <(find . -maxdepth 1 -type f -name "linux-image-*.deb" ! -name "*-dbg_*" | sort -V -r)
fi

if [ ${#KERNELS[@]} -eq 0 ]; then
    echo -e "${YELLOW}В папке $EXPORT_DIR нет собранных ядер для вашей ОС.${NC}"
    exit 1
fi

echo -e "\nДоступные версии (в $EXPORT_DIR):"
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

if [[ ! "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] ||[ "$choice" -gt "${#KERNELS[@]}" ]; then
    if [ "$choice" -eq 0 ]; then exit 0; fi
    echo -e "${RED}Неверный выбор.${NC}"
    exit 1
fi

# Получаем имя файла выбранного ядра
kernel_pkg="${KERNELS[$((choice-1))]}"
kernel_pkg_clean="${kernel_pkg#./}"

echo -e "\nВыбрано ядро: ${GREEN}$kernel_pkg_clean${NC}"

# 5. Автопоиск Headers
INSTALL_LIST=("$kernel_pkg_clean")
header_pkg=""

if [ "$OS_TYPE" == "arch" ]; then
    # Логика для Arch: извлекаем версию и ищем файл с "-headers-"
    version_part=$(echo "$kernel_pkg_clean" | sed -E 's/^[a-zA-Z0-9_-]+-([0-9]+\.[0-9]+\.[0-9]+.*)-x86_64.*/\1/')
    header_pkg=$(find . -maxdepth 1 -type f -name "*-headers-*${version_part}*" | head -n 1)
elif [ "$OS_TYPE" == "debian" ]; then
    # Логика для Debian/Ubuntu: заменяем префикс linux-image на linux-headers
    expected_header_name="${kernel_pkg_clean/linux-image-/linux-headers-}"
    if [ -f "$expected_header_name" ]; then
        header_pkg="./$expected_header_name"
    fi
fi

if [ -n "$header_pkg" ]; then
    header_pkg_clean="${header_pkg#./}"
    echo -e "Найдены заголовки: ${GREEN}$header_pkg_clean${NC}"
    INSTALL_LIST+=("$header_pkg_clean")
else
    echo -e "${YELLOW}Внимание: Пакет headers для этой версии не найден.${NC}"
    echo "Если вам нужны модули (Nvidia/VirtualBox/DKMS), они не соберутся."
fi

# Формируем команду установки
if [ "$OS_TYPE" == "arch" ]; then
    INSTALL_CMD="sudo pacman -U ${INSTALL_LIST[*]} --overwrite='*'"
elif [ "$OS_TYPE" == "debian" ]; then
    INSTALL_CMD="sudo dpkg -i ${INSTALL_LIST[*]}"
fi

# 6. Подтверждение и Установка
echo ""
echo "Будет выполнена команда:"
echo -e "${BLUE}$INSTALL_CMD${NC}"
echo ""

read -p "Начать установку? (y/N): " confirm
if [[ "$confirm" =~ ^[Yy]$ ]]; then

    # Выполнение команды
    eval "$INSTALL_CMD"

    # Для Ubuntu/Debian после dpkg -i обычно нужно обновить grub и initramfs
    # (хотя скрипты пакета linux-image делают это сами, лишним не будет)
    if [ "$OS_TYPE" == "debian" ]; then
        echo -e "${YELLOW}Выполняю обновление загрузчика (update-grub)...${NC}"
        sudo update-grub
    fi

    echo -e "\n${GREEN}Установка завершена!${NC}"

    # Напоминание про загрузчик
    echo "---------------------------------------------------"
    echo "Не забудьте проверить загрузчик, если это не произошло автоматически:"
    if [ "$OS_TYPE" == "arch" ]; then
        echo " -> GRUB:         sudo grub-mkconfig -o /boot/grub/grub.cfg"
        echo " -> Systemd-boot: Проверьте файлы в /boot/loader/entries/"
    elif [ "$OS_TYPE" == "debian" ]; then
        echo " -> GRUB:         sudo update-grub"
    fi
    echo "---------------------------------------------------"
else
    echo "Отмена."
fi
