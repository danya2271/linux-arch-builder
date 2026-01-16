#!/bin/bash

# ================= SETTINGS =================
REPO_URL="https://github.com/danya2271/linux-KKNX.git"
WORK_DIR="$HOME/kernel-dev"
SRC_DIR_NAME="linux-src"
PKG_NAME="linux-kknx"
EXPORT_DIR="$HOME/kernel-exports"
SAVED_CONFIG_NAME="saved.config"
# ============================================

set -e
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Create work directory
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"
SAVED_CONFIG_PATH="$WORK_DIR/$SAVED_CONFIG_NAME"

# --- 1. Source Check ---
echo -e "${BLUE}=== [1/7] Source Code ===${NC}"
if [ ! -d "$SRC_DIR_NAME" ]; then
    echo -e "${YELLOW}Cloning repository...${NC}"
    git clone "$REPO_URL" "$SRC_DIR_NAME"
else
    echo -e "${GREEN}Repository found.${NC}"
    read -p "Run 'git pull'? (y/N): " do_pull
    if [[ "$do_pull" =~ ^[Yy]$ ]]; then
        cd "$SRC_DIR_NAME"
        git pull
        cd ..
    fi
fi
cd "$SRC_DIR_NAME"

# --- 2. Compiler ---
echo -e "\n${BLUE}=== [2/7] Compiler ===${NC}"
echo "1) GCC (Default)"
echo "2) Clang/LLVM"
read -p "Selection (Enter=1): " compiler_choice

MAKE_FLAGS=""
COMPILER_DEPS="'bc' 'libelf' 'pahole' 'cpio' 'perl' 'tar' 'xz' 'git' 'xmlto' 'kmod' 'inetutils'"

if [ "$compiler_choice" == "2" ]; then
    echo -e "${YELLOW}Selected: CLANG${NC}"
    MAKE_FLAGS="LLVM=1 LLVM_IAS=1"
    COMPILER_DEPS="${COMPILER_DEPS} 'clang' 'llvm' 'lld'"
else
    echo -e "${GREEN}Selected: GCC${NC}"
fi

# --- Config Helper ---
set_conf() {
    sed -i "/^$1=/d" .config
    sed -i "/# $1 is not set/d" .config
    if [[ "$2" == "n" ]]; then echo "# $1 is not set" >> .config
    elif [[ "$2" == \"*\" ]]; then echo "$1=$2" >> .config
    else echo "$1=$2" >> .config; fi
}

ask_opt() {
    echo -e "\n${YELLOW}Tweak: $1${NC}"
    echo "Desc: $2"
    read -p "Enable? (y/N): " choice
    if [[ "$choice" =~ ^[Yy]$ ]]; then
        return 0
    else
        return 1
    fi
}

# --- 3. Configuration Setup ---
echo -e "\n${BLUE}=== [3/7] Configuration Setup ===${NC}"
echo "1) [SYSTEM]  Current System (/proc/config.gz)"
if [ -f "$SAVED_CONFIG_PATH" ]; then
    echo "2) [SAVED]   Saved ($SAVED_CONFIG_NAME)"
else
    echo "2) [SAVED]   Saved (No file)"
fi
echo "3) [PATH]    Specify path to .config file"
echo "4) [RESET]   Reset to Arch Default"

read -p "Selection: " config_src
if [ -f ".config" ]; then rm .config; fi

case $config_src in
    1) zcat /proc/config.gz > .config ;;
    2) [ -f "$SAVED_CONFIG_PATH" ] && cp "$SAVED_CONFIG_PATH" .config || zcat /proc/config.gz > .config ;;
    3) read -e -p "Enter path: " p; cp "${p/#\~/$HOME}" .config ;;
    4) find arch/x86/configs/ -name "*_defconfig" -printf "%f\n"; read -p "Name: " d; make $MAKE_FLAGS "$d" ;;
    *) [ -f "$SAVED_CONFIG_PATH" ] && cp "$SAVED_CONFIG_PATH" .config || zcat /proc/config.gz > .config ;;
