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
    git clone "$REPO_URL" "$SRC_DIR_NAME" --depth=1
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
echo "1) GCC"
echo "2) Clang/LLVM (Default)"
read -p "Selection (Enter=2): " compiler_choice

MAKE_FLAGS=""
COMPILER_DEPS="'bc' 'libelf' 'pahole' 'cpio' 'perl' 'tar' 'xz' 'git' 'xmlto' 'kmod' 'inetutils'"

if [ "$compiler_choice" == "1" ]; then
    echo -e "${GREEN}Selected: GCC${NC}"
else
    echo -e "${YELLOW}Selected: CLANG${NC}"
    MAKE_FLAGS="LLVM=1 LLVM_IAS=1"
    COMPILER_DEPS="${COMPILER_DEPS} 'clang' 'llvm' 'lld'"
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

echo -e "${YELLOW}Select Compiler Optimization Level:${NC}"
echo "1) Maximum Performance (-O3) [Default]"
echo "2) Standard Performance (-O2)"
echo "3) Optimize for Size (-Os)"
read -p "Selection (Enter=1): " cc_opt_select

set_conf CONFIG_CC_OPTIMIZE_FOR_MAXIMUM_PERFORMANCE n
set_conf CONFIG_CC_OPTIMIZE_FOR_PERFORMANCE n
set_conf CONFIG_CC_OPTIMIZE_FOR_SIZE n

# Default variable for PKGBUILD
OPT_LEVEL_FLAG="-O3"

case $cc_opt_select in
    2)
        echo "   -> Setting -O2 (Standard)"
        set_conf CONFIG_CC_OPTIMIZE_FOR_MAXIMUM_PERFORMANCE n
        set_conf CONFIG_CC_OPTIMIZE_FOR_PERFORMANCE y
        set_conf CONFIG_CC_OPTIMIZE_FOR_SIZE n
        OPT_LEVEL_FLAG="-O2"
        ;;
    3)
        echo "   -> Setting -Os (Size)"
        set_conf CONFIG_CC_OPTIMIZE_FOR_MAXIMUM_PERFORMANCE n
        set_conf CONFIG_CC_OPTIMIZE_FOR_PERFORMANCE n
        set_conf CONFIG_CC_OPTIMIZE_FOR_SIZE y
        OPT_LEVEL_FLAG="-Os"
        ;;
    *)
        echo "   -> Setting -O3 (Max Performance)"
        set_conf CONFIG_CC_OPTIMIZE_FOR_MAXIMUM_PERFORMANCE y
        set_conf CONFIG_CC_OPTIMIZE_FOR_PERFORMANCE n
        set_conf CONFIG_CC_OPTIMIZE_FOR_SIZE n
        OPT_LEVEL_FLAG="-O3"
        ;;
esac

echo -e "${YELLOW}LTO optimization:${NC}"
echo "1) Use default [Default]"
echo "2) Use ThinLTO"
echo "3) Use FullLTO"
read -p "Selection (Enter=1): " cc_lto_select

case $cc_lto_select in
    2)
        echo "   -> Setting ThinLTO"
        set_conf CONFIG_CC_OPTIMIZE_FOR_MAXIMUM_PERFORMANCE n
        set_conf CONFIG_CC_OPTIMIZE_FOR_PERFORMANCE y
        set_conf CONFIG_CC_OPTIMIZE_FOR_SIZE n
        ;;
    3)
        echo "   -> Setting FullLTO"
        set_conf CONFIG_CC_OPTIMIZE_FOR_MAXIMUM_PERFORMANCE n
        set_conf CONFIG_CC_OPTIMIZE_FOR_PERFORMANCE n
        set_conf CONFIG_CC_OPTIMIZE_FOR_SIZE y
        ;;
    *)
        echo "   -> Not changing anything"
        ;;
esac

echo "1) [Gaming]  Auto-apply best gaming tweaks (Low Latency / High Perf)"
echo "2) [Laptop]  Auto-apply best battery tweaks (Power Save / Secure)"
echo "3) [Manual]  Set each flag manually with description"
echo "4) [Skip]    Keep base config as-is"
read -p "Selection: " opt_choice

