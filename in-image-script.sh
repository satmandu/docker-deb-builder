#!/bin/bash -e
mkdir -p /flag || echo "Are you sure you didn't mean to run ./build-image ?"
echo $BASHPID > /flag/main
# The above is used for, amongst other things, the tail log process.
#[[ $DEBUG ]] && export PS4='+(${BASH_SOURCE}:${LINENO}): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
[[ $DEBUG ]] && export PS4='+(${LINENO}): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
mainPID=$BASHPID

echo "mainPID=${BASHPID}" >> /tmp/env.txt


# Set to "/bin/bash -e" only when debugging.
# This script is executed within the container as root. The resulting image &
# logs are written to /output after a succesful build.  These directories are 
# mounted as docker volumes to allow files to be exchanged between the host and 
# the container.

#kernel_branch=rpi-4.19.y
#kernelgitrepo="https://github.com/raspberrypi/linux.git"
#branch=bcm2711-initial-v5.2
#kernelgitrepo="https://github.com/lategoodbye/rpi-zero.git"
# This should be the image we want to modify.
#base_url="http://cdimage.ubuntu.com/ubuntu-server/daily-preinstalled/current/"
#base_image="${BASE_DIST}-preinstalled-server-arm64+raspi3.img.xz"
base_image_url="${base_url}/${base_image}"
# This is the base name of the image we are creating.
new_image="${BASE_DIST}-preinstalled-server-arm64+raspi4"
# Comment out the following if apt is throwing errors silently.
# Note that these only work for the chroot commands.
silence_apt_flags="-o Dpkg::Use-Pty=0 -qq < /dev/null > /dev/null "

if [ "${BUILDHOST_ARCH}" = "aarch64" ]
    then
        unset BUILDNATIVE
    else
        BUILDNATIVE=1
fi

image_compressors=("lz4")
[[ $XZ ]] && image_compressors=("lz4" "xz")

# Quick build shell exit script
cat <<-EOF> /usr/bin/killme
	#!/bin/bash
	pkill -9 -F /flag/main
EOF
chmod +x /usr/bin/killme

#DEBUG=1
#GIT_DISCOVERY_ACROSS_FILESYSTEM=1

# Needed for display
shopt -s checkwinsize 
#size=$(stty size) 
#lines=${size% *}
#columns=${size#* }
#echo "COLS: $COLS COLUMNS: $COLUMNS" > /tmp/columns
#env > /tmp/env
COLUMNS="${COLS:-80}"

# Set Time Stamp
now=$(date +"%m_%d_%Y_%H%M%Z")

# Create debug output folder.
#[[ $DEBUG ]] && ( mkdir -p /output/"${now}"/ ; chown "$USER":"$GROUP" /output/"${now}"/ )
#[[ $DEBUG ]] && chown $USER:$GROUP /output/${now}/

# Logging Setup
TMPLOG=/tmp/build.log
touch $TMPLOG
exec 3>&1 4>&2
trap 'exec 2>&4 1>&3' 0 1 2 3
exec 1>$TMPLOG 2>&1

# Use ccache.
PATH=/usr/lib/ccache:$PATH
CCACHE_DIR=/cache/ccache
mkdir -p ${CCACHE_DIR}
# Change these settings if you need them to be different.
ccache -M 0 > /dev/null
ccache -F 0 > /dev/null
# Show ccache stats.
echo "Build ccache stats:"
ccache -s

# Default flags as per gentoo sources and also:
# https://community.arm.com/developer/tools-software/tools/b/tools-software-ides-blog/posts/compiler-flags-across-architectures-march-mtune-and-mcpu
# Note how many of these fail to work with compiling the kernel!
#DEFAULTCFLAGS="-mcpu=cortex-a72 -ftree-vectorize -O2 -pipe -fomit-frame-pointer"
#DEFAULTCFLAGS="-mcpu=cortex-a72 -ftree-vectorize -pipe -fomit-frame-pointer"
#DEFAULTCFLAGS="-mcpu=cortex-a72 -march=armv8-a+crc"
DEFAULTCFLAGS="-mcpu=cortex-a72"
CFLAGS=${CFLAGS:-${DEFAULTCFLAGS}}
export CXXFLAGS="${CFLAGS}"

# These environment variables are set at container invocation.
# Create work directory.
#workdir=/build/source
mkdir -p "${workdir}"
#cp -a /source-ro/ ${workdir}
# Source cache is on the cache volume.
#src_cache=/cache/src_cache
mkdir -p "${src_cache}"
# Apt cache is on the cache volume.
#apt_cache=/cache/apt_cache
# This is needed or apt has issues.
mkdir -p "${apt_cache}"/partial 

# Set git hash digits. For some reason this can vary between containers.
git config --global core.abbrev 9

# Set this once:
nprocs=$(($(nproc) + 1))

# Set Spinner index to avoid conflicts with multiple instances.
spinner_idx=0
declare -a spinner_proc_array

# echo "Starting local container software installs."
apt-get -o dir::cache::archives="${apt_cache}" install checkinstall -y &>> /tmp/main.install.log 
# [[ ! $JUSTDEBS ]] && apt-get -o dir::cache::archives="${apt_cache}" install lsof -y &>> /tmp/main.install.log 
# [[ ! $JUSTDEBS ]] && apt-get -o dir::cache::archives="${apt_cache}" install xdelta3 -y &>> /tmp/main.install.log 
# [[ ! $JUSTDEBS ]] && apt-get -o dir::cache::archives="${apt_cache}" install e2fsprogs -y &>> /tmp/main.install.log 
# [[ ! $JUSTDEBS ]] && apt-get -o dir::cache::archives="${apt_cache}" install qemu-user-static -y &>> /tmp/main.install.log 
# [[ ! $JUSTDEBS ]] && apt-get -o dir::cache::archives="${apt_cache}" install dosfstools -y &>> /tmp/main.install.log 
# [[ ! $JUSTDEBS ]] && apt-get -o dir::cache::archives="${apt_cache}" install libc6-arm64-cross -y &>> /tmp/main.install.log 
# [[ ! $JUSTDEBS ]] && apt-get -o dir::cache::archives="${apt_cache}" install pv -y &>> /tmp/main.install.log 
# [[ ! $JUSTDEBS ]] && apt-get -o dir::cache::archives="${apt_cache}" install u-boot-tools -y &>> /tmp/main.install.log 
# apt-get -o dir::cache::archives="${apt_cache}" install vim -y &>> /tmp/main.install.log 


echo -e "Performing cache volume apt autoclean.\n\r"
apt-get -o dir::cache::archives="${apt_cache}" autoclean -y -qq &>> /tmp/main.install.log 

# Utility Functions

function ragequit {
    export PS4='+(${BASH_SOURCE}:${LINENO}): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    echo "ragequit:  1.${FUNCNAME[1]} 2.${FUNCNAME[2]} 3.${FUNCNAME[3]} 4.${FUNCNAME[4]}" >> /tmp/build.log
    echo pkill -F /flag/main
}

function abspath {
    cd "${1}" && pwd
}

# via https://serverfault.com/a/905345
PrintLog(){
  local information="${1}"
  local logFile="${2}"
#[[ $DEBUG ]] && echo "Log: ${logFile} ${FUNCNAME[0]} ${FUNCNAME[1]} ${FUNCNAME[2]} ${FUNCNAME[3]}"
  [[ ! -e "${logFile}" ]] && (mkdir -p "$(dirname ${logFile})" &>/dev/null || true) && \
  (touch "${logFile}" &> /tmp/PrintLog || true)
  [[ -e "${logFile}" ]] && echo "${information}" | ts >> "${logFile}"
}

# Via https://superuser.com/a/917073
wait_file() {
    local file="${1}"
#   local file="${1}"; shift
   [[ -e "${file}" ]] && return
#   local wait_seconds="${1:-100000}"; shift # 100000 seconds as default timeout
    PrintLog "${FUNCNAME[1]}->file: ${file}" /tmp/wait.log
    [[ -f "${file}" ]] && (PrintLog "${file} found" /tmp/wait_file.log && return )
    timeout 100000 tail -f -s 1 --retry "${file}" 2> /dev/null | ( grep -q -m1 ""  && pkill -P $$ -x tail) || true
    [[ -f "${file}" ]] && PrintLog "${file} found" /tmp/wait_file.log
}

# Via https://unix.stackexchange.com/a/163819
occur() {
        while case "$1" in (*"$2"*) set -- \
        "${1#*"$2"}" "$2" "${3:-0}" "$((${4:-0}+1))";;
        (*) return "$((${4:-0}<${3:-1}))";;esac
        do : "${_occur:+$((_occur=$4))}";done
}

spinnerwait () {
((spinner_idx++))
[[ $DEBUG ]] && echo "Spinner_idx: ${spinner_idx}"
startfunc
    local spinner_proc_file=${spinner_proc_array[${spinner_idx}]}
    echo ${spinner_proc_array[*]}
    local spin_target=${1}
    #[[ $DEBUG ]] && echo "FUNCNAME:  1.${FUNCNAME[1]} 2.${FUNCNAME[2]} 3.${FUNCNAME[3]} 4.${FUNCNAME[4]}"
    local spin_target_file
    [[ -z ${spin_target_file} ]] && spin_target_file=$(find /flag -regextype egrep \( -regex ".*strt_([A-Za-z0-9]{3})_${1}" -o -regex ".*done_([A-Za-z0-9]{3})_${1}" \) -print)
    until [[ -n ${spin_target_file} ]]; do
        spin_target_file=$(find /flag -regextype egrep \( -regex ".*strt_([A-Za-z0-9]{3})_${spin_target}" -o -regex ".*done_([A-Za-z0-9]{3})_${spin_target}" \) -print)
        sleep $(echo "scale=2; .5+$(( RANDOM % 50 ))/100" | bc)
    done
    local spin_target_file_base_raw=$(basename "${spin_target_file}")
    local spin_target_file_base=${spin_target_file_base_raw:5}
        PrintLog "start.${1}" /tmp/spinnerwait.log
        [[ -e "/flag/done_${spin_target_file_base}" ]] && return
        wait_file "/flag/strt_${spin_target_file_base}" || \
        PrintLog "${1} didn't start in $? seconds." /tmp/spinnerwait.log
        local job_id=$(< ${spin_target_file})
        [[ ${job_id} = ${mainPID} ]] && return
        (
        flock 201 
        echo "spinner_proc_file: ${spinner_proc_file}" >> /tmp/spinnerwait.log
        echo "job_id: ${job_id}" >> /tmp/spinnerwait.log
        echo "${job_id}" > "${spinner_proc_file}" |& tee -a /tmp/spinnerwait.log
        PrintLog "Start wait for ${1}:${job_id} end." /tmp/spinnerwait.log
        tput sc
        while (pgrep -cxP "${job_id}" &>/dev/null)
        do for s in / - \\ \|
            do 
            tput rc
            printf "%${COLUMNS}s\r" "${1} .$s"
            sleep .06
            done
        done
        PrintLog "${1}:${job_id} done." /tmp/spinnerwait.log
        ) 201>/flag/spinnerwait
        PrintLog "${1}:${job_id} pgrep exit:$(pgrep -cxP "${job_id}")" /tmp/spinnerwait.log
        PrintLog "${1}:${job_id} $(pstree -p)" /tmp/spinnerwait.log
endfunc

}

waitfor () {
    local wait_target=${1}
    local silence=${2:-0}
    #[[ $DEBUG ]] && echo "FUNCNAME:  1.${FUNCNAME[1]} 2.${FUNCNAME[2]} 3.${FUNCNAME[3]} 4.${FUNCNAME[4]}"
    local level_a=${FUNCNAME[1]:-main}
#     local level_b=${FUNCNAME[2]:-_}
#     local level_c=${FUNCNAME[3]:-_}
#     local level_d=${FUNCNAME[4]:-_}
    #local proc_base=${level_a}.${level_b}.${level_c}.${level_d}
    #[[ $level_d = "main" ]] && proc_base=${level_a}.${level_b}.${level_c}
    #[[ $level_c = "main" ]] && proc_base=${level_a}.${level_b}
    #[[ $level_b = "main" ]] && proc_base=${level_a}
    #local proc_name=${FUNCNAME[1]:-main}
    #local proc_base=${level_a}
    local proc_name=${level_a}
    echo ${BASHPID} >> /flag/waiting_${proc_name}_for_${wait_target}
[[ $silence = "0" ]] && printf "%${COLUMNS}s\r\n\r" "${proc_name} waits for: ${wait_target} [/] "
    local wait_proc=
    until [[ -n ${wait_proc} ]]; do
        wait_proc=$(find /flag -regextype egrep \( -regex ".*strt_([A-Za-z0-9]{3})_${wait_target}" -o -regex ".*done_([A-Za-z0-9]{3})_${wait_target}" \) -print)
        sleep $(echo "scale=2; .5+$(( RANDOM % 50 ))/100" | bc)
    done

    local wait_proc_raw=$(basename "${wait_proc}")
    local wait_proc_base=${wait_proc_raw:5}
    echo ${BASHPID} >> /flag/waiting_${proc_name}_for_${wait_proc_base}
    echo ${wait_proc} >> /flag/waiting_${proc_name}_for_${wait_proc_base}
    echo ${wait_proc} >> /flag/waiting_${proc_name}_for_${wait_target}
    #[[ -z ${proc_name} ]] && proc_name=main
    local wait_file="/flag/done_${wait_proc_base}"
    [[ ! -f ${wait_file} ]] && wait_file ${wait_file}
[[ $silence = "0" ]] && printf "%${COLUMNS}s\r\n\r" "${proc_name} noticed: ${wait_target} [X] " && \
    rm -f /flag/waiting_${proc_name}_for_${wait_proc_base}
    rm -f /flag/waiting_${proc_name}_for_${wait_target}
}


