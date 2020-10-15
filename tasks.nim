import godotapigen
from sequtils import toSeq, filter, mapIt
import times
import anycase

task godot, "build the godot engine with dll unloading mod":
  var godotSrcPath = getEnv("GODOT_SRC_PATH")
  if godotSrcPath == "":
    echo "Please set GODOT_SRC_PATH env variable to godot source directory."
    quit(1)

  var curDir = getCurrentDir()
  setCurrentDir(godotSrcPath)

  # run scons --help to see godot flags
  var flags = ""
  var info = ""
  if "export" in args:
    info &= "export, "
    if "release" in args:
      flags = "tools=no target=release"
      info &= "release"
    else:
      flags = "tools=no target=debug"
      info &= "debug"
  else:
    info &= "tools, "
    if "release" in args :
      flags = "target=release_debug debug_symbols=fulcons-H vsproj=yes"
      info &= "release"
    else:
      flags = "target=debug debug_symbols=full vsproj=yes"
      info &= "debug"

  var threads = if "fast" in args: "11" else: "6"
  echo &"Compiling godot {info} threads:{threads}"
  discard execShellCmd &"scons -j{threads}  p=windows bits=64 {flags}"
  setCurrentDir(curDir)

task cleanapi, "clean generated api":
  removeDir "logs"
  removeDir "deps/godotapi"

task genapi, "generate the godot api bindings":
  let godotBin = if existsEnv "GODOT_BIN":
    getEnv "GODOT_BIN"
  else:
    echo "GODOT_BIN environment variable is not set"
    quit -1

  cleanapiTask()

  let apidir = "deps/godotapi"
  createDir apidir
  let cmd = &"{godotBin} --gdnative-generate-json-api {apidir}/api.json"
  if (execShellCmd cmd) != 0:
    echo &"Could not generate api with '{cmd}'"
    quit -1
  genApi(apidir, apidir / "api.json")


# compiling with gcc, vcc spitting out warnings about incompatible pointer types with NimGodotObj, which was added for gc:arc
# include to include libgcc_s_seh-1.dll, libwinpthread-1.dll in the app/_dlls folder for project to run
const gccDlls = @["libgcc_s_seh-1", "libwinpthread-1"]

proc checkGccDlls() =
  for dll in gccDlls:
    if not fileExists(&"app/_dlls/{dll}.dll"):
      echo "Missing app/_dlls/{dll}.dll, please copy from gcc/bin"

task cleandll, "clean the dlls, arguments are component names, default all non-gcc dlls":
  let dllDir = "app/_dlls"
  var dllPaths:seq[string]
  if args.len > 1:
    var seqDllPaths = args.mapIt(toSeq(walkFiles(&"{dllDir}/{it}*.*")))
    for paths in seqDllPaths:
      dllPaths &= paths
  else:
    dllPaths = toSeq(walkFiles(&"{dllDir}/*.*"))

  dllPaths = dllPaths.filterIt(splitFile(it)[1] notin gccDlls)

  for dllPath in dllPaths:
    echo &"rm {dllPath}"
    removeFile dllPath
  checkGccDlls()


task watcher, "build the watcher dll":
  checkGccDlls()
  execnim("--path:deps --path:deps/godot", "app/_dlls/watcher.dll", "watcher.nim")

task storage, "build the storage dll":
  checkGccDlls()
  execnim("--d:exportStorage", "app/_dlls/storage.dll", "storage.nim")


task core, "build the core":
  watcherTask()
  storageTask()

# components generator
const gdns_template = """
[gd_resource type="NativeScript" load_steps=2 format=2]

[sub_resource type="GDNativeLibrary" id=1]
entry/Windows.64 = "res://_dlls/$1.dll"
dependency/Windows.64 = [  ]

[resource]
resource_name = "$2"
class_name = "$2"
library = SubResource( 1 )
"""

# components are named {compName}_safe.dll and
# are loaded by the watcher.dll via resources. At runtime, the watcher.dll will copy
# the {compName}_safe.dll to the {compName}.dll and monitor the _dlls
# folder to see if _safe.dll is rebuilt.
task comp, "build component and generate a gdns file\n\tmove safe to hot with 'f' arg (e.g.) build comp target -- f":
  if args.len < 1:
    echo "comp needs a component name\n  .\\build comp (comp_name)"
    quit()
  let compName = args[0].snake

  let safeDllFilePath = &"app/_dlls/{compName}_safe.dll"
  let hotDllFilePath = &"app/_dlls/{compName}.dll"
  let nimFilePath = &"components/{compName}.nim"
  if not fileExists(nimFilePath):
    echo &"Error compiling {nimFilePath} [Not Found]"
    quit()

  let gdns = &"app/gdns/{compName}.gdns"
  if not fileExists(gdns):
    var gdnsContent = gdns_template % [compName, compName.pascal]
    var f = open(gdns, fmWrite)
    f.write(gdnsContent)
    f.close()
    echo &"generated {gdns}"

  execnim("--path:deps --path:deps/godot --path:.", &"{safeDllFilePath}", &"{nimFilePath}")

  if fileExists(safeDllFilePath) and getLastModificationTime(nimFilePath) < getLastModificationTime(safeDllFilePath) and
    (not fileExists(hotDllFilePath) or (args.len > 1 and args[1] == "move")):
    echo "move safe to hot"
    moveFile(safeDllFilePath, hotDllFilePath)