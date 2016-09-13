
library shelf_serve.middlewares;

import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_cors/shelf_cors.dart' as shelf_cors;
import '../shelf_serve.dart';
import 'dart:async';

@ShelfMiddleware("log_requests")
Future<shelf.Middleware> createLogRequestsMiddleware(String type, Map config) async {
  return shelf.logRequests();
}

@ShelfMiddleware("cors")
Future<shelf.Middleware> createCorsMiddleware(String type, Map config) async {
  Map allow = config["allow"];
  return shelf_cors.createCorsHeadersMiddleware(corsHeaders: {
    "Access-Control-Allow-Origin": allow["origin"],
    "Access-Control-Allow-Headers": allow["headers"],
    "Access-Control-Allow-Methods": allow["methods"]
  });
}
