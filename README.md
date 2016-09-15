# shelf_serve

Configure and run a http server.

## Defining a http server

You define a http server by creating a `shelf_serve.yaml` file. This file lists the middleware and handlers that should
be used to handle requests. For example: 

```yaml

handlers:
  /html:
    type: compound
    handlers:
      /web:
        type: pub
        package:
          path: test_web
      /static:
        type: static
        path: test_static
  /source:
    type: proxy
    url: https://github.com/appsup-dart/shelf_serve
  /api:
    type: rpc
  /echo:
    type: echo

middlewares:
  log_requests:

dependencies:
  test_api:
    path: test_api
  test_echo:
    path: test_echo
    
```

### Adding middleware

In the middlewares section of the `shelf_serve.yaml` file, you can list the middlewares to be used and define optional
configuration parameters. 

There are two build in middlewares:

* **log_requests** logs requests to `stdout`.
* **cors** adds cors headers to the response.
 
Example: 

```yaml

middlewares:
  cors:
    allow: 
      headers: "rpc-auth, content-type"
      methods: "POST, GET, PUT, OPTIONS, DELETE"
      origin: "*"
```

### Adding handlers

In the handlers section of the `shelf_serve.yaml` file, you can list different handlers to be used for different routes.

There are five build in handlers:

* **static** serves the static files in the directory defined by the `path` parameter.
* **pub** runs pub serve on a dart package and forwards requests to it.
* **proxy** proxies requests to the server defined in the `url` parameter.
* **rpc** serves a rest api defined by the `rpc` package. 
* **compound** a compound handler that can contain other handlers and middlewares.

Note: when using the `rpc` handler, you should add the package that defines the api classes in the dependencies section.

### Defining custom handlers and middleware

You can define custom handlers and middleware by annotating a factory function that creates the handler or middleware
based on some configuration parameters. 

For example 

```dart
import 'package:shelf_serve/shelf_serve.dart';
import 'package:shelf/shelf.dart';

@ShelfHandler("echo")
createEchoHandler(String type, String route,
                      Map<String,dynamic> config) {
  return (Request r) async => new Response.ok(await r.readAsString());
}

```

You should add the package that defines those custom handlers and middlewares to the dependencies section.

## Running the server from command line

First install the `shelf_serve` executable:

```sh
pub global activate shelf_serve
```

Then goto the directory where the `shelf_serve.yaml` file is located and run:

```sh
shelf_serve serve
```

By default the server will listen to port 8080. You can define another port by:

```sh
shelf_serve serve --port 5000
```


## Running the server from code

Create a dart file and import all the necessary dependencies.

Run the method `serve`:

```dart
serve('path/to/shelf_serve.yaml', port: 5000);
```

Alternatively, you can run the method `serveInIsolate`, which will automatically do all the necessary imports based on
the dependencies section in the `shelf_serve.yaml` file.

## Creating a docker file


First install the `shelf_serve` executable:

```sh
pub global activate shelf_serve
```

Then goto the directory where the `shelf_serve.yaml` file is located and run:

```sh
shelf_serve create-docker-project
```

By default the project will be created in `build/project`. To select another output directory run:

```sh
shelf_serve create-docker-project --output-directory some/other/path
```

Next, go to the built project directory. There will be a `Dockerfile` there. 
You can create a container image by running:

```sh
docker build -t my/app .
```

And to run this image:

```sh
docker run -d -p 8080:8080 my/app
```
