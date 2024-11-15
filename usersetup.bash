function usersetup
{
    if [ -z "$USER_HOST" ]; then
        echo "First .. setup the host using 'choosehost'"
        return
    fi

    if [ -z "$1" ]; then
        echo "Usage: usersetup {netid} [keyfile]"
        echo "  This will setup a user on $USER_HOST"
    fi

    netid="$1"
    uid=$(id -u $netid)
    if [ ! -z "$uid" ]; then
        uid="-u $uid"
    else
        uid=""
    fi

    echo useradd -m "$uid" -s /bin/bash "$netid" > "$netid.sh"
    chmod 700 "$netid.sh"

    echo mkdir -p "/home/$netid/.ssh"  >> "$netid.sh"
    echo chmod 700 "/home/$netid/.ssh" >> "$netid.sh"

    echo touch "/home/$netid/.ssh/authorized_keys" >> "$netid.sh"
    echo chmod 600 "/home/$netid/.ssh/authorized_keys" >> "$netid.sh"
    echo chown -R "$netid" "/home/$netid/.ssh" >> "$netid.sh"

    cat "$netid.sh"

    echo "Copying instructions to $USER_HOST"
    scp "$netid.sh" "root@$USER_HOST:~/."
    if [ ! $? ]; then
        echo "Failed to copy $netid.sh to $USER_HOST"
        return
    fi

    echo "Creating $netid on $USER_HOST"
    ssh "root@$USER_HOST" "~/$netid.sh"
    if [ ! $? ]; then
        echo "Failed to create $netid to $USER_HOST"
        return
    fi

    # If there is a keyfile, then move it over and append it.
    if [ ! -z "$2" ]; then
        echo "Copying $netid.key to $USER_HOST"
        scp "$2" "root@$USER_HOST:~/$netid.key"
        if [ ! $? ]; then
            echo "Unable to copy $2 to $USER_HOST"
            return
        fi
        ssh "root@$USER_HOST" "cat $netid.key >> /home/$netid/.ssh/authorized_keys"
        if [ $? ]; then
            echo "Login key for $netid successfully installed on $USER_HOST"
        else
            echo "Unable to attach key for $netid on $USER_HOST"
        fi
    else
        echo "No key file. You will need to add this later."
    fi
}

function choosehost
{
    if [ -z "$1" ]; then
        echo "Usage: choosehost {hostname}"
    fi

    case "$1" in
        localhost)
            export USER_HOST=$(hostname -s)
            ;;


        *)
            export USER_HOST="$1"
            ;;

    esac
}
