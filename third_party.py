from os import getcwdu
from os.path import split, join, exists, isabs, abspath

def get_3rdparty_dir():
    cwd = getcwdu()
    (pwd,cwdname) = split(cwd)

    custom_path = join(pwd, '3rdparty.path')
    if exists(custom_path):
        with open(custom_path,'rb') as f:
            path = f.read()
            if not isabs(path):
                pwd = abspath(join(pwd, path))
            else:
                pwd = path

    return join(pwd,'3rdparty')