esac
make $MAKE_FLAGS olddefconfig

set_conf CONFIG_LOCALVERSION_AUTO n

# --- 3.5 Optimization Layer ---
echo -e "\n${BLUE}=== [3.5] Optimization Layer ===${NC}"
echo "1) [Gaming]  Auto-apply best gaming tweaks"
echo "2) [Manual]  Set each flag manually with description"
echo "3) [Skip]    Keep base config as-is"
read -p "Selection: " opt_choice

if [ "$opt_choice" == "1" ] || [ "$opt_choice" == "2" ]; then
    set_conf CONFIG_EXPERT y

    # --- Preemption ---
    DESC="Reduces latency by allowing the kernel to interrupt tasks. Essential for gaming/desktop."
    if [ "$opt_choice" == "1" ] || ask_opt "Full Preemption (PREEMPT)" "$DESC"; then
        set_conf CONFIG_PREEMPT_VOLUNTARY n
        set_conf CONFIG_PREEMPT y
        set_conf CONFIG_PREEMPT_DYNAMIC y
    else
        # Default: Voluntary preemption (standard desktop)
        set_conf CONFIG_PREEMPT n
        set_conf CONFIG_PREEMPT_VOLUNTARY y
        set_conf CONFIG_PREEMPT_DYNAMIC n
    fi

    # --- HZ ---
    DESC="Sets the internal clock frequency. 1000Hz makes mouse/UI feel smoother but uses slightly more CPU."
    if [ "$opt_choice" == "1" ] || ask_opt "1000Hz Timer Frequency" "$DESC"; then
        set_conf CONFIG_HZ_250 n
        set_conf CONFIG_HZ_1000 y
        set_conf CONFIG_HZ 1000
    else
        # Default: 250Hz (balanced)
        set_conf CONFIG_HZ_1000 n
        set_conf CONFIG_HZ_250 y
        set_conf CONFIG_HZ 250
    fi

    # --- MGLRU ---
    DESC="Multi-Gen LRU. Better memory management under load, prevents micro-stutters when RAM is full."
    if [ "$opt_choice" == "1" ] || ask_opt "MGLRU" "$DESC"; then
        set_conf CONFIG_LRU_GEN y
        set_conf CONFIG_LRU_GEN_ENABLED y
    else
        # Default: Standard LRU
        set_conf CONFIG_LRU_GEN n
        set_conf CONFIG_LRU_GEN_ENABLED n
    fi

    # --- THP ---
    DESC="Transparent Hugepages. 'Madvise' is safer for gaming than 'Always' (prevents stuttering)."
    if [ "$opt_choice" == "1" ] || ask_opt "THP (Madvise mode)" "$DESC"; then
        set_conf CONFIG_TRANSPARENT_HUGEPAGE_ALWAYS n
        set_conf CONFIG_TRANSPARENT_HUGEPAGE_MADVISE y
    else
        # Default: Always (standard kernel default)
        set_conf CONFIG_TRANSPARENT_HUGEPAGE_MADVISE n
        set_conf CONFIG_TRANSPARENT_HUGEPAGE_ALWAYS y
    fi

    # --- TCP BBR ---
    DESC="Google's BBR congestion control. Improves download speeds and reduces bufferbloat/ping."
    if [ "$opt_choice" == "1" ] || ask_opt "TCP BBR" "$DESC"; then
        set_conf CONFIG_TCP_CONG_BBR y
        set_conf CONFIG_DEFAULT_TCP_CONG "bbr"
    else
        # Default: Cubic
        set_conf CONFIG_TCP_CONG_BBR n
        set_conf CONFIG_TCP_CONG_CUBIC y
        set_conf CONFIG_DEFAULT_TCP_CONG "cubic"
    fi

    make $MAKE_FLAGS olddefconfig
fi

