import sys
import os
from os.path import exists, split, join
import CvsHelper
from xml.etree.ElementTree import parse
from deputils import find_lib, read_deps, filter_deps
from sys import platform
from third_party import get_3rdparty_dir


def getseparator():
    separator = '\\'
    if platform == "linux" or platform == "linux2" or platform == "darwin":
        separator = '/'
    return separator

def process_command_line():
    from optparse import OptionParser

    usage = "usage: %prog [options] search_path"
    parser = OptionParser(usage=usage, version="%prog v")
    parser.disable_interspersed_args()
    parser.add_option("-p", "--pull", action="store_true",
                                      dest="pull",
                                      help="Pull remote changes to local \
                                      repository")
    parser.add_option("-d", "--pullupdate", action="store_true",
                                          dest="pullupdate",
                                          help="Pull remote changes to local \
                                                repository and update to \
                                                tip.")
    parser.add_option("-u", "--update", action="store_true",
                                         dest="update",
                                         help="Update local repositories to \
                                               tip.")
    parser.add_option("-t", "--thirdparty", action="store_true",
                                         dest="thirdparty",
                                         help="Process third party repositories.")
    parser.add_option("-c", "--currentrepo", action="store_true",
                                         dest="workwithcurrentrepo",
                                         help="Process current repository only.")
    parser.add_option("", "--currentrepothirdparty", action="store_true",
                                         dest="workwiththirdpartyincurrentrepo",
                                         help="Process third party for current repository only.")
    options, args = parser.parse_args(args=None, values=None)
    if not options.pull and not options.pullupdate and not options.update and not options.thirdparty and not options.workwiththirdpartyincurrentrepo and not options.workwithcurrentrepo:
        options.workwiththirdpartyincurrentrepo = True
    if len(args) != 0:
        argsForRemove = []
        for argstr in args:
            if not exists(argstr):
                argsForRemove.append(argstr)
            elif not os.path.isabs(argstr):
                argsForRemove.append(argstr)
            else:
                temppath = os.path.abspath(argstr)
                if not exists(temppath):
                    argsForRemove.append(argstr)
        for argstr in argsForRemove:
            args.remove(argstr)
    if len(args) == 0:
        tpdir = get_3rdparty_dir()
        tags = []
        libs = read_deps(parse(os.getcwd()+getseparator()+'3rdparty.xml'))
        for dep in libs:
            print join(tpdir,dep.dir)
            args.append(join(tpdir,dep.dir))
        if options.workwiththirdpartyincurrentrepo:
            print 'Thirdparty updating...'
        elif options.workwithcurrentrepo:
            args.append(os.getcwd())
        else:
            args = [os.getcwd()+getseparator()+'..']
    return options, args

def print_repo_error(repo):
    print repo.standard_error_stream

def has_repo_error_occured(repo):
    if repo.standard_error_stream:
        return True
    else:
        return False

def pull_update_repo(repo):
    repo.revert()
    if has_repo_error_occured(repo):
            print_repo_error(repo)
    repo.purge()
    if has_repo_error_occured(repo):
            print_repo_error(repo)
    if not pull_repo(repo):
        return
    update_repo(repo)


def pull_repo(repo):
    if repo.supports_incoming():
        print 'Pulling changes for %s' % repo.path
        repo.pull()
        if has_repo_error_occured(repo):
            print_repo_error(repo)
            return False

        print ' '.join(repo.standard_output_stream) + '\n'
        return True
    else:
        print repo.path, "isn't configured to pull..."

    return False

def update_repo(repo):
    print 'Updating %s' % repo.path
    repo.update()
    if has_repo_error_occured(repo):
        print_repo_error(repo)
        return False

    print ' '.join(repo.standard_output_stream)
    return True

def process_repo_based_on_options(repo, options):
    if options.pullupdate:
        pull_update_repo(repo)

    elif options.pull:
        pull_repo(repo)

    elif options.update:
        update_repo(repo)

    else:
        pull_update_repo(repo)

def main():
    options, args = process_command_line()
    print options
    print args
    for arg in args:
        path = os.path.abspath(arg)

        print 'Searching %s...' % path

        for repo in CvsHelper.find_repositories(path):
            repo.relative_repo_path = os.path.relpath(repo.path, path)

            if not options.thirdparty and not options.workwiththirdpartyincurrentrepo:
                if "3rdparty" in repo.relative_repo_path:
                    continue
            process_repo_based_on_options(repo, options)
            print '#####################################################'
    return 0

def clean_update_3rdparty(tpdir, libs):
    for lib in libs:
        path = join(tpdir, lib.dir)

        print 'Searching %s...' % path

        for repo in CvsHelper.find_repositories(path):
            repo.relative_repo_path = os.path.relpath(repo.path, path)

            pull_update_repo(repo)
            print '#####################################################'
    return 0


if __name__ == '__main__':
    status = main()
    sys.exit(status)
