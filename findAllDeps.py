#! /usr/bin/python

import apt, apt_pkg, os.path, re, sys, urllib
import optparse

# constants
ops = { '<=' : lambda x: x <= 0,
        '<'  : lambda x: x < 0,
        '=' :  lambda x: x == 0,
        '>'  : lambda x: x > 0,
        '>=' : lambda x: x >= 0 }

TMP_DIR    = '/tmp/foo'
SOURCES    = TMP_DIR + '/sources.list'
PREFS      = TMP_DIR + '/preferences'
ARCHIVES   = TMP_DIR + '/archives'
STATE      = TMP_DIR + '/varlibapt'
LISTS      = STATE + '/lists'
STATUS_DIR = TMP_DIR + '/varlibdpkg'
STATUS     = STATUS_DIR + '/status'

# functions
def parseCommandLineArgs(args):
  usage = "usage: %prog [options] <package> [<package>,...]"

  parser = optparse.OptionParser(usage=usage)
  parser.add_option("-f", "--force-download", dest="forceDownload",
                    action="store_true", default=False,
                    help="Force download of all dependencies" )
  parser.add_option("-d", "--distribution", dest="distribution",
                    action="store", default="sarge",
                    help="Set target distribution" )
  
  options, args = parser.parse_args(args)
  
  if len(args) == 0:
    parser.error("Wrong number of arguments")
  else:
    pkgs = args
    
  return pkgs, options

def initializeChrootedAptFiles(distribution):
  os.system('rm -fr ' + TMP_DIR)

  os.makedirs(TMP_DIR)
  os.makedirs(ARCHIVES + '/partial')
  os.makedirs(STATE)
  os.makedirs(LISTS + '/partial')
  os.makedirs(STATUS_DIR)

  # touch status file
  open(STATUS, 'w')
  
  # create sources.list file
  open(SOURCES, 'w').write('''
deb http://http.us.debian.org/debian %s main contrib non-free
deb http://security.debian.org/ %s/updates main contrib non-free
#php5
#deb http://people.debian.org/~dexter php5 woody
# backports
deb http://www.backports.org/debian %s-backports main contrib non-free
# volatile
deb http://volatile.debian.org/debian-volatile %s/volatile main contrib non-free
# mephisto
deb http://10.0.0.105/public/%s stable main premium upstream\n''' % (distribution, distribution, distribution, distribution, distribution))

  # create preferences files
  open(PREFS, 'w').write('''
Package: *
Pin: release l=Untangle
Pin-Priority: 700
Package: *
Pin: origin volatile.debian.org
Pin-Priority: 695
Package: *
Pin: release a=%s-backports
Pin-Priority: 690
Package: *
Pin: release a=%s
Pin-Priority: 600
Package: *
Pin: origin debian.org
Pin-Priority: 550\n''' % (distribution, distribution))

def initializeChrootedApt():
  apt_pkg.InitConfig()
  apt_pkg.InitSystem()
  apt_pkg.Config.Set("Dir::Etc::sourcelist", SOURCES)
  apt_pkg.Config.Set("Dir::Etc::preferences", PREFS)
  apt_pkg.Config.Set("Dir::Cache::archives", ARCHIVES)
  apt_pkg.Config.Set("Dir::State", STATE)
  apt_pkg.Config.Set("Dir::State::Lists",  LISTS)
  apt_pkg.Config.Set("Dir::State::status", STATUS)

# this needs to be called before the classes are declared, since the static
# variables in them are initialized right away

pkgs, options = parseCommandLineArgs(sys.argv[1:])
print "Initializing chrooted apt"
initializeChrootedAptFiles(options.distribution)
initializeChrootedApt()

# classes
class Package:
  cache = apt.Cache()

  print "Updating cache..."
  cache.update()
  cache.open(apt.progress.OpProgress())

  pkgCache      = apt_pkg.GetCache()
  depcache      = apt_pkg.GetDepCache(pkgCache)

  dependsKey    = 'Depends'
  suggestsKey   = 'Suggests'
  recommendsKey = 'Recommends'

  basePackages  = ()
  
#  basePackages = ( 'libc6', 'debconf', 'libx11-6', 'xfree86-common',
#                   'debianutils', 'zlib1g', 'perl' )

  def __init__(self, name, version = None, fileName = None):
    self.name     = name
    self.version  = version
    self.fileName = fileName

  def __str__(self):
    return "%s %s" % (self.name, self.version)
      
  def __hash__(self):
    return self.name.__hash__()

  def __eq__(self, p):
    if not type(self) == type(p):
      return False
    return (self.name == p.name and self.version == p.version)

class VersionedPackage(Package):

  def __init__(self, name, version = None, fileName = None):
    Package.__init__(self, name, version, fileName)

    # FIXME
    self.isVirtual               = False
    self.foundDeps             = False
    self.foundAllDeps          = False

    if not self.version:
      try:
        self._package          = Package.cache[name]
        self._package._lookupRecord(True)
        self._record           = self._package._records.Record
        self._section          = apt_pkg.ParseSection(self._record)
        self.version           = self._section['Version']
        self.isRequired        = self._section['Priority'] == 'required'
        self.isImportant       = self._section['Priority'] == 'important'
        self.isStandard        = self._section['Priority'] == 'standard'
        self.fileName          = self._sanitizeName(self._section["Filename"])
        
        self._versionedPackage = Package.depcache.GetCandidateVer(\
          Package.pkgCache[self.name])
            
        packageFile = self._versionedPackage.FileList[0][0]
        indexFile = Package.cache._list.FindIndex(packageFile)
        self.url = indexFile.ArchiveURI(self.fileName)
      except KeyError: # FIXME
        print "ooops, couldn't find package %s" % self.name
        self.isVirtual = True

  def _sanitizeName(self, name):
    return name.replace('%3a', ':')

  def getName(self):
    return self.name

  def getVersionedPackage(self):
    return self._versionedPackage
  
  def getDependsList(self, extra = None):
    if self.foundDeps:
      return self.deps
    
    if self.isVirtual or self.isRequired or self.isImportant or self.isStandard:
      return []
    deps = self._versionedPackage.DependsList
    if Package.dependsKey in deps:
