
part of shelf_serve;


/// An annotation class that registers a [HandlerFactory] with the name [name].
class ShelfHandler implements initialize.Initializer<HandlerFactory> {

  /// The name of the factory.
  final String name;

  const ShelfHandler(this.name);

  initialize(HandlerFactory f) {
    if (_handlerFactories.containsKey(name))
      throw new StateError("Shelf handler '$name' already registered");
    _handlerFactories[name] = f;
  }
}

/// An annotation class that registers a [MiddlewareFactory] with the name
/// [name].
class ShelfMiddleware implements initialize.Initializer<MiddlewareFactory> {

  /// The name of the factory.
  final String name;

  const ShelfMiddleware(this.name);

  initialize(MiddlewareFactory f) {
    if (_handlerFactories.containsKey(name))
      throw new StateError("Shelf middleware '$name' already registered");
    _middlewareFactories[name] = f;
  }
}