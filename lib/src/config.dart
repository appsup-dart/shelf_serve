
library shelf_serve.config;

import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:collection/collection.dart';
import 'package:pubspec/pubspec.dart';
import 'package:yamlicious/yamlicious.dart';
import 'package:yaml/yaml.dart';
import 'package:logging/logging.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'dart:async';
import 'dart:isolate';
import '../shelf_serve.dart';

const _currentVersion = "0.2.0";

final Logger _logger = new Logger("shelf_serve");

_link(FileSystemEntity entity, Directory destDir) {
  new Link(path.join(destDir.path, path.basename(entity.path)))
      .createSync(path.absolute(entity.path));
}

_copy(FileSystemEntity entity, Directory destDir) {
  if (entity is Directory) {
    for (FileSystemEntity entity in entity.listSync()) {
      String name = path.basename(entity.path);
      if (name.startsWith(".")) continue;
      if (path.absolute(destDir.path).startsWith(path.absolute(entity.path))) continue;

      if (entity is File) {
        _copy(entity, destDir);
      } else {
        _copy(entity, new Directory(path.join(destDir.path, name)));
      }
    }
  } else if (entity is File) {
    String name = path.basename(entity.path);
    File destFile = new File(path.join(destDir.path, name));

    if (!destFile.existsSync() ||
        entity.lastModifiedSync() != destFile.lastModifiedSync()) {
      destDir.createSync(recursive: true);
      entity.copySync(destFile.path);
    }
  } else {
    throw new StateError('unexpected type: ${entity.runtimeType}');
  }
}

class HandlerConfig {

  final String route;
  final String type;
  final Map<String,dynamic> parameters;

  HandlerConfig({this.route, this.type, this.parameters});


}

class HandlerConfigs extends DelegatingList<HandlerConfig> {

  HandlerConfigs() : super([]);
  HandlerConfigs.from(Iterable<HandlerConfig> it) : super(new List.from(it));

  factory HandlerConfigs.fromJson(Map<String,dynamic> json) {
    return new HandlerConfigs.from(json.keys.map((k)=> new HandlerConfig(
        route: k,
        type: json[k] is String ? json[k] : json[k]["type"],
        parameters: json[k] is String ? {} : new Map.from(json[k])..remove("type")
    )));
  }

  toJson() => new Map.fromIterable(this,
      key: (c)=>c.route,
      value: (c)=>new Map.from(c.parameters)..["type"] = c.type
  );

}

class MiddlewareConfig {
  final String type;
  final Map<String,dynamic> parameters;

  MiddlewareConfig({this.type, this.parameters});
}

class MiddlewareConfigs extends DelegatingList<HandlerConfig> {

  MiddlewareConfigs() : super([]);
  MiddlewareConfigs.from(Iterable<HandlerConfig> it) : super(new List.from(it));

  factory MiddlewareConfigs.fromJson(Map<String,dynamic> json) {
    return json==null ? new MiddlewareConfigs() :
    new MiddlewareConfigs.from(json.keys.map((k)=> new MiddlewareConfig(
        type: k,
        parameters: json[k]
    )));
  }

  toJson() => new Map.fromIterable(this,
      key: (c)=>c.type,
      value: (c)=>new Map.from(c.parameters ?? {})
  );

}


class ShelfServeConfig {

  final HandlerConfigs handlers;
  final MiddlewareConfigs middlewares;

  final Map<String,PathReference> resources;

  final Map<String,DependencyReference> dependencies;
  final Map<String,DependencyReference> dependencyOverrides;

  final Directory homeDirectory;

  ShelfServeConfig({this.handlers, this.middlewares, this.resources,
  this.dependencies, this.dependencyOverrides, Directory homeDirectory}) :
        homeDirectory = homeDirectory ?? Directory.current;

