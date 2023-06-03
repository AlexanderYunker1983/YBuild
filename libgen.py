#!/usr/bin/env python
# -*- coding: cp1251 -*-

from __future__ import with_statement

from sys import argv, exit, stdout
from subprocess import Popen, PIPE
from platform import system
from os.path import exists, split, join, isabs, abspath, dirname
from os import mkdir, getcwdu, chdir, environ
from inspect import isfunction
from shutil import rmtree
from traceback import print_exc
from re import sub, search
from os import devnull
from operator import concat
from xml.etree.ElementTree import parse
from collections import namedtuple
from string import whitespace, ascii_letters, digits
from StringIO import StringIO

from SubprocessHelper import SubprocessHelper
from deputils import find_lib, read_deps, filter_deps
from nuget import NuGet
from msbuild_restore import MsBuild
from third_party import get_3rdparty_dir
import CvsUtilities

# местоположение исходников (CMAKE_SOURCE_DIR). Абсолютный путь
SRC_DIR = getcwdu()

# местоположение генеренных cmake файлов (CMAKE_BINARY_DIR) относительно исходников (CMAKE_SOURCE_DIR)
CMAKE_RELATIVE_DIR = "."
args_list = argv[2:]
if '-G' in args_list:
    dashg_idx = args_list.index('-G')
    generator_str = args_list[dashg_idx+1]
    if 'Eclipse' in generator_str:
        CMAKE_RELATIVE_DIR = ".."

GENERATOR_UNIX_MAKEFILES = "Unix Makefiles"
GENERATOR_ECLIPSE4_UNIX_MAKEFILES = "Eclipse CDT4 - Unix Makefiles"
GENERATOR_NMAKE_MAKEFILES = "NMake Makefiles"
GENERATOR_NMAKE_MAKEFILES_VS14 = "NMake Makefiles/VS14"
GENERATOR_NMAKE_MAKEFILES_VS15 = "NMake Makefiles/VS15"
GENERATOR_NMAKE_MAKEFILES_VS16 = "NMake Makefiles/VS16"
GENERATOR_NMAKE_MAKEFILES_VS17 = "NMake Makefiles/VS17"
GENERATOR_VS14 = "Visual Studio 14"
GENERATOR_VS15 = "Visual Studio 15"
GENERATOR_VS16 = "Visual Studio 16"
GENERATOR_VS17 = "Visual Studio 17"
GENERATOR_NONE = "None"

nmake_generators = [GENERATOR_NMAKE_MAKEFILES, GENERATOR_NMAKE_MAKEFILES_VS14,
                    GENERATOR_NMAKE_MAKEFILES_VS15, GENERATOR_NMAKE_MAKEFILES_VS16]
vs_generators = [GENERATOR_NMAKE_MAKEFILES, GENERATOR_NMAKE_MAKEFILES_VS14,
                 GENERATOR_NMAKE_MAKEFILES_VS15, GENERATOR_NMAKE_MAKEFILES_VS16,
                 GENERATOR_NMAKE_MAKEFILES_VS17, GENERATOR_VS14, GENERATOR_VS15,
                 GENERATOR_VS16, GENERATOR_VS17]

umake_generators = [GENERATOR_UNIX_MAKEFILES, GENERATOR_ECLIPSE4_UNIX_MAKEFILES]

blackhole = open(devnull,'w')

if '-v' in args_list:
    blackhole = stdout
    system_gen_args.remove('-v')

if '--verbose' in args_list:
    blackhole = stdout
    system_gen_args.remove('--verbose')

configs = ['Release']
libs = []
custom_build_dir_suffix = ''
use_memory_guard = 0
memory_guard_check_low_bound = 0
memory_guard_check_both_bounds = 0
solution_name = ''

def cmdline_to_string(args):
    newargs = []
    for arg in args:
        if search(r'\s',arg) is not None:
            newargs.append('"' + arg + '"')
        else:
            newargs.append(arg)

    return ' '.join(newargs)

def get_build_code(generator):
    if generator == 'Unix Makefiles': return ''
    elif generator.find('CodeBlocks') != -1: return '_CB'
    elif generator.find('Eclipse CDT4') != -1: return '_Eclipse4'
    elif generator.find('KDevelop') != -1: return '_KDevelop'
    elif generator.find('NMake') != -1:
        return '_NMake_VS' + vs_version
    elif generator.find('Visual Studio') != -1:
        return '_VS' + vs_version
    return 'Unk'

