import threading
from subprocess import Popen, PIPE
from re import search
import sys

class CallHelper(object):
    @staticmethod
    def cmdline_to_string(args):
        newargs = []
        for arg in args:
            if search(r'\s',arg) is not None:
                newargs.append('"' + arg + '"')
            else:
                newargs.append(arg)
        
        return ' '.join(newargs)
    
    @staticmethod
    def call_helper(*args,**kwargs):
        return CallHelper.call_helper_internal(0, *args, **kwargs)
    
    @staticmethod
    def call_helper_ignoring_result(*args,**kwargs):
        return CallHelper.call_helper_internal(1, *args, **kwargs)
    
    @staticmethod
    def call_helper_internal(ignore_result,*args,**kwargs):
        print "CMD:", CallHelper.cmdline_to_string(args[0])
        kwargs['stderr'] = PIPE
        kwargs['stdout'] = PIPE
        p = Popen(*args,**kwargs)
        sstdout_lines = []
        sstderr_lines = []
        def echo_filter_stdout():
            for line in p.stdout:
                sstdout_lines.append(line)
                print 'STDOUT:', line,
        def echo_filter_stderr():
            for line in p.stderr:
                sstderr_lines.append(line)
                print 'STDERR:', line,
    
        tout = threading.Thread(None,echo_filter_stdout)
        terr = threading.Thread(None,echo_filter_stderr)
        
        tout.start()
        terr.start()
        
        p.wait()
        
        tout.join()
        terr.join()
        
        ret = p.returncode
        if (0 == ignore_result) and (0 != ret):
            print 'CMD FAILED WITH:', ret
            raise Exception('Command failed: ' + CallHelper.cmdline_to_string(args[0]))
            
        return (''.join(sstdout_lines),''.join(sstderr_lines))