startfunc () {
. /tmp/env.txt
    #[[ $DEBUG ]] && echo "FUNCNAME:  1.${FUNCNAME[1]} 2.${FUNCNAME[2]} 3.${FUNCNAME[3]} 4.${FUNCNAME[4]}"
    local level_a=${FUNCNAME[1]:-main}
    local level_b=${FUNCNAME[2]:-_}
    local level_c=${FUNCNAME[3]:-_}
    local level_d=${FUNCNAME[4]:-_}
    local proc_base=${level_a}.${level_b}.${level_c}.${level_d}
    #[[ $level_d = "main" ]] && proc_base=${level_a}.${level_b}.${level_c}
    [[ $level_d = "main" ]] && proc_base=${level_a}
    #[[ $level_c = "main" ]] && proc_base=${level_a}.${level_b}
    [[ $level_c = "main" ]] && proc_base=${level_a}
    [[ $level_b = "main" ]] && proc_base=${level_a}
    local verbose_proc=${proc_base}
    [[ $level_d = "main" ]] && verbose_proc=${level_a}.${level_b}.${level_c}
    [[ $level_c = "main" ]] && verbose_proc=${level_a}.${level_b}

    local proc_file=$(mktemp /flag/strt_XXX_${proc_base})
    echo ${BASHPID} > "${proc_file}"
    printf "%${COLUMNS}s\n" "Started: ${verbose_proc} [ ] "
    [[ $DEBUG ]] && echo "${proc_file}"
    occur "${proc_base}" "spinnerwait" "1" && echo "count: $_occur"
    occur "${proc_base}" "spinnerwait" "1" && ( spinner_proc_array[${spinner_idx}]="${proc_file}") || true
}

