###
# Collect the information when we load this
# collection of functions.
###
pools=$(zpool list | tail -n 2 | awk '{print $1}' | tr '\n' ' ')
npools=$(zpool list | tail -n 2 | grep -c $)
for default_pool in $pools; do break; done

unalias dh >/dev/null 2>&1
function dh
{
    zfs list -o name,used,available,refer,usedbydataset,usedbysnapshots,usedbychildren,usedbyrefreservation
}

function zfs_check
{
    case $1 in
        0)
            echo Success
            true
        ;;

        1)
            echo Failure
            false
        ;;

        2)
            echo Bad option in command
            false
        ;;

    esac
}

function validate_user
{
    if [ "$EUID" -ne 0 ] && [ -z "$SUDO_USER" ]; then
        echo "This script must be run as root or with sudo."
        # 10 is the usual exit code for failure to be root-ed.
        exit 10
    fi
}


###
# Datasets
###
function create_dataset
{
    if [ -z $1 ]; then
        echo "Usage: ${FUNCNAME[0]} {dataset} ['share'] [pool]"
        return
    fi

    validate_user
    local share=${2:-}
    local pool=${3:-$default_pool}
    local dataset=$1
    zfs create "${pool}/${dataset}"
    if not zfs_check $? ; then
        return
    fi
    if [ $share == "share" ]; then
        zfs set sharenfs="rw,noexec,nosuid" "${pool}/${dataset}"
        zfs_check $?
    fi

}

function destroy_dataset
{
    if [ -z $1 ]; then
        echo "Usage: ${FUNCNAME[0]} {dataset} [pool]"
        return
    fi

    validate_user
    local pool=${2:-$default_pool}
    local dataset=$2
    zfs destroy "${pool}/${dataset}"
    zfs_check $?
}

###
# Permissions
###
function grant
{
    if [ -z $5 ]; then
        echo "Usage: ${FUNCNAME[0]} {privs} on {file_or_directory} for|to {user|group}"
        echo "   privs: any or all of create,read,write,execute,delete using"
        echo "          commas but *not* spaces to separate them. If you use"
        echo "          the word 'all', then all five permissions are granted."
        return
    fi

    local privs="$1"
    if [ "$privs" == "all" ]; then
        privs="create,delete,read,write,execute"
    fi
    local dataset="$3"
    local u="$5"
    zfs set aclinherit=passthrough "$dataset"
    zfs allow "$u" "$privs" "$dataset"
    zfs_check $?
    zfs allow $dataset
}

function revoke
{
    if [ -z $5 ]; then
        echo "Usage: ${FUNCNAME[0]} {privs} on {file_or_directory} for|to {user|group}"
        echo "   privs: any or all of create,read,write,execute using"
        echo "          commas but *not* spaces to separate them."
        return
    fi

    local privs="$1"
    local dataset="$3"
    local u="$5"
    zfs unallow "$u" "$privs" "$dataset"
    zfs_check $?
}


###
# Quotas
###
function remove_quota
{
    if [ -z $1 ]; then
        echo "Usage: ${FUNCNAME[0]} {dataset} [pool]"
        return
    fi

    validate_user
    local pool=${2:-$default_pool}
    local dataset=$1
    zfs set quota=none "${pool}/${dataset}"
    zfs_check $?
}

function set_quota
{
    if [ -z $1 ]; then
        echo "Usage: ${FUNCNAME[0]} {dataset} {size} [pool]"
        return
    fi

    validate_user
    local pool=${3:-$default_pool}
    local dataset=$1
    local size=$2
    zfs set quota=${size} "${pool}/${dataset}"
    zfs_check $?
}

###
# Reservations
###
function set_reservation
{
    if [ -z $1 ]; then
        echo "Usage: ${FUNCNAME[0]} {dataset} {size} [pool]"
        return
    fi

    validate_user
    local pool=${3:-$default_pool}
    local dataset=$1
    local size=$2
    zfs set reservation=${size} "${pool}/${dataset}"
    zfs_check $?
}

function remove_reservation
{
    if [ -z $1 ]; then
        echo "Usage: ${FUNCNAME[0]} {dataset} [pool]"
        return
    fi

    validate_user
    local pool=${2:-$default_pool}
    local dataset=$1
    zfs set reservation=none "${pool}/${dataset}"
    zfs_check $?
}

echo "Use 'helpzfs' to list the commands in this file."

function helpzfs
{
    echo " "
    create_dataset
    echo " "
    destroy_dataset
    echo " "
    grant
    echo " "
    revoke
    echo " "
    remove_quota
    echo " "
    set_quota
    echo " "
    set_reservation
    echo " "
    remove_reservation
    echo " "
}
