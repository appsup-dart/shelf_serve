
import 'package:shelf_serve/shelf_serve.dart';
import 'dart:io';
import 'package:yamlicious/yamlicious.dart';

main(List<String> args) async {

  var config = new ShelfServeConfig.fromCommandLineArguments(args);

  Directory dir = new Directory("${config.homeDir}/.shelf_serve").createTempSync();
  dir.createSync(recursive: true);

  var name = dir.path.split("/").last;

  var pubspec = {
    "name": name,
    "dependencies": config.dependencies,
    "dependency_overrides": {
      "quiver": "^0.21.3"
    }
  };

  new File("${dir.path}/pubspec.yaml").writeAsStringSync(toYamlString(pubspec));

  var server = """

import 'package:shelf_serve/shelf_serve.dart' as shelf_serve;
${config.imports.map((i)=>"import 'package:$i';").join("\n")}


main(List<String> args) => shelf_serve.run(args);
""";

  new Directory("${dir.path}/bin").createSync();

  new File("${dir.path}/bin/server.dart").writeAsStringSync(server);

  new File("${dir.path}/shelf_serve.yaml").writeAsStringSync(toYamlString(config.config));

  print("server package wirtten to $dir");
  print("getting pub dependencies");
  var r = Process.runSync("pub",["get"], workingDirectory: dir.path);

  print(dir);
  stdout.writeln(r.stdout);
  stderr.writeln(r.stderr);
  if (r.exitCode!=0) {
    exit(r.exitCode);
  }

  print("starting server");
  Process p = await Process.start("dart",["bin/server.dart"], workingDirectory: dir.path);

  p.stdout.listen((d)=>stdout.add(d));
  p.stderr.listen((d)=>stderr.add(d));



}
