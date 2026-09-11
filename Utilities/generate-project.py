#!/usr/bin/env python3
"""Dependency-free generator of a native Xcode macOS application project."""
import hashlib
from pathlib import Path
root = Path(__file__).resolve().parent.parent
project = root/'DuoLidAnimation.xcodeproj'
project.mkdir(exist_ok=True)
def uid(s): return hashlib.sha1(s.encode()).hexdigest()[:24].upper()
def q(s): return '"'+str(s).replace('\\','\\\\').replace('"','\\"')+'"'
objects=[]
def obj(key, body): objects.append(f'{uid(key)} = {{ {body} }};')
sources=sorted(str(p.relative_to(root)) for d in ['App','LidSensor','Capture','Renderer','Overlay','Utilities'] for p in (root/d).glob('*.swift'))+['Diagnostics/SelfTest.swift','Diagnostics/RenderReference.swift']
resources=['Shaders/Shaders.metal','Config/AnimationConfig.json']
refs=[]
for path in sources+resources+['App/Info.plist','README.md']:
    kind='sourcecode.swift' if path.endswith('.swift') else 'sourcecode.metal' if path.endswith('.metal') else 'text.json' if path.endswith('.json') else 'text.plist.xml' if path.endswith('.plist') else 'net.daringfireball.markdown'
    obj('ref'+path, f'isa = PBXFileReference; lastKnownFileType = {kind}; path = {q(path)}; sourceTree = "<group>";')
    refs.append(uid('ref'+path))
    if path in sources+resources: obj('build'+path, f'isa = PBXBuildFile; fileRef = {uid("ref"+path)};')
obj('product', 'isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = DuoLidAnimation.app; sourceTree = BUILT_PRODUCTS_DIR;')
obj('products', f'isa = PBXGroup; children = ({uid("product")},); name = Products; sourceTree = "<group>";')
obj('rootgroup', f'isa = PBXGroup; children = ({",".join(refs)},{uid("products")},); sourceTree = "<group>";')
for name,isa,files in [('sources','PBXSourcesBuildPhase',sources),('resources','PBXResourcesBuildPhase',resources),('frameworks','PBXFrameworksBuildPhase',[])]:
    obj(name, f'isa = {isa}; buildActionMask = 2147483647; files = ({"".join(uid("build"+p)+"," for p in files)}); runOnlyForDeploymentPostprocessing = 0;')
for scope in ['project','target']:
    for name in ['Debug','Release']:
        settings={'MACOSX_DEPLOYMENT_TARGET':'14.0','SDKROOT':'macosx','CLANG_ENABLE_MODULES':'YES','SWIFT_VERSION':'6.0'}
        if scope=='target':
            settings.update({'PRODUCT_NAME':'DuoLidAnimation','PRODUCT_BUNDLE_IDENTIFIER':'local.duolid.animation','INFOPLIST_FILE':'App/Info.plist','GENERATE_INFOPLIST_FILE':'NO','CODE_SIGN_IDENTITY':'-','CODE_SIGN_STYLE':'Manual','ENABLE_APP_SANDBOX':'NO','ENABLE_HARDENED_RUNTIME':'NO','SWIFT_STRICT_CONCURRENCY':'complete','SWIFT_OPTIMIZATION_LEVEL':'-Onone' if name=='Debug' else '-O','LD_RUNPATH_SEARCH_PATHS':'$(inherited) @executable_path/../Frameworks'})
        obj(scope+name, f'isa = XCBuildConfiguration; buildSettings = {{ {" ".join(k+" = "+q(v)+";" for k,v in settings.items())} }}; name = {name};')
    obj(scope+'configs', f'isa = XCConfigurationList; buildConfigurations = ({uid(scope+"Debug")},{uid(scope+"Release")},); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
obj('target', f'isa = PBXNativeTarget; buildConfigurationList = {uid("targetconfigs")}; buildPhases = ({uid("sources")},{uid("frameworks")},{uid("resources")},); buildRules = (); dependencies = (); name = DuoLidAnimation; productName = DuoLidAnimation; productReference = {uid("product")}; productType = "com.apple.product-type.application";')
obj('project', f'isa = PBXProject; attributes = {{ LastSwiftUpdateCheck = 2600; LastUpgradeCheck = 2600; }}; buildConfigurationList = {uid("projectconfigs")}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en,Base,); mainGroup = {uid("rootgroup")}; productRefGroup = {uid("products")}; projectDirPath = ""; projectRoot = ""; targets = ({uid("target")},);')
(project/'project.pbxproj').write_text('// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n'+'\n'.join(objects)+f'\n}}; rootObject = {uid("project")}; }}\n')
schemes=project/'xcshareddata/xcschemes'
schemes.mkdir(parents=True,exist_ok=True)
ref=f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uid("target")}" BuildableName="DuoLidAnimation.app" BlueprintName="DuoLidAnimation" ReferencedContainer="container:DuoLidAnimation.xcodeproj"/>'
(schemes/'DuoLidAnimation.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2600" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{ref}</BuildActionEntry></BuildActionEntries></BuildAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{ref}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{ref}</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>''')
print(project)
