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
min_py = (3, 8)
import os
import sys
if sys.version_info < min_py:
    print(f"You are using {sys.version_info}.")
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
import setutils
import socket
from   urdecorators import trap
from   urlogger import URLogger

###
# imports and objects that were written for this project.
###

###
# Global objects
###
logger = None
login = None
myargs = None
group_dict = linuxutils.group_dicts()

"""
"""
class SystemParams:
    """
    Convenient way to store the parameters for the target system
    where we will be creating the users.
    """
    def __init__(self) -> None:
        """
        Go find the information the target system. Primarily, we
        are interested in the default GID and the UID whose
        value divides the priv from non-priv users.
        """
        self.hostname = socket.gethostname()

        result = dorunrun(f"useradd -D", return_datatype=str)
        self.default_group = int(
            [line.split('=')[-1].strip() for line in result.split('\n') if 'GROUP' in line][0]
            )

        result = dorunrun(f"cat /etc/login.defs", return_datatype=str)
        self.min_UID = int(
            [line.split()[-1].strip() for line in result.split('\n') if 'UID_MIN' in line][0]
            )

S = SystemParams()

class UserInfo:
    """
    Immutable object to collect the information that we use to construct
    a new user on the system.
    """
    def __init__(self, username:str, *,
        UID:int = -1,
        flags:Iterable = setutils.PHI,
        groups:Iterable = setutils.PHI,
        keyfiles:Iterable = setutils.PHI) -> None:

        """
        Setup the object from the parameters.
        """
        self.username = username
        self.flags = frozenset(flags)
        self.groups = frozenset(groups)
        self.keyfiles = frozenset(keyfiles)
        self.keys = self.loadkeys(self.keyfiles)

        self.UID = self.getuid(username) if 0 > UID else UID


    def getuid(self, u:str) -> str:

        try:
            return int(dorunrun(f'id -u {u}', return_datatype=str).strip())

        except Exception as e:
            return linuxutils.next_uid()


    def loadkeys(self, files:Iterable) -> str:
        """
        load zero or more files of public keys into a string
        to be written to the destination's authorized_keys file.
        """
        keydata = ""

        if self.keyfiles:
            for keyfile in self.keyfiles:
                with open(keyfile) as f:
                    keydata += f.read() + '\n'

        return keydata


@trap
def touch(path:str) -> bool:
    try:
        with open(path, 'a'):
            os.utime(path, None)

        return True

    except:
        return False

@trap
def usersetup_main(myargs:argparse.Namespace) -> int:
    """
    Collect all the information, and issue the commands.
    """
    global logger, S
    if 'nodefaultgroup' not in myargs.flags:
        myargs.group.append(S.default_group)

    U = UserInfo(myargs.user,
            UID=myargs.uid,
            groups=myargs.group,
            keyfiles=myargs.keyfile)

    # Fundamental setup first.
    try:
        cmd = f"useradd -u {U.UID} -m -s /bin/bash {U.username}"
        if not (OK := dorunrun(cmd, return_datatype=bool)):
            logger.error(f"Failed. {cmd=}")
        logger.info(f'User {U.username} created.')

        home_dir = f'/home/{U.username}'
        ssh_dir = f'{home_dir}/.ssh'
        scratch_dir = f'/scratch/{U.username}'
        keys_file = f'{ssh_dir}/authorized_keys'
        logger.info(f'set directory names for {U.username}')

        os.makedirs(ssh_dir, exist_ok=True)
        os.makedirs(scratch_dir, exist_ok=True)
        touch(keys_file)
        try:
            os.symlink(scratch_dir, f'{home_dir}/scratch')
        except:
            pass
        logger.info('files and directories created.')


        os.chmod(ssh_dir, 0o700)
        os.chmod(keys_file, 0o600)
        os.chmod(scratch_dir, 0o2755)
        os.chown(keys_file, U.UID, -1)
        os.chown(scratch_dir, U.UID, -1)
        os.chown(ssh_dir, U.UID, -1)
        logger.info('Permissions and owners set')


    except Exception as e:
        logger.error(e)
        return os.EX_DATAERR

    # Let's take care of any additional groups.
    try:
        for g in U.groups:
            cmd = f"usermod -aG {g} {U.username}"
            if not (OK := dorunrun(cmd, return_datatype=bool)): raise Exception()
    except Exception as e:
        logger.error(f"Failed to add {U.username} to {g}")


    # And add keys to the keyring if there are any.
    mode = 'w' if 'replacekeys' in U.flags else 'a'
    if U.keys:
        with open(keys_file, mode) as f:
            f.write(U.keys)

    return os.EX_OK


if __name__ == '__main__':

    if os.getuid():
        print("You are not root.")
        sys.exit(os.EX_CONFIG)

    here       = os.getcwd()
    progname   = os.path.basename(__file__)[:-3]
    configfile = f"{here}/{progname}.toml"
    logfile    = f"{here}/{progname}.log"
    lockfile   = f"{here}/{progname}.lock"

    parser = argparse.ArgumentParser(prog="usersetup",
        description="What usersetup does, usersetup does best.")

    parser.add_argument('--faculty', action='store_true',
        help="This user is faculty.")

    parser.add_argument('-g', '--group', action='append',
        default=[],
        help="non-default groups where the user will be a member.")

    parser.add_argument('-k', '--keyfile', action='append',
        default=[],
        help="One or more files containing public keys to be transferred.")

    parser.add_argument('--loglevel', type=int,
        choices=range(logging.FATAL, logging.NOTSET, -10),
        default=logging.INFO,
        help=f"Logging level, defaults to {logging.INFO} (INFO)")

    parser.add_argument('--no-default-group', action='store_true',
        help="Do not add user to default group.")

    parser.add_argument('-o', '--output', type=str, default="",
        help="Output file name")

    parser.add_argument('--replace-keys', action='store_true',
        help="Overwrite any existing keys in authorized_keys.")

    parser.add_argument('-u', '--user', type=str, required=True,
        help="netid of the user being added.")

    parser.add_argument('--uid', type=int, default=-1,
        help="Explicitly give the UID. The default is to use the user's UID on the source computer if the user exists in LDAP.")

    parser.add_argument('-z', '--zap', action='store_true',
        help="Remove old log file and create a new one.")

    myargs = parser.parse_args()

    # Set the flags.
    myargs.flags = set()
    if myargs.no_default_group: myargs.flags.add('nodefaultgroup')
    if myargs.replace_keys: myargs.flags.add('replacekeys')
    if myargs.faculty: myargs.group.append('faculty')

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