if [[ "$opt_choice" =~ ^(1|2|3)$ ]]; then
    set_conf CONFIG_EXPERT y

    DESC="This option enables LLVM's polyhedral loop optimizer known as Polly. Polly is able to optimize various loops throughout the kernel for
	  maximum cache locality"
    if [ "$opt_choice" == "1" ] || [ "$opt_choice" == "2" ] || ([ "$opt_choice" == "3" ] && ask_opt "Enable LLVM's polyhedral loop optimizer (Polly)" "$DESC"); then
        set_conf LLVM_POLLY y
    else
        set_conf LLVM_POLLY n
    fi

    # ==========================================================
    # [A] SECURITY MITIGATIONS (The "Free Performance" Switch)
    # ==========================================================
    # Gaming: Disable mitigations (Spectre/Meltdown). Riskier, but 5-20% faster.
    # Laptop: Enable mitigations. Safer for untrusted webs/apps.
    DESC_MIT_OFF="Disable Mitigations. Boosts CPU performance significantly, reduces security."

    if [ "$opt_choice" == "1" ] || ([ "$opt_choice" == "3" ] && ask_opt "Disable CPU Mitigations (Speed Boost)" "$DESC_MIT_OFF"); then
        set_conf CONFIG_CPU_MITIGATIONS n
        set_conf CONFIG_MITIGATION_RETPOLINE n
        set_conf CONFIG_MITIGATION_SLS n
        set_conf CONFIG_RETPOLINE n
        set_conf CONFIG_SLS n
    else
        # Default / Laptop (Secure)
        set_conf CONFIG_CPU_MITIGATIONS y
    fi

    # ==========================================================
    # [B] BACKGROUND TASKS (NUMA & KSM)
    # ==========================================================

    # --- 1. NUMA Balancing (Crucial for Laptops) ---
    # Laptops are UMA (Single Node). Balancing scans are wasted power.
    DESC_NUMA="Disable NUMA. Stops memory scanning on single-socket PC's"

    if [ "$opt_choice" == "2" ] || ([ "$opt_choice" == "3" ] && ask_opt "Disable the whole NUMA subsystem" "$DESC_NUMA"); then
        # Ludicrous: Rip out the whole subsystem (Save RAM + CPU)
        set_conf CONFIG_NUMA_BALANCING n
        set_conf CONFIG_NUMA_BALANCING_DEFAULT_ENABLED n
        set_conf CONFIG_NUMA n
        set_conf CONFIG_AMD_NUMA n
        set_conf CONFIG_X86_64_ACPI_NUMA n
    else
        set_conf CONFIG_NUMA_BALANCING y
        set_conf CONFIG_NUMA_BALANCING_DEFAULT_ENABLED y
        set_conf CONFIG_NUMA y
        set_conf CONFIG_AMD_NUMA y
        set_conf CONFIG_X86_64_ACPI_NUMA y
    fi

    # --- 2. KSM (Kernel Samepage Merging) ---
    DESC_KSM="Disable KSM. Stops 'ksmd' thread from scanning memory. Saves CPU."
    if [ "$opt_choice" != "1" ] || ask_opt "Disable KSM (Save CPU)" "$DESC_KSM"; then
        set_conf CONFIG_KSM n
    else
        set_conf CONFIG_KSM y
    fi

    # --- 3. Virtualization (KVM) ---
    DESC_KVM="Disable KVM. If you don't use Virtual Machines, save the overhead."
    if ([ "$opt_choice" == "3" ] && ask_opt "Disable KVM Support" "$DESC_KVM"); then
        set_conf CONFIG_KVM n
        set_conf CONFIG_KVM_INTEL n
        set_conf CONFIG_KVM_AMD n
    else
        set_conf CONFIG_KVM y
        set_conf CONFIG_KVM_INTEL y
        set_conf CONFIG_KVM_AMD y
    fi

    # ==========================================================
    # [C] CPU SCHEDULING & GOVERNORS
    # ==========================================================

    # --- 1. Preemption (Latency vs Throughput) ---
    DESC="Full Preemption. Essential for Gaming smoothness/input latency."
    if [ "$opt_choice" == "1" ] || ([ "$opt_choice" == "3" ] && ask_opt "Full Preemption (PREEMPT)" "$DESC"); then
        set_conf CONFIG_PREEMPT_VOLUNTARY n
        set_conf CONFIG_PREEMPT y
        set_conf CONFIG_PREEMPT_DYNAMIC y
    else
        set_conf CONFIG_PREEMPT n
        set_conf CONFIG_PREEMPT_VOLUNTARY y
    fi

    # --- 2. Timer Frequency (HZ) ---
    DESC_1000="1000Hz Timer. Best for mouse smoothness/gaming."
    DESC_300="300Hz Timer. Best balance for video sync and battery."
    DESC_100="100Hz Timer. Best for battery. Worst for latency."
    if [ "$opt_choice" == "1" ] || ([ "$opt_choice" == "3" ] && ask_opt "1000Hz Timer" "$DESC_1000"); then
        set_conf CONFIG_HZ_100 n
        set_conf CONFIG_HZ_250 n
        set_conf CONFIG_HZ_300 n
        set_conf CONFIG_HZ_1000 y
        set_conf CONFIG_HZ 1000
    elif [ "$opt_choice" == "2" ] || ([ "$opt_choice" == "3" ] && ask_opt "300Hz Timer" "$DESC_300"); then
        set_conf CONFIG_HZ_100 n
        set_conf CONFIG_HZ_250 n
        set_conf CONFIG_HZ_300 y
        set_conf CONFIG_HZ_1000 n
        set_conf CONFIG_HZ 300
    elif ([ "$opt_choice" == "3" ] && ask_opt "100Hz Timer" "$DESC_100"); then
        set_conf CONFIG_HZ_100 y
        set_conf CONFIG_HZ_250 n
        set_conf CONFIG_HZ_300 n
        set_conf CONFIG_HZ_1000 n
        set_conf CONFIG_HZ 100
    else
        set_conf CONFIG_HZ_100 n
        set_conf CONFIG_HZ_300 n
        set_conf CONFIG_HZ_250 y
        set_conf CONFIG_HZ_1000 n
        set_conf CONFIG_HZ 250
    fi

    # --- 3. Default CPU IDLE governor ---
    # TEO (Timer Events Oriented) is newer and often better for battery
    # on tickless (NO_HZ) systems than the standard 'Menu' governor.
    DESC_TEO="Use TEO Idle Governor. Best for battery on modern tickless kernels."
    if [ "$opt_choice" != "1" ] || ask_opt "Use TEO Idle Governor" "$DESC_TEO"; then
        set_conf CONFIG_CPU_IDLE_GOV_TEO y
        set_conf CONFIG_CPU_IDLE_GOV_MENU n
    else
        # Standard Menu Governor (better for server/steady loads)
        set_conf CONFIG_CPU_IDLE_GOV_TEO n
        set_conf CONFIG_CPU_IDLE_GOV_MENU y
    fi

    # --- 3. Default CPU Governor ---
    DESC_PERF="Performance Governor. Pins clocks high. Max responsiveness."
    DESC_SCHED="Schedutil Governor. Intelligent scaling. Best for battery."
    if [ "$opt_choice" == "1" ] || ([ "$opt_choice" == "3" ] && ask_opt "Default Governor: Performance" "$DESC_PERF"); then
        set_conf CONFIG_CPU_FREQ_DEFAULT_GOV_PERFORMANCE y
        set_conf CONFIG_CPU_FREQ_DEFAULT_GOV_SCHEDUTIL n
    elif [ "$opt_choice" == "2" ] || ([ "$opt_choice" == "3" ] && ask_opt "Default Governor: Schedutil" "$DESC_SCHED"); then
         set_conf CONFIG_CPU_FREQ_DEFAULT_GOV_PERFORMANCE n
         set_conf CONFIG_CPU_FREQ_DEFAULT_GOV_SCHEDUTIL y
    fi

    # ==========================================================
    # [D] STORAGE (I/O) SCHEDULING
    # ==========================================================

    # Gaming: Kyber (Low latency for NVMe).
    # Laptop: BFQ (Fairness, prevents system lockup during heavy copies).
    DESC_KYBER="Kyber I/O. Simple, low overhead. Best for pure NVMe gaming."
    DESC_BFQ="BFQ I/O. Complex, high fairness. Smooth desktop usage under load."

    if [ "$opt_choice" == "1" ] || ([ "$opt_choice" == "3" ] && ask_opt "Use Kyber I/O (Gaming)" "$DESC_KYBER"); then
        set_conf CONFIG_MQ_IOSCHED_KYBER y
        set_conf CONFIG_IOSCHED_BFQ n
        set_conf CONFIG_DEFAULT_KYBER y
        set_conf CONFIG_DEFAULT_IOSCHED "kyber"
    elif [ "$opt_choice" == "2" ] || ([ "$opt_choice" == "3" ] && ask_opt "Use BFQ I/O (Smoothness)" "$DESC_BFQ"); then
        set_conf CONFIG_IOSCHED_BFQ y
        set_conf CONFIG_DEFAULT_BFQ y
        set_conf CONFIG_DEFAULT_IOSCHED "bfq"
    fi

    # ==========================================================
    # [E] MEMORY, NETWORK & BATTERY
    # ==========================================================

    # --- 1. SATA/AHCI Link Power Management (LPM) ---
    # This is often the culprit for high sleep drain if you have SATA SSDs or controllers.
    # Policy 3 = Med_Power_with_DIPM (Device Initiated Power Management)
    DESC_SATA="SATA Mobile LPM. Essential for dropping SATA link power."
    if [ "$opt_choice" == "2" ] || [ "$opt_choice" == "3" ] || ask_opt "Enable SATA Mobile LPM" "$DESC_SATA"; then
        set_conf CONFIG_SATA_MOBILE_LPM_POLICY 3
    else
        set_conf CONFIG_SATA_MOBILE_LPM_POLICY 0
    fi

    # --- 2. Wi-Fi Power Save Default ---
    # Forces the Wi-Fi driver to enable power saving immediately on boot.
    DESC_WIFI="Wi-Fi Power Save Default. Enable radio sleep on boot."
    if [ "$opt_choice" == "2" ] || [ "$opt_choice" == "3" ] || ask_opt "Enable Wi-Fi PS" "$DESC_WIFI"; then
        set_conf CONFIG_CFG80211_DEFAULT_PS y
    else
        set_conf CONFIG_CFG80211_DEFAULT_PS n
    fi

    # --- 3. PCIe ASPM (Active State Power Management) ---
    # Laptop: Supersave (Max battery, aggressive link sleep).
    # Gaming: Performance (Keeps links awake to avoid wake-latency stutters).
    DESC_ASPM="PCIe ASPM Supersave. Force PCIe links (WiFi/SSD) to low power. Essential for Laptop battery."

    if [ "$opt_choice" == "2" ] || ([ "$opt_choice" == "3" ] && ask_opt "Enable PCIe ASPM Supersave" "$DESC_ASPM"); then
        set_conf CONFIG_PCIEASPM y
        set_conf CONFIG_PCIEASPM_POWER_SUPERSAVE y
        set_conf CONFIG_PCIEASPM_PERFORMANCE n
        set_conf CONFIG_PCIEASPM_DEFAULT n
    elif [ "$opt_choice" == "1" ]; then
        # Gaming: Force Performance to prevent stutter
        set_conf CONFIG_PCIEASPM y
        set_conf CONFIG_PCIEASPM_PERFORMANCE y
        set_conf CONFIG_PCIEASPM_POWER_SUPERSAVE n
    fi

    # --- 4. Deep Sleep Tweaks (Laptop Focused) ---
    DESC="Power Efficient WQ & RCU Lazy. Essential for battery life (Deep Sleep)."
    if [ "$opt_choice" == "2" ] || ([ "$opt_choice" == "3" ] && ask_opt "Enable Deep Sleep Tweaks" "$DESC"); then
        # Move tasks to power-efficient cores
        set_conf CONFIG_WQ_POWER_EFFICIENT_DEFAULT y
        # Batch RCU updates (less wakeups)
        set_conf CONFIG_RCU_LAZY y
        set_conf CONFIG_RCU_NOCB_CPU y
        # Power down audio chip after 5s
        set_conf CONFIG_SND_HDA_POWER_SAVE_DEFAULT 5
        # Disable NMI Watchdog (wasted energy on stable systems)
        set_conf CONFIG_HARDLOCKUP_DETECTOR n
    else
        # Gaming Defaults
        set_conf CONFIG_WQ_POWER_EFFICIENT_DEFAULT n
        set_conf CONFIG_SND_HDA_POWER_SAVE_DEFAULT 0
    fi

    # --- 5. ZSWAP (Compressed RAM) ---
    DESC="Enable ZSWAP. Compresses RAM to reduce disk swapping. Faster & Efficient."
    if [ "$opt_choice" == "1" ] || [ "$opt_choice" == "2" ] || ask_opt "Enable ZSWAP" "$DESC"; then
        set_conf CONFIG_ZSWAP y
        set_conf CONFIG_ZSWAP_DEFAULT_ON y
        set_conf CONFIG_ZPOOL y
        set_conf CONFIG_ZBUD y
    fi

    # --- 6. TCP BBR ---
    DESC="TCP BBR. Improved network throughput and latency."
    if [ "$opt_choice" == "1" ] || [ "$opt_choice" == "2" ] || ask_opt "Enable TCP BBR" "$DESC"; then
        set_conf CONFIG_TCP_CONG_BBR y
        set_conf CONFIG_DEFAULT_TCP_CONG "bbr"
    fi

    # --- 7. MGLRU & THP ---
    DESC="MGLRU & THP Madvise. Best modern defaults for smoothness."
    if [ "$opt_choice" == "1" ] || [ "$opt_choice" == "2" ] || ask_opt "Enable MGLRU & Madvise" "$DESC"; then
        set_conf CONFIG_LRU_GEN y
        set_conf CONFIG_LRU_GEN_ENABLED y
        set_conf CONFIG_TRANSPARENT_HUGEPAGE_ALWAYS n
        set_conf CONFIG_TRANSPARENT_HUGEPAGE_MADVISE y
    fi

    # --- 8. DAMON ---
    DESC="Data Access MONitoring. Useful for servers with much of RAM (>256gb), useless and (sometimes) harmful for desktop PC's"
    if [ "$opt_choice" == "1" ] || [ "$opt_choice" == "2" ] || ask_opt "Enable DAMON" "$DESC"; then
        set_conf CONFIG_DAMON y
    else
        set_conf CONFIG_DAMON n
    fi

    # --- 9. Legacy syscalls (obsolete) ---
    DESC="MODIFY_LDT_SYSCALL Bypasses an old system call used by Wine for very old Windows apps. Modern games don't use it."
    if [ "$opt_choice" == "1" ] || [ "$opt_choice" == "2" ] || ask_opt "Enable MODIFY_LDT_SYSCALL" "$DESC"; then
        set_conf CONFIG_MODIFY_LDT_SYSCALL
        set_conf CONFIG_16BIT y
    else
        set_conf CONFIG_16BIT n
        set_conf CONFIG_MODIFY_LDT_SYSCALL n
    fi


    DESC_DEBLOAT="Remove obsolete hardware/protocols (Hamradio, ISDN, Legacy Ethernet/Audio, Crash Dumps)."

    if [ "$opt_choice" == "3" ] && ask_opt "Apply Hardware Debloat" "$DESC_DEBLOAT"; then
        echo "   -> Disabling Obsolete Protocols (Hamradio, ISDN, FDDI, WiMAX)..."
        set_conf CONFIG_HAMRADIO n
        set_conf CONFIG_ISDN n
        set_conf CONFIG_FDDI n
        set_conf CONFIG_HIPPI n
        set_conf CONFIG_WIMAX n
        set_conf CONFIG_NET_FC n

        echo "   -> Disabling Legacy Ethernet Vendors (3COM, Adaptec, DEC, etc.)..."
        set_conf CONFIG_NET_VENDOR_3COM n
        set_conf CONFIG_NET_VENDOR_ADAPTEC n
        set_conf CONFIG_NET_VENDOR_AGERE n
        set_conf CONFIG_NET_VENDOR_ALACRITECH n
        set_conf CONFIG_NET_VENDOR_ALTEON n
        set_conf CONFIG_NET_VENDOR_AMD n
        set_conf CONFIG_NET_VENDOR_ARC n
        set_conf CONFIG_NET_VENDOR_ATHEROS n
        set_conf CONFIG_NET_VENDOR_BROADCOM n
        set_conf CONFIG_NET_VENDOR_DEC n
        set_conf CONFIG_NET_VENDOR_DLINK n
        set_conf CONFIG_NET_VENDOR_EMULEX n
        set_conf CONFIG_NET_VENDOR_HUAWEI n
        set_conf CONFIG_NET_VENDOR_NVIDIA n
        set_conf CONFIG_NET_VENDOR_SIS n
        set_conf CONFIG_NET_VENDOR_VIA n
        set_conf CONFIG_NET_VENDOR_SILAN n

        echo "   -> Disabling Legacy Input/Sound..."
        # Disable Analog Gameports (Modern controllers use USB/HID)
        set_conf CONFIG_INPUT_JOYSTICK n

        echo "   -> Disabling Guest Virtualization & Crash Dumps..."
        # Disable acting as a Guest (Hyper-V/Xen/KVM Guest)
        set_conf CONFIG_HYPERV n
        set_conf CONFIG_XEN n
        set_conf CONFIG_KVM_GUEST n
        set_conf CONFIG_PARAVIRT n

        # Disable Legacy/Enterprise SCSI drivers
        set_conf CONFIG_SCSI_LOWLEVEL n

        # Disable older Graphics drivers if not needed (Assuming Modern AMD/Nvidia/Intel)
        set_conf CONFIG_DRM_RADEON n
        set_conf CONFIG_DRM_NOUVEAU n
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

    # 6. Battery-related
    set_conf CONFIG_PM_DEBUG n
    set_conf CONFIG_ACPI_DEBUG n
    set_conf CONFIG_PM_TRACE n

    # 7. Scheduler-related
    set_conf CONFIG_SCHEDSTATS n

    # 8. Other
    set_conf CONFIG_DEBUG_BUGVERBOSE n
    set_conf CONFIG_DEBUG_LIST n
    set_conf CONFIG_BUG_ON_DATA_CORRUPTION n
    set_conf CONFIG_CRASH_DUMP n
    set_conf CONFIG_KEXEC n
    set_conf CONFIG_PAGE_POISONING n

