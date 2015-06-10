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

run(List<String> args, [dynamic config]) async {
  await initialize.run();
  Logger.root.onRecord.listen(print);

  if (config==null) config = loadConfig("shelf_serve.yaml");
  if (config is String) config = loadConfig(config);

  var parser = new ArgParser()
    ..addOption('port', abbr: 'p', defaultsTo: '8080');

  var result = parser.parse(args);

  var port = int.parse(result['port'], onError: (val) {
    stdout.writeln('Could not parse port value "\$val" into a number.');
    exit(1);
  });


  var pipeline = const shelf.Pipeline();
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

  var router = shelf_route.router();
  for (var c in config["handlers"]) {
    if (c.keys.length!=1) {
      stdout.writeln('Expected single key in handlers');
      exit(1);
    }
    var path = c.keys.single;
    var v = c[path];
    if (v is String) v = {"type": v};
    print("adding handler ${v["type"]} on path $path");
    router.add(path, null, await createHandler(path, v), exactMatch: false);

  }

  var handler = pipeline.addHandler(router.handler);

  HttpServer server = await shelf_io.serve(handler, '0.0.0.0', port);
  print('Serving on http://${server.address.host}:${server.port}');

}

loadConfig(String configFile) => loadYaml(new File(configFile).readAsStringSync());