def get_build_tags(generator):
    tags = []

    if system() == 'Windows': tags.append('windows')
    elif system() == 'Linux': tags.append('linux')
    else: raise Exception('get_build_tags: Unknown system type')

    if generator in vs_generators:
        tags.append('vs' + vs_version)

    return tags

def get_build_folder_subdir_name_only(name):
    return '_build_' + name + get_build_code(generator) + custom_build_dir_suffix

def wrap_chdir(func):
    def helper(*args,**kwargs):
        cwd = getcwdu()
        subdir = cwd+'/' + CMAKE_RELATIVE_DIR + '/' + get_build_folder_subdir_name_only(args[0])
        if not exists(subdir): mkdir(subdir)
        chdir(subdir)

        try:
            return func(*args,**kwargs)
        finally:
            chdir(cwd)

    return helper

def call_helper(args,**kwargs):
    quiet = True
    if kwargs['stderr'] is blackhole and kwargs['stdout'] is blackhole and blackhole is not stdout:
        quiet = False
        kwargs['stderr'] = PIPE
        kwargs['stdout'] = PIPE

    p = Popen(args,**kwargs)
    (sstdout,sstderr) = p.communicate()
    ret = p.returncode
    if ret != 0:
        print "Popen failed:", cmdline_to_string(args)
        print "Popen kwargs were:", kwargs
        if not quiet:
            print "STDERR was:"
            print sstderr
            print "STDOUT was:"
            print sstdout
    return ret

if system() == 'Windows':
    import _winreg

    automatic_generators = vs_generators

    automatic_generator = GENERATOR_VS14
    generator = automatic_generator

    def get_lib_path(cfg):
        return '3rdparty\\_lib\\' + cfg + '\\'

    def get_bin_path(cfg):
        return '3rdparty\\_bin\\' + cfg + '\\'

    def get_exe_name(name):
        return name + '.exe'

    def get_lib_names_platform(lib,cfg):
        return [get_lib_path(cfg) + lib.dir + '/' + lib.name + '.lib']

    def detect_best_visual_studio_version():
        versions = ['14.0','12.0','10.0','9.0','8.0']

        k = None
        for version in versions:
            try:
                k = _winreg.OpenKey(_winreg.HKEY_LOCAL_MACHINE,r'Software\Microsoft\VisualStudio\\' + version, 0, _winreg.KEY_READ|512)
                k.Close()
                return version
            except:
                pass

        return '8.0'

    def find_visual_studio(g):
        version = int(vs_version)
        ybuild_dir = dirname(__file__)
        subprocess_helper = SubprocessHelper()
        subprocess_helper.run(join(ybuild_dir ,r'bin\vswhere.exe') +
                              ' -legacy -version [{0},{1}) -latest -property installationPath'.format(version, version + 1), shell=False)
        vs_path = subprocess_helper.standard_output_stream[0]

        if version > 14:
            subprocess_helper = SubprocessHelper()
            subprocess_helper.run(join(ybuild_dir, r'bin\vswhere.exe') +
                                  ' -version [{0},{1}) -latest -requires Microsoft.Component.Msbuild -find MSBuild\**\Bin\MSBuild.exe'.format(version, version + 1), shell=False)
            environ['MSBUILD_PATH'] = subprocess_helper.standard_output_stream[0]
        return join(vs_path, r'Common7\IDE'), join(vs_path,r'Common7\Tools\VsDevCmd.bat')

    def mycall_with_environment(g, args, **kwargs):
        msvs, vcvarsall = find_visual_studio(g)
        if use_amd64:
            arch = "-arch=amd64"
            if g == GENERATOR_VS14 or g == GENERATOR_NMAKE_MAKEFILES_VS14:
                arch = "amd64"

            args = ['call', vcvarsall, arch, '&&'] + args
        else:
            args = ['call', vcvarsall, '&&'] + args

        return mycall(g, args, **kwargs)

    def mycall(g,args,**kwargs):
        kwargs['shell'] = True
        # print args
        return call_helper(args,**kwargs)

