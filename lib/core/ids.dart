int _counter = 0;

/// Local unique id. Swap for server ids once an API exists.
String newId() => '${DateTime.now().microsecondsSinceEpoch}${_counter++}';
