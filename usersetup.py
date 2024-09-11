# -*- coding: utf-8 -*-
"""
This program sets up newusers on a remote computer for sshkey 
access only. If a key is provided to this program, it is used
to populate the authorized_keys file on the remote computer.
"""
###
# Credits
###
__author__ = 'George Flanagin'
__copyright__ = 'Copyright 2024, University of Richmond'
__credits__ = None
__version__ = 0.1
__maintainer__ = 'George Flanagin'
__email__ = f'gflanagin@richmond.edu'
__status__ = 'in progress'
__license__ = 'MIT'


import typing
from   typing import *

###
# Standard imports, starting with os and sys
###
min_py = (3, 11)
import os
import sys
if sys.version_info < min_py:
    print(f"This program requires Python {min_py[0]}.{min_py[1]}, or higher.")
    sys.exit(os.EX_SOFTWARE)

###
# Other standard distro imports
###
import argparse
from   collections.abc import *
import contextlib
import getpass
import logging
import tempfile

###
# Installed libraries like numpy, pandas, paramiko
###

###
# From hpclib
###
from   dorunrun import dorunrun
import linuxutils
from   sloppytree import SloppyTree
from   urdecorators import trap
from   urlogger import URLogger

###
# imports and objects that were written for this project.
###

###
# Global objects
###
mynetid = getpass.getuser()
logger = None
login = None
myargs = None

"""
From a conceptual standpoint, we are executing these commands:

echo "$pubkey" > /home/"$username"/.ssh/authorized_keys
"""
remote_commands = SloppyTree({
    'default_group': " grep GROUP /etc/default/useradd ",
    'user_add' : lambda u, uid : f"'useradd -m {uid} -s /bin/bash {u}'",
    'make_ssh_dir' : lambda u : f"'mkdir -p /home/{u}/.ssh'",
    'chmod_ssh_dir' : lambda u : f"'chmod 700 /home/{u}/.ssh'",
    'keyring_perms' : lambda u : f"'chmod 600 /home/{u}/.ssh/authorized_keys'",
    'chown_keyring' : lambda u : f"'chown -R {u} /home/{u}/.ssh'"
    })

@trap
def getuid(u:str) -> str:

    global logger

    try:
        result = dorunrun(f'id -u {u}', return_datatype=dict)
        return f" -u {result['stdout'].strip()}" if result['OK'] else ""

    except Exception as e:
        logger.error(f"Unable to id {u} {e=}")
        return ""


@trap
def make_command(*args) -> str:
    s = "ssh "
    for arg in args:
        s += str(arg) + ' '
    return s


@trap
def loadgroups(user:str, groups:Iterable) -> Iterable:
    """
    format commands to add user to any non-default groups.
    """ 
    global remote_commands, login

    if not groups:
        return tuple()

    result = dorunrun(make_command(login, remote_commands.default_group), return_datatype=str)

    # There should be only one line that matches, so we take the first
    # line, split on =, and take whatever follows the =.
    default_group = result.split('\n')[0].split('=')[-1].strip()

    return tuple(f"'usermod -aG {group} {user}'" 
        for group in groups 
            if group != default_group)


@trap
def loadkeys(keyfiles:Iterable) -> str:
    """
    load zero or more files of public keys into a string
    to be written to the destination's authorized_keys file.
    """
    keydata = ""

    if keyfiles:
        for keyfile in keyfiles:
            with open(keyfile) as f:
                keydata += f.read() + '\n'

    f = tempfile.NamedTemporaryFile(mode='w+t')
    f.write(keydata)
    f.seek(0)

    return f


@trap
def take_action(cmd:str, OK:Iterable={0}) -> int:
    """
    a wrapper around the conditional execution, logging, and
    error handling. The purpose is just to neaten the code.
    """
    global myargs, logger, login

    error_msg = f"${cmd}$ failed."

    if myargs.dry_run:
        logger.info(cmd)
        return os.EX_OK

    if not (result := dorunrun(cmd, return_datatype=bool, OK=OK)):
        logger.error(f"${cmd}$ failed.")
    else:
        logger.info(f"${cmd}$")
    
    return os.EX_OK if result else os.EX_DATAERR
    

