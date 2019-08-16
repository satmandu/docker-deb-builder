#!/bin/bash

# @see http://ubuntugenius.wordpress.com/2011/01/08/ubuntu-cleanup-how-to-remove-all-unused-linux-kernel-headers-images-and-modules/
# Originally from kivisade/kernel-purge

current_kernel="$(uname -r | sed 's/\(.*\)-\([^0-9]\+\)/\1/')"
current_ver=${current_kernel/%-generic}

#Display the current running kernel version
echo "Running kernel version is: ${current_kernel}"

#Display the currently installed kernel packages which are unused
echo 'Installed and unusued kernel packages:'
select kernelVersion in $(dpkg -l 'linux-*' | sed '/^ii/!d;/libc-dev/d;/'${current_ver}'/d;s/^[^ ]* [^ ]* \([^ ]*\).*/\1/;/[0-9]/!d')
do
  #Version exists, confirm that the version is to be deleted
  read -n 1 -p "$kernelVersion exists. Are you sure [y/n]? " REPLY
  printf '\n'

  #User selected Yes, delete the kernel
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Deleting $kernelVersion" 
    dpkg -l 'linux-*' | sed '/^ii/!d;/libc-dev/d;/'${kernelVersion}'/!d;s/^[^ ]* [^ ]* \([^ ]*\).*/\1/;/[0-9]/!d' | xargs sudo apt-get -y purge 
    echo "$kernelVersion deleted"
  else
     echo 'User cancelled. Nothing deleted.'
  fi
done

#Ask the user which one they wish to delete
#read -p 'Which version do you want to remove (I.e. 4.15.0-33)? ' -r
#todelete=$REPLY