fi

read -p "Disable debug fs? (y/N): " kill_debug_fs
if [[ "$kill_debug_fs" =~ ^[Yy]$ ]]; then
    echo -e "${GREEN}Disabling debug fs...${NC}"
    set_conf CONFIG_DEBUG_FS n
elif [[ "$kill_debug_fs" =~ ^[Nn]$ ]]; then
    echo -e "${GREEN}Enabling debug fs...${NC}"
    set_conf CONFIG_DEBUG_FS y
fi

read -p "Disable kallsyms? (y/N): " kill_ksyms
if [[ "$kill_ksyms" =~ ^[Yy]$ ]]; then
    echo -e "${GREEN}Disabling kallsyms...${NC}"
    set_conf CONFIG_KALLSYMS n
elif [[ "$kill_ksyms" =~ ^[Nn]$ ]]; then
    echo -e "${GREEN}Enabling kallsyms...${NC}"
    set_conf CONFIG_KALLSYMS y
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
            sudo dmesg | grep -iE "firmware|failed|missing" | grep -v "status 0" || echo "No missing firmware detected."
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

# Detect Host Details
HOST_VENDOR=$(grep -m1 "vendor_id" /proc/cpuinfo | awk '{print $3}')
IS_64BIT=$(grep -q " lm " /proc/cpuinfo && echo 1 || echo 0)

