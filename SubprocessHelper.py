import subprocess

class SubprocessHelper():

    def __init__(self):
        self.standard_output_stream = []
        self.standard_error_stream = []

    def run(self, command, **kwargs):
        if not command:
            raise Exception, 'Valid command required - fill the list please!'

        p = subprocess.Popen(command,
                             stdout=subprocess.PIPE,
                             stderr=subprocess.PIPE,
                             shell=kwargs.get('shell', False),
                             cwd=kwargs.get('working_directory', None))

        output_stream, error_stream = p.communicate()

        if output_stream:
            self.standard_output_stream = output_stream.strip().split('\n')

        if error_stream:
            self.standard_error_stream = error_stream.strip().split('\n')