@trap
def usersetup_main(myargs:argparse.Namespace) -> int:
    """
    Collect all the information, and issue the commands.
    """
    global login
    login = f'root@{myargs.remote_host}'

    userkeys = loadkeys(myargs.keyfile)
    group_cmds = loadgroups(myargs.user, myargs.group)
    logger.debug(f"{group_cmds=}")
    u = myargs.user

    uid = f" -u {myargs.uid} " if myargs.uid is not None else getuid(myargs.user)
    logger.info(f"{uid=}")

    # Create the user.

    errors = 0

    errors += take_action(make_command(login, remote_commands.user_add(u, uid)), OK={0,9})

    for group in group_cmds:
        errors += take_action(make_command(login, group))

    errors += take_action(make_command(login, remote_commands.make_ssh_dir(u)))

    errors += take_action(make_command(login, remote_commands.chmod_ssh_dir(u)))
    
    if os.path.getsize(userkeys.name):
        errors += ( take_action(f'rsync -a {userkeys.name} {login}:/home/{u}/.ssh/authorized_keys') 
                    if myargs.force else
                    take_action(f'rsync -a --ignore-existing {userkeys.name} {login}:/home/{u}/.ssh/authorized_keys'))

        errors += take_action(make_command(login, remote_commands.keyring_perms(u)))
    else:
        logger.info(f"No keys found in {userkeys.name} to transfer.")

    errors += take_action(make_command(login, remote_commands.chown_keyring(u)))

    errors and sys.stderr.write('One or more errors occurred. Check logfile.')

    return os.EX_OK


if __name__ == '__main__':

    here       = os.getcwd()
    progname   = os.path.basename(__file__)[:-3]
    configfile = f"{here}/{progname}.toml"
    logfile    = f"{here}/{progname}.log"
    lockfile   = f"{here}/{progname}.lock"
    
    parser = argparse.ArgumentParser(prog="usersetup", 
        description="What usersetup does, usersetup does best.")

    parser.add_argument('--dry-run', action='store_true', 
        help="Generate the commands but do not execute them.")

    parser.add_argument('-f', '--force', action='store_true',
        help="Overwrite any existing key files if the user already exists, and has them.")

    parser.add_argument('-g', '--group', action='append', 
        help="non-default groups where the user will be a member.")

    parser.add_argument('-k', '--keyfile', action='append',
        help="One or more files containing public keys to be transferred.")

    parser.add_argument('--loglevel', type=int, 
        choices=range(logging.FATAL, logging.NOTSET, -10),
        default=logging.INFO,
        help=f"Logging level, defaults to {logging.INFO} (INFO)")

    parser.add_argument('-o', '--output', type=str, default="",
        help="Output file name")

    parser.add_argument('-r', '--remote-host', type=str, required=True,
        help="Remote host where the new user will be created.")

    parser.add_argument('-u', '--user', type=str, required=True,
        help="netid of the user being added.")
    
    parser.add_argument('--uid', type=int, default=None,
        help="Explicitly give the UID. The default is to use the user's UID on the source computer if the user exists in LDAP.")

    parser.add_argument('-z', '--zap', action='store_true', 
        help="Remove old log file and create a new one.")

    myargs = parser.parse_args()
    if myargs.zap:
        try:
            os.unlink(logfile)
        except:
            pass
    
    logger = URLogger(logfile=logfile, level=myargs.loglevel)


    try:
        outfile = sys.stdout if not myargs.output else open(myargs.output, 'w')
        with contextlib.redirect_stdout(outfile):
            sys.exit(globals()[f"{progname}_main"](myargs))

    except Exception as e:
        print(f"Escaped or re-raised exception: {e}")

