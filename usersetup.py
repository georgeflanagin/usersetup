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

"""
From a conceptual standpoint, we are executing these commands:

echo "$pubkey" > /home/"$username"/.ssh/authorized_keys
"""
remote_commands = SloppyTree({
    'default_group': "'cat /etc/default/useradd | grep GROUP'",
    'user_add' : lambda u : f"'useradd -m -s /bin/bash {u}'",
    'make_ssh_dir' : lambda u : f"'mkdir -p /home/{u}/.ssh && chmod 700 /home/{u}/.ssh'",
    'keyring_perms' : lambda u : f"'chmod 600 /home/{u}/.ssh/authorized_keys && chown -R {u} /home/{u}/.ssh'"
    })


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

    default_group = dorunrun(make_command(login, remote_commands.default_group), 
        return_datatype=str)

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

    for keyfile in keyfiles:
        with open(keyfile) as f:
            keydata += f.read() + '\n'

    f = tempfile.NamedTemporaryFile(mode='w+t')
    f.write(keydata)
    f.seek(0)

    return f


@trap
def usersetup_main(myargs:argparse.Namespace) -> int:
    """
    Collect all the information, and issue the commands.
    """
    global login
    login = f'root@{myargs.remote_host}'

    userkeys = loadkeys(myargs.keyfile)
    group_cmds = loadgroups(myargs.groups)
    u = myargs.user

    # Create the user.
    if not (result := dorunrun(make_command(login, remote_commands.user_add(u)),
        return_datatype=bool)):
        logger.error(f'unable to add {u}.')
        sys.exit(os.EX_DATAERR)

    for group in group_cmds:
        if not (result := dorunrun(make_command(login, group), return_datatype=bool)):
            logger.error(f'unable to execute {group}')
            sys.exit(os.EX_DATAERR)

    if not (result := dorunrun(make_command(login, remote_commands.make_ssh_dir(u)),
        return_datatype=bool)):
        logger.error(f'cannot create .ssh dir for {u}')
        sys.exit(os.EX_DATAERR)
        
    
    if not (result := dorunrun(f'scp {login}:{userkeys.name} /home/{u}/.ssh/authorized_keys',
        return_datatype=bool)):
        logger.error(f'unable to create authorized_keys for {u}')
        sys.exit(os.EX_DATAERR)

    if not (result := dorunrun(make_command(login, remote_commands.keyring_perms(u)), 
        return_datatype=bool)):
        logger.error(f'unable to set permissions for {u}')
        sys.exit(os.EX_DATAERR)
    

    return os.EX_OK


if __name__ == '__main__':

    here       = os.getcwd()
    progname   = os.path.basename(__file__)[:-3]
    configfile = f"{here}/{progname}.toml"
    logfile    = f"{here}/{progname}.log"
    lockfile   = f"{here}/{progname}.lock"
    
    parser = argparse.ArgumentParser(prog="usersetup", 
        description="What usersetup does, usersetup does best.")

    parser.add_argument('--loglevel', type=int, 
        choices=range(logging.FATAL, logging.NOTSET, -10),
        default=logging.DEBUG,
        help=f"Logging level, defaults to {logging.DEBUG}")

    parser.add_argument('-g', '--group', action='append', 
        help="non-default groups where the user will be a member.")

    parser.add_argument('-k', '--keyfile', action='append',
        help="One or more files containing public keys to be transferred.")

    parser.add_argument('-o', '--output', type=str, default="",
        help="Output file name")

    parser.add_argument('-r', '--remote-host', type=str, required=True,
        help="Remote host where the new user will be created.")

    parser.add_argument('-u', '--user', type=str, required=True,
        help="netid of the user being added.")
    
    parser.add_argument('--uid', type=int, default=None,
        help="Explicitly give the UID. The default is to use the user's UID on the source computer.")

    parser.add_argument('-z', '--zap', type='store_true', 
        help="Remove old log file and create a new one.")

    myargs = parser.parse_args()
    logger = URLogger(logfile=logfile, level=myargs.loglevel)

    try:
        outfile = sys.stdout if not myargs.output else open(myargs.output, 'w')
        with contextlib.redirect_stdout(outfile):
            sys.exit(globals()[f"{progname}_main"](myargs))

    except Exception as e:
        print(f"Escaped or re-raised exception: {e}")

