function usersetup
{
    alias python=/usr/local/anaconda3/bin/python
    export OLD_PYTHONPATH="$PYTHONPATH"
    export PYTHONPATH=/usr/local/hpclib
    python usersetup.py  $@
    export PYTHONPATH="$OLD_PYTHONPATH"
}
