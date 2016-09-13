// Copyright (c) 2015, Rik Bellens. All rights reserved. Use of this source code
// is governed by a BSD-style license that can be found in the LICENSE file.

/// Configure and run a http server.
library shelf_serve;

import 'dart:io';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:yaml/yaml.dart';
import 'package:yamlicious/yamlicious.dart';
import 'package:logging/logging.dart';
import 'package:initialize/initialize.dart' as initialize;

import 'src/middlewares.dart';
import 'src/handlers.dart';
import 'dart:async';
import 'dart:isolate';
import 'package:path/path.dart' as path;

part 'src/annotations.dart';

/// A function that creates a [shelf.Middleware] of a particular [type].
///
/// Additional configuration options will be passed in the [config] map.
typedef Future<shelf.Middleware> MiddlewareFactory(String type, Map config);

/// Creates a [shelf.Middleware] of type [type].
///
/// Additional configuration options can be passed in the [config] map.
Future<shelf.Middleware> createMiddleware(String type, Map config) async {
  await initialize.run();
  if (!_middlewareFactories.containsKey(type))
    throw new ArgumentError("No middleware registered for type '$type'.");
  return _middlewareFactories[type](type, config);
}




/// A function that creates a [shelf.Handler] of a particular [type] to handle
/// requests with a path starting with [route].
///
/// Additional configuration options will be passed in the [config] map.
typedef Future<shelf.Handler> HandlerFactory(String type, String route, Map config);

/// Creates a [shelf.Handler] of type [type] to handle requests with paths
/// starting with [route].
///
/// Additional configuration options can be passed in the [config] map.
Future<shelf.Handler> createHandler(String type, String route, Map config) async {
  await initialize.run();
  if (!_handlerFactories.containsKey(type))
    throw new ArgumentError("No handler registered for type '$type'.");
  return _handlerFactories[type](type, route, config);
}

/// Starts a [HttpServer] at port [port] based on the configurations read from
/// the file at [pathToConfigFile].
///
/// Note: This will not handle dependencies defined in the config file. A script
/// that uses this function should import all the necessary dependencies.
serve(String pathToConfigFile, {int port: 8080, String logLevel: 'INFO'}) {
  Logger.root.level = Level.LEVELS.firstWhere((l)=>l.name==logLevel, orElse: ()=>Level.INFO);
  Logger.root.onRecord.listen(print);
  var workingDir = path.dirname(pathToConfigFile);
  var config = _loadConfig(pathToConfigFile);
  runZoned(() async {
    var handler = await createHandler("compound","/",config);

    HttpServer server = await shelf_io.serve(handler, '0.0.0.0', port);
    _logger.info('Serving on http://${server.address.host}:${server.port}');

  }, zoneValues: {
    "workingDirectory": workingDir
  });
}

const _currentVersion = "0.1.3";

/// Starts a [HttpServer] at port [port] based on the configurations read from
/// the file at [pathToConfigFile].
///
/// The server will run in an isolate and dependencies defined in the config
/// file will automatically be imported.
///
/// When not using the shelf_serve package from the pub repository, the path to
/// the shelf_serve package should be specified.
Future serveInIsolate(String pathToConfigFile, {int port: 8080, String pathToShelfServe, String logLevel: 'INFO'}) async {
  Logger.root.level = Level.LEVELS.firstWhere((l)=>l.name==logLevel, orElse: ()=>Level.INFO);
  Logger.root.onRecord.listen(print);

  var config = _loadConfig(pathToConfigFile);

  var workingDir = path.dirname(pathToConfigFile);

  var packageDir = path.join(Directory.systemTemp.path, "shelf_serve_${pathToConfigFile.hashCode}");

  var dependencies = {
    "shelf_serve": pathToShelfServe==null ? _currentVersion :
        pathToShelfServe.startsWith("git:") ?
    {"git": pathToShelfServe} :
    {"path": path.absolute(pathToShelfServe)}
  }..addAll(config["dependencies"] ?? const{});

  await _writePubspec(packageDir,dependencies, workingDir,
      config["dependency_overrides"] ?? const{});

  var isolate = await Isolate.spawnUri(new Uri.dataFromString("""

import 'package:shelf_serve/shelf_serve.dart' as serve;
${config["dependencies"].keys.map((k)=>"import 'package:$k/$k.dart';").join("\n")}

main() {
  serve.serve("$pathToConfigFile", port: $port, logLevel: '$logLevel');
}

    """), [], null,
      packageRoot: new Uri.file(path.join(packageDir,"packages")));


  var receivePort = new ReceivePort();
  isolate.addErrorListener(receivePort.sendPort);
  isolate.addOnExitListener(receivePort.sendPort);
  receivePort.listen(print);



}

final Map<String, MiddlewareFactory> _middlewareFactories = {};

final Map<String, HandlerFactory> _handlerFactories = {};

final Logger _logger = new Logger("shelf_serve");

_writePubspec(String dir, Map<String,dynamic> dependencies, String workingDir, Map<String,dynamic> dependencyOverrides) {
  resolve(dir) {
    return path.absolute(workingDir==null ? dir : path.join(workingDir,dir));
  }

  Map<String,dynamic> _mapDependencies(Map<String,dynamic> dependencies) =>
      new Map.fromIterables(
          dependencies.keys,
          dependencies.values.map((d)=>(d is Map&&d.containsKey("path") ?
          (new Map.from(d)..["path"] = resolve(d["path"])) : d)));

  var str = toYamlString({
    "name": path.basename(dir),
    "dependencies": _mapDependencies(dependencies),
    "dependency_overrides": _mapDependencies(dependencyOverrides)
  });
  _logger.fine("Creating package for dependencies at $dir");
  _logger.finest(str);
  new Directory(dir).createSync(recursive: true);
  new File("$dir/pubspec.yaml").writeAsStringSync(str);
  var r = Process.runSync("pub",["get"], workingDirectory: dir);
  if (r.exitCode!=0) {
    _logger.finer("pub get failed");
    _logger.finer(r.stderr);
    r = Process.runSync("pub",["upgrade"], workingDirectory: dir);
    if (r.exitCode!=0) {
      _logger.shout("Unable to get dependencies");
      _logger.shout(r.stderr);
      exit(1);
    }
  }
}

_loadConfig(String configFile) => loadYamlNode(new File(configFile).readAsStringSync());
