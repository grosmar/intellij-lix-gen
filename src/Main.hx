package;

import arguable.ArgParser;
import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;
import sys.io.Process;

/**
 * ...
 * @author grosmar
 */
class Main 
{
	var ideaPath:String = ".idea";
	var libPath:String = ".idea/libraries";
	var moduleFile:String;
	var buildFile:String;
	
	static function main() 
	{
		new Main();
	}
	
	public function new()
	{
		var args = ArgParser.parse(Sys.args());
		
		if ( args.has("help") )
		{
			showHelp();
			Sys.exit(0);
		}
		
		if ( args.has("dir") )
			Sys.setCwd(args.get("dir").value);
			
		moduleFile = args.has("module") ? args.get("module").value : findFirstModule();
		buildFile = args.has("build") ? args.get("build").value : findFirstBuildFile();
		
		if ( !FileSystem.exists(ideaPath) )
		{
			Sys.println("No .idea folder found. You should run it in the project .idea folder");
			Sys.exit(1);
		}
		
		if ( !FileSystem.exists(libPath) )
		{
			FileSystem.createDirectory(libPath);
		}
		
		var libs = getLibraries();
		var libNames = libs.map( function( e:{name:String} ):String return e.name );
		
		clearLibraryFiles(libNames);
		
		writeLibraries(libs);
		
		addModules(moduleFile, libNames);
		
	}
	
	function showHelp() 
	{
		Sys.println("Usage: intellij-lix-gen [arguments]");
		Sys.println("--dir <WorkingDirectory>   Directory it should run in. By default, ");
		Sys.println("                           it will take the current working directiory");
		Sys.println("--module <ModuleFile>      Module file that it should add the dependencies to.");
		Sys.println("                           If not specified, will find the first one in the WorkingDirectory");
		Sys.println("--build <BuildFile>        hxml build file that represents all the library dependencies.");
		Sys.println("                           By default it searches for build.hxml or the first available hxml");
		Sys.println("--help                     Shows this command");
	}
	
	function findFirstModule() 
	{
		var moduleFiles = FileSystem.readDirectory("./").filter( function (file:String) return Path.extension(file) == "iml" );
		
		if ( moduleFiles.length == 0 )
		{
			Sys.println("Not found default module file. Please provide one");
			Sys.exit(1);
			return null;
		}
		
		Sys.println("Default module file will be used: " + moduleFiles[0]);
		
		return moduleFiles[0];
	}
	
	function findFirstBuildFile() 
	{
		if ( FileSystem.exists("build.hxml") && !FileSystem.isDirectory("build.hxml")  )
		{
			Sys.println("Default build file will be used: build.hxml");
			return "build.hxml";
		}
		
		var buildFiles = FileSystem.readDirectory("./").filter( function (file:String) return Path.extension(file) == "hxml" );
		
		if ( buildFiles.length == 0 )
		{
			Sys.println("Not found default build file. Please provide one");
			Sys.exit(1);
			return null;
		}
		
		Sys.println("Default build file will be used: " + buildFiles[0]);
		
		return buildFiles[0];
	}
	
	function clearLibraryFiles(libNames:Array<String>) 
	{
		var files = FileSystem.readDirectory(libPath);
		
		for ( file in files )
		{
			if ( file.indexOf("lix_") == 0 )
				FileSystem.deleteFile(libPath + "/"  + file);
		}
	}
	
	function addModules(moduleFile:String, libNames:Array<String>) 
	{
		var xml = Xml.parse(File.getContent(moduleFile)).firstElement();
		
		var rootComonent:Xml = null;
		
		for ( component in xml.elementsNamed("component" ) )
		{
			if ( component.get("name") == "NewModuleRootManager" )
			{
				rootComonent = component;
				
				for ( orderEntry in component.elementsNamed("orderEntry" ) )
				{
					var entryName = orderEntry.get("name");
					if ( orderEntry.get("type") == "library" && entryName.indexOf("lix:") == 0 )
					{
						var index = libNames.indexOf(entryName.substr(4));
						if ( index > -1 )
						{
							libNames.splice(index, 1);
						}
						else
						{
							component.removeChild(orderEntry);
						}
					}
				}
			}
		}
		
		if ( rootComonent != null )
		{
			for ( i in libNames )
			{
				rootComonent.addChild( Xml.parse('    <orderEntry type="library" name="lix:${i}" level="project" />\n') );
			}
		}
		
		var result = '<?xml version="1.0" encoding="UTF-8"?>\n' + xml.toString();
		
		File.saveContent(moduleFile, result);
		
		Sys.println("Libraries added to module: " + moduleFile);
	}
	
	function getLibraries()
	{
		var out = readDependencies();
		var libs = new Array<{name:String, path:String, cleanName:String}>();
		
		var rDep = ~/-cp\n([^\n]+haxe_libraries[^\n]+)/;
		var rLibName = ~/haxe_libraries\/([^\/]+)\//;
		var rLibCleanName = ~/[^\w]/;
		var dependencies = getMatches(rDep, out, 1);
		
		for ( i in dependencies )
		{
			var path = i.split("\\").join("/");
			var name = getMatches(rLibName, path, 1)[0];
			
			var cleanName = rLibCleanName.replace(name, "_");
			libs.push({name:name, path:i, cleanName:cleanName});
		}
		
		return libs;
	}
	
	function writeLibraries(libs:Array<{name:String, path:String, cleanName:String}>) 
	{
		for ( i in libs )
		{
			var library = 
'<component name="libraryTable">
	<library name="lix:${i.name}" type="Haxe">
		<SOURCES />	
		<JAVADOC />
		<CLASSES>
			<root url="file://${i.path}" />
		</CLASSES>
	</library>
</component>';
		
			var depPath = libPath + "/" + "lix_" + i.cleanName + ".xml";
			File.saveContent(depPath, library);
			Sys.println("Saved dependenciy to: " + depPath);
		}
	}
	
	function readDependencies():String
	{
		var folder = "./haxe_libraries";
		if ( !FileSystem.exists(folder) || !FileSystem.isDirectory(folder) )
		{
			Sys.println("No 'haxe_libraries' folder found. Run the application in the root folder of lix dependencies");
			Sys.exit(1);
			return null;
		}
		
		var files = FileSystem.readDirectory(folder);
		
		var p = new Process("haxe --run resolve-args " + buildFile);
		
		var bytes = p.stdout.readAll();
		return bytes.getString(0, bytes.length);
	}
	
	function getMatches(ereg:EReg, input:String, index:Int = 0):Array<String> 
	{
		var matches = [];
		while (ereg.match(input)) 
		{
			matches.push(ereg.matched(index)); 
			input = ereg.matchedRight();
		}
		return matches;
	}

	
}