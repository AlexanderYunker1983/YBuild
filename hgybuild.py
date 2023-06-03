#!/usr/bin/env python
# -*- coding: cp1251 -*-
# Расширение для Mercurial, чтобы вытаскивать разную информацию в правильном формате без лишней ботвы

from mercurial.i18n import _
from mercurial.node import hex
from mercurial import hg, util

def yrev(ui,repo,source=None):
    if not repo and not source:
        raise util.Abort(_("There is no Mercurial repository here (.hg not found)"))

    if source:
        source, branches = hg.parseurl(ui.expandpath(source))
        repo = hg.repository(ui,source)

    if not repo.local():
        raise util.Abort(_("hgybuild.py is unable to operate with remote repository"))

    ctx = repo[None]
    parents = ctx.parents()

    ui.write("%i\n" % parents[0].rev())

def yhash(ui,repo,source=None):
    if not repo and not source:
        raise util.Abort(_("There is no Mercurial repository here (.hg not found)"))

    if source:
        source, branches = hg.parseurl(ui.expandpath(source))
        repo = hg.repository(ui,source)
    
    if not repo.local():
        raise util.Abort(_("hgybuild.py is unable to operate with remote repository"))
    
    ctx = repo[None]
    parents = ctx.parents()
    changed = util.any(repo.status())
    output = "%s%s" % ('+'.join([hex(p.node()) for p in parents]),(changed) and '+' or '')
    
    ui.write("%s\n" % output)

def ydate(ui,repo,source=None):
    if not repo and not source:
        raise util.Abort(_("There is no Mercurial repository here (.hg not found)"))

    if source:
        source, branches = hg.parseurl(ui.expandpath(source))
        repo = hg.repository(ui,source)
    
    if not repo.local():
        raise util.Abort(_("hgybuild.py is unable to operate with remote repository"))
    
    ctx = repo[None]
    parents = ctx.parents()
    output = util.datestr(parents[0].date(),'%Y-%m-%dT%H:%M:%S%1%2')
    
    ui.write("%s\n" % output)
    
cmdtable = {
    'yhash' : (yhash, [], _('[SOURCE]')),
    'ydate' : (ydate, [], _('[SOURCE]')),
    'yrev' : (yrev, [], _('[SOURCE]')),
}
