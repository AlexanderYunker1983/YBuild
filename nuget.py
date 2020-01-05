from xml.dom.minidom import parse, parseString
from call_helper import CallHelper

class NuGet:
    def __init__(self, fileConfig, nugetPath, packPath):
        self.FileConfig = fileConfig
        self.NugetPath = nugetPath
        self.PackPath = packPath
    
    def ParseConfigFile(self, filePath):
        print "\r\n### Parse nuget repositories.config"
        xmlDocument = None
        try:
            datasource = open(self.PackPath + '\\' + filePath, 'r')
            xmlDocument = parse(datasource)
        except IOError:
            print "\r\nINFO: Can not find file\r\n"
            return
        
        if(xmlDocument == None):
            raise Exception('\r\nINFO: Is not xml document\r\n')

        self.packConfig = [pack.getAttribute("path") for pack in xmlDocument.getElementsByTagName("repository")]
        if(len(self.packConfig) == 0):
            print "\r\nINFO: No packages.config\r\n"
            return False 
        else:
            return True
    
    def NugetCmdInstall(self, packConfig, dstPath):
        return [self.NugetPath
                , 'install', packConfig
                , '-ConfigFile', self.FileConfig
                , '-OutputDirectory', dstPath]
        
    def ProcessPackagesConfig(self):
        if(len(self.packConfig) == 0):
            raise Exception("No repositories")
        for pack in self.packConfig:
            fullPackPath = self.PackPath + '\\' + pack
            print "\r\nPackages config: " + fullPackPath + "\r\n"
            CallHelper.call_helper(self.NugetCmdInstall(fullPackPath, self.PackPath))
        
        print "\r\nAll packages config processed\r\n"
        
    def NugetCmdRestore(self, solutionName):
        return [self.NugetPath
                , 'restore'
                , '-ConfigFile', self.FileConfig
                , '-OutputDirectory', self.PackPath
                , solutionName]
        
    def Restore(self, solutionName):
        if(len(solutionName) > 0) :
            CallHelper.call_helper(self.NugetCmdRestore(solutionName + '.sln'))
        else:
            CallHelper.call_helper(self.NugetCmdRestore(''))