elif system() == 'Linux':
    automatic_generators = umake_generators

    automatic_generator = GENERATOR_UNIX_MAKEFILES
    generator = automatic_generator

    def get_lib_path(cfg):
        return '3rdparty/_lib/' + cfg + '/'

    def get_bin_path(cfg):
        return '3rdparty/_bin/' + cfg + '/'

    def get_exe_name(name):
        return name

    def get_lib_names_platform(lib,cfg):
        return [get_lib_path(cfg) + lib.dir + '/lib' + lib.name + '.a']

    def mycall_with_environment(g, args, **kwargs):
        return mycall(g, args, **kwargs)

    def mycall(g,*args,**kwargs):
        return call_helper(*args,**kwargs)

else:
    print 'ERROR: Unknown system [' + system() + '], exiting'
    exit(1)

def create_3rdparty_cmake():
    sio = StringIO()
    sio.write('### Generated by libgen.py, do not modify\n\n')

    if use_amd64:
        sio.write('set(YWIN64 true)\n')
        sio.write('set(CMAKE_STATIC_LINKER_FLAGS "${CMAKE_STATIC_LINKER_FLAGS} /machine:x64")\n')

    sio.write('set(YBUILD_TPLIB_3RDPARTY_PATH \"' + tpdir + '\")\n')

    for dep in libs:
        sio.write('set(YBUILD_TPLIB_' + dep.name.upper() + '_PATH \"' + join(tpdir,dep.dir) + '\")\n')
    sio.write('\n')

    sio.write('set(YBUILD_TPLIBS_PATH\n')
    for dep in libs:
        sio.write('    \"' + join(tpdir,dep.dir) + '\"\n')
    sio.write('    )\n\n')

    sio.write('set(YBUILD_TPLIBS_NAME\n')
    for dep in libs:
        if dep.auto_link != 'false' :
            sio.write('    \"' + dep.name + '\"\n')
    sio.write('    )\n\n')

    for dep in libs:
        sio.write('function(YBUILD_TPLIB_' + dep.name.upper() + '_EXISTS)\n')
        sio.write('endfunction(YBUILD_TPLIB_' + dep.name.upper() + '_EXISTS)\n\n')
        sio.write('function(YBUILD_TPLIB_' + dep.name.upper() + '_' + dep.version.upper().replace('.', '_', 10) + '_EXISTS)\n')
        sio.write('endfunction(YBUILD_TPLIB_' + dep.name.upper() + '_' + dep.version.upper().replace('.', '_', 10) + '_EXISTS)\n\n')

    sio.write('macro(YBUILD_GET_TPLIB_DIR result tplibname)\n')
    for dep in libs:
        if dep.auto_link != 'false' :
            sio.write('    if("${tplibname}" STREQUAL "' + dep.name + '")\n')
            sio.write('        set(${result} "' + dep.dir + '")\n')
            sio.write('    endif()\n\n')
    sio.write('endmacro(YBUILD_GET_TPLIB_DIR)\n\n')

    if YBuildUsingNMake:
        sio.write('function(YBUILD_USING_NMAKE)\n')
        sio.write('endfunction(YBUILD_USING_NMAKE)\n\n')

    result = sio.getvalue()
    result = sub(r'([\\])',r'\\\1',result)

    if exists('3rdparty.cmake'):
        with open('3rdparty.cmake','rb') as f:
            old = f.read()
            if old == result: return

    with open('3rdparty.cmake','wb') as f: f.write(result)