# --- 4. No-Debug (Performance) ---
echo -e "\n${BLUE}=== [4/7] No-Debug (Performance) ===${NC}"
read -p "Disable debugging (Audit, Lock, Info)? (y/N): " kill_debug

if [[ "$kill_debug" =~ ^[Yy]$ ]]; then
    echo -e "${GREEN}Disabling debugging...${NC}"
    set_conf CONFIG_EXPERT y

    # 1. Most of debugging
    set_conf CONFIG_DEBUG_KERNEL n
    set_conf CONFIG_DEBUG_INFO n
    set_conf CONFIG_DEBUG_INFO_NONE y
    set_conf CONFIG_DEBUG_INFO_DWARF_TOOLCHAIN_DEFAULT n
    set_conf CONFIG_DEBUG_MISC n

    # 2. High-overhead options
    set_conf CONFIG_LOCK_DEBUGGING_SUPPORT n
    set_conf CONFIG_DEBUG_RT_MUTEXES n
    set_conf CONFIG_DEBUG_SPINLOCK n
    set_conf CONFIG_DEBUG_MUTEXES n
    set_conf CONFIG_PROVE_LOCKING n
    set_conf CONFIG_LOCK_STAT n

    # 3. Auditing
    set_conf CONFIG_AUDIT n
    set_conf CONFIG_AUDITSYSCALL n

    # 4. Tracing
    set_conf CONFIG_FTRACE n
    set_conf CONFIG_KPROBES n
    set_conf CONFIG_STACKTRACER n

    # 5. Memory-management
    set_conf CONFIG_SCHED_DEBUG n
    set_conf CONFIG_SCHEDSTACK_DEBUG n
    set_conf CONFIG_SLUB_DEBUG n
    set_conf CONFIG_SHRINKER_DEBUG n
    set_conf CONFIG_DEBUG_MEMORY_INIT n
    set_conf CONFIG_KFENCE n

    # 6. Different
    set_conf CONFIG_DEBUG_BUGVERBOSE n
    set_conf CONFIG_DEBUG_LIST n
    set_conf CONFIG_BUG_ON_DATA_CORRUPTION n
fi

# --- 5. Drivers & Hardware Optimization ---
echo -e "\n${BLUE}=== [5/7] Hardware & Driver Configuration ===${NC}"

# Options for an advanced kernel tailoring workflow
options=(
    "LocalModConfig: Strip unused drivers (set as Modules)"
    "LocalYesConfig: Strip unused drivers (Built-in/Monolithic)"
    "Modprobed-DB: Use database of known hardware (Safest Strip)"
    "Manual: Launch nconfig/xconfig (Advanced Tuning)"
    "Diagnostic: Check dmesg for missing firmware"
    "Skip: Keep existing configuration"
)

PS3="Please select your configuration mode (1-${#options[@]}): "

select opt in "${options[@]}"; do
    case $REPLY in
        1)
            echo -e "${YELLOW}Running localmodconfig...${NC}"
            lsmod > /tmp/lsmod.list
            yes '' | make $MAKE_FLAGS LSMOD=/tmp/lsmod.list localmodconfig
            break
            ;;
        2)
            echo -e "${YELLOW}Running localyesconfig (Monolithic build)...${NC}"
            # This turns all currently loaded modules into built-in (=y) features
            lsmod > /tmp/lsmod.list
            yes '' | make $MAKE_FLAGS LSMOD=/tmp/lsmod.list localyesconfig
            setconf CONFIG_MODVERSIONS y
            setconf CONFIG_MODULES y
            setconf CONFIG_MODULE_UNLOAD y
            break
            ;;
        3)
            if [ -f "$HOME/.config/modprobed.db" ]; then
                echo -e "${YELLOW}Applying localmodconfig using modprobed-db...${NC}"
                make $MAKE_FLAGS LSMOD="$HOME/.config/modprobed.db" localmodconfig
            else
                echo -e "${RED}Error: modprobed.db not found at $HOME/.config/modprobed.db${NC}"
                echo "Falling back to standard lsmod scan..."
                lsmod > /tmp/lsmod.list
                make $MAKE_FLAGS LSMOD=/tmp/lsmod.list localmodconfig
            fi
            break
            ;;
        4)
            # nconfig is preferred for its better search and modern UI
            echo -e "${YELLOW}Opening manual configuration...${NC}"
            make $MAKE_FLAGS nconfig || make $MAKE_FLAGS menuconfig
            break
            ;;
        5)
            echo -e "${BLUE}Scanning for firmware errors in dmesg:${NC}"
            # Filters for common missing blob errors
            dmesg | grep -iE "firmware|failed|missing" | grep -v "status 0" || echo "No missing firmware detected."
            echo -e "\nPress any key to return to the menu..."
            read -n 1
            echo -e "\n"
            ;;
        6)
            echo "Skipping driver tailoring."
            break
            ;;
        *)
            echo "Invalid option: $REPLY. Skipping"
            break
            ;;
    esac
