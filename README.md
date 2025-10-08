# usersetup

This program adds users to a remote system in such a way that their
access will be by key. The following are constraints on being able to
execute the program.

## contraints

- The user running the program can login as `root` on the remote system.
    Only `root` can create users and execute the program `chown`.
- The user running this script need not have any special righs on the system where the script is run. IOW,
    as long as `joe@localhost` can become `root@remotehost`, `joe` can run the script.
- The file[s] containing the public keys to be installed on the remote
    system are on localhost, and are readable. This program will create the
    user even if no keys are supplied, but the new user will not be able
    to login until keys are provided. Keys can be added later on by the
    usual means.
- This program will happily use a file with multiple public keys, making
    it suitable for users who have several computers from which they login.
- The desired UID of the user on the remote system either [1] can be discovered
    with the `id` command on the computer where this program is run, or
    [2] is irrelevant and assigned by the remote system.

## What this program does

Why not use the usual command line tools like `ssh-copy-id` and `useradd`
to setup the remote user? From an administrative standpoint, it is tedious
and error prone to login / logout, and ensure that the user for whom
the administrator is creating the account is usable.  The scenario for
`usersetup` is closer to the informal situation:

1. User `fred` wants an account on `remote`.
2. `fred` emails his public key to the administrator.
3. The administrator's saves `fred`'s key to a file on the administrator's own computer.
4. The administrator uses `usersetup` without having to interactively login to `remote`.
5. `fred` has an account.

Here is what happens:

- The remote system is queried to determine the default group name on that system.
- If the UID is not given, usersetup tries to discover it. If it cannot be determined, then the remote system assigns it by whatever algorithm it uses.
- The user on the remote system is created, a home directory is created, and the skeleton files on the remote system are used to provide `.bashrc`, `.bash_profile`, and so on.
- Whatever group scheme is in use on the remote machine (usually UPG), the new user is added to the default group to which all users can belong.
- The group association of the new user's `$HOME` is changed to the default group.
- The permissions on the new user's `$HOME` are set to `2755`.
- A `$HOME/.ssh` directory is created.
- Any keys supplied are added to `$HOME/.ssh/authorized_keys`.
- Permissions and ownership are set appropriately.
- An ed25519 key is created for the user on the remote machine.
- The accounts are propagated to the compute nodes.


## Usage

```
[~]: source usersetup.sh

[~]: choosehost arachne

[~]: usersetup cparish carols.key.pub

```

## Some important things to know:

[1] There is no requirement to use a key that is from an existing `.ssh`
directory, and there is no need to give the key file[s] restricted
permissions. The new `~/.ssh/authorized_keys` file will be given the
correct permissions by the `usersetup` program.

[2] The user being created need not exist on localhost.

[3] If the user already exists on the remote host, you can still use
this command to transfer keys and do the remainder of the setup.

[4] The program can be run anywhere on the network; i.e., the target
computer where the user is to be created can be *this* computer.

[5] The newly created user does not need to run `ssh-keygen` to create
a private/public key pair. In many cases the target computer is one that
is only connected *to* rather than a source of new connections.

[6] Most mistakes are forgiven. If the new user already exists, this program
can be used to append keys.

