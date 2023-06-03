#!/usr/bin/env python
#-*- coding: utf-8 -*-

# Входные параметры: 1. Путь к файлу change_log.txt 2: Имя ветки
# Идея: Открываем файл chnge_log.txt, считываем первую строку (там должна быть версия(tag) ввиде x.x.x).
# Затем считываем из репозитория (ветка из входных параметров) последние 10 коммитов. 
# Проходим по ним и если встречаем коммит с меткой tag и он неравен tip и номеру версии из файла, записываем его описание в переменную.
# Как только встречаем tag с номером версии из файла останавливаем проход и записываем в начало файла переменную с описаниями, текущее время и первый встреченный tag

import threading
from subprocess import Popen, PIPE
from re import search
import traceback
import sys
from datetime import datetime
from call_helper import CallHelper

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

def OpenFileAndGetLastVersion(FileName):
    try:
        findTag = ""
        fileChangeLog = open(FileName, "r+")
        firstLine = fileChangeLog.readline()
        if len(firstLine) > 3:
            if search('^[0-9]+\.[0-9]+\.[0-9]+',firstLine) is not None:
                findTag = firstLine
        fileChangeLog.close()
        if len(findTag) == 0:
            raise OtherException('Can\'t find tag in file')
        return findTag.rstrip('\r\n')
    except IOError:
        raise OtherException('Can\'t open file {0}'.format(FileName))

def GetCommentsAndVersionFromHg(lastVersion, branchName):
 
    (o,e) = CallHelper.call_helper(hgcmd('log', '--template', 'tag: {tags}&&&&\nsummary: {desc}&&&&\n', '-l', '10', '-b', branchName))
    logs = o.split("&&&&")
    readComments = False
    firstVersion = False
    
    version = ""
    comments = ""
                   
    for log in logs:
        line = log.split(None,1)
        if(line.__len__() > 1):
            if line[0] == 'tag:':
                if line[1] == lastVersion:
                    break
                elif line[1] != 'tip':
                    readComments = True
                    if False == firstVersion:
                        version = line[1]
                        firstVersion = True
            elif line[0] == 'summary:':
                if readComments:
                    comments += line[1] + '\r\n'
                    readComments = False
                    
    return (comments, version)
 
def WriteCommentsAndVersionToFile(FileName, Version, Comments):
    try:
        currentTime = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
        fileChangeLog = open(FileName, "r+")
        
        linesInFile = fileChangeLog.readlines();
        linesInFile.insert(0, 'Change:\r\n' + Comments + '\r\n')
        linesInFile.insert(0, 'Time build: ' + currentTime + '\r\n')
        linesInFile.insert(0, Version + '\r\n')
        
        fileChangeLog.seek(0)
        fileChangeLog.writelines(linesInFile)
        fileChangeLog.close()
        
    except IOError:
        raise OtherException('Can\'t open file {0} to write'.format(FileName))

def main():                    
    try:   
        fileName = 'change_log.txt'
        if len(sys.argv) < 3:
            raise OtherException('Enter path to file ' + fileName + ' and branch name')
        
        fileName = sys.argv[1] + fileName;
        
        (comments, version) = GetCommentsAndVersionFromHg(OpenFileAndGetLastVersion(fileName), sys.argv[2])
        if len(comments) > 0 and len(version) > 0:
            WriteCommentsAndVersionToFile(fileName, version, comments)
            print version + ' ' + comments
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
