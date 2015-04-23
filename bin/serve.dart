
import 'package:args/args.dart';
import 'packages:yaml/yaml.dart';
import 'dart:io';
import 'dart:isolate';

main(List<String> args) async {
  var parser = new ArgParser()
    ..addOption('config', abbr: 'c', defaultsTo: 'shelf_serve.yaml')
    ..addOption('out', abbr: 'o', defaultsTo: 'bin/server.dart')
    ..addOption('port', abbr: 'p', defaultsTo: '8080')
    ..addFlag("serve", defaultsTo: true);

  var result = parser.parse(args);

  var y = loadYaml(new File(result["config"]).readAsStringSync());

  var dependencies = {};

  var middlewares = [];
  for (var name in y["middleware"]) {
    switch (name) {
      case "log_requests":
        middlewares.add("shelf.logRequests()");
    }
  }

  print(y);
  var handlers = [];
  for (var h in y["handlers"]) {
    if (h.keys.length!=1) {
      stdout.writeln('Expected single key in handlers');
      exit(1);
    }
    var path = h.keys.single;
    var v = h[path];
    var type;
    var config = {};
    if (v is String) {
      type = v;
    } else if (v is Map) {
      type = v["type"];
      config = v;//..remove("type");
    }
    switch (type) {
      case "api":
        break;
      case "static":
        break;
    }
    handlers.add({
      "path": path,
      "handler": null
                 });
  }

  var code = """
import 'package:args/args.dart';
import 'dart:io';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_route/shelf_route.dart' as shelf_route;
import 'package:shelf/shelf_io.dart' as shelf_io;


main(List<String> args) async {
  var parser = new ArgParser()
      ..addOption('port', abbr: 'p', defaultsTo: '8080');

  var result = parser.parse(args);

  var port = int.parse(result['port'], onError: (val) {
    stdout.writeln('Could not parse port value "\$val" into a number.');
    exit(1);
  });

  var router = shelf_route.router();

  var handler = const shelf.Pipeline()
  ${middlewares.map((m)=>".addMiddleware($m)").join("\n")}
  .addHandler(router.handler);

  HttpServer server = await shelf_io.serve(handler, '0.0.0.0', port);
  print('Serving on http://\${server.address.host}:\${server.port}');



}

  """;

  new File(result["out"]).writeAsStringSync(code);

  if (result["serve"]) {
    SendPort sendPort;

    ReceivePort receivePort = new ReceivePort();
    receivePort.listen((msg) {
      if (sendPort == null) {
        sendPort = msg;
      } else {
        print('Received from isolate: $msg\n');
      }
    });
    Isolate.spawnUri(new Uri.file("server.dart"), [], receivePort.sendPort).then((isolate) {
      print('isolate spawned');

    });

/*
    Process p = await Process.start("pub",["run","server"]);
    stdout.addStream(p.stdout);
    stderr.addStream(p.stderr);
*/
  }
}