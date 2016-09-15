// Copyright (c) 2015, Rik Bellens. All rights reserved. Use of this source code
// is governed by a BSD-style license that can be found in the LICENSE file.

/// Configure and run a http server.
library shelf_serve;

import 'dart:io';
import 'package:shelf/shelf.dart' as shelf;
import 'package:logging/logging.dart';
import 'package:initialize/initialize.dart' as initialize;
import 'src/config.dart';

/// defines the [createLogRequestsMiddleware] and [createCorsMiddleware]
/// factories
import 'src/middlewares.dart';
/// defines the [createRpcHandler], [createStaticHandler], [createPubHandler],
/// [createProxyHandler] and [createCompoundHandler] factories.
import 'src/handlers.dart';
import 'dart:async';
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
serve(String pathToConfigFile, {int port: 8080, String logLevel: 'INFO'}) async {
  Logger.root.level = Level.LEVELS.firstWhere((l)=>l.name==logLevel, orElse: ()=>Level.INFO);
  Logger.root.onRecord.listen(print);
  var workingDir = pathToConfigFile.endsWith("shelf_serve.yaml") ?
    path.dirname(pathToConfigFile) : pathToConfigFile;
  var config = await ShelfServeConfig.load(new Directory(workingDir));
  return config.serve(port: port);
}


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
  var workingDir = pathToConfigFile.endsWith("shelf_serve.yaml") ?
  path.dirname(pathToConfigFile) : pathToConfigFile;
  var config = await ShelfServeConfig.load(new Directory(workingDir));
  return runZoned(() {
    return config.serveInIsolate(port: port, logLevel: logLevel);
  }, zoneValues: {
    "path_to_shelf_serve": pathToShelfServe
  });
}

ShelfServeConfig get context => Zone.current["context"];

final Map<String, MiddlewareFactory> _middlewareFactories = {};

final Map<String, HandlerFactory> _handlerFactories = {};


