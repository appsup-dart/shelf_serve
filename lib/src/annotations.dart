
library shelf_serve.annotations;

import 'package:initialize/initialize.dart';
import '../shelf_serve.dart';
import 'dart:async';
import 'package:shelf/shelf.dart' as shelf;

typedef Future<shelf.Middleware> MiddlewareFactory(Map config);
typedef Future<shelf.Handler> HandlerFactory(String path, Map config);


class ShelfHandler implements Initializer<HandlerFactory> {

  final String name;

  const ShelfHandler({this.name});

  initialize(HandlerFactory f) {
    print("init handler $name");
    if (handlerFactories.containsKey(name))
      throw new StateError("Shelf handler '$name' already registered");
    handlerFactories[name] = f;
  }
}

class ShelfMiddleware implements Initializer<MiddlewareFactory> {

  final String name;

  const ShelfMiddleware({this.name});

  initialize(MiddlewareFactory f) {
    print("init middleware $name");
    if (handlerFactories.containsKey(name))
      throw new StateError("Shelf middleware '$name' already registered");
    middlewareFactories[name] = f;
  }
}