done

# --- 6. CPU Opt ---
echo -e "\n${BLUE}=== [6/7] CPU Optimization ===${NC}"

FLAGS=$(grep -m1 "flags" /proc/cpuinfo)

# x86-64-v2: popcnt, sse4_1, sse4_2, ssse3
grep -q "popcnt" <<< "$FLAGS" && grep -q "sse4_2" <<< "$FLAGS" && grep -q "ssse3" <<< "$FLAGS" && V2_SUP=1 || V2_SUP=0
# x86-64-v3: avx, avx2, bmi1, bmi2, f16c, fma, movbe, xsave
grep -q "avx2" <<< "$FLAGS" && grep -q "bmi2" <<< "$FLAGS" && grep -q "fma" <<< "$FLAGS" && V3_SUP=1 || V3_SUP=0
# x86-64-v4: avx512f, avx512bw, avx512cd, avx512dq, avx512vl
grep -q "avx512f" <<< "$FLAGS" && grep -q "avx512bw" <<< "$FLAGS" && V4_SUP=1 || V4_SUP=0

get_status() { [[ $1 -eq 1 ]] && echo -e "${GREEN}[Supported]${NC}" || echo -e "${RED}[Unsupported]${NC}"; }

echo -e "1) [NATIVE]   Use Host CPU      ${GREEN}[Recommended]${NC}"
echo -e "2) [Generic]  Generic           ${GREEN}[Universal]${NC}"
echo -e "3) [Legacy]   x86-64-v2         $(get_status $V2_SUP)"
echo -e "4) [Modern]   x86-64-v3         $(get_status $V3_SUP)"
echo -e "5) [Bleeding] x86-64-v4         $(get_status $V4_SUP)"
read -p "Selection: " cpu_opt

KCFLAGS_OPT="-mtune=generic"
case $cpu_opt in
    1) set_conf "CONFIG_MNATIVE" "y"; set_conf "CONFIG_GENERIC_CPU" "n"; KCFLAGS_OPT="-march=native" ;;
    3) KCFLAGS_OPT="-march=x86-64-v2" ;;
    4) KCFLAGS_OPT="-march=x86-64-v3" ;;
    5) KCFLAGS_OPT="-march=x86-64-v4" ;;
esac
make $MAKE_FLAGS olddefconfig
cp .config "$SAVED_CONFIG_PATH"

# Prepare Build
echo -e "\n${BLUE}Preparing build...${NC}"
cd "$WORK_DIR"
mkdir -p build
cp "$SRC_DIR_NAME/.config" build/config
cd build

# --- 7. PKGBUILD ---
echo -e "\n${BLUE}=== [7/7] PKGBUILD ===${NC}"

