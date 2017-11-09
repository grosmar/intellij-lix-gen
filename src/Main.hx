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
	var ideaPath:String;
	var libPath:String;
	var moduleFile:String;
	
	static function main() 
	{
		new Main();
	}
	
	public function new()
	{
		var args = ArgParser.parse(Sys.args());
		
		ideaPath = ".idea";
		libPath = ideaPath + "/" + "libraries";
		
		if ( args.has("help") )
		{
			Sys.println("Usage: intellij-lix-gen [arguments]");
			Sys.println("--dir <WorkingDirectory>   Directory it should run in. By default, ");
			Sys.println("                           it will take the current working directiory");
			Sys.println("--module <ModuleFile>      Module file that it should add the dependencies to.");
			Sys.println("                           If not specified, will find the first one in the WorkingDirectory");
			Sys.println("--help                     Shows this command");
			Sys.exit(0);
		}
		
		if ( args.has("dir") )
			Sys.setCwd(args.get("dir").value);
		
			
		moduleFile = args.has("module") ? args.get("module").value : findFirstModule();
		
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
		
		addModules(moduleFile, libNames);
		
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
				rootComonent.addChild( Xml.parse('    <orderEntry type="library" name="${i}" level="project" />\n') );
			}
		}
		
		var result = '<?xml version="1.0" encoding="UTF-8"?>\n' + xml.toString();
		
		File.saveContent(moduleFile, result);
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
	
	function readDependencies():String
	{
		var folder = "./haxe_libraries";
		var files = FileSystem.readDirectory(folder);
		
		var p = new Process("haxe --run resolve-args build.hxml");
		
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