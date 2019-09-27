#!/bin/bash
#
# Simple script to tweak an existing baseline kernel .config file.
#
# Copyright (c) 2018 sakaki <sakaki@deciban.com>
# License: GPL v2.0
# NO WARRANTY
# Copied from https://github.com/sakaki-/bcm2711-kernel-bis
#

set -e
set -u
shopt -s nullglob

# Utility functions

set_kernel_config() {
    # flag as $1, value to set as $2, config must exist at "./.config"
    local TGT="CONFIG_${1#CONFIG_}"
    local REP="${2//\//\\/}"
    if grep -q "^${TGT}[^_]" .config; then
        sed -i "s/^\(${TGT}=.*\|# ${TGT} is not set\)/${TGT}=${REP}/" .config
    else
        echo "${TGT}=${2}" >> .config
    fi
}

unset_kernel_config() {
    # unsets flag with the value of $1, config must exist at "./.config"
    local TGT="CONFIG_${1#CONFIG_}"
    sed -i "s/^${TGT}=.*/# ${TGT} is not set/" .config
}


# Custom config settings follow

# Submit PRs with edits targeting the _bottom_ of this file
# Please set modules where possible, rather than building in, and
# provide a short rationale comment for the changes made

# Enable squashfs since snap needs it, which causes errors at boot on the eoan 
# image otherwise which disallows logins.
set_kernel_config CONFIG_SQUASHFS y

# Add git tag to version
set_kernel_config CONFIG_LOCALVERSION_AUTO y

# enable basic KVM support; see e.g.
# https://www.raspberrypi.org/forums/viewtopic.php?f=63&t=210546&start=25#p1300453
set_kernel_config CONFIG_VIRTUALIZATION y
set_kernel_config CONFIG_KVM y
set_kernel_config CONFIG_VHOST_NET m
set_kernel_config CONFIG_VHOST_CROSS_ENDIAN_LEGACY y

# enable ZSWAP support for better performance during large builds etc.
# requires activation via kernel parameter or sysfs
# see e.g. https://askubuntu.com/a/472227 for a summary of ZSWAP (vs ZRAM etc.)
# and e.g. https://wiki.archlinux.org/index.php/zswap for parameters etc.
set_kernel_config CONFIG_ZPOOL y
set_kernel_config CONFIG_ZSWAP y
set_kernel_config CONFIG_ZBUD y
set_kernel_config CONFIG_Z3FOLD y
set_kernel_config CONFIG_ZSMALLOC y
set_kernel_config CONFIG_PGTABLE_MAPPING y

# https://groups.google.com/forum/#!topic/linux.gentoo.user/_2aSc_ztGpA
# https://github.com/torvalds/linux/blob/master/init/Kconfig#L848
# Enables BPF syscall for systemd-journald firewalling
set_kernel_config CONFIG_BPF_SYSCALL y
set_kernel_config CONFIG_CGROUP_BPF y

