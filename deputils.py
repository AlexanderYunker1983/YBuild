#!/usr/bin/env python

from collections import namedtuple
from string import whitespace, ascii_letters, digits

class Dependency(namedtuple('Dependency','name version cond cond_text auto_link cvs')):
    @property
    def dir(self): return self.name + '_' + self.version

def find_lib(libs,name):
    for lib in libs:
        if lib.name==name: return lib
    raise Exception('find_lib: Library %s wasn\'t found' % name)

def read_deps(xml):
    def lex_cond(s):
        lexemes = []
        identifier_chars = ascii_letters + digits + '.-_'
        
        while len(s) > 0:
            if s[0] in whitespace: s = s[1:]
            elif s[0] in '()':
                lexemes.append(s[0])
                s = s[1:]
            elif s[0] in identifier_chars:
                identifier = ''
                while len(s) > 0 and s[0] in identifier_chars:
                    identifier = identifier + s[0]
                    s = s[1:]
                lexemes.append(identifier)
            else: raise Exception('lex_cond: Unknown symbol %s' % s[0])
        
        return lexemes

    def parse_cond(lexemes):
        oprs = ['and','or','not']
        cmds = []
        
        def calc_or(stack,tags): stack[-2:] = [stack[-1] or stack[-2]]
        def calc_and(stack,tags): stack[-2:] = [stack[-1] and stack[-2]]
        def calc_not(stack,tags): stack[-1] = not stack[-1]
        def calc_true(stack,tags): stack.append(True)
        
        def parse_cond_binary(parse_left,op,calc):
            parse_left()
            if len(lexemes) > 0 and lexemes[0] == op:
                del lexemes[0]
                parse_cond_binary(parse_left,op,calc)
                cmds.append(calc)

        def parse_cond_or(): parse_cond_binary(parse_cond_and,'or',calc_or)
        def parse_cond_and(): parse_cond_binary(parse_cond_not,'and',calc_and)

        def parse_cond_not():
            cmd = []
            if lexemes[0] == 'not':
                del lexemes[0]
                cmd.append(calc_not)
            
            parse_cond_primary()
            cmds.extend(cmd)
        
        def parse_cond_primary():
            if lexemes[0] == '(':
                del lexemes[0]
                parse_cond_or()
                if lexemes[0] != ')': raise Exception('parse_cond_primary: No matching ) found')
                del lexemes[0]
            else:
                arg = lexemes[0]
                def calc_primary(stack,tags): stack.append(arg in tags)
                cmds.append(calc_primary)
                del lexemes[0]
        
        if len(lexemes) > 0:
            parse_cond_or()
        else:
            cmds.append(calc_true)

        return cmds

    def calc_cond(cmds,tags):
        stack = []
        for cmd in cmds: cmd(stack,tags)
        if len(stack) != 1: raise Exception('calc_cond: Unbalanced stack')
        return stack[0]
        
    def helper(d):
        rd = d.copy()
        cond_text = rd['if'] if 'if' in rd else ''
        cond = parse_cond(lex_cond(cond_text))
        rd['cond'] = lambda tags: calc_cond(cond,tags)
        rd['cond_text'] = cond_text
        rd['auto_link'] = rd['auto_link'] if 'auto_link' in rd else 'true'
        rd['cvs'] = rd['cvs'] if 'cvs' in rd else 'git'
        dict1 = dict([(n, rd[n]) for n in ['name', 'version', 'cond', 'cond_text', 'auto_link', 'cvs']])
        return dict1

    return [Dependency(**helper(d.attrib)) for d in xml.findall('dependency')]

def filter_deps(deps,tags):
    return [dep for dep in deps if dep.cond(tags)]
