
import 'package:shelf_serve/shelf_serve.dart';
import 'package:shelf/shelf.dart';

@ShelfHandler("echo")
createEchoHandler(a,b,c) {
  return (Request r) async => new Response.ok(await r.readAsString());
}