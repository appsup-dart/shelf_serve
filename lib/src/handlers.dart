library shelf_serve.handlers;

import 'annotations.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:rpc/rpc.dart' as rpc;
import 'package:shelf_rpc/shelf_rpc.dart' as shelf_rpc;
import 'package:shelf_static/shelf_static.dart' as shelf_static;
import 'package:shelf_proxy/shelf_proxy.dart' as shelf_proxy;

import 'dart:mirrors';
import 'dart:async';
import 'dart:io';

@ShelfHandler(name: "api")
Future<shelf.Handler> createApiHandler(String path, Map config) async {
  final rpc.ApiServer _apiServer = new rpc.ApiServer(apiPrefix: path, prettyPrint: true);
  for (var lib in currentMirrorSystem().libraries.values) {
    if (lib.simpleName == const Symbol("discovery.api")) continue;
    for (var c in lib.declarations.values.where((d) => d is ClassMirror)) {
      if (c.metadata.any((m) => m.reflectee is rpc.ApiClass)) {
        print("  adding $c");
        var s = _apiServer.addApi((c as ClassMirror).newInstance(const Symbol(""), []).reflectee);
        print("  adding $s");
      }
    }
  }
  if (config["enable_discovery_api"] != false) _apiServer.enableDiscoveryApi();
  return shelf_rpc.createRpcHandler(_apiServer);
}

@ShelfHandler(name: "static")
Future<shelf.Handler> createStaticHandler(String path, Map config) async {
  return shelf_static.createStaticHandler(config["path"],
  defaultDocument: "index.html",
  serveFilesOutsidePath: true);
}


int _PUB_PORT = 7777;

@ShelfHandler(name: "pub")
Future<shelf.Handler> createPubHandler(String path, Map config) async {
  var port = _PUB_PORT += 10;
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
  Process p = await Process.start("pub", ["serve", "--port", "$port"], workingDirectory: workingDir);
  p.stdout.listen((v) => stdout.add(v));
  p.stderr.listen((v) => stderr.add(v));
  return shelf_proxy.proxyHandler(Uri.parse('http://localhost:$port'));
}

@ShelfHandler(name: "proxy")
Future<shelf.Handler> createProxyHandler(String path, Map config) async {
  if (config.containsKey("process")) {
    var process = config["process"];
    Process p = await Process.start(process["executable"], process["arguments"],
                          workingDirectory: process["workingDirectory"],
                          environment: process["environment"]);
    p.stdout.listen((v) => stdout.add(v));
    p.stderr.listen((v) => stderr.add(v));
  }
  return shelf_proxy.proxyHandler(config["url"]);
}