def create_config_header(project_name):
    avail_defines = {
        'ATLMFC8': 'ATLMFC',
        'ATLMFC9': 'ATLMFC',
        'ATLMFC10': 'ATLMFC',
        'ATLMFC12': 'ATLMFC',
        'ATLMFC14': 'ATLMFC',
        'VSCRT8': 'VSCRT',
        'VSCRT9': 'VSCRT',
        'VSCRT10': 'VSCRT',
        'VSCRT12': 'VSCRT',
        'VSCRT14': 'VSCRT',
        'VSCRT15': 'VSCRT',
        'VSCRT16': 'VSCRT'}
    includes = ['TBB', 'XERCESC', 'PUGIXML', 'AES', 'DB', 'PROTOBUF', 'LOG4C', 'CPPUNIT', 'ORBACUS', 'SQLITE', 'SOUNDTOUCH',
        'DB', 'WTL', 'WMSDK', 'DIRECTX', 'PSDK', 'PARAPET', 'MW10DEC', 'AMWSDK', 'WN95SCM', 'BASS', 'MSWORD2000',
        'CYUSB', 'NSP', 'NSIS_PLUGINAPI', 'ATLMFC8', 'ATLMFC9', 'ATLMFC10','ATLMFC12', 'ATLMFC14', 'VSCRT8', 'VSCRT9', 'VSCRT10','VSCRT12','VSCRT14','VSCRT15', 'VSCRT16', "FFMPEG"
        , 'WK', 'LEVELDB', 'CATCH', 'WK10', 'LIVE555', 'OPENCV']
    sio = StringIO()
    sio.write('// Generated by libgen.py, do not modify\r\n\r\n')
    sio.write('#ifndef _Y_YBUILD_CONFIGURATION_COMMON_H_\r\n')
    sio.write('#define _Y_YBUILD_CONFIGURATION_COMMON_H_\r\n\r\n')
    for dep in libs:
        dep_name = dep.name.upper()
        if dep_name in includes:
            dep_name_in_define = dep_name
            if dep_name in avail_defines.keys():
                dep_name_in_define = avail_defines[dep_name]
            sio.write('#define YBUILD_LIB_' + dep_name_in_define + '_AVAIL 1\r\n')
            if dep_name == 'XERCESC':
                sio.write('#define XML_LIBRARY 1\r\n')
    sio.write('#define YBUILD_BUILD_FOLDER_NAME_ONLY ' + get_build_folder_subdir_name_only(project_name) + '\r\n')
    if generator in vs_generators:
        sio.write('#define _BIND_TO_CURRENT_VCLIBS_VERSION 1\r\n')
    if use_memory_guard:
        sio.write('#define YBUILD_USE_MEMORY_GUARD 1\r\n')
    if memory_guard_check_low_bound:
        sio.write('#define YBUILD_DETECT_BUFFER_OVERRUN_LOW 1\r\n')
    if memory_guard_check_both_bounds:
        sio.write('#define YBUILD_DETECT_BUFFER_OVERRUN_BOTH 1\r\n')
    sio.write('\r\n#endif // _Y_YBUILD_CONFIGURATION_COMMON_H_\r\n')
    result = sio.getvalue()
    config_file_name = 'ConfigurationCommon.h'
    if exists(config_file_name):
        with open(config_file_name,'rb') as f:
            old = f.read()
            if old == result: return
    with open(config_file_name,'wb') as f: f.write(result)

def get_spread_target_version(e):
    if 'version' in e.attrib:
        return e.attrib['version']
    else:
        return e.text.strip()

def create_spread_cmake():
    sio = StringIO()
    sio.write('### Generated by libgen.py, do not modify\n\n')

    if exists(SRC_DIR + '/spread-target.xml'):
        spread_target_xml = parse(SRC_DIR + '/spread-target.xml')
        for src in spread_target_xml.findall('sources/source'):
            sio.write('set(YBUILD_SPREAD_' + src.attrib['id'].upper() + '_VERSION' + ' \"' + get_spread_target_version(src) + '\")\n')

    result = sio.getvalue()
    result = sub(r'([\\])',r'\\\1',result)

    if exists('spread.cmake'):
        with open('spread.cmake','rb') as f:
            old = f.read()
            if old == result: return

    with open('spread.cmake','wb') as f: f.write(result)

def gen_and_build(what,args,tobuild):
    if automatic_generator in nmake_generators:
        @wrap_chdir
        def make(what,cfg,lib):
            if mycall_with_environment(automatic_generator, ['nmake',lib.name], stdout=blackhole, stderr=blackhole) != 0:
                raise Exception, 'build('+what+') failed'
    elif automatic_generator in umake_generators:
        @wrap_chdir
        def make(what,cfg,lib):
            if mycall(automatic_generator,['make',lib.name],stdout=blackhole,stderr=blackhole) != 0:
                raise Exception, 'build('+what+') failed'
    else:
        msvs, vcvarsall = find_visual_studio(automatic_generator)
        @wrap_chdir
        def make(what,cfg,lib):
            if mycall_with_environment(automatic_generator,[join(msvs, 'devenv.com'),what+'.sln','/Build',cfg,'/Project',lib.name],stdout=blackhole,stderr=blackhole) != 0:
                raise Exception, 'build('+what+') failed'

    totalcount = len(reduce(concat,tobuild.values()))
    progress = 1

    for cfg in tobuild.keys():
        gen(what,args + ['-DCMAKE_BUILD_TYPE='+cfg],automatic_generator)
        for lib in tobuild[cfg]:
            print '###', str(progress) + '/' + str(totalcount), 'Building', lib.dir, '[' + cfg + ']...'
            stdout.flush()
            progress += 1
            make(what,cfg,lib)

