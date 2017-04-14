library shelf_serve.handlers;

import '../shelf_serve.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:rpc/rpc.dart' as rpc;
import 'package:shelf_rpc/shelf_rpc.dart' as shelf_rpc;
import 'package:shelf_static/shelf_static.dart' as shelf_static;
import 'package:shelf_proxy/shelf_proxy.dart' as shelf_proxy;
import 'package:logging/logging.dart';
import 'package:shelf_route/shelf_route.dart' as shelf_route;

import 'dart:mirrors';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:mime/mime.dart' as mime;
import 'package:shelf_static/src/util.dart';
import 'package:http_parser/http_parser.dart';


@ShelfHandler("rpc")
Future<shelf.Handler> createRpcHandler(String type, String route, Map config) async {
  final rpc.ApiServer _apiServer = new rpc.ApiServer(apiPrefix: route, prettyPrint: true);
  for (var lib in currentMirrorSystem().libraries.values) {
    if (lib.simpleName == const Symbol("discovery.api")) continue;
    for (var c in lib.declarations.values.where((d) => d is ClassMirror)) {
      if (c.metadata.any((m) => m.reflectee is rpc.ApiClass)) {
        _apiServer.addApi((c as ClassMirror).newInstance(const Symbol(""), []).reflectee);
      }
    }
  }
  if (config["enable_discovery_api"] != false) _apiServer.enableDiscoveryApi();
  return shelf_rpc.createRpcHandler(_apiServer);
}

@ShelfHandler("static")
Future<shelf.Handler> createStaticHandler(String type, String route, Map config) async {
  var handler = shelf_static.createStaticHandler(
      context.resolveDependency(config),
      defaultDocument: "index.html",
      serveFilesOutsidePath: true);

  return (shelf.Request request) {
    if (request.headers.containsKey("if-modified-since")) {
      var d = request.headers["if-modified-since"];
      d = d.replaceAll("UTC","GMT");
      request = request.change(
          headers: new Map.from(request.headers)..["if-modified-since"] = d
      );
    }
    return handler(request);
  };
}


int _PUB_PORT = 7777;

@ShelfHandler("pub")
Future<shelf.Handler> createPubHandler(String type, String route, Map config) async {
  var port = _PUB_PORT += 10;
  var workingDir;
  if (config.containsKey("package")) {
    if (config["package"] is String) {
      var link = new Link("${context.homeDirectory.path}/packages${Platform.pathSeparator}${config["package"]}");
      workingDir = new Directory(link.targetSync()).parent.path;
    } else {
      workingDir = context.resolveDependency(config["package"]);
    }
  }

  await Process.run("pub",["get"], workingDirectory: workingDir);
  Process p = await Process.start("pub", ["serve", "--port", "$port"], workingDirectory: workingDir);
  final Logger _logger = new Logger("pub-handler");
  p.stdout.transform(UTF8.decoder).transform(const LineSplitter()).listen((v) => _logger.info(v));
  p.stderr.transform(UTF8.decoder).transform(const LineSplitter()).listen((v) => _logger.warning(v));
  return shelf_proxy.proxyHandler(Uri.parse('http://localhost:$port'));
}

@ShelfHandler("proxy")
Future<shelf.Handler> createProxyHandler(String type, String path, Map config) async {
  if (config.containsKey("process")) {
    var process = config["process"];
    Process p = await Process.start(process["executable"], process["arguments"],
                          workingDirectory: process["workingDirectory"]["path"],
                          environment: process["environment"]);
    final Logger _logger = new Logger("proxy-handler");
    p.stdout.transform(UTF8.decoder).transform(const LineSplitter()).listen((v) => _logger.info(v));
    p.stderr.transform(UTF8.decoder).transform(const LineSplitter()).listen((v) => _logger.warning(v));
  }
  return shelf_proxy.proxyHandler(config["url"]);
}

@ShelfHandler("compound")
Future<shelf.Handler> createCompoundHandler(String type, String route,
    Map<String,dynamic> config) async {
  var pipeline = const shelf.Pipeline();
  if (config.containsKey("middlewares")) {
    for (var key in config["middlewares"].keys) {
      var v = config["middlewares"][key];
      var c = (v==null ? {} : new Map.from(v))..["type"] = key;
      pipeline = pipeline.addMiddleware(await createMiddleware(c["type"], c));
    }
  }

  var router = shelf_route.router();
  for (String p in config["handlers"].keys) {
    var v = config["handlers"][p];
    if (v is String) v = {"type": v};
    router.add(p, null, await createHandler(v["type"], path.join(route,p.substring(1)), v), exactMatch: false);
  }

  var handler = pipeline.addHandler(router.handler);

  return handler;
}


@ShelfHandler("file")
Future<shelf.Handler> createFileHandler(String type, String route, Map config) async {
  return (shelf.Request request) async {
    var file = new File(context.resolveDependency(config)+Platform.pathSeparator+config["fileName"]);
    var fileStat = file.statSync();
    var ifModifiedSince = request.ifModifiedSince;

    if (ifModifiedSince != null) {
      var fileChangeAtSecResolution = toSecondResolution(fileStat.changed);
      if (!fileChangeAtSecResolution.isAfter(ifModifiedSince)) {
        return new shelf.Response.notModified();
      }
    }

    var headers = <String, String>{
      HttpHeaders.CONTENT_LENGTH: fileStat.size.toString(),
      HttpHeaders.LAST_MODIFIED: formatHttpDate(fileStat.changed)
    };

    String contentType = mime.lookupMimeType(file.path);

    if (contentType != null) {
      headers[HttpHeaders.CONTENT_TYPE] = contentType;
    }

    return new shelf.Response.ok(file.openRead(), headers: headers);
  };
}
