#!/bin/bash
#
# Simple script to patch a baseline RPi kernel source tree, with
# facilities to easily download and apply PRs from:
# https://github.com/raspberrypi/linux/pull/<#>.
#
# Copyright (c) 2019 sakaki <sakaki@deciban.com>
# License: GPL v2.0
# NO WARRANTY
#

set -e
set -u
shopt -s nullglob

#PRs apply status counts:
declare -a applied_prs
# Utility functions

apply_pr() {
    # pr number as $1, comment as $2
    echo "Applying PR#${1}: '${2}':"
    if ! wget -c --quiet \
      https://patch-diff.githubusercontent.com/raw/raspberrypi/linux/pull/${1}.diff \
      -O ${1}.patch; then
        >&2 echo "  Failed to download patchfile for PR#${1}"
    elif [[ ! -s ${1}.patch ]]; then
        >&2 echo "  No non-empty patchfile for PR#${1}"
    elif ! patch -p1 --forward --silent --force --dry-run &>/dev/null \
           < ${1}.patch; then
        >&2 echo "  Failed to apply PR#${1} in dry run - already merged?"
    elif ! patch -p1 --forward --force < ${1}.patch; then
        >&2 echo "  PR#{1} failed to apply - source tree may be corrupt!"
    else
        echo "  PR#${1} applied successfully!"
        applied_prs+="${1}"
    fi
    echo
    return 0
}

# Custom kernel patches follow

# Submit PRs with edits targeting the _bottom_ of this file
# Please provide a short rationale comment for the changes made
# The apply_pr() function will not apply a patch if it
# has already been merged, or some part of it will otherwise
# not apply

# Make bcm2835-mmc compatible with swiotlb that is used on ARM64
# This resolves swiotlb buffer full errors on Wi-Fi bursts on
# Raspberry PI4 in 64-bit mode.
#apply_pr 3159 "Resolves swiotlb buffer full errors on Wi-Fi bursts in 64-bit mode."


# If any patches are applied then note it since 
# compiled kernel version will be marked as dirty.
# if (( ${#applied_prs[@]} ))
#     then
#         APPLIED_KERNEL_PATCHES=$(IFS="+"; echo "-pr${applied_prs[*]}")
#         echo $APPLIED_KERNEL_PATCHES > /tmp/APPLIED_KERNEL_PATCHES
# fi