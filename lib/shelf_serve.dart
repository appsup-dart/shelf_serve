// Copyright (c) 2015, <your name>. All rights reserved. Use of this source code
// is governed by a BSD-style license that can be found in the LICENSE file.

/// The shelf_serve library.
library shelf_serve;

import 'package:args/args.dart';
import 'dart:io';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_route/shelf_route.dart' as shelf_route;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:yaml/yaml.dart';
import 'package:logging/logging.dart';
import 'package:initialize/initialize.dart' as initialize;
import 'dart:mirrors';
import 'package:shelf_appengine/shelf_appengine.dart' as shelf_ae;

import 'src/annotations.dart';
import 'src/middlewares.dart';
import 'src/handlers.dart';
import 'dart:collection';
final Map<String, MiddlewareFactory> middlewareFactories = {};

final Map<String, HandlerFactory> handlerFactories = {};

createMiddleware(Map config) => middlewareFactories[config["type"]](config);
createHandler(String path, Map config) => handlerFactories[config["type"]](path, config);

class ShelfServeConfig {

  int port = 8080;

  String outDir;

  Map _config = {};

  String command;

  Map _vars = {};

  Map _copyMapResolvePaths(Map v) {
    if (v==null) return null;
    Map o = new LinkedHashMap.from(v);
    for (var k in o.keys) {
      if (o[k] is Map) o[k] = _copyMapResolvePaths(o[k]);
      else if (k=="path") o[k] = resolvePath(o[k]);
    }
    return o;

  }

  Map get config {
    return {
      "port": port,
      "vars": new Map.from(_config.containsKey("vars") ? _config["vars"] : {})..addAll(_vars),
      "handlers": _copyMapResolvePaths(_config["handlers"]),
      "middlewares": _copyMapResolvePaths(_config["middlewares"])
    };
  }

  String homeDir;

  Map get dependencies {
    Map dependencies = _config["dependencies"];
    if (dependencies==null) dependencies = {};
    print(dependencies);

    for (var key in dependencies.keys) {
      var d = dependencies[key];
      if (d is Map) {
        d = dependencies[key] = new Map.from(d);

        d.remove("imports");
        if (d.length==1&&d.containsKey("version")) {
          dependencies[key] = d["version"];
        }
        if (d.containsKey("path")) {
          d["path"] = resolvePath(d["path"]);
        }
      }
    }
    print(dependencies);

    return dependencies;
  }

  List<String> get imports {
    Map dependencies = _config["dependencies"];
    if (dependencies==null) dependencies = {};

    var imports = ["shelf_serve/shelf_serve.dart"];
    for (var key in dependencies.keys) {
      var d = dependencies[key];
      if (d is Map&&d.containsKey("imports")) {
        for (var i in d["imports"]) {
          imports.add("$key/$i.dart");
        }
      } else {
        imports.add("$key/$key.dart");
      }
    }

    return imports;
  }

  ShelfServeConfig.fromCommandLineArguments(List<String> args) {
    var parser = new ArgParser()
      ..addOption('dir', abbr: 'd', defaultsTo: '.')
      ..addOption('config-file', abbr: 'c', defaultsTo: 'shelf_serve.yaml')
      ..addOption('out', abbr: 'o', defaultsTo: r'$dir/.shelf_serve')
      ..addOption('port', abbr: 'p', defaultsTo: '8080')
      ..addOption('var', abbr: 'v', allowMultiple: true)
      ..addCommand("build")
      ..addCommand("serve")
      ..addCommand("docker-build")
      ..addCommand("docker-run");


    var result = parser.parse(args);

    port = int.parse(result['port'], onError: (val) {
      throw new ArgumentError('Could not parse port value "\$val" into a number.');
    });


    for (var v in result["var"]) {
      var key = v.substring(0,v.indexOf("=")).trim();
      var value = v.substring(v.indexOf("=")+1);
      _vars[key] = value;
    }

    print(result["var"]);

    _config = new Map.from(loadConfig(result["config-file"]));

    homeDir = "${new Directory(result["dir"]).resolveSymbolicLinksSync()}/";
    outDir = result["out"].replaceFirst(new RegExp(r"\$dir/"), homeDir);

    command = result.command.name;

    var dependencies = _config["dependencies"] = _config["dependencies"]!=null ? new Map.from(_config["dependencies"]) : {};
    if (new File.fromUri(Uri.parse(homeDir).resolve("pubspec.yaml")).existsSync()) {
      var name = loadYaml(new File.fromUri(Uri.parse(homeDir).resolve("pubspec.yaml")).readAsStringSync())["name"];
      dependencies.putIfAbsent(name, ()=>{"path": homeDir});
    }
    dependencies.putIfAbsent("shelf_serve",()=>{"path": new File.fromUri(Platform.script).parent.parent.path});
    print(dependencies);

    _addPathsFromMap(_config);
    _createPathMapping();
    print(_pathMap);
  }