cat > PKGBUILD <<EOF
# Maintainer: danya2271
pkgbase=$PKG_NAME
pkgname=("$PKG_NAME" "$PKG_NAME-headers")
pkgver=AUTO
pkgrel=1
pkgdesc="Kernel KKNX (Opt: $KCFLAGS_OPT)"
arch=('x86_64')
url="$REPO_URL"
license=('GPL2')
makedepends=($COMPILER_DEPS)
options=('!strip')
source=("git+file://${WORK_DIR}/${SRC_DIR_NAME}#branch=$(cd ${WORK_DIR}/${SRC_DIR_NAME} && git branch --show-current)" "config")
sha256sums=('SKIP' 'SKIP')

pkgver() {
  cd "${SRC_DIR_NAME}"
  # Очищаем версию от пробелов и лишнего
  make kernelversion | tr -d '[:space:]' | tr '-' '_'
}

prepare() {
  cd "${SRC_DIR_NAME}"
  cp ../config .config
  make $MAKE_FLAGS olddefconfig
}

build() {
  cd "${SRC_DIR_NAME}"
  make $MAKE_FLAGS KCFLAGS="${KCFLAGS_OPT} -O3 -pipe" -j\$(nproc) all

  # --- SAVE EXACT KERNEL VERSION ---
  # Сохраняем точную версию в файл, чтобы она совпадала в обоих пакетах
  make kernelrelease > ../version.txt
}

package_$PKG_NAME() {
  pkgdesc="The KKNX Kernel image"
  depends=('kmod' 'initramfs')
  optdepends=('linux-firmware: firmware images needed for some devices')
  provides=("VMLINUZ")

  cd "${SRC_DIR_NAME}"
  # Читаем сохраненную версию (удаляем пробелы)
  local kernver="\$(cat ../version.txt | tr -d '[:space:]')"
  local modulesdir="\${pkgdir}/usr/lib/modules/\${kernver}"

  echo "Installing modules for version: [\${kernver}]"
  make $MAKE_FLAGS INSTALL_MOD_PATH="\${pkgdir}/usr" modules_install

  # Удаляем сломанные симлинки от make modules_install
  rm -f "\${modulesdir}/build" "\${modulesdir}/source"

  # Создаем правильный симлинк на /usr/src (где будут заголовки)
  # Это ключевой момент для DKMS
  ln -sf "/usr/src/linux-kknx-\${kernver}" "\${modulesdir}/build"

  # Установка ядра
  mkdir -p "\${pkgdir}/boot"
  cp arch/x86/boot/bzImage "\${pkgdir}/boot/vmlinuz-${PKG_NAME}"

  # Mkinitcpio preset
  mkdir -p "\${pkgdir}/etc/mkinitcpio.d/"
  echo "# Preset for ${PKG_NAME}" > "\${pkgdir}/etc/mkinitcpio.d/${PKG_NAME}.preset"
  echo "ALL_kver='/boot/vmlinuz-${PKG_NAME}'" >> "\${pkgdir}/etc/mkinitcpio.d/${PKG_NAME}.preset"
  echo "PRESETS=('default')" >> "\${pkgdir}/etc/mkinitcpio.d/${PKG_NAME}.preset"
  echo "default_image='/boot/initramfs-${PKG_NAME}.img'" >> "\${pkgdir}/etc/mkinitcpio.d/${PKG_NAME}.preset"
  echo "default_options=''" >> "\${pkgdir}/etc/mkinitcpio.d/${PKG_NAME}.preset"
}