def get_lib_names(lib,cfg):
    if lib.name=='jacorb':
        return [
            get_lib_path(cfg) + lib.dir + '/jacorb.jar',
            get_lib_path(cfg) + lib.dir + '/idl.jar',
            get_lib_path(cfg) + lib.dir + '/jboss-cosnotification.sar',
            get_lib_path(cfg) + lib.dir + '/avalon-framework-4.1.5.jar'
            ]
    if lib.name=='db':
        return [
            get_bin_path(cfg) + lib.dir + '/' + get_exe_name('db_archive'),
            get_bin_path(cfg) + lib.dir + '/' + get_exe_name('db_checkpoint'),
            get_bin_path(cfg) + lib.dir + '/' + get_exe_name('db_deadlock'),
            get_bin_path(cfg) + lib.dir + '/' + get_exe_name('db_dump'),
            get_bin_path(cfg) + lib.dir + '/' + get_exe_name('db_hotbackup'),
            get_bin_path(cfg) + lib.dir + '/' + get_exe_name('db_load'),
            get_bin_path(cfg) + lib.dir + '/' + get_exe_name('db_printlog'),
            get_bin_path(cfg) + lib.dir + '/' + get_exe_name('db_recover'),
            get_bin_path(cfg) + lib.dir + '/' + get_exe_name('db_stat'),
            get_bin_path(cfg) + lib.dir + '/' + get_exe_name('db_verify'),
            ] + get_lib_names_platform(lib,cfg)

    if lib.name=='live555':
        return [
            get_lib_path(cfg) + lib.dir + '/BasicUsageEnvironment.lib',
            get_lib_path(cfg) + lib.dir + '/groupsock.lib',
            get_lib_path(cfg) + lib.dir + '/liveMedia.lib',
            get_lib_path(cfg) + lib.dir + '/UsageEnvironment.lib',
            ]

    if lib.name=='intel-media-sdk':
        if cfg == 'Debug':
            return [
                get_lib_path(cfg) + lib.dir + '/libmfx_d.lib'
            ]
        else:
            return [
                get_lib_path(cfg) + lib.dir + '/libmfx.lib'
            ]

    return get_lib_names_platform(lib,cfg)

def check_libs(libs):
    tobuild = dict()
    for lib in libs:
        if not exists(join(tpdir,lib.dir,'CMakeLists.txt')): continue
        for cfg in configs:
            if all(map(exists,get_lib_names(lib,cfg))):
                stdout.write(" +%s" % cfg)
            else:
                stdout.write(" -%s" % cfg)
                liblist = tobuild.get(cfg,[])
                liblist.append(lib)
                tobuild[cfg] = liblist
        stdout.write(" -- %s_%s\n" % (lib.name, lib.version))
        stdout.flush()
    return tobuild

def cmake_generator_name(g):
    return sub(r'^([^/]*)(/.*)?$',r'\1',g)

def run_custom_script(path):
    print '### Running custom script...'
    execfile(path)

@wrap_chdir
def gen(what,args,g):
    if no_cmake_flag:
        return
    print "### Generating " + what + "..."
    stdout.flush()
    create_3rdparty_cmake()
    create_spread_cmake()
    create_config_header(what)
    generator_args = ['-G',cmake_generator_name(g)]
    if mycall_with_environment(g,[cmake_cmd] + generator_args + cmake_args + ['-DY_SYSTEM='+what] + ['-DYBUILD_EXTENSION_FOR_MANAGED_PROJECTS='+extension_for_managed_projects] + ['-DYBUILD_ENABLE_COM_REGISTRATION='+YBuildEnableComRegistration] + args + [SRC_DIR], stdout=blackhole, stderr=blackhole) != 0:
        raise Exception, 'gen('+what+') failed'