case $cpu_opt in
    1)
        echo "   -> Configuring Native Optimization for: $HOST_VENDOR"

        KCFLAGS_OPT="-march=native"
        set_conf "CONFIG_FORCE_NR_CPUS" "y"
        set_conf "CONFIG_NR_CPUS" $(($(nproc)))
        set_conf "CONFIG_GENERIC_CPU" "n"
        set_conf "CONFIG_X86_NATIVE_CPU" "y"
        set_conf "CONFIG_EXPERT" "y"
        set_conf "CONFIG_PROCESSOR_SELECT" "y"

        case "$HOST_VENDOR" in
            "GenuineIntel")
                set_conf "CONFIG_CPU_SUP_INTEL" "y"
                set_conf "CONFIG_CPU_SUP_AMD" "n"
                set_conf "CONFIG_CPU_SUP_HYGON" "n"
                set_conf "CONFIG_CPU_SUP_CENTAUR" "n"
                set_conf "CONFIG_CPU_SUP_ZHAOXIN" "n"
                ;;
            "AuthenticAMD")
                set_conf "CONFIG_CPU_SUP_INTEL" "n"
                set_conf "CONFIG_CPU_SUP_AMD" "y"
                set_conf "CONFIG_CPU_SUP_HYGON" "n" # Hygon is based on AMD but distinct config
                set_conf "CONFIG_CPU_SUP_CENTAUR" "n"
                set_conf "CONFIG_CPU_SUP_ZHAOXIN" "n"
                ;;
            "HygonGenuine")
                set_conf "CONFIG_CPU_SUP_INTEL" "n"
                set_conf "CONFIG_CPU_SUP_AMD" "y" # Hygon usually requires AMD support
                set_conf "CONFIG_CPU_SUP_HYGON" "y"
                set_conf "CONFIG_CPU_SUP_CENTAUR" "n"
                set_conf "CONFIG_CPU_SUP_ZHAOXIN" "n"
                ;;
            *)
                echo "   -> Unknown vendor '$HOST_VENDOR'. Keeping all vendors enabled for safety."
                ;;
        esac

        # 4. Disable Legacy/Obscure 32-bit CPUs on 64-bit systems
        if [[ "$IS_64BIT" -eq 1 ]]; then
            set_conf "CONFIG_CPU_SUP_CYRIX_32" "n"
            set_conf "CONFIG_CPU_SUP_TRANSMETA_32" "n"
            set_conf "CONFIG_CPU_SUP_UMC_32" "n"
            set_conf "CONFIG_CPU_SUP_VORTEX_32" "n"
        fi
        ;;
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

cat > "${PKG_NAME}.install" <<EOF
post_install() {
  echo ">>> KKNX kernel installed. Generating initramfs..."
  mkinitcpio -p ${PKG_NAME}
}

post_upgrade() {
  post_install
}

post_remove() {
  echo ">>> Removing initramfs images for ${PKG_NAME}..."
  rm -f /boot/initramfs-${PKG_NAME}.img
  rm -f /boot/initramfs-${PKG_NAME}-fallback.img
}
EOF

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
  make kernelversion | tr -d '[:space:]' | tr '-' '_'
}

prepare() {
  cd "${SRC_DIR_NAME}"
  cp ../config .config
  make $MAKE_FLAGS olddefconfig
}

build() {
  cd "${SRC_DIR_NAME}"

  # Force userspace tools (objtool, resolve_btfids) to use the selected CPU level.
  # This overrides /etc/makepkg.conf settings which might be set to -march=native (v3).
  export CFLAGS="${KCFLAGS_OPT} ${OPT_LEVEL_FLAG} -pipe"
  export CXXFLAGS="${KCFLAGS_OPT} ${OPT_LEVEL_FLAG} -pipe"
  export LDFLAGS="-Wl,-O1,--sort-common,--as-needed,-z,relro,-z,now"
  export HOSTCFLAGS="${KCFLAGS_OPT} ${OPT_LEVEL_FLAG} -pipe"

  make $MAKE_FLAGS KCFLAGS="${KCFLAGS_OPT} ${OPT_LEVEL_FLAG} -pipe" -j\$(nproc) all

  make kernelrelease > ../version.txt
}

