#!/usr/bin/env python
#-*- coding: utf-8 -*-

import threading
import traceback
import sys
import os
import shutil
import zipfile

from subprocess import Popen, PIPE
from re import search
from datetime import datetime
from call_helper import CallHelper
from os.path import basename

class OtherException(Exception):
    def __init__ (self, value):
        self.value = value
    def __str__(self):
        return self.value
#use valid login and password
def hgcmd(cmd,*args):
    return [
        'hg',
        cmd,
        '--config','auth.spread.username=user',
        '--config','auth.spread.password=password',
        '--config','auth.spread.schemes=http https',
        '--config','auth.spread.prefix=*',
        '--noninteractive',
        ] + list(args)

def GetVersionFromHg(branchName):
    (o,e) = CallHelper.call_helper(hgcmd('log', '--template', 'tag: {tags}&&&&\n', '-l', '5', '-b', branchName))
    logs = o.split("&&&&")
    
    version = ""
                   
    for log in logs:
        line = log.split(None,1)
        if(line.__len__() > 1):
            if line[0] == 'tag:':
                if line[1] != 'tip':
                    version = line[1]
                    break
    return version

def ZipPdb(path, zip_handle):
    for root, dirs, files in os.walk(path):
        for file in files:
            if file.endswith(".pdb"):
                file_path = os.path.join(root,file)
                zip_handle.write(file_path, basename(file_path))

def main():                    
    try:   
        if len(sys.argv) < 5:
            raise OtherException('Enter source dir, Project name, prefix for dest. dir and branch name')
               
        version = GetVersionFromHg(sys.argv[4])
        prefix_dst = sys.argv[3]
        project_name = sys.argv[2]
        src_dir = sys.argv[1]
        
        zipfile_name = version + '.zip'
        zip_file_path = src_dir + '\\' + zipfile_name
        
        zipf = zipfile.ZipFile(zip_file_path, 'w', zipfile.ZIP_DEFLATED)
        ZipPdb(src_dir, zipf)
        
        if len(version) > 0:
            print 'Copy symbol ' + version
            #use symbols server path
            dst_dir = '\\\\server\\ReleaseSymbol\\' + project_name + '\\' + version[:version.rfind('.')] + '\\' + prefix_dst + '\\'
            try:
                os.makedirs(dst_dir)
            except OSError as e:
                pass
                
            shutil.copyfile(zip_file_path, dst_dir + zipfile_name)
        else:
            print "No Change"
                    
    except OtherException as e:
        print "\r\n ERROR:"
        print e.__str__()
               
    except:
        print "\r\nSYS ERROR:"
        traceback.print_exc(file=sys.stdout)
        
if __name__ == "__main__":
    main()