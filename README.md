# usersetup

This program adds users to a remote system in such a way that their access will be by
key. The following are constraints on being able to execute the program.

- The user running the program can login as `root` on the remote system. Only `root` can create users and execute the program `chown`.
- The file[s] containing the public keys to be installed on the remote system are on localhost, and are readable. The program will create the user even if no keys are supplied, but the new user will not be able to login until keys are provided. They can be added later on by the usual means.
- The desired UID of the user on the remote system is known, or can be discovered with the `id` command, or is supplies as an argument. 

## Usage

```
[~]: usersetup -h
usage: usersetup [-h] [--loglevel {50,40,30,20,10}] [--dry-run]
                 [-g GROUP] [-k KEYFILE] [-o OUTPUT] -r REMOTE_HOST -u
                 USER [--uid UID] [-z]

What usersetup does, usersetup does best.

options:
  -h, --help            show this help message and exit
  --loglevel {50,40,30,20,10}
                        Logging level, defaults to 10
  --dry-run             Generate the commands but do not execute them.
  -g GROUP, --group GROUP
                        non-default groups where the user will be a
                        member.
  -k KEYFILE, --keyfile KEYFILE
                        One or more files containing public keys to be
                        transferred.
  -o OUTPUT, --output OUTPUT
                        Output file name
  -r REMOTE_HOST, --remote-host REMOTE_HOST
                        Remote host where the new user will be
                        created.
  -u USER, --user USER  netid of the user being added.
  --uid UID             Explicitly give the UID. The default is to use
                        the user's UID on the source computer if the
                        user exists in LDAP.
  -z, --zap             Remove old log file and create a new one.
```

## Example

```
source usersetup.sh
usersetup -u gflanagi -k /home/gflanagi/.ssh/id_rsa.pub -z -r adam.richmond.edu
```

Sourcing the `usersetup.sh` file allows you to type `usersetup` instead of 
`python usersetup.py`. That's really all it does, along with making it more
bash-like.

The command above creates a user named `gflanagi` on the remote host `adam.richmond.edu`. 
The user will only be added to the default group on `adam.richmond.edu`, and the key file
to be copied is the one in `gflanagi`'s $HOME on localhost. The `uid` will be sought, and
if found, it will be used. The logfile will be "zapped," 
so that it will contain only results from this operation. 

In the logfile will be these facts:

```
#DEBUG    [2024-09-10 12:32:30,882] (494249 usersetup usersetup_main: group_cmds=())
#INFO     [2024-09-10 12:32:30,883] (494249 usersetup usersetup_main: uid=' -u 222222')
#INFO     [2024-09-10 12:32:30,883] (494249 usersetup take_action: ssh root@adam 'useradd -m -s  -u 222222 /bin/bash gflanagi' )
#INFO     [2024-09-10 12:32:30,883] (494249 usersetup take_action: ssh root@adam 'mkdir -p /home/gflanagi/.ssh' )
#INFO     [2024-09-10 12:32:30,883] (494249 usersetup take_action: ssh root@adam 'chmod 700 /home/gflanagi/.ssh' )
#INFO     [2024-09-10 12:32:30,883] (494249 usersetup take_action: scp /tmp/tmpaknkhe0o root@adam:/home/gflanagi/.ssh/authorized_keys)
#INFO     [2024-09-10 12:32:30,883] (494249 usersetup take_action: ssh root@adam 'chmod 600 /home/gflanagi/.ssh/authorized_keys' )
#INFO     [2024-09-10 12:32:30,883] (494249 usersetup take_action: ssh root@adam 'chown -R gflanagi /home/gflanagi/.ssh' )
```

Some important things to note: 

[1] There is no requirement to use a key that is from an existing `.ssh` directory. 

[2] More than one key can be added. The program takes all the filenames alleged to 
contain keys, concatenates them 
into a secure temporary file, and copies the local file to `~/.ssh/authorized_keys` 
on the remote computer. The temporary file is removed by the OS when the file is closed.

[3] The user need not exist on localhost.

[4] If the user already exists on the remote host, you can still use this command to 
transfer keys and do the remainder of the setup.
