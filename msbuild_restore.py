from xml.dom.minidom import parse, parseString
from call_helper import CallHelper

class MsBuild:
    def __init__(self, fileConfig):
        self.FileConfig = fileConfig
    
    def FindMsBuild(self):
        output = CallHelper.call_helper(['YBuild\\bin\\vswhere', '-latest', '-products', '*', '-requires', 'Microsoft.Component.MSBuild', '-property', 'installationPath'])
        if not output[1]:
            vs_path = output[0].rstrip()
        else:
            print "\r\ncould not find Visual Studio installation"
            return False
        self.msbuild_path = vs_path + '\\MSBuild\\15.0\\Bin\\MSBuild.exe'
        return True

    def MsBuildCmdRestore(self, solutionName):
        return [self.msbuild_path
                , '/t:restore'
                , '/p:RestoreConfigFile=' + self.FileConfig
                , solutionName]
        
    def Restore(self, solutionName):
        if not self.FindMsBuild():
            return
        if(len(solutionName) > 0) :
            CallHelper.call_helper(self.MsBuildCmdRestore(solutionName + '.sln'))
        else:
            CallHelper.call_helper(self.MsBuildCmdRestore(''))