package_$PKG_NAME() {
  pkgdesc="The KKNX Kernel image"
  depends=('kmod' 'initramfs' 'mkinitcpio')
  optdepends=('linux-firmware: firmware images needed for some devices')
  provides=("VMLINUZ")

  install="${PKG_NAME}.install"

  cd "${SRC_DIR_NAME}"
  local kernver="\$(cat ../version.txt | tr -d '[:space:]')"
  local modulesdir="\${pkgdir}/usr/lib/modules/\${kernver}"

  echo "Installing modules for version: [\${kernver}]"
  make $MAKE_FLAGS INSTALL_MOD_PATH="\${pkgdir}/usr" modules_install

  rm -f "\${modulesdir}/build" "\${modulesdir}/source"

  ln -sf "/usr/src/linux-kknx-\${kernver}" "\${modulesdir}/build"

  mkdir -p "\${pkgdir}/boot"
  cp arch/x86/boot/bzImage "\${pkgdir}/boot/vmlinuz-${PKG_NAME}"

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

  cp .config Makefile Module.symvers System.map "\${builddir}/"

  cp -a include scripts arch "\${builddir}/"

  find "\${builddir}/scripts" -type f -name "*.o" -delete
  find "\${builddir}/arch" -type f -name "*.o" -delete

  if [ -f tools/objtool/objtool ]; then
    mkdir -p "\${builddir}/tools/objtool"
    cp tools/objtool/objtool "\${builddir}/tools/objtool/"
  fi

  if [ -f tools/bpf/resolve_btfids/resolve_btfids ]; then
    mkdir -p "\${builddir}/tools/bpf/resolve_btfids"
    cp tools/bpf/resolve_btfids/resolve_btfids "\${builddir}/tools/bpf/resolve_btfids/"
  fi

  find "\${builddir}" -name "*.cmd" -delete
  find "\${builddir}" -name "*.a" -delete
  find "\${builddir}" -name "..install.cmd" -delete

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