def build_3rdparty(args):
    print "### Checking whether 3rdparty libraries are built..."
    stdout.flush()
    tobuild = check_libs(libs)
    if len(tobuild)>0:
        try:
            gen_and_build('3RDPARTY',args,tobuild)
        finally:
            thirdparty_build_dir = getcwdu() + '/_build_3RDPARTY' + get_build_code(generator)
            if exists(thirdparty_build_dir): rmtree(thirdparty_build_dir)

    if(nuget_cmd != None):
        nugetHelper = NuGet(nuget_cmd + "\\NuGet.Config", nuget_cmd + "\\nuget.exe", "packages")
        nugetHelper.Restore(solution_name)

def hg_checkout(dep):
    print '### Checking out ' + dep.dir + '...'
    #use valid login and password and server path
    srcroot = r'http://hgserver/'
    hgclone_args = [
        srcroot+'/'+dep.dir,
        join(tpdir,dep.dir),
        '--config','auth.spread.username=user',
        '--config','auth.spread.password=password',
        '--config','auth.spread.schemes=http https',
        '--config','auth.spread.prefix=*',
        '--noninteractive'
        ]
    if(automatic_generator != GENERATOR_NONE):
        if mycall(generator,['hg','clone']+hgclone_args, stdout=blackhole, stderr=blackhole) != 0:
            raise Exception, 'hg_checkout('+dep.dir+') failed'
    else:
        if call_helper(['hg','clone']+hgclone_args, stdout=blackhole, stderr=blackhole) != 0:
            raise Exception, 'hg_checkout('+dep.dir+') failed'

def git_checkout(dep):
    print '### Checking out ' + dep.dir + '...'
    srcroot = r'https://github.com/AlexanderYunker1983'
    hgclone_args = [
        srcroot+'/'+dep.dir,
        join(tpdir,dep.dir)
        ]
    if(automatic_generator != GENERATOR_NONE):
        if mycall(generator,['git','clone']+hgclone_args, stdout=blackhole, stderr=blackhole) != 0:
            raise Exception, 'git_checkout('+dep.dir+') failed'
    else:
        if call_helper(['git','clone']+hgclone_args, stdout=blackhole, stderr=blackhole) != 0:
            raise Exception, 'git_checkout('+dep.dir+') failed'


if len(argv) < 2:
    print "ERROR: Not enough args!"
    print "USAGE: libgen.py <PROJECT> [args...]"
    exit(1)

system_name = argv[1]
system_gen_args = argv[2:]
no_cmake_flag = False
no_3rdparty_update = False
use_amd64 = False

if '-G' in system_gen_args:
    dashg_index = system_gen_args.index('-G')
    generator = system_gen_args[dashg_index+1]
    del system_gen_args[dashg_index:dashg_index+2]

if '--no-blackhole' in system_gen_args:
    blackhole = stdout
    system_gen_args.remove('--no-blackhole')

if '--custom-build-dir-suffix' in system_gen_args:
    custom_build_dir_suffix_index = system_gen_args.index('--custom-build-dir-suffix')
    custom_build_dir_suffix = system_gen_args[custom_build_dir_suffix_index + 1]
    system_gen_args.remove('--custom-build-dir-suffix')

if '--memory-guard' in system_gen_args:
    use_memory_guard = 1
    system_gen_args.remove('--memory-guard')

if '--memory-guard-low' in system_gen_args:
    use_memory_guard = 1
    memory_guard_check_low_bound = 1
    system_gen_args.remove('--memory-guard-low')

if '--memory-guard-both' in system_gen_args:
    use_memory_guard = 1
    memory_guard_check_both_bounds = 1
    system_gen_args.remove('--memory-guard-both')

if '--release' in system_gen_args:
    cmake_args = ['-DCMAKE_BUILD_TYPE=Release']
    system_gen_args.remove('--release')
elif '--release_with_info' in system_gen_args:
    cmake_args = ['-DCMAKE_BUILD_TYPE=RelWithDebInfo']
    system_gen_args.remove('--release_with_info')
    configs.append('RelWithDebInfo')
else:
    cmake_args = []
    configs.insert(0, 'Debug')

if '--x32' in system_gen_args:
    cmake_args.append('-DY_X32=1')
    system_gen_args.remove('--x32')

