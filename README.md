# usersetup

This program adds users to a remote system in such a way that their access will be by
key. The following are constraints on being able to execute the program.

- The user running the program can login as `root` on the remote system. Only `root` can create users and execute the program `chown`.
- The file[s] containing the public keys to be installed on the remote system are on localhost, and are readable. The program will create the user even if no keys are supplied, but the new user will not be able to login until keys are provided. They can be added later on by the usual means.
- The desired UID of the user on the remote system is known, or can be discovered with the `id` command, or is supplies as an argument. 

## Usage

```bash
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