#See https://github.com/raspberrypi/linux/issues/2177#issuecomment-354647406
# Netfilter kernel support
# xtables
set_kernel_config CONFIG_NETFILTER_XTABLES m
# # Netfilter nf_tables support
set_kernel_config CONFIG_NF_TABLES m
set_kernel_config CONFIG_NETFILTER_XTABLES m
set_kernel_config CONFIG_NF_TABLES_BRIDGE m
set_kernel_config CONFIG_NF_NAT_SIP m
set_kernel_config CONFIG_NF_NAT_TFTP m
set_kernel_config CONFIG_NF_NAT_REDIRECT m
set_kernel_config CONFIG_NF_TABLES_INET m
set_kernel_config CONFIG_NF_TABLES_NETDEV m
set_kernel_config CONFIG_NF_TABLES_ARP m
set_kernel_config CONFIG_NF_DUP_IPV4 m
set_kernel_config CONFIG_NF_LOG_IPV4 m
set_kernel_config CONFIG_NF_REJECT_IPV4 m
set_kernel_config CONFIG_NF_NAT_IPV4 m
set_kernel_config CONFIG_NF_DUP_NETDEV m
set_kernel_config CONFIG_NF_DEFRAG_IPV4 m
set_kernel_config CONFIG_NF_CONNTRACK_IPV4 m
set_kernel_config CONFIG_NF_TABLES_IPV4 m
set_kernel_config CONFIG_NF_NAT_MASQUERADE_IPV4 m
set_kernel_config CONFIG_NF_NAT_SNMP_BASIC m
set_kernel_config CONFIG_NF_NAT_PROTO_GRE m
set_kernel_config CONFIG_NF_NAT_PPTP m
set_kernel_config CONFIG_NF_DEFRAG_IPV6 m
set_kernel_config CONFIG_NF_CONNTRACK_IPV6 m
set_kernel_config CONFIG_NF_TABLES_IPV6 m
set_kernel_config CONFIG_NF_DUP_IPV6 m
set_kernel_config CONFIG_NF_REJECT_IPV6 m
set_kernel_config CONFIG_NF_LOG_IPV6 m
set_kernel_config CONFIG_NF_NAT_IPV6 m
set_kernel_config CONFIG_NF_NAT_MASQUERADE_IPV6 m
set_kernel_config CONFIG_NFT_EXTHDR m
set_kernel_config CONFIG_NFT_META m
set_kernel_config CONFIG_NFT_NUMGEN m
set_kernel_config CONFIG_NFT_CT m
set_kernel_config CONFIG_NFT_SET_RBTREE m
set_kernel_config CONFIG_NFT_SET_HASH m
set_kernel_config CONFIG_NFT_COUNTER m
set_kernel_config CONFIG_NFT_LOG m
set_kernel_config CONFIG_NFT_LIMIT m
set_kernel_config CONFIG_NFT_MASQ m
set_kernel_config CONFIG_NFT_REDIR m
set_kernel_config CONFIG_NFT_NAT m
set_kernel_config CONFIG_NFT_QUEUE m
set_kernel_config CONFIG_NFT_QUOTA m
set_kernel_config CONFIG_NFT_REJECT m
set_kernel_config CONFIG_NFT_REJECT_INET m
set_kernel_config CONFIG_NFT_COMPAT m
set_kernel_config CONFIG_NFT_HASH m
set_kernel_config CONFIG_NFT_DUP_NETDEV m
set_kernel_config CONFIG_NFT_FWD_NETDEV m
set_kernel_config CONFIG_NFT_CHAIN_ROUTE_IPV4 m
set_kernel_config CONFIG_NFT_REJECT_IPV4 m
set_kernel_config CONFIG_NFT_DUP_IPV4 m
set_kernel_config CONFIG_NFT_CHAIN_NAT_IPV4 m
set_kernel_config CONFIG_NFT_MASQ_IPV4 m
set_kernel_config CONFIG_NFT_REDIR_IPV4 m
set_kernel_config CONFIG_NFT_CHAIN_ROUTE_IPV6 m
set_kernel_config CONFIG_NFT_REJECT_IPV6 m
set_kernel_config CONFIG_NFT_DUP_IPV6 m
set_kernel_config CONFIG_NFT_CHAIN_NAT_IPV6 m
set_kernel_config CONFIG_NFT_MASQ_IPV6 m
set_kernel_config CONFIG_NFT_REDIR_IPV6 m
set_kernel_config CONFIG_NFT_BRIDGE_META m
set_kernel_config CONFIG_NFT_BRIDGE_REJECT m
set_kernel_config CONFIG_IP_SET_BITMAP_IPMAC m
set_kernel_config CONFIG_IP_SET_BITMAP_PORT m
set_kernel_config CONFIG_IP_SET_HASH_IP m
set_kernel_config CONFIG_IP_SET_HASH_IPMARK m
set_kernel_config CONFIG_IP_SET_HASH_IPPORT m
set_kernel_config CONFIG_IP_SET_HASH_IPPORTIP m
set_kernel_config CONFIG_IP_SET_HASH_IPPORTNET m
set_kernel_config CONFIG_IP_SET_HASH_MAC m
set_kernel_config CONFIG_IP_SET_HASH_NETPORTNET m
set_kernel_config CONFIG_IP_SET_HASH_NET m
set_kernel_config CONFIG_IP_SET_HASH_NETNET m
set_kernel_config CONFIG_IP_SET_HASH_NETPORT m
set_kernel_config CONFIG_IP_SET_HASH_NETIFACE m
set_kernel_config CONFIG_IP_SET_LIST_SET m
set_kernel_config CONFIG_IP6_NF_IPTABLES m
set_kernel_config CONFIG_IP6_NF_MATCH_AH m
set_kernel_config CONFIG_IP6_NF_MATCH_EUI64 m
set_kernel_config CONFIG_IP6_NF_NAT m
set_kernel_config CONFIG_IP6_NF_TARGET_MASQUERADE m
set_kernel_config CONFIG_IP6_NF_TARGET_NPT m
set_kernel_config CONFIG_NF_LOG_BRIDGE m
set_kernel_config CONFIG_BRIDGE_NF_EBTABLES m
set_kernel_config CONFIG_BRIDGE_EBT_BROUTE m
set_kernel_config CONFIG_BRIDGE_EBT_T_FILTER m 

# Mask this temporarily during switch to rpi-4.19.y
# Fix SD_DRIVER upstream and downstream problem in 64bit defconfig
# use correct driver MMC_BCM2835_MMC instead of MMC_BCM2835_SDHOST - see https://www.raspberrypi.org/forums/viewtopic.php?t=210225
#set_kernel_config CONFIG_MMC_BCM2835 n
#set_kernel_config CONFIG_MMC_SDHCI_IPROC n
#set_kernel_config CONFIG_USB_DWC2 n
#sed -i "s|depends on MMC_BCM2835_MMC && MMC_BCM2835_DMA|depends on MMC_BCM2835_MMC|" ./drivers/mmc/host/Kconfig