if '--xp-toolset' in system_gen_args:
    if generator in GENERATOR_VS14:
        cmake_args.append('-Tv140_xp')
    elif generator in [GENERATOR_NMAKE_MAKEFILES_VS14]:
        cmake_args.append('-DUSE_VS13_NMAKE_XP_HACK=1')
    system_gen_args.remove('--xp-toolset')

if '--brand-name' in system_gen_args:
    dashg_index = system_gen_args.index('--brand-name')
    brand_name = system_gen_args[dashg_index+1]
    del system_gen_args[dashg_index:dashg_index+2]
else:
    brand_name = system_name

if '--x64' in system_gen_args:
    use_amd64 = True
    system_gen_args.remove('--x64')

if '--solution-name' in system_gen_args:
    dashg_index = system_gen_args.index('--solution-name')
    solution_name = system_gen_args[dashg_index+1]
    system_gen_args.remove('--solution-name')

if '--no-cmake' in system_gen_args:
    no_cmake_flag = True
    system_gen_args.remove('--no-cmake')

if '--no-3rdparty-update' in system_gen_args:
    no_3rdparty_update = True
    system_gen_args.remove('--no-3rdparty-update')


cmake_args.append('-DCMAKE_BRAND_NAME='+brand_name)

actions = []
tpdir = get_3rdparty_dir()

if not exists(tpdir): mkdir(tpdir)

if generator in automatic_generators:
    automatic_generator = generator

if generator in vs_generators:
    vs_version = generator[-2:]

extension_for_managed_projects = 'vcxproj'

tags = get_build_tags(generator)
libs = filter_deps(read_deps(parse('3rdparty.xml')),tags)
for dep in libs:
    if not exists(join(tpdir,dep.dir)):
        def helper(d): actions.append(dict(name='%s_checkout(' % d.cvs + d.dir+')', fn=lambda: globals()['%s_checkout' % d.cvs](d)))
        helper(dep)


@wrap_chdir
def run_nmake(what):
    print '### Compiling ' + what + '...'
    if mycall_with_environment(automatic_generator, ['nmake', 'all'], stdout=stdout, stderr=blackhole) != 0:
        raise Exception, 'nmake all (' + what + ') failed'

if(automatic_generator != GENERATOR_NONE):
    if system() == 'Windows':
        if (no_cmake_flag):
            cmake_cmd = None
        else:
            cmake_cmd = join(tpdir,find_lib(libs,'cmake').dir,'bin','cmake.exe')
        try:
            nuget_cmd = join(tpdir,find_lib(libs,'nuget').dir)
        except:
            nuget_cmd = None
    elif system() == 'Linux':
        cmake_cmd = join(tpdir,find_lib(libs,'cmake').dir,'bin','cmake')
        nuget_cmd = None

    if not no_3rdparty_update:
        actions.append(dict(name='3rdparty update',fn=lambda: CvsUtilities.clean_update_3rdparty(tpdir, libs)))

    if system_name != '3RDPARTY':
        actions.append(dict(name='build_3rdparty',fn=lambda: build_3rdparty(system_gen_args)))

    if not no_cmake_flag:
        actions.append(dict(name='gen('+system_name+')',fn=lambda: gen(system_name,system_gen_args,generator)))

    if exists('Configuration/projgen.py'):
        actions.append(dict(name='custom gen(' + system_name + ')', fn=lambda: run_custom_script('Configuration/projgen.py')))

    if generator in nmake_generators:
        YBuildEnableComRegistration = '1'
        YBuildUsingNMake = True
        actions.append(dict(name='nmake('+system_name+')', fn=lambda: run_nmake(system_name)))
    else:
        YBuildEnableComRegistration = '0'
        YBuildUsingNMake = False
        if generator not in umake_generators:
            cmake_args.append('-A')
            if use_amd64:
                 cmake_args.append('x64')
            else:
                cmake_args.append('Win32')

print 'collected ' + str(len(actions)) + ' actions:'
print '\n'.join('     {0}: {1}'.format(*k) for k in enumerate([a['name'] for a in actions]))

for action in actions:
    try:
        action['fn']()
    except Exception, e:
        print 'ERROR: [exception] ' + action['name'] + ': ' + str(e)
        print_exc()
        exit(1)