package_$PKG_NAME-headers() {
  pkgdesc="Kernel KKNX headers"
  depends=('pahole')
  cd "${SRC_DIR_NAME}"
  local kernver="\$(cat ../version.txt | tr -d '[:space:]')"
  local builddir="\${pkgdir}/usr/src/linux-kknx-\${kernver}"

  echo "Installing headers to: \${builddir}"
  mkdir -p "\${builddir}"

  # Копируем основные файлы
  cp .config Makefile Module.symvers System.map "\${builddir}/"

  # Копируем директории
  cp -a include scripts arch "\${builddir}/"

  # Очистка от мусора (.o), но осторожно
  find "\${builddir}/scripts" -type f -name "*.o" -delete
  find "\${builddir}/arch" -type f -name "*.o" -delete

  # --- DKMS FIX: Tools ---
  # Копируем objtool (обязательно)
  if [ -f tools/objtool/objtool ]; then
    mkdir -p "\${builddir}/tools/objtool"
    cp tools/objtool/objtool "\${builddir}/tools/objtool/"
  fi

  # Копируем resolve_btfids (если есть)
  if [ -f tools/bpf/resolve_btfids/resolve_btfids ]; then
    mkdir -p "\${builddir}/tools/bpf/resolve_btfids"
    cp tools/bpf/resolve_btfids/resolve_btfids "\${builddir}/tools/bpf/resolve_btfids/"
  fi

  # Удаляем временные файлы
  find "\${builddir}" -name "*.cmd" -delete
  find "\${builddir}" -name "*.a" -delete
  find "\${builddir}" -name "..install.cmd" -delete

  # --- CRITICAL FIX ---
  # Убеждаемся, что скрипты запускаемые
  chmod 755 -R "\${builddir}/scripts"
}
EOF

# --- Сборка ---
echo -e "${YELLOW}Build start...${NC}"
rm -rf src pkg
makepkg -sf --noconfirm

# --- Финиш ---
echo -e "\n${BLUE}=== DONE ===${NC}"
PKG_FILE=$(find . -maxdepth 1 -type f -name "${PKG_NAME}-[0-9]*.pkg.tar.zst" | sort -V | tail -n 1)
PKG_HEADER=$(find . -maxdepth 1 -type f -name "${PKG_NAME}-headers-*.pkg.tar.zst" | sort -V | tail -n 1)

PKG_FILE="${PKG_FILE#./}"
PKG_HEADER="${PKG_HEADER#./}"

if [ -n "$PKG_FILE" ]; then
    echo -e "Kernel:   ${GREEN}$PKG_FILE${NC}"
    echo -e "Headers: ${GREEN}$PKG_HEADER${NC}"

    read -p "Install? (y/N): " inst
    if [[ "$inst" =~ ^[Yy]$ ]]; then

        # --- 1. CLEANUP CONFLICTS ---
        echo -e "${YELLOW}Checking for conflicting directories...${NC}"

        # Get correct path
        cd "$WORK_DIR/$SRC_DIR_NAME"
        CURRENT_KVER=$(make kernelrelease)
        cd "$WORK_DIR/build"

        CONFLICT_DIR="/usr/lib/modules/$CURRENT_KVER/build"
        CONFLICT_SRC="/usr/lib/modules/$CURRENT_KVER/source"

        # Remove old symlinks or directories to avoid Pacman conflicts
        if [ -e "$CONFLICT_DIR" ]; then
            echo "Removing conflicting entry: $CONFLICT_DIR"
            sudo rm -rf "$CONFLICT_DIR"
        fi

        if [ -e "$CONFLICT_SRC" ]; then
             echo "Removing conflicting entry: $CONFLICT_SRC"
             sudo rm -rf "$CONFLICT_SRC"
        fi
        # ----------------------------

        sudo pacman -U "$PKG_FILE" "$PKG_HEADER" --overwrite='*' --noconfirm

        echo -e "\n${YELLOW}IMPORTANT:${NC} Do not forget: sudo grub-mkconfig -o /boot/grub/grub.cfg"
    fi

    # ... (Export part remains same)
    read -p "Export to $EXPORT_DIR? (y/N): " exp
    if [[ "$exp" =~ ^[Yy]$ ]]; then
        mkdir -p "$EXPORT_DIR"
        cp "$PKG_FILE" "$EXPORT_DIR/"
        [ -n "$PKG_HEADER" ] && cp "$PKG_HEADER" "$EXPORT_DIR/"
        echo "Copied"
    fi
else
    echo -e "${RED}Error: Package files not found!${NC}"
fi