  factory ShelfServeConfig.fromJson(Map<String,dynamic> json, {Directory homeDirectory}) =>
      new ShelfServeConfig(
          handlers: new HandlerConfigs.fromJson(json["handlers"]),
          middlewares: new MiddlewareConfigs.fromJson(json["middlewares"]),
          resources: new Map.fromIterable(
              json["resources"]?.keys ?? [],
              value: (k) => new PathReference(json["resources"][k])
          ),
          dependencies: new Map.fromIterable(
              json["dependencies"]?.keys ?? [],
              value: (k) => new DependencyReference.fromJson(json["dependencies"][k])
          ),
          dependencyOverrides: new Map.fromIterable(
              json["dependency_overrides"]?.keys ?? [],
              value: (k) => new DependencyReference.fromJson(json["dependency_overrides"][k])
          ),
          homeDirectory: homeDirectory
      );


  static Future<ShelfServeConfig> load(Directory directory) async {
    return new ShelfServeConfig.fromJson(loadYamlNode(new File(path.join(directory.path, "shelf_serve.yaml"))
        .readAsStringSync()) as YamlMap, homeDirectory: directory);
  }

  Map<String,dynamic> toJson() => {
    "handlers": handlers.toJson(),
    "middlewares": middlewares.toJson(),
    "resources": new Map.fromIterable(resources.keys,
        value: (k)=>resources[k].path),
    "dependencies": new Map.fromIterable(dependencies.keys,
        value: (k)=>dependencies[k].toJson()),
    "dependency_overrides": new Map.fromIterable(dependencyOverrides.keys,
        value: (k)=>dependencyOverrides[k].toJson()),
  };

  ShelfServeConfig replace({
  Map<String,dynamic> handlers,
  Map<String,dynamic> middlewares,
  Map<String,PathReference> resources,
  Map<String,DependencyReference> dependencies,
  Map<String,DependencyReference> dependencyOverrides,
  Directory homeDirectory
  }) => new ShelfServeConfig(
      handlers: handlers ?? this.handlers,
      middlewares: middlewares ?? this.middlewares,
      resources: resources ?? this.resources,
      dependencies: dependencies ?? this.dependencies,
      dependencyOverrides: dependencyOverrides ?? this.dependencyOverrides,
      homeDirectory: homeDirectory ?? this.homeDirectory
  );

  ShelfServeConfig moveTo(Directory dir) => replace(
      resources: _moveReferences(resources, homeDirectory.path, dir.path),
      dependencies: _moveReferences(dependencies, homeDirectory.path, dir.path),
      dependencyOverrides: _moveReferences(dependencyOverrides, homeDirectory.path, dir.path)
  );

  static Map<String,DependencyReference> _moveReferences(Map<String,DependencyReference> map, String from, String to) =>
      new Map.fromIterables(map.keys, map.values.map((r)=>_moveReference(r,from,to)));

  static DependencyReference _moveReference(DependencyReference ref, String from, String to) {
    if (ref is! PathReference) return ref;
    return new PathReference(
        path.relative(path.absolute(path.join(from,(ref as PathReference).path)), from: to)
    );
  }

  Future serveInIsolate({int port: 8080, String logLevel: 'INFO'}) async {
    var packageDir = path.join(Directory.systemTemp.path, "shelf_serve_${homeDirectory.path.hashCode}");

    var newConfig = await writeProject(new Directory(packageDir), copy: false);
    var r = Process.runSync("pub",["get"], workingDirectory: packageDir);
    if (r.exitCode!=0) {
      _logger.finer("pub get failed");
      _logger.finer(r.stderr);
      r = Process.runSync("pub",["upgrade"], workingDirectory: packageDir);
      if (r.exitCode!=0) {
        _logger.shout("Unable to get dependencies");
        _logger.shout(r.stderr);
        throw new StateError("Could not get dependencies");
      }
    }

    var isolate = await Isolate.spawnUri(
        new Uri.file(newConfig.resolvePath("bin/server.dart")),
        ["--port","$port","--log-level",logLevel], null,
        packageRoot: new Uri.file(path.join(packageDir,"packages")));


    var receivePort = new ReceivePort();
    isolate.addErrorListener(receivePort.sendPort);
    isolate.addOnExitListener(receivePort.sendPort);
    receivePort.listen(print);

  }