endfunc () {
. /tmp/env.txt
    caller=${1}
    local level_a=${FUNCNAME[1]:-main}
    local level_b=${FUNCNAME[2]:-_}
    local level_c=${FUNCNAME[3]:-_}
    local level_d=${FUNCNAME[4]:-_}
    local proc_base=${level_a}.${level_b}.${level_c}.${level_d}
    [[ $level_d = "main" ]] && proc_base=${level_a}
    [[ $level_c = "main" ]] && proc_base=${level_a}
    [[ $level_b = "main" ]] && proc_base=${level_a}
    local verbose_proc=${proc_base}
    [[ $level_d = "main" ]] && verbose_proc=${level_a}.${level_b}.${level_c}
    [[ $level_c = "main" ]] && verbose_proc=${level_a}.${level_b}

    local parent_pid=${BASHPID}
    local proc_file=$(grep -lw ${parent_pid} --exclude=waiting* /flag/* 2>/dev/null || true)
    #local proc_file=$(echo "${proc_file_raw}" | head -n 1 | awk 'NR == 1{print $1}')
    #local proc_file=$(echo ${proc_file_raw%% *}| grep -v waiting)
    [[ ${proc_file} = "/flag/main" ]] && proc_file=$(find /flag -regextype egrep \( -regex ".*strt_([A-Za-z0-9]{3})_${caller}" -o -regex ".*done_([A-Za-z0-9]{3})_${caller}" \) -print)
    [[ "$(cat ${proc_file})" = "$(cat /flag/main)" ]] && proc_file=$(find /flag -regextype egrep \( -regex ".*strt_([A-Za-z0-9]{3})_${caller}" -o -regex ".*done_([A-Za-z0-9]{3})_${caller}" \) -print)
    [[ -z ${proc_file} ]] && proc_file=$(find /flag -regextype egrep \( -regex ".*strt_([A-Za-z0-9]{3})_${caller}" -o -regex ".*done_([A-Za-z0-9]{3})_${caller}" \) -print)
    local proc_file_base_raw=$(basename "${proc_file}")
    local proc_file_base=${proc_file_base_raw:5}
   if [[ ! $DEBUG ]]
        then 
        if test -n "$(find /tmp -maxdepth 1 ! -name 'spinnerwait.*' -name ${proc_file_base:4}.*.log -print -quit)"
            then
                rm /tmp/${proc_file_base:4}*.log || true
        fi
    fi
    mv -f /flag/${proc_file_base_raw:?} /flag/done_${proc_file_base}
    printf "%${COLUMNS}s\n" "Done: ${verbose_proc} [X] "
}



git_remote_check () {
    local git_base="$1"
    local git_branch="$2"
    [ -n "$2" ] || git_branch="master"
    local git_output=$(git ls-remote "${git_base}" refs/heads/${git_branch})
    [ -n "${git_output}" ] || git_output=$(git ls-remote "${git_base}" refs/tags/${git_branch})
    [ -n "${git_output}" ] || git_output=$(git ls-remote "${git_base}" "${git_branch}")
    [ -n "${git_output}" ] || git_output="Git Remote Error!"
    local git_hash
    local discard 
    read -r git_hash discard< <(echo "${git_output}")
    echo "${git_hash}"
}

local_check () {
    local git_path="$1"
    local git_branch="$2"
    [ -n "$2" ] || git_branch="HEAD"
    local git_output=$(git -C "${git_path}" rev-parse ${git_branch} 2>/dev/null)
    echo "${git_output}"
}


arbitrary_wait_here () {
    # To stop here "rm /flag/done.ok_to_continue_after_here".
    # Arbitrary build pause for debugging
    if [ ! -f /flag/done.ok_to_continue_after_here ]; then
        echo "** Build Paused. **"
        echo 'Type in "echo 1 > /flag/done.ok_to_continue_after_here"'
        echo "in a shell into this container to continue."
    fi 
    wait_file "/flag/done.ok_to_continue_after_here"
}


# Standalone get with git function
# get_software_src () {
# startfunc
# 
#     git_get "gitrepo" "local_path" "git_branch"
# 
# endfunc
# }

git_get () {
startfunc
    local proc_name=${FUNCNAME[1]}
    [[ -z ${proc_name} ]] && proc_name=main
    local git_repo="${1}"
    local local_path="${2}"
    local git_branch="${3}"
    [ -n "${3}" ] || git_branch="master"
    PrintLog "proc_name: ${proc_name}, git_repo: ${git_repo}, local_path: ${local_path}, git_branch: ${git_branch}" /tmp/git_get.log
    mkdir -p "${src_cache}/${local_path}"
    mkdir -p "${workdir}/${local_path}"
    
    local remote_git=$(git_remote_check "${git_repo}" "${git_branch}")
    local local_git=$(local_check "${src_cache}/${local_path}" "${git_branch}")
    
    [ -z ${git_branch} ] && git_extra_flags= || git_extra_flags=" -b ${git_branch} "
    local git_flags=" --quiet --depth=1 "
    local clone_flags=" ${git_repo} $git_extra_flags "
    local pull_flags="origin/${git_branch}"
    PrintLog "${proc_name}->remote hash: ${remote_git}, local hash: ${local_git}" /tmp/git_get.log
    if [ ! "${remote_git}" = "${local_git}" ] || [[ $CLEAN_GIT ]] 
        then
            PrintLog "proc_name: ${proc_name}. Git local/remote hash ! match." /tmp/git_get.log
            # Does the local repo even exist?
            if [[ ! -d "${src_cache}/${local_path}/.git" ]] || [[ $CLEAN_GIT ]]  
                then
                    PrintLog "proc_name: ${proc_name}-> recreate." /tmp/git_get.log
                    recreate_git "${git_repo}" "${local_path}" ${git_branch}
            fi
            # Is the requested branch the same as the local saved branch?
            local local_branch=
            local local_branch=$(git -C ${src_cache}/${local_path} \
            rev-parse --abbrev-ref HEAD || true)
            # Set HEAD = master
            [[ "${local_branch}" = "HEAD" ]] && local_branch="master"
            if [[ "${local_branch}" != "${git_branch}" ]]
                then 
                    echo "Kernel git branch mismatch!"
                    printf "%${COLUMNS}s\n" "${proc_name} refreshing cache files from git."
                    mkdir -p "${src_cache}/${local_path}" && cd "${src_cache}/${local_path}" || ragequit
                    # Just recreate_git always
                    # git checkout ${git_branch} || recreate_git ${git_repo} \
                    #${local_path} ${git_branch}
                    recreate_git ${git_repo} ${local_path} ${git_branch}
                else
                    echo -e "${proc_name}\nremote hash: \
                    ${remote_git}\nlocal hash:${local_git}\n"
                    printf "%${COLUMNS}s\n" "${proc_name} refreshing cache files from git."
            fi
            
            
            # sync to local branch
            mkdir -p "${src_cache}/${local_path}" && cd "${src_cache}/${local_path}" || ragequit
            # Recreate in lieu of syncing git.
            #git fetch --all ${git_flags} &>> /tmp/${proc_name}.git.log || true
            #git reset --hard $pull_flags --quiet 2>> /tmp/${proc_name}.git.log
            recreate_git ${git_repo} ${local_path} ${git_branch}
        else
            echo -e "${proc_name} git info:\nremote hash: ${remote_git}\n local hash: \
${local_git}\n\r${proc_name} getting files from cache volume. 😎\n"
    fi
    cd "${src_cache}"/"${local_path}" || ragequit
    last_commit=$(git log --graph \
    --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) \
%C(bold blue)<%an>%Creset' --abbrev-commit -2 \
    --quiet 2> /dev/null)
    echo -e "*${proc_name} Last Git Commits:\n$last_commit\n"
    rsync -a "${src_cache}/${local_path}" "${workdir}"/
endfunc
}

recreate_git () {
startfunc
    local git_repo="$1"
    local local_path="$2"
    local git_branch="$3"
PrintLog "recreate: ${FUNCNAME[2]}, git_repo: ${git_repo}, local_path: ${local_path}, git_branch: ${git_branch}" /tmp/git_get.log
    #local git_flags=" --quiet --depth=1 "
    local git_flags=" --depth=1 "
    local git_extra_flags=" -b ${git_branch} "
    local clone_flags=" ${git_repo} $git_extra_flags "
    rm -rf "${src_cache:?}/${local_path}" &>> /tmp/"${FUNCNAME[2]}".git.log
    cd "${src_cache}" &>> /tmp/"${FUNCNAME[2]}".git.log || ragequit
    git clone ${git_flags} $clone_flags ${local_path} \
    &>> /tmp/"${FUNCNAME[2]}".git.log 
endfunc
}

mv_arch () {
startfunc
        echo Replacing "${1}" with "${1}":"${2}"-cross.
        local dest_arch=${2}
        local dest_arch_prefix="${dest_arch}-linux-gnu-"
        local host_arch_prefix="${BUILDHOST_ARCH}-linux-gnu-"
        local file_out=$(file /usr/bin/"${1}")
        # Exit if dest arch file isn't available.
        [[ ! -f /usr/bin/${dest_arch_prefix}${1} ]] && PrintLog "Missing dest arch ${dest_arch_prefix}${1}" /tmp/compiler_setup.install.log && ragequit
        # If host arch backup file isn't available make backup.
        # This doesn't dereference symlinks!
        [[ ! -f /usr/bin/${host_arch_prefix}${1} && $(echo "${file_out}" | grep -m1 "${BUILDHOST_ARCH}") ]] && (
         cp /usr/bin/"${1}" /usr/bin/"${host_arch_prefix}""${1}"
         )
        if [[ $(echo "${file_out}" | grep -m1 "symbolic") ]]
            then
            rm /usr/bin/"${1}" && ln -s /usr/bin/"${dest_arch_prefix}""${1}" /usr/bin/"${1}"
        elif [[ -f /usr/bin/${dest_arch_prefix}${1} ]]
            then
            #cp ${dest_arch_prefix}${1} ${1}
            update-alternatives --install /usr/bin/"${1}" "${1}" /usr/bin/"${dest_arch_prefix}""${1}" 10
        fi
endfunc
}

# Main functions

utility_scripts () {
startfunc
. /tmp/env.txt
# Apt concurrency manager wrapper via
# https://askubuntu.com/posts/375031/revisions
cat <<'EOF'> /usr/bin/chroot-apt-wrapper
#!/bin/bash

i=0
tput sc
while fuser /mnt/var/lib/dpkg/lock >/dev/null 2>&1 ; do
    case $(($i % 4)) in
        0 ) j="-" ;;
        1 ) j="\\" ;;
        2 ) j="|" ;;
        3 ) j="/" ;;
    esac
    tput rc
    echo -en "\r[$j] Waiting for other apt instances to finish..." 
    sleep 0.5
    ((i=i+1))
done 

/usr/bin/apt-get "$@"
EOF
chmod +x /usr/bin/chroot-apt-wrapper

cat <<'EOF'> /usr/bin/chroot-dpkg-wrapper
#!/bin/bash

i=0
tput sc
while fuser /mnt/var/lib/dpkg/lock >/dev/null 2>&1 ; do
    case $(($i % 4)) in
        0 ) j="-" ;;
        1 ) j="\\" ;;
        2 ) j="|" ;;
        3 ) j="/" ;;
    esac
    tput rc
    echo -en "\r[$j] Waiting for other dpkg instances to finish..." 
    sleep 0.5
    ((i=i+1))
done 

/usr/bin/dpkg "$@"
EOF
chmod +x /usr/bin/chroot-dpkg-wrapper

waitfor "image_mount"
    # Apt concurrency manager wrapper via
    # https://askubuntu.com/posts/375031/revisions
    mkdir -p /mnt/usr/local/bin
    cat <<'EOF'> /mnt/usr/local/bin/chroot-apt-wrapper
#!/bin/bash

i=0
tput sc
while fuser /var/lib/dpkg/lock >/dev/null 2>&1 ; do
    case $(($i % 4)) in
        0 ) j="-" ;;
        1 ) j="\\" ;;
        2 ) j="|" ;;
        3 ) j="/" ;;
    esac
    tput rc
    echo -en "\r[$j] Waiting for other apt instances to finish..." 
    sleep 0.5
    ((i=i+1))
done 

/usr/bin/apt-get "$@"
EOF
    chmod +x /mnt/usr/local/bin/chroot-apt-wrapper

cat <<'EOF'> /mnt/usr/local/bin/chroot-dpkg-wrapper
#!/bin/bash

i=0
tput sc
while fuser /var/lib/dpkg/lock >/dev/null 2>&1 ; do
    case $(($i % 4)) in
        0 ) j="-" ;;
        1 ) j="\\" ;;
        2 ) j="|" ;;
        3 ) j="/" ;;
    esac
    tput rc
    echo -en "\r[$j] Waiting for other dpkg instances to finish..." 
    sleep 0.5
    ((i=i+1))
done 

/usr/bin/dpkg "$@"
EOF
chmod +x /mnt/usr/local/bin/chroot-dpkg-wrapper

endfunc
}

compiler_setup () {
startfunc

PrintLog "setup multiarch"  /tmp/"${FUNCNAME[0]}".install.log
    [[ $BUILDNATIVE ]] && (
    mv_arch ar aarch64 &>> /tmp/"${FUNCNAME[0]}".install.log 
    )
    [[ $BUILDNATIVE ]] && (
    mv_arch ld.bfd aarch64 &>> /tmp/"${FUNCNAME[0]}".install.log 
    )
    [[ $BUILDNATIVE ]] && (
    mv_arch ld aarch64 &>> /tmp/"${FUNCNAME[0]}".install.log 
    )
    [[ $BUILDNATIVE ]] && [[ ${BASE_DIST} = "bionic" ]] && (
    mv_arch gcc-8 aarch64 &>> /tmp/"${FUNCNAME[0]}".install.log || true
    )
    [[ $BUILDNATIVE ]] && [[ ${BASE_DIST} = "bionic" ]] && (
    mv_arch g++-8 aarch64 &>> /tmp/"${FUNCNAME[0]}".install.log || true
    )
    [[ $BUILDNATIVE ]] && [[ ${BASE_DIST} = "bionic" ]] && (
    mv_arch cpp-8 aarch64 &>> /tmp/"${FUNCNAME[0]}".install.log || true
    )
    [[ $BUILDNATIVE ]] && [[ ! ${BASE_DIST} = "bionic" ]] && (
    mv_arch gcc-9 aarch64 &>> /tmp/"${FUNCNAME[0]}".install.log || true
    )
    [[ $BUILDNATIVE ]] && [[ ! ${BASE_DIST} = "bionic" ]] && (
    mv_arch g++-9 aarch64 &>> /tmp/"${FUNCNAME[0]}".install.log || true
    )
    [[ $BUILDNATIVE ]] && [[ ! ${BASE_DIST} = "bionic" ]] && (
    mv_arch cpp-9 aarch64 &>> /tmp/"${FUNCNAME[0]}".install.log || true
    )

endfunc
}




download_base_image () {
startfunc
    echo "* Downloading ${base_image} ."
    #wget_fail=0
    #wget -nv ${base_image_url} -O ${base_image} || wget_fail=1
    #curl_fail=0
    curl -o "$base_image_url" "${base_image}"
endfunc
}

base_image_check () {
startfunc
    echo "* Checking for downloaded ${base_image} ."
    cd "${workdir}" || ragequit
    if [ ! -f /"${base_image}" ]; then
        download_base_image
    else
        echo "* Downloaded ${base_image} exists."
    fi
    # Symlink existing image
    if [ ! -f "${workdir}"/"${base_image}" ]; then 
        ln -s /"$base_image" "${workdir}"/
    fi   
endfunc ${BASHPID}
}

image_extract () {
startfunc 
    waitfor "base_image_check"

    if [[ -f "/source-ro/${base_image%.xz}" ]] 
        then
            cp "/source-ro/${base_image%.xz}" "${workdir}"/"$new_image".img
        else
            local size
            local filename   
            echo "* Extracting: ${base_image} to ${new_image}.img"
            read -r size filename < <(ls -sH "${workdir}"/"${base_image}")
            pvcmd="pv -s ${size} -cfperb -N "xzcat:${base_image}" ${workdir}/$base_image"
            echo "$pvcmd"
            $pvcmd | xzcat > "${workdir}"/"$new_image".img
    fi

endfunc
}

image_mount () {
startfunc 
    waitfor "image_extract"
. /tmp/env.txt
    [[ -f "/output/loop_device" ]] && ( old_loop_device=$(< /output/loop_device) ; \
    dmsetup remove -f /dev/mapper/"${old_loop_device}"p2 &> /dev/null || true; \
    dmsetup remove -f /dev/mapper/"${old_loop_device}"p1 &> /dev/null || true; \
    losetup -d /dev/"${old_loop_device}" &> /dev/null || true)
    #echo "* Increasing image size by 200M"
    #dd if=/dev/zero bs=1M count=200 >> ${workdir}/$new_image.img
    echo "* Clearing existing loopback mounts."
    # This is dangerous as this may not be the relevant loop device.
    #losetup -d /dev/loop0 &>/dev/null || true
    #dmsetup remove_all
    dmsetup info
    losetup -a
    cd "${workdir}" || ragequit
    echo "* Mounting: ${new_image}.img"
    
    loop_device=$(kpartx -avs "${new_image}".img \
    | sed -n 's/\(^.*map\ \)// ; s/p1\ (.*//p')
    echo "$loop_device" >> /tmp/loop_device
    echo "$loop_device" > /output/loop_device
    #e2fsck -f /dev/loop0p2
    #resize2fs /dev/loop0p2
    
    # To stop here "rm /flag/done.ok_to_continue_after_mount_image".
    if [ ! -f /flag/done.ok_to_continue_after_mount_image ]; then
        echo "** Image mount done & container paused. **"
        echo 'Type in "echo 1 > /flag/done.ok_to_continue_after_mount_image"'
        echo "in a shell into this container to continue."
    fi 
    wait_file "/flag/done.ok_to_continue_after_mount_image"
    
    mount /dev/mapper/"${loop_device}"p2 /mnt
    mount /dev/mapper/"${loop_device}"p1 /mnt/boot/firmware
    
    # Ubuntu after bionic symlinks /lib to /usr/lib
    if [[ -L "/mnt/lib" && -d "/mnt/lib" ]]
    then
        MNTLIBPATH="/mnt/usr/lib"
    else
        MNTLIBPATH="/mnt/lib"
    fi
    echo "MNTLIBPATH=${MNTLIBPATH}" >> /tmp/env.txt
    # Guestmount is at least an order of magnitude slower than using loopback device.
    #guestmount -a ${new_image}.img -m /dev/sda2 -m /dev/sda1:/boot/firmware --rw /mnt -o dev
    
endfunc
}

arm64_chroot_setup () {
startfunc
    waitfor "image_mount"
. /tmp/env.txt
    echo "* Setup ARM64 chroot"
    cp /usr/bin/qemu-aarch64-static /mnt/usr/bin
    

    mount -t proc proc     /mnt/proc/
#    mount -t sysfs sys     /mnt/sys/
#    mount -o bind /dev     /mnt/dev/
    mount -o bind /dev/pts /mnt/dev/pts
    mount --bind "${apt_cache}" /mnt/var/cache/apt
 #   chmod -R 777 /mnt/var/lib/apt/
 #   setfacl -R -m u:_apt:rwx /mnt/var/lib/apt/ 
    mkdir -p /mnt/ccache || ls -aFl /mnt
    mount --bind $CCACHE_DIR /mnt/ccache
    mount --bind /run /mnt/run
    mkdir -p /run/systemd/resolve
    cp /etc/resolv.conf /run/systemd/resolve/stub-resolv.conf
    rsync -avh --devices --specials /run/systemd/resolve /mnt/run/systemd > /dev/null
    
    
    mkdir -p /mnt/build
    mount -o bind /build /mnt/build
    echo "deb http://ports.ubuntu.com/ubuntu-ports eoan-proposed restricted main multiverse universe" >> /mnt/etc/apt/sources.list
    echo "deb-src http://ports.ubuntu.com/ubuntu-ports eoan-proposed restricted main multiverse universe" >> /mnt/etc/apt/sources.list
    echo "* ARM64 chroot setup is complete."  
    image_apt_installs &
[[ $DEBUG ]] && spinnerwait image_apt_installs
endfunc
}

image_apt_installs () {
startfunc  
        waitfor "utility_scripts"
        waitfor "added_scripts"
. /tmp/env.txt
        # Following removed since calling from arm64_chroot_setup
        #waitfor "arm64_chroot_setup"
    echo "* Starting apt update."
    chroot-apt-wrapper -o Dir=/mnt -o APT::Architecture=arm64 \
    update &>> /tmp/"${FUNCNAME[0]}".install.log | grep packages | cut -d '.' -f 1  || true
    echo "* Apt update done."
    echo "* Downloading software for apt upgrade."
    chroot-apt-wrapper -o Dir=/mnt -o APT::Architecture=arm64 \
    -o dir::cache::archives="${apt_cache}" \
    upgrade -d -y &>> /tmp/"${FUNCNAME[0]}".install.log || true
    echo "* Apt upgrade download done."
    echo "* Downloading wifi & networking tools."
    chroot-apt-wrapper -o Dir=/mnt -o APT::Architecture=arm64 \
    -o dir::cache::archives="${apt_cache}" \
    -d install network-manager wireless-tools wireless-regdb crda \
    net-tools rng-tools apt-transport-https \
    -qq &>> /tmp/"${FUNCNAME[0]}".install.log || true
    # This setup DOES get around the issues with kernel
    # module support binaries built in amd64 instead of arm64.
    # This happend for instance with Ubuntu Mainline kernel builds.
    #echo "* Downloading qemu-user-static"
    # qemu-user-binfmt needs to be installed after reboot though otherwise there 
    # are container problems.
    chroot-apt-wrapper -o Dir=/mnt -o APT::Architecture=arm64 \
    -o dir::cache::archives="${apt_cache}" \
    -d install  \
    qemu-user qemu libc6-amd64-cross -qq &>> /tmp/"${FUNCNAME[0]}".install.log || true
    chroot /mnt /bin/bash -c "/usr/local/bin/chroot-apt-wrapper install -qq \
    --no-install-recommends \
    qemu-user qemu libc6-amd64-cross" &>> /tmp/"${FUNCNAME[0]}".install.log || true
    # These steps needed to allow x86_64 kernel programs to allow module installation.
    chroot /mnt /bin/bash -c "ln -rsf /usr/x86_64-linux-gnu/lib64 /lib64 || true"
    chroot /mnt /bin/bash -c "ln -rsf /usr/x86_64-linux-gnu/lib /lib/x86_64-linux-gnu || true"
    

    echo "* Apt upgrading image using native qemu chroot."
    #echo "* There may be some errors here..." 
    [[ ! $(file /mnt/etc/apt/apt.conf.d/01autoremove-kernels | awk '{print $2}') = "ASCII" ]] && (chroot /mnt /bin/bash -c "/etc/kernel/postinst.d/apt-auto-removal" || true )
    chroot /mnt /bin/bash -c "/usr/local/bin/chroot-apt-wrapper remove \
    linux-image-raspi2 linux-image*-raspi2 linux-modules*-raspi2 \
    linux-headers*-raspi2 linux-raspi2-headers* -y --purge" \
    &>> /tmp/"${FUNCNAME[0]}".install.log || true
    [[ ! $(file /mnt/etc/apt/apt.conf.d/01autoremove-kernels | awk '{print $2}') = "ASCII" ]] && (chroot /mnt /bin/bash -c "/etc/kernel/postinst.d/apt-auto-removal" || true )
    chroot /mnt /bin/bash -c "/usr/local/bin/chroot-apt-wrapper remove \
    linux-image-4.15* linux-modules-4.15* linux-headers-4.15* \
    linux-image-5.0* linux-image-5.3* linux-modules-5.0* linux-modules-5.3.* \
    linux-headers-5.0* linux-headers-5.3.*-y --purge" \
    &>> /tmp/"${FUNCNAME[0]}".install.log || true
    [[ ! $(file /mnt/etc/apt/apt.conf.d/01autoremove-kernels | awk '{print $2}') = "ASCII" ]] && (chroot /mnt /bin/bash -c "/etc/kernel/postinst.d/apt-auto-removal" || true )
    [[ $ZFS ]] && chroot /mnt /bin/bash -c "echo zfs-dkms zfs-dkms/note-incompatible-licenses note | debconf-set-selections" || true
    [[ $ZFS ]] && chroot /mnt /bin/bash -c "/usr/local/bin/chroot-apt-wrapper install --no-install-recommends -y zfs-dkms" || true
    chroot /mnt /bin/bash -c "/usr/local/bin/chroot-apt-wrapper upgrade -qq || (/usr/local/bin/chroot-dpkg-wrapper --configure -a ; /usr/local/bin/chroot-apt-wrapper upgrade -qq)" || true &>> /tmp/"${FUNCNAME[0]}".install.log || true
    echo "* Image apt upgrade done."
    
     waitfor "kernel_debs"
    KERNEL_VERS=$(< /tmp/KERNEL_VERS)
    echo "* Installing ${KERNEL_VERS} debs to image."
    cp "${workdir}"/*.deb /mnt/tmp/
    # Try installing the generated debs in chroot before we do anything else.
    chroot /mnt /bin/bash -c "/usr/local/bin/chroot-dpkg-wrapper -i /tmp/*.deb" \
    &>> /tmp/"${FUNCNAME[0]}".install.log || true
    
    echo "* Installing wifi & networking tools to image."
    chroot /mnt /bin/bash -c "/usr/local/bin/chroot-apt-wrapper \
    install network-manager wireless-tools wireless-regdb crda \
    net-tools rng-tools -y -qq " &>> /tmp/"${FUNCNAME[0]}".install.log || true
    echo "* Wifi & networking tools installed." 
endfunc
}


rpi_firmware () {
startfunc  
    git_get "https://github.com/Hexxeh/rpi-firmware" "rpi-firmware"
    waitfor "image_mount"
    waitfor "image_apt_installs"
. /tmp/env.txt  
    cd "${workdir}"/rpi-firmware || ragequit
    echo "* Installing current RPI firmware."
    # Note that this is overkill and much of these aren't needed for rpi4.
    cp bootcode.bin /mnt/boot/firmware/
    cp ./*.elf* /mnt/boot/firmware/
    cp ./*.dat* /mnt/boot/firmware/
    cp ./*.dat* /mnt/boot/firmware/
    cp ./*.dtb* /mnt/boot/firmware/
    mkdir -p /mnt/boot/firmware/broadcom/
    cp ./*.dtb* /mnt/boot/firmware/broadcom/
    cp ./*.dtb* /mnt/etc/flash-kernel/dtbs/
    cp overlays/*.dtbo* /mnt/boot/firmware/overlays/
endfunc
}

kernelbuild_setup () {
startfunc   
    git_get "$kernelgitrepo" "rpi-linux" "$kernel_branch"
. /tmp/env.txt 
    majorversion=$(grep VERSION "${src_cache}"/rpi-linux/Makefile | \
    head -1 | awk -F ' = ' '{print $2}')
    echo "MAJORVERSION=${majorversion}" >> /tmp/env.txt
    patchlevel=$(grep PATCHLEVEL "${src_cache}"/rpi-linux/Makefile | \
    head -1 | awk -F ' = ' '{print $2}')
    echo "PATCHLEVEL=${patchlevel}" >> /tmp/env.txt
    sublevel=$(grep SUBLEVEL "${src_cache}"/rpi-linux/Makefile | \
    head -1 | awk -F ' = ' '{print $2}')
    extraversion=$(grep EXTRAVERSION "${src_cache}"/rpi-linux/Makefile | \
    head -1 | awk -F ' = ' '{print $2}')
    extraversion_nohyphen="${extraversion//-}"
    CONFIG_LOCALVERSION=$(grep CONFIG_LOCALVERSION \
    "${src_cache}"/rpi-linux/arch/arm64/configs/bcm2711_defconfig | \
    head -1 | awk -F '=' '{print $2}' | sed 's/"//g')
    PKGVER="$majorversion.$patchlevel.$sublevel"
    [[ -n ${xtraversion} ]] && PKGVER="$majorversion.$patchlevel.$sublevel${extraversion}"
    
    KERNELREV=$(git -C "${src_cache}"/rpi-linux rev-parse --short HEAD) > /dev/null
    echo "$KERNELREV" > /tmp/KERNELREV
    echo "KERNELREV=${KERNELREV}" >> /tmp/env.txt
    cd "${workdir}"/rpi-linux || ragequit
    git update-index --refresh &>> /tmp/"${FUNCNAME[0]}".compile.log || true
    git diff-index --quiet HEAD &>> /tmp/"${FUNCNAME[0]}".compile.log || true
    

    mkdir -p "${workdir}"/kernel-build
    cd "${workdir}"/rpi-linux || ragequit
    defconfig="${KERNELDEF:-bcm2711_defconfig}"
    # [[ ! $KERNELDEF ]] && defconfig="${defconfig:-bcm2711_defconfig}"
    #[ ! -f arch/arm64/configs/bcm2711_defconfig ] && \
    #wget https://raw.githubusercontent.com/raspberrypi/linux/rpi-5.3.y/arch/arm64/configs/bcm2711_defconfig \
    #-O arch/arm64/configs/bcm2711_defconfig
    [[ ${defconfig} = "bcm2711_defconfig" ]] && ( [ ! -f arch/arm64/configs/bcm2711_defconfig ] && defconfig=defconfig )
    [[ -n "${defconfig}" ]] || defconfig=defconfig
    echo "defconfig=${defconfig}" >> /tmp/env.txt
    # Use kernel patch script from sakaki- found at 
    # https://github.com/sakaki-/bcm2711-kernel-bis
    [[ -e /source-ro/scripts/patch_kernel-${MAJORVERSION}.${PATCHLEVEL}.sh ]] && { /source-ro/scripts/patch_kernel-${MAJORVERSION}.${PATCHLEVEL}.sh ;true; } || \
    { /source-ro/scripts/patch_kernel.sh ; true; }
    [[ $NOETHLED ]] && (if ! patch -p1 --forward --silent --force --dry-run &>/dev/null \
           < /source-ro/patches/no_eth_led_5.3.patch; then
        >&2 echo "  Failed to apply eth led 5.3 patch in dry run - already merged?"
    elif ! patch -p1 --forward --force < /source-ro/patches/no_eth_led_5.3.patch; then
        >&2 echo " Failed to apply no eth led 5.3 patch - source tree may be corrupt!"
    else
        echo "  eth led 5.3 patch applied successfully!"
    fi)
    [[ $NOETHLED ]] && (if ! patch -p1 --forward --silent --force --dry-run &>/dev/null \
           < /source-ro/patches/no_eth_led_4.19.patch; then
        >&2 echo "  Failed to apply eth led 4.19 patch in dry run - already merged?"
    elif ! patch -p1 --forward --force < /source-ro/patches/no_eth_led_4.19.patch; then
        >&2 echo " Failed to apply no eth led - source tree may be corrupt!"
    else
        echo "  eth led 4.19 patch applied successfully!"
    fi)
     [[ $NOETHLED ]] && ( sed -i 's/BCM5482_SHD_SSD_LEDM/~BCM5482_SHD_SSD_LEDM/' "${workdir}"/rpi-linux/drivers/net/phy/broadcom.c || true ) 
#     [[ $NOETHLED ]] && ( sed -i '/^BCM5482_SHD_SSD_LEDM/d' "${workdir}"/rpi-linux/drivers/net/phy/broadcom.c || true ) 
    if [[ -e /tmp/APPLIED_KERNEL_PATCHES ]]
        then
            KERNEL_VERS="${PKGVER}${CONFIG_LOCALVERSION}-g${KERNELREV}$(< /tmp/APPLIED_KERNEL_PATCHES)"
            LOCALVERSION="-g$(< /tmp/KERNELREV)$(< /tmp/APPLIED_KERNEL_PATCHES)"
        else
            KERNEL_VERS="${PKGVER}${CONFIG_LOCALVERSION}-g${KERNELREV}"
            LOCALVERSION="-g$(< /tmp/KERNELREV)"
    fi
    
    echo "** Current Kernel Version: ${KERNEL_VERS}" 
    echo "${KERNEL_VERS}" > /tmp/KERNEL_VERS
    echo "KERNEL_VERS=${KERNEL_VERS}" >> /tmp/env.txt
    echo "${LOCALVERSION}" > /tmp/LOCALVERSION
    echo "LOCALVERSION=${LOCALVERSION}" >> /tmp/env.txt
    #arbitrary_wait_here
endfunc
}
    
kernel_build () {
startfunc
    waitfor "kernelbuild_setup"
    waitfor "compiler_setup"
. /tmp/env.txt
    KERNEL_VERS=$(< /tmp/KERNEL_VERS)
    LOCALVERSION=$(< /tmp/LOCALVERSION)



 
    cd "${workdir}"/rpi-linux
    make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- O="${workdir}"/kernel-build \
    LOCALVERSION="${LOCALVERSION}" ${defconfig} &>> /tmp/"${FUNCNAME[0]}".compile.log
    
    [[ $UBOOTONLY ]] && scripts/kconfig/merge_config.sh -y -m -O "${workdir}"/kernel-build arch/arm64/configs/bcmrpi3_defconfig arch/arm64/configs/bcm2711_defconfig &>> /tmp/"${FUNCNAME[0]}".compile.log

    cd "${workdir}"/kernel-build
    # Use kernel config modification script from sakaki- found at 
    # https://github.com/sakaki-/bcm2711-kernel-bis
    if [[ -e /source-ro/scripts/conform_config-${MAJORVERSION}.${PATCHLEVEL}.sh ]]
        then 
            cp /source-ro/scripts/conform_config-${MAJORVERSION}.${PATCHLEVEL}.sh \
            "${workdir}"/kernel-build/conform_config.sh
    elif [[ -e /source-ro/scripts/conform_config.sh ]]
        then
        cp /source-ro/scripts/conform_config.sh "${workdir}"/kernel-build/
    fi
    "${workdir}"/kernel-build/conform_config.sh


    yes "" | make LOCALVERSION="${LOCALVERSION}" ARCH=arm64 \
    CROSS_COMPILE=aarch64-linux-gnu- \
    O="${workdir}"/kernel-build/ \
    olddefconfig &>> /tmp/"${FUNCNAME[0]}".compile.log  || true
    KERNEL_VERS=$(< /tmp/KERNEL_VERS)
    echo "* Making ${KERNEL_VERS} kernel debs."
    cd "${workdir}"/rpi-linux || ragequit

cat <<-EOF> "${workdir}"/kernel_compile.sh
	#!/bin/bash
	cd ${workdir}/rpi-linux || exit 1
	make -j${nprocs} CFLAGS=${CFLAGS} CCPREFIX=aarch64-linux-gnu- ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE=aarch64-linux-gnu- LOCALVERSION=${LOCALVERSION} O=${workdir}/kernel-build/ bindeb-pkg
EOF
    cd "${workdir}"/rpi-linux || ragequit
    [[ -f ${workdir}/kernel_compile.sh ]] && chmod +x "${workdir}"/kernel_compile.sh && "${workdir}"/kernel_compile.sh |& tee -a /tmp/"${FUNCNAME[0]}".compile.log | \
    grep --line-buffered -v libfakeroot-sysv.so
     #[[ -f ${workdir}/kernel_compile.sh ]] && chmod +x "${workdir}"/kernel_compile.sh && "${workdir}"/kernel_compile.sh |& grep --line-buffered -v libfakeroot-sysv.so >> /tmp/"${FUNCNAME[0]}".compile.log 
    cd "${workdir}"/kernel-build || ragequit
    # This file should be EMPTY if all goes well.
    find . -executable ! -type d -exec file {} \; | grep x86-64 \
     >> /tmp/"${FUNCNAME[0]}".compile.log

    DEB_KERNEL_VERSION=$(sed -e 's/.*"\(.*\)".*/\1/' "${workdir}"/kernel-build/include/generated/utsrelease.h )
    echo -e "** Expected Kernel Version: ${KERNEL_VERS}\n**    Built Kernel Version: ${DEB_KERNEL_VERSION}"   
    echo "${DEB_KERNEL_VERSION}" > /tmp/KERNEL_VERS
endfunc
}


kernel_debs () {
startfunc
    waitfor "kernelbuild_setup"
. /tmp/env.txt

# Don't remake debs if they already exist in output.
KERNEL_VERS=$(< /tmp/KERNEL_VERS)

if [[ ! $REBUILD ]]
then
    # Look for Linux Image
    if test -n "$(find "${apt_cache}" -maxdepth 1 -name linux-image-*"${KERNEL_VERS}"* -print -quit)"
    then
        echo -e "${KERNEL_VERS} linux image deb on cache volume. 😎\n"
        cp "${apt_cache}"/linux-image-*"${KERNEL_VERS}"*arm64.deb "${workdir}"/
        echo "linux-image" >> /tmp/nodebs
    elif test -n "$(find /output/ -maxdepth 1 -name linux-image-*"${KERNEL_VERS}"* -print -quit)"
    then
        echo -e "${KERNEL_VERS} linux image deb found in /output/. 😎\n"
        cp /output/linux-image-*"${KERNEL_VERS}"*arm64.deb "${workdir}"/
        cp "${workdir}"/linux-image-*"${KERNEL_VERS}"*arm64.deb "${apt_cache}"/ 
        echo "linux-image" >> /tmp/nodebs
    else
        rm -f /tmp/nodebs || true
    fi
    if test -n "$(find "${apt_cache}" -maxdepth 1 -name linux-headers-*"${KERNEL_VERS}"* -print -quit)"
    then
        echo -e "${KERNEL_VERS} linux headers deb on cache volume. 😎\n"
        cp "${apt_cache}"/linux-headers-*"${KERNEL_VERS}"*arm64.deb "${workdir}"/
        echo "linux-image" >> /tmp/nodebs
    elif test -n "$(find /output/ -maxdepth 1 -name linux-headers-*"${KERNEL_VERS}"* -print -quit)"
    then
        echo -e "${KERNEL_VERS} linux headers deb found in /output/. 😎\n"
        cp /output/linux-headers-*"${KERNEL_VERS}"*arm64.deb "${workdir}"/
        cp "${workdir}"/linux-headers-*"${KERNEL_VERS}"*arm64.deb "${apt_cache}"/ 
        echo "linux-headers" >> /tmp/nodebs
    else
        rm -f /tmp/nodebs || true
    fi
fi
    [[ $REBUILD ]] && rm -f /tmp/nodebs || true
    
if [[ -e /tmp/nodebs ]]
then
    echo -e "Using cached ${KERNEL_VERS} debs.\n \
    \rNo kernel needs to be built."
    #cp "${apt_cache}"/linux-image-*"${KERNEL_VERS}"*arm64.deb "${workdir}"/
    #cp "${apt_cache}"/linux-headers-*"${KERNEL_VERS}"*arm64.deb "${workdir}"/
    cp "${workdir}"/*.deb /output/ 
    chown "$USER":"$GROUP" /output/*.deb
else
    [[ ! $REBUILD ]] && echo "Cached ${KERNEL_VERS} kernel debs not found. Building."
    [[ $REBUILD ]] && echo -e "🧐 Rebuild requested.\r😮Building ${KERNEL_VERS} ."
    
    (kernel_build &) || echo "kernel_build died"
    #[[ $DEBUG ]] && (spinnerwait kernel_build || echo "spinnerwait kernel_build died" )
    (spinnerwait kernel_build || echo "spinnerwait kernel_build died" )
    # This may have changed, so reload:
    KERNEL_VERS=$(< /tmp/KERNEL_VERS)
    echo "* Copying out git *${KERNEL_VERS}* kernel debs."
    rm -f "${workdir}"/linux-libc-dev*.deb
    cp "${workdir}"/*.deb "${apt_cache}"/ || (echo -e "Kernel Build Failed! 😬" ; pkill -F /flag/main)
    cp "${workdir}"/*.deb /output/ 
    chown "$USER":"$GROUP" /output/*.deb
fi
    
 endfunc
}   

kernel_nondeb_install () {
startfunc
    waitfor "kernel_debs"
    waitfor "image_mount"
    waitfor "added_scripts"
    waitfor "arm64_chroot_setup"
    waitfor "image_apt_installs"
. /tmp/env.txt
    KERNEL_VERS=$(< /tmp/KERNEL_VERS)
#     chroot /mnt /bin/bash -c "/usr/local/bin/chroot-apt-wrapper remove \
#     linux-image-raspi2 linux-image*-raspi2 linux-modules*-raspi2 -y --purge" \
#     &>> /tmp/"${FUNCNAME[0]}".install.log || true
#     chroot /mnt /bin/bash -c "/usr/local/bin/chroot-apt-wrapper remove \
#     linux-image-4.15* linux-modules-4.15* -y --purge" \
#     &>> /tmp/"${FUNCNAME[0]}".install.log || true
#     chroot /mnt /bin/bash -c "/usr/local/bin/chroot-dpkg-wrapper -i /tmp/*.deb" \
#     &>> /tmp/"${FUNCNAME[0]}".install.log || true
    cp /mnt/boot/initrd.img-"${KERNEL_VERS}" /mnt/boot/firmware/initrd.img
    cp /mnt/boot/vmlinuz-"${KERNEL_VERS}" /mnt/boot/firmware/vmlinuz
#     vmlinuz_type=$(file -bn /mnt/boot/firmware/vmlinuz)
#     if [ "$vmlinuz_type" == "MS-DOS executable" ]
#         then
#         cp /mnt/boot/firmware/vmlinuz /mnt/boot/firmware/kernel8.img.nouboot
#     else
#         cp /mnt/boot/firmware/vmlinuz /mnt/boot/firmware/kernel8.img.nouboot.gz
#         cd /mnt/boot/firmware/ || exit 1 ; gunzip -f /mnt/boot/firmware/kernel8.img.nouboot.gz \
#         &>> /tmp/"${FUNCNAME[0]}".install.log
#     fi
endfunc
}


armstub8-gic () {
startfunc 
    git_get "https://github.com/raspberrypi/tools.git" "rpi-tools"
. /tmp/env.txt   
    cd "${workdir}"/rpi-tools/armstubs || ragequit
    ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- make armstub8-gic.bin &>> /tmp/"${FUNCNAME[0]}".compile.log
    waitfor "image_mount"
    cp "${workdir}"/rpi-tools/armstubs/armstub8-gic.bin /mnt/boot/firmware/armstub8-gic.bin
endfunc
}

non-free_firmware () {
startfunc 
    git_get "https://github.com/RPi-Distro/firmware-nonfree" "firmware-nonfree"
    waitfor "image_mount"
. /tmp/env.txt
    mkdir -p ${MNTLIBPATH}/firmware
    cp -af "${workdir}"/firmware-nonfree/*  ${MNTLIBPATH}/firmware

endfunc
}


rpi_config_txt_configuration () {
startfunc 
    waitfor "image_mount"
    waitfor "image_apt_installs"
 . /tmp/env.txt  
    echo "* Making /boot/firmware/ config file modifications."
    
    cat <<-EOF >> /mnt/boot/firmware/usercfg.txt
	#
	# This image was built on ${now} using software at
	# https://github.com/satmandu/docker-rpi4-imagebuilder/
	# 
EOF
    if ! grep -qs 'armstub=armstub8-gic.bin' /mnt/boot/firmware/config.txt
        then echo "armstub=armstub8-gic.bin" >> /mnt/boot/firmware/config.txt
    fi
    
#    if ! grep -qs 'enable_gic=1' /mnt/boot/firmware/config.txt
#        then echo "enable_gic=1" >> /mnt/boot/firmware/config.txt
#    fi
    
#    if ! grep -qs 'arm_64bit=1' /mnt/boot/firmware/config.txt
#        then echo "arm_64bit=1" >> /mnt/boot/firmware/config.txt
#    fi

# Workaround for firmware issue at https://github.com/raspberrypi/firmware/issues/1259
    if ! grep -qs 'device_tree_end' /mnt/boot/firmware/config.txt; then
        if grep -qs 'device_tree_address' /mnt/boot/firmware/config.txt; then
        device_tree_address=$(grep device_tree_address /mnt/boot/firmware/config.txt | head -1 | awk -F '=0x' '{print $2}')
        device_tree_end=$(echo "obase=16;ibase=16;$device_tree_address+000FFFFF" | bc)
        sed -i "s/device_tree_address=0x${device_tree_address}/device_tree_address=0x${device_tree_address}\ndevice_tree_end=0x${device_tree_end}/" /mnt/boot/firmware/config.txt
        fi
    fi
    
#    if ! grep -qs 'dtoverlay=vc4-fkms-v3d' /mnt/boot/firmware/config.txt
#        then echo "dtoverlay=vc4-fkms-v3d" >> /mnt/boot/firmware/config.txt
#    fi
    
#    if grep -qs 'kernel8.bin' /mnt/boot/firmware/config.txt
#        then sed -i 's/kernel8.bin/kernel8.img/' /mnt/boot/firmware/config.txt
#    fi
    
#    if ! grep -qs 'initramfs' /mnt/boot/firmware/config.txt
#        then echo "initramfs initrd.img followkernel" >> /mnt/boot/firmware/config.txt
#    fi
    
#    if ! grep -qs 'enable_uart=1' /mnt/boot/firmware/config.txt
#        then echo "enable_uart=1" >> /mnt/boot/firmware/config.txt
#    fi
    
    if ! grep -qs 'dtparam=eth_led0' /mnt/boot/firmware/usercfg.txt
        then cat <<-EOF >> /mnt/boot/firmware/config.txt
		# Disable Ethernet LEDs
		# Not yert functional on RPI4
		#dtparam=eth_led0=14
		#dtparam=eth_led1=14
EOF
    fi
    
    if ! grep -qs 'dtparam=pwr_led_trigger' /mnt/boot/firmware/usercfg.txt
        then cat <<-EOF >> /mnt/boot/firmware/config.txt
		# Disable the PWR LED
		#dtparam=pwr_led_trigger=none
		#dtparam=pwr_led_activelow=off
EOF
    fi
    
    if ! grep -qs 'dtparam=act_led_trigger' /mnt/boot/firmware/usercfg.txt
        then cat <<-EOF >> /mnt/boot/firmware/config.txt
		# Disable the Activity LED
		#dtparam=act_led_trigger=none
		#dtparam=act_led_activelow=off
EOF
    fi
    
   
endfunc
}

rpi_cmdline_txt_configuration () {
startfunc 
    waitfor "image_mount"
    waitfor "image_apt_installs"
 . /tmp/env.txt  
    echo "* Making /boot/firmware cmdline file modifications."
    
    # Seeing possible sdcard issues, so be safe for now.
    if ! grep -qs 'fsck.repair=yes' /mnt/boot/firmware/nobtcmd.txt 
        then sed -i 's/rootwait/rootwait fsck.repair=yes/' /mnt/boot/firmware/nobtcmd.txt
    fi
    
    if ! grep -qs 'fsck.mode=force' /mnt/boot/firmware/nobtcmd.txt
        then sed -i 's/rootwait/rootwait fsck.mode=force/' /mnt/boot/firmware/nobtcmd.txt
    fi
    if ! grep -qs 'fsck.repair=yes' /mnt/boot/firmware/btcmd.txt 
        then sed -i 's/rootwait/rootwait fsck.repair=yes/' /mnt/boot/firmware/btcmd.txt
    fi
    
    if ! grep -qs 'fsck.mode=force' /mnt/boot/firmware/btcmd.txt
        then sed -i 's/rootwait/rootwait fsck.mode=force/' /mnt/boot/firmware/btcmd.txt
    fi
    
endfunc
}


rpi_userland () {
startfunc
    git_get "https://github.com/raspberrypi/userland" "rpi-userland"
    USERLANDREV=$(git -C "${src_cache}"/rpi-userland rev-parse --short HEAD) > /dev/null
    waitfor "image_mount"
. /tmp/env.txt
    echo "* Installing Raspberry Pi userland source."
    cd "${workdir}"/rpi-userland/ || ragequit
    sed -i 's/__bitwise/FDT_BITWISE/' "${workdir}"/rpi-userland/opensrc/helpers/libfdt/libfdt_env.h
    sed -i 's/__force/FDT_FORCE/' "${workdir}"/rpi-userland/opensrc/helpers/libfdt/libfdt_env.h
    mkdir -p /mnt/opt/vc
    CROSS_COMPILE=aarch64-linux-gnu- ./buildme --aarch64 /mnt &>> /tmp/"${FUNCNAME[0]}".compile.log

    cd "${workdir}"/rpi-userland/build/arm-linux/release/ || ragequit
    mkdir -p "${workdir}"/rpi-userland/build/arm-linux/release/extracted
    
    mkdir -p extracted/etc/ld.so.conf.d/
    echo '/opt/vc/lib' > extracted/etc/ld.so.conf.d/vc.conf 
    
    mkdir -p extracted/etc/environment.d
    cat  <<-EOF > extracted/etc/environment.d/10-vcgencmd.conf
	# /etc/environment.d/10-vcgencmd.conf
	# Do not edit this file
	
	PATH="/opt/vc/bin:/opt/vc/sbin"
	ROOTPATH="/opt/vc/bin:/opt/vc/sbin"
	LDPATH="/opt/vc/lib"
EOF
    chmod +x extracted/etc/environment.d/10-vcgencmd.conf
    
    mkdir -p extracted/etc/profile.d/
    cat <<-'EOF' > extracted/etc/profile.d/98-rpi.sh 
	# /etc/profile.d/98-rpi.sh
	# Adds Raspberry Pi Foundation userland binaries to path
	export PATH="$PATH:/opt/vc/bin:/opt/vc/sbin"
EOF
    chmod +x extracted/etc/profile.d/98-rpi.sh
       
    cat  <<-EOF > extracted/etc/ld.so.conf.d/00-vmcs.conf
	/opt/vc/lib
EOF
    local SUDOPATH=$(sed -n 's/\(^.*secure_path="\)//p' /mnt/etc/sudoers | sed s'/.$//')
    SUDOPATH="${SUDOPATH:-/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin}"
    SUDOPATH+=":/opt/vc/bin:/opt/vc/sbin"
    # Add path to sudo
    mkdir -p extracted/etc/sudoers.d
    echo "* Adding rpi util path to sudo."
    cat <<-EOF >> extracted/etc/sudoers.d/rpi
	Defaults secure_path=$SUDOPATH
EOF
    chmod 0440 extracted/etc/sudoers.d/rpi
    # Add display forwarding to sudo as per https://askubuntu.com/a/414810/844422
    echo "* Adding X Display forwarding to sudo."
    cat <<-EOF >> extracted/etc/sudoers.d/display
	Defaults env_keep+="XAUTHORIZATION XAUTHORITY TZ PS2 PS1 PATH LS_COLORS KRB5CCNAME HOSTNAME HOME DISPLAY COLORS"
EOF
    chmod 0440 extracted/etc/sudoers.d/display
    cd "${workdir}"/rpi-userland/build/arm-linux/release/
    ARM64=on checkinstall -D --install=no --pkgname=rpiuserland --pkgversion="$(date +%Y%m):$(date +%Y%m%d)-${USERLANDREV}" --fstrans=yes -y &>> /tmp/"${FUNCNAME[0]}".compile.log
    dpkg-deb -R rpiuserland_*.deb extracted/ &>> /tmp/"${FUNCNAME[0]}".compile.log
    dpkg-deb -b extracted &>> /tmp/"${FUNCNAME[0]}".compile.log
    mv extracted.deb rpiuserland_$(date +%Y%m%d)-${USERLANDREV}_arm64.deb &>> /tmp/"${FUNCNAME[0]}".compile.log
[[ $PKGUSERLAND ]] && cp rpiuserland_$(date +%Y%m%d)-${USERLANDREV}_arm64.deb /output/ &>> /tmp/"${FUNCNAME[0]}".compile.log
    cp rpiuserland_$(date +%Y%m%d)-${USERLANDREV}_arm64.deb /mnt/var/cache/apt/archives/ &>> /tmp/"${FUNCNAME[0]}".compile.log
    
echo "rpi_userland done" >> /tmp/build.log
arbitrary_wait_here
endfunc
}

rpi_eeprom_firmware () {
startfunc
    rm -rf /mnt/lib/firmware/raspberrypi/rpi-eeprom
    mkdir -p /mnt/lib/firmware/raspberrypi/
    cd /mnt/lib/firmware/raspberrypi
    git clone --depth=1 https://github.com/raspberrypi/rpi-eeprom.git
    mv rpi-eeprom/firmware bootloader
    mv rpi-eeprom/rpi-eeprom-update /mnt/usr/local/bin/
    mv rpi-eeprom/rpi-eeprom-config /mnt/usr/local/bin/
endfunc
}



wifi_firmware_modification () {
startfunc  
    waitfor "image_mount"
    waitfor "non-free_firmware"
. /tmp/env.txt
    #echo "* Modifying wireless firmware if necessary."
    # as per https://andrei.gherzan.ro/linux/raspbian-rpi4-64/

    if [ ! -e "${MNTLIBPATH}/firmware/brcm/brcmfmac43455-sdio.raspberrypi,4-model-b.txt" ]
    then
    cp ${MNTLIBPATH}/firmware/brcm/brcmfmac43455-sdio.txt ${MNTLIBPATH}/firmware/brcm/brcmfmac43455-sdio.raspberrypi,4-model-b.txt
    fi
    if ! grep -qs 'boardflags3=0x44200100' \
        ${MNTLIBPATH}/firmware/brcm/brcmfmac43455-sdio.raspberrypi,4-model-b.txt
    then sed -i -r 's/0x48200100/0x44200100/' \
        ${MNTLIBPATH}/firmware/brcm/brcmfmac43455-sdio.raspberrypi,4-model-b.txt
    fi
endfunc
}

patched_uboot () {
startfunc
    UBOOTDEF="${UBOOTDEF:-rpi_4}"
    ubootdefconfig="${UBOOTDEF}_defconfig"
#    [[ ! $UBOOTONLY ]] && git_get "https://github.com/agherzan/u-boot.git" "u-boot" "ag/v2019.07-rpi4-wip"
#    [[ $UBOOTONLY ]] && git_get "https://github.com/agherzan/u-boot.git" "u-boot" "ag/v2019.07-rpi4-wip"
    #git_get "https://github.com/u-boot/u-boot.git" "u-boot" "master"
    git_get "https://github.com/u-boot/u-boot.git" "u-boot" "v2019.10"
. /tmp/env.txt
    cd "${workdir}"/u-boot || exit 1
    # Working git tag
    # git reset --hard cd5ffc5de5a26f5b785e25654977fee25779b3e4
    UBOOTREV=$(git -C "${src_cache}"/u-boot rev-parse --short HEAD) > /dev/null
#    curl -O https://github.com/satmandu/u-boot/commit/b514f892bc3d6ecbc75f80d0096055a6a8afbf75.patch
#    patch -p1 < b514f892bc3d6ecbc75f80d0096055a6a8afbf75.patch
#     patch -p1 < /source-ro/patches/0002-raspberrypi-Disable-simple-framebuffer-support.patch
#     patch -p1 < /source-ro/patches/U-Boot-board-rpi4-fix-instantiating-PL011-driver.patch

    (if ! patch -p1 --forward --silent --force --dry-run &>/dev/null \
           < /source-ro/patches/U-Boot-v2-rpi4-enable-dram-bank-initialization.patch; then
        >&2 echo "  Failed to apply U-Boot-v2-rpi4-enable-dram-bank-initialization in dry run - already merged?"
    elif ! patch -p1 --forward --force < /source-ro/patches/U-Boot-v2-rpi4-enable-dram-bank-initialization.patch; then
        >&2 echo "  U-Boot-v2-rpi4-enable-dram-bank-initialization failed to apply - source tree may be corrupt!"
    else
        echo "  U-Boot-v2-rpi4-enable-dram-bank-initialization applied successfully!"
    fi)
    (if ! patch -p1 --forward --silent --force --dry-run &>/dev/null \
           < /source-ro/patches/Fix-default-values-for-address-and-size-cells.patch; then
        >&2 echo "  Failed to apply Fix-default-values-for-address-and-size-cells in dry run - already merged?"
    elif ! patch -p1 --forward --force < /source-ro/patches/Fix-default-values-for-address-and-size-cells.patch; then
        >&2 echo "  Fix-default-values-for-address-and-size-cells failed to apply - source tree may be corrupt!"
    else
        echo "  Fix-default-values-for-address-and-size-cells applied successfully!"
    fi)
    
#    [[ $UBOOTONLY ]] && patch -p1 < /source-ro/patches/RPi-one-binary-for-RPi3-4-and-RPi1-2.patch    
     [[ $UBOOTONLY ]] && echo "CONFIG_USB_DWC2=y" >> "${workdir}"/u-boot/configs/${ubootdefconfig}
     [[ $UBOOTONLY ]] && echo "CONFIG_USB_ETHER_LAN78XX=y" >> "${workdir}"/u-boot/configs/${ubootdefconfig}
     [[ $UBOOTONLY ]] && echo "CONFIG_USB_ETHER_SMSC95XX=y" >> "${workdir}"/u-boot/configs/${ubootdefconfig}
#     [[ $UBOOTONLY ]] && echo "CONFIG_DM_ETH=y" >> "${workdir}"/u-boot/configs/${ubootdefconfig}
#     [[ $UBOOTONLY ]] && echo "CONFIG_USB=y" >> "${workdir}"/u-boot/configs/${ubootdefconfig}
#     [[ $UBOOTONLY ]] && echo "CONFIG_DM_USB=y" >> "${workdir}"/u-boot/configs/${ubootdefconfig}
#     [[ $UBOOTONLY ]] && echo "CONFIG_USB_KEYBOARD=y" >> "${workdir}"/u-boot/configs/${ubootdefconfig}
#     [[ $UBOOTONLY ]] && echo "CONFIG_USB_HOST_ETHER=y" >> "${workdir}"/u-boot/configs/${ubootdefconfig}
#     [[ $UBOOTONLY ]] && echo "CONFIG_OF_BOARD=y" >> "${workdir}"/u-boot/configs/${ubootdefconfig}
#     [[ $UBOOTONLY ]] && echo "CONFIG_USE_PREBOOT=y" >> "${workdir}"/u-boot/configs/${ubootdefconfig}
#     [[ $UBOOTONLY ]] && echo 'CONFIG_PREBOOT="usb start"' >> "${workdir}"/u-boot/configs/${ubootdefconfig}
#     [[ $UBOOTONLY ]] && echo "CONFIG_MISC_INIT_R=y" >> "${workdir}"/u-boot/configs/${ubootdefconfig}
#     [[ $UBOOTONLY ]] && echo "CONFIG_ARM64" >> "${workdir}"/u-boot/configs/${ubootdefconfig}

#    [[ $UBOOTONLY ]] && patch -p1 < /source-ro/patches/rpi-import-mkknlimg.patch
#    [[ $UBOOTONLY ]] && chmod +x tools/mkknlimg
#    [[ $UBOOTONLY ]] && patch -p1 < /source-ro/patches/rpi2-rpi3-config-tweaks.patch || true


    echo "CONFIG_SUPPORT_RAW_INITRD=y" >> "${workdir}"/u-boot/configs/${ubootdefconfig}
    echo "CONFIG_ENV_IS_IN_FAT=y" >> "${workdir}"/u-boot/configs/${ubootdefconfig}
    sed -i 's/CONFIG_OF_EMBED/CONFIG_OF_BOARD/' "${workdir}"/u-boot/configs/${ubootdefconfig}
#    [[ $UBOOTONLY ]] && sed -i 's/fdt_addr_r=0x02600000/fdt_addr_r=0x03000000/' "${workdir}"/u-boot/include/configs/rpi.h
    
    echo "CONFIG_LZ4=y" >> "${workdir}"/u-boot/configs/${ubootdefconfig}
    echo "CONFIG_GZIP=y" >> "${workdir}"/u-boot/configs/${ubootdefconfig}
    echo "CONFIG_BZIP2=y" >> "${workdir}"/u-boot/configs/${ubootdefconfig}
    echo "CONFIG_SYS_LONGHELP=y" >> "${workdir}"/u-boot/configs/${ubootdefconfig}
    echo "CONFIG_REGEX=y" >> "${workdir}"/u-boot/configs/${ubootdefconfig}
    echo "CONFIG_CMD_ZFS=y" >> "${workdir}"/u-boot/configs/${ubootdefconfig}
    echo "CONFIG_FS_BTRFS=y" >> ${workdir}/u-boot/configs/${ubootdefconfig}
    echo "CONFIG_FS_EXT4=y" >> ${workdir}/u-boot/configs/${ubootdefconfig}
    echo "CONFIG_FS_FAT=y" >> ${workdir}/u-boot/configs/${ubootdefconfig}
    #echo "CONFIG_CMD_PART=y" >> ${workdir}/u-boot/configs/${ubootdefconfig}
    #echo "CONFIG_CMD_PCI=y" >> ${workdir}/u-boot/configs/${ubootdefconfig}
    #echo "CONFIG_CMD_USB=y" >> ${workdir}/u-boot/configs/${ubootdefconfig}
    #echo "CONFIG_CMD_BTRFS=y" >> ${workdir}/u-boot/configs/${ubootdefconfig}
    #echo "CONFIG_CMD_EXT4=y" >> ${workdir}/u-boot/configs/${ubootdefconfig}
    #echo "CONFIG_CMD_EXT4_WRITE=y" >> ${workdir}/u-boot/configs/${ubootdefconfig}
    #echo "CONFIG_CMD_FAT=y" >> ${workdir}/u-boot/configs/${ubootdefconfig}
    #echo "CONFIG_CMD_FS_GENERIC=y" >> ${workdir}/u-boot/configs/${ubootdefconfig}
    #echo "CONFIG_PARTITION_TYPE_GUID=y" >> ${workdir}/u-boot/configs/${ubootdefconfig}
    #echo "CONFIG_ENV_IS_IN_EXT4=y" >> ${workdir}/u-boot/configs/${ubootdefconfig}
    #echo "CONFIG_PCI=y   " >> ${workdir}/u-boot/configs/${ubootdefconfig}
    #echo "CONFIG_DM_PCI=y" >> ${workdir}/u-boot/configs/${ubootdefconfig}
    #echo "CONFIG_PCI_PNP=y" >> ${workdir}/u-boot/configs/${ubootdefconfig}
    #echo "CONFIG_PCIE_ECAM_GENERIC=y" >> ${workdir}/u-boot/configs/${ubootdefconfig}
    #echo "CONFIG_USB=y" >> ${workdir}/u-boot/configs/${ubootdefconfig}
    #echo "CONFIG_DM_USB=y" >> ${workdir}/u-boot/configs/${ubootdefconfig}
    #echo "CONFIG_USB_HOST=y" >> ${workdir}/u-boot/configs/${ubootdefconfig}
    #echo "CONFIG_USB_XHCI_HCD=y" >> ${workdir}/u-boot/configs/${ubootdefconfig}
    #echo "CONFIG_USB_XHCI_PCI=y" >> ${workdir}/u-boot/configs/${ubootdefconfig}
    #echo "CONFIG_USB_UHCI_HCD=y" >> ${workdir}/u-boot/configs/${ubootdefconfig}
    #echo "CONFIG_USB_DWC2=y" >> ${workdir}/u-boot/configs/${ubootdefconfig}
    #echo "CONFIG_USB_STORAGE=y" >> ${workdir}/u-boot/configs/${ubootdefconfig}
    #echo "CONFIG_USB_KEYBOARD=y" >> ${workdir}/u-boot/configs/${ubootdefconfig}
    #echo "CONFIG_SYS_USB_EVENT_POLL=y" >> ${workdir}/u-boot/configs/${ubootdefconfig}
    #echo "CONFIG_EXT4_WRITE=y" >> ${workdir}/u-boot/configs/${ubootdefconfig}
    #echo "CONFIG_FAT_WRITE=y" >> ${workdir}/u-boot/configs/${ubootdefconfig}
    
    echo "* Compiling u-boot."
    ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- make ${ubootdefconfig} &>> /tmp/"${FUNCNAME[0]}".compile.log
    ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- make -j $(($(nproc) + 1)) &>> /tmp/"${FUNCNAME[0]}".compile.log
#    [[ $UBOOTONLY ]] && tools/mkknlimg --dtok --270x --283x "${workdir}"/u-boot/u-boot.bin /output/${now}.${UBOOTDEF}.uboot.bin
   [[ $UBOOTONLY ]] && cp "${workdir}"/u-boot/u-boot.bin /output/${now}.${UBOOTDEF}.uboot-${UBOOTREV}.bin
    #[[ $UBOOTONLY ]] && return
    waitfor "image_mount"
    echo "* Installing u-boot to image."
    cp "${workdir}"/u-boot/u-boot.bin /mnt/boot/firmware/uboot.bin
    cp "${workdir}"/u-boot/u-boot.bin /mnt/boot/firmware/uboot_rpi_4.bin
    #cp "${workdir}"/u-boot/u-boot.bin /mnt/boot/firmware/kernel8.img
    mkdir -p  ${MNTLIBPATH}/u-boot/rpi_4/
    cp "${workdir}"/u-boot/u-boot.bin  ${MNTLIBPATH}/u-boot/rpi_4/
    cp "${workdir}"/u-boot/u-boot.bin ${MNTLIBPATH}/u-boot/rpi_4/${UBOOTDEF}.uboot-${UBOOTREV}.bin
    # This can be done without chroot by just having u-boot-tools on the build
    # container
    #chroot /mnt /bin/bash -c "mkimage -A arm64 -O linux -T script \
    #-d /etc/flash-kernel/bootscript/bootscr.rpi \
    #/boot/firmware/boot.scr" &>> /tmp/${FUNCNAME[0]}.compile.log
#     [[ !  -f /mnt/etc/flash-kernel/bootscript/bootscr.rpi ]] && \
#     cp /source-ro/scripts/bootscr.rpi /mnt/etc/flash-kernel/bootscript/bootscr.rpi
#     mkimage -A arm64 -O linux -T script \
#     -d /mnt/etc/flash-kernel/bootscript/bootscr.rpi \
#     /mnt/boot/firmware/boot.scr &>> /tmp/"${FUNCNAME[0]}".compile.log

#uboot_script

endfunc
}

uboot_script () {
startfunc
    [[ !  -f /usr/bin/mkimage ]] && apt install u-boot-tools -y
    [[ !  -f /mnt/etc/flash-kernel/bootscript/bootscr.rpi ]] && \
    cp /source-ro/scripts/bootscr.rpi /mnt/etc/flash-kernel/bootscript/bootscr.rpi
    mkimage -A arm64 -O linux -T script \
    -d /mnt/etc/flash-kernel/bootscript/bootscr.rpi \
    /mnt/boot/firmware/boot.scr &>> /tmp/"${FUNCNAME[0]}".compile.log
endfunc
}


first_boot_scripts_setup () {
startfunc  
    waitfor "image_mount"
. /tmp/env.txt  
    echo "* Creating first start cleanup script."
    cat <<-'EOF' > /mnt/etc/rc.local
	#!/bin/sh -e
	#
	# Print the IP address
	    _IP=$(hostname -I) || true
	if [ "$_IP" ]; then
	    printf "My IP address is %s\n" "$_IP"
	fi
	#
	# Disable wifi power saving, which causes wifi instability.
	# See discussion here: https://github.com/raspberrypi/linux/issues/3127
	iwconfig wlan0 power off
	#
	if [ ! -e "/lib/firmware/brcm/brcmfmac43455-sdio.clm_blob" ]
	then
		set +o noclobber
		curl https://raw.githubusercontent.com/RPi-Distro/firmware-nonfree/master/brcm/brcmfmac43455-sdio.clm_blob > /lib/firmware/brcm/brcmfmac43455-sdio.clm_blob
	fi
	if [ ! -e "/lib/firmware/brcm/brcmfmac43455-sdio.raspberrypi,4-model-b.txt" ]
	then
		set +o noclobber
		( curl https://raw.githubusercontent.com/RPi-Distro/firmware-nonfree/master/brcm/brcmfmac43455-sdio.raspberrypi,4-model-b.txt > /lib/firmware/brcm/brcmfmac43455-sdio.raspberrypi,4-model-b.txt) || \
		curl https://raw.githubusercontent.com/RPi-Distro/firmware-nonfree/master/brcm/brcmfmac43455-sdio.txt > /lib/firmware/brcm/brcmfmac43455-sdio.raspberrypi,4-model-b.txt
	cp /lib/firmware/brcm/brcmfmac43455-sdio.raspberrypi,4-model-b.txt /lib/firmware/brcm/brcmfmac43455-sdio.txt
	sed -i -r 's/0x48200100/0x44200100/' \
        /lib/firmware/brcm/brcmfmac43455-sdio.raspberrypi,4-model-b.txt
	fi 
	if [ ! -e "/lib/firmware/brcm/brcmfmac43455-sdio.bin" ]
	then
		set +o noclobber
		curl https://raw.githubusercontent.com/RPi-Distro/firmware-nonfree/master/brcm/brcmfmac43455-sdio.bin > /lib/firmware/brcm/brcmfmac43455-sdio.bin
	fi
	/etc/rc.local.temp &
	exit 0
EOF
    chmod +x /mnt/etc/rc.local


    cat <<-'EOF' > /mnt/etc/rc.local.temp
	#!/bin/sh -e
	# 1st Boot Cleanup Script
	#
	# make flash-kernel force install kernels
	sed -i 's/exec flash-kernel/exec flash-kernel --force/' \
	/etc/kernel/postrm.d/zz-flash-kernel
	sed -i 's/exec flash-kernel/exec flash-kernel --force/' \
	/etc/kernel/postinst.d/zz-flash-kernel
	/usr/bin/dpkg -i /var/cache/apt/archives/*.deb
	/usr/local/bin/chroot-apt-wrapper remove linux-image-raspi2 linux-image*-raspi2 -y --purge
	# Modifying instruction at https://launchpad.net/linux-purge/+announcement/15313
	cd /tmp && wget -N https://git.launchpad.net/linux-purge/plain/install-linux-purge.sh && chmod +x ./install-linux-purge.sh && ./install-linux-purge.sh && /usr/local/bin/linux-purge -k 1 -y
	# Note that linux-purge can be removed through this step as per 
	# https://launchpad.net/linux-purge/+announcement/15314
	# cd $(xdg-user-dir DOWNLOAD) && wget -N https://git.launchpad.net/linux-purge/plain/remove-linux-purge.sh && chmod +x ./remove-linux-purge.sh && sudo ./remove-linux-purge.sh
	/usr/local/bin/chroot-apt-wrapper update && /usr/local/bin/chroot-apt-wrapper upgrade -y
	/usr/local/bin/chroot-apt-wrapper install qemu-user-binfmt -qq
	/usr/sbin/update-initramfs -c -k all
	sed -i 's/\/etc\/rc.local.temp\ \&//' /etc/rc.local 
	touch /etc/cloud/cloud-init.disabled
	ldconfig
	SKIP_WARNING=1 /usr/local/bin/rpi-update
	rm -- "$0"
	exit 0
EOF
    chmod +x /mnt/etc/rc.local.temp
    
endfunc
} 

added_scripts () {
startfunc  
    waitfor "image_mount"
. /tmp/env.txt  
    ## This script allows flash-kernel to create the uncompressed kernel file
    #  on the boot partition.
    mkdir -p /mnt/etc/kernel/postinst.d
    echo "* Creating /etc/kernel/postinst.d/zzzz_rpi4_kernel ."
    cat <<-'EOF' > /mnt/etc/kernel/postinst.d/zzzz_rpi4_kernel
	#!/bin/sh -eu
	#
	# If u-boot is not being used, this uncompresses the arm64 kernel to 
	# kernel8.img
	#
	# First exit if we aren't running an ARM64 kernel.
	#
	[ $(uname -m) != aarch64 ] && exit 0
	#
	KERNEL_VERSION="$1"
	KERNEL_INSTALLED_PATH="$2"
	
	# If kernel8.img does not look like u-boot, then assume u-boot
	# is not being used.
	if [ ! $(file /boot/firmware/kernel8.img | grep -vq "PCX") ]; then
	    if [ ! $(file /boot/firmware/uboot_rpi_4.bin | grep -vq "PCX") ]
	    # Assume uboot is not being used, save kernel as kernel8.img
	    gunzip -c -f ${KERNEL_INSTALLED_PATH} > /boot/firmware/kernel8.img && \
	cp /boot/firmware/kernel8.img /boot/firmware/kernel8.img.nouboot
	    else
	    # uboot found, do not overwrite it.
	    gunzip -c -f ${KERNEL_INSTALLED_PATH} > /boot/firmware/kernel8.img.nouboot
	    fi
	fi
	
	exit 0
EOF
    chmod +x /mnt/etc/kernel/postinst.d/zzzz_rpi4_kernel

    ## This script makes the device tree folder that a bunch of kernel debs 
    # never bother installing.

    mkdir -p /mnt/etc/kernel/preinst.d/
    echo "* Creating /etc/kernel/preinst.d/rpi4_make_device_tree_folders ."
    cat <<-'EOF' > /mnt/etc/kernel/preinst.d/rpi4_make_device_tree_folders
	#!/bin/sh -eu
	#
	# This script keeps kernel installs from complaining about a missing 
	# device tree folder in /lib/firmware/kernelversion/device-tree
	# This should go in /etc/kernel/preinst.d/
	
	KERNEL_VERSION="$1"
	KERNEL_INSTALLED_PATH="$2"
	
	if [[ -L "/lib" && -d "/lib" ]]
	then
	    mkdir -p /usr/lib/firmware/${KERNEL_VERSION}/device-tree/
	else
	    mkdir -p /lib/firmware/${KERNEL_VERSION}/device-tree/
	fi
	
	exit 0
EOF
    chmod +x /mnt/etc/kernel/preinst.d/rpi4_make_device_tree_folders

    # Updated flash-kernel db entry for the RPI 4B

    mkdir -p /mnt/etc/flash-kernel/
    echo "* Creating /etc/flash-kernel/db ."
    cat <<-EOF >> /mnt/etc/flash-kernel/db
	#
	# Raspberry Pi 4 Model B Rev 1.1
	Machine: Raspberry Pi 4 Model B
	Machine: Raspberry Pi 4 Model B Rev 1.1
	DTB-Id: /etc/flash-kernel/dtbs/bcm2711-rpi-4-b.dtb
	Boot-DTB-Path: /boot/firmware/bcm2711-rpi-4-b.dtb
	Boot-Kernel-Path: /boot/firmware/vmlinuz
	Boot-Initrd-Path: /boot/firmware/initrd.img
	Boot-Script-Path: /boot/firmware/boot.scr
	U-Boot-Script-Name: bootscr.rpi
	Required-Packages: u-boot-tools
	# XXX we should copy the entire overlay dtbs dir too
EOF

    # Keep wifi up despite tendency to drop out.
    echo "* Creating /usr/local/bin/wpaping.sh ."
    cat <<-EOF >> /mnt/usr/local/bin/wpaping.sh
	#!/bin/bash
	#
	# Loop forever doing wpa_cli SCAN commands
	#
	
	sleeptime=120  # number of seconds to sleep. 2 minutes (120 seconds) is a good value
	
	while [ 1 ];
	do
	        wpa_cli -i wlan0 scan
	            sleep $sleeptime
	    done
EOF

    chroot /mnt /bin/bash -c "(crontab -l ; echo \"*/5 * * * * /usr/local/bin/wpaping.sh\") | crontab -"

    rpi_eeprom_firmware
    cd /mnt/usr/local/bin
    curl -OL https://raw.githubusercontent.com/Hexxeh/rpi-update/master/rpi-update
    chmod +x /mnt/usr/local/bin/rpi-update
    sed -i 's/UPDATE_SELF:-1/UPDATE_SELF:-0/' /mnt/usr/local/bin/rpi-update
    sed -i 's/BOOT_PATH:-"\/boot"/BOOT_PATH:-"\/boot\/firmware"/' /mnt/usr/local/bin/rpi-update
    sed -i 's/SKIP_KERNEL:-0/SKIP_KERNEL:-1/' /mnt/usr/local/bin/rpi-update
    sed -i 's/SKIP_SDK:-0/SKIP_SDK:-1/' /mnt/usr/local/bin/rpi-update
    sed -i 's/\tupdate_vc_libs/\t#update_vc_libs/' /mnt/usr/local/bin/rpi-update
    sed -i 's/\tupdate_sdk/\t#update_sdk/' /mnt/usr/local/bin/rpi-update

endfunc
}

image_and_chroot_cleanup () {
startfunc  
    waitfor "rpi_firmware" 1
    waitfor "armstub8-gic" 1
    waitfor "non-free_firmware" 1
    waitfor "rpi_userland" 1
    waitfor "patched_uboot" 1
    waitfor "kernel_debs" 1
    waitfor "rpi_config_txt_configuration" 1
    waitfor "rpi_cmdline_txt_configuration" 1
    waitfor "wifi_firmware_modification" 1
    waitfor "first_boot_scripts_setup" 1
    waitfor "added_scripts" 1
    waitfor "arm64_chroot_setup"
    waitfor "kernel_nondeb_install"
. /tmp/env.txt 
    echo "* Finishing image setup."
    
    echo "* Cleaning up ARM64 chroot"
    chroot /mnt /bin/bash -c "/usr/local/bin/chroot-apt-wrapper \
    autoclean -y $silence_apt_flags"
    
    # binfmt wreaks havoc with the container AND THE HOST, so let it get 
    # installed at first boot.
    umount -l /mnt/var/cache/apt
    echo "Installing binfmt-support files for install at first boot."
    chroot-apt-wrapper -o Dir=/mnt -o APT::Architecture=arm64 \
    -o dir::cache::archives=/mnt/var/cache/apt/archives/ \
    -d install qemu-user-binfmt -qq 2>/dev/null
    
    # Copy in kernel debs generated earlier to be installed at
    # first boot.
    echo "* Copying compiled kernel debs to image for proper install"
    echo "* at first boot and also so we have a copy locally."
    cp "${workdir}"/*.deb /mnt/var/cache/apt/archives/
    #Install better u-boot script
    uboot_script
    sync
    # To stop here "rm /flag/done.ok_to_unmount_image_after_build".
    if [ ! -f /flag/done.ok_to_unmount_image_after_build ]; then
        echo "** Container paused before image unmount. **"
        echo 'Type in "echo 1 > /flag/done.ok_to_unmount_image_after_build"'
        echo "in a shell into this container to continue."
    fi  
    wait_file "/flag/done.ok_to_unmount_image_after_build"
    umount /mnt/build
    umount /mnt/run
    umount /mnt/ccache
    rm -rf /mnt/ccache
    umount /mnt/proc
    umount /mnt/dev/pts
    #umount /mnt/sys
    # This is no longer needed after we are done building the image.
    rm /mnt/usr/bin/qemu-aarch64-static
endfunc
}

image_unmount () {
startfunc
    waitfor "image_and_chroot_cleanup"
. /tmp/env.txt    
    echo "* Unmounting modified ${new_image}.img (This may take a minute or two.)"
    loop_device=$(< /tmp/loop_device)
    umount -l /mnt/boot/firmware || (lsof +f -- /mnt/boot/firmware ; sleep 60 ; \
    umount -f /mnt/boot/firmware) || true
    umount -f /mnt/boot/firmware || true
    #umount /mnt || (mount | grep /mnt)
    e4defrag /mnt >/dev/null || true
    umount -l /mnt || (lsof +f -- /mnt ; sleep 60 ; umount -f /mnt) || true
    umount -f /mnt || true
    #guestunmount /mnt
    echo "* Checking partitions on ${new_image}.img"
    fsck.ext4 -fy /dev/mapper/${loop_device}p2 || true
    fsck.vfat -wa /dev/mapper/${loop_device}p1 || true
    kpartx -dv "${workdir}"/"${new_image}".img &>> /tmp/"${FUNCNAME[0]}".cleanup.log || true
    losetup -d /dev/${loop_device} &>/dev/null || true
    dmsetup remove -f /dev/${loop_device} &>/dev/null || true
    dmsetup info &>> /tmp/"${FUNCNAME[0]}".cleanup.log || true
    # To stop here "rm /flag/done.ok_to_exit_container_after_build".
    if [ ! -f /flag/done.ok_to_exit_container_after_build ]; then
        echo "** Image unmounted & container paused. **"
        echo 'Type in "echo 1 > /flag/done.ok_to_exit_container_after_build"'
        echo "in a shell into this container to continue."
    fi 
    wait_file "/flag/done.ok_to_exit_container_after_build"
endfunc
}

image_export () {
startfunc
    waitfor "image_unmount"
. /tmp/env.txt
    KERNEL_VERS=$(< /tmp/KERNEL_VERS)
    # Note that lz4 is much much faster than using xz.
    chown -R "$USER":"$GROUP" /build
    cd "${workdir}" || exit 1
    [[ $RAWIMAGE ]] && cp "${workdir}/${new_image}.img" \
    "/output/${new_image}-${KERNEL_VERS}_${now}.img"
    [[ $RAWIMAGE ]] && chown "$USER":"$GROUP" \
     "/output/${new_image}-${KERNEL_VERS}_${now}.img"

    [[ $RAWIMAGE ]] && echo "${new_image}-${KERNEL_VERS}_${now}.img created." 
    for i in "${image_compressors[@]}"
    do
     echo "* Compressing ${new_image} with $i and exporting."
     compress_flags=""
     [ "$i" == "lz4" ] && compress_flags="-m"
     compresscmd="$i -v -k $compress_flags ${new_image}.img"
     echo "$compresscmd"
     $compresscmd
     cp "${workdir}/${new_image}.img.$i" \
     "/output/${new_image}-${KERNEL_VERS}_${now}.img.$i"
     #echo $cpcmd
     #$cpcmd
     chown "$USER":"$GROUP" /output/"${new_image}"-"${KERNEL_VERS}"_"${now}".img."$i"
     echo "${new_image}-${KERNEL_VERS}_${now}.img.$i created." 
    done
endfunc
}    

export_log () {
startfunc
if [[ ! $JUSTDEBS ]];
    then
    waitfor "image_export"
    else
    waitfor "kernel_debs"
fi
. /tmp/env.txt

    KERNEL_VERS=$(< /tmp/KERNEL_VERS)
    echo "* Build log at: build-log-${KERNEL_VERS}_${now}.log"
    cat $TMPLOG > /output/build-log-"${KERNEL_VERS}"_"${now}".log
    chown "$USER":"$GROUP" /output/build-log-"${KERNEL_VERS}"_"${now}".log
    echo "** Build appears to have completed successfully. **"
    
endfunc
}

# Delete this by connecting to the container using a shell if you want to 
# debug the container before the image is unmounted.
# The shell command would be something like this:
# docker exec -it `cat ~/docker-rpi4-imagebuilder/build.cid` /bin/bash
# Note that this flag is looked for in the image_and_chroot_cleanup function
echo 1 > /flag/done.ok_to_unmount_image_after_build


# For debugging.
echo 1 > /flag/done.ok_to_continue_after_mount_image

# Arbitrary_wait pause for debugging.
[[ ! $ARBITRARY_WAIT ]] && echo 1 > /flag/done.ok_to_continue_after_here

# Delete this by connecting to the container using a shell if you want to 
# debug the container before the container is exited.
# The shell command would be something like this:
# docker exec -it `cat ~/docker-rpi4-imagebuilder/build.cid` /bin/bash
# Note that this flag is looked for in the image_and_chroot_cleanup function
echo 1 > /flag/done.ok_to_exit_container_after_build


compiler_setup &
[[ ! $JUSTDEBS  ]] && utility_scripts &
[[ ! $JUSTDEBS  ]] && base_image_check
[[ ! $JUSTDEBS  ]] && image_extract &
[[ ! $JUSTDEBS  ]] && image_mount &
[[ ! $JUSTDEBS ]] && rpi_firmware &
[[ ! $JUSTDEBS ]] && armstub8-gic &
[[ ! $JUSTDEBS ]] && non-free_firmware & 
[[ ! $JUSTDEBS ]] && rpi_userland &
[[ ! $JUSTDEBS ]] && patched_uboot &
kernelbuild_setup && kernel_debs &
[[ ! $JUSTDEBS ]] && rpi_config_txt_configuration &
[[ ! $JUSTDEBS ]] && rpi_cmdline_txt_configuration &
[[ ! $JUSTDEBS ]] && wifi_firmware_modification &
[[ ! $JUSTDEBS ]] && first_boot_scripts_setup &
[[ ! $JUSTDEBS ]] && added_scripts &
[[ ! $JUSTDEBS ]] && arm64_chroot_setup &
#[[ ! $JUSTDEBS ]] && image_apt_installs &
[[ ! $JUSTDEBS ]] && kernel_nondeb_install &
[[ ! $JUSTDEBS ]] && image_and_chroot_cleanup &
[[ ! $JUSTDEBS ]] && image_unmount &
[[ ! $JUSTDEBS ]] && image_export &
#[[ ! $JUSTDEBS ]] && spinnerwait image_apt_installs
export_log
# This stops the tail process.
rm $TMPLOG
echo "**** Done."
