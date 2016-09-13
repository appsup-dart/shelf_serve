
import 'package:rpc/rpc.dart';

class Message {
  String text;
}


@ApiClass(
    name: 'test',
    version: 'v1',
    description: 'My Awesome Dart server side API' // optional
)
class TestApi {

  @ApiMethod(method: 'GET', path: 'hello')
  Message hello() => new Message()..text = "world";

}