  Map<String,String> _pathMap = {};

  copyExt() {
    var paths = new List.from(_pathMap.keys)..sort();
    var last;
    new Directory("$outDir/ext").createSync();
    for (var p in paths) {
      if (last==null||!p.startsWith("$last")) {
        Process.runSync("cp",["-R",p,"$outDir/${_pathMap[p]}"]);
        if (outDir.startsWith(p)) {
          new Directory("$outDir/${_pathMap[p]}${outDir.substring(p.length)}").deleteSync(recursive: true);
        }
        last = p;
      } else {
      }
    }
  }

  _addPath(String path) {
    path = new Directory(path).resolveSymbolicLinksSync();
    if (!path.endsWith("/")) path += "/";
    if (_pathMap.containsKey(path)) return;
    _pathMap[Uri.parse(homeDir).resolve(path).toFilePath()] = null;
    _addPathsFromPackage(path);
  }
  _addPathsFromMap(Map map) {
    if (map==null) return;
    if (map.containsKey("path")) {
      _addPath(map["path"]);
    }
    for (var key in map.keys) {
      var d = map[key];
      if (d is Map) {
        _addPathsFromMap(d);
      }
    }
  }
  _addPathsFromPackage(String path) {
    var f = new File.fromUri(Uri.parse(path).resolve("pubspec.yaml"));
    if (!f.existsSync()) return;
    var m = loadYaml(f.readAsStringSync());
    _addPathsFromMap(m);
  }
  _createPathMapping() {
    var paths = new List.from(_pathMap.keys)..sort();
    var last;
    int count = 0;
    for (var p in paths) {
      if (last==null||!p.startsWith("$last")) {
        _pathMap[p] = "ext/${p.substring(0,p.length-1).split("/").last}-${count++}/";
        last = p;
      } else {
        _pathMap[p] = p.replaceFirst("$last",_pathMap[last]);
      }
    }
  }

  String resolvePath(String path) {
    Directory dir = path.startsWith("/") ? new Directory(path) : new Directory("$homeDir/$path");
    String r = dir.resolveSymbolicLinksSync();
    print("resolve $r");
    return _pathMap["$r/"];
  }
}

createServerHandler(List<String> args, [dynamic config]) async {
  Logger.root.onRecord.listen(print);
  await initialize.run();

  if (config==null) config = loadConfig("shelf_serve.yaml");
  if (config is String) config = loadConfig(config);

  var vars = config.containsKey("vars") ? config["vars"] : {};
  for(var v in vars.keys) {
    List parts = v.split(".");
    var libName = parts.sublist(0,parts.length-1).join(".");

    var lib = currentMirrorSystem().findLibrary(new Symbol(libName));
    (lib.declarations.keys.forEach(print));

    var value = config["vars"][v];
    if (value is Map&&value.containsKey("path")&&value.keys.length==1)
      value = value["path"];
    lib.setField(new Symbol(parts.last), value);

  }

  var pipeline = const shelf.Pipeline();
  if (config.containsKey("middleware")) {
    for (var c in config["middleware"]) {
      if (c is String) c = {"type": c};
      else if (c.keys.length!=1) {
        stdout.writeln('Expected single key in handlers');
        exit(1);
      } else {
        var key = c.keys.single;
        c = new Map.from(c[key])..["type"] = key;
      }
      print("adding middleware ${c["type"]}");
      pipeline = pipeline.addMiddleware(await createMiddleware(c));
    }

  }

  var router = shelf_route.router();
  for (var path in config["handlers"].keys) {
    var v = config["handlers"][path];
    if (v is String) v = {"type": v};
    print("adding handler ${v["type"]} on path $path");
    router.add(path, null, await createHandler(path, v), exactMatch: false);

  }

  var handler = pipeline.addHandler(router.handler);

  return handler;
}

run(List<String> args, [dynamic config]) async {
  var handler = await createServerHandler(args, config);
  if (config==null) config = loadConfig("shelf_serve.yaml");
  if (config is String) config = loadConfig(config);
  var parser = new ArgParser()
    ..addOption('port', abbr: 'p', defaultsTo: "${config["port"]}");

  var result = parser.parse(args);

  var port = int.parse(result['port'], onError: (val) {
    stdout.writeln('Could not parse port value "\$val" into a number.');
    exit(1);
  });

  HttpServer server = await shelf_io.serve(handler, '0.0.0.0', port);
  print('Serving on http://${server.address.host}:${server.port}');

}

runOnAppEngine(List<String> args, [dynamic config]) async => shelf_ae.serve(await shelf_serve.createServerHandler(args));

loadConfig(String configFile) => loadYamlNode(new File(configFile).readAsStringSync());
