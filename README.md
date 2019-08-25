
# Creating an ARM64 boot image for a Raspberry Pi 4B in a Ubuntu Docker container from a either a Ubuntu Bionic or Ubuntu Disco (current/dev) RPI3 boot image

(Initially adapted from project at https://github.com/tsaarni/docker-deb-builder )

## Overview

This creates a docker container to build an Ubuntu Eoan 19.10 or Ubuntu Bionic 18.04 server image for a Raspberry Pi 4B using a Ubuntu Disco 19.04 build container. This is has been run successfully (self-hosting?) with docker on a RPI 4B with 4Gb of ram to generate both kernels and images. This setup will compile a current RPI kernel, current RPI userland, get current RPI firmware, and copy them all to the ubuntu image.

## Note that this container runs in PRIVILEGED MODE.
Feel free to offer suggestions on how to make this setup safer without making the build an order of magnitude slower. :/

 ## To build an arm64 Ubuntu Raspberry Pi 4B image run the following commands:

## 1. Make sure you have a recent install of Docker. (There is no Docker Host OS version requirement.) Tested using Docker running on Ubuntu Eoan & macos Mojave, but this should also work fine in Ubuntu Disco and maybe also Ubuntu Bionic.
Installation instructions for Ubuntu: https://docs.docker.com/install/linux/docker-ce/ubuntu/

## 1.5. Some have reported that qemu-user-static needs to be installed on your HOST system before this setup works:
    sudo apt install qemu-user-static -y
(Note that this is installed in the container, and I don't know why this helps... but FYI.)


## 2. Clone Build build environment

Clone the [docker-rpi4-imagebuilder](https://github.com/satmandu/docker-rpi4-imagebuilder)
(the repository you are reading now):


    git clone https://github.com/satmandu/docker-rpi4-imagebuilder
    cd docker-rpi4-imagebuilder


## 3.  Build package from inside source directory
    git pull ; time ./build-image
    
| Ubuntu Image Built | Buid Container OS | command | comments |
| --- | --- | --- | --- |
| eoan | rolling/disco/19.04 | ```git pull ; time ./build-image``` | **DEFAULT**
| bionic | bionic/18.04 | ```git pull ; time BASE_DIST=bionic ./build-image``` | old stable|
| eoan | eoan/dev/19.10 | ```git pull ; time ./build-image -i docker-rpi4-imagebuilder-v1:19.10``` | dev/dev|

1st Build takes ~ 30 min.
2nd Build with cached kernel compile debs takes ~ 5 min.

After a successful build you will find the `eoan-preinstalled-server-arm64+raspi4.img___kernel___timestamp.lz4` 
file in your specified `output` directory (defaults to `output` ). (Failure will lead to a build_fail.log in that folder.)

Currently the images are under 700Mb compressed with xz, or about 1.3Gb compressed with lz4.
The xz images are about 50 Mb larger than the base ubuntu images.

## 4. Installing image to sd card

Use the instructions here: https://ubuntu.com/download/iot/installation-media

Example: 

```lz4cat ~/Downloads/eoan-preinstalled-server-arm64+raspi4.img.lz4 | sudo dd of=< drive address > bs=32M ```

or

```xzcat ~/Downloads/eoan-preinstalled-server-arm64+raspi4.img.xz | sudo dd of=< drive address > bs=32M ```

Note that you want to replace instances of "xzcat" with "lzcat" since this setup uses the much faster lz4 to compress the images created in the docker container.

## 1st Login
The **default login for this image is unchanged** from the ubuntu server default image: **ubuntu/ubuntu**.
Note also that the **RPI4 SHOULD Be connected to ethernet for first login**, as the ubuntu startup cloud sequence wants a connection.
After the network starts, you should be able to ssh to the IP of the RPI with username ubuntu, where you will be prompted to change the password. As the ubuntu cloud setup is not disabled, you have to wait about five minutes for login to be available.

Do setup the Time Zone using ```sudo dpkg-reconfigure tzdata``` when you first login. You can use ```sudo nmtui``` to configure the wireless network.

## Advanced Build Options

| Build Env. Variable| Syntax | What/Why |
| --- | --- | --- |
| BASE_DIST | ```BASE_DIST=bionic``` | Options are bionic or eoan |
| CFLAGS | ```CFLAGS="-mcpu=cortex-a72"``` | Good Luck. (Changing this may make your compiles fail.)|
| CLEAN_GIT | ```CLEAN_GIT=1``` | Force download all source from git. |
| JUSTDEBS | ```JUSTDEBS=1``` | Just compile kernel debs, don't rebuild image. |
| RAWIMAGE | ```RAWIMAGE=1``` | Copy out uncompressed images. |
| REBUILD | ```REBUILD=1``` | Rebuild kernel even if current version has been compiled & cached. |
| XZ | ```XZ=1``` | Use XZ to compress final disk image. |

# Example usage:
git pull ; JUSTDEBS=1 REBUILD=1 ./build-image


### Current capatiblity options on the 4Gb RPI4:

| Boot Option | How to Enable | Maximum Accessible RAM |
| --- | --- | --- |
| u-boot at /boot/firmware/kernel8.img | ```sudo cp /boot/firmware/uboot.bin /boot/firmware/kernel8.img ; sudo reboot``` | **4 Gb** (Default) | 
| uncompressed linux kernel at /boot/firmware/kernel8.img | ```sudo cp /boot/firmware/kernel8.img.nouboot /boot/firmware/kernel8.img ; sudo reboot``` | **4Gb** |

## Default is booting with u-boot just like a normal ubuntu image.

Note that the u-boot in the ubuntu package [u-boot-rpi](https://packages.ubuntu.com/eoan/u-boot-rpi) doesn't yet support the RPI. 
The u-boot here has been compiled from @agherzan's WIP u-boot [fork here](https://github.com/agherzan/u-boot/tree/ag/v2019.07-rpi4-wip).

## Resetting your build setup (useful if you're having compilation problems and suspect that you have a corrupted cache.)

1. Remove your local git cloned folder.
```rm -rf ~/docker-rpi4-imagebuilder```

2. Remove the docker cache volume this setup uses.
```docker volume rm rpi4-imagebuilder-cache```

3. Start again with the steps above.



## Note that running this repeatedly will create much container cruft.
Consider running ```docker container prune``` on your docker machine to reclaim unused space.

# Credit to:

https://jamesachambers.com/raspberry-pi-ubuntu-server-18-04-2-installation-guide/

https://blog.cloudkernels.net/posts/rpi4-64bit-image/

https://andrei.gherzan.ro/linux/raspbian-rpi-64/
https://andrei.gherzan.ro/linux/raspbian-rpi4-64/

https://github.com/sakaki-/bcm2711-kernel-bis
