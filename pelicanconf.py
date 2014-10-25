#!/usr/bin/env python
# -*- coding: utf-8 -*- #
from __future__ import unicode_literals

AUTHOR = u'Chris R'
SITENAME = u'Ideas.Offby1'
SITEURL = '//ideas.offby1.net'

PATH = 'content'

TIMEZONE = 'Europe/Paris'

DEFAULT_LANG = u'en'

# Feed generation is usually not desired when developing
FEED_ALL_ATOM = None
CATEGORY_FEED_ATOM = None
TRANSLATION_FEED_ATOM = None

# Blogroll
# LINKS = (('Pelican', 'http://getpelican.com/'),
#          ('Python.org', 'http://python.org/'),
#          ('Jinja2', 'http://jinja.pocoo.org/'),
#          ('You can modify those links in your config file', '#'),)
LINKS = ()

# Social widget
SOCIAL = (('Twitter', 'https://twitter.com/offby1'),
)

DEFAULT_PAGINATION = 10

# Uncomment following line if you want document-relative URLs when developing
RELATIVE_URLS = True

PLUGIN_PATHS = ['../pelican-plugins']
PLUGINS = ['assets', 'pelican_gist']

ARTICLE_URL = 'posts/{slug}.html'
ARTICLE_SAVE_AS = 'posts/{slug}.html'

THEME = 'monospace'

FLICKR_API_KEY = 'b6948f5853252a6c1310523f2e3b1faa'
FLICKR_USER = '11217428@N00'

THEMES_I_LIKE = ['svtble', 'simple-bootstrap', 'pelican-bootstrap3', 'monospace', 'irfan', 'blueidea', 'basic']
