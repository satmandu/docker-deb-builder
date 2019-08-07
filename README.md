
# Creating an ARM64 boot image for a Raspberry Pi 4B in a Docker container from a current/nightly Ubuntu RPI3 boot image

(Largely adapted from project at https://github.com/tsaarni/docker-deb-builder )

## Overview

This creates a docker container to build an Ubuntu 19.10 server image for a Raspberry Pi 4B using unstable/current software.
A new kernel is compiled, and current firmware is copied into the container.


### Current capatiblity options on the 4Gb RPI4:

| Boot Option | How to Enable | RAM | USB|
| --- | --- | --- | --- |
| u-boot at /boot/firmware/kernel8.img | sudo cp /boot/firmware/uboot.bin /boot/firmware/kernel8.img ; sudo reboot | 1 Gb | **Works** |
| uncompressed linux kernel at /boot/firmware/kernel8.img | sudo cp /boot/firmware/kernel8.img.nouboot /boot/firmware/kernel8.img ; sudo reboot | **4Gb** | No |
| uncompressed linux kernel at /boot/firmware/kernel8.img |  sudo cp /boot/firmware/kernel8.img.nouboot /boot/firmware/kernel8.img ; [ \`grep -cs "total_mem=" /boot/firmware/config.txt\` -gt 0 ]  && sudo sed  \'s/total_mem=*$/total_mem=3072/\' /boot/firmware/config.txt \|\| echo "total_mem=3072" \| sudo tee -a /boot/firmware/config.txt; sudo reboot | 3Gb | **Works** |



Note that there is a bug opened on this issue here: https://github.com/raspberrypi/linux/issues/3093



## Default is booting with u-boot just like a normal ubuntu image.

Note that the u-boot in the ubuntu package [u-boot-rpi](https://packages.ubuntu.com/eoan/u-boot-rpi) doesn't yet support the RPI. 
The u-boot here has been compiled from @agherzan's WIP u-boot [fork here](https://github.com/agherzan/u-boot/tree/ag/rpi4).


## Note that this container runs in PRIVILEGED MODE.
Feel free to offer suggestions on how to make this setup safer without making the build an order of magnitude slower. :/

 ## To build an Ubuntu Eoan Raspberry Pi 4B image run following commands:

## 1. Clone Build build environment

Clone the [docker-rpi4-imagebuilder](https://github.com/satmandu/docker-rpi4-imagebuilder)
(the repository you are reading now) and run the build script to see
usage:


    git clone https://github.com/satmandu/docker-rpi4-imagebuilder
    cd docker-rpi4-imagebuilder
    ./build-image
    usage: build [options...] SOURCEDIR
    Options:
      -i IMAGE  Name of the docker image (including tag) to use as package build environment.
      -o DIR    Destination directory to store output compressed image to.

## 2.  Create Docker Build container 
*(This only has to be done once every several days.)*

Build a container that will act as package build environment:

    docker build -t docker-rpi4-imagebuilder:19.10 -f Dockerfile-ubuntu-19.10 .

In this example the target is Ubuntu 19.10 but you can create and modify `Dockerfile-nnn` to match your target environment. 
(I have only tested with Ubuntu 19.10, since that is what the source image is built from.)

## 3.  Create destination directory to store the build results

    mkdir output


## 4.  Build package from inside source directory
    git pull ; NOXZ=1 time ./build-image -i docker-rpi4-imagebuilder:19.10 -o output .
    
A first build takes about 30 min on my Skylake build machine. A second build takes about 10 min due to the use of ccache if I have xz compression disabled and just use lz4 for image compression, or 25 min if I use both.

(xz compression be toggled by dropping NOXZ=1 from the command line.) 


After a successful build you will find the `eoan-preinstalled-server-arm64+raspi4.img___kernel___timestamp.lz4` 
file in your specified `output` directory. (Failure will lead to a build_fail.log in that folder.)

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

Do setup the Time Zone using ```sudo dpkg-reconfigure tzdata``` when you first login. You can use ```nmtui``` to configure the wireless network.

## Note that running this repeatedly will create much container cruft.
Consider running ```docker container prune``` on your docker machine to reclaim unused space.

# Credit to:

https://jamesachambers.com/raspberry-pi-ubuntu-server-18-04-2-installation-guide/

https://blog.cloudkernels.net/posts/rpi4-64bit-image/

https://andrei.gherzan.ro/linux/raspbian-rpi-64/
https://andrei.gherzan.ro/linux/raspbian-rpi4-64/

https://github.com/sakaki-/bcm2711-kernel-bis
