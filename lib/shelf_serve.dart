// Copyright (c) 2015, <your name>. All rights reserved. Use of this source code
// is governed by a BSD-style license that can be found in the LICENSE file.

/// The shelf_serve library.
///
/// This is an awesome library. More dartdocs go here.
library shelf_serve;

import 'package:args/args.dart';
import 'dart:io';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_route/shelf_route.dart' as shelf_route;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:yaml/yaml.dart';
import 'package:logging/logging.dart';
import 'package:initialize/initialize.dart' as initialize;

import 'src/annotations.dart';
import 'src/middlewares.dart';
import 'src/handlers.dart';

final Map<String, MiddlewareFactory> middlewareFactories = {};

final Map<String, HandlerFactory> handlerFactories = {};

createMiddleware(Map config) => middlewareFactories[config["type"]](config);
createHandler(String path, Map config) => handlerFactories[config["type"]](path, config);

class ShelfServeConfig {

  int port = 8080;


  Map _config = {};


  Map _copyMapResolvePaths(Map v) {
    if (v==null) return null;
    Map o = new Map.from(v);
    for (var k in o.keys) {
      if (o[k] is Map) o[k] = _copyMapResolvePaths(o[k]);
      else if (k=="path") o[k] = resolvePath(o[k]);
    }
    return o;
  }

  Map get config {
    return {
      "port": port,
      "handlers": _copyMapResolvePaths(_config["handlers"]),
      "middlewares": _copyMapResolvePaths(_config["middlewares"])
    };
  }

  String homeDir;

  Map get dependencies {
    Map dependencies = _config["dependencies"];
    if (dependencies==null) dependencies = {};
    dependencies = new Map.from(dependencies);
    dependencies.putIfAbsent("shelf_serve",()=>"any");

    for (var key in dependencies.keys) {
      var d = dependencies[key];
      if (d is Map) {
        d = dependencies[key] = new Map.from(d);

        d.remove("imports");
        if (d.length==1&&d.containsKey("version")) {
          dependencies[key] = d["version"];
        }
        if (d.containsKey("path")) {
          print(d);
          d["path"] = resolvePath(d["path"]);
          print(d);
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
      ..addOption('config', abbr: 'c', defaultsTo: 'shelf_serve.yaml')
      ..addOption('out', abbr: 'o', defaultsTo: 'bin/server.dart')
      ..addOption('port', abbr: 'p', defaultsTo: '8080');

    var result = parser.parse(args);

    port = int.parse(result['port'], onError: (val) {
      throw new ArgumentError('Could not parse port value "\$val" into a number.');
    });

    _config = loadConfig(result["config"]);

    homeDir = new File(result["config"]).absolute.parent.path;
    print(homeDir);


  }

  String resolvePath(String path) => "$homeDir/$path";
}

run(List<String> args, [dynamic config]) async {
  Logger.root.onRecord.listen(print);
  await initialize.run();

  if (config==null) config = loadConfig("shelf_serve.yaml");
  if (config is String) config = loadConfig(config);

  print(config);

  var parser = new ArgParser()
    ..addOption('port', abbr: 'p', defaultsTo: '8080');

  var result = parser.parse(args);

  var port = int.parse(result['port'], onError: (val) {
    stdout.writeln('Could not parse port value "\$val" into a number.');
    exit(1);
  });

  print("parse result $result");

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
      print(c);
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

  HttpServer server = await shelf_io.serve(handler, '0.0.0.0', port);
  print('Serving on http://${server.address.host}:${server.port}');

}

loadConfig(String configFile) => loadYaml(new File(configFile).readAsStringSync());