# Enable VLAN support again (its in armv7 configs)
set_kernel_config CONFIG_IPVLAN m

# Enable SoC camera support
# See https://www.raspberrypi.org/forums/viewtopic.php?p=1425257#p1425257
#set_kernel_config CONFIG_VIDEO_V4L2_SUBDEV_API y
#set_kernel_config CONFIG_VIDEO_BCM2835_UNICAM m

# Enable RPI POE HAT fan
set_kernel_config CONFIG_SENSORS_RPI_POE_FAN m

# Unset hifiberry options
unset_kernel_config CONFIG_SND_BCM2835_SOC_I2S
unset_kernel_config CONFIG_SND_SOC_CYGNUS
unset_kernel_config CONFIG_SND_BCM2708_SOC_GOOGLEVOICEHAT_SOUNDCARD
unset_kernel_config CONFIG_SND_BCM2708_SOC_HIFIBERRY_DAC
unset_kernel_config CONFIG_SND_BCM2708_SOC_HIFIBERRY_DACPLUS
unset_kernel_config CONFIG_SND_BCM2708_SOC_HIFIBERRY_DACPLUSADC
unset_kernel_config CONFIG_SND_BCM2708_SOC_HIFIBERRY_DIGI
unset_kernel_config CONFIG_SND_BCM2708_SOC_HIFIBERRY_AMP
unset_kernel_config CONFIG_SND_BCM2708_SOC_RPI_CIRRUS
unset_kernel_config CONFIG_SND_BCM2708_SOC_RPI_DAC
unset_kernel_config CONFIG_SND_BCM2708_SOC_RPI_PROTO
unset_kernel_config CONFIG_SND_BCM2708_SOC_JUSTBOOM_DAC
unset_kernel_config CONFIG_SND_BCM2708_SOC_JUSTBOOM_DIGI
unset_kernel_config CONFIG_SND_BCM2708_SOC_IQAUDIO_CODEC
unset_kernel_config CONFIG_SND_BCM2708_SOC_IQAUDIO_DAC
unset_kernel_config CONFIG_SND_BCM2708_SOC_IQAUDIO_DIGI
unset_kernel_config CONFIG_SND_BCM2708_SOC_I_SABRE_Q2M
unset_kernel_config CONFIG_SND_BCM2708_SOC_ADAU1977_ADC
unset_kernel_config CONFIG_SND_AUDIOINJECTOR_PI_SOUNDCARD
unset_kernel_config CONFIG_SND_AUDIOINJECTOR_OCTO_SOUNDCARD
unset_kernel_config CONFIG_SND_AUDIOSENSE_PI
unset_kernel_config CONFIG_SND_DIGIDAC1_SOUNDCARD
unset_kernel_config CONFIG_SND_BCM2708_SOC_DIONAUDIO_LOCO
unset_kernel_config CONFIG_SND_BCM2708_SOC_DIONAUDIO_LOCO_V2
unset_kernel_config CONFIG_SND_BCM2708_SOC_ALLO_PIANO_DAC
unset_kernel_config CONFIG_SND_BCM2708_SOC_ALLO_PIANO_DAC_PLUS
unset_kernel_config CONFIG_SND_BCM2708_SOC_ALLO_BOSS_DAC
unset_kernel_config CONFIG_SND_BCM2708_SOC_ALLO_DIGIONE
unset_kernel_config CONFIG_SND_BCM2708_SOC_ALLO_KATANA_DAC
unset_kernel_config CONFIG_SND_BCM2708_SOC_FE_PI_AUDIO
unset_kernel_config CONFIG_SND_PISOUND
unset_kernel_config CONFIG_SND_RPI_SIMPLE_SOUNDCARD
unset_kernel_config CONFIG_SND_RPI_WM8804_SOUNDCARD

unset_kernel_config CONFIG_RTL8187
unset_kernel_config CONFIG_RTL8192CU 
# This is needed for for zfs to compile without GPL-incompatible module zfs.ko uses GPL-only symbol 'preempt_schedule_notrace' error
unset_kernel_config CONFIG_PREEMPT
unset_kernel_config PREEMPT_RT_FULL
set_kernel_config CONFIG_PREEMPT_VOLUNTARY y
# Remove upstream mmc modules as per https://lists.ubuntu.com/archives/kernel-team/2018-April/091646.html
#unset_kernel_config CONFIG_MMC_BCM2835
# This is needed as per https://github.com/raspberrypi/linux/pull/3045/commits/4a14d01965a86370d78d474b486a45e343f28f66
#set_kernel_config CONFIG_MMC_SDHCI_IPROC
