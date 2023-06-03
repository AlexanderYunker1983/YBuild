import os
from SubprocessHelper import SubprocessHelper

class Repository():
    def run_repo_command(self, command):
        if command:
            subprocess_helper = SubprocessHelper()
            subprocess_helper.run(command,
                                  shell=False,
                                  working_directory=self.path)

            self.standard_output_stream = subprocess_helper.standard_output_stream
            self.standard_error_stream = subprocess_helper.standard_error_stream

    def update(self):
        self.run_repo_command(self.commands['update'])

    def pull(self):
        self.run_repo_command(self.commands['pull'])

    def purge(self):
        self.run_repo_command(self.commands['purge'])

    def revert(self):
        self.run_repo_command(self.commands['revert'])

    def incoming(self):
        self.run_repo_command(self.commands['incoming'])

    def outgoing(self):
        self.run_repo_command(self.commands['outgoing'])

    def status(self):
        self.run_repo_command(self.commands['status'])

class HgRepository(Repository):
#Use valid login and password
    def __init__(self, repo_path):
        hg_args = ['--config','auth.all.username=user',
        '--config','auth.all.password=password',
        '--config','auth.all.schemes=http',
        '--config','auth.all.prefix=*']
        self.path = repo_path
        self.name = os.path.basename(repo_path)
        self.commands = {'update': ('hg ' + ' '.join(hg_args) + ' update').split(),
                         'pull': ('hg ' + ' '.join(hg_args) + ' pull').split(),
                         'revert': ['hg', 'revert', '--all'],
                         'purge': ['hg', 'purge', '--all'],
                         'status': ['hg', 'status'],
                         'incoming': ('hg ' + ' '.join(hg_args) + ' incoming').split(),
                         'outgoing': ['hg', 'outgoing']}

    def has_pending_commits(self):
        self.status()
        if self.standard_output_stream:
            return True
        else:
            return False

    def supports_incoming(self):
        self.incoming()
        m = 'abort: repository default not found!'
        if self.standard_output_stream:
            return not m in self.standard_output_stream[0]
        else:
            return False

    def supports_outgoing(self):
        self.outgoing()
        m = 'abort: repository default not found!'
        if self.standard_output_stream:
            if len(self.standard_output_stream) > 1:
                return not m in self.standard_output_stream[1]
            else:
                return False
        else:
            return False

class GitRepository(Repository):
    def __init__(self, repo_path):
        self.path = repo_path
        self.name = os.path.basename(repo_path)
        self.commands = {'update': ['git', 'checkout'],
                         'pull': ['git', 'pull'],
                         'revert': ['git', 'reset', '--hard'],
                         'purge': ['git', 'clean', '-f', '-d', '-x'],
                         'status': ['git', 'status']}

    def supports_incoming(self):
        return True

    def supports_outgoing(self):
        return True

def find_repositories(path):
    hg_repository_folder_indicator = '.hg'
    git_repository_folder_indicator = '.git'

    for current_path, dirs, files in os.walk(path):
        if hg_repository_folder_indicator in dirs:
            dirs[:] = [] #no point in searching the branch any further
            yield HgRepository(current_path)
        elif git_repository_folder_indicator in dirs:
            dirs[:] = [] #no point in searching the branch any further
            yield GitRepository(current_path)
