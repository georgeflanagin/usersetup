# usersetup

This program adds users to a remote system in such a way that their
access will be by key. The following are constraints on being able to
execute the program.

- The user running the program can login as `root` on the remote system. Only `root` can create users and execute the program `chown`.
- The file[s] containing the public keys to be installed on the remote system are on localhost, and are readable. The program will create the user even if no keys are supplied, but the new user will not be able to login until keys are provided. Keys can be added later on by the usual means.
- The desired UID of the user on the remote system is [1] supplied as an argument, or [2] can be discovered with the `id` command, or [3] is irrelevant and assigned by the remote system.

## About

Why not use the usual command line tools like `ssh-copy-id` and `useradd`
to setup the remote user? From an administrative standpoint, it is tedious
and error prone to login / logout, and ensure that the user for whom
the administrator is creating the account is usable.  The scenario for
`usersetup` is closer to the informal situation:

1. User `fred` wants an account on `remote`.
2. `fred` emails his public key to the administrator.
3. The administrator's saves `fred`'s key to a file on the administrator's own computer.
4. The administrator uses `usersetup` without having to interactively login to `remote`.
5. The permissions get set correctly for `fred` to use his account.

## Usage

```
[~]: source usersetup.sh

[~]: choosehost arachne

[~]: usersetup cparish carols.key.pub

```

## Example

```
source usersetup.sh
usersetup -u gflanagi -k /home/gflanagi/.ssh/id_rsa.pub -z -r adam.richmond.edu
```


## Some important things to know:

[1] There is no requirement to use a key that is from an existing `.ssh`
directory, and there is no need to give the key file[s] restricted
permissions. The new `~/.ssh/authorized_keys` file will be given the
correct permissions by the `usersetup` program.

[2] The user need not exist on localhost.

[3] If the user already exists on the remote host, you can still use this command to
transfer keys and do the remainder of the setup.

[4] The program can be run anywhere on the network; i.e., the target computer where
the user is to be created can be *this* computer.

[5] The newly created user does not need to run `ssh-keygen` to create a private/public
key pair. In many cases the target computer is one that is only connected *to* rather than
a source of new connections.

