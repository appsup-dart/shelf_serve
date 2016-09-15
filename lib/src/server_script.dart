
import '../shelf_serve.dart';
import 'package:unscripted/unscripted.dart';

main(arguments) => new Script(start).execute(arguments);

@Command(help: 'Start the server', plugins: const [const Completion()])
start(
    {@Option(help: 'The port the server should listen on.') int port: 8080,
    @Option(help: 'The level of logging.', allowed: const ["ALL", "FINEST", "FINER", "FINE", "CONFIG",
    "INFO", "WARNING", "SEVERE", "SHOUT", "OFF"]) String logLevel: 'INFO',
    @Option(help: 'Path to the "shelf_serve.yaml" file.') String configPath: 'shelf_serve.yaml'}) {
  serve(configPath, port: port, logLevel: logLevel);
}