
import 'package:unscripted/unscripted.dart';
import 'package:shelf_serve/shelf_serve.dart' as shelf_serve;
import 'package:path/path.dart' as path;
import 'dart:io';
import 'package:shelf_serve/src/config.dart';

main(arguments) => new Script(Server).execute(arguments);


class Server {

  final String configPath;
  final String pathToShelfServe;
  final String logLevel;

  @Command(
      help: 'Manages a server',
      plugins: const [const Completion()])
  Server({
  @Option(help: 'Path to the "shelf_serve.yaml" file.') this.configPath: 'shelf_serve.yaml',
  @Option(help: 'Path to the "shelf_serve" package.') this.pathToShelfServe,
  @Option(help: 'The level of logging.', allowed: const ["ALL", "FINEST",
  "FINER", "FINE", "CONFIG", "INFO", "WARNING", "SEVERE", "SHOUT", "OFF"])
  this.logLevel: 'INFO'});

  @SubCommand(help: 'Start the server')
  serve({@Option(help: 'The port the server should listen on.') int port: 8080})
  => shelf_serve.serveInIsolate(configPath, port: port, pathToShelfServe: pathToShelfServe, logLevel: logLevel);

  @SubCommand(help: 'Creates a docker project.')
  createDockerProject(
      {@Option(help: 'The output directory') String outputDirectory: 'build/project'}) async {
    var workingDir = configPath.endsWith("shelf_serve.yaml") ?
    path.dirname(configPath) : configPath;
    var config = await ShelfServeConfig.load(new Directory(workingDir));
    await config.writeProject(new Directory(outputDirectory), copy: true);
  }
}