#      self.deps = [ DepPackage(self.name) ]
      self.deps = []
#      print [ p for p in deps[Package.dependsKey] ]
      intermediate = deps[Package.dependsKey]
      if extra:
        if Package.recommendsKey in deps:
          intermediate += deps[Package.recommendsKey]
        if Package.suggestsKey in deps:
          intermediate += deps[Package.suggestsKey]
        
      for p in [ p[0] for p in intermediate ]:
        name = p.TargetPkg.Name
        if not name in Package.basePackages:
          self.deps.append(DepPackage(name, p.TargetVer, p.CompType))
#      print "%s --> %s" % (self.name, [ str(p) for p in self.deps ])
    else:
      self.deps = []

    self.foundDeps = True
    return self.deps

  def _getAllDeps(self, deps = set(), extra = None):
    for p in self.getDependsList(extra):
      if not p in deps:
#        print "%s is a dep of %s" % (p, self)
        deps.add(p)
        for p1 in VersionedPackage(p.name)._getAllDeps():
          if not p1 in deps:
#            print "%s is a dep of %s" % (p, self)            
            deps.add(p1)

    return deps

  def getAllDeps(self):
    if self.isVirtual:
      return []
    if not self.foundAllDeps:
      # set extra to True to get recommends/suggest
      # FIXME: make this a CL option
      self.allDeps = self._getAllDeps(extra = None)
      self.allDeps.add(DepPackage(self.name))
#      print self.name
#      print DepPackage(self.name)
#      for p in self.allDeps:
#        print p.name
      self.foundAllDeps = True
    return self.allDeps

  def satisfies(self, depPkg):
    if not depPkg.comp:
      return True
    r = apt_pkg.VersionCompare(self.version, depPkg.version)
    result = apply( ops[depPkg.comp], (r,) )
    print "compared package %s: %s to %s -> %s" % (depPkg.name,
                                                   self.version,
                                                   depPkg.version,
                                                   result)
    return result
  
  def getURL(self):
    return self.url

  def download(self, name = None):
    if not name:
      name = os.path.basename(self.fileName)      
    print "%s --> %s" % (self.url, name)
    urllib.urlretrieve(self.url, name)

class DepPackage(Package):

  def __init__(self, name, version = None, comp = None):
    Package.__init__(self, name)
    self.version = version
    self.comp = comp

  def __str__(self):
    return "%s %s %s" % (self.name,
                         self.comp,
                         self.version)

  def __hash__(self):
    return self.__str__().__hash__()

  def __eq__(self, p):
    if not type(self) == type(p):
      return False
    elif self.name == p.name and self.comp == p.comp \
             and self.version == p.version:
      return True
    else:
      return False

class UntangleStore:

  reObj = re.compile(r'([^_]+)_([^_]+)_[^\.]+\.deb')

  def __init__(self, basedir):
    self.basedir = basedir
    self.pkgs = {}
    for root, dirs, files in os.walk(basedir):
      if root.count('/.svn'):
        continue
      for f in files:
        m = UntangleStore.reObj.match(f)
        if m:
#          print "Found in store: %s (%s)" % (m.group(1), m.group(2))
          self.pkgs[m.group(1)] = VersionedPackage(m.group(1),
                                                   m.group(2),
                                                   os.path.join(root, f))

  def add(self, pkg):
    self.pkgs[pkg.name] = pkg

  def has(self, pkg):
    return pkg.name in self.pkgs

  def getByName(self, name):
    return self.pkgs[name]

  def get(self, pkg):
    return self.pkgs[pkg.name]

  def __str__(self):
    s = ""
    for p in self.pkgs.values():
      s += "%s\n" % p
    return s[:-1]

# main
us = UntangleStore(os.path.join(sys.path[0], '../upstream_pkgs_%s' % (options.distribution)))

for arg in pkgs:
  pkg = VersionedPackage(arg)

  deps = pkg.getAllDeps()
  
  for p in deps:
    try:
      versionedPackage = VersionedPackage(p.name)
#      print "*** ", versionedPackage.name, versionedPackage.version

      if (versionedPackage.isVirtual or versionedPackage.isRequired or versionedPackage.isImportant or versionedPackage.isStandard) and not options.forceDownload:
        print "%s won't be downloaded since --force-download wasn't used." % p.name
        continue

      if not us.has(versionedPackage):
        print "Package %s is missing" % p.name
      elif us.has(versionedPackage):
        if versionedPackage.name in pkgs:
          print "Download explicitely requested"
        elif not us.get(versionedPackage).satisfies(p):
          print "Version of %s doesn't satisfy dependency (%s)" % (us.get(versionedPackage), p)
          print "Downloading new one, but you probably want to remove the older one (%s)" % us.getByName(p.name)
      else:
        continue
      
      versionedPackage.download()
      us.add(versionedPackage)

    except Exception,e:
      print p, type(p), p.name, dir(p)
      raise
#      sys.exit(1)
  #  else:
  #    print "%s is in the store and satisfies the dependency" % us.get(versionedPackage)

os.system('rm -fr ' + TMP_DIR)
