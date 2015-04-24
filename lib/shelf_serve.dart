// Copyright (c) 2015, <your name>. All rights reserved. Use of this source code
// is governed by a BSD-style license that can be found in the LICENSE file.

/// The shelf_serve library.
///
/// This is an awesome library. More dartdocs go here.
library shelf_serve;

import 'package:args/args.dart';
import 'dart:io';
import 'dart:mirrors';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_route/shelf_route.dart' as shelf_route;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_static/shelf_static.dart' as shelf_static;
import 'package:shelf_rpc/shelf_rpc.dart' as shelf_rpc;
import 'package:shelf_proxy/shelf_proxy.dart' as shelf_proxy;
import 'package:rpc/rpc.dart' as rpc;
import 'package:yaml/yaml.dart';
import 'package:logging/logging.dart';

typedef shelf.Middleware MiddlewareFactory(Map config);
typedef shelf.Handler HandlerFactory(Map config);

final Map<String, MiddlewareFactory> middlewareFactories = {
  "log_requests": (_) => shelf.logRequests()
};

int _PUB_PORT = 7777;

final Map<String, HandlerFactory> handlerFactories = {
  "api": (Map config) {
    const _API_PREFIX = '/api';
    final rpc.ApiServer _apiServer = new rpc.ApiServer(apiPrefix: _API_PREFIX, prettyPrint: true);
    for (var lib in currentMirrorSystem().libraries.values) {
      if (lib.simpleName==const Symbol("discovery.api")) continue;
      for (var c in lib.declarations.values.where((d)=>d is ClassMirror)) {
        if (c.metadata.any((m)=>m.reflectee is rpc.ApiClass)) {
          var s = _apiServer.addApi((c as ClassMirror).newInstance(const Symbol(""),[]).reflectee);
          print("  adding $s");
        }
      }
    }
    _apiServer.enableDiscoveryApi();
    return shelf_rpc.createRpcHandler(_apiServer);
  },
  "static": (Map config) {
    return shelf_static.createStaticHandler("web",
                                              defaultDocument: "index.html",
                                              serveFilesOutsidePath: true);
  },
  "pub": (Map config) async {
    var port = _PUB_PORT+=10;
    print("trying to serve ${config["package"]} on $port");
    var workingDir = ".";
    if (config.containsKey("package")) {
      if (config["package"] is String) {
        var link = new Link("packages${Platform.pathSeparator}${config["package"]}");
        workingDir = new Directory(link.targetSync()).parent.path;
      } else {
        workingDir = config["package"]["path"];
      }
    }
    Process p = await Process.start("pub",["serve", "--port", "$port"], workingDirectory: workingDir);
    p.stdout.listen((v)=>stdout.add(v));
    p.stderr.listen((v)=>stderr.add(v));
    return shelf_proxy.proxyHandler(Uri.parse('http://localhost:$port'));
  }
};

createMiddleware(Map config) => middlewareFactories[config["type"]](config);
createHandler(Map config) => handlerFactories[config["type"]](config);

run(List<String> args, [dynamic config]) async {
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
    print("adding middleware ${c["type"]}");
    pipeline = pipeline.addMiddleware(createMiddleware(c));
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
    router.add(path, null, await createHandler(v), exactMatch: false);

  }

  var handler = pipeline.addHandler(router.handler);

  HttpServer server = await shelf_io.serve(handler, '0.0.0.0', port);
  print('Serving on http://${server.address.host}:${server.port}');

}

loadConfig(String configFile) => loadYaml(new File(configFile).readAsStringSync());