  Future serve({int port: 8080}) =>
    runZoned(() async {
      var handler = await createHandler("compound","/",toJson());

      HttpServer server = await shelf_io.serve(handler, '0.0.0.0', port);
      _logger.info('Serving on http://${server.address.host}:${server.port}');

    }, zoneValues: {
      "context": this
    });

  generateDockerCode() => """
FROM google/dart-runtime-base

WORKDIR /project/app

# Add the pubspec.yaml files for each local package.
${(dependencies.values.toSet()..addAll(dependencyOverrides.values))
      .where((d)=>d is PathReference)
      .map((d)=>
  "ADD ${d.path}/pubspec.yaml /project/app/${d.path}/").join("\n")}

# Template for adding the application and local packages.
ADD pubspec.* /project/app/
RUN pub get --no-precompile
ADD . /project/app/
RUN pub get --offline --no-precompile

  """;

  resolveDependency(json) {
    if (json is Map&&json.containsKey("resource"))
      return resolvePath(resources[json["resource"]].path);
    return resolvePath(json["path"]);
  }

  String resolvePath(String p) => path.join(homeDirectory.path, p);

  PubSpec generatePubSpec(String name) => new PubSpec(
      name: name,
      dependencies: dependencies,
      dependencyOverrides: dependencyOverrides
  );


  generateScriptCode() => """
import 'package:shelf_serve/src/server_script.dart' as serve;
${dependencies.keys.map((k)=>"import 'package:$k/$k.dart';").join("\n")}

main(List<String> args) => serve.main(args);
""";


  DependencyReference get shelfServeDependency =>
      Zone.current["path_to_shelf_serve"]==null ?
      new HostedReference.fromJson(_currentVersion) :
      new PathReference(Zone.current["path_to_shelf_serve"]);


  Map<String,PathReference> _copyDependencies(Map<String,DependencyReference> dependencies, Directory dest, bool copy) {
    var updates = {};
    for (var k in dependencies.keys) {
      var dep = dependencies[k];
      if (dep is PathReference) {
        updates[k] = new PathReference(path.join(path.basename(dest.path), k));
        if (copy) {
          _copy(new Directory(path.join(homeDirectory.path,dep.path)),
              new Directory(path.join(dest.path,path.basename(dep.path))));
        } else {
          _link(new Directory(path.join(homeDirectory.path,dep.path)), dest);
        }
      }
    }
    return updates;
  }

  Future<ShelfServeConfig> writeProject(Directory outputDir, {bool copy: false}) async {
    if (outputDir.existsSync())
      outputDir.deleteSync(recursive: true);

    var binDir = new Directory(path.join(outputDir.path, "bin/"));
    binDir.createSync(recursive: true);

    new File(path.join(binDir.path, "server.dart"))
        .writeAsStringSync(generateScriptCode());

    var pkgDir = new Directory(path.join(outputDir.path, "pkg"));
    pkgDir.createSync(recursive: true);
    var dependencyOverrides =new Map.from(this.dependencyOverrides)..["shelf_serve"] = shelfServeDependency;
    var depUpdates = _copyDependencies(new Map.from(dependencies)..addAll(dependencyOverrides), pkgDir, copy);

    var resDir = new Directory(path.join(outputDir.path, "res"));
    resDir.createSync(recursive: true);
    var resUpdates = _copyDependencies(new Map.from(resources), resDir, copy);

    var newConfig = replace(
        dependencies: new Map.fromIterable(dependencies.keys,
            value: (k)=>depUpdates[k] ?? dependencies[k]),
        dependencyOverrides: new Map.fromIterable(dependencyOverrides.keys,
            value: (k)=>depUpdates[k] ?? dependencyOverrides[k]),
        resources: new Map.fromIterable(resources.keys,
            value: (k)=>resUpdates[k] ?? resources[k]),
        homeDirectory: outputDir
    );

    await newConfig.generatePubSpec(path.basename(outputDir.path)).save(outputDir);

    new File(path.join(outputDir.path,"shelf_serve.yaml")).writeAsStringSync(
        toYamlString(newConfig.toJson()));

    new File(path.join(outputDir.path,"Dockerfile")).writeAsStringSync(
        newConfig.generateDockerCode());

    return newConfig;
  }


}
