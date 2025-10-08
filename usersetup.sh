# Get the default group from the remote machine.
export DEFAULT_GROUP=


function choosehost
{
    if [ -z "$1" ]; then
        cat<<EOF
Usage: choosehost {hostname}

This function sets the target computer for creating
users and installing keys. It sets the environment
variable USER_HOST.
EOF
        return
    fi

    case "$1" in
        localhost)
            export USER_HOST=$(hostname -s)
            ;;


        *)
            export USER_HOST="$1"
            ;;

    esac
    
    local scratchfile="/tmp/$USER_HOST.userdefaults.txt"


    ssh "root@$USER_HOST" "useradd -D" > "$scratchfile"
    DEFAULT_GROUP=$(cat "/tmp/$USER_HOST.userdefaults.txt" | grep "^GROUP=" | cut -d= -f2)
    if [ $? -ne 0 ] || [ -z "$DEFAULT_GROUP" ]; then
        echo "Cannot determine the default group on $USER_HOST"
        exit 1
    fi
    echo "Default group on $USER_HOST is $DEFAULT_GROUP"
    rm -f /tmp/$USER_HOST.userdefaults.txt
}


function userexists
{
    if [ -z "$1" ]; then
        echo "Usage: userexists <username>" >&2
        return 2
    fi

    local user="$1"

    if ! getent passwd "$user" > /dev/null; then
        echo "User '$user' does not exist"
        false
        return
    fi

    if grep -q "^$user:" /etc/passwd; then
        echo "User '$user' exists (local)"
    else
        echo "User '$user' exists (LDAP)"
    fi

    true
}

function groupexists
{
    if [[ $# -ne 1 ]]; then
        echo "Usage: groupexists <groupname>" >&2
        return 2
    fi

    if getent group "$1" > /dev/null; then
        if grep -q "^$1:" /etc/group; then
            echo "Group '$1' exists (local)"
        else
            echo "Group '$1' exists (remote, e.g. LDAP)"
        fi
        true

    else
        echo "Group '$1' does not exist"
        false
    fi
}

function adduserkey
{
    if [ -z "$1" ]; then
        cat<<EOF
    Usage: adduserkey {user} {keyfile}

    This will append the contents of keyfile to the
    .ssh/authorized_keys file of the user. It will
    create the user using the default profile if the
    user does not exist.
EOF
    fi

    if [ $(id -u) -ne 0 ]; then
        echo "addkey must be run as root."
        return
    fi

    user="$1"
    keyfile="$2"
    sshdir="/home/$user/.ssh"
    authkeys="$sshdir/authorized_keys"

    if [ ! userexists "$user" ]; then
        useradd -m "$user"
        echo "User $user added."
    else
        echo "User $user exists."
    fi

    if [ ! -d "/home/$user/.ssh" ]; then
        echo "Creating ssh directory."
        mkdir -p "$sshdir"
        chmod 700 "$sshdir"
        touch "$authkeys"
        chmod 600 "$authkeys"
        chown -R "$user" "$sshdir"
    fi

    if [ -e "$keyfile" ]; then
        cat "$keyfile" >> "$authkeys"
        echo "$keyfile appened to $authkeys"
    else
        "$keyfile not found"
    fi
}

function usersetup
{
    if [ -z "$USER_HOST" ]; then
        echo "First .. setup the host using 'choosehost'"
        return
    fi

    if [ -z "$1" ]; then
        cat<<EOF
Usage: usersetup {netid} [keyfile]
This will setup a user on $USER_HOST.

If you do not supply a keyfile, the function will
look in $PWD for a file that is named "netid.keys",
where netid is the netid of the user you want to
create and set up.
EOF
        return
    fi

    netid="$1"
    keyfile=${2-"$netid".keys}

    ###
    # Explanation: if we find the user already has a known uid,
    #   then we use that id with the "-u uid" construct. If the
    #   value does not exist, we leave it out and let the system
    #   choose a unique id.
    ###
    uid=$(id -u $netid)
    if [ ! -z "$uid" ]; then
        uid="-u $uid"
    else
        uid=""
    fi

    ###
    cat<<EOF
Parameters:
    netid = "$netid"
    keyfile = "$keyfile"
    default_group = "$DEFAULT_GROUP"
    uid = "$uid"
EOF

    # If the user doesn't exist, then we create the user.
    echo useradd -m "$uid" -s /bin/bash "$netid" > "$netid.sh"
    chmod 700 "$netid.sh"
    if [ ! -z "$DEFAULT_GROUP" ]; then
        echo usermod -aG "$DEFAULT_GROUP" "$netid" >> "$netid.sh"
        echo chown "$netid:$DEFAULT_GROUP" "/home/$netid" >> "$netid.sh"
        echo chmod 2755 "/home/$netid" >> "$netid.sh"
    fi

    echo mkdir -p "/home/$netid/.ssh"  >> "$netid.sh"
    echo chmod 700 "/home/$netid/.ssh" >> "$netid.sh"

    echo touch "/home/$netid/.ssh/authorized_keys" >> "$netid.sh"
    echo chmod 600 "/home/$netid/.ssh/authorized_keys" >> "$netid.sh"
    echo chown -R "$netid" "/home/$netid/.ssh" >> "$netid.sh"

    cat "$netid.sh"

    echo "Copying instructions to $USER_HOST"
    scp "$netid.sh" "root@$USER_HOST:~/."
    if [ $? -ne 0 ]; then
        echo "Failed to copy $netid.sh to $USER_HOST"
        return
    fi

    echo "Creating $netid on $USER_HOST"
    ssh "root@$USER_HOST" "~/$netid.sh"
    if [ $? -ne 0 ]; then
        echo "Failed to create $netid to $USER_HOST"
        return
    fi


    # If there is a keyfile, then move it over and append it.
    if [ -e "$keyfile" ]; then
        echo "Copying $netid.key to $USER_HOST"
        scp "$keyfile" "root@$USER_HOST:~/."
        if [ $? -ne 0 ]; then
            echo "Unable to copy $keyfile to $USER_HOST"
            return
        fi
        ssh "root@$USER_HOST" "cat $keyfile >> /home/$netid/.ssh/authorized_keys"
        if [ $? -eq 0 ]; then
            echo "Login key for $netid successfully installed on $USER_HOST"
            ssh "root@$USER_HOST" "chown $netid:$netid /home/$netid/.ssh/authorized_keys"
            ssh "root@$USER_HOST" "sudo -u $netid ssh-keygen -t ed25519 -N '' -f /home/$netid/.ssh/id_ed25519 -q"
            if [ $? -eq 0 ]; then
                echo "key for user $netid generated"
                ssh "root@$USER_HOST" "sudo -u $netid cat /home/$netid/.ssh/*.pub >> /home/$netid/.ssh/authorized_keys"
            else
                echo "key generation for $netid failed."
            fi
        else
            echo "Unable to attach key for $netid on $USER_HOST"
        fi
    else
        echo "No key file. You will need to add this later."
    fi

    echo "Creating account for $uid on the nodes of $USER_HOST"
    ssh root@$USER_HOST "./sync_nodes.